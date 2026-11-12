--!strict
--[[
	LobbyDirectory: pure rules for the cross-server public lobby directory.

	No Roblox services are touched here, so every rule runs offline under Lune (tests/lobby_directory.luau).
	The server adapter (src/server/Lobby/LobbyDirectoryService.luau) stores the records this module builds
	in a MemoryStore sorted map and calls these functions inside UpdateAsync transforms, so everything here
	must stay deterministic: no clocks, no randomness, no yielding. Callers pass `now` (unix seconds).

	A listing record (server-only; it holds routing secrets and member ids):
		v            schema version (SCHEMA)
		lobbyId      key in the directory
		placeId      place the lobby's server runs
		jobId        that server's JobId (routing for public servers)
		accessCode   reserved-server access code (routing for reserved servers; never sent to clients)
		hostUserId   who owns the lobby (0 = the server itself, e.g. an ordinary public server)
		name, map    display text
		players      seated players right now
		capacity     seats
		userIds      ids of everyone in the server (to consume reservations and spot double joins)
		reservations { [tostring(userId)] = expiry } seats held for players being teleported in
		status       "waiting" | "inProgress" | "closing"
		visibility   "public" | "friends" | "private"
		joinInProgress  whether a running match still takes new players
		createdAt, updatedAt, expiresAt  unix seconds

	Clients only ever see publicView(), which strips routing data and member ids.
]]

local LobbyDirectory = {}

LobbyDirectory.SCHEMA = 1
LobbyDirectory.HEARTBEAT_SEC = 15 -- how often a live server rewrites its listing
LobbyDirectory.STALE_SEC = 45 -- a listing not rewritten for this long is treated as dead
LobbyDirectory.STORE_TTL_SEC = 60 -- MemoryStore expiry on each write; deletes listings of crashed servers
LobbyDirectory.MAX_LIFETIME_SEC = 4 * 3600 -- hard cap on any listing's expiresAt
LobbyDirectory.WAITING_EXPIRY_SEC = 30 * 60 -- a lobby that waits this long without starting is delisted
LobbyDirectory.RESERVATION_SEC = 60 -- a seat held for a teleporting player
LobbyDirectory.MAX_RESERVATIONS = 16
LobbyDirectory.MAX_CAPACITY = 100 -- Roblox's own per-server ceiling for this kind of game
LobbyDirectory.MAX_NAME = 40
LobbyDirectory.MAX_MAP = 32
LobbyDirectory.MAX_ID = 64
LobbyDirectory.DEFAULT_LIMIT = 50
LobbyDirectory.MAX_LIMIT = 100

LobbyDirectory.STATUS = { waiting = true, inProgress = true, closing = true }
LobbyDirectory.VISIBILITY = { public = true, friends = true, private = true }

-- Refusal reasons a join can return. `retry` says whether a fresh browse might find a seat elsewhere.
LobbyDirectory.REASONS = {
	gone = { text = "That lobby no longer exists.", retry = true },
	stale = { text = "That lobby's server stopped responding.", retry = true },
	closed = { text = "That lobby is closing.", retry = true },
	expired = { text = "That lobby has expired.", retry = true },
	forbidden = { text = "You don't have permission to join that lobby.", retry = false },
	full = { text = "That lobby is full.", retry = true },
	inProgress = { text = "That match has already started.", retry = true },
	already = { text = "You are already in that lobby.", retry = false },
	unroutable = { text = "That lobby can't be reached right now.", retry = true },
	teleportFailed = { text = "The teleport failed. Try again.", retry = true },
	busy = { text = "Too many requests. Wait a moment.", retry = true },
	unavailable = { text = "The lobby directory is unavailable right now.", retry = true },
	invalid = { text = "Invalid request.", retry = false },
}

export type Listing = { [string]: any }
export type Viewer = {
	userId: number,
	isFriend: ((hostUserId: number) -> boolean)?, -- pure predicate; the adapter pre-resolves and caches friendships
}
export type Route =
	{ kind: "local" }
	| { kind: "instance", placeId: number, jobId: string }
	| { kind: "reserved", placeId: number, accessCode: string }

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function int(n: any, lo: number, hi: number): number?
	if not finite(n) or n % 1 ~= 0 or n < lo or n > hi then
		return nil
	end
	return n
