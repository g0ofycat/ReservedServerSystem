local serversFolder = game.ReplicatedStorage:WaitForChild("Servers")
local Messenger = require(game.ReplicatedStorage:WaitForChild("Messenger"))
local events = game.ReplicatedStorage:WaitForChild("Events")
local CreateServer = events:WaitForChild("CreateServer")
local TeleportService = game:GetService("TeleportService")
local PLACE_ID = game.PlaceId
local rate = 5
local Players = game:GetService('Players')
local ms = Messenger.new("ServerList")
local si = Messenger.new("ServerInfo")
local MessagingService = game:GetService("MessagingService")
local JobID = game.JobId
local MemoryStoreService = game:GetService('MemoryStoreService')
local Hashmap = MemoryStoreService:GetSortedMap('PlayersInServers')

local Expiration = 60 * 60 * 24 * 7

local function PlayerCountChanged(ServerId) --lowkey failed at making this :c too lazy to do it bc i will have to rework the whole system
	local success, serverData = pcall(function()
		return Hashmap:GetAsync(ServerId)
	end)

	if success and serverData then
		serverData.PlayerCount = #Players:GetPlayers()
		Hashmap:SetAsync(ServerId, serverData, Expiration)
		
		local serverValue = serversFolder:FindFirstChild("Server: " .. ServerId)
		if serverValue then
			serverValue.Value = string.format(
				"%s %d %s %s %s",
				ServerId,
				serverData.PlayerCount,
				serverData.Name or "[N/A]",
				serverData.Desc or "[No Description]",
				tostring(serverData.VCMode)
			)
		end
	end
end

CreateServer.OnServerEvent:Connect(function(player, Desc, Name, VCMode)
	local success, code = pcall(function()
		return TeleportService:ReserveServer(PLACE_ID)
	end)

	if success then

		Hashmap:SetAsync(code, {
			PlayerCount = 1,
			Name = Name,
			Desc = Desc,
			VCMode = VCMode
		}, Expiration)

		si:PublishAsync({
			Code = code,
			Name = Name,
			Desc = Desc,
			VCMode = VCMode
		})

		TeleportService:TeleportToPrivateServer(PLACE_ID, code, {player}, nil, {
			Description = Desc,
			ServerName = Name,
			VCMode = VCMode
		})

	else
		warn("Failed to reserve server; code: " .. tostring(code))
	end
end)

si:SubscribeAsync(function(message)
	local data = message
	local serverValue = script.ServerName:Clone()

	local success, serverData = pcall(function()
		return Hashmap:GetAsync(data.Code)
	end)

	local playerCount = (success and serverData and serverData.PlayerCount) or 1

	serverValue.Name = "Server: " .. data.Code
	serverValue.Parent = serversFolder
	serverValue.Value = string.format(
		"%s %d %s %s %s",
		data.Code,
		playerCount,
		data.Name or "[N/A]",
		data.Desc or "[No Description]",
		tostring(data.VCMode)
	)
end)

while true do
	for _, serverValue in pairs(serversFolder:GetChildren()) do
		local serverStats = string.split(serverValue.Value, " ")
		local reservationCode = serverStats[1]
		PlayerCountChanged(reservationCode)
	end
	task.wait(rate)
end

game:BindToClose(function()
	for _, serverInfo in pairs(serversFolder:GetChildren()) do
		local serverStats = string.split(serverInfo.Value, " ")
		local serverId = serverStats[1]

		local success, err = pcall(function()
			Hashmap:RemoveAsync(serverId)
		end)
	end
end)
