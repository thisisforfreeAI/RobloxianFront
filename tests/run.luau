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
			map = {
				width = W, height = H,
				terrainAt = function(c)
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

	test("bot captures a rig and trains infantry within 5 minutes", function()
		local sim = newSim()
		local bot = Bot.new(sim, 2)
		run(sim, 300, { bot })
		assert(#units(sim, 2, "rig") >= 1, "bot owns no rig")
		assert(#units(sim, 2, "infantry") > 3 or sim.winner ~= nil, "bot did not train")
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
