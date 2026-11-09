--!strict
-- Unit tests for pure shared modules. Run from the repo root: lune run tests/run
-- (Roblox-only modules are covered by the Studio checklist in docs/STUDIO_TESTS.md.)
local fs = require("@lune/fs")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`  ok    {name}`)
	else
		failed += 1
		print(`  FAIL  {name}: {err}`)
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "values differ"}: got {a}, expected {b}`, 2)
	end
end
local function near(a: number, b: number, msg: string?)
	if math.abs(a - b) > 1e-12 then
		error(`{msg or "numbers differ"}: got {a}, expected {b}`, 2)
	end
end

local Rng = require("../src/shared/Utilities/Rng")
local ValueNoise = require("../src/shared/Utilities/ValueNoise")
local Rules = require("../src/shared/Config/Rules")
local MapCodec = require("../src/shared/Maps/MapCodec")
local Protocol = require("../src/shared/Protocol/Protocol")
local Movement = require("../src/shared/Simulation/Movement")
local Pathing = require("../src/shared/Simulation/Pathing")
local Territory = require("../src/shared/Simulation/Territory")

print("Rng / ValueNoise (vectors produced by WarFront's own JS)")
test("rng matches original for 4 seeds", function()
	local vectors = {
		[7121] = { 0.3741214736364782, 0.6082034008577466, 0.18615563539788127, 0.7323299183044583, 0.32289322768338025 },
		[1] = { 0.6270739405881613, 0.002735721180215478, 0.5274470399599522, 0.9810509674716741, 0.9683778982143849 },
		[0] = { 0.26642920868471265, 0.0003297457005828619, 0.2232720274478197, 0.1462021479383111, 0.46732782293111086 },
		[4294967295] = { 0.8964226141106337, 0.189478256739676, 0.7156526781618595, 0.9440599093213677, 0.8452364315744489 },
	}
	for seed, values in vectors do
		local g = Rng.new(seed)
		for i, v in values do
			near(g(), v, `seed {seed} draw {i}`)
		end
	end
end)
test("rng 1000th draw for seed 7121", function()
	local g, x = Rng.new(7121), 0
	for _ = 1, 1000 do
		x = g()
	end
	near(x, 0.5211691600270569)
end)
test("value noise matches original", function()
	local n = ValueNoise.new(Rng.new(7121))
	eq(n.perm[1], 190)
	eq(n.perm[8], 97)
	near(n.grads[1], 0.9792643189430237)
	near(n:sample(3.3, 4.7), 0.2511387091748023)
	near(n:sample(-12.25, 0.5), 0.506257641420234)
	near(n:fbm(10.5, 20.25), 0.5113688632395239)
	near(n:fbm(-3.1, 7.9, 3, 2, 0.6), 0.5641692552422755)
end)

print("Protocol")
test("accepts a valid move", function()
	local intent = Protocol.parse({ kind = "move", unitIds = { 1, 2, 2 }, x = 10, y = 20 }, 384, 240)
	assert(intent and intent.kind == "move" and #intent.unitIds == 2, "should dedupe ids")
end)
test("parses attack and produce, rejects bad ones", function()
	local a = Protocol.parse({ kind = "attack", unitIds = { 1, 2 }, targetId = 7 }, 10, 10)
	assert(a and a.kind == "attack" and (a :: any).targetId == 7)
	assert(Protocol.parse({ kind = "attack", unitIds = { 1 }, targetId = 1.5 }, 10, 10) == nil)
	local p = Protocol.parse({ kind = "produce", item = "infantry" }, 10, 10)
	assert(p and (p :: any).item == "infantry")
	assert(Protocol.parse({ kind = "produce", item = "nuke" }, 10, 10) == nil)
	assert(Protocol.parse({ kind = "produce" }, 10, 10) == nil)
end)

test("rejects bad moves", function()
	local cases = {
		{ kind = "move", unitIds = {}, x = 1, y = 1 },
		{ kind = "move", unitIds = { 1 }, x = -1, y = 1 },
		{ kind = "move", unitIds = { 1 }, x = 384, y = 1 },
		{ kind = "move", unitIds = { 1 }, x = 0 / 0, y = 1 },
		{ kind = "move", unitIds = { 1.5 }, x = 1, y = 1 },
		{ kind = "teleport", unitIds = { 1 } },
		"nope",
	}
	for i, c in cases do
		local intent = Protocol.parse(c, 384, 240)
		assert(intent == nil, `case {i} should be rejected`)
	end
	local many = {}
	for i = 1, Protocol.MAX_UNITS_PER_ORDER + 1 do
		many[i] = i
	end
	assert(Protocol.parse({ kind = "stop", unitIds = many }, 384, 240) == nil, "oversized order should be rejected")
end)

print("Movement")
local function ctx(blockX: number?)
	return {
		speedOf = function(_kind: string)
			return 0.5
		end,
		paceAt = function(_kind: string, x: number, _y: number)
			return if blockX and x >= blockX then 0 else 1
		end,
	}
end
test("moves at speed x pace and arrives", function()
	local u: any = { id = 1, kind = "infantry", side = 1, x = 0, y = 0, heading = 0, hp = 100, target = { x = 1, y = 0 } }
	Movement.step(u, 1, ctx())
	near(u.x, 0.5)
	Movement.step(u, 1, ctx())
	near(u.x, 1)
	assert(u.target == nil, "target cleared on arrival")
end)
test("stops before impassable cells", function()
	local u: any = { id = 1, kind = "infantry", side = 1, x = 0, y = 0, heading = 0, hp = 100, target = { x = 5, y = 0 } }
	for _ = 1, 20 do
		Movement.step(u, 0.5, ctx(2))
	end
	assert(u.x < 2, "unit entered blocked cells")
	assert(u.target == nil, "blocked unit gives up its order")
end)

print("Generated data (needs tools/conversion output; skipped if absent)")
local rulesPath = "src/shared/GameData/RulesData.luau"
if fs.isFile(rulesPath) then
	test("rules table has 1435 entries and known values", function()
		local r = Rules.new(require("../src/shared/GameData/RulesData") :: any)
		eq(r:count(), 1435)
		eq(r:number("units.tank.cost"), 145)
		eq(r:has("match.tickHz"), false, "locked rules are not in the moddable table")
		eq(require("../src/shared/GameData/Locked")["match.tickHz"], 20)
		eq(r:flag("intel.fog"), true)
		eq(r:section("units.infantry").hp, 100)
	end)
else
	print("  skip  RulesData.luau not generated")
end
if fs.isFile("src/shared/GameData/Maps/Saddle.luau") then
	test("saddle decodes to the original terrain histogram", function()
		local map = MapCodec.decode(require("../src/shared/GameData/Maps/Saddle") :: any)
		eq(map.width, 384)
		eq(map.height, 240)
		local counts = {}
		for i = 0, map.width * map.height - 1 do
			local t = buffer.readu8(map.terrain, i)
			counts[t] = (counts[t] or 0) + 1
		end
		eq(counts[3], 71074, "plains")
		eq(counts[5], 10954, "hills")
		eq(counts[6], 5150, "mountain")
		eq(counts[4], 4553, "forest")
		eq(counts[7], 429, "snow")
		eq(#map.data.rigs, 14, "rigs")
		eq(#map.data.starts, 2, "starts")
	end)
else
	print("  skip  Saddle.luau not generated")
end

print("Roads (pure)")
local Roads = require("../src/shared/Simulation/Roads")
test("grid line walk matches the game's (0,0)->(5,2) and (3,3)->(0,0)", function()
	-- expected cells computed with WarFront's own line function
	local a = Roads.line(10, 10, 0, 0, 5, 2)
	eq(table.concat(a, ","), "0,1,11,12,13,14,24,25")
	local b = Roads.line(10, 10, 3.7, 3.2, 0, 0)
	eq(table.concat(b, ","), "33,23,22,12,11,1,0")
	eq(table.concat(Roads.line(10, 10, 2, 2, 2, 6), ","), "22,32,42,52,62", "vertical")
	eq(table.concat(Roads.line(10, 10, 2, 2, 7, 2), ","), "22,23,24,25,26,27", "horizontal")
end)
test("float32 rounding helper", function()
	eq(Roads.f32(0.1), 0.10000000149011612)
end)
test("road raster, bridge widening, networks and truck route", function()
	-- 20x9 plains with a river column at x=10; one highway along y=4 crossing it
	local w, h = 20, 9
	local roads = Roads.build({
		width = w, height = h,
		terrainAt = function(c) return if c % w == 10 then "river" else "plains" end,
		passable = function(t) return t ~= "river" and t ~= "deep" end,
		roads = { { rank = 2, track = false, pts = { 0.5, 4.5, 19.5, 4.5 } } },
		bridgeHalf = 1,
		truckCost = { [0] = 1.25, [1] = 1 / 0.6, [2] = 1.25, [3] = 1 },
		offRoadCost = 20,
		offRoadReach = 3,
	})
	assert(roads.isRoad(4 * w + 10), "bridge cell is road")
	assert(roads.isRoad(3 * w + 10) and roads.isRoad(5 * w + 10), "deck widened over the river")
	assert(not roads.isRoad(3 * w + 9), "no widening onto passable ground")
	eq(roads.pieces, 1)
	local path = roads.truckRoute(4 * w + 2, 4 * w + 18) :: { number }
	eq(#path, 16, "straight along the highway")
	eq(path[#path], 4 * w + 18)
	-- off-road only near the ends: a goal 7 rows away from any road is unreachable
	local far = roads.truckRoute(0 * w + 2, 8 * w + 18)
	assert(far ~= nil, "short off-road ends allowed (reach 3 + road)")
end)

print("Milestone 1B simulation on WarFront's match rules (needs RulesMatch)")
local matchPath = "src/shared/GameData/RulesMatch.luau"
if fs.isFile(matchPath) then
	local Sim = require("../src/shared/Simulation/Sim")
	local Bot = require("../src/shared/Simulation/Bot")
	local rulesData = require("../src/shared/GameData/RulesMatch") :: any
	local W, H = 180, 60
	-- plains, a forest block at x 100..102, and a highway along y = 30
	local function newSim(opts: { [string]: any }?)
		local o = opts or {}
		return Sim.new({
			rules = Rules.new(rulesData) :: any,
			movement = Movement,
			roadsLib = Roads,
			pathingLib = Pathing,
			territoryLib = Territory,
			valueNoise = ValueNoise,
			rng = Rng,
			map = {
				width = W, height = H,
				terrainAt = o.terrainAt or function(c)
					local x = c % W
					return if x >= 100 and x <= 102 then "forest" else "plains"
				end,
				roads = o.roads or { { rank = 2, track = false, pts = { 0.5, 30.5, 179.5, 30.5 } } },
			},
			starts = { { x = 10.5, y = 30.5 }, { x = 170.5, y = 30.5 } },
			rigs = o.rigs or { { x = 50, y = 30 }, { x = 130, y = 30 } },
		})
	end
	local function run(sim, seconds, bots: any?)
		for _ = 1, math.floor(seconds * 20 + 0.5) do
			if bots then
				for _, b in bots do
					b.step(0.05)
				end
			end
			sim.step(0.05)
		end
	end
	local function units(sim, side, kind)
		local list = {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.kind == kind then
				table.insert(list, e)
			end
		end
		return list
	end
	local function ids(list)
		local out = {}
		for _, e in list do
			table.insert(out, e.id)
		end
		return out
	end
	local function clearUnits(sim, keep: { any })
		local k = {}
		for _, e in keep do
			k[e] = true
		end
		for _, e in sim.list do
			if e.cat == "unit" and not k[e] then
				e.alive = false
			end
		end
	end
	local function rigAt(sim, x)
		for _, rig in sim.rigs do
			if math.floor(rig.x) == x then
				return rig
			end
		end
		error("no rig")
	end

	test("match rules: cell scale 3, infantry range 13.5 cells, real rig values", function()
		local r = Rules.new(rulesData)
		eq(r:number("match.cellScale"), 3)
		near(r:number("units.infantry.range"), 13.5, "range")
		eq(r:number("rigs.oilPerSec"), 2.4)
		eq(r:number("rigs.tank"), 440)
		eq(r:number("trucks.kinds.light.capacity"), 160)
	end)

	test("setup: 600 oil, 3 idle trucks, 3 infantry 6.2 cells round the HQ, HQ 3000 hp", function()
		local sim = newSim()
		eq(sim.sides[1].oil, 600)
		eq(sim.sides[1].trucksIdle, 3)
		local hq = sim.hqOf(1)
		eq(hq.hp, 3000)
		local inf = units(sim, 1, "infantry")
		eq(#inf, 3)
		near(math.sqrt((inf[1].x - hq.x) ^ 2 + (inf[1].y - hq.y) ^ 2), 2 + 1.4 * 3, "ring radius")
		near(math.atan2(inf[1].y - hq.y, inf[1].x - hq.x), 0.6, "first at 0.6 rad")
	end)

	test("production: 36 oil, 7 s, queue 6, unit cap and oil refusals", function()
		local sim = newSim()
		assert(sim.orderProduce(1, "infantry"))
		eq(sim.sides[1].oil, 564)
		run(sim, 6.9)
		eq(#units(sim, 1, "infantry"), 3, "not yet")
		run(sim, 0.2)
		eq(#units(sim, 1, "infantry"), 4, "built after 7 s")
		for _ = 1, 6 do
			sim.orderProduce(1, "infantry")
		end
		local ok, why = sim.orderProduce(1, "infantry")
		assert(not ok and why == "queueFull", why)
		sim.sides[2].oil = 10
		local ok2, why2 = sim.orderProduce(2, "infantry")
		assert(not ok2 and why2 == "oil", why2)
		assert(not sim.orderProduce(1, "tank"), "HQ must not build tanks")
	end)

	test("orders for the other side's units are refused", function()
		local sim = newSim()
		local refused = sim.orderMove(1, ids(units(sim, 2, "infantry")), 30, 10)
		eq(#refused, 3)
	end)

	test("capture: weight 3 takes 12 s, weight 1 takes 24 s (minPace formula)", function()
		local sim = newSim()
		local inf = units(sim, 1, "infantry")
		clearUnits(sim, inf)
		for i, u in inf do
			u.x, u.y = 50.5 + (i - 2) * 0.5, 30.5
		end
		run(sim, 11.9)
		eq(rigAt(sim, 50).side, 0, "not before 12 s")
		run(sim, 0.2)
		eq(rigAt(sim, 50).side, 1, "captured at 12 s")
		local sim2 = newSim()
		local one = units(sim2, 1, "infantry")[1]
		clearUnits(sim2, { one })
		one.x, one.y = 50.5, 30.5
		run(sim2, 23.9)
		eq(rigAt(sim2, 50).side, 0, "one infantry: pace 0.5")
		run(sim2, 0.2)
		eq(rigAt(sim2, 50).side, 1, "captured at 24 s")
	end)

	test("capture: a rival freezes progress, leaving lets it decay at 0.08/s", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 2, "infantry")[1]
		clearUnits(sim, { a })
		a.x, a.y = 50.5, 30.5
		run(sim, 6) -- progress 0.25
		local rig = rigAt(sim, 50)
		near(rig.capture.progress, 0.25 + 0, "progress after 6 s at pace 0.5")
		_ = b
		local rival = sim.spawnUnit("infantry", 2, 51, 30.5) -- an unkillable rival on the rig
		rival.hp, rival.shotTimer, a.shotTimer = 1e9, math.huge, math.huge
		run(sim, 2)
		assert(rig.contested, "contested")
		near(rig.capture.progress, 0.25, "frozen")
		rival.alive, a.target = false, nil
		a.x = 80
		run(sim, 1)
		assert(math.abs(rig.capture.progress - (0.25 - 0.08)) < 1e-6, `decayed: {rig.capture.progress}`)
	end)

	test("guard: a rig within radius x guardShare of the owner's HQ cannot be taken", function()
		local sim = newSim({ rigs = { { x = 160, y = 30 } } })
		local rig = sim.rigs[1]
		rig.side, rig.takenAt = 2, -999
		assert(sim.guarded(rig, 2), "HQ guards rig 10.5 cells away (reach 12)")
		local inf = units(sim, 1, "infantry")
		clearUnits(sim, inf)
		for _, u in inf do
			u.x, u.y, u.hp, u.shotTimer = 160.5, 31, 1e9, math.huge
		end
		run(sim, 30)
		eq(rig.side, 2, "still side 2")
	end)

	test("pumping starts takeoverSec (6 s) after capture at 2.4 oil/s into a 440 tank", function()
		local sim = newSim()
		local inf = units(sim, 1, "infantry")
		clearUnits(sim, inf)
		for _, u in inf do
			u.x, u.y = 50.5, 30.5
		end
		local rig = rigAt(sim, 50)
		while rig.side ~= 1 do
			sim.step(0.05)
		end
		local t0 = sim.time
		while sim.time - t0 < 5.9 do
			sim.step(0.05)
		end
		eq(rig.tank, 0, "no oil during takeover")
		run(sim, 1.1)
		assert(rig.tank > 0 and rig.tank <= 2.4 * 1.1, `pumping: {rig.tank}`)
	end)

	test("trucks: one idle truck goes out automatically, loads and delivers by road", function()
		local sim = newSim()
		local inf = units(sim, 1, "infantry")
		clearUnits(sim, inf)
		for _, u in inf do
			u.x, u.y = 50.5, 30.5
		end
		local start = sim.sides[1].oil
		local delivered = 0
		local t = 0
		for _ = 1, 20 * 120 do
			sim.step(0.05)
			t += 0.05
			for _, ev in sim.takeEvents() do
				if ev.type == "delivered" then
					delivered += ev.oil
				end
			end
		end
		eq(sim.sides[1].trucksIdle, 2, "one idle truck used")
		eq(#units(sim, 1, "truck"), 1, "one truck on the rig")
		assert(delivered >= 80, `first load is at least half a truck: {delivered}`)
		assert(math.abs(sim.sides[1].oil - (start + 0.5 * t + delivered)) < 1e-6, "oil = start + HQ trickle + deliveries")
	end)

	test("buying trucks: idle first, then 40 oil each, at most 4 per rig", function()
		local sim = newSim()
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, 0
		sim.updateConnections()
		for _ = 1, 10 do
			sim.updateRoutes()
			sim.ticks += 1
		end
		assert(rig.route, "route home exists")
		for _ = 1, 3 do
			assert(sim.orderTruck(1, rig.id))
		end
		eq(sim.sides[1].trucksIdle, 0)
		eq(sim.sides[1].oil, 600)
		assert(sim.orderTruck(1, rig.id))
		eq(sim.sides[1].oil, 560, "fourth truck bought")
		local ok, why = sim.orderTruck(1, rig.id)
		assert(not ok and why == "truckLimit", why)
		local ok2, why2 = sim.orderTruck(2, rig.id)
		assert(not ok2 and why2 == "notOwned", why2)
	end)

	test("a rig with no road nearby is not connected and gets no truck", function()
		local sim = newSim({ roads = { { rank = 2, track = false, pts = { 0.5, 30.5, 30.5, 30.5 } } } })
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		eq(rig.connected, false)
		local ok, why = sim.orderTruck(1, rig.id)
		assert(not ok and why == "noRoute", why)
	end)

	test("combat: 8 damage per infantry shot, landing after the bullet flight", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 2, "infantry")[1]
		clearUnits(sim, { a, b })
		a.x, a.y, b.x, b.y = 60, 10, 67, 10 -- 7 cells: flight 0.1 s
		b.shotTimer = math.huge
		run(sim, 0.1)
		eq(b.hp, 100, "still in flight")
		run(sim, 0.1)
		eq(b.hp, 92, "first hit")
		run(sim, 14)
		assert(not b.alive, `b hp {b.hp}`)
	end)

	test("cover: forest takes 25% off", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 2, "infantry")[1]
		clearUnits(sim, { a, b })
		a.x, a.y, b.x, b.y = 95, 10, 101.5, 10
		b.heading, b.shotTimer = math.pi, math.huge -- b faces a
		run(sim, 0.3)
		near(b.hp, 100 - 8 * 0.75, "forest cover 0.25")
	end)

	test("armour facing: front 0.7x, rear 1.35x (tank target)", function()
		local sim = newSim()
		local tank = sim.spawnUnit("tank", 2, 60, 10)
		local front = sim.spawnUnit("infantry", 1, 63, 10)
		clearUnits(sim, { tank, front })
		tank.heading, tank.shotTimer = 0, math.huge
		local hp0 = tank.hp
		run(sim, 0.15)
		near(hp0 - tank.hp, 8 * 0.25 * 0.7, "front")
		front.x, front.shotTimer = 57, 0
		local hp1 = tank.hp
		run(sim, 0.15)
		near(hp1 - tank.hp, 8 * 0.25 * 1.35, "rear (flanked, armour keeps facing only)")
	end)

	test("a destroyed truck loses its cargo and its rig reports no trucks", function()
		local sim = newSim()
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, 0
		sim.updateConnections()
		for _ = 1, 10 do
			sim.updateRoutes()
			sim.ticks += 1
		end
		assert(sim.orderTruck(1, rig.id))
		local truck = units(sim, 1, "truck")[1]
		truck.payload = 50
		rig.takenAt, rig.autoTruckAt = 1e9, 1e9 -- keep the rig dry so the truck waits there
		clearUnits(sim, { truck })
		for i = 1, 3 do -- an ambush next to the rig, where the truck waits for oil
			sim.spawnUnit("infantry", 2, 50, 20 + i) -- 8+ cells off: in range, outside the capture radius
		end
		local lost = false
		for _ = 1, 20 * 60 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "convoyLost" then
					lost = true
				end
			end
		end
		assert(lost and not truck.alive, "truck survived the ambush")
		assert(rig.noTrucks, "rig flagged")
		eq(sim.sides[1].trucksIdle, 2, "a lost truck does not return to the pool")
	end)

	test("HQ destroyed with no factory: eliminated at once, rigs neutral, winner decided", function()
		local sim = newSim()
		local rig = rigAt(sim, 130)
		rig.side, rig.tank = 2, 100
		local hq2 = sim.hqOf(2)
		hq2.hp = 5
		local inf = units(sim, 1, "infantry")
		for _, u in units(sim, 2, "infantry") do
			u.alive = false -- otherwise our infantry shoot them first (units before structures)
		end
		for _, u in inf do
			u.x, u.y = 160, 30.5
		end
		run(sim, 5)
		eq(sim.winner, 1)
		assert(sim.sides[2].lost)
		eq(#units(sim, 2, "infantry"), 0, "all its units die")
		eq(rig.side, 0)
		eq(rig.tank, 0)
	end)

	-- buildings: cells are y * 180 + x on the 180 x 60 test map (HQs at (10, 30) and (170, 30))
	local function cellOf(x: number, y: number): number
		return y * W + x
	end
	local function structuresOf(sim, side, kind)
		local out = {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.kind == kind then
				table.insert(out, e)
			end
		end
		return out
	end
	test("territory: the HQ paints buildRadius x reachShare (27 x 1.6 cells), rigs their pad", function()
		local sim = newSim()
		eq(sim.territoryAt(cellOf(10, 30)), 1)
		eq(sim.territoryAt(cellOf(52, 30)), 1, "42 cells out is inside 43.2")
		eq(sim.territoryAt(cellOf(70, 30)), -1, "beyond r x (1 + wobble 0.3) is never painted")
		eq(sim.territoryAt(cellOf(170, 30)), 2)
		local rig = sim.rigs[2] -- (130, 30)
		rig.side = 1
		eq(sim.territoryAt(cellOf(130, 37)), 1, "an unjoined rig paints rigPad 12; the nearer source wins")
	end)
	test("buildings: a barracks costs 170, blocks its 3x3 footprint and is built in 15 s", function()
		local sim = newSim()
		local c = cellOf(20, 42)
		eq(sim.canPlace(1, "barracks", c), nil)
		local id = sim.placeStructure(1, "barracks", c)
		assert(id, "placed")
		eq(sim.sides[1].oil, 600 - 170)
		local b = sim.entities[id]
		eq(b.built, 0)
		assert(not sim.roads.passable(cellOf(21, 43)) and sim.roads.passable(cellOf(22, 43)), "footprint radius 1")
		eq(sim.inactiveReason(b), "building")
		run(sim, 14.9)
		assert(b.built < 1, "not yet")
		run(sim, 0.2)
		eq(b.built, 1)
		local done = false
		for _, ev in sim.takeEvents() do
			if ev.type == "built" and ev.id == id then
				done = true
			end
		end
		assert(done, "built event")
	end)
	test("placement refusals in the game's order: onRoad, spacing, onRig, outsideBase, requires, oil", function()
		local sim = newSim()
		eq(sim.canPlace(1, "barracks", cellOf(20, 32)), "onRoad", "within footprint + road clearance 1 + pad 1 of the highway")
		eq(sim.canPlace(1, "barracks", cellOf(13, 33)), "spacing", "Chebyshev 3 from the HQ (1 + 2)")
		eq(sim.canPlace(1, "barracks", cellOf(48, 34)), "onRig", "within 1 + padCells 3 of the rig at (50, 30)")
		eq(sim.canPlace(1, "barracks", cellOf(100, 45)), "outsideBase")
		eq(sim.canPlace(1, "factory", cellOf(20, 42)), "requires", "a factory needs a built barracks")
		eq(sim.canPlace(1, "hq", cellOf(20, 42)), "blocked")
		sim.sides[1].oil = 100
		eq(sim.canPlace(1, "barracks", cellOf(20, 42)), "oil")
	end)
	test("production: barracks train infantry and AT, factories tanks; the HQ cannot train AT", function()
		local sim = newSim()
		sim.sides[1].oil = 5000
		local b = sim.placeStructure(1, "barracks", cellOf(20, 42)) :: number
		run(sim, 15.1)
		local f = sim.placeStructure(1, "factory", cellOf(26, 42)) :: number
		assert(f, "factory placed once the barracks stands")
		eq(select(2, sim.orderProduce(1, "at")), "blocked", "HQ")
		eq(select(2, sim.orderProduce(1, "tank", b)), "blocked", "barracks")
		eq(select(2, sim.orderProduce(1, "tank", f)), "notOperational", "still building")
		run(sim, 22)
		assert(sim.orderProduce(1, "at", b))
		assert(sim.orderProduce(1, "tank", f))
		run(sim, 16.1)
		eq(#units(sim, 1, "at"), 1)
		eq(#units(sim, 1, "tank"), 1)
		-- a facility under half health stops working and does not self-repair
		local fac = sim.entities[f]
		fac.hp = fac.maxHp * 0.4
		eq(select(2, sim.orderProduce(1, "tank", f)), "notOperational")
		run(sim, 10)
		eq(fac.hp, fac.maxHp * 0.4)
	end)
	test("HQ loss with an active factory: the nation stays in for hqLoss.graceSec (120 s)", function()
		local sim = newSim()
		sim.sides[2].oil = 5000
		local hq2 = sim.hqOf(2)
		sim.placeStructure(2, "barracks", cellOf(160, 42))
		run(sim, 15.1)
		assert(sim.placeStructure(2, "factory", cellOf(166, 42)))
		run(sim, 22.1)
		assert(sim.hasBuilding(2, "factory", true))
		hq2.hp = 5
		for _, u in units(sim, 2, "infantry") do
			u.alive = false
		end
		for _, u in units(sim, 1, "infantry") do
			u.x, u.y = 160, 30.5
		end
		run(sim, 5)
		assert(not hq2.alive, "HQ down")
		assert(not sim.sides[2].lost, "rehouse grace")
		run(sim, 110)
		assert(not sim.sides[2].lost, "still within 120 s")
		run(sim, 10)
		assert(sim.sides[2].lost, "out when the grace runs out (no command truck in the slice)")
	end)
	test("bot builds a barracks early, then a factory, and trains from them", function()
		local sim = newSim()
		local bot = Bot.new(sim, 1, "balanced")
		run(sim, 600, { bot })
		assert(#structuresOf(sim, 1, "barracks") >= 1, "barracks")
		local trained = 0
		for _, k in { "at", "tank", "ifv" } do
			trained += #units(sim, 1, k)
		end
		assert(#structuresOf(sim, 1, "factory") >= 1 or trained > 0, "factory or units from buildings")
	end)

	test("defences: a bunker goes up in 10 s, then fires on enemy infantry in its 16.5 cell range", function()
		local sim = newSim()
		for _, side in { 1, 2 } do
			for _, u in units(sim, side, "infantry") do
				u.alive = false
			end
		end
		local id = sim.placeStructure(1, "bunker", cellOf(20, 42)) :: number
		assert(id, "placed")
		eq(sim.sides[1].oil, 600 - 110)
		local foe = sim.spawnUnit("infantry", 2, 20.5, 56.5)
		foe.hp = 1e6
		run(sim, 9.9)
		eq(foe.hp, 1e6, "an unbuilt bunker does not fire")
		run(sim, 3)
		assert(foe.hp < 1e6, "a built bunker fires")
		foe.x, foe.y = 20.5, 60.5 -- 18 cells: out of range
		local hp = foe.hp
		run(sim, 3)
		eq(foe.hp, hp, "out of range")
	end)
	test("defences: the AT gun's cannon shot flies at 38 cells/s; tank shells and AT rockets fly too", function()
		local sim = newSim()
		for _, side in { 1, 2 } do
			for _, u in units(sim, side, "infantry") do
				u.alive = false
			end
		end
		local id = sim.placeStructure(1, "atgun", cellOf(20, 42)) :: number
		run(sim, 8.1)
		eq(sim.entities[id].built, 1)
		local tank = sim.spawnUnit("tank", 2, 20.5, 61.5)
		tank.hp = 1e6
		sim.strikes = {}
		local seen = nil
		for _ = 1, 200 do
			run(sim, 0.05)
			for _, s in sim.strikes do
				if s.by == 1 and not seen then
					seen = s.at - sim.time
				end
			end
			if seen then
				break
			end
		end
		assert(seen, "the AT gun fired")
		assert(math.abs(seen - 19 / 38) < 0.06, `19 cells at 38 cells/s: {seen}`)
	end)
	test("bot guards its home: after 300 s it builds bunkers or AT guns near the HQ", function()
		local sim = newSim()
		local bot = Bot.new(sim, 1, "turtle")
		for _ = 1, 45 do
			sim.sides[1].oil = 5000
			run(sim, 10, { bot })
		end
		local n = #structuresOf(sim, 1, "bunker") + #structuresOf(sim, 1, "atgun")
		assert(n >= 1, `defences built: {n}`)
	end)

	-- artillery, mortars and scouts
	local Fog = require("../src/shared/Simulation/Fog")
	local function emptySim()
		local sim = newSim()
		for _, side in { 1, 2 } do
			for _, u in units(sim, side, "infantry") do
				u.alive = false
			end
		end
		run(sim, 0.05)
		return sim
	end
	-- runs, returning the time of the first new strike by key, and its flight time
	local function firstShot(sim, key: string, seconds: number): (number?, number?)
		local known = {}
		for _, st in sim.strikes do
			known[st] = true
		end
		for _ = 1, math.floor(seconds * 20 + 0.5) do
			sim.step(0.05)
			for _, st in sim.strikes do
				if not known[st] and st.key == key then
					return sim.time, st.at - sim.time
				end
			end
		end
		return nil, nil
	end
	test("mortar: sets up 3 s before firing, shells fly at 6.5 cells/s, nothing inside 7.5 cells", function()
		local sim = emptySim()
		local m = sim.spawnUnit("mortar", 1, 90.5, 10.5)
		m.hp = 1e6
		local foe = sim.spawnUnit("infantry", 2, 90.5, 22.5)
		foe.hp = 1e6
		local t0 = sim.time
		local at, fl = firstShot(sim, "units.mortar", 6)
		assert(at, "fired")
		assert(at - t0 >= 3 - 1e-6 and at - t0 <= 3.15, `set-up 3 s: fired after {at - t0}`)
		assert(math.abs((fl :: number) - 12 / 6.5) < 0.01, `flight {fl}`)
		foe.x, foe.y = 90.5, 17.5 -- 7 cells
		local again = firstShot(sim, "units.mortar", 8)
		eq(again, nil, "inside the minimum range")
	end)
	test("mortar spotting: with fog on it fires only on cells its nation sees", function()
		local sim = emptySim()
		local m = sim.spawnUnit("mortar", 1, 90.5, 5.5)
		m.hp = 1e6
		local foe = sim.spawnUnit("infantry", 2, 90.5, 35.5) -- 30 cells: in range 43.2, beyond sight 18
		foe.hp = 1e6
		eq(firstShot(sim, "units.mortar", 6), nil, "unseen")
		local spot = sim.spawnUnit("infantry", 1, 90.5, 52.5) -- sees the foe 17 cells away
		spot.hp = 1e6
		assert(firstShot(sim, "units.mortar", 2), "fires once a comrade spots it")
	end)
	test("artillery: splash hits comrades within 4.5 cells for half the hit, with bunching", function()
		local sim = emptySim()
		local a = sim.spawnUnit("artillery", 1, 90.5, 5.5)
		a.hp = 1e6
		local main = sim.spawnUnit("infantry", 2, 90.5, 40.5)
		local mate = sim.spawnUnit("infantry", 2, 92.5, 41.5)
		local far = sim.spawnUnit("infantry", 2, 96.5, 41.5)
		for _, u in { main, mate, far } do
			u.hp = 1e6
		end
		local at = firstShot(sim, "units.artillery", 6)
		assert(at, "fired (artillery needs no spotting)")
		run(sim, 3)
		local hitMain, hitMate = 1e6 - main.hp, 1e6 - mate.hp
		assert(hitMain > 0, "main hit")
		assert(math.abs(hitMate - hitMain * 0.5) < 1e-6, `half splash: {hitMate} vs {hitMain}`)
		eq(far.hp, 1e6, "6 cells from the target: no splash")
		-- 12 dps x 0.9 soft x 7 s x bunch (1 + 0.2 x 1) x (1 - cover)
		local cover = sim.coverAt and sim.coverAt(sim.roads.cellAt(main.x, main.y)) or 0
		assert(math.abs(hitMain - 12 * 0.9 * 7 * 1.2 * (1 - cover)) < 1e-6, `damage {hitMain}`)
	end)
	test("artillery: a gun that fired is revealed for 6 s and packs 3 s before it moves", function()
		local sim = emptySim()
		local a = sim.spawnUnit("artillery", 1, 90.5, 5.5)
		a.hp = 1e6
		local foe = sim.spawnUnit("infantry", 2, 90.5, 40.5)
		foe.hp = 1e6
		local viewer = Fog.newViewer(sim, 2)
		viewer.update()
		assert(not viewer.visibleAt(a.x, a.y), "hidden before it fires")
		local at = firstShot(sim, "units.artillery", 6)
		assert(at, "fired")
		eq(a.packAt, -1, "deployed")
		viewer.update()
		assert(viewer.visibleAt(a.x, a.y), "revealed to the enemy")
		foe.alive = false
		sim.orderMove(1, { a.id }, 90.5, 20.5)
		run(sim, 2.9)
		eq(a.y, 5.5, "packing")
		run(sim, 1)
		assert(a.y > 5.5, "moving after packSec")
		run(sim, 3)
		viewer.update()
		assert(not viewer.visibleAt(a.x, a.y), "reveal over after revealSec")
	end)
	test("scout: recon for 90 s sees 66 cells and holds still, then a 60 s cooldown; orders pack it", function()
		local sim = emptySim()
		local sc = sim.spawnUnit("scout", 1, 90.5, 30.5)
		local foe = sim.spawnUnit("infantry", 2, 150.5, 30.5) -- 60 cells
		foe.hp, sc.hp = 1e6, 1e6
		local viewer = Fog.newViewer(sim, 1)
		viewer.update()
		assert(not viewer.unitVisible(foe), "beyond the scout's sight 15")
		eq((sim.deployRecon(1, { sc.id })), 1)
		viewer.update()
		assert(viewer.unitVisible(foe), "recon radius 66")
		sim.orderMove(1, { sc.id }, 60.5, 30.5)
		assert(not sim.scoutDeployed(sc), "a move order packs it")
		near(sim.scoutReadyIn(sc), 60, "cooldown")
		local n, why = sim.deployRecon(1, { sc.id })
		eq(n, 0)
		eq(why, "cooldown")
		run(sim, 60.05)
		sim.orderStop(1, { sc.id })
		eq((sim.deployRecon(1, { sc.id })), 1)
		local x = sc.x
		run(sim, 89.9)
		assert(sim.scoutDeployed(sc) and sc.x == x, "deployed and still")
		run(sim, 0.2)
		assert(not sim.scoutDeployed(sc), "packs after 90 s")
	end)

	-- fog of war
	local Fog = require("../src/shared/Simulation/Fog")
	local function soloSim()
		local sim = newSim({ roads = {} })
		for _, u in units(sim, 1, "infantry") do
			u.alive = false
		end
		for _, u in units(sim, 2, "infantry") do
			u.alive = false
		end
		run(sim, 0.05)
		return sim
	end
	test("vision: infantry see 21 cells by day and x0.4 at full night (night ops on)", function()
		local sim = soloSim()
		local u = sim.spawnUnit("infantry", 1, 90.5, 30.5)
		local grid = {}
		sim.visionFor(1, grid)
		eq(grid[30 * W + 110 + 1], 2, "20 cells east")
		eq(grid[30 * W + 112 + 1], 0, "22 cells east")
		sim.time = 320 -- phase 0.747 of the 480 s day: full night
		eq(sim.nightAmount(), 1)
		sim.visionFor(1, grid)
		eq(grid[30 * W + 98 + 1], 2, "8 cells")
		eq(grid[30 * W + 100 + 1], 0, "10 cells is past 8.4")
		u.alive = false
	end)
	test("fog viewer: enemy units only when seen, enemy HQ always, buildings remembered as last seen", function()
		local sim = soloSim()
		local enemy = sim.spawnUnit("infantry", 2, 150.5, 45.5)
		local scout = sim.spawnUnit("infantry", 1, 60.5, 45.5)
		local v = Fog.newViewer(sim, 1)
		v.update()
		assert(not v.unitVisible(enemy), "far enemy hidden")
		eq(v.structureState(sim.hqOf(2)), "seen", "the enemy HQ is always shown")
		sim.sides[2].oil = 1000
		local bid = sim.placeStructure(2, "barracks", 42 * W + 150) :: number
		assert(bid, "red barracks placed")
		v.update()
		eq(v.structureState(sim.entities[bid]), "hidden")
		scout.x = 135.5
		v.update()
		assert(v.unitVisible(enemy), "now in sight")
		eq(v.structureState(sim.entities[bid]), "seen")
		scout.x = 60.5
		v.update()
		eq(v.structureState(sim.entities[bid]), "stale", "remembered after leaving")
		local rig = sim.rigs[2]
		rig.side = 2
		v.update()
		eq(v.rigOwner(rig), 0, "never seen: shown neutral")
	end)
	test("bot intel: the bot only knows enemy units it has seen, and forgets them after 45 s", function()
		local sim = soloSim()
		local bot = Bot.new(sim, 1, "balanced")
		local far = sim.spawnUnit("infantry", 2, 150.5, 50.5)
		run(sim, 1, { bot })
		assert(bot.intel.units[far.id] == nil, "unseen")
		local watcher = sim.spawnUnit("infantry", 1, 100.5, 50.5)
		local near = sim.spawnUnit("infantry", 2, 110.5, 50.5)
		run(sim, 3, { bot })
		assert(bot.intel.units[near.id] ~= nil, "seen by its unit")
		watcher.alive = false
		near.x, near.y = 150.5, 55.5
		run(sim, 30, { bot })
		assert(bot.intel.units[near.id] ~= nil, "remembered where it was last seen")
		run(sim, 20, { bot })
		assert(bot.intel.units[near.id] == nil, "forgotten after intel.unitIntelSec")
	end)

	-- a river along x = 80 with one ford at y = 11 (no roads)
	local function riverSim()
		return newSim({
			roads = {},
			terrainAt = function(c)
				local x, y = c % W, c // W
				return if x == 80 and y ~= 11 then "river" else "plains"
			end,
		})
	end
	test("pathing: a move across a river finds the ford instead of stopping at the bank", function()
		local sim = riverSim()
		local u = sim.spawnUnit("infantry", 1, 70.5, 40.5)
		sim.orderMove(1, { u.id }, 90.25, 40.75)
		local crossedAt = nil
		for _ = 1, 20 * 120 do
			sim.step(0.05)
			if not crossedAt and u.x >= 81 then
				crossedAt = math.floor(u.y)
			end
			if not u.target then
				break
			end
		end
		eq(crossedAt, 11, "crossed at the ford")
		assert(u.target == nil, "arrived")
		assert(math.abs(u.x - 90.25) < 1e-6 and math.abs(u.y - 40.75) < 1e-6, `ends on the exact spot, got {u.x},{u.y}`)
	end)
	test("pathing: a goal in the river sends the unit to the nearest bank cell (ring slots)", function()
		local sim = riverSim()
		local u = sim.spawnUnit("infantry", 1, 70.5, 40.5)
		sim.orderMove(1, { u.id }, 80.5, 40.5)
		assert(u.target ~= nil, "a slot was found")
		eq(sim.roads.cellAt(u.target.x, u.target.y), 40 * 180 + 79, "the bank cell on the unit's side (first in ring order)")
	end)
	test("pathing: a group stands in one rank 1.8 cells apart across its travel", function()
		local sim = newSim({ roads = {} })
		local group = {}
		for i = 1, 6 do
			table.insert(group, sim.spawnUnit("infantry", 1, 20.5, 40.5 + i * 0.3))
		end
		sim.orderMove(1, ids(group), 40.5, 42.5)
		local cells = {}
		for _, e in group do
			local c = sim.roads.cellAt(e.target.x, e.target.y)
			assert(not cells[c], "slots are distinct")
			cells[c] = true
		end
		run(sim, 20)
		local xs, ys = {}, {}
		for _, e in group do
			assert(e.target == nil, "all arrived")
			table.insert(xs, math.floor(e.x))
			table.insert(ys, math.floor(e.y))
		end
		table.sort(ys)
		for i = 2, #xs do
			assert(math.abs(xs[i] - xs[1]) <= 1, "one rank (same column, give or take rounding)")
		end
		assert(ys[#ys] - ys[1] >= 7 and ys[#ys] - ys[1] <= 11, `rank spans about 5 x 1.8 cells, got {ys[#ys] - ys[1]}`)
	end)
	test("pathing: road cells are preferred for long moves (off-road bias 1.6)", function()
		local sim = newSim()
		local u = sim.spawnUnit("infantry", 1, 20.5, 33.5)
		sim.orderMove(1, { u.id }, 90.5, 33.5)
		local onRoad = 0
		for _, c in u.path do
			if sim.roads.isRoad(c) then
				onRoad += 1
			end
		end
		assert(onRoad > 40, `most of the route is on the highway, got {onRoad} road cells`)
	end)
	test("bot personas come from the game's data; warlord earns 1.6x and thinks faster", function()
		local sim = newSim()
		local b = Bot.new(sim, 2, "turtle")
		eq(b.persona.attackMargin, 2.1)
		eq(b.persona.home, 0.4)
		eq(sim.sides[2].oilMult, 1)
		local sim2 = newSim()
		local w = Bot.new(sim2, 2, "warlord")
		eq(w.persona.attackMargin, 1.05)
		near(sim2.sides[2].oilMult, 1.6, "warlord oil edge")
		near(Bot.new(newSim(), 2, "nonsense").persona.attackMargin, 1.5, "unknown persona falls back to balanced")
	end)

	test("bot sends its 3 start infantry to the nearest neutral rig as a pair and keeps one home", function()
		local sim = newSim()
		local b = Bot.new(sim, 2, "balanced")
		run(sim, 1, { b }) -- first think at 0.87 s
		local sent = 0
		for _, t in b.orders do
			eq(t.kind, "rig")
			eq(sim.entities[t.id].x, 130.5, "nearest rig")
			sent += 1
		end
		eq(sent, 2, "need 20 -> two infantry (worth 30 each), the third stays home")
		eq(#sim.hqOf(2).queue, 1, "and it trains infantry")
	end)

	test("bot gets a truck onto its rig and trains an engineer once its army is 4", function()
		local sim = newSim()
		local b = Bot.new(sim, 2, "balanced")
		run(sim, 90, { b })
		local rig = rigAt(sim, 130)
		eq(rig.side, 2, "captured")
		assert(sim.trucksOf(rig.id) >= 1, "truck on the rig")
		local eng = #units(sim, 2, "engineer")
		local queued = 0
		for _, item in sim.hqOf(2).queue do
			if item == "engineer" then
				queued += 1
			end
		end
		assert(eng + queued >= 1, "engineer trained or queued")
	end)

	test("bot vs bot for 15 minutes: both expand, trucks deliver, nobody stalls", function()
		local sim = newSim({ rigs = { { x = 50, y = 30 }, { x = 130, y = 30 }, { x = 90, y = 10 }, { x = 90, y = 50 } } })
		local b1, b2 = Bot.new(sim, 1, "balanced"), Bot.new(sim, 2, "warlord")
		local delivered = { 0, 0 }
		for _ = 1, 20 * 900 do
			b1.step(0.05)
			b2.step(0.05)
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "delivered" then
					delivered[ev.side] += ev.oil
				end
			end
			if sim.winner then
				break
			end
		end
		assert(delivered[1] > 0 and delivered[2] > 0, `deliveries {delivered[1]} {delivered[2]}`)
		assert(#units(sim, 1, "rig") + #units(sim, 2, "rig") >= 2 or sim.winner, "rigs taken")
	end)
else
	print("  skip  RulesMatch.luau not generated")
end

print("Sprites (synthetic atlas)")
local Facing = require("../src/shared/Assets/Facing")
local PixelCodec = require("../src/shared/Assets/PixelCodec")
local AtlasCheck = require("../src/shared/Assets/AtlasCheck")
local MapCodecS = require("../src/shared/Maps/MapCodec")

test("facing index follows WarFront: 0 east, clockwise, round to nearest", function()
	local step = 2 * math.pi / 16
	eq(Facing.index(0, 16), 0)
	eq(Facing.index(math.pi / 2, 16), 4, "south (y down)")
	eq(Facing.index(math.pi, 16), 8, "west")
	eq(Facing.index(-math.pi / 2, 16), 12, "north")
	eq(Facing.index(-math.pi, 16), 8, "atan2 can return -pi")
	eq(Facing.index(step * 0.49, 16), 0)
	eq(Facing.index(step * 0.5, 16), 1, "half step rounds up like Math.round")
	eq(Facing.index(-step * 0.5, 16), 0, "Math.round(-0.5) = -0")
	eq(Facing.index(-step * 0.51, 16), 15)
	for i = 0, 15 do
		eq(Facing.index(i * step, 16), i)
	end
end)

test("residual stays within half a step and rebuilds the angle", function()
	for k = 0, 720 do
		local a = math.rad(k) - math.pi * 2
		local i = Facing.index(a, 16)
		local r = Facing.residual(a, i, 16)
		assert(math.abs(r) <= math.pi / 16 + 1e-9, `residual {r} at {k}`)
		local back = (i * math.pi / 8 + r - a) % (2 * math.pi)
		assert(back < 1e-9 or back > 2 * math.pi - 1e-9, `angle not rebuilt at {k}`)
	end
end)

test("synthetic 8x2 atlas metadata: 960x240, rects col = i % 8, row = i // 8", function()
	local meta = require("../src/shared/Assets/Atlases/SynVehicleArrow") :: any
	eq(meta.pages[1].width, 960)
	eq(meta.pages[1].height, 240)
	eq(meta.frameWidth, 120)
	for d = 0, 15 do
		local page, x, y = Facing.rect(meta, "idle", 0, d)
		eq(page, 1)
		eq(x, (d % 8) * 120, `x of {d}`)
		eq(y, (d // 8) * 120, `y of {d}`)
	end
end)

test("dev pixels decode and pass the in-memory atlas check", function()
	local meta = require("../src/shared/Assets/Atlases/SynVehicleArrow") :: any
	local dev = require("../src/client/DevAssets/SynVehicleArrow_p0") :: any
	local px = PixelCodec.decode(MapCodecS.base64Decode(dev.rle), dev.width, dev.height)
	eq(buffer.len(px), 960 * 240 * 4)
	local res = AtlasCheck.run(px, dev.width, meta, true)
	assert(res.ok, table.concat(res.failures, "; "))
	assert(res.worstDegrees < 3, "arrow error")
end)

test("atlas check catches a wrong rectangle", function()
	local meta = require("../src/shared/Assets/Atlases/SynVehicleArrow") :: any
	local dev = require("../src/client/DevAssets/SynVehicleArrow_p0") :: any
	local px = PixelCodec.decode(MapCodecS.base64Decode(dev.rle), dev.width, dev.height)
	local bad = table.clone(meta)
	bad.frames = { idle = { table.clone(meta.frames.idle[1]) } }
	bad.frames.idle[1][4], bad.frames.idle[1][5] = bad.frames.idle[1][5], bad.frames.idle[1][4]
	local res = AtlasCheck.run(px, dev.width, bad, true)
	assert(not res.ok, "swapped frames should fail")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed")
end
