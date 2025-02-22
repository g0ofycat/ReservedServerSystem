-- // Variables

local serversFolder = game.ReplicatedStorage:WaitForChild("Servers")
local Messenger = require(game.ReplicatedStorage:WaitForChild("Messenger"))
local events = game.ReplicatedStorage:WaitForChild("Events")
local CreateServer = events:WaitForChild("CreateServer")
local TeleportService = game:GetService("TeleportService")
local PlaceId = game.PlaceId
local Players = game:GetService('Players')
local ServerInfo = Messenger.new("ServerInfo")
local MessagingService = game:GetService("MessagingService")
local JobID = game.JobId
local MemoryStoreService = game:GetService('MemoryStoreService')
local Hashmap = MemoryStoreService:GetSortedMap('PlayersInServers')
local Teleport = events:WaitForChild("Teleport")

local Config = {
    PLAYER_UPDATE_INTERVAL = 5,
    Expiration = 86400,
	SERVER_VALUE_FORMAT = "%s %d %s %s %s",
	MAX_SERVERS_TO_LOAD = 200
}

local lastUpdate = time()
local pendingUpdate = false

local serverEntries = {}

local function UpdatePlayerCount()
    local playerCount = #Players:GetPlayers()
    Hashmap:UpdateAsync(JobID, function(serverData)
        local newData = serverData or {
            Name = "Game Server",
            Desc = "Default Description",
            VCMode = false
        }
        newData.PlayerCount = playerCount
        return newData
    end, Config.Expiration)
end

local function QueuePlayerUpdate()
	if pendingUpdate then return end
	pendingUpdate = true
	lastUpdate = time()
	task.delay(Config.PLAYER_UPDATE_INTERVAL, function()
		UpdatePlayerCount()
		pendingUpdate = false
	end)
end


Players.PlayerAdded:Connect(QueuePlayerUpdate)
Players.ChildRemoved:Connect(QueuePlayerUpdate) -- // ChildRemoved Fires after PlayerRemoved, meaning that I can use #Players:GetPlayers() instead of #Players:GetPlayers() - 1	

-- // Teleport Function

local function teleportPlayer(player, placeId, reservedId)
	if not player or not placeId or not reservedId then
		warn("Invalid arguments provided to teleportPlayer.")
		return false
	end
	local success, err = pcall(function()
		TeleportService:TeleportToPrivateServer(placeId, reservedId, {player})
	end)
	
	if not success then Hashmap:RemoveAsync(reservedId) return warn("Teleport failed! Server: "..reservedId) end
	
	return success
end

-- // Server creation Function

CreateServer.OnServerEvent:Connect(function(player, Desc, Name, VCMode)
	local success, code = pcall(TeleportService.ReserveServer, TeleportService, PlaceId)

	if not success then warn("Failed to Reserve Server! "..tostring(code)) return end

	-- // Initial server data
	local setSuccess, err = pcall(function()
		Hashmap:SetAsync(code, {
			PlayerCount = 1,
			Name = Name,
			Desc = Desc,
			VCMode = VCMode
		}, Config.Expiration)
	end)

	if not setSuccess then warn("Failed to Set Server Data! "..tostring(err)) return end

	teleportPlayer(player, PlaceId, code)

	ServerInfo:PublishAsync({
		Code = code,
		Name = Name,
		Desc = Desc,
		VCMode = VCMode
	})
end)

-- // StringValue Creation for all Reserved Servers

local function createServerEntry(code, playerCount, name, desc, vcMode)
	local serverValue = Instance.new("StringValue")
	serverValue.Name = "Server: " .. code
	serverValue.Value = string.format(Config.SERVER_VALUE_FORMAT, code, playerCount, name, desc, tostring(vcMode))
	serverValue.Parent = serversFolder
	serverEntries[code] = serverValue
end

-- // Server Info Handling

ServerInfo:SubscribeAsync(function(data)
	if serverEntries[data.Code] then return end

	local success, serverData = pcall(Hashmap.GetAsync, Hashmap, data.Code)
	local playerCount = (success and serverData and serverData.PlayerCount) or 0

	if playerCount == 0 then
		serverEntries[data.Code] = nil
	else
		createServerEntry(data.Code, playerCount or 0, data.Name or "[N/A]", data.Desc or "[No Description]", tostring(data.VCMode))
	end
end)

-- // Load servers when creating new Public Servers or Reserved Servers

local function LoadReservedServers()
	local success, allServers = pcall(function()
		return Hashmap:GetRangeAsync(Enum.SortDirection.Ascending, Config.MAX_SERVERS_TO_LOAD)
	end)

	if not success then 
		warn("Failed to load reserved servers! " .. tostring(allServers))
		return 
	end

	for _, entry in ipairs(allServers) do
		(function()
			if serverEntries[entry.key] then
				return 
			end
			createServerEntry(entry.key, entry.value.PlayerCount or 0, entry.value.Name or "[N/A]", entry.value.Desc or "[No Description]", tostring(entry.value.VCMode))
		end)()
	end
end

LoadReservedServers()

task.spawn(function()
	pcall(QueuePlayerUpdate)
end)

-- // Remove Hashmap Function for Debugging

local function RemoveAllHashmaps()
	local success, allEntries = pcall(function()
		return Hashmap:GetRangeAsync(Enum.SortDirection.Ascending, Config.MAX_SERVERS_TO_LOAD)
	end)

	if not success or not allEntries or type(allEntries) ~= "table" then 
		warn("Failed to fetch entries from Hashmap. Error:", allEntries) 
		return 
	end

	serversFolder:ClearAllChildren()

	for _, entry in ipairs(allEntries) do
		local key = entry.key
		print("Attempting to remove entry with key:", key)

		local removeSuccess, removeError = pcall(function()
			Hashmap:RemoveAsync(key)
		end)

		if not removeSuccess then 
			warn("Failed to remove entry with key:", key, "Error:", removeError) 
		else
			serverEntries[key] = nil
		end
	end

	print("All hashmaps removed successfully!")
end



Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		if msg == "!remove-hashmap" then
			RemoveAllHashmaps()
		end
	end)
end)

-- // Teleport Player on Creation

Teleport.OnServerEvent:Connect(function(player, PlaceID, reservedID)
	game:GetService("TeleportService"):TeleportToPrivateServer(game.PlaceId, reservedID, {player})
end)

-- // Remove Hashmap

game:BindToClose(function()
	pcall(function()
		Hashmap:RemoveAsync(JobID)
	end)
end)