end

-- Display text: printable, trimmed, length-capped. Never trust what another server wrote either.
local function text(s: any, max: number): string?
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("[%c]", ""):match("^%s*(.-)%s*$") :: string
	if #s == 0 then
		return nil
	end
	if #s > max then
		s = s:sub(1, max)
	end
	return s
end

-- Ids: lobby ids, job ids and access codes are GUID-like or base64-ish tokens.
function LobbyDirectory.validId(s: any): boolean
	return type(s) == "string" and #s >= 1 and #s <= LobbyDirectory.MAX_ID and s:match("^[%w%-_]+$") ~= nil
end

local function token(s: any, max: number): boolean
	return type(s) == "string" and #s >= 1 and #s <= max and s:match("^[%w%-_=+/]+$") ~= nil
end

--[[
	Builds and validates the record a server publishes about itself.
	state = { lobbyId, placeId, jobId, accessCode?, hostUserId?, name?, map, players, capacity, userIds?,
	          status, visibility, joinInProgress?, createdAt?, expiresAt? }
	Returns the record, or nil and a reason. A listing that cannot be routed to is refused.
]]
function LobbyDirectory.makeListing(state: any, now: number): (Listing?, string?)
	if type(state) ~= "table" then
		return nil, "state must be a table"
	end
	if not LobbyDirectory.validId(state.lobbyId) then
		return nil, "bad lobbyId"
	end
	local placeId = int(state.placeId, 1, 2 ^ 53)
	if not placeId then
		return nil, "bad placeId"
	end
	local jobId = if state.jobId ~= nil and LobbyDirectory.validId(state.jobId) then state.jobId else nil
	local accessCode = if state.accessCode ~= nil and token(state.accessCode, 128) then state.accessCode else nil
	if not jobId and not accessCode then
		return nil, "unroutable"
	end
	local map = text(state.map, LobbyDirectory.MAX_MAP)
	if not map then
		return nil, "bad map"
	end
	local capacity = int(state.capacity, 1, LobbyDirectory.MAX_CAPACITY)
	if not capacity then
		return nil, "bad capacity"
	end
	local players = int(state.players, 0, LobbyDirectory.MAX_CAPACITY)
	if not players then
		return nil, "bad players"
	end
	if not LobbyDirectory.STATUS[state.status] then
		return nil, "bad status"
	end
	if not LobbyDirectory.VISIBILITY[state.visibility] then
		return nil, "bad visibility"
	end
	local hostUserId = if state.hostUserId == nil then 0 else int(state.hostUserId, 0, 2 ^ 53)
	if not hostUserId then
		return nil, "bad hostUserId"
	end
	local userIds = {}
	if state.userIds ~= nil then
		if type(state.userIds) ~= "table" then
			return nil, "bad userIds"
		end
		for _, id in state.userIds do
			local u = int(id, 1, 2 ^ 53)
			if u and #userIds < LobbyDirectory.MAX_CAPACITY then
				table.insert(userIds, u)
			end
		end
		table.sort(userIds)
	end
	local createdAt = int(state.createdAt, 0, 2 ^ 40) or now
	local cap = createdAt + LobbyDirectory.MAX_LIFETIME_SEC
	local expiresAt = int(state.expiresAt, 0, 2 ^ 40) or cap
	if expiresAt > cap then
		expiresAt = cap
	end
	return {
		v = LobbyDirectory.SCHEMA,
		lobbyId = state.lobbyId,
		placeId = placeId,
		jobId = jobId,
		accessCode = accessCode,
		hostUserId = hostUserId,
		name = text(state.name, LobbyDirectory.MAX_NAME) or map,
		map = map,
		players = math.min(players, capacity),
		capacity = capacity,
		userIds = userIds,
		reservations = {},
		status = state.status,
		visibility = state.visibility,
		joinInProgress = state.joinInProgress == true,
		createdAt = createdAt,
		updatedAt = now,
		expiresAt = expiresAt,
	}, nil
end

