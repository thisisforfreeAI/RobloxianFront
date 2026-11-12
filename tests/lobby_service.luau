--!strict
-- LobbyDirectoryService across several simulated servers sharing one fake MemoryStore, with fake
-- teleports, friendships, messaging and clock. The real Roblox wiring (LobbyServer.luau) is not
-- exercised here; docs/LOBBY_DIRECTORY.md lists what must be checked in published servers.
return function(test: any, eq: any)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local D = require("../src/shared/Lobby/LobbyDirectory")
	local P = require("../src/shared/Lobby/LobbyProtocol")
	local source = fs.readFile("src/server/Lobby/LobbyDirectoryService.luau")
	local T0 = 1_800_000_000

	local function copy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = copy(x)
		end
		return out
	end

	-- One "experience": a clock, a MemoryStore sorted map, and a MessagingService topic.
	local function world()
		local w: any = { t = T0, data = {}, fail = false, bus = {}, writes = 0 }
		local function live(key: string): any
			local e = w.data[key]
			if e and e.exp <= w.t then
				w.data[key] = nil
				return nil
			end
			return e
		end
		w.store = {
			get = function(key: string)
				if w.fail then
					return false, nil
				end
				local e = live(key)
				return true, if e then copy(e.value) else nil
			end,
			update = function(key: string, transform: any, ttl: number)
				if w.fail then
					return false, nil
				end
				local e = live(key)
				local old = if e then e.value else nil
				transform(copy(old)) -- MemoryStore may retry a transform; it must give the same answer
				local result = transform(copy(old))
				if result == nil then
					return true, nil
				end
				w.writes += 1
				w.data[key] = { value = copy(result), exp = w.t + ttl }
				return true, copy(result)
			end,
			remove = function(key: string)
				if w.fail then
					return false
				end
				w.data[key] = nil
				return true
			end,
			range = function(count: number, after: any)
				w.rangeCount=(w.rangeCount or 0)+1
				assert(after==nil or type(after)=="table","Native GetRangeAsync requires a cursor table")
				if w.fail then
					return false, nil
				end
				local keys = {}
				for k in w.data do
					if live(k) and (after == nil or k > after.key) then
						table.insert(keys, k)
					end
				end
				table.sort(keys)
				local out = {}
				for i = 1, math.min(count, #keys) do
					table.insert(out, { key = keys[i], value = copy(w.data[keys[i]].value) })
				end
				return true, out
			end,
		}
		w.raw = function(key: string): any
			local e = live(key)
			return e and e.value
		end
		return w
	end

	local friendships: { [number]: { [number]: boolean } } = { [6] = { [42] = true } }

	local function server(w: any, opts: { [string]: any })
		local s: any = { teleports = {}, notices = {}, warnings = {}, loops = {}, friendCalls = 0, tpOk = true }
		s.state = { map = "Saddle", players = 1, capacity = 2, status = "waiting" }
		for k, v in opts.state or {} do
			s.state[k] = v
		end
		local shared = { Lobby = { LobbyDirectory = "dir", LobbyProtocol = "proto" } }
		local rs = { WaitForChild = function() return shared end }
		local env = setmetatable({
			game = { GetService = function() return rs end },
			require = function(key: string) return if key == "dir" then D else P end,
		}, { __index = getfenv() })
		local Service = luau.load(source, { environment = env })()
		s.svc = Service.new({
			store = w.store,
			now = function() return w.t end,
			lobbyId = opts.lobbyId,
			placeId = 111,
			jobId = if opts.jobId == false then nil else (opts.jobId or opts.lobbyId),
			accessCode = opts.accessCode,
			teleport = function(player: any, route: any, data: any)
				table.insert(s.teleports, { player = player, route = route, data = data })
				if s.onTeleport then s.onTeleport(player,data) end
				return s.tpOk, if s.tpOk then nil else "HTTP 500"
			end,
			isFriend = function(player: any, userId: number)
				s.friendCalls += 1
				return (friendships[player.UserId] or {})[userId] == true
			end,
			messaging = {
				publish = function(msg: any)
					for _, cb in w.bus do
						cb(copy(msg))
					end
				end,
				subscribe = function(cb: any)
					table.insert(w.bus, cb)
				end,
			},
			every = function(sec: number, fn: any)
				table.insert(s.loops, sec)
				return function() s.stopped = true end
			end,
			fireNotice = function(player: any, payload: any)
				table.insert(s.notices, { player = player, payload = payload })
			end,
			warn = function(msg: string)
				table.insert(s.warnings, msg)
			end,
		})
		if opts.start ~= false then
			s.svc.start(function() return s.state end)
		end
		return s
	end

	local nextId = 100
	local function player(userId: number?): any
		nextId += 1
		return { UserId = userId or nextId, Name = "p" .. tostring(userId or nextId) }
	end
	local function ids(res: any): string
		assert(res.ok, res.reason)
		local out = {}
		for _, l in res.lobbies do
			table.insert(out, l.lobbyId)
		end
		return table.concat(out, ",")
	end

	test("lobby service publishes this server and other servers list it", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b", state = { players = 0, capacity = 4 } })
		eq(a.loops[1], D.HEARTBEAT_SEC)
		eq(w.raw("job-a").map, "Saddle"); eq(w.raw("job-a").jobId, "job-a")
		eq(ids(b.svc.browse(player(), nil)), "job-a,job-b")
	end)
	test("lobby service browse sorts fullest first and hides routing data", function()
		local w = world()
		server(w, { lobbyId = "job-a", state = { players = 1, capacity = 2 } })
		local b = server(w, { lobbyId = "job-b", state = { players = 0, capacity = 4 } })
		local res = b.svc.browse(player(), { hasSpace = true })
		eq(ids(res), "job-a,job-b")
		local a = res.lobbies[1]
		eq(a.map, "Saddle"); eq(a.players, 1); eq(a.capacity, 2); eq(a.openSeats, 1); eq(a.status, "waiting")
		eq(a.jobId, nil); eq(a.accessCode, nil); eq(a.userIds, nil)
		eq(a.expiresIn, D.WAITING_EXPIRY_SEC); eq(res.refreshAfter, P.REFRESH_AFTER_SEC)
	end)
	test("lobby service without a JobId (Studio) publishes nothing", function()
		local w = world()
		local s = server(w, { lobbyId = "" })
		eq(s.svc.heartbeat(), false); eq(next(w.data), nil)
		eq(#s.warnings, 1)
	end)
	test("lobby join holds a seat and teleports to the lobby's server; the last seat goes once", function()
		local w = world()
		server(w, { lobbyId = "job-a" }) -- 1 of 2 seated
		local b = server(w, { lobbyId = "job-b" })
		local c = server(w, { lobbyId = "job-c" })
		local p, q = player(10), player(11)
		local r = b.svc.join(p, "job-a")
		eq(r.ok, true); eq(r.route, "teleport")
		local tp = b.teleports[1]
		eq(tp.player, p); eq(tp.route.kind, "instance"); eq(tp.route.jobId, "job-a"); eq(tp.route.placeId, 111)
		eq(tp.data.lobbyId, "job-a"); eq(tp.data.from, "job-b")
		eq(w.raw("job-a").reservations["10"], T0 + D.RESERVATION_SEC)
		local r2 = c.svc.join(q, "job-a")
		eq(r2.ok, false); eq(r2.reason, "full"); eq(r2.retry, true); eq(r2.message, D.REASONS.full.text)
		eq(#c.teleports, 0)
	end)
	test("lobby join gives the seat back when the teleport fails", function()
		local w = world()
		server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b" })
		b.tpOk = false
		local p = player(10)
		local r = b.svc.join(p, "job-a")
		eq(r.ok, false); eq(r.reason, "teleportFailed")
		eq(w.raw("job-a").reservations["10"], nil)
		b.tpOk = true
		w.t += P.JOIN_COOLDOWN_SEC
		eq(b.svc.join(p, "job-a").ok, true) -- not left "busy"
	end)
	test("lobby join releases the seat on a later TeleportInitFailed and tells the player", function()
		local w = world()
		server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b" })
		local p = player(10)
		eq(b.svc.join(p, "job-a").ok, true)
		b.svc.teleportFailed(p)
		eq(w.raw("job-a").reservations["10"], nil)
		eq(b.notices[1].player, p); eq(b.notices[1].payload.reason, "teleportFailed")
		b.svc.teleportFailed(p) -- a second event for the same player is ignored
		eq(#b.notices, 1)
	end)
	test("lobby arrival honours the held seat and the next heartbeat consumes it", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b" })
		eq(b.svc.join(player(10), "job-a").ok, true)
		local arrived = player(10)
		local res = a.svc.arrive(arrived)
		eq(res.admit, true); eq(res.seat, true); eq(a.svc.arrival(arrived), res)
		a.state.players = 2
		w.t += 1
		a.svc.heartbeat()
		local l = w.raw("job-a")
		eq(l.reservations["10"], nil); eq(l.userIds[1], 10); eq(l.players, 2)
		w.t += 5
		local view = b.svc.browse(player(), nil).lobbies
		for _, v in view do
			if v.lobbyId == "job-a" then
				eq(v.openSeats, 0); eq(v.joinable, false)
			end
		end
		a.svc.leave(arrived)
		eq(a.svc.arrival(arrived), nil)
	end)
	test("stale lobby listings disappear without deleting a possibly refreshed owner's key", function()
		local w = world()
		server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b", start = false })
		eq(ids(b.svc.browse(player(), nil)), "job-a")
		w.t += D.STALE_SEC + 1
		local res = b.svc.browse(player(), nil)
		eq(ids(res), "")
		assert(w.data["job-a"]) -- TTL, not another browser, owns physical expiry.
		eq(b.svc.join(player(), "job-a").reason, "stale")
	end)
	test("lobby listings expire on their own, and MemoryStore expiry removes crashed servers", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a", state = { expiresAt = T0 + 30 } })
		w.t += 31
		a.svc.heartbeat()
		eq(w.raw("job-a"), nil)
		local w2 = world()
		server(w2, { lobbyId = "job-x" })
		w2.t += D.STORE_TTL_SEC
		eq(w2.raw("job-x"), nil)
	end)
	test("lobby waiting expiry restarts each time the server goes back to waiting", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a" })
		eq(w.raw("job-a").expiresAt, T0 + D.WAITING_EXPIRY_SEC)
		w.t += 600
		a.state.status = "inProgress"
		a.svc.heartbeat()
		eq(w.raw("job-a").expiresAt, T0 + D.MAX_LIFETIME_SEC)
		w.t += 600
		a.state.status = "waiting" -- match over, a new lobby on the same server
		a.svc.heartbeat()
		eq(w.raw("job-a").createdAt, T0 + 1200); eq(w.raw("job-a").expiresAt, T0 + 1200 + D.WAITING_EXPIRY_SEC)
	end)
	test("lobby close delists at once and other servers drop it from their cache", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b", start = false })
		eq(ids(b.svc.browse(player(), nil)), "job-a")
		a.svc.close()
		eq(w.data["job-a"], nil); eq(a.stopped, true)
		eq(ids(b.svc.browse(player(), nil)), "") -- same second: served from b's cache, already pruned
		a.svc.close() -- idempotent
		eq(a.svc.heartbeat(), false)
	end)
	test("lobby friends-only lobbies are hidden from and refuse strangers", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a", state = { visibility = "friends", hostUserId = 42 } })
		local b = server(w, { lobbyId = "job-b", start = false })
		local stranger, friend = player(5), player(6)
		eq(ids(b.svc.browse(stranger, nil)), "")
		eq(b.svc.join(stranger, "job-a").reason, "forbidden")
		eq(ids(b.svc.browse(friend, nil)), "job-a")
		local calls = b.friendCalls
		w.t += P.BROWSE_COOLDOWN_SEC
		b.svc.browse(friend, nil)
		eq(b.friendCalls, calls) -- cached
		eq(b.svc.join(friend, "job-a").ok, true)
		eq(a.svc.arrive(player(5)).admit, false)
		eq(a.svc.arrive(player(6)).seat, true)
	end)
	test("lobby visibility can only be changed by the host and takes effect at once", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a", state = { hostUserId = 42 } })
		local b = server(w, { lobbyId = "job-b", start = false })
		eq(a.svc.setVisibility(player(7), "private").reason, "forbidden")
		eq(a.svc.setVisibility(player(42), "secret").reason, "invalid")
		eq(a.svc.setVisibility(player(42), "private").ok, true)
		eq(w.raw("job-a").visibility, "private")
		eq(ids(b.svc.browse(player(), nil)), "")
		eq(b.svc.join(player(), "job-a").reason, "forbidden")
		eq(a.svc.arrive(player(8)).admit, false)
		eq(a.svc.arrive(player(42)).admit, true)
	end)
	test("lobby service reports an unavailable directory instead of a missing lobby", function()
		local w = world()
		server(w, { lobbyId = "job-a" })
		local b = server(w, { lobbyId = "job-b", start = false })
		eq(ids(b.svc.browse(player(), nil)), "job-a")
		w.fail = true
		w.t += 10
		eq(ids(b.svc.browse(player(), nil)), "job-a") -- last good read
		local j = b.svc.join(player(), "job-a")
		eq(j.reason, "unavailable"); eq(j.retry, true)
		local c = server(w, { lobbyId = "job-c", start = false })
		eq(c.svc.browse(player(), nil).reason, "unavailable")
		local arrivedDuringOutage = server(w, { lobbyId = "job-d", start = false }).svc.arrive(player())
		eq(arrivedDuringOutage.admit, true) -- fail open; match seat rules still apply
	end)
	test("lobby join for this server's own lobby needs no teleport or seat hold", function()
		local w = world()
		local a = server(w, { lobbyId = "job-a" })
		local r = a.svc.join(player(), "job-a")
		eq(r.ok, true); eq(r.route, "local"); eq(#a.teleports, 0)
		eq(next(w.raw("job-a").reservations), nil)
	end)
	test("lobby requests are validated and rate limited", function()
		local w = world()
		server(w, { lobbyId = "job-a", state = { capacity = 8 } })
		local b = server(w, { lobbyId = "job-b", start = false })
		local p = player()
		eq(b.svc.join(p, "bad id").reason, "invalid")
		eq(b.svc.join(p, { "job-a" }).reason, "invalid")
		local first = b.svc.browse(p, nil)
		eq(b.svc.browse(p, nil),first)
		eq(b.svc.browse(p, { map = "Ridge" }).reason,"busy") -- Never return another filter's rows.
		eq(b.svc.join(p, "job-a").ok, true)
		eq(b.svc.join(p, "job-a").reason, "busy")
		w.t += P.JOIN_COOLDOWN_SEC
		eq(b.svc.join(p, "job-a").reason, "busy") -- a teleport is still pending for this player
	end)
	test("lobby on a reserved server is routed by access code, never shown to clients", function()
		local w = world()
		server(w, { lobbyId = "job-r", jobId = false, accessCode = "Res3rved+Code/=" })
		local b = server(w, { lobbyId = "job-b", start = false })
		local res = b.svc.browse(player(), nil)
		eq(ids(res), "job-r"); eq(res.lobbies[1].accessCode, nil)
		eq(b.svc.join(player(), "job-r").ok, true)
		eq(b.teleports[1].route.kind, "reserved"); eq(b.teleports[1].route.accessCode, "Res3rved+Code/=")
	end)
	test("lobby on a server nobody can be routed to is not published, and warns once", function()
		local w = world()
		local v = server(w, { lobbyId = "job-v", jobId = false })
		v.svc.heartbeat()
		eq(next(w.data), nil); eq(#v.warnings, 1)
	end)
	test("destination claims direct arrivals atomically and holds seats until the match handshake",function()
		local w=world();local a=server(w,{lobbyId="job-a",state={userIds={}}});local p,q=player(303),player(304)
		eq(a.svc.arrive(p).seat,true);eq(a.svc.arrive(q).seat,false)
		assert(w.raw("job-a").reservations["303"]);a.svc.heartbeat();assert(w.raw("job-a").reservations["303"])
		a.state.players=2;a.state.userIds={303,42};a.svc.heartbeat();eq(w.raw("job-a").reservations["303"],nil)
		eq(a.svc.arrive(p).seat,true) -- Idempotent check, not a second seat claim.
	end)
	test("arrival enforces current local privacy even while MemoryStore is unavailable",function()
		local w=world();local a=server(w,{lobbyId="job-a",state={visibility="private",hostUserId=42,userIds={}}})
		w.fail=true;eq(a.svc.arrive(player(5)).admit,false);eq(a.svc.arrive(player(42)).admit,true)
	end)
	test("friends filter resolves friendship for public hosted listings too",function()
		local w=world();server(w,{lobbyId="job-a",state={hostUserId=42}});local b=server(w,{lobbyId="job-b",start=false})
		eq(ids(b.svc.browse(player(6),{friendsOnly=true})),"job-a")
	end)
	test("directory paging uses native cursor tables and shares a complete cached read",function()
		local w=world();for i=1,205 do local id=string.format("job-%03d",i);w.data[id]={value=D.makeListing({lobbyId=id,placeId=111,jobId=id,map="Saddle",players=1,capacity=2,status="waiting",visibility="public"},w.t),exp=w.t+60} end
		local b=server(w,{lobbyId="job-b",start=false});eq(#b.svc.browse(player(),{limit=100}).lobbies,100);eq(w.rangeCount,2)
		b.svc.browse(player(),nil);eq(w.rangeCount,2)
	end)
	test("a yielding join cannot be overlapped by another request after the cooldown",function()
		local w=world();server(w,{lobbyId="job-a"});local b=server(w,{lobbyId="job-b",start=false});local p=player()
		local get=w.store.get;w.store.get=function(id) coroutine.yield();return get(id) end
		local thread=coroutine.create(function() return b.svc.join(p,"job-a") end);assert(coroutine.resume(thread));w.t+=4
		eq(b.svc.join(p,"job-a").reason,"busy");local ok,r=coroutine.resume(thread);assert(ok);eq(r.ok,true);eq(#b.teleports,1)
	end)
	test("late teleport failures cannot release a newer request and synchronous events cannot revive joining",function()
		local w=world();server(w,{lobbyId="job-a"});local b=server(w,{lobbyId="job-b",start=false});local p=player()
		b.tpOk=false;eq(b.svc.join(p,"job-a").reason,"teleportFailed");local old=b.teleports[1].data.requestId
		w.t+=4;b.tpOk=true;eq(b.svc.join(p,"job-a").ok,true);local latest=b.teleports[2].data.requestId
		b.svc.teleportFailed(p,old);assert(w.raw("job-a").reservations[tostring(p.UserId)])
		b.svc.teleportFailed(p,latest);eq(w.raw("job-a").reservations[tostring(p.UserId)],nil)
		w.t+=4;b.onTeleport=function(who,data) b.svc.teleportFailed(who,data.requestId) end
		eq(b.svc.join(p,"job-a").reason,"teleportFailed")
	end)
	test("an in-flight heartbeat cannot republish after close",function()
		local w=world();local a=server(w,{lobbyId="job-a"});local update=w.store.update
		w.store.update=function(...) a.svc.close();return update(...) end
		eq(a.svc.heartbeat(),false);eq(w.raw("job-a"),nil)
	end)
	test("heartbeat retries read current seated players instead of an earlier captured count",function()
		local w=world();local a=server(w,{lobbyId="job-a"});local update=w.store.update
		w.store.update=function(...) a.state.players=2;a.state.userIds={1,2};return update(...) end
		a.svc.heartbeat();eq(w.raw("job-a").players,2);eq(#w.raw("job-a").userIds,2)
	end)
end

