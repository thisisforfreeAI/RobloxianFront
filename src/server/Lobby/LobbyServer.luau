--!strict
--[[
	LobbyServer: wires LobbyDirectoryService to real Roblox services. This is the only lobby file that
	calls MemoryStoreService, MessagingService and TeleportService, so it is the part that can only be
	verified in published servers (see docs/LOBBY_DIRECTORY.md, "Needs published-server testing").

	Started by init.server after MatchService; admission is gated before the match remotes appear.
	Custom state providers (see the guide):
		local LobbyServer = require(script.Lobby.LobbyServer)
		local lobby = LobbyServer.start(function()
			return { map = "Saddle", players = <seated>, capacity = 2, status = "waiting" | "inProgress" }
		end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyDirectory = require(Shared.Lobby.LobbyDirectory)
local LobbyProtocol = require(Shared.Lobby.LobbyProtocol)
local Service = require(script.Parent.LobbyDirectoryService)

local LobbyServer = {}

LobbyServer.DIRECTORY_MAP = "LobbyDirectory_v1"
LobbyServer.ACCESS_CODE_MAP = "LobbyAccessCodes_v1"
LobbyServer.TOPIC = "LobbyDirectory_v1"
local ACCESS_CODE_TTL = LobbyDirectory.MAX_LIFETIME_SEC + 3600

local directory = MemoryStoreService:GetSortedMap(LobbyServer.DIRECTORY_MAP)
local accessCodes = MemoryStoreService:GetSortedMap(LobbyServer.ACCESS_CODE_MAP)

-- Every store call is pcall'd: MemoryStore throttles and fails transiently; the service treats a
-- failure as "unavailable" and never as "gone".
local store = {
	get = function(key: string): (boolean, any)
		local ok, value = pcall(directory.GetAsync, directory, key)
		if not ok then
			warn(`[Lobby] GetAsync {key}: {value}`)
		end
		return ok, if ok then value else nil
	end,
	update = function(key: string, transform: (any) -> any, ttl: number): (boolean, any)
		local ok, value = pcall(directory.UpdateAsync, directory, key, function(old: any)
			return transform(old)
		end, ttl)
		if not ok then
			warn(`[Lobby] UpdateAsync {key}: {value}`)
		end
		return ok, if ok then value else nil
	end,
	remove = function(key: string): boolean
		local ok, err = pcall(directory.RemoveAsync, directory, key)
		if not ok then
			warn(`[Lobby] RemoveAsync {key}: {err}`)
		end
		return ok
	end,
	range = function(count: number, after: any): (boolean, any)
		local ok, items = pcall(directory.GetRangeAsync, directory, Enum.SortDirection.Ascending, count, after)
		if not ok then
			warn(`[Lobby] GetRangeAsync: {items}`)
		end
		return ok, if ok then items else nil
	end,
}

-- Reserved servers can't read their own access code, so whoever calls TeleportService:ReserveServer
-- must record it here. Call right after ReserveServer: LobbyServer.rememberAccessCode(code, privateServerId)
function LobbyServer.rememberAccessCode(accessCode: string, privateServerId: string): boolean
	local ok, err = pcall(accessCodes.SetAsync, accessCodes, privateServerId, accessCode, ACCESS_CODE_TTL)
	if not ok then
		warn(`[Lobby] could not record access code: {err}`)
	end
	return ok
end

local function serverKind(): string
	if game.PrivateServerId == "" then
		return "public"
	elseif game.PrivateServerOwnerId ~= 0 then
		return "vip" -- a player-owned private server: other servers cannot teleport anyone into it
	else
		return "reserved"
	end
end

local function lookupAccessCode(): string?
	for attempt = 1, 3 do
		local ok, code = pcall(accessCodes.GetAsync, accessCodes, game.PrivateServerId)
		if ok then
			return if type(code) == "string" then code else nil
		end
		task.wait(attempt)
	end
	return nil
end

local function teleport(player: Player, route: any, data: any): (boolean, string?)
	local options = Instance.new("TeleportOptions")
	if route.kind == "reserved" then
		options.ReservedServerAccessCode = route.accessCode
	elseif route.kind == "instance" then
		options.ServerInstanceId = route.jobId
	else
		return false, "bad route"
	end
	options:SetTeleportData(data)
	-- The client offers an explicit retry. Automatic retries share failure events and can release
	-- a newer hold after an earlier attempt fails asynchronously.
	local ok,err=pcall(TeleportService.TeleportAsync,TeleportService,route.placeId,{player},options)
	return ok,if ok then nil else tostring(err)
end

local function every(sec: number, fn: () -> any): () -> ()
	local running = true
	task.spawn(function()
		while running do
			task.wait(sec)
			if running then
				local ok, err = pcall(fn)
				if not ok then
					warn(`[Lobby] heartbeat error: {err}`)
				end
			end
		end
	end)
	return function()
		running = false
	end
end

export type Options = {
	-- Called for a player whose arrival check says admit = false. Default: kick with the reason text.
	onRefused: ((Player, { [string]: any }) -> ())?,
	-- Called after a player passes the arrival check, before anything else seats them.
	onAdmitted: ((Player, { [string]: any }) -> ())?,
}

--[[
	Starts the directory for this server: publishing, remotes, arrival checks and cleanup.
	stateFn returns LobbyDirectoryService.LocalState (map, players, capacity, status, ...) or nil.
	Returns the service (lobby.arrival(player).seat tells the match whether to seat a player).
]]
function LobbyServer.start(stateFn: () -> any, options: Options?)
	local opts: Options = options or {}
	local kind = serverKind()
	local accessCode = if kind == "reserved" then lookupAccessCode() else nil
	if kind == "reserved" and not accessCode then
		warn("[Lobby] reserved server without a recorded access code: it will not be listed")
	elseif kind == "vip" then
		warn("[Lobby] player-owned private server: not listed (other servers cannot route players here)")
	end

	local folder = Instance.new("Folder")
	folder.Name = LobbyProtocol.FOLDER
	local browse = Instance.new("RemoteFunction")
	browse.Name = LobbyProtocol.BROWSE
	browse.Parent = folder
	local join = Instance.new("RemoteFunction")
	join.Name = LobbyProtocol.JOIN
	join.Parent = folder
	local setVisibility = Instance.new("RemoteFunction")
	setVisibility.Name = LobbyProtocol.SET_VISIBILITY
	setVisibility.Parent = folder
	local notice = Instance.new("RemoteEvent")
	notice.Name = LobbyProtocol.NOTICE
	notice.Parent = folder

	local service = Service.new({
		enabled = not RunService:IsStudio(),
		isPresent = function(player) return player.Parent==Players end,
		store = store,
		now = os.time, -- UTC unix seconds; servers' clocks are NTP-synced (see the guide's checklist)
		lobbyId = game.JobId,
		placeId = game.PlaceId,
		jobId = if kind == "public" then game.JobId else nil,
		accessCode = accessCode,
		teleport = teleport,
		isFriend = function(player: Player, userId: number): boolean
			return player:IsFriendsWithAsync(userId)
		end,
		messaging = {
			publish = function(msg: any)
				MessagingService:PublishAsync(LobbyServer.TOPIC, msg)
			end,
			subscribe = function(cb: (any) -> ())
				local active=true;local connection:any=nil
				task.spawn(function()
					local ok, result = pcall(MessagingService.SubscribeAsync, MessagingService, LobbyServer.TOPIC, function(packet: any)
						if active then cb(packet.Data) end
					end)
					if ok then connection=result;if not active then connection:Disconnect() end
					else warn("[Lobby] SubscribeAsync unavailable") end
				end)
				return function() active=false;if connection then connection:Disconnect() end end
			end,
		},
		every = every,
		fireNotice = function(player: Player, payload: any)
			notice:FireClient(player, payload)
		end,
		warn = warn,
	})

	-- Arrival checks read the store, so they finish a moment after PlayerAdded. Match code that seats
	-- players (MatchService's Join handler) should wait for it: returns nil only on timeout.
	function service.waitArrival(player: Player, timeoutSec: number?): { [string]: any }?
		local deadline = os.clock() + (timeoutSec or 10)
		while player.Parent and os.clock() < deadline do
			local result = service.arrival(player)
			if result then
				return result
			end
			task.wait(0.1)
		end
		return service.arrival(player)
	end

	browse.OnServerInvoke = function(player: Player, filter: any)
		return service.browse(player, filter)
	end
	join.OnServerInvoke = function(player: Player, lobbyId: any)
		return service.join(player, lobbyId)
	end
	setVisibility.OnServerInvoke = function(player: Player, visibility: any)
		return service.setVisibility(player, visibility)
	end
	folder.Parent = ReplicatedStorage

	local connections={}
	table.insert(connections,TeleportService.TeleportInitFailed:Connect(function(player: Player, _result: Enum.TeleportResult, _message: string,_placeId:number,teleportOptions:any)
		local ok,data=pcall(function() return teleportOptions:GetTeleportData() end)
		if ok and type(data)=="table" and type(data.requestId)=="string" then service.teleportFailed(player,data.requestId) end
	end))

	local function onPlayer(player: Player)
		local result = service.arrive(player)
		if player.Parent~=Players then return end
		if result.admit then
			if opts.onAdmitted then
				opts.onAdmitted(player, result)
			end
		elseif opts.onRefused then
			opts.onRefused(player, result)
		else
			-- Kicking (not teleporting to the start place) avoids a loop if Roblox matchmaking puts the
			-- player straight back here. Pass onRefused to send them to a hub place instead.
			player:Kick(LobbyDirectory.reasonText(result.reason or "forbidden"))
		end
	end
	-- Set the local state provider before any arrival checks (even if the first write yields).
	task.spawn(service.start,stateFn)
	table.insert(connections,Players.PlayerAdded:Connect(onPlayer))
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	table.insert(connections,Players.PlayerRemoving:Connect(function(player: Player)
		service.leave(player)
	end))
	local close=service.close
	function service.close()
		for _,connection in connections do connection:Disconnect() end;table.clear(connections)
		folder:Destroy();close()
	end

	game:BindToClose(function()
		service.close()
	end)

	return service
end

return LobbyServer