-- A record read back from the store is untrusted: wrong schema or broken shape counts as unusable.
function LobbyDirectory.wellFormed(l: any): boolean
	return type(l) == "table"
		and l.v == LobbyDirectory.SCHEMA
		and LobbyDirectory.validId(l.lobbyId)
		and int(l.placeId, 1, 2 ^ 53) ~= nil
		and int(l.capacity, 1, LobbyDirectory.MAX_CAPACITY) ~= nil
		and int(l.players, 0, LobbyDirectory.MAX_CAPACITY) ~= nil
		and LobbyDirectory.STATUS[l.status] == true
		and LobbyDirectory.VISIBILITY[l.visibility] == true
		and finite(l.updatedAt)
		and finite(l.expiresAt)
		and type(l.map) == "string"
end

-- Why a listing should no longer be offered, or nil while it is live.
function LobbyDirectory.deadReason(l: any, now: number): string?
	if not LobbyDirectory.wellFormed(l) then
		return "gone"
	end
	if l.status == "closing" then
		return "closed"
	end
	if now >= l.expiresAt then
		return "expired"
	end
	if now - l.updatedAt > LobbyDirectory.STALE_SEC then
		return "stale"
	end
	return nil
end

-- Reservations still holding a seat: unexpired, and the player hasn't arrived yet.
function LobbyDirectory.pendingReservations(l: Listing, now: number): number
	local present = {}
	for _, id in l.userIds or {} do
		present[tostring(id)] = true
	end
	local n = 0
	for key, expiry in l.reservations or {} do
		if finite(expiry) and expiry > now and not present[key] then
			n += 1
		end
	end
	return n
end

function LobbyDirectory.openSeats(l: Listing, now: number): number
	return math.max(0, l.capacity - l.players - LobbyDirectory.pendingReservations(l, now))
end

-- Who may see (and so join from the browser) a listing. Private lobbies never appear in the directory.
function LobbyDirectory.canSee(l: Listing, viewer: Viewer): boolean
	if l.visibility == "public" then
		return true
	end
	if l.visibility == "friends" then
		if l.hostUserId == 0 then
			return false -- a friends-only lobby needs a host to be friends with
		end
		if viewer.userId == l.hostUserId then
			return true
		end
		return viewer.isFriend ~= nil and viewer.isFriend(l.hostUserId) == true
	end
	return false
end

-- What a client is told. Routing secrets (jobId, accessCode) and member ids are stripped.
function LobbyDirectory.publicView(l: Listing, now: number): { [string]: any }
	local open = LobbyDirectory.openSeats(l, now)
	return {
		lobbyId = l.lobbyId,
		name = l.name,
		map = l.map,
		players = l.players,
		capacity = l.capacity,
		openSeats = open,
		status = l.status,
		visibility = l.visibility,
		joinInProgress = l.joinInProgress,
		joinable = open > 0 and (l.status == "waiting" or l.joinInProgress),
		hostUserId = l.hostUserId,
		expiresIn = math.max(0, math.floor(l.expiresAt - now)),
		ageSec = math.max(0, math.floor(now - l.createdAt)),
	}
end

--[[
	Client browse filter, validated. Unknown keys are ignored.
	{ map: string?, status: "waiting"|"inProgress"?, hasSpace: boolean?, friendsOnly: boolean?, limit: number? }
]]
function LobbyDirectory.readFilter(raw: any): { [string]: any }
	local f: { [string]: any } = { limit = LobbyDirectory.DEFAULT_LIMIT }
	if type(raw) ~= "table" then
		return f
	end
	f.map = text(raw.map, LobbyDirectory.MAX_MAP)
	if raw.status == "waiting" or raw.status == "inProgress" then
		f.status = raw.status
	end
	f.hasSpace = raw.hasSpace == true
	f.friendsOnly = raw.friendsOnly == true
	local limit = int(raw.limit, 1, LobbyDirectory.MAX_LIMIT)
	if limit then
		f.limit = limit
	end
	return f
end

