--!strict
-- LobbyDirectory: the pure cross-server lobby directory rules (listing, visibility, expiry, joins).
return function(test: any, eq: any)
	local D = require("../src/shared/Lobby/LobbyDirectory")
	local NOW = 1_800_000_000

	local function state(over: { [string]: any }?): { [string]: any }
		local s: { [string]: any } = {
			lobbyId = "job-a", placeId = 111, jobId = "job-a", map = "Saddle", players = 1, capacity = 2,
			status = "waiting", visibility = "public", hostUserId = 0, createdAt = NOW,
		}
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end
	local function listing(over: { [string]: any }?, now: number?): any
		local l, err = D.makeListing(state(over), now or NOW)
		assert(l, err)
		return l
	end
	local stranger = { userId = 5 }
	local function friendOf(host: number)
		return { userId = 6, isFriend = function(id: number) return id == host end }
	end

	test("lobby listing keeps map, seats, status and expiry", function()
		local l = listing({ name = "  Tank\nrush  " })
		eq(l.v, D.SCHEMA); eq(l.map, "Saddle"); eq(l.players, 1); eq(l.capacity, 2)
		eq(l.status, "waiting"); eq(l.visibility, "public"); eq(l.name, "Tankrush")
		eq(l.updatedAt, NOW); eq(l.expiresAt, NOW + D.MAX_LIFETIME_SEC)
		eq(next(l.reservations), nil)
	end)
	test("lobby listing refuses bad fields and unroutable servers", function()
		local cases = {
			{ lobbyId = "bad id!" }, { placeId = 0 }, { map = "" }, { capacity = 0 }, { capacity = 1.5 },
			{ players = -1 }, { status = "lobby" }, { visibility = "secret" }, { hostUserId = -2 },
		}
		for _, over in cases do
			local l = D.makeListing(state(over), NOW)
			eq(l, nil)
		end
		local l, err = D.makeListing(state({ jobId = false }), NOW)
		eq(l, nil); eq(err, "unroutable")
		eq(D.makeListing("x", NOW), nil)
	end)
	test("lobby listing caps expiry at the lifetime limit and clamps players to seats", function()
		local l = listing({ expiresAt = NOW + 10 * D.MAX_LIFETIME_SEC, players = 9 })
		eq(l.expiresAt, NOW + D.MAX_LIFETIME_SEC); eq(l.players, 2)
		eq(listing({ expiresAt = NOW + 60 }).expiresAt, NOW + 60)
	end)
	test("lobby listing goes dead when stale, expired, closing or malformed", function()
		local l = listing({ expiresAt = NOW + 1000 })
		eq(D.deadReason(l, NOW + D.STALE_SEC), nil)
		eq(D.deadReason(l, NOW + D.STALE_SEC + 1), "stale")
		eq(D.deadReason(listing({ expiresAt = NOW + 10 }), NOW + 10), "expired")
		local closing = table.clone(l); closing.status = "closing"
		eq(D.deadReason(closing, NOW), "closed")
		local old = table.clone(l); old.v = 0
		eq(D.deadReason(old, NOW), "gone")
		eq(D.deadReason(nil, NOW), "gone")
	end)
	test("lobby visibility: public for all, friends for the host's friends, private never listed", function()
		eq(D.canSee(listing(), stranger), true)
		local f = listing({ visibility = "friends", hostUserId = 42 })
		eq(D.canSee(f, stranger), false)
		eq(D.canSee(f, friendOf(42)), true)
		eq(D.canSee(f, { userId = 42 }), true)
		eq(D.canSee(listing({ visibility = "friends", hostUserId = 0 }), friendOf(0)), false)
		local p = listing({ visibility = "private", hostUserId = 42 })
		eq(D.canSee(p, { userId = 42 }), false); eq(D.canSee(p, friendOf(42)), false)
	end)
	test("lobby public view hides routing secrets and member ids", function()
		local l = listing({ accessCode = "secret-code", userIds = { 9 } })
		l.reservations = { ["8"] = NOW + 30 }
		local v = D.publicView(l, NOW + 5)
		eq(v.jobId, nil); eq(v.accessCode, nil); eq(v.userIds, nil); eq(v.reservations, nil); eq(v.placeId, nil)
		eq(v.openSeats, 0); eq(v.joinable, false); eq(v.expiresIn, D.MAX_LIFETIME_SEC - 5); eq(v.ageSec, 5)
	end)
	test("lobby open seats count live reservations only", function()
		local l = listing({ players = 0, capacity = 3, userIds = { 7 } })
		l.reservations = { ["1"] = NOW + 10, ["2"] = NOW - 1, ["7"] = NOW + 10 } -- 2 expired, 7 arrived
		eq(D.pendingReservations(l, NOW), 1); eq(D.openSeats(l, NOW), 2)
		l.players = 3
		eq(D.openSeats(l, NOW), 0)
	end)
	test("lobby browse lists live visible lobbies, waiting and fullest first", function()
		local a = listing({ lobbyId = "a", players = 0 })
		local b = listing({ lobbyId = "b", players = 1 })
		local c = listing({ lobbyId = "c", players = 2, status = "inProgress" })
		local stale = listing({ lobbyId = "s" }, NOW - D.STALE_SEC - 1)
		local hidden = listing({ lobbyId = "h", visibility = "private", hostUserId = 3 })
		local friends = listing({ lobbyId = "f", visibility = "friends", hostUserId = 42, players = 0 })
		local out, dead = D.browse({ a, b, c, stale, hidden, friends, "junk", b }, stranger, NOW)
		eq(#out, 3); eq(out[1].lobbyId, "b"); eq(out[2].lobbyId, "a"); eq(out[3].lobbyId, "c")
		eq(#dead, 1); eq(dead[1], "s")
		out = D.browse({ a, b, c, friends }, friendOf(42), NOW)
		eq(#out, 4)
	end)
	test("lobby browse filters by map, status, space and friends, and honours the limit", function()
		local a = listing({ lobbyId = "a", players = 2 })
		local b = listing({ lobbyId = "b", map = "Ridge" })
		local c = listing({ lobbyId = "c", status = "inProgress", joinInProgress = true })
		local f = listing({ lobbyId = "f", visibility = "friends", hostUserId = 42 })
		local all = { a, b, c, f }
		local function ids(filter: any, viewer: any?)
			local out = D.browse(all, viewer or stranger, NOW, D.readFilter(filter))
			local s = {}
			for _, v in out do
				table.insert(s, v.lobbyId)
			end
			return table.concat(s, ",")
		end
		eq(ids({ map = "ridge" }), "b")
		eq(ids({ status = "inProgress" }), "c")
		eq(ids({ hasSpace = true }), "b,c")
		eq(ids({ friendsOnly = true }, friendOf(42)), "f")
		eq(ids({ limit = 1 }), "a")
	end)
	test("lobby join recheck refuses gone, stale, hidden, duplicate, started and full lobbies", function()
		local function why(l: any, viewer: any?, now: number?)
			local ok, r = D.checkJoin(l, viewer or stranger, now or NOW, "job-here")
			eq(ok, false)
			return r
		end
		eq(why(nil), "gone")
		eq(why(listing(), nil, NOW + D.STALE_SEC + 1), "stale")
		eq(why(listing({ visibility = "friends", hostUserId = 42 })), "forbidden")
		eq(why(listing({ visibility = "private", hostUserId = 42 }), { userId = 42 }), "forbidden")
		eq(why(listing({ userIds = { 5 } })), "already")
		eq(why(listing({ status = "inProgress" })), "inProgress")
		eq(why(listing({ players = 2 })), "full")
		local held = listing({ players = 1 }); held.reservations = { ["9"] = NOW + 5 }
		eq(why(held), "full")
	end)
	test("lobby join routes to the lobby's own server", function()
		local ok, r: any = D.checkJoin(listing(), stranger, NOW, "job-here")
		eq(ok, true); eq(r.kind, "instance"); eq(r.jobId, "job-a"); eq(r.placeId, 111)
		ok, r = D.checkJoin(listing({ jobId = false, accessCode = "code+/=" }), stranger, NOW, "job-here")
		eq(ok, true); eq(r.kind, "reserved"); eq(r.accessCode, "code+/=")
		ok, r = D.checkJoin(listing(), stranger, NOW, "job-a")
		eq(ok, true); eq(r.kind, "local")
		ok, r = D.checkJoin(listing({ status = "inProgress", joinInProgress = true }), stranger, NOW, "x")
		eq(ok, true)
	end)
	test("lobby reserve hands out the last seat once and keeps a retry's own hold", function()
		local l = listing({ players = 1, capacity = 2 })
		local first, r1: any = D.reserve(l, { userId = 1 }, NOW, "x")
		assert(first); eq(r1.kind, "instance")
		eq(next(l.reservations), nil) -- input untouched
		local second, r2 = D.reserve(first, { userId = 2 }, NOW, "x")
		eq(second, nil); eq(r2, "full")
		local again = D.reserve(first, { userId = 1 }, NOW + 1, "x") -- teleport retry
		assert(again); eq(again.reservations["1"], NOW + 1 + D.RESERVATION_SEC)
		first.updatedAt = NOW + D.RESERVATION_SEC -- the owner kept heartbeating
		local later = D.reserve(first, { userId = 2 }, NOW + D.RESERVATION_SEC + 1, "x") -- hold lapsed
		assert(later); eq(later.reservations["1"], nil)
	end)
	test("lobby reserve caps outstanding holds and never writes for a local join", function()
		local l = listing({ players = 0, capacity = 50 })
		for i = 1, D.MAX_RESERVATIONS do
			l = D.reserve(l, { userId = i }, NOW, "x") :: any
		end
		local nope, why = D.reserve(l, { userId = 999 }, NOW, "x")
		eq(nope, nil); eq(why, "busy")
		local none, r: any = D.reserve(listing(), stranger, NOW, "job-a")
		eq(none, nil); eq(r.kind, "local")
	end)
	test("lobby release gives a held seat back", function()
		local held = D.reserve(listing(), { userId = 1 }, NOW, "x") :: any
		local back = D.release(held, 1) :: any
		eq(back.reservations["1"], nil); eq(held.reservations["1"] ~= nil, true)
		eq(D.release(back, 1), nil); eq(D.release(nil, 1), nil)
	end)
	test("lobby heartbeat keeps others' holds and takes the owner's fresh state", function()
		local old = D.reserve(listing({ players = 0, capacity = 4 }), { userId = 1 }, NOW, "x") :: any
		old = D.reserve(old, { userId = 2 }, NOW, "x") :: any
		local fresh = listing({ players = 1, capacity = 4, userIds = { 2 }, createdAt = NOW + 50 }, NOW + 20)
		local merged = D.mergeHeartbeat(old, fresh, NOW + 20) :: any
		eq(merged.reservations["1"], NOW + D.RESERVATION_SEC); eq(merged.reservations["2"], nil) -- 2 arrived
		eq(merged.createdAt, NOW + 50); eq(merged.updatedAt, NOW + 20); eq(merged.players, 1)
		local closing = table.clone(fresh); closing.status = "closing"
		eq(D.mergeHeartbeat(old, closing, NOW), nil)
		eq(next((D.mergeHeartbeat({ junk = true }, fresh, NOW) :: any).reservations), nil)
	end)
	test("lobby arrival admits holders and the host, refuses strangers to closed lobbies", function()
		local f = listing({ visibility = "friends", hostUserId = 42, players = 0 })
		eq(D.checkArrival(f, stranger, NOW).admit, false)
		eq(D.checkArrival(f, friendOf(42), NOW).seat, true)
		eq(D.checkArrival(f, { userId = 42 }, NOW).seat, true)
		local p = listing({ visibility = "private", hostUserId = 42 })
		eq(D.checkArrival(p, friendOf(42), NOW).admit, false)
		local held = D.reserve(listing({ visibility = "friends", hostUserId = 42 }), friendOf(42), NOW, "x") :: any
		held.visibility = "private" -- host locked it after the seat was held: the hold still counts
		eq(D.checkArrival(held, friendOf(42), NOW).seat, true)
	end)
	test("lobby arrival without a seat becomes a spectator; unreadable directory fails open", function()
		local full = D.checkArrival(listing({ players = 2 }), stranger, NOW)
		eq(full.admit, true); eq(full.seat, false); eq(full.reason, "full")
		local started = D.checkArrival(listing({ status = "inProgress" }), stranger, NOW)
		eq(started.seat, false); eq(started.reason, "inProgress")
		eq(D.checkArrival(nil, stranger, NOW).seat, true)
		local counted = listing({ players = 2, userIds = { 5 } }) -- a heartbeat already counted them
		eq(D.checkArrival(counted, stranger, NOW).seat, true)
	end)
	test("lobby client input is validated", function()
		eq(D.readLobbyId("abc-123_X"), "abc-123_X"); eq(D.readLobbyId("a b"), nil)
		eq(D.readLobbyId(string.rep("a", 65)), nil); eq(D.readLobbyId(12), nil)
		local f = D.readFilter({ map = 5, status = "closing", limit = 1000, hasSpace = "yes" })
		eq(f.map, nil); eq(f.status, nil); eq(f.limit, D.DEFAULT_LIMIT); eq(f.hasSpace, false)
		eq(D.readFilter(nil).limit, D.DEFAULT_LIMIT)
		eq(D.reasonText("full"), D.REASONS.full.text); eq(D.reasonRetry("forbidden"), false)
		eq(D.reasonText("nonsense"), D.REASONS.unavailable.text)
	end)
end
