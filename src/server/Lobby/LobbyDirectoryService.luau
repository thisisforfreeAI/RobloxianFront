--!strict
--[[
	LobbyDirectoryService: this server's half of the cross-server lobby directory.

	- Publishes this server's lobby to the directory every HEARTBEAT_SEC (and removes it on close).
	- Answers browse requests from players here with every live, visible lobby on any server.
	- Joins: rechecks the target's freshest record, holds a seat atomically, then teleports the player
	  to the lobby's actual server (or tells the caller it is this server).
	- Arrivals: rechecks a teleported player's permission and seat against this server's own record.

	Roblox services are injected (see RobloxLobbyBackends.luau), so tests drive this module with fakes.
	deps = {
		store: {
			get: (key) -> (ok, value?),
			update: (key, transform(old) -> new?, ttlSec) -> (ok, value?),  -- atomic; nil from transform = no write
			remove: (key) -> ok,
			range: (count, afterKey?) -> (ok, { { key, value } }?),     -- ascending by key
		},
		now: () -> number,                       -- unix seconds, the same clock on every server
		lobbyId: string,                         -- this server's key in the directory (its JobId)
		placeId: number,
		jobId: string?,                          -- set on ordinary public servers (route by JobId)
		accessCode: string?,                     -- set on reserved servers (they cannot discover their own)
		teleport: (player, route, data) -> (ok, err?),   -- may yield
		isFriend: (player, userId) -> boolean,           -- may yield; cached here
		messaging: { publish: (msg) -> (), subscribe: (cb) -> () }?,
		every: (sec, fn) -> (() -> ()),          -- repeat fn; returns stop
		fireNotice: ((player, payload) -> ())?,
		warn: ((string) -> ())?,
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyDirectory = require(Shared.Lobby.LobbyDirectory)
local LobbyProtocol = require(Shared.Lobby.LobbyProtocol)

local Service = {}

local RANGE_PAGE = 200 -- MemoryStore's GetRangeAsync maximum
local MAX_PAGES = 5 -- at most 1000 listings read per directory refresh
local CACHE_SEC = 3 -- one directory read per server per CACHE_SEC, shared by every browsing player
local FRIEND_CACHE_SEC = 120
local MAX_DEAD_REMOVALS = 5 -- stale keys deleted per refresh (MemoryStore expiry gets the rest)

export type LocalState = {
	map: string,
	players: number,
	capacity: number,
	status: string, -- "waiting" | "inProgress" | "closing"
	visibility: string?, -- default "public"; SetVisibility from the host overrides it
	name: string?,
	hostUserId: number?,
	joinInProgress: boolean?,
	expiresAt: number?,
}

function Service.new(deps: any)
	local self: any = {}
	local log = deps.warn or function(_: string) end
	local lobbyId: string? = if LobbyDirectory.validId(deps.lobbyId) then deps.lobbyId else nil
	local getState: (() -> LocalState?)? = nil
	local cycleStart: number? = nil -- when the current lobby began waiting (resets when a match ends)
	local lastStatus: string? = nil
	local visibilityOverride: string? = nil
	local closed = false
	local stopLoop: (() -> ())? = nil

	local admitted: { [number]: boolean } = {} -- userIds that passed arrival here
	local cache: { at: number, listings: { any } }? = nil
	local lastBrowse: { [any]: { at: number, response: any } } = {}
	local lastJoin: { [any]: number } = {}
	local friends: { [any]: { [number]: { at: number, value: boolean } } } = {}
	local pending: { [any]: { id: string, at: number } } = {} -- player -> teleport in flight
	local arrivals: { [any]: { [string]: any } } = {} -- player -> their arrival check here
	local lastErr: string? = nil

	self.lobbyId = lobbyId
	if not lobbyId then
		log("[Lobby] no valid lobby id (Studio has no JobId): this server will not publish a listing")
	end

	local function reply(reason: string, extra: { [string]: any }?): { [string]: any }
		local r: { [string]: any } = { ok = false, reason = reason, message = LobbyDirectory.reasonText(reason), retry = LobbyDirectory.reasonRetry(reason) }
		if extra then
			for k, v in extra do
				r[k] = v
			end
		end
		return r
	end

	local function friendOf(player: any, userId: number): boolean
		if userId == 0 then
			return false
		end
		local now = deps.now()
		local per = friends[player]
		if not per then
			per = {}
			friends[player] = per
		end
		local hit = per[userId]
		if hit and now - hit.at < FRIEND_CACHE_SEC then
			return hit.value
		end
		local ok, value = pcall(deps.isFriend, player, userId)
		local result = ok and value == true
		per[userId] = { at = now, value = result }
		return result
	end

	-- Builds a pure viewer: friendships for the hosts in `listings` are resolved (and cached) up front,
	-- because the directory's predicates must not yield.
	local function viewerFor(player: any, listings: { any }): LobbyDirectory.Viewer
		local known: { [number]: boolean } = {}
		for _, l in listings do
			if type(l) == "table" and l.visibility == "friends" and type(l.hostUserId) == "number" and l.hostUserId ~= 0 and known[l.hostUserId] == nil then
				known[l.hostUserId] = if l.hostUserId == player.UserId then true else friendOf(player, l.hostUserId)
			end
		end
		return { userId = player.UserId, isFriend = function(id: number) return known[id] == true end }
	end

	local function present(): { number }
		local ids = {}
		for id in admitted do
			table.insert(ids, id)
		end
		return ids
	end

	local function fresh(now: number): (any?, string?)
		if not lobbyId or not getState then
			return nil, "not started"
		end
		local ok, state = pcall(getState :: any)
		if not ok or type(state) ~= "table" then
			return nil, "state provider failed"
		end
		local status = if closed then "closing" else state.status
		if cycleStart == nil or (status == "waiting" and lastStatus ~= "waiting") then
			cycleStart = now
		end
		lastStatus = status
		local start = cycleStart :: number
		return LobbyDirectory.makeListing({
			lobbyId = lobbyId,
			placeId = deps.placeId,
			jobId = deps.jobId,
			accessCode = deps.accessCode,
			hostUserId = state.hostUserId,
			name = state.name,
			map = state.map,
			players = state.players,
			capacity = state.capacity,
			userIds = present(),
			status = status,
			visibility = visibilityOverride or state.visibility or "public",
			joinInProgress = state.joinInProgress,
			createdAt = start,
			-- waiting lobbies that never start are delisted; running matches use the lifetime cap
			expiresAt = state.expiresAt or (if status == "waiting" then start + LobbyDirectory.WAITING_EXPIRY_SEC else nil),
		}, now)
	end

	-- Writes (or deletes) this server's listing. Returns true when the directory reflects our state.
	function self.heartbeat(): boolean
		if closed then
			return false
		end
		local now = deps.now()
		local listing, err = fresh(now)
		if not listing then
			if err ~= "not started" and err ~= lastErr then
				log(`[Lobby] not publishing: {err}`)
			end
			lastErr = err
			return false
		end
		if listing.status == "closing" or now >= listing.expiresAt then
			return deps.store.remove(lobbyId) == true
		end
		local ok = deps.store.update(lobbyId, function(old: any)
			return LobbyDirectory.mergeHeartbeat(old, listing, now)
		end, LobbyDirectory.STORE_TTL_SEC)
		if not ok then
			log("[Lobby] heartbeat write failed")
		end
		return ok == true
	end

	-- Starts publishing. stateFn is called each heartbeat; return nil to skip a beat.
	function self.start(stateFn: () -> LocalState?)
		getState = stateFn
		self.heartbeat()
		stopLoop = deps.every(LobbyDirectory.HEARTBEAT_SEC, self.heartbeat)
	end

	-- Delists this server (BindToClose, match over, server shutting down).
	function self.close()
		if closed then
			return
		end
		closed = true
		if stopLoop then
			stopLoop()
		end
		if lobbyId then
			deps.store.remove(lobbyId)
			if deps.messaging then
				pcall(deps.messaging.publish, { t = "closed", id = lobbyId })
			end
		end
	end

	-- Other servers announce closes so our browse cache drops them before the next directory read.
	if deps.messaging then
		deps.messaging.subscribe(function(msg: any)
			if type(msg) == "table" and msg.t == "closed" and LobbyDirectory.validId(msg.id) and cache then
				local kept = {}
				for _, l in cache.listings do
					if not (type(l) == "table" and l.lobbyId == msg.id) then
						table.insert(kept, l)
					end
				end
				cache.listings = kept
			end
		end)
	end

	-- Reads the whole directory (cached for CACHE_SEC) and deletes a few dead keys it finds.
	local function readAll(now: number): (boolean, { any })
		if cache and now - cache.at < CACHE_SEC then
			return true, cache.listings
		end
		local all: { any } = {}
		local after: string? = nil
		for _ = 1, MAX_PAGES do
			local ok, items = deps.store.range(RANGE_PAGE, after)
			if not ok or type(items) ~= "table" then
				if cache then
					return true, cache.listings -- serve the last good read
				end
				return false, {}
			end
			for _, item in items do
				table.insert(all, item.value)
				after = item.key
			end
			if #items < RANGE_PAGE then
				break
			end
		end
		cache = { at = now, listings = all }
		return true, all
	end

	local function sweep(dead: { string })
		for i, id in dead do
			if i > MAX_DEAD_REMOVALS then
				break
			end
			if id ~= lobbyId then
				deps.store.remove(id)
			end
		end
		if #dead > 0 and cache then
			local gone = {}
			for _, id in dead do
				gone[id] = true
			end
			local kept = {}
			for _, l in cache.listings do
				if not (type(l) == "table" and gone[l.lobbyId]) then
					table.insert(kept, l)
				end
			end
			cache.listings = kept
		end
	end

	function self.browse(player: any, rawFilter: any): { [string]: any }
		local now = deps.now()
		local last = lastBrowse[player]
		if last and now - last.at < LobbyProtocol.BROWSE_COOLDOWN_SEC then
			return last.response
		end
		local filter = LobbyDirectory.readFilter(rawFilter)
		local ok, listings = readAll(now)
		local response
		if not ok then
			response = reply("unavailable", { refreshAfter = LobbyProtocol.REFRESH_AFTER_SEC })
		else
			local lobbies, dead = LobbyDirectory.browse(listings, viewerFor(player, listings), now, filter)
			sweep(dead)
			response = { ok = true, lobbies = lobbies, refreshAfter = LobbyProtocol.REFRESH_AFTER_SEC }
		end
		lastBrowse[player] = { at = now, response = response }
		return response
	end

	function self.join(player: any, rawLobbyId: any): { [string]: any }
		local now = deps.now()
		local id = LobbyDirectory.readLobbyId(rawLobbyId)
		if not id then
			return reply("invalid")
		end
		if lastJoin[player] and now - lastJoin[player] < LobbyProtocol.JOIN_COOLDOWN_SEC then
			return reply("busy")
		end
		lastJoin[player] = now
		local inFlight = pending[player]
		if inFlight and now - inFlight.at < LobbyDirectory.RESERVATION_SEC then
			return reply("busy") -- a teleport is under way; its seat hold lapses after RESERVATION_SEC
		end

		-- 1. Fresh read (not the browse cache), and resolve friendship outside the atomic transform.
		local okGet, current = deps.store.get(id)
		if not okGet then
			return reply("unavailable")
		end
		if current == nil then
			cache = nil
			return reply("gone")
		end
		local viewer = viewerFor(player, { current })

		-- 2. Recheck and hold a seat atomically. The transform may run more than once; it is pure.
		local outcome: any = nil
		local okUpdate = deps.store.update(id, function(old: any)
			local nextL, result = LobbyDirectory.reserve(old, viewer, now, lobbyId)
			outcome = result
			return nextL
		end, LobbyDirectory.STORE_TTL_SEC)
		if not okUpdate and outcome == nil then
			return reply("unavailable")
		end
		if type(outcome) == "string" then
			if outcome == "gone" or outcome == "stale" or outcome == "expired" or outcome == "closed" then
				cache = nil
			end
			return reply(outcome)
		end
		local route = outcome :: LobbyDirectory.Route
		if route.kind == "local" then
			return { ok = true, route = "local" }
		end
		if not okUpdate then
			return reply("unavailable") -- the seat write failed; don't teleport without a seat
		end

		-- 3. Route the player to that lobby's server. Teleport data is a hint only; the destination
		-- rechecks the reservation in the store.
		pending[player] = { id = id, at = now }
		local okTp, tpErr = deps.teleport(player, route, { lobbyId = id, from = lobbyId })
		if not okTp then
			pending[player] = nil
			deps.store.update(id, function(old: any)
				return LobbyDirectory.release(old, player.UserId)
			end, LobbyDirectory.STORE_TTL_SEC)
			log(`[Lobby] teleport to {id} failed: {tostring(tpErr)}`)
			return reply("teleportFailed")
		end
		return { ok = true, route = "teleport" }
	end

	-- TeleportService.TeleportInitFailed: give the held seat back and tell the player.
	function self.teleportFailed(player: any)
		local inFlight = pending[player]
		if not inFlight then
			return
		end
		local id = inFlight.id
		pending[player] = nil
		deps.store.update(id, function(old: any)
			return LobbyDirectory.release(old, player.UserId)
		end, LobbyDirectory.STORE_TTL_SEC)
		if deps.fireNotice then
			deps.fireNotice(player, { reason = "teleportFailed", message = LobbyDirectory.reasonText("teleportFailed"), retry = true })
		end
	end

	--[[
		Call when a player joins this server, before seating them. Returns
		{ admit, seat, reason? } (see LobbyDirectory.checkArrival). The integration decides what
		admit = false means (send back to the start place, or seat as spectator).
	]]
	function self.arrive(player: any): { [string]: any }
		local now = deps.now()
		if not lobbyId then
			admitted[player.UserId] = true
			arrivals[player] = { admit = true, seat = true }
			return arrivals[player]
		end
		local ok, own = deps.store.get(lobbyId)
		local result
		if not ok then
			result = { admit = true, seat = true } -- directory down: fail open, match seat rules apply
		else
			local viewer = viewerFor(player, { own })
			result = LobbyDirectory.checkArrival(own, viewer, now)
		end
		if result.admit then
			admitted[player.UserId] = true
		end
		arrivals[player] = result
		return result
	end

	-- The arrival check for a player here (nil until arrive ran). MatchService can read .seat to decide
	-- between a side and spectating.
	function self.arrival(player: any): { [string]: any }?
		return arrivals[player]
	end

	function self.leave(player: any)
		admitted[player.UserId] = nil
		lastBrowse[player] = nil
		lastJoin[player] = nil
		friends[player] = nil
		pending[player] = nil
		arrivals[player] = nil
	end

	-- Host-only. The change is written at once so browsers stop (or start) seeing it promptly.
	function self.setVisibility(player: any, raw: any): { [string]: any }
		if not LobbyDirectory.VISIBILITY[raw] then
			return reply("invalid")
		end
		local state = getState and getState()
		if not state or not state.hostUserId or state.hostUserId == 0 or state.hostUserId ~= player.UserId then
			return reply("forbidden")
		end
		visibilityOverride = raw
		self.heartbeat()
		return { ok = true }
	end

	function self.visibility(): string?
		return visibilityOverride
	end

	return self
end

return Service
