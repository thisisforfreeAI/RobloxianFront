--!strict
--[[
	LobbyDirectoryService: this server's half of the cross-server lobby directory.

	- Publishes this server's lobby to the directory every HEARTBEAT_SEC (and removes it on close).
	- Answers browse requests from players here with every live, visible lobby on any server.
	- Joins: rechecks the target's freshest record, holds a seat atomically, then teleports the player
	  to the lobby's actual server (or tells the caller it is this server).
	- Arrivals: rechecks a teleported player's permission and seat against this server's own record.

	Roblox services are injected (see LobbyServer.luau), so tests drive this module with fakes.
	deps = {
		store: {
			get: (key) -> (ok, value?),
			update: (key, transform(old) -> new?, ttlSec) -> (ok, value?),  -- atomic; nil from transform = no write
			remove: (key) -> ok,
			range: (count, {key, sortKey}?) -> (ok, { { key, value } }?),     -- ascending by key
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

export type LocalState = {
	map: string,
	players: number,
	userIds: {number}?, -- exactly the seated players represented by players; consumed holds leave here
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
	local stopMessages:any=nil

	local admitted: { [number]: boolean } = {} -- userIds that passed arrival here
	local cache: { at: number, listings: { any } }? = nil
	local lastBrowse: { [any]: { at: number, response: any, filter:any } } = {}
	local lastJoin: { [any]: number } = {}
	local friends: { [any]: { [number]: { at: number, value: boolean } } } = {}
	local pending: { [any]: { id: string, at: number } } = {} -- player -> teleport in flight
	local arrivals: { [any]: { [string]: any } } = {} -- player -> their arrival check here
	local lastErr: string? = nil
	local joining: {[any]:boolean}={}
	local browsing:{[any]:boolean}={}
	local reading=false
	local readAt=-math.huge

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
		if not ok then return false end -- A transient service failure is not a cached negative friendship.
		local result = ok and value == true
		per[userId] = { at = now, value = result }
		return result
	end

	-- Builds a pure viewer: friendships for the hosts in `listings` are resolved (and cached) up front,
	-- because the directory's predicates must not yield.
	local function viewerFor(player: any, listings: { any }, allHosts:boolean?): LobbyDirectory.Viewer
		local known: { [number]: boolean } = {}
		for _, l in listings do
			if type(l) == "table" and (allHosts or l.visibility == "friends") and type(l.hostUserId) == "number" and l.hostUserId ~= 0 and known[l.hostUserId] == nil then
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

	local function fresh(now: number,forArrival:boolean?): (any?, string?)
		if (not lobbyId and not forArrival) or not getState then
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
			lobbyId = lobbyId or "local",
			placeId = deps.placeId,
			jobId = deps.jobId or (if forArrival then "local" else nil),
			accessCode = deps.accessCode,
			hostUserId = state.hostUserId,
			name = state.name,
			map = state.map,
			players = state.players,
			capacity = state.capacity,
			-- Integrated matches consume holds only after their Join handshake assigns a side.
			userIds = state.userIds or present(),
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
		local removeAfter=false
		local ok = deps.store.update(lobbyId, function(old: any)
			if closed then return nil end
			local at=deps.now();local latest=fresh(at)
			if not latest then return nil end
			removeAfter=latest.status=="closing" or at>=latest.expiresAt
			if removeAfter then return nil end
			return LobbyDirectory.mergeHeartbeat(old, latest, at)
		end, LobbyDirectory.STORE_TTL_SEC)
		if closed or removeAfter then deps.store.remove(lobbyId);return false end
		if not ok then
			log("[Lobby] heartbeat write failed")
		end
		return ok == true
	end

	-- Starts publishing. stateFn is called each heartbeat; return nil to skip a beat.
	function self.start(stateFn: () -> LocalState?)
		if closed then return end
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
		if stopMessages then stopMessages();stopMessages=nil end
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
		stopMessages=deps.messaging.subscribe(function(msg: any)
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
		if reading or now-readAt<CACHE_SEC then return cache~=nil,if cache then cache.listings else {} end
		reading=true;readAt=now
		local all: { any } = {}
		local after: any = nil
		for _ = 1, MAX_PAGES do
			local ok, items = deps.store.range(RANGE_PAGE, after)
			if not ok or type(items) ~= "table" then
				reading=false
				if cache then
					return true, cache.listings -- serve the last good read
				end
				return false, {}
			end
			for _, item in items do
				table.insert(all, item.value)
				after = {key=item.key,sortKey=item.sortKey}
			end
			if #items < RANGE_PAGE then
				break
			end
		end
		reading=false;cache = { at = now, listings = all }
		return true, all
	end

	local function sweep(dead: { string })
		-- Only the owner deletes a key. A cached stale record may already have been refreshed;
		-- deleting it here would erase a live lobby. Store TTL handles abandoned records.
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

	local function browseRequest(player: any, rawFilter: any): { [string]: any }
		if deps.enabled==false then return reply("unavailable",{message="Cross-server matches are available in Roblox Player."}) end
		local now = deps.now()
		local filter = LobbyDirectory.readFilter(rawFilter)
		local last = lastBrowse[player]
		if last and now - last.at < LobbyProtocol.BROWSE_COOLDOWN_SEC then
			local same=true;for _,key in {"map","status","hasSpace","friendsOnly","limit"} do if filter[key]~=last.filter[key] then same=false end end
			if same then return last.response end
			return reply("busy",{refreshAfter=LobbyProtocol.BROWSE_COOLDOWN_SEC-(now-last.at)})
		end
		local ok, listings = readAll(now)
		local response
		if not ok then
			response = reply("unavailable", { refreshAfter = LobbyProtocol.REFRESH_AFTER_SEC })
		else
			local lobbies, dead = LobbyDirectory.browse(listings, viewerFor(player, listings,filter.friendsOnly), now, filter)
			sweep(dead)
			response = { ok = true, lobbies = lobbies, refreshAfter = LobbyProtocol.REFRESH_AFTER_SEC, currentLobbyId=lobbyId }
		end
		lastBrowse[player] = { at = now, response = response,filter=filter }
		return response
	end
	function self.browse(player:any,filter:any):any
		if browsing[player] then return reply("busy") end
		browsing[player]=true;local ok,result=pcall(browseRequest,player,filter);browsing[player]=nil
		if not ok then log("[Lobby] browse request failed");return reply("unavailable") end
		return result
	end

	local function joinRequest(player: any, rawLobbyId: any): { [string]: any }
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
			local nextL, result = LobbyDirectory.reserve(old, viewer, deps.now(), lobbyId)
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
		if type(outcome)~="table" then return reply("unavailable") end
		local route = outcome :: LobbyDirectory.Route
		if route.kind == "local" then
			return { ok = true, route = "local" }
		end
		if not okUpdate then
			return reply("unavailable") -- the seat write failed; don't teleport without a seat
		end

		-- 3. Route the player to that lobby's server. Teleport data is a hint only; the destination
		-- rechecks the reservation in the store.
		if deps.isPresent and not deps.isPresent(player) then
			deps.store.update(id,function(old) return LobbyDirectory.release(old,player.UserId) end,LobbyDirectory.STORE_TTL_SEC)
			return reply("gone")
		end
		self.serial=(self.serial or 0)+1
		local operation={id=id,at=deps.now(),requestId=tostring(player.UserId)..":"..tostring(now)..":"..tostring(self.serial)}
		pending[player] = operation
		local okTp, tpErr = deps.teleport(player, route, { lobbyId = id, from = lobbyId,requestId=operation.requestId })
		if pending[player]~=operation then return reply("teleportFailed") end
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
	function self.join(player:any,id:any):any
		if deps.enabled==false then return reply("unavailable") end
		if joining[player] then return reply("busy") end
		joining[player]=true
		local ok,result=pcall(joinRequest,player,id);joining[player]=nil
		if not ok then log("[Lobby] join request failed");return reply("unavailable") end
		return result
	end

	-- TeleportService.TeleportInitFailed: give the held seat back and tell the player.
	function self.teleportFailed(player: any,requestId:string?)
		local inFlight = pending[player]
		if not inFlight or (requestId and requestId~=inFlight.requestId) then
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
		if arrivals[player] then return arrivals[player] end
		local now = deps.now()
		local localListing=fresh(now,true)
		local result:any=nil
		if localListing then
			local viewer=viewerFor(player,{localListing})
			if lobbyId and (deps.jobId or deps.accessCode) and deps.enabled~=false then
				local ok=deps.store.update(lobbyId,function(old)
					if closed then result={admit=false,reason="closed"};return nil end
					-- Read current local seating inside every retry; no yielding in this provider.
					local latest=fresh(now,true);if not latest then result=nil;return nil end
					local merged=LobbyDirectory.mergeHeartbeat(old,latest,now)
					if not merged then result={admit=true,seat=false,reason="inProgress"};return nil end
					local nextL,verdict=LobbyDirectory.claimArrival(merged,viewer,now);result=verdict
					return nextL or merged
				end,LobbyDirectory.STORE_TTL_SEC)
				if not ok then result=nil end
			end
			-- During outages/unroutable local servers, still enforce this server's actual privacy.
			result=result or LobbyDirectory.checkArrival(localListing,viewer,now)
		else
			local ok,own=true,nil
			if lobbyId then ok,own=deps.store.get(lobbyId) end
			result=LobbyDirectory.checkArrival(if ok then own else nil,viewerFor(player,{own}),now)
		end
		if deps.isPresent and not deps.isPresent(player) then
			if lobbyId and deps.enabled~=false then deps.store.update(lobbyId,function(old) return LobbyDirectory.release(old,player.UserId) end,LobbyDirectory.STORE_TTL_SEC) end
			return {admit=false,reason="gone"}
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
		if lobbyId and deps.enabled~=false then
			deps.store.update(lobbyId,function(old) return LobbyDirectory.release(old,player.UserId) end,LobbyDirectory.STORE_TTL_SEC)
		end
	end

	-- Host-only. The change is written at once so browsers stop (or start) seeing it promptly.
	function self.setVisibility(player: any, raw: any): { [string]: any }
		if type(raw)~="string" or not LobbyDirectory.VISIBILITY[raw] then
			return reply("invalid")
		end
		local ok,state=pcall(function() return getState and getState() end)
		if not ok then return reply("unavailable") end
		if not state or not state.hostUserId or state.hostUserId == 0 or state.hostUserId ~= player.UserId then
			return reply("forbidden")
		end
		visibilityOverride = raw
		if not self.heartbeat() then return reply("unavailable") end
		return { ok = true }
	end

	function self.visibility(): string?
		return visibilityOverride
	end

	return self
end

return Service