--[[
	Lists what a viewer may see: live, visible listings matching the filter, as public views, sorted
	waiting first, then fullest (lobbies that are nearly ready fill first), then newest, then by id.
	Also returns the ids of dead listings found, so the adapter can delete them.
]]
function LobbyDirectory.browse(listings: { any }, viewer: Viewer, now: number, filter: { [string]: any }?): ({ { [string]: any } }, { string })
	local f = filter or LobbyDirectory.readFilter(nil)
	local out, dead = {}, {}
	local seen = {}
	for _, l in listings do
		local why = LobbyDirectory.deadReason(l, now)
		if why then
			if type(l) == "table" and LobbyDirectory.validId(l.lobbyId) then
				table.insert(dead, l.lobbyId)
			end
			continue
		end
		if seen[l.lobbyId] or not LobbyDirectory.canSee(l, viewer) then
			continue
		end
		if f.friendsOnly and l.visibility ~= "friends" and not (viewer.isFriend and l.hostUserId ~= 0 and viewer.isFriend(l.hostUserId)) then
			continue
		end
		if f.map and l.map:lower() ~= (f.map :: string):lower() then
			continue
		end
		if f.status and l.status ~= f.status then
			continue
		end
		local view = LobbyDirectory.publicView(l, now)
		if f.hasSpace and not view.joinable then
			continue
		end
		seen[l.lobbyId] = true
		table.insert(out, view)
	end
	table.sort(out, function(a, b)
		if a.status ~= b.status then
			return a.status == "waiting"
		end
		if a.players ~= b.players then
			return a.players > b.players
		end
		if a.ageSec ~= b.ageSec then
			return a.ageSec < b.ageSec
		end
		return a.lobbyId < b.lobbyId
	end)
	local limit = f.limit or LobbyDirectory.DEFAULT_LIMIT
	while #out > limit do
		table.remove(out)
	end
	return out, dead
end

-- Where to send a player for a listing, from the server they are on now (identified by its own lobby id,
-- which is that server's JobId). Reserved servers are reached by access code: Roblox does not allow
-- TeleportAsync into them by JobId.
function LobbyDirectory.route(l: Listing, currentLobbyId: string?): (Route?, string?)
	if currentLobbyId and l.lobbyId == currentLobbyId then
		return { kind = "local" }, nil
	end
	if l.accessCode then
		return { kind = "reserved", placeId = l.placeId, accessCode = l.accessCode }, nil
	end
	if l.jobId then
		return { kind = "instance", placeId = l.placeId, jobId = l.jobId }, nil
	end
	return nil, "unroutable"
end

local function present(l: Listing, userId: number): boolean
	for _, id in l.userIds or {} do
		if id == userId then
			return true
		end
	end
	return false
end

--[[
	Rechecks everything at join time against the freshest record: still live, still visible to this
	player, not already inside, accepting players in its current status, a free seat, and routable.
	Returns ok and the route, or false and a reason key from REASONS.
	A player who already holds an unexpired reservation keeps it (retrying a failed teleport is fine).
]]
function LobbyDirectory.checkJoin(l: any, viewer: Viewer, now: number, currentLobbyId: string?): (boolean, string | Route)
	if l == nil then
		return false, "gone"
	end
	local why = LobbyDirectory.deadReason(l, now)
	if why then
		return false, why
	end
	if not LobbyDirectory.canSee(l, viewer) then
		return false, "forbidden"
	end
	if present(l, viewer.userId) then
		return false, "already"
	end
	if l.status ~= "waiting" and not l.joinInProgress then
		return false, "inProgress"
	end
	local held = l.reservations and l.reservations[tostring(viewer.userId)]
	local holds = finite(held) and held > now
	if not holds and LobbyDirectory.openSeats(l, now) <= 0 then
		return false, "full"
	end
	local route, err = LobbyDirectory.route(l, currentLobbyId)
	if not route then
		return false, err or "unroutable"
	end
	return true, route
end

-- Drops expired reservations and ones whose player has arrived. Returns a new table.
local function prune(reservations: any, userIds: { number }, now: number): { [string]: number }
	local here = {}
	for _, id in userIds do
		here[tostring(id)] = true
	end
	local out = {}
	if type(reservations) == "table" then
		for key, expiry in reservations do
			if type(key) == "string" and finite(expiry) and expiry > now and not here[key] then
				out[key] = expiry
			end
		end
	end
	return out
end

--[[
	UpdateAsync transform for joining: returns the new record holding a seat for the viewer, plus the
	route; or nil (cancel the write) and a reason. Reserving through the store's atomic update is what
	stops two servers from handing out the last seat twice.
]]
function LobbyDirectory.reserve(l: any, viewer: Viewer, now: number, currentLobbyId: string?): (Listing?, string | Route)
	local ok, result = LobbyDirectory.checkJoin(l, viewer, now, currentLobbyId)
	if not ok then
		return nil, result
	end
	local route = result :: Route
	if route.kind == "local" then
		return nil, route -- same server: nothing to hold, the caller seats the player directly
	end
	local nextL = table.clone(l)
	nextL.reservations = prune(l.reservations, l.userIds or {}, now)
	local count = 0
	for _ in nextL.reservations do
		count += 1
	end
	local key = tostring(viewer.userId)
	if nextL.reservations[key] == nil and count >= LobbyDirectory.MAX_RESERVATIONS then
		return nil, "busy"
	end
	nextL.reservations[key] = now + LobbyDirectory.RESERVATION_SEC
	return nextL, route
end

-- UpdateAsync transform to give a seat back after a failed teleport. nil = nothing to change.
function LobbyDirectory.release(l: any, userId: number): Listing?
	if type(l) ~= "table" or type(l.reservations) ~= "table" or l.reservations[tostring(userId)] == nil then
		return nil
	end
	local nextL = table.clone(l)
	nextL.reservations = table.clone(l.reservations)
	nextL.reservations[tostring(userId)] = nil
	return nextL
end

--[[
	UpdateAsync transform for the owning server's heartbeat: the fresh self-description wins (only the
	owner writes heartbeats), but seats other servers reserved are kept until they expire or the player
	shows up. A closing listing returns nil: delete it instead.
]]
function LobbyDirectory.mergeHeartbeat(old: any, fresh: Listing, now: number): Listing?
	if fresh.status == "closing" then
		return nil
	end
	local nextL = table.clone(fresh)
	if LobbyDirectory.wellFormed(old) and old.lobbyId == fresh.lobbyId then
		nextL.reservations = prune(old.reservations, fresh.userIds or {}, now)
	else
		nextL.reservations = {}
	end
	return nextL
end

--[[
	Permission recheck on the destination server when a player arrives. The listing is this server's own
	record (or nil if the directory could not be read). Returns:
		{ admit = true, seat = true }   a reserved or free seat, or the directory is down (fail open:
		                                 the match's own seat rules still apply)
		{ admit = true, seat = false, reason }  let in without a seat (e.g. as a spectator)
		{ admit = false, reason }        not permitted here (friends-only stranger, private lobby)
	Teleport data is never trusted; only the reservation in the store counts.
]]
function LobbyDirectory.checkArrival(l: any, viewer: Viewer, now: number): { [string]: any }
	if not LobbyDirectory.wellFormed(l) then
		return { admit = true, seat = true }
	end
	local held = l.reservations and l.reservations[tostring(viewer.userId)]
	if finite(held) and held > now then
		return { admit = true, seat = true }
	end
	if viewer.userId == l.hostUserId then
		return { admit = true, seat = true }
	end
	if l.visibility ~= "public" and not LobbyDirectory.canSee(l, viewer) then
		return { admit = false, reason = "forbidden" }
	end
	if l.visibility == "private" then
		return { admit = false, reason = "forbidden" }
	end
	if l.status ~= "waiting" and not l.joinInProgress then
		return { admit = true, seat = false, reason = "inProgress" }
	end
	-- The arriving player normally isn't counted yet; if a heartbeat already counted them, don't count
	-- them against their own seat.
	local open = LobbyDirectory.openSeats(l, now)
	if present(l, viewer.userId) then
		open += 1
	end
	if open <= 0 then
		return { admit = true, seat = false, reason = "full" }
	end
	return { admit = true, seat = true }
end

-- The record's key in the store; also accepted from clients, so it is validated the same way.
function LobbyDirectory.readLobbyId(raw: any): string?
	if LobbyDirectory.validId(raw) then
		return raw
	end
	return nil
end

function LobbyDirectory.reasonText(reason: string): string
	local r = LobbyDirectory.REASONS[reason]
	return if r then r.text else LobbyDirectory.REASONS.unavailable.text
end

function LobbyDirectory.reasonRetry(reason: string): boolean
	local r = LobbyDirectory.REASONS[reason]
	return if r then r.retry else true
end

return LobbyDirectory
