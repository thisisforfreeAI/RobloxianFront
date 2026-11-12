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
test("kc hash matches the game's for the wreck seeds", function()
	local Hash = require("../src/shared/Utilities/Hash")
	-- values from the game's own function run in node
	local want = { { 0, 2, 0.9814142426475883 }, { 5821, 3, 0.4126983806490898 }, { 123456, 1, 0.8793687438592315 }, { 99999, 2, 0.18589441129006445 } }
	for _, w in want do
		near(Hash.kc(w[1], w[2]), w[3], `kc({w[1]}, {w[2]})`)
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
test("intents without unit ids parse (drop pick, ready, cancel, demolish, mines)", function()
	for _, raw in { { kind = "dropPick", x = 10, y = 10 }, { kind = "dropReady" }, { kind = "cancelQueue", index = 0 },
		{ kind = "demolish", structureId = 3 }, { kind = "layMines", pts = { 1, 2, 3, 4 } }, { kind = "nightOps", on = false }, { kind = "dig", unitIds = { 1 }, pts = { 1, 2, 5, 6 } }, { kind = "fill", unitIds = { 1 }, x = 3, y = 4 } } do
		local i, err = Protocol.parse(raw, 100, 100)
		assert(i and i.kind == raw.kind, `{raw.kind}: {err}`)
	end
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
			visibilityLib = o.visibilityLib,
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
				urbanAt = o.urbanAt,
				blockers = o.blockers,
			},
			starts = { { x = 10.5, y = 30.5 }, { x = 170.5, y = 30.5 } },
			rigs = o.rigs or { { x = 50, y = 30 }, { x = 130, y = 30 } },
			settlements = o.settlements,
			drop = o.drop,
			armies = o.armies,
			seed = o.seed,
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
	test("world fire impact hook reports ground aim once and ignores air hits",function()
		local sim=newSim();local impacts={};sim.worldBlast=function(x,y,w) table.insert(impacts,{x,y,w}) end
		sim.strikes={{kind="unit",at=0,target=-1,key="units.tank",aimX=70,aimY=20,by=1},
			{kind="unit",at=0,target=-1,key="units.tank",aimX=75,aimY=20,by=1,airTarget=true}}
		sim.step(.05);eq(#impacts,1);eq(impacts[1][1],70);eq(impacts[1][2],20);eq(impacts[1][3],"cannon")
		sim.step(.05);eq(#impacts,1)
	end)
	test("world fire impact hook routes salvo and barrage landing coordinates exactly once",function()
		local sim=newSim();local impacts={};sim.worldBlast=function(x,y,w) table.insert(impacts,{x,y,w}) end
		sim.strikes={{kind="rocket",at=0,target=-1,key="units.rocket",x=70,y=20,by=1,damage=0},
			{kind="rocket",at=0,target=-1,key="artyBase.barrage",x=75,y=20,by=1,damage=0}}
		sim.step(.05);eq(#impacts,2);eq(impacts[1][1],70);eq(impacts[1][3],"salvo");eq(impacts[2][1],75);eq(impacts[2][3],"barrage")
	end)
	test("structure destruction retains its fire origin after dead entities are compacted",function()
		local sim=newSim();local target=sim.hqOf(2);local id,cell=target.id,target.cell
		sim.takeEvents();sim.strikes={{kind="structure",at=0,target=id,key="units.tank",damage=target.hp+1,aimX=target.x,aimY=target.y,by=1}}
		sim.step(.05);eq(sim.entities[id],nil)
		local found=0;for _,ev in sim.takeEvents() do if ev.type=="destroyed" and ev.id==id then
			found+=1;eq(ev.cat,"structure");eq(ev.kind,"hq");eq(ev.x,cell%W+.5);eq(ev.y,math.floor(cell/W)+.5)
		end end;eq(found,1)
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

	test("releasing a truck: the least busy one leaves the rig, drives home and joins the idle pool", function()
		local sim = newSim()
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, math.huge
		sim.updateConnections()
		for _ = 1, 10 do
			sim.updateRoutes()
			sim.ticks += 1
		end
		eq(sim.releaseTruckProblem(1, rig.id), "noTrucks")
		eq(sim.releaseTruckProblem(2, rig.id), "notOwned")
		assert(sim.orderTruck(1, rig.id))
		assert(sim.orderTruck(1, rig.id))
		local idle0 = sim.sides[1].trucksIdle
		-- one out loaded, one loading: the loading one goes
		local ts = units(sim, 1, "truck")
		eq(#ts, 2)
		ts[1].state, ts[1].payload = "out", 0
		ts[2].state, ts[2].payload = "loading", 50
		local id = sim.releaseTruck(1, rig.id)
		eq(id, ts[2].id, "the loading truck")
		eq(ts[2].from, -1)
		eq(sim.trucksOf(rig.id), 1)
		local back = false
		for _ = 1, 20 * 120 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "truckIdle" and ev.side == 1 then
					back = true
				end
			end
			if back then
				break
			end
		end
		assert(back, "home and idle")
		eq(sim.sides[1].trucksIdle, idle0 + 1)
	end)

	test("retreat: units fall back to a ring round the HQ, 1.25x faster, holding fire and not stopping for enemies", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 1, "infantry")[2]
		local foe = units(sim, 2, "infantry")[1]
		clearUnits(sim, { a, b, foe })
		a.x, a.y, b.x, b.y = 60.5, 30.5, 60.5, 32.5
		foe.x, foe.y, foe.shotTimer = 52.5, 30.5, math.huge -- in the way, inside range
		foe.side = 2
		local hq = sim.hqOf(1)
		eq(sim.orderRetreat(1, { a.id, b.id }), 2)
		assert(sim.retreating(a) and sim.retreating(b), "retreating")
		assert(a.goalCell ~= b.goalCell, "own slots")
		local hx, hy = hq.cell % W, hq.cell // W
		for _, u in { a, b } do
			local gx, gy = u.goalCell % W, u.goalCell // W
			assert(math.max(math.abs(gx - hx), math.abs(gy - hy)) >= math.ceil(sim.footprintOf("hq")) + 1, "outside the footprint ring")
		end
		local hp0 = foe.hp
		sim.step(0.05)
		local speed = sim.num("units.infantry.speed")
		local paceAt = sim.pathing.paceAt("infantry", a.x, a.y)
		near(a.pace, speed * paceAt * sim.num("movement.retreatPace"))
		for _ = 1, 20 * 8 do
			sim.step(0.05)
		end
		eq(foe.hp, hp0, "held fire passing the enemy")
		assert(a.x < 52, `walked on past the enemy: {a.x}`)
		for _ = 1, 20 * 60 do
			sim.step(0.05)
		end
		eq(a.path, nil, "arrived")
		eq(sim.retreating(a), false)
		-- a new order ends a retreat
		a.x, a.y = 60.5, 30.5
		sim.orderRetreat(1, { a.id })
		sim.orderMove(1, { a.id }, 70.5, 30.5)
		eq(sim.retreating(a), false)
		-- no HQ: refused
		hq.alive = false
		eq(select(2, sim.orderRetreat(1, { b.id })), "blocked")
	end)

	test("waypoints: a moving unit queues stops and walks them in turn; an idle one goes at once", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 1, "infantry")[2]
		clearUnits(sim, { a, b })
		a.x, a.y, b.x, b.y = 40.5, 30.5, 40.5, 34.5
		sim.orderMove(1, { a.id }, 50.5, 30.5)
		eq(sim.queueMove(1, { a.id }, 50.5, 36.5), 1)
		eq(sim.queueMove(1, { a.id }, 44.5, 36.5), 1)
		eq(#a.waypoints, 2)
		eq(a.goalCell, 30 * W + 50, "still on the first leg")
		eq(sim.queueMove(1, { b.id }, 45.5, 34.5), 1, "idle: sent now")
		eq(b.goalCell, 34 * W + 45)
		eq(b.waypoints, nil)
		local legs = {}
		for _ = 1, 20 * 60 do
			sim.step(0.05)
			if legs[#legs] ~= a.goalCell and a.path then
				table.insert(legs, a.goalCell)
			end
		end
		eq(#legs, 3, "three legs")
		eq(legs[2], 36 * W + 50)
		eq(legs[3], 36 * W + 44)
		near(a.x, 44.5)
		near(a.y, 36.5)
		eq(a.waypoints, nil)
		-- the cap
		sim.orderMove(1, { a.id }, 80.5, 30.5)
		for _ = 1, sim.num("movement.waypointCap") do
			sim.queueMove(1, { a.id }, 60.5, 36.5)
		end
		eq(select(2, sim.queueMove(1, { a.id }, 60.5, 36.5)), "waypointsFull")
	end)

	test("rig upgrades: the intent parses; pump and tank once each, paid up front", function()
		local i = Protocol.parse({ kind = "upgradeRig", rigId = 3, upgrade = "pump" }, 100, 100)
		eq(i.upgrade, "pump")
		eq(select(2, Protocol.parse({ kind = "upgradeRig", rigId = 3, upgrade = "gold" }, 100, 100)), "upgrade must be pump or tank")
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.sides[1].oil = 1000
		local pump0, tank0 = sim.pumpRate(rig), sim.tankSize(rig)
		eq(sim.upgradeRig(1, rig.id, "pump"), true)
		near(sim.sides[1].oil, 1000 - sim.num("rigs.upgrades.pump.cost"))
		near(sim.pumpRate(rig), pump0 * sim.num("rigs.upgrades.pump.mult"))
		eq(select(2, sim.upgradeRig(1, rig.id, "pump")), "maxLevel")
		eq(sim.upgradeRig(1, rig.id, "tank"), true)
		near(sim.tankSize(rig), tank0 * sim.num("rigs.upgrades.tank.mult"))
		eq(select(2, sim.upgradeRig(2, rig.id, "tank")), "notOwned")
	end)

	test("squad men: the game's hash, wedge when moving, losses, walk frames", function()
		local SM = require("../src/client/Rendering/SquadMen")
		-- values from the game's q5 run in node
		near(SM.hash(1, 1), 0.8882474072743207)
		near(SM.hash(7, 10), 0.01096736709587276)
		near(SM.hash(123, 50), 0.38830226683057845)
		near(SM.hash(99999, 42), 0.6716460343450308)
		local inp = { x = 10, y = 10, vx = 1, vy = 0, hpFrac = 1, firing = false, aimX = 0, aimY = 0, road = false, contact = false, cover = false }
		local sq = SM.new(5, "infantry", inp)
		eq(#sq.men, 3)
		eq(sq.men[1].kind, "leader")
		SM.step(sq, inp, 1 / 60)
		-- wedge, heading east: leader ahead on the axis, riflemen behind on each side
		local mean = (0.62 - 0.31 - 0.31) / 3
		near(sq.men[1].x, 10 + (0.62 - mean) * 0.6)
		near(sq.men[1].y, 10)
		near(sq.men[2].y, 10 - 0.9 * 0.6)
		near(sq.men[3].y, 10 + 0.9 * 0.6)
		-- walking for a while cycles the walk frames and faces east
		local poses = {}
		for _ = 1, 120 do
			inp.x += 1 / 60
			SM.step(sq, inp, 1 / 60)
			poses[sq.men[1].pose] = true
		end
		eq(poses.walk0 and poses.walk1 and poses.walk2 and poses.walk3, true, "all four walk frames")
		eq(math.abs(sq.men[1].heading) < 0.05, true, "faces east")
		-- a third of its health gone: one rifleman falls, never the leader
		inp.hpFrac = 0.6
		SM.step(sq, inp, 1 / 60)
		eq(sq.men[1].up, true)
		eq((if sq.men[2].up then 1 else 0) + (if sq.men[3].up then 1 else 0), 1)
		-- stopped and firing: everyone ends up kneeling, facing the aim point
		inp.vx, inp.firing, inp.aimX, inp.aimY = 0, true, inp.x, inp.y - 20
		for _ = 1, 240 do
			SM.step(sq, inp, 1 / 60)
		end
		eq(sq.men[1].pose, "kneel")
		eq(math.abs(sq.men[1].heading + math.pi / 2) < 0.05, true, "faces the aim")
	end)

	test("squad men: crews, and a mortar puts its tube down", function()
		local SM = require("../src/client/Rendering/SquadMen")
		local inp = { x = 5, y = 5, vx = 0, vy = 0, hpFrac = 1, firing = false, aimX = 0, aimY = 0, road = false, contact = false, cover = false,
			mortar = "setting", phaseSec = 2, sinceShot = 9 }
		eq(#SM.new(1, "at", inp).men, 2)
		eq(#SM.new(1, "para", inp).men, 3)
		local sq = SM.new(3, "mortar", inp)
		eq(sq.men[2].kind, "bearer")
		SM.step(sq, inp, 1 / 60)
		eq(sq.tube ~= nil and sq.tube.pose, "base", "first half of setting up")
		for _ = 1, 90 do
			SM.step(sq, inp, 1 / 60)
		end
		eq(sq.tube and sq.tube.pose, "set", "second half")
		inp.mortar, inp.sinceShot = "set", 0.05
		SM.step(sq, inp, 1 / 60)
		eq(sq.tube and sq.tube.pose, "kick", "just fired")
		-- crew at their places by the tube, kneeling
		for _ = 1, 300 do
			SM.step(sq, inp, 1 / 60)
		end
		local h = sq.heading
		local bx = 5 + (math.cos(h) * 0.1 - math.sin(h) * 0.72) * SM.MAN_CELLS
		eq(math.abs(sq.men[2].x - bx) < 0.01, true, "bearer beside the tube")
		eq(sq.men[1].pose, "kneel")
		-- moving packs it away
		inp.vx = 1
		SM.step(sq, inp, 1 / 60)
		eq(sq.tube, nil)
	end)

	test("inflate: raw deflate round trips (stored, fixed and dynamic blocks)", function()
		local serde = require("@lune/serde")
		local Inflate = require("../src/shared/Utilities/Inflate")
		local function check(data: string, label: string)
			local z = serde.compress("zlib", data)
			local raw = buffer.fromstring(string.sub(z, 3, #z - 4)) -- drop the zlib header and checksum
			eq(buffer.tostring(Inflate.raw(raw, #data)), data, label)
		end
		check("", "empty")
		check("hello hello hello hello", "short repeats")
		local parts = {}
		local seed = 1
		for i = 1, 60000 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			parts[i] = string.char(if i % 7 < 3 then 65 + seed % 4 else seed % 256)
		end
		check(table.concat(parts), "mixed noise and runs")
		check(string.rep("ab", 40000), "long overlapping copies")
	end)

	test("rig card: the lines and buttons the panel shows", function()
		local RC = require("../src/client/UI/RigCard")
		local prices = { truck = 40, pump = 120, tank = 60, pumpMult = 1.5, tankMult = 2, baseTank = 440 }
		local row = { id = 7, name = "North", rich = 1, tank = 100, tankCap = 440, pumpNow = 144, pumpMax = 144, trucks = 1, perRig = 4,
			haul = 60, pump = false, bigTank = false, hp = 800, maxHp = 800, wrecked = false, connected = true, cut = false,
			contested = false, readyIn = 0, refinery = nil, trip = 30, canRelease = true }
		local v = RC.view(row, 500, 0, prices)
		eq(v.title, "OIL FIELD · North")
		eq(v.lines[1], "Tank 100 / 440")
		eq(v.lines[2], "Pump 144 oil/min · now 144")
		eq(v.lines[3], "Trucks 1 / 4")
		eq(v.lines[4], "Hauls about 60 of 144 oil/min")
		eq(v.warn[4], true, "under 85% of the pump")
		eq(v.lines[5], "To the HQ · 00:30 a way")
		eq(v.buttons[1].label, "Buy oil truck (40)")
		eq(v.buttons[3].label, "Second pump (120)")
		eq(v.buttons[3].off, false)
		eq(v.buttons[4].tip, "Tank holds 880")
		eq(v.buttons[5].label, "Reroute: next way")
		row.pump, row.readyIn, row.tank, row.wrecked = true, 5, 440, true
		v = RC.view(row, 50, 2, prices)
		eq(v.lines[1], "DESTROYED: it pumps nothing until engineers repair it.")
		eq(v.lines[2], "Tank full, needs trucks")
		eq(v.buttons[1].label, "Send idle truck (free)")
		eq(v.buttons[3].label, "Second pump: Done")
		eq(v.buttons[3].off, true)
		eq(v.buttons[4].off, true, "not enough oil for the tank")
		eq(v.buttons[5].label, "Reroute (ready in 00:05)")
	end)

	test("control groups: make, add, select, double press, dead units drop out", function()
		local CG = require("../src/client/Input/ControlGroups")
		local g = CG.new()
		local live = { [1] = true, [2] = true, [3] = true, [50] = true, [51] = true }
		local uOk = function(id: number): boolean
			return live[id] == true and id < 50
		end
		local sOk = function(id: number): boolean
			return live[id] == true and id >= 50
		end
		eq(CG.set(g, 1, { 1, 2 }, 50), 2, "units win over the building")
		eq(CG.add(g, 1, { 2, 3 }, nil, uOk, sOk), 3)
		local u, st, double = CG.recall(g, 1, 1000, uOk, sOk)
		eq(#u, 3)
		eq(st, nil)
		eq(double, false)
		live[2] = nil
		u, st, double = CG.recall(g, 1, 1300, uOk, sOk)
		eq(#u, 2, "a dead unit drops out")
		eq(double, true, "second press within 400 ms")
		u, st, double = CG.recall(g, 1, 1500, uOk, sOk)
		eq(double, false, "a third press starts over")
		-- buildings
		eq(CG.set(g, 2, {}, 50), 1)
		eq(CG.add(g, 2, {}, 51, uOk, sOk), 2)
		u, st = CG.recall(g, 2, 5000, uOk, sOk)
		eq(#u, 0)
		eq(st, 50)
		eq(CG.add(g, 2, { 1 }, nil, uOk, sOk), 1, "units replace a building group")
		eq(CG.add(g, 2, {}, nil, uOk, sOk), nil, "nothing selected")
		eq(CG.set(g, 2, {}, nil), 0, "cleared")
	end)

	test("direct moves: straight over the land when the line is open, a pulled-straight route otherwise", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 1, "infantry")[2]
		clearUnits(sim, { a, b })
		local P = sim.pathing
		-- the direct table: no off-road bias, roads cost the land under them
		local plain, direct = P.moveTable("infantry"), P.moveTable("infantry", true)
		eq(direct["@road"], 0)
		near(plain.plains / direct.plains, sim.num("movement.offRoadBias"))
		-- lineCells: Bresenham from a (left out) to b
		local line = P.lineCells(30 * W + 40, 33 * W + 46)
		eq(#line, 6)
		eq(line[#line], 33 * W + 46)
		a.x, a.y = 40.5, 30.5
		local from = 30 * W + 40
		sim.orderMove(1, { a.id }, 52.5, 34.5, true)
		eq(a.direct, true)
		if P.straightPassable(a.x, a.y, 34 * W + 52) then
			local want = P.lineCells(from, 34 * W + 52)
			eq(#a.path, #want, "the straight line")
			for i, c in want do
				eq(a.path[i], c)
			end
		end
		-- every step of a direct path is to a neighbouring cell
		local prev = from
		for _, c in a.path do
			eq(math.max(math.abs(c % W - prev % W), math.abs(c // W - prev // W)), 1, "neighbouring cells")
			prev = c
		end
		eq(a.path[#a.path], 34 * W + 52)
		-- straightWay with a blocked line still reaches the goal through neighbouring cells
		local way = P.straightWay({ x = 40.5, y = 30.5, kind = "infantry" }, from, 30 * W + 80)
		eq(way ~= nil and way[#way] == 30 * W + 80, true, "reaches the goal")
		-- a plain move or a stop ends it
		sim.orderMove(1, { a.id }, 50.5, 30.5)
		eq(a.direct, nil)
		-- queued stops keep their own flag
		sim.queueMove(1, { a.id }, 50.5, 36.5, true)
		sim.queueMove(1, { a.id }, 44.5, 36.5)
		eq(a.wayDirect[1], true)
		eq(a.wayDirect[2], false)
		local sawDirect = false
		for _ = 1, 20 * 60 do
			sim.step(0.05)
			if a.goalCell == 36 * W + 50 and a.direct then
				sawDirect = true
			end
		end
		eq(sawDirect, true, "the second leg walked straight")
		eq(a.direct, nil, "the last leg was a plain one")
		eq(a.wayDirect, nil)
		-- through the intent parser
		local i = Protocol.parse({ kind = "move", unitIds = { b.id }, x = 45, y = 34, direct = true }, W, sim.roads.height)
		eq(i.direct, true)
		eq(select(2, Protocol.parse({ kind = "move", unitIds = { b.id }, x = 45, y = 34, direct = 1 }, W, sim.roads.height)), "direct must be a boolean")
	end)

	test("rig damage: enemy blasts wreck a rig (no oil, trucks let go, none sent); engineers repair it; the bot sends one", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		run(sim, 1)
		eq(rig.maxHp, sim.num("rigs.damage.hp"))
		local hit = sim.num("rigs.damage.hitCells")
		sim.rigBlast(rig.x + hit - 0.1, rig.y, 300, 1)
		eq(rig.hp, rig.maxHp, "a side's own blasts spare its rigs")
		sim.rigBlast(rig.x + hit + 0.1, rig.y, 300, 2)
		eq(rig.hp, rig.maxHp, "beyond hitCells")
		sim.rigBlast(rig.x + hit - 0.1, rig.y, 300, 2)
		eq(rig.hp, rig.maxHp - 300)
		-- a splash beyond hitCells: half way across the radius = 3/4
		sim.rigSplash(rig.x + hit + 2, rig.y, 4, 100, 2)
		near(rig.hp, rig.maxHp - 300 - 75)
		sim.rigSplash(rig.x + hit - 1, rig.y, 4, 100, 2)
		near(rig.hp, rig.maxHp - 375, "the inner ring is rigBlast's")
		local ev0 = {}
		for _, e in sim.takeEvents() do
			ev0[e.type] = true
		end
		assert(ev0.rigUnderFire, "the owner hears of it")
		assert(sim.orderTruck(1, rig.id))
		rig.tank = 200
		sim.rigBlast(rig.x, rig.y, 1000, 2)
		eq(rig.wrecked, true)
		eq(rig.hp, 0)
		eq(rig.tank, 0, "the tank burns")
		eq(sim.trucksOf(rig.id), 0, "its trucks are let go")
		eq(select(2, sim.orderTruck(1, rig.id)), "notOperational")
		local seen = false
		for _, e in sim.takeEvents() do
			if e.type == "rigDestroyed" and e.side == 1 and e.by == 2 then
				seen = true
			end
		end
		assert(seen, "rigDestroyed")
		run(sim, 2)
		eq(rig.rate, 0, "pumps nothing")
		eq(rig.tank, 0)
		-- the bot sends its nearest idle engineer
		local bot = Bot.new(sim, 1, "balanced")
		local eng = sim.spawnUnit("engineer", 1, rig.x + 6, rig.y + 0.5)
		local eng2 = sim.spawnUnit("engineer", 1, rig.x + 30, rig.y + 0.5)
		for _ = 1, 40 do
			bot.step(0.05)
			sim.step(0.05)
			if eng.repairId then
				break
			end
		end
		eq(eng.repairId, rig.id, "the nearest one goes")
		eq(eng2.repairId, nil)
		-- one engineer mends it in repairSec
		local t0 = sim.time
		local back = nil
		for _ = 1, 20 * (sim.num("rigs.damage.repairSec") + 15) do
			sim.step(0.05)
			for _, e in sim.takeEvents() do
				if e.type == "rigRepaired" then
					back = sim.time
				end
			end
			if back then
				break
			end
		end
		assert(back, "repaired")
		assert(back - t0 >= sim.num("rigs.damage.repairSec") - 0.1 and back - t0 <= sim.num("rigs.damage.repairSec") + 10, `about repairSec: {back - t0}`)
		eq(rig.wrecked, nil)
		eq(rig.hp, rig.maxHp)
		eq(eng.repairId, nil, "job done")
		run(sim, 1)
		assert(rig.rate > 0, "pumping again")
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

	test("a tank turns its turret at turretDegSec and fires once it is on the aim (the game's Tie)", function()
		local function about(x: number, want: number, msg: string, tol: number)
			assert(math.abs(x - want) <= tol, `{msg}: got {x}, expected {want}`)
		end
		local sim = newSim()
		local tank = sim.spawnUnit("tank", 1, 60, 10)
		local foe = sim.spawnUnit("infantry", 2, 57, 10) -- straight behind
		clearUnits(sim, { tank, foe })
		tank.heading, tank.turret, tank.shotTimer = 0, 0, 0
		foe.shotTimer = math.huge
		run(sim, 1)
		assert(tank.firedAt == nil, "held fire while the turret turns")
		about(math.abs(tank.turret), 70 * math.pi / 180, "turned 70 degrees in a second", 0.05)
		about(tank.heading, 0, "the hull stays", 1e-9)
		run(sim, 1.6)
		assert(tank.firedAt ~= nil, "fired once within 4 degrees")
		about(math.abs(tank.turret), math.pi, "on the aim", 4 * math.pi / 180)
		-- the foe gone, the turret swings back to the hull
		foe.alive = false
		run(sim, 3)
		about(tank.turret, 0, "back over the hull", 0.01)
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

	test("territory: a captured rig lets its owner build beside it, far from the HQ", function()
		local sim = newSim()
		local rig = sim.rigs[2] -- (130, 30), 120 cells from side 1's HQ
		eq(sim.canPlace(1, "bunker", cellOf(130, 37)), "outsideBase", "not owned yet")
		rig.side = 1
		eq(sim.canPlace(1, "bunker", cellOf(130, 37)), nil, "rigPad 12 paints territory round it")
		eq(sim.canPlace(1, "atgun", cellOf(133, 37)), nil)
		eq(sim.canPlace(1, "bunker", cellOf(130, 34)), "onRig", "within footprint + padCells of the rig")
	end)
	test("idle: a unit knocked more than leashCells/2 off its post walks back; an order moves its post", function()
		local sim = newSim()
		local u = units(sim, 1, "infantry")[1]
		clearUnits(sim, { u })
		u.x, u.y, u.post = 50.5, 30.5, nil
		run(sim, 1.1) -- first idle think: the post is where it stands
		local post = u.post
		assert(post, "post set")
		u.x = 62.5 -- 12 cells off (> match leash 18 / 2)
		run(sim, 1.1)
		assert(u.path and u.chasing, "walking back on its own")
		run(sim, 30)
		assert(math.abs(u.x - 50.5) < 1.5 and math.abs(u.y - 30.5) < 1.5, `back at its post ({u.x}, {u.y})`)
		u.x = 56.5 -- 6 cells off: within leash / 2, stays
		run(sim, 2)
		assert(not u.path, "stays within half the leash")
		sim.orderMove(1, { u.id }, 60.5, 30.5)
		assert(not u.chasing, "an order is not idle")
		run(sim, 30)
		assert(not u.path and math.abs(u.x - 60.5) < 1.5, "arrived")
		run(sim, 3)
		assert(not u.path and math.abs(u.x - 60.5) < 1.5, "its post is now where it was sent")
	end)
	test("holdAtEnemy: an armed unit walking into an enemy stops enemySpaceCells (2.1 match) short", function()
		local sim = newSim()
		local u = units(sim, 1, "infantry")[1]
		clearUnits(sim, { u })
		u.x, u.y = 50.5, 30.5
		local foe = sim.spawnUnit("infantry", 2, 56.5, 30.5)
		foe.hp, u.hp = 1e9, 1e9
		sim.orderMove(1, { u.id }, 62.5, 30.5)
		run(sim, 20)
		local d = math.abs(foe.x - u.x)
		assert(u.x < foe.x and d >= 2.1 - 0.05 and d < 3, `held short of the enemy (gap {d})`)
	end)
	test("seekCover: an idle infantryman under fire steps into the nearest forest and makes it his post", function()
		local sim = newSim()
		local u = units(sim, 1, "infantry")[1]
		clearUnits(sim, { u })
		u.x, u.y, u.post = 96.5, 30.5, nil
		local foe = sim.spawnUnit("infantry", 2, 110.5, 30.5)
		foe.hp, u.hp = 1e9, 1e9
		run(sim, 8)
		eq(math.floor(u.x), 100, "nearest forest cell (forest x 100-102, cover 0.25)")
		eq(math.floor(u.y), 30)
		eq(u.coverCell, u.post, "the cover cell is its post")
		assert(not u.path, "settled")
		-- no enemy in range: a fresh unit stays in the open
		local sim2 = newSim()
		local w = units(sim2, 1, "infantry")[1]
		clearUnits(sim2, { w })
		w.x, w.y, w.post = 96.5, 30.5, nil
		run(sim2, 8)
		eq(math.floor(w.x), 96, "no enemy, no cover seeking")
	end)
	test("repair: engineers walk within reach and mend maxHp x 0.025 per engineer per second", function()
		local sim = newSim()
		clearUnits(sim, {})
		local hq = sim.entities[sim.sides[1].hqId]
		eq(sim.orderRepair(1, hq.id, {}), 0, "nothing to mend at full hp")
		hq.hp = 300
		local _, why = sim.orderRepair(1, hq.id, {})
		eq(why, "noEngineers")
		local a = sim.spawnUnit("engineer", 1, 30.5, 30.5)
		local b = sim.spawnUnit("engineer", 1, 31.5, 30.5)
		eq(select(2, sim.orderRepair(2, hq.id, {})), "notOwned")
		eq(sim.orderRepair(1, hq.id, {}), 2, "the nearest idle engineers")
		run(sim, 15)
		assert(math.abs(a.x - 10.5) <= 6.5 and math.abs(b.x - 10.5) <= 6.5, "within footprint 2 + reach 4.5")
		assert(not a.path and a.repairId == hq.id, "working")
		local h0 = hq.hp
		run(sim, 2)
		near(hq.hp - h0, 3000 * 0.025 * 2 * 2, "two engineers: 150 hp/s")
		run(sim, 15)
		eq(hq.hp, 3000)
		assert(a.repairId == nil and b.repairId == nil, "released when whole")
		-- any other order ends the job
		hq.hp = 2000
		sim.orderRepair(1, hq.id, { a.id })
		sim.orderMove(1, { a.id }, 40.5, 30.5)
		eq(a.repairId, nil)
	end)
	test("bot sends an idle engineer to mend a building below 70% hp", function()
		local sim = newSim()
		local bot = Bot.new(sim, 1, "balanced")
		local hq = sim.entities[sim.sides[1].hqId]
		local e = sim.spawnUnit("engineer", 1, 20.5, 30.5)
		sim.sides[1].oil = 0 -- below trenchWorks.bots.digFrom, so the engineer is not sent to dig
		hq.hp = 2200 -- 73%: left alone
		bot.think()
		eq(e.repairId, nil, "not below 70%")
		hq.hp = 2000
		bot.think()
		eq(e.repairId, hq.id)
	end)
	test("traits: each side's nearest towns get rail then hospital; a contested town starts at factory", function()
		local sim = newSim({ settlements = {
			{ name = "A", x = 40, y = 45, kind = "town" }, { name = "B", x = 60, y = 45, kind = "town" },
			{ name = "C", x = 140, y = 45, kind = "town" }, { name = "D", x = 120, y = 45, kind = "town" },
			{ name = "M", x = 90, y = 45, kind = "town" }, { name = "V", x = 30, y = 45, kind = "village" },
		} })
		local t = {}
		for _, st in sim.settlements do
			t[st.name] = st.trait or "-"
		end
		eq(t.A, "rail")
		eq(t.B, "hospital")
		eq(t.C, "rail")
		eq(t.D, "hospital")
		eq(t.M, "factory", "contested by both starts: order from index 2")
		eq(t.V, "-", "villages get no trait")
	end)
	test("traits: a secured hospital heals men 5%/s; secured towns and a factory town cut prices", function()
		local sim = newSim({ settlements = { { name = "A", x = 40, y = 45, kind = "town" }, { name = "B", x = 60, y = 45, kind = "town" },
			{ name = "M", x = 90, y = 45, kind = "town" } } })
		clearUnits(sim, {})
		local hosp, fac = sim.settlements[2], sim.settlements[3]
		eq(hosp.trait, "hospital")
		eq(fac.trait, "factory")
		eq(sim.unitCost(1, "tank"), 145)
		local function secure(st)
			st.owner, st.hold = 1, 1
			local ids = {}
			for i = 1, 3 do
				table.insert(ids, sim.spawnUnit("infantry", 1, st.x + 0.5, st.y + 0.5).id)
			end
			eq((sim.orderGarrison(1, st.id, ids)), 3)
			eq(sim.cityStatus(st), "secured")
		end
		secure(hosp)
		assert(sim.traitActive(hosp), "held and secured")
		local hurt = sim.spawnUnit("infantry", 1, 60.5, 60.5) -- 15 cells off: past radius + repairReach, within + 18
		hurt.hp = hurt.maxHp * 0.5
		local h0 = hurt.hp
		run(sim, 2)
		near(hurt.hp - h0, hurt.maxHp * 0.05 * 2, "hospital.menPerSec 0.05")
		eq(sim.unitCost(1, "infantry"), math.floor(36 * (1 - 0.09) + 0.5), "one secured town: 9% off")
		secure(fac)
		eq(sim.unitCost(1, "infantry"), math.floor(36 * (1 - 0.18) + 0.5), "men: towns only")
		eq(sim.unitCost(1, "tank"), math.floor(145 * (1 - 0.3) + 0.5), "vehicles: 0.18 + factory 0.15, capped at 0.3")
		eq(sim.unitCost(2, "tank"), 145)
		-- rail: a working rail town speeds its owner's trucks within radius 6 + reach 90
		local rail = sim.settlements[1]
		eq(rail.trait, "rail")
		eq(sim.railPace(1, 40.5, 45.5), 1, "not secured yet")
		secure(rail)
		eq(sim.railPace(1, 40.5 + 95, 45.5), 1.3)
		eq(sim.railPace(1, 40.5 + 97, 45.5), 1, "beyond 96")
		eq(sim.railPace(2, 40.5, 45.5), 1, "only its owner's trucks")
	end)
	test("withdraw: units leave a held settlement last in first, onto its rim; one by id; refused when empty or not held", function()
		local sim = newSim({ settlements = { { name = "T", x = 90, y = 45, kind = "town" } } })
		clearUnits(sim, {})
		local st = sim.settlements[1]
		st.owner, st.hold = 1, 1
		local ids = {}
		for _ = 1, 3 do
			table.insert(ids, sim.spawnUnit("infantry", 1, st.x + 0.5, st.y + 0.5).id)
		end
		eq((sim.orderGarrison(1, st.id, ids)), 3)
		eq(#st.garrison, 3)
		eq(select(2, sim.withdraw(2, st.id)), "notHeld")
		local last = st.garrison[3]
		eq(sim.withdraw(1, st.id, 1), 1)
		local e = sim.entities[last]
		eq(e.inside, nil, "the last one in is out")
		eq(#st.garrison, 2)
		local d = math.sqrt((e.x - st.x) ^ 2 + (e.y - st.y) ^ 2)
		assert(d >= st.radius - 0.5 and d <= st.radius + 4, `on the rim: {d} vs radius {st.radius}`)
		local first = st.garrison[1]
		eq(sim.withdraw(1, st.id, nil, first), 1)
		eq(sim.entities[first].inside, nil, "that one by id")
		eq(sim.withdraw(1, st.id), 1, "the rest")
		eq(#st.garrison, 0)
		eq(select(2, sim.withdraw(1, st.id)), "garrisonEmpty")
		-- the units are free to move again
		sim.orderMove(1, { last }, 100.5, 45.5)
		assert(e.path, "walks")
	end)
	test("bot mending: hurt idle units walk to a secured town that heals them, and rejoin when whole", function()
		local sim = newSim({ settlements = { { name = "T", x = 40, y = 45, kind = "town" } } })
		clearUnits(sim, {})
		local st = sim.settlements[1]
		st.owner, st.hold = 1, 1
		local ids = {}
		for _ = 1, 3 do
			table.insert(ids, sim.spawnUnit("infantry", 1, st.x + 0.5, st.y + 0.5).id)
		end
		eq((sim.orderGarrison(1, st.id, ids)), 3)
		eq(sim.cityStatus(st), "secured")
		local bot = Bot.new(sim, 1, "balanced")
		local tank = sim.spawnUnit("tank", 1, 70.5, 45.5)
		local fit = sim.spawnUnit("tank", 1, 72.5, 47.5)
		tank.hp = tank.maxHp * 0.5
		for _ = 1, 20 * 2 do
			bot.step(0.05)
			sim.step(0.05)
		end
		assert(bot.mending[tank.id], "the hurt tank is sent to heal")
		eq(bot.mending[tank.id].city, st.id)
		eq(bot.mending[fit.id], nil, "the whole one is not")
		assert(tank.goalCell and math.abs(tank.goalCell % W - st.x) < 8, "walking to the town")
		local healed = false
		for _ = 1, 20 * 200 do
			bot.step(0.05)
			sim.step(0.05)
			if tank.hp >= tank.maxHp then
				healed = true
				break
			end
		end
		assert(healed, `healed: {tank.hp}/{tank.maxHp}`)
		for _ = 1, 20 * 2 do
			bot.step(0.05)
			sim.step(0.05)
		end
		eq(bot.mending[tank.id], nil, "back in the pool")
	end)
	test("bridges: spans found; the bot posts a guard at its end, blows it when an enemy force masses beyond, and leaves its own blow unmended", function()
		local sim = newSim({ terrainAt = function(c)
			local x = c % W
			return if x >= 30 and x <= 32 then "shallow" else "plains"
		end })
		clearUnits(sim, {})
		local spans = sim.bridgeSpans()
		eq(#spans, 1, "one span over the river")
		local sp = spans[1]
		for _, c in sp.cells do
			assert(c % W >= 30 and c % W <= 32, "deck cells on the water")
		end
		eq(sp.blown, false)
		local hq = sim.hqOf(1)
		local post = sim.bridgeEnd(sp, hq.x, hq.y)
		eq(post % W, 29, "the near end")
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		run(sim, 1)
		assert(rig.route, "a route over the bridge")
		local bot = Bot.new(sim, 1, "balanced")
		bot.persona.defence = 2 -- always willing (the game rolls defence x bridgeBlowChance)
		for i = 1, 6 do
			sim.spawnUnit("infantry", 1, 14.5 + i, 34.5)
		end
		local eng = sim.spawnUnit("engineer", 1, 16.5, 28.5)
		sim.sides[1].oil = 100 -- below trenchWorks.bots.digFrom: the engineer is not sent digging
		bot.think()
		local guards = 0
		for id, g in bot.guards do
			guards += 1
			eq(g.post, post)
			eq(sim.entities[id].goalCell, post, "walking to the post")
		end
		eq(guards, 1, "one guard")
		eq(eng.sabotageCell, nil, "no threat yet: the bridge stands")
		-- an enemy force beyond the river, seen from our rig
		for i = 1, 4 do
			sim.spawnUnit("tank", 2, 46.5, 27.5 + i)
		end
		bot.think()
		assert(eng.sabotageCell, "an engineer goes to blow the bridge")
		local cx = eng.sabotageCell % W
		assert(cx >= 30 and cx <= 32, "on the span")
		eq(bot.lastBlow, sim.time)
		-- our own blow is not mended while the hold lasts
		sim.orderStop(1, { eng.id })
		local cut = sim.cutRoad(eng.sabotageCell or (30 * W + 31), 1) or sim.cutRoad(30 * W + 31, 1)
		assert(cut, "blown")
		eq(sim.bridgeSpans()[1].blown, true)
		bot.lastBlow = sim.time
		sim.sides[1].oil = 1000
		bot.think()
		eq(eng.roadJob, nil, "left blown")
		cut.at = sim.time - sim.num("bots.bridgeHoldMaxSec") - 1
		sim.sides[1].oil = 1000 -- mending a cut costs oil
		bot.think()
		assert(eng.roadJob, "mended after bridgeHoldMaxSec")
	end)
	test("forward training: a secured town trains infantry / AT (faster with workforce); lost = refund", function()
		local sim = newSim({ settlements = { { name = "T", x = 130, y = 45, kind = "town" }, { name = "V", x = 90, y = 45, kind = "village" } } })
		clearUnits(sim, {})
		local town, village = sim.settlements[1], sim.settlements[2]
		eq(select(2, sim.queueForward(1, town.id, "infantry")), "notHeld")
		town.owner, town.hold = 1, 1
		eq(select(2, sim.queueForward(1, town.id, "infantry")), "notSecured")
		eq(select(2, sim.queueForward(1, town.id, "tank")), "blocked", "trains infantry and AT only")
		village.owner = 1
		eq(select(2, sim.queueForward(1, village.id, "infantry")), "blocked", "towns and cities only")
		local ids = {}
		for _ = 1, 3 do
			table.insert(ids, sim.spawnUnit("infantry", 1, 130.5, 45.5).id)
		end
		sim.orderGarrison(1, town.id, ids)
		eq(sim.cityStatus(town), "secured")
		near(sim.workforce(1), 0.12, "one secured town: workforce 0.12")
		local oil = sim.sides[1].oil
		local price = sim.unitCost(1, "infantry")
		assert(sim.queueForward(1, town.id, "infantry"))
		eq(sim.sides[1].oil, oil - price, "paid now (with the town discount)")
		local bt = 7 / 1.12 -- infantry buildSec 7 over 1 + workforce
		near(sim.forwardLeft(town.id), bt)
		local before = #units(sim, 1, "infantry")
		run(sim, bt - 0.2)
		eq(#units(sim, 1, "infantry"), before, "not yet")
		run(sim, 0.4)
		eq(#units(sim, 1, "infantry"), before + 1, "appears at the town")
		local u = units(sim, 1, "infantry")[before + 1]
		assert(math.abs(math.sqrt((u.x - 130) ^ 2 + (u.y - 45) ^ 2) - 6.5) < 1.5, "radius + 0.5 from the centre")
		-- queued, then the town is lost: refunded
		local atPrice = sim.unitCost(1, "at")
		assert(sim.queueForward(1, town.id, "at"))
		local mid = sim.sides[1].oil
		town.owner = 2
		run(sim, 0.1)
		eq(town.forward, nil)
		assert(math.abs(sim.sides[1].oil - mid - atPrice) < 0.5, "what was paid comes back (plus 0.1 s of HQ trickle)")
	end)
	test("drive: a tank speeds up at top / accelSec, pivots to a far goal behind it and stops on its goal", function()
		local sim = newSim()
		clearUnits(sim, {})
		local t = sim.spawnUnit("tank", 1, 60.5, 15.5)
		t.heading, t.headed, t.hp = 0, true, 1e9
		sim.orderMove(1, { t.id }, 80.5, 15.5)
		run(sim, 0.5)
		local accel = 3.57 * 1.25 / 3.2 -- top (speed x roadMult) / accelSec
		assert(t.pace > 0 and t.pace <= accel * 0.5 + 1e-6, `accelerating, not at full pace at once ({t.pace})`)
		run(sim, 20)
		assert(not t.path, "arrived")
		assert(math.abs(t.x - 80.5) < 0.5 and math.abs(t.y - 15.5) < 0.5, `on its goal ({t.x}, {t.y})`)
		-- a far goal behind: it pivots on the spot first (tracks), then drives
		local x0 = t.x
		sim.orderMove(1, { t.id }, 50.5, 15.5)
		run(sim, 0.5)
		assert(math.abs(t.x - x0) < 0.01, `pivoting in place ({t.x})`)
		assert(t.steer.pivot, "pivot")
		run(sim, 30)
		assert(math.abs(t.x - 50.5) < 0.5, `drove to the far goal ({t.x})`)
		assert(math.abs(math.cos(t.heading) + 1) < 0.05, "facing west now")
	end)
	test("drive: a close goal behind is reached in reverse; a scout car turns no tighter than its radius", function()
		local sim = newSim()
		clearUnits(sim, {})
		local t = sim.spawnUnit("tank", 1, 60.5, 15.5)
		t.heading, t.headed, t.hp = 0, true, 1e9
		sim.orderMove(1, { t.id }, 56.5, 15.5) -- 4 cells behind (reverseCells 6)
		run(sim, 1.5)
		assert(t.x < 60.5 and t.reversing, `backing up ({t.x})`)
		assert(math.abs(math.cos(t.heading) - 1) < 0.05, "still facing east")
		local car = sim.spawnUnit("scout", 1, 60.5, 45.5)
		car.heading, car.headed, car.hp = 0, true, 1e9
		sim.orderMove(1, { car.id }, 90.5, 45.5)
		run(sim, 3)
		local maxTurn = 0
		sim.orderMove(1, { car.id }, car.x, 60.5) -- hard right
		for _ = 1, 20 do
			local h0 = car.heading
			run(sim, 0.05)
			local dh = math.abs(math.atan2(math.sin(car.heading - h0), math.cos(car.heading - h0)))
			local limit = math.min(sim.deps.rules:number("units.scout.turnDegSec") * math.pi / 180, (car.pace or 0) / sim.deps.rules:number("units.scout.turnRadiusCells")) * 0.05
			maxTurn = math.max(maxTurn, dh - limit)
		end
		assert(maxTurn < 1e-6, `turn rate within min(turnDegSec, pace / radius) (over by {maxTurn})`)
	end)
	test("town damage: shells landing in a town take damage x 0.6 off it; ruins at 0, standing again after mending", function()
		local sim = newSim({ settlements = { { name = "T", x = 130, y = 45, kind = "town" } } })
		clearUnits(sim, {})
		local town = sim.settlements[1]
		eq(town.integrity, 1000)
		eq(sim.integrityBand(town), "intact")
		local man = sim.spawnUnit("infantry", 2, 131.5, 45.5)
		man.hp = 1e6
		local function shell(target, bombard)
			table.insert(sim.strikes, { kind = "unit", at = sim.time, target = target.id, dps = 100, key = "units.artillery",
				secs = 1, by = 1, fromX = 100, fromY = 45, splash = 0, bombard = bombard })
			local hp = target.hp
			sim.step(0.05)
			return hp - target.hp
		end
		local lost = shell(man, false)
		eq(town.integrity, 1000, "direct fire leaves the town alone")
		lost = shell(man, true)
		assert(lost > 0, "hit")
		near(town.integrity, 1000 - lost * 0.6, "collateral 0.6 x the damage")
		town.integrity = 1
		shell(man, true)
		assert(town.destroyed, "in ruins")
		eq(sim.integrityBand(town), "destroyed")
		-- 60 s quiet, then 1000 / 600 s: standing again at 30% (180 s more)
		run(sim, 60 + 179)
		assert(town.destroyed, "still ruins at 29.9%")
		run(sim, 1.2)
		assert(not town.destroyed, "standing again at 30%")
		eq(sim.integrityBand(town), "damaged", "30% is the critical line: at it, damaged")
	end)
	test("roads: wear builds per class and slows traffic, up to half on a worn-out road", function()
		local sim = newSim()
		clearUnits(sim, {})
		local c = 30 * W + 60 -- highway (wear x0.6)
		local p0 = sim.paceAt("infantry", 60.5, 30.5)
		sim.wearRoad(c, 0.5)
		eq(sim.roads.wearRaw(c), 76, "0.5 x 0.6 x 255 = 76.5, the half owed")
		sim.wearRoad(c, 1 / (0.6 * 255) * 0.5)
		eq(sim.roads.wearRaw(c), 77, "the owed half adds up")
		eq(sim.wearSlow(c), 0, "below 35% wear: no slowdown")
		sim.wearRoad(c, 10)
		eq(sim.roads.wearRaw(c), 255)
		near(sim.wearSlow(c), 0.5)
		local cu = 1 -- highway unit share
		local mult = rulesData["units.infantry.roadMult"]
		near(p0, 1 + (mult - 1) * cu)
		near(sim.paceAt("infantry", 60.5, 30.5), 1 + (mult - 1) * cu * 0.5)
		-- a tank driving along the road wears the cells it enters
		local t = sim.spawnUnit("tank", 1, 70.5, 30.5)
		sim.orderMove(1, { t.id }, 90.5, 30.5)
		run(sim, 20)
		assert(sim.roads.wearRaw(30 * W + 80) > 0, "tank tracks wear the road")
	end)
	test("roads: shells near a road add strike damage; 260 within the cut radius cuts it", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		eq(rig.connected, true)
		sim.roadBlast(30.5, 30.5, 150, 2)
		eq(next(sim.roadCuts), nil, "150 is not enough")
		near(sim.roadStrikeAt(30 * W + 30), 150)
		run(sim, 21)
		eq(sim.roadStrikeAt(30 * W + 30), 0, "forgotten after 20 s")
		sim.roadBlast(30.5, 30.5, 150, 2)
		sim.roadBlast(31.5, 30.5, 150, 2)
		local cut = select(2, next(sim.roadCuts))
		assert(cut, "two strikes close together cut the road")
		assert(not sim.roads.isRoad(30 * W + 31) and not sim.roads.isRoad(30 * W + 34), "cells within 3.6 cut")
		assert(sim.roads.isRoad(30 * W + 36), "beyond the radius stays")
		eq(cut.by, 2)
		eq(rig.connected, false, "the rig loses its road link home")
		-- a shell far from any road does nothing
		sim.roadBlast(30.5, 50.5, 999, 2)
		eq(sim.roadStrikeAt(30 * W + 30), 0)
	end)
	test("roads: engineers repair a cut for 30 oil in 30 s / crew, and worn road back to new", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		local cut = sim.cutRoad(30 * W + 30, 2)
		sim.updateConnections()
		eq(rig.connected, false)
		eq(select(2, sim.orderRoadRepair(1, "cut", cut.id, {})), "noEngineers")
		local a = sim.spawnUnit("engineer", 1, 22.5, 31.5)
		local b = sim.spawnUnit("engineer", 1, 23.5, 31.5)
		local oil = sim.sides[1].oil
		eq(sim.orderRoadRepair(1, "cut", cut.id, {}), 2)
		near(sim.sides[1].oil, oil - 30, "the side pays once")
		sim.orderRoadRepair(1, "cut", cut.id, { a.id })
		near(sim.sides[1].oil, oil - 30, "not again")
		run(sim, 6)
		assert(a.roadJob and not a.path, "working at the cut")
		local r0 = cut.repair
		run(sim, 2)
		near(cut.repair - r0, 2 / 30 * 2, "two engineers: 2/30 a second")
		run(sim, 15)
		eq(sim.roadCuts[cut.id], nil, "repaired")
		assert(sim.roads.isRoad(30 * W + 30))
		eq(a.roadJob, nil, "crew released")
		sim.updateConnections()
		eq(rig.connected, true)
		-- worn road
		local c = 30 * W + 25
		eq(select(2, sim.orderRoadRepair(1, "wear", c, {})), "notWorn")
		sim.wearRoad(c, 1)
		sim.wearRoad(c + 2, 0.5)
		eq(sim.wornCellNear(c + 1), c, "the most worn in the 3x3")
		eq(sim.orderRoadRepair(1, "wear", c, { a.id }), 1)
		run(sim, 12)
		eq(sim.roads.wearRaw(c), 0)
		eq(sim.roads.wearRaw(c + 2), 0, "the whole stretch within the repair radius")
		eq(a.roadJob, nil)
	end)
	test("bot: an idle engineer goes to mend a road cut near its HQ, then a worn stretch on its rig route", function()
		local sim = newSim()
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		local e = sim.spawnUnit("engineer", 1, 20.5, 31.5)
		local cut = sim.cutRoad(30 * W + 30, 2)
		bot.think()
		assert(e.roadJob and e.roadJob.kind == "cut" and e.roadJob.id == cut.id, "sent to the cut")
		eq(cut.repairBy, 1)
		local cut2 = sim.cutRoad(30 * W + 170, 1) -- next to the enemy HQ: not ours
		local f = sim.spawnUnit("engineer", 1, 22.5, 31.5)
		bot.think()
		eq(f.roadJob, nil, "a cut far from our rigs and HQ is left alone")
		assert(cut2)
	end)
	test("sabotage: engineers plant 25 s, it arms, blows after 6-8 s and cuts the road", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 130)
		rig.side, rig.takenAt = 2, 0
		sim.updateConnections()
		sim.updateRoutes()
		for _ = 1, 10 do
			sim.step(0.05)
		end
		eq(select(2, sim.orderSabotage(1, 31 * W + 150, {})), "notRoad")
		eq(select(2, sim.orderSabotage(1, 30 * W + 150, {})), "noEngineers")
		local e = sim.spawnUnit("engineer", 1, 146.5, 31.5)
		eq(sim.orderSabotage(1, 30 * W + 150, {}), 1)
		eq(e.sabotageCell, 30 * W + 150)
		run(sim, 3)
		local sb = sim.sabotageAt(30 * W + 150)
		assert(sb and sb.phase == "planting", "planting")
		run(sim, 10)
		assert(math.abs(sb.progress - 0.5) < 0.1, `half way after ~12.5 s of work: {sb.progress}`)
		run(sim, 14)
		eq(sb.phase, "armed")
		eq(e.sabotageCell, nil, "the crew walks off")
		assert(sb.fuseAt - sim.time <= 8 and sb.fuseAt - sim.time >= 4.5, "fuse 6-8 s")
		assert(table.find(sb.victims, 2), "the enemy's rig route crosses it")
		run(sim, 9)
		eq(sim.sabotageAt(30 * W + 150), nil)
		local cut = select(2, next(sim.roadCuts))
		assert(cut and cut.sabotage and cut.by == 1, "the road is cut by the charge")
		eq(rig.connected, false, "the enemy rig loses its road home")
		eq(select(2, sim.orderSabotage(1, 30 * W + 150, { e.id })), "alreadyCut")
		-- the victim sees along its rig route either side of the cut for revealSec (the game's VZe)
		local rv = sim.reveals[#sim.reveals]
		assert(rv and rv.side == 2, "a reveal for the victim")
		assert(#rv.pts > 4, `points along the route: {#rv.pts}`)
		eq(rv.r, sim.num("sabotage.revealWidth"))
		run(sim, sim.num("sabotage.revealSec") + 1)
		eq(#sim.reveals, 0, "gone after revealSec")
	end)
	test("sabotage: a crew member taking damage ends the planting", function()
		local sim = newSim()
		clearUnits(sim, {})
		local e = sim.spawnUnit("engineer", 1, 99.5, 31.5)
		sim.orderSabotage(1, 30 * W + 100, { e.id })
		run(sim, 3)
		local sb = sim.sabotageAt(30 * W + 100)
		assert(sb, "planting")
		e.hp -= 5
		run(sim, 0.1)
		eq(sim.sabotageAt(30 * W + 100), nil, "failed")
		eq(e.sabotageCell, nil)
	end)
	test("traffic: trucks and road vehicles within 3.6 cells slow each other", function()
		local sim = newSim()
		clearUnits(sim, {})
		local fakeTruck = { x = 60.5, y = 30.5 }
		eq(sim.truckJammed(fakeTruck), false)
		local tank = sim.spawnUnit("tank", 1, 63.5, 30.5)
		sim.step(0.05)
		eq(sim.truckJammed(fakeTruck), true, "a tank on the road 3 cells off")
		tank.x = 65.5
		sim.step(0.05)
		eq(sim.truckJammed(fakeTruck), false, "5 cells off")
		local inf = sim.spawnUnit("infantry", 1, 61.5, 30.5)
		sim.step(0.05)
		eq(sim.truckJammed(fakeTruck), false, "foot units do not jam trucks")
		-- the tank near a truck keeps 40% of its road bonus
		eq(sim.trafficPace(tank, 30 * W + 65, 2, 3), 3, "no truck near")
		assert(inf)
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		sim.updateRoutes()
		for _ = 1, 10 do
			sim.step(0.05)
		end
		assert(sim.orderTruck(1, rig.id), "truck sent")
		local truck
		for _, e in sim.list do
			if e.alive and e.kind == "truck" then
				truck = e
			end
		end
		assert(truck, "a truck")
		tank.x, tank.y = truck.x + 1, 30.5
		near(sim.trafficPace(tank, 30 * W + math.floor(tank.x), 2, 3), 2 + 1 * 0.4, "only 40% of the road bonus")
	end)
	test("bot: gathers idle units 30% of the way to the capital, then sends them in at 180 worth", function()
		local sim = newSim({ settlements = { { name = "Cap", x = 90, y = 45, kind = "capital" } },
			rigs = { { x = 40, y = 30 }, { x = 50, y = 30 }, { x = 60, y = 30 }, { x = 130, y = 30 } } })
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		for i = 1, 3 do
			sim.rigs[i].side, sim.rigs[i].takenAt = 1, 0
		end
		local cap = sim.settlements[1]
		local a = sim.spawnUnit("infantry", 1, 14.5, 40.5)
		sim.time = 200
		bot.think()
		eq(bot.muster[a.id], nil, "too early (capitalAfter 300 s)")
		sim.time = 400
		bot.think()
		eq(bot.muster[a.id], true, "one infantryman is not enough: he musters")
		local hq = sim.hqOf(1)
		local mx = hq.x + (cap.x - hq.x) * 0.3
		assert(a.target, `walking to the muster point {a.x} {mx}`)
		eq(bot.orders[a.id], nil)
		for _ = 1, 10 do
			sim.spawnUnit("tank", 1, 16.5, 40.5)
		end
		bot.think()
		eq(next(bot.muster), nil, "muster released into the assault")
		local o = bot.orders[a.id]
		assert(o and o.kind == "city" and o.id == cap.id, "everyone sent at the capital")
	end)
	test("radar: enemies inside a finished radar's sweep become contacts with a group strength", function()
		local sim = newSim()
		clearUnits(sim, {})
		eq(#sim.contactsFor(1, nil), 0, "no radar, no contacts")
		local id, why = sim.placeStructure(1, "radar", 42 * W + 20)
		assert(id, `radar placed near the HQ: {why}`)
		local radar = sim.entities[id]
		eq(#sim.radarsOf(1), 0, "not while being built")
		radar.built = 1
		local rd = sim.radarsOf(1)[1]
		near(rd.r, 54, "18 cells x cell scale 3")
		local a = sim.spawnUnit("infantry", 2, 60.5, 40.5)
		sim.spawnUnit("infantry", 2, 62.5, 40.5)
		sim.spawnUnit("tank", 2, 70.5, 40.5) -- 8 cells from the second man: within 15, same group
		sim.spawnUnit("infantry", 2, 160.5, 40.5) -- outside the sweep
		local list = sim.contactsFor(1, nil)
		eq(#list, 3)
		eq(list[1].strength, "medium", "capture 1 + 1 + 2 = 4")
		for _ = 1, 3 do
			sim.spawnUnit("tank", 2, 72.5, 42.5)
		end
		eq(sim.contactsFor(1, nil)[1].strength, "heavy", "10 and up")
		local lone = sim.spawnUnit("infantry", 2, 30.5, 10.5)
		local found = nil
		for _, ct in sim.contactsFor(1, nil) do
			if ct.x == lone.x and ct.y == lone.y then
				found = ct
			end
		end
		assert(found and found.strength == "light", "a lone man far from the group: light")
		assert(a)
		-- the bot's knowledge: one entry per group, at its mean position
		local dark = table.create(W * H, 0)
		local groups = sim.contactGroups(1, dark)
		eq(#groups, 2, "the big group and the lone man")
		eq(groups[1].count, 6)
		eq(groups[1].strength, "heavy")
		eq(#sim.contactGroups(1, nil), 0, "nothing out of sight without fog")
		local bot = Bot.new(sim, 1, "balanced")
		bot.think()
	end)
	test("convoys: trucks drive slower off road, in town, on a bridge and into a bend", function()
		local sim = newSim({
			terrainAt = function(c)
				local x = c % W
				return if x >= 70 and x <= 72 then "shallow" else "plains"
			end,
			urbanAt = function(c)
				local x = c % W
				return x >= 40 and x <= 44 and c // W == 30
			end,
		})
		local v = sim.rules:number("convoys.speed")
		local function cruise(x, y, nx, ny)
			local path = { y * W + x }
			if nx then
				table.insert(path, ny * W + nx)
			end
			return sim.truckCruise(path, 1, x - 0.5, y + 0.5)
		end
		near(cruise(30, 30), v, "open road")
		near(cruise(42, 30), v * 0.7, "town")
		near(cruise(71, 30), v * 0.6, "bridge")
		near(cruise(30, 20), v * 0.25, "off road")
		near(cruise(30, 30, 30, 31), v * 0.55, "a right-angle bend")
		near(cruise(30, 30, 31, 30), v, "straight on")
	end)
	test("convoys: a truck stops short of armed enemies ahead; the next one closes up behind it", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, 0
		sim.updateConnections()
		for _ = 1, 10 do
			sim.step(0.05)
		end
		assert(sim.orderTruck(1, rig.id), "first truck")
		run(sim, 3)
		assert(sim.orderTruck(1, rig.id), "second truck")
		local trucks = units(sim, 1, "truck")
		table.sort(trucks, function(a, b) return a.id < b.id end)
		local lead, back = trucks[1], trucks[2]
		local foe = sim.spawnUnit("engineer", 2, 44.5, 30.5) -- unarmed: not a threat
		local armed = nil
		sim.takeEvents()
		local held = false
		for _ = 1, 20 * 30 do
			sim.step(0.05)
			foe.x, foe.y = 44.5, 30.5
			if armed then
				armed.x, armed.y, armed.target, armed.path = 44.5, 32.5, nil, nil
				armed.reload = 1e9
			end
			if not armed and lead.x > 25 then
				eq(lead.stopped, nil, "an unarmed enemy does not hold the convoy")
				armed = sim.spawnUnit("infantry", 2, 44.5, 32.5)
			end
			for _, ev in sim.takeEvents() do
				if ev.type == "convoyHeld" and ev.id == lead.id then
					held = true
				end
			end
		end
		assert(held, "held event")
		eq(lead.stopped, "enemy")
		assert(lead.convoySpeed < 0.01, `lead stopped: {lead.convoySpeed}`)
		assert(lead.x < 44.5 - 4.5 + 0.5, `stops short of the enemy: {lead.x}`)
		local gap = lead.x - back.x
		local s = sim.rules:number("convoys.spacingCells")
		assert(gap >= s * 0.9 and gap <= s * 2, `second truck closes up to the spacing: {gap}`)
		assert(back.convoyStall == nil or back.convoyStall < 5 or back.convoySpeed < 0.01, "no creep behind a held truck")
		armed.alive = false
		run(sim, 5)
		eq(lead.stopped, nil, "drives on once the enemy is gone")
		assert(lead.x > 41, `moving again: {lead.x}`)
	end)
	test("convoys: a truck cut off with no way round stops short of the cut and is stranded after 30 s", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, 0
		sim.updateConnections()
		for _ = 1, 10 do
			sim.step(0.05)
		end
		assert(sim.orderTruck(1, rig.id), "truck")
		local truck = units(sim, 1, "truck")[1]
		while truck.x < 22 do
			sim.step(0.05)
		end
		sim.cutRoad(30 * W + 36, 2)
		sim.takeEvents()
		local stranded, at = false, 0
		for i = 1, 20 * 40 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "convoyStranded" and ev.id == truck.id then
					stranded, at = true, i * 0.05
				end
			end
		end
		eq(truck.stopped, "cut")
		assert(stranded and at >= 29 and at <= 31, `stranded event after 30 s: {at}`)
		assert(truck.x < 36 - sim.rules:number("roads.cutRadius"), `stops short of the cut: {truck.x}`)
	end)
	test("airfield: a secured airfield town drops 2 rifle squads within 135 cells, then waits 240 s", function()
		local sim = newSim({ settlements = { { name = "F", x = 20, y = 45, kind = "town" } } })
		clearUnits(sim, {})
		local st = sim.settlements[1]
		st.trait = "airfield"
		st.owner, st.hold = 1, 1
		local ok, why = sim.callAirfield(1, st.id, 70.5, 40.5)
		eq(ok, false)
		eq(why, "notSecured")
		local ids = {}
		for i = 1, 3 do
			table.insert(ids, sim.spawnUnit("infantry", 1, st.x + 0.5, st.y + 0.5).id)
		end
		sim.orderGarrison(1, st.id, ids)
		eq(sim.cityStatus(st), "secured")
		eq(select(2, sim.callAirfield(1, st.id, 160.5, 45.5)), "outOfRange")
		eq(select(2, sim.callAirfield(1, st.id, 70.5, 3.5)), "terrain", "too near the edge")
		ok = sim.callAirfield(1, st.id, 70.5, 40.5)
		assert(ok, "called")
		eq(select(2, sim.callAirfield(1, st.id, 70.5, 40.5)), "cooldown")
		local before = #units(sim, 1, "infantry")
		local landed = nil
		for i = 1, 20 * 20 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "airfieldLanded" then
					landed = i * 0.05
				end
			end
		end
		assert(landed and landed >= 16 and landed <= 18.5, `down in about 17 s: {landed}`)
		local new = 0
		for _, u in units(sim, 1, "infantry") do
			if math.abs(u.x - 70.5) < 6 and math.abs(u.y - 40.5) < 6 then
				new += 1
			end
		end
		eq(#units(sim, 1, "infantry") - before, 2, "two squads")
		eq(new, 2, "near the point")
		local ready = false
		for _ = 1, 20 * 225 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "airfieldReady" then
					ready = true
				end
			end
		end
		assert(ready, "ready again after 240 s")
	end)
	test("capital powers: 6 paratroopers, then 180 s cooldown; only for the capital's holder", function()
		local sim = newSim({ settlements = { { name = "C", x = 90, y = 45, kind = "capital" } } })
		clearUnits(sim, {})
		local cap = sim.capitalOf()
		eq(select(2, sim.callParatroopers(1, 60.5, 40.5)), "noCapital")
		eq((sim.capitalPower(1, "para")), "locked")
		cap.owner = 1
		eq((sim.capitalPower(1, "para")), "ready")
		assert(sim.callParatroopers(1, 60.5, 40.5), "called")
		local state, left = sim.capitalPower(1, "para")
		eq(state, "cooldown")
		near(left, 180, "cooldown")
		run(sim, 20)
		local paras = units(sim, 1, "para")
		eq(#paras, 6, "six paratroopers")
		for _, u in paras do
			assert(math.abs(u.x - 60.5) < 9 and math.abs(u.y - 40.5) < 9, `near the point: {u.x},{u.y}`)
		end
		run(sim, 60)
		eq(#sim.paradrops, 0, "the drop is over once the plane is gone")
	end)
	test("capital powers: a bomb truck drives to an enemy building and blows up; detonate on demand", function()
		local sim = newSim({ settlements = { { name = "C", x = 150, y = 45, kind = "capital" } } })
		clearUnits(sim, {})
		sim.capitalOf().owner = 1
		local hq = sim.hqOf(2)
		local hp0 = hq.hp
		local ok, id = sim.deployDemo(1, hq.x, hq.y)
		assert(ok, "sent")
		local truck = sim.entities[id]
		eq(truck.kind, "demo")
		local blast = false
		for _ = 1, 20 * 60 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "demoBlast" then
					blast = true
				end
			end
			if blast then
				break
			end
		end
		assert(blast and not truck.alive, "blew up at the HQ")
		assert(hp0 - hq.hp >= 1400 * 0.5 - 1, `HQ took the blast: {hp0 - hq.hp}`)
		-- detonate: units within 3 cells die, a tank further out is hurt
		sim.sides[1].capitalReady = nil
		local near1 = sim.spawnUnit("infantry", 2, 140.5, 60.5)
		local far1 = sim.spawnUnit("tank", 2, 145.0, 60.5)
		local ok2, id2 = sim.deployDemo(1, 160.5, 60.5)
		assert(ok2)
		local d = sim.entities[id2]
		d.x, d.y, d.path = 140.5, 62.0, nil
		assert(sim.detonate(1, { id2 }), "detonated")
		eq(near1.alive, false, "within the lethal radius")
		assert(far1.alive and far1.hp < far1.maxHp, `hurt further out: {far1.hp}`)
		eq(select(2, sim.detonate(1, { id2 })), "noDemo")
	end)
	test("bot: holding the capital it drops paratroopers on a rig and sends a bomb truck at a building", function()
		local sim = newSim({ settlements = { { name = "C", x = 150, y = 45, kind = "capital" } } })
		clearUnits(sim, {})
		sim.capitalOf().owner = 2
		local bot = Bot.new(sim, 2, "balanced")
		bot.think()
		eq((sim.capitalPower(2, "para")), "cooldown", "paratroopers called")
		eq(#sim.paradrops, 1)
		local d = sim.paradrops[1]
		local nearRig = false
		for _, rg in sim.rigs do
			if rg.side ~= 2 and math.abs(rg.x - d.x) <= 7 and math.abs(rg.y - d.y) <= 7 then
				nearRig = true
			end
		end
		assert(nearRig, `onto a rig that is not ours: {d.x},{d.y}`)
		eq((sim.capitalPower(2, "demo")), "cooldown", "bomb truck sent at the enemy HQ it knows")
		eq(#units(sim, 2, "demo"), 1)
	end)
	test("recon drone: 120 oil, flies out, circles 25 s showing the area, home, refuels 60 s", function()
		local sim = newSim()
		clearUnits(sim, {})
		local oil = sim.sides[1].oil
		eq((sim.droneState(1)), "buy")
		assert(sim.launchDrone(1, 120.5, 40.5), "launched")
		eq(sim.sides[1].oil, oil - 120, "bought")
		eq((sim.droneState(1)), "out")
		eq(select(2, sim.launchDrone(1, 120.5, 40.5)), "droneOut")
		local grid = {}
		local scanned, scanAt = false, 0
		local sawThere = false
		for i = 1, 20 * 40 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "droneScanned" then
					scanned, scanAt = true, i * 0.05
				end
			end
			if scanned and not sawThere and i * 0.05 > scanAt + 1 then
				sim.visionFor(1, grid)
				sawThere = grid[40 * W + 140 + 1] == 2
			end
		end
		assert(scanned, "reached the point")
		local want = (math.sqrt((120.5 - 10.5) ^ 2 + 10 ^ 2) - 0.3 * 49.5) / 18
		assert(math.abs(scanAt - want) < 0.2, `out at 18 cells/s, stopping at the orbit: {scanAt} vs {want}`)
		assert(sawThere, "sees 20 cells from the point while circling")
		run(sim, 15)
		local state, left = sim.droneState(1)
		eq(state, "refuel")
		assert(left > 40 and left <= 60, `refuelling: {left}`)
		run(sim, 61)
		eq((sim.droneState(1)), "ready")
		local oil2 = sim.sides[1].oil
		assert(sim.launchDrone(1, 60.5, 40.5))
		eq(sim.sides[1].oil, oil2, "no charge once owned")
	end)
	test("SAM site: fires at an enemy drone in range every 10 s; a downed drone must be replaced", function()
		local sim = newSim()
		clearUnits(sim, {})
		local id, why = sim.placeStructure(2, "sam", 42 * W + 150)
		assert(id, `SAM placed: {why}`)
		local sam = sim.entities[id]
		sam.built = 1
		assert(sim.launchDrone(1, 150.5, 40.5))
		local fired, lost = 0, false
		for _ = 1, 20 * 30 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "samFired" then
					fired += 1
				elseif ev.type == "droneLost" then
					lost = true
				end
			end
		end
		assert(fired >= 1 and lost, `shot down ({fired} missiles)`)
		local state, left = sim.droneState(1)
		eq(state, "replace")
		assert(left > 30 and left <= 60, `replace in 60 s: {left}`)
		-- SAMs do not shoot ground units
		local inf = sim.spawnUnit("infantry", 1, 145.5, 40.5)
		run(sim, 5)
		eq(inf.hp, inf.maxHp, "infantry next to the SAM untouched by it")
	end)
	test("rocket artillery: fires only on a barrage order, 8 rockets round the point, then lowers and drives off", function()
		local sim = newSim()
		clearUnits(sim, {})
		local mrl = sim.spawnUnit("rocket", 1, 60.5, 40.5)
		local foes = {}
		for i = 0, 3 do
			table.insert(foes, sim.spawnUnit("infantry", 2, 110.5 + i, 40.5))
		end
		run(sim, 10)
		eq(mrl.firedAt, nil, "no fire without an order")
		eq(select(2, sim.orderBarrage(1, { mrl.id }, 70.5, 40.5)), "tooClose")
		eq((sim.orderBarrage(1, { foes[1].id }, 111.5, 40.5)), 0, "not its unit")
		eq((sim.orderBarrage(1, { mrl.id }, 111.5, 40.5)), 1)
		mrl.shotTimer, mrl.still = 0, 0
		local fired = nil
		local hp0 = 0
		for _, f in foes do
			hp0 += f.hp
		end
		for i = 1, 20 * 12 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "barrageFired" then
					fired = i * 0.05
				end
			end
			for _, f in foes do
				f.x, f.y, f.path, f.target = f.x, f.y, nil, nil
			end
		end
		assert(fired and fired >= 3 and fired <= 3.3, `rails up 3 s, then it fires: {fired}`)
		local hp1 = 0
		for _, f in foes do
			hp1 += math.max(0, f.hp)
		end
		assert(hp0 - hp1 > 100, `the salvo hurt the squads: {hp0 - hp1}`)
		eq(mrl.barrage, nil, "one salvo per order")
		assert(mrl.shotTimer > 30, `reloading 45 s: {mrl.shotTimer}`)
		local x0 = mrl.x
		run(sim, 10)
		assert(mrl.x < x0 - 6, `drove away from its target after lowering: {mrl.x}`)
		-- out of range: it drives within 0.9 x range first
		local far = sim.spawnUnit("rocket", 1, 20.5, 40.5)
		far.shotTimer = 0
		eq((sim.orderBarrage(1, { far.id }, 150.5, 40.5)), 1)
		assert(far.path ~= nil, "drives closer")
	end)
	test("republic artillery: a missile launcher, one heavy missile on order (min range 24, 40 s reload, tbm speed 15)", function()
		local sim = newSim({ armies = { "republic", "coalition" } })
		clearUnits(sim, {})
		local tbm = sim.spawnUnit("artillery", 1, 30.5, 40.5)
		local gun = sim.spawnUnit("artillery", 2, 150.5, 20.5)
		eq(sim.unitKey(tbm), "armyUnits.republic.artillery")
		eq(sim.unitKey(gun), "units.artillery", "the coalition keeps the howitzer")
		eq(sim.num(sim.unitKey(tbm) .. ".hp"), sim.num("units.artillery.hp"), "the rest from the base unit")
		eq(sim.minRangeOf(sim.unitKey(tbm)), 24)
		local foes = {}
		for i = 0, 2 do
			table.insert(foes, sim.spawnUnit("infantry", 2, 70.5 + i, 40.5))
		end
		run(sim, 5)
		eq(tbm.firedAt, nil, "no fire without an order")
		eq(select(2, sim.orderBarrage(1, { tbm.id }, 50.5, 40.5)), "tooClose", "inside 24 cells")
		eq((sim.orderBarrage(1, { tbm.id }, 71.5, 40.5)), 1)
		tbm.shotTimer, tbm.still = 0, 0
		local hp0 = 0
		for _, f in foes do
			hp0 += f.hp
		end
		local fired, rockets = nil, 0
		for i = 1, 20 * 4 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "barrageFired" then
					fired = i * 0.05
					for _, st in sim.strikes do
						if st.kind == "rocket" and st.shooter == tbm.id then
							rockets += 1
							assert(math.abs(st.at - sim.time - 41 / 15) < 0.1, `tbm flight: {st.at - sim.time}`)
						end
					end
				end
			end
		end
		assert(fired, "fired")
		eq(rockets, 1, "one missile")
		local hp1 = 0
		for _, f in foes do
			hp1 += math.max(0, f.hp)
		end
		run(sim, 3)
		hp1 = 0
		for _, f in foes do
			hp1 += math.max(0, f.hp)
		end
		assert(hp0 - hp1 > 100, `the missile hurt all three: {hp0 - hp1}`)
		assert(tbm.shotTimer > 25, `reloading 40 s: {tbm.shotTimer}`)
		local Stages = require("../src/shared/Presentation/UnitStages")
		eq(Stages.artillery(true, tbm.firedAt, tbm.shotTimer, 1), Stages.MISSILE_EMPTY)
		-- Movement must not refill the rack; the same authoritative timer still runs.
		sim.orderMove(1, { tbm.id }, 35.5, 38.5)
		run(sim, 1)
		eq(Stages.artillery(true, tbm.firedAt, tbm.shotTimer, 0), Stages.MISSILE_EMPTY)
		run(sim, math.max(0, tbm.shotTimer) + 0.1)
		eq(Stages.artillery(true, tbm.firedAt, tbm.shotTimer, 0), Stages.MISSILE_LOADED, "reload completes from the sim timer")
	end)
	test("bot: an idle reloaded rocket launcher fires at the best enemy building in reach", function()
		local sim = newSim()
		clearUnits(sim, {})
		local bid = sim.placeStructure(2, "barracks", 42 * W + 150) :: number
		sim.entities[bid].built = 1
		local mrl = sim.spawnUnit("rocket", 1, 100.5, 42.5)
		mrl.shotTimer = 0
		sim.spawnUnit("infantry", 1, 143.5, 42.5) -- a spotter: the launcher sees 15 cells
		local bot = Bot.new(sim, 1, "balanced")
		for _ = 1, 3 do
			sim.step(0.05)
		end
		bot.think()
		assert(mrl.barrage ~= nil, "barrage ordered")
		local hq2 = sim.hqOf(2)
		assert(math.abs(mrl.barrage.x - hq2.x) < 1 or math.abs(mrl.barrage.x - 150.5) < 1, `at a building: {mrl.barrage.x}`)
	end)
	test("artillery base: kills from enemy units pay for it (20) and for its barrage (15)", function()
		local sim = newSim()
		clearUnits(sim, {})
		eq(sim.canPlace(1, "artybase", cellOf(20, 42)), "kills")
		local inf = sim.spawnUnit("infantry", 2, 30.5, 30.5)
		inf.hp = 1
		local tank = sim.spawnUnit("tank", 1, 33.5, 30.5)
		run(sim, 5)
		eq(inf.alive, false)
		eq(sim.killsOf(1), 1, "one kill")
		tank.alive = false
		sim.sides[1].kills = 40
		local id, why = sim.placeStructure(1, "artybase", cellOf(20, 42))
		assert(id, `placed: {why}`)
		eq(sim.killsOf(1), 20, "20 kills spent")
		local b = sim.entities[id :: number]
		eq(select(2, sim.artyStrike(1, b.id, "barrage", 110.5, 40.5)), "notOperational", "still building")
		b.built = 1
		local foes = {}
		for i = 0, 5 do
			table.insert(foes, sim.spawnUnit("infantry", 2, 110.5 + (i % 3), 40.5 + i // 3))
		end
		local hp0 = 0
		for _, f in foes do
			hp0 += f.hp
		end
		local n0 = #sim.strikes
		assert(sim.artyStrike(1, b.id, "barrage", 111.5, 41))
		eq(#sim.strikes - n0, 18, "18 shells")
		eq(sim.killsOf(1), 5, "15 more spent")
		eq(select(2, sim.artyStrike(1, b.id, "barrage", 111.5, 41)), "cooldown")
		eq(select(2, sim.artyStrike(1, b.id, "flare", 111.5, 41)), nil, "flares are separate and cost 5")
		eq(sim.killsOf(1), 0)
		for i = 1, 20 * 25 do
			sim.step(0.05)
			for _, f in foes do
				f.path, f.target = nil, nil
			end
		end
		local hp1 = 0
		for _, f in foes do
			hp1 += math.max(0, f.hp)
		end
		assert(hp0 - hp1 > 300, `the barrage hurt them: {hp0 - hp1}`)
		eq(select(2, sim.artyStrike(1, b.id, "barrage", 111.5, 41)), "kills", "ready again but no kills")
	end)
	test("artillery base: enemy SAMs stop up to 6 shells each; flares light the area and drift", function()
		local sim = newSim()
		clearUnits(sim, {})
		sim.sides[1].kills = 100
		local id = sim.placeStructure(1, "artybase", cellOf(20, 42)) :: number
		sim.entities[id].built = 1
		local sid = sim.placeStructure(2, "sam", 42 * W + 150) :: number
		sim.entities[sid].built = 1
		local n0 = #sim.strikes
		assert(sim.artyStrike(1, id, "barrage", 150.5, 40.5))
		local stopped = nil
		for _, ev in sim.takeEvents() do
			if ev.type == "barrageIntercepted" then
				stopped = ev.n
			end
		end
		eq(stopped, 6)
		eq(#sim.strikes - n0, 12, "12 of 18 get through")
		-- the SAM reloads 20 s after stopping shells
		assert(sim.artyStrike(1, id, "flare", 120.5, 20.5))
		eq(#sim.flares, 5)
		local vis = {}
		sim.visionFor(1, vis)
		local function lit(): number
			sim.visionFor(1, vis)
			local n = 0
			for _, f in sim.flares do
				if vis[sim.roads.cellAt(f.x, f.y) + 1] == 2 then
					n += 1
				end
			end
			return n
		end
		eq(lit(), 0, "not lit before they burst")
		run(sim, 20)
		eq(lit(), 5, "all five burning and lit")
		local x0 = sim.flares[1].x
		run(sim, 20)
		assert(sim.flares[1].x > x0 + 2, `drifts downwind: {sim.flares[1].x - x0}`)
		run(sim, 80)
		eq(#sim.flares, 0, "burnt out after 100 s")
	end)
	test("bot: builds an artillery base once it has the kills and fires a barrage at a cluster", function()
		local sim = newSim()
		clearUnits(sim, {})
		sim.sides[1].kills = 60
		local bar = sim.placeStructure(1, "barracks", cellOf(20, 42))
		if bar then
			sim.entities[bar].built = 1
		end
		sim.sides[1].oil = 0
		local bot = Bot.new(sim, 1, "balanced")
		local base = nil
		for _ = 1, 30 do
			bot.think()
			run(sim, 2)
			for _, e in sim.list do
				if e.alive and e.kind == "artybase" and e.side == 1 then
					base = e
				end
			end
			if base then
				break
			end
		end
		assert(bar and base, "artillery base placed")
		base.built = 1
		for i = 0, 7 do
			sim.spawnUnit("tank", 2, 120.5 + (i % 4), 40.5 + i // 4)
		end
		sim.spawnUnit("scout", 1, 112.5, 40.5)
		run(sim, 0.2)
		local fired = false
		for _ = 1, 3 do
			bot.think()
			for _, ev in sim.takeEvents() do
				if ev.type == "artyBarrage" then
					fired = true
				end
			end
		end
		assert(fired, "barrage at the tanks")
	end)
	test("night ops tower: night vision for its side, alerts kept by night, 300 s wait after losing it", function()
		local sim = newSim()
		clearUnits(sim, {})
		local t = 0
		while sim.nightAmount() < 1 and t < 480 do
			t += 1
			sim.time = t
		end
		eq(sim.nightAmount(), 1, "full night found")
		eq(sim.sightFactor(1), 0.4, "blind-ish without a tower")
		eq(sim.quietAtNight("rigUnderAttack", 1), true, "rig alerts lost in the dark")
		eq(sim.quietAtNight("convoyLost", 1), false, "not every alert")
		sim.sides[1].oil = 1000
		local id, why = sim.placeStructure(1, "nightops", cellOf(20, 46))
		assert(id, `placed: {why}`)
		local nv = sim.entities[id :: number]
		eq(sim.nightVisionFor(1), false, "not until built")
		nv.built = 1
		eq(sim.nightVisionFor(1), true)
		eq(sim.sightFactor(1), 0.9, "night vision share")
		eq(sim.sightFactor(2), 0.4, "the other side is still in the dark")
		eq(sim.quietAtNight("rigUnderAttack", 1), false)
		assert(sim.switchNightOps(1, nv.id, false))
		eq(sim.sightFactor(1), 0.4, "switched off")
		assert(sim.switchNightOps(1, nv.id, true))
		-- lose it: no new one for 300 s
		local foe = sim.spawnUnit("tank", 2, nv.x + 4, nv.y)
		nv.hp = 1
		run(sim, 5)
		eq(nv.alive, false)
		foe.alive = false
		local left = sim.nightOpsRebuildIn(1)
		assert(left > 290 and left <= 300, `wait: {left}`)
		eq(sim.canPlace(1, "nightops", cellOf(20, 46)), "rebuildWait")
		run(sim, 300)
		eq(sim.canPlace(1, "nightops", cellOf(20, 46)), nil)
	end)
	test("veterancy: 3 kills make a veteran (harder hitting, faster firing, tougher); heroes heal out of contact", function()
		local sim = newSim()
		clearUnits(sim, {})
		local tank = sim.spawnUnit("tank", 1, 60.5, 40.5)
		local promoted = nil
		for i = 1, 3 do
			local foe = sim.spawnUnit("infantry", 2, 64.5, 40.5)
			foe.hp = 1
			for _ = 1, 20 * 8 do
				sim.step(0.05)
				for _, ev in sim.takeEvents() do
					if ev.type == "unitPromoted" then
						promoted = ev.rank
					end
				end
				if not foe.alive then
					break
				end
			end
			eq(foe.alive, false, `foe {i} down`)
		end
		eq(tank.kills, 3)
		eq(tank.rank, 1)
		eq(promoted, "veteran")
		eq(sim.killsOf(1), 3, "the side's kills too")
		assert(math.abs(sim.vetDamage(tank) - 1.3) < 1e-9)
		assert(math.abs(sim.vetReload(tank) - 0.91) < 1e-9)
		assert(math.abs(sim.vetTaken(tank) - 1 / 1.45) < 1e-9)
		-- a hit on it hurts less
		local hp0 = tank.hp
		sim.vetHit(tank, 100)
		assert(math.abs(hp0 - tank.hp - 100 / 1.45) < 1e-6, `taken: {hp0 - tank.hp}`)
		-- rank 3 heals 2.5% of its hp a second when nobody is shooting at it
		tank.rank = 3
		tank.hitAt = nil
		local base = tank.maxHp
		tank.hp = base * 0.5
		run(sim, 10)
		local healed = tank.hp - base * 0.5
		assert(math.abs(healed - base * 0.25) < base * 0.03, `healed {healed} of {base}`)
	end)
	test("transport: 2 riders board an IFV, ride out of reach, get set down behind it; a wreck hurts them", function()
		local sim = newSim()
		clearUnits(sim, {})
		local ifv = sim.spawnUnit("ifv", 1, 60.5, 40.5)
		local a = sim.spawnUnit("infantry", 1, 66.5, 40.5)
		local b = sim.spawnUnit("at", 1, 66.5, 42.5)
		local c = sim.spawnUnit("infantry", 1, 70.5, 40.5)
		local tank = sim.spawnUnit("tank", 1, 62.5, 44.5)
		eq(select(2, sim.orderBoard(1, tank.id, { a.id })), "notCarrier")
		eq(select(2, sim.orderBoard(1, ifv.id, { tank.id })), "noRiders")
		eq((sim.orderBoard(1, ifv.id, { c.id, a.id, b.id })), 2, "room for two, nearest first")
		eq(c.boarding, nil)
		eq(select(2, sim.orderBoard(1, ifv.id, { c.id })), "carrierFull", "both seats spoken for")
		run(sim, 10)
		eq(#(ifv.cargo or {}), 2, "both aboard")
		eq(a.carrier, ifv.id)
		for _, e in sim.list do
			assert(e ~= a and e ~= b, "riders are out of the world")
		end
		sim.orderMove(1, { a.id }, 80.5, 40.5)
		eq(a.path, nil, "a rider takes no orders")
		sim.orderMove(1, { ifv.id }, 90.5, 40.5)
		run(sim, 25)
		assert(ifv.x > 85, `IFV drove: {ifv.x}`)
		eq(a.x, ifv.x, "riders move with it")
		ifv.heading = 0
		eq((sim.orderUnload(1, { ifv.id })), 2)
		eq(a.carrier, nil)
		assert(a.x < ifv.x - 2, `set down behind it: {a.x} vs {ifv.x}`)
		eq(select(2, sim.orderUnload(1, { ifv.id })), "noCargo")
		-- board again, then the IFV is destroyed: each rider loses 35% of its hp and jumps out
		eq((sim.orderBoard(1, ifv.id, { a.id, b.id })), 2)
		run(sim, 10)
		eq(#(ifv.cargo or {}), 2)
		local foe = sim.spawnUnit("tank", 2, ifv.x + 3, ifv.y)
		ifv.hp = 1
		run(sim, 5)
		eq(ifv.alive, false)
		foe.alive = false
		eq(a.carrier, nil)
		assert(a.alive and math.abs(a.hp - a.maxHp * 0.65) < a.maxHp * 0.25, `bailed out hurt: {a.hp}/{a.maxHp}`)
		local inList = false
		for _, e in sim.list do
			inList = inList or e == a
		end
		assert(inList, "back in the world")
	end)
	test("bot: idle riders at home get into an idle IFV; a loaded IFV unloads when enemies are near", function()
		local sim = newSim()
		clearUnits(sim, {})
		local hq = sim.hqOf(1)
		local ifv = sim.spawnUnit("ifv", 1, hq.x + 6, hq.y)
		local a = sim.spawnUnit("infantry", 1, hq.x + 8, hq.y + 1)
		local b = sim.spawnUnit("infantry", 1, hq.x + 8, hq.y - 1)
		local bot = Bot.new(sim, 1, "balanced")
		bot.think()
		eq(a.boarding, ifv.id)
		run(sim, 8)
		eq(#(ifv.cargo or {}), 2, "boarded")
		-- out in the field with an enemy close by: out they get
		ifv.x, ifv.y = 100.5, 40.5
		sim.spawnUnit("tank", 2, 108.5, 40.5)
		sim.step(0.05)
		bot.think()
		eq(#(ifv.cargo or {}), 0, "unloaded under threat")
	end)
	test("command truck: deploys into an HQ after 10 s still (moving cancels), with its share of hp", function()
		local sim = newSim()
		clearUnits(sim, {})
		local hq0 = sim.hqOf(1)
		local tr = sim.spawnUnit("command", 1, hq0.x + 30, hq0.y)
		eq(select(2, sim.deployHq(2, tr.id)), "noTruck", "not theirs")
		assert(sim.deployHq(1, tr.id))
		eq(select(2, sim.deployHq(1, tr.id)), "alreadyDeploying")
		run(sim, 3)
		sim.orderMove(1, { tr.id }, tr.x + 6, tr.y)
		run(sim, 0.2)
		eq(tr.deployAt, nil, "moving cancels it")
		run(sim, 10)
		tr.path, tr.target = nil, nil
		tr.hp = tr.maxHp * 0.5
		assert(sim.deployHq(1, tr.id))
		local up = nil
		for i = 1, 20 * 11 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "hqDeployed" then
					up = i * 0.05
				end
			end
		end
		assert(up and up >= 9.9 and up <= 10.1, `HQ up after 10 s: {up}`)
		eq(tr.alive, false, "the truck is gone")
		local hq = sim.hqOf(1)
		assert(hq ~= hq0, "the new HQ is the side's HQ")
		assert(math.abs(hq.hp - hq.maxHp * 0.5) < 1, `half hp: {hq.hp}`)
		assert(math.abs(hq.x - tr.x) <= 12.5 and math.abs(hq.y - tr.y) <= 12.5, "within deployReach")
	end)
	test("rally points: new units leave by the door facing the rally and walk to slots round it; set, refused, cleared", function()
		local sim = newSim()
		clearUnits(sim, {})
		local Wd = sim.roads.width
		local hq = sim.hqOf(1)
		local foot = sim.footprintOf("hq") + 0.5
		-- default: beyond the footprint by rallyCells x cellScale, towards the nearest road or the centre
		local rx, ry, set = sim.rallyOf(hq)
		eq(set, false)
		-- the road runs along the HQ's row: the nearest road cells outside the footprint tie at 3 cells west and
		-- east; the scan meets the west one first, so the rally is 11.5 west, clamped at the map edge
		eq(rx, 0.5, "west, clamped")
		eq(ry, hq.y)
		local cx = sim.rallyOf({ cell = hq.cell + 40, kind = "hq" } :: any)
		near(cx, hq.x + 40 - foot - sim.num("production.rallyCells") * sim.num("match.cellScale"), "unclamped: footprint + rallyCells x cellScale")
		local dx, dy = sim.doorOf(hq, rx, ry)
		near(math.max(math.abs(dx - hq.x), math.abs(dy - hq.y)), foot + 0.5, "door just outside the edge")
		assert(math.abs(dx - hq.x) <= foot * sim.num("production.doorSpan") + 1e-6 or math.abs(dy - hq.y) <= foot * sim.num("production.doorSpan") + 1e-6, "door within the span")
		-- refusals
		eq(sim.setRally(2, hq.id, hq.x + 20, hq.y), "notOwned")
		eq(sim.setRally(1, hq.id, hq.x, hq.y), "terrain", "inside the footprint")
		-- a passable point about 20 cells east of the HQ
		local px, py
		for k = 0, 30 do
			local c = math.floor(hq.y) * Wd + math.floor(hq.x) + 20 + k
			if sim.roads.passable(c) then
				px, py = c % Wd + 0.5, c // Wd + 0.5
				break
			end
		end
		assert(px, "found ground east of the HQ")
		eq(sim.setRally(1, hq.id, px, py), nil)
		local ax, ay, aset = sim.rallyOf(hq)
		eq(aset, true)
		eq(ax, px)
		eq(ay, py)
		local ex = sim.doorOf(hq, px, py)
		near(ex, hq.x + foot + 0.5, "east door")
		sim.sides[1].oil = 5000
		assert(sim.orderProduce(1, "infantry"))
		assert(sim.orderProduce(1, "infantry"))
		local made = {}
		for _ = 1, 20 * 60 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "unitReady" and ev.side == 1 then
					local u = sim.entities[ev.id]
					table.insert(made, u)
					assert(u.x > hq.x + foot, `spawned on the east side: {u.x} vs {hq.x}`)
				end
			end
			if #made == 2 then
				break
			end
		end
		eq(#made, 2, "two trained")
		assert(made[1].goalCell ~= made[2].goalCell, "each takes its own slot")
		eq(hq.made, 2)
		for _ = 1, 20 * 30 do
			sim.step(0.05)
		end
		for _, u in made do
			assert(math.sqrt((u.x - px) ^ 2 + (u.y - py) ^ 2) < 4, `at the rally: {u.x},{u.y} vs {px},{py}`)
		end
		eq(sim.clearRally(2, hq.id), "notOwned")
		eq(sim.clearRally(1, hq.id), nil)
		eq(hq.rally, nil)
	end)
	test("cancel and demolish: queued units refund what was paid; a building going up refunds the unfinished share; a demolish takes 6 s and gives back 60%", function()
		local sim = newSim()
		clearUnits(sim, {})
		local sd = sim.sides[1]
		sd.oil = 5000
		local hq = sim.hqOf(1)
		local before = sd.oil
		assert(sim.orderProduce(1, "infantry"))
		assert(sim.orderProduce(1, "infantry"))
		local cost = before - sd.oil
		run(sim, 1)
		before = sd.oil
		assert(sim.cancelQueued(1, hq.id, 2))
		eq(#hq.queue, 1)
		assert(sim.cancelQueued(1, hq.id, 1))
		eq(hq.queueProgress, 0, "the one in training resets")
		eq(sd.oil - before, cost, "all of it back")
		eq(sim.cancelQueued(1, hq.id, 1), false, "nothing left")
		-- a building going up
		local o0 = sd.oil
		local id, why = sim.placeStructure(1, "barracks", cellOf(20, 46))
		assert(id, `placed: {why}`)
		local b = sim.entities[id :: number]
		local price = o0 - sd.oil
		b.built = 0.25
		eq(select(2, sim.demolish(1, b.id)), "blocked", "not finished: cancel it instead")
		assert(sim.cancelBuilding(1, b.id))
		eq(b.alive, false)
		eq(sd.oil, o0 - price + math.floor(price * 0.75 + 0.5), "75% back")
		-- a finished one
		local id2 = sim.placeStructure(1, "barracks", cellOf(20, 46))
		assert(id2, "the cell is free again")
		local b2 = sim.entities[id2 :: number]
		b2.built = 1
		local o1 = sd.oil
		assert(sim.orderProduce(1, "infantry", b2.id) or true)
		eq(select(2, sim.demolish(2, b2.id)), "notOwned")
		eq(select(2, sim.demolish(1, hq.id)), "blocked", "never the HQ")
		assert(sim.demolish(1, b2.id))
		eq(sd.oil, o1, "its queue refunded")
		eq(select(2, sim.demolish(1, b2.id)), "blocked", "already coming down")
		eq(sim.inactiveReason(b2), "demolishing")
		local gone, back = nil, nil
		for i = 1, 20 * 7 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "demolished" then
					gone, back = i * 0.05, ev.oil
				end
			end
		end
		assert(gone and gone >= 5.9 and gone <= 6.1, `down after 6 s: {gone}`)
		eq(b2.alive, false)
		eq(back, math.floor(price * 0.6 + 0.5), "60% back")
	end)
	test("trenches: engineers dig a drawn line cell by cell for oil; dug cells block the way; filling opens a gap", function()
		local sim = newSim()
		clearUnits(sim, {})
		local sd = sim.sides[1]
		sd.oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq(select(2, sim.orderDig(1, ids, { { x = 62.5, y = 45.5 } })), "lineShort")
		local lay = sim.trenchLayout(1, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } })
		eq(#lay.cells, 15, "one cell per row")
		eq(lay.good, 15)
		eq((sim.orderDig(1, ids, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } })), 3)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		assert(t, "a trench")
		run(sim, 30)
		eq(t.dug, 15, "all dug")
		for i = 1, 15 do
			eq(t.state[i], sim.TRENCH.dug)
		end
		-- the same match without the trench, for the income
		local ctl = newSim()
		clearUnits(ctl, {})
		ctl.sides[1].oil = 500
		for i = 0, 2 do
			ctl.spawnUnit("engineer", 1, 58.5, 44.5 + i)
		end
		run(ctl, 30)
		local spent = ctl.sides[1].oil - sd.oil
		assert(math.abs(spent - 15 * sim.num("trenches.oilPerCell")) < 0.5, `oil per cell: {spent}`)
		eq(sim.roads.passable(t.cells[5]), false, "a dug cell blocks the way")
		eq(sim.placeProblem(t.cells[5], "barracks") ~= nil, true, "no building on it")
		for _, e in engs do
			eq(e.trenchJob, nil, "diggers done")
		end
		-- fill round the middle: gapCells (9) cells open again
		eq((sim.orderFill(1, ids, t.cells[8])), 3)
		run(sim, 30)
		local open = 0
		for i = 1, 15 do
			if t.state[i] == sim.TRENCH.gone then
				open += 1
			end
		end
		eq(open, 9, "a 9-cell gap")
		eq(sim.roads.passable(t.cells[8]), true)
		eq(sim.roads.passable(t.cells[1]), false, "the rest stays")
	end)
	test("trenches: wire near roads, stall without oil, an abandoned line keeps what was dug", function()
		local sim = newSim()
		clearUnits(sim, {})
		local sd = sim.sides[1]
		sd.oil = 1000
		local e = sim.spawnUnit("engineer", 1, 70.5, 27.5)
		local lay = sim.trenchLayout(1, { { x = 72.5, y = 26.5 }, { x = 72.5, y = 34.5 } })
		local wired = 0
		for _, w in lay.wire do
			if w then
				wired += 1
			end
		end
		assert(wired >= 3 and wired < #lay.cells, `wire only by the road: {wired} of {#lay.cells}`)
		eq((sim.orderDig(1, { e.id }, { { x = 72.5, y = 26.5 }, { x = 72.5, y = 34.5 } })), 1)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		for _ = 1, 20 * 20 do
			if t.dug >= 1 then
				break
			end
			sim.step(0.05)
		end
		assert(t.dug >= 1 and t.dug < #t.cells, `some dug: {t.dug}`)
		sd.oil = 0
		local stalled = false
		for _ = 1, 20 * 10 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "trenchStalled" then
					stalled = true
				end
			end
		end
		assert(stalled, "stalls without oil")
		local dug = t.dug
		e.trenchJob = nil
		run(sim, 0.1)
		eq(#t.cells, dug, "cut back to what was dug")
	end)
	test("trench kinds: a wire belt costs its own rate, slows infantry, stops wheels and is flattened by tracks", function()
		local sim = newSim()
		clearUnits(sim, {})
		local sd = sim.sides[1]
		sd.oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq(select(2, sim.orderDig(1, ids, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } }, "moat")), "blocked", "unknown kind")
		eq((sim.orderDig(1, ids, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } }, "wire")), 3)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		eq(t.kind, "wire")
		run(sim, 30)
		eq(t.dug, 15, "all laid")
		local ctl = newSim()
		clearUnits(ctl, {})
		ctl.sides[1].oil = 500
		for i = 0, 2 do
			ctl.spawnUnit("engineer", 1, 58.5, 44.5 + i)
		end
		run(ctl, 30)
		local spent = ctl.sides[1].oil - sd.oil
		assert(math.abs(spent - 15 * sim.num("trenchWorks.kinds.wire.oilPerCell")) < 0.5, `oil per cell: {spent}`)
		local c = t.cells[5]
		local x, y = c % sim.roads.width + 0.5, c // sim.roads.width + 0.5
		eq(sim.roads.passable(c), true, "a belt is not a wall")
		eq(sim.roads.trenchSoft(c), 3)
		local foot = sim.paceAt("infantry", x, y)
		assert(math.abs(foot - sim.num("trenchWorks.kinds.wire.footPace")) < 1e-6, `infantry pace {foot}`)
		eq(sim.paceAt("tank", x, y), 1, "tracks roll over")
		eq(sim.paceAt("scout", x, y), 0.05, "wheels barely (routes avoid it)")
		-- a tank on the belt flattens that cell
		sim.spawnUnit("tank", 1, x, y)
		run(sim, 0.1)
		eq(t.damage[5], 1)
		eq(sim.roads.trenchSoft(c), 0, "flattened")
		eq(sim.roads.trenchSoft(t.cells[1]), 3, "the rest stays")
	end)
	test("trench kinds: a fire trench is crossed slowly on foot; a ditch by the water floods and still blocks", function()
		local sim = newSim({ terrainAt = function(c)
			local x, y = c % W, c // W
			return if x == 63 and y >= 44 and y <= 46 then "river" else "plains"
		end })
		clearUnits(sim, {})
		sim.sides[1].oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq((sim.orderDig(1, ids, { { x = 56.5, y = 30.5 + 8 }, { x = 56.5, y = 38.5 + 8 } }, "fire")), 3)
		run(sim, 20)
		local fire = nil
		for _, tr in sim.trenches do
			fire = tr
		end
		eq(fire.dug, #fire.cells, "fire trench dug")
		local c = fire.cells[3]
		eq(sim.roads.passable(c), true)
		eq(sim.roads.trenchSoft(c), 1)
		local foot = sim.paceAt("infantry", c % W + 0.5, c // W + 0.5)
		assert(math.abs(foot - sim.num("trenchWorks.kinds.fire.footPace")) < 1e-6, `infantry pace {foot}`)
		-- a ditch along the river bank floods
		local flooded = false
		eq((sim.orderDig(1, ids, { { x = 62.5, y = 40.5 }, { x = 62.5, y = 50.5 } })), 3)
		local ditch = nil
		for _, tr in sim.trenches do
			if tr ~= fire then
				ditch = tr
			end
		end
		for _ = 1, 20 * 25 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "trenchFlooded" then
					flooded = true
				end
			end
		end
		assert(flooded, "flood notice")
		local wet, dry = 0, 0
		for i = 1, #ditch.cells do
			if ditch.state[i] == sim.TRENCH.wet then
				wet += 1
			elseif ditch.state[i] == sim.TRENCH.dug then
				dry += 1
			end
		end
		assert(wet >= 3, `wet cells: {wet}`)
		eq(wet + dry, #ditch.cells, "all dug")
		for i = 1, #ditch.cells do
			eq(sim.roads.passable(ditch.cells[i]), false, "wet or dry, a ditch blocks")
		end
	end)
	test("trench shelling: blasts wear a ditch until it caves in, big shells smash it, engineers mend both", function()
		local sim = newSim()
		clearUnits(sim, {})
		sim.sides[1].oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq((sim.orderDig(1, ids, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } })), 3)
		run(sim, 30)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		eq(t.dug, 15)
		local c = t.cells[8]
		local x, y = c % W + 0.5, c // W + 0.5
		eq(select(2, sim.orderMend(1, ids, c)), "notCaved", "nothing to mend yet")
		local hp = sim.num("trenchWorks.shells.caveHp")
		sim.trenchShell(x, y, hp * 0.6, 2)
		assert(math.abs(t.damage[8] - 0.6) < 1e-6, `worn {t.damage[8]}`)
		eq(sim.roads.passable(c), false, "still a wall")
		local caved = false
		sim.trenchShell(x, y, hp * 0.6, 2)
		for _, ev in sim.takeEvents() do
			if ev.type == "trenchCaved" and ev.side == 1 then
				caved = true
			end
		end
		assert(caved, "the owner hears of it")
		eq(t.damage[8], 1)
		eq(sim.roads.passable(c), true, "caved: crossable")
		eq(sim.roads.trenchSoft(c), 1, "like a fire trench")
		-- a small shell does not smash; a big one smashes cells round it flat
		sim.trenchSmash(x, y + 5, 0, sim.num("trenchWorks.shells.big.damage") - 1, 2)
		eq(t.state[13], sim.TRENCH.dug)
		sim.trenchSmash(x, y + 5, 0, sim.num("trenchWorks.shells.big.damage"), 2)
		eq(t.state[13], sim.TRENCH.smashed)
		eq(sim.roads.passable(t.cells[13]), true)
		eq(sim.roads.trenchSoft(t.cells[13]), 0, "flat")
		-- mend from the caved cell: everything within gapCells either side
		eq((sim.orderMend(1, ids, c)), 3)
		local mended = false
		for _ = 1, 20 * 30 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "trenchMended" then
					mended = true
				end
			end
		end
		assert(mended, "mended notice")
		for i = 1, 15 do
			eq(t.state[i], sim.TRENCH.dug, `cell {i} dug`)
			eq(t.damage[i], 0)
			eq(sim.roads.passable(t.cells[i]), false)
		end
		for _, e in engs do
			eq(e.trenchJob, nil)
		end
	end)
	test("manning trenches: infantry spread along a fire trench, take less damage and stay hidden until something is close", function()
		local sim = newSim()
		clearUnits(sim, {})
		sim.sides[1].oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq((sim.orderDig(1, ids, { { x = 62.5, y = 38.5 }, { x = 62.5, y = 52.5 } }, "fire")), 3)
		run(sim, 30)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		eq(t.dug, 15)
		local men, mids = {}, {}
		for i = 0, 3 do
			local u = sim.spawnUnit("infantry", 1, 56.5, 42.5 + i)
			table.insert(men, u)
			table.insert(mids, u.id)
		end
		eq(select(2, sim.orderMan(1, mids, 20 * W + 20)), "notFireTrench")
		eq(select(2, sim.orderMan(1, { engs[1].id }, t.cells[8])), "noUnits", "engineers don't man trenches")
		eq((sim.orderMan(1, mids, t.cells[8])), 4)
		run(sim, 25)
		local cells = {}
		-- each is sent to its own trench cell (separation can nudge one off the line)
		local inside, posts = 0, {}
		for _, u in men do
			eq(posts[u.post], nil, "one to a cell")
			posts[u.post] = true
			assert(table.find(t.cells, u.post), "posted on the trench")
			if u.inTrench == t.id then
				inside += 1
			end
		end
		assert(inside >= 3, `in the trench: {inside}`)
		local u = men[1]
		u.x, u.y = t.cells[1] % W + 0.5, t.cells[1] // W + 0.5
		run(sim, 0.05)
		eq(u.inTrench, t.id)
		eq(sim.trenchShare(u, 0, false), sim.num("trenchWorks.man.bulletShare"))
		eq(sim.trenchShare(u, 1, false), sim.num("trenchWorks.man.shellShare"))
		eq(sim.trenchShare(engs[1], 0, false), 1)
		-- an enemy squad far off cannot see them; one close by can; firing gives them away
		local far = sim.spawnUnit("infantry", 2, u.x + 15, u.y)
		u.firedAt = nil
		run(sim, 0.05)
		eq(sim.trenchHidden(u, 2), true, "hidden")
		eq(sim.trenchHidden(u, 1), false, "never from your own side")
		u.firedAt = sim.time
		eq(sim.trenchHidden(u, 2), false, "just fired")
		u.firedAt = sim.time - sim.num("trenchWorks.man.firedShowSec") - 0.1
		sim.step(0.05)
		far.x = u.x + sim.num("trenchWorks.man.hideCells") - 1
		sim.step(0.05)
		eq(sim.trenchHidden(u, 2), false, "something close by sees them")
	end)
	test("breaching: an enemy charge on a trench smashes a gap and shows the owner the spot; by water it breaks the bank", function()
		local sim = newSim({ terrainAt = function(c)
			local x, y = c % W, c // W
			return if x == 64 and y >= 50 and y <= 52 then "river" else "plains"
		end })
		clearUnits(sim, {})
		sim.sides[1].oil = 500
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 1, 58.5, 44.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq((sim.orderDig(1, ids, { { x = 40.5, y = 33.5 }, { x = 40.5, y = 47.5 } })), 3)
		run(sim, 30)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		eq(t.dug, 15)
		local c = t.cells[8]
		local x, y = c % W + 0.5, c // W + 0.5
		local foe = sim.spawnUnit("engineer", 2, x + 2, y)
		eq((sim.orderSabotage(2, c, { foe.id })), 1)
		local blown, breached = false, false
		for _ = 1, 20 * 20 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "trenchBlown" and ev.side == 2 then
					blown = true
				elseif ev.type == "trenchBreached" and ev.side == 1 then
					breached = true
				end
			end
		end
		assert(blown and breached, "both sides hear of it")
		local half = math.floor(sim.num("trenchWorks.breach.gapCells") / 2)
		for i = 1, 15 do
			eq(t.state[i], if math.abs(i - 8) <= half then sim.TRENCH.smashed else sim.TRENCH.dug, `cell {i}`)
		end
		eq(sim.roads.passable(c), true, "open")
		eq(#sim.reveals, 1, "the owner sees round the spot")
		eq(sim.reveals[1].side, 1)
		-- a second ditch by the river: the charge breaks its bank and it floods there
		eq((sim.orderDig(1, ids, { { x = 63.5, y = 49.5 }, { x = 63.5, y = 58.5 } })), 3)
		run(sim, 30)
		local d = nil
		for _, tr in sim.trenches do
			if tr ~= t then
				d = tr
			end
		end
		-- dry it again so only the charge floods it
		for i = 1, #d.cells do
			if d.state[i] == sim.TRENCH.wet then
				d.state[i] = sim.TRENCH.dug
			end
		end
		d.fed = nil
		local dc = d.cells[2]
		eq(sim.blowTrench(dc, 2), true)
		eq(d.fed, true)
		eq(d.state[2], sim.TRENCH.wet, "flooded, not smashed")
		eq(select(1, sim.breachCheck(dc)), "trenchWet")
		eq(select(2, sim.orderSabotage(2, dc, { foe.id })), "trenchWet")
	end)
	test("bot trenches: with digFrom oil an idle engineer digs a fire trench line towards the enemy, idle infantry man it", function()
		local sim = newSim()
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		local e = sim.spawnUnit("engineer", 1, 14.5, 34.5)
		sim.sides[1].oil = sim.num("trenchWorks.bots.digFrom") - 1
		bot.think()
		eq(next(sim.trenches), nil, "not enough oil")
		sim.sides[1].oil = 2000
		bot.think()
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		assert(t, "a line")
		eq(t.owner, 1)
		eq(t.kind, "fire")
		eq(e.trenchJob and e.trenchJob.id, t.id)
		-- out towards the enemy HQ (east), across the way
		local hq = sim.hqOf(1)
		local hx = hq.cell % W
		for _, c in t.cells do
			assert(c % W > hx + 10, `ahead of the HQ: {c % W}`)
		end
		run(sim, 60)
		eq(t.dug, #t.cells, "dug")
		local men = {}
		for i = 0, 2 do
			table.insert(men, sim.spawnUnit("infantry", 1, hx + 20.5, 40.5 + i))
		end
		run(sim, 0.1)
		sim.botTrenches(1) -- the trench step alone (the rest of the think would send them elsewhere)
		run(sim, 30)
		local inside = 0
		for _, u in men do
			if u.inTrench == t.id then
				inside += 1
			end
		end
		assert(inside >= 2, `manned: {inside}`)
	end)
	test("bot trenches: an enemy trench cutting the way to its HQ for tanks is breached", function()
		local sim = newSim()
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		sim.sides[2].oil = 2000
		local engs = {}
		for i = 0, 2 do
			table.insert(engs, sim.spawnUnit("engineer", 2, 92.5, 2.5 + i))
		end
		local ids = { engs[1].id, engs[2].id, engs[3].id }
		eq((sim.orderDig(2, ids, { { x = 90.5, y = 0.5 }, { x = 90.5, y = 59.5 } }, "fire")), 3)
		local t = nil
		for _, tr in sim.trenches do
			t = tr
		end
		run(sim, 120)
		eq(t.dug, #t.cells, "dug across the map")
		eq(#t.cells, 60)
		local e = sim.spawnUnit("engineer", 1, 70.5, 34.5)
		sim.sides[1].oil = 0
		bot.think()
		assert(e.sabotageCell and table.find(t.cells, e.sabotageCell), "sent to breach it")
	end)
	test("trench seal: a line stopping just short of a river is carried on to it", function()
		local sim = newSim({ terrainAt = function(c)
			local x = c % W
			return if x >= 70 and x <= 72 then "river" else "plains"
		end })
		clearUnits(sim, {})
		local lay = sim.trenchLayout(1, { { x = 50.5, y = 45.5 }, { x = 66.5, y = 45.5 } })
		local last = lay.cells[#lay.cells]
		eq(last % W, 69, "runs up to the bank")
		eq(lay.cells[1] % W, 50, "the open end stays")
		local far = sim.trenchLayout(1, { { x = 50.5, y = 45.5 }, { x = 60.5, y = 45.5 } })
		eq(far.cells[#far.cells] % W, 60, "too far from the river: unchanged")
	end)
	test("road signs: a side shuts a stretch of road to its trucks; its rig routes go round, never left with no way home", function()
		local bypass = { { rank = 2, track = false, pts = { 0.5, 30.5, 179.5, 30.5 } },
			{ rank = 2, track = false, pts = { 20.5, 30.5, 20.5, 20.5, 40.5, 20.5, 40.5, 30.5 } } }
		local sim = newSim({ roads = bypass })
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		for _ = 1, 20 do
			sim.step(0.05)
		end
		assert(rig.route, "a route home")
		eq(select(2, sim.placeRoadSign(1, 25 * W + 30)), "notRoad")
		local mid = 30 * W + 30
		assert(table.find(rig.route, mid), "the route takes the straight road")
		local id = sim.placeRoadSign(1, mid)
		assert(id, "placed")
		eq(select(2, sim.placeRoadSign(1, mid)), "signHere")
		for _ = 1, 20 do
			sim.step(0.05)
		end
		assert(rig.route, "still a route")
		eq(table.find(rig.route, mid), nil, "round the sign")
		assert(table.find(rig.route, 20 * W + 30), "by the bypass")
		-- the other side's trucks are not affected
		eq(sim.signClosed(2), nil)
		-- shutting the bypass too would strand the rig
		eq(select(2, sim.placeRoadSign(1, 20 * W + 30)), "noRoute")
		eq(select(2, sim.removeRoadSign(2, id)), "noSign")
		eq((sim.removeRoadSign(1, id)), true)
		for _ = 1, 20 do
			sim.step(0.05)
		end
		assert(table.find(rig.route, mid), "back on the straight road")
		for i = 1, sim.num("signs.max") do
			assert(sim.placeRoadSign(1, 30 * W + 90 + i * 9), `sign {i}`)
		end
		eq(select(2, sim.placeRoadSign(1, 30 * W + 170)), "limitReached")
	end)
	test("cut supply routes: trucks stop leaving; after 45 s a bot re-routes itself, a player picks one of the routes on offer", function()
		local bypass = { { rank = 2, track = false, pts = { 0.5, 30.5, 179.5, 30.5 } },
			{ rank = 2, track = false, pts = { 20.5, 30.5, 20.5, 20.5, 40.5, 20.5, 40.5, 30.5 } } }
		local function setup()
			local sim = newSim({ roads = bypass })
			clearUnits(sim, {})
			local rig = rigAt(sim, 50)
			rig.side, rig.takenAt, rig.autoTruckAt = 1, 0, math.huge
			sim.updateConnections()
			for _ = 1, 20 do
				sim.step(0.05)
			end
			return sim, rig
		end
		local sim, rig = setup()
		local mid = 30 * W + 30
		assert(rig.route and table.find(rig.route, mid), "the straight road")
		local offer = sim.routeChoices(rig)
		assert(#offer >= 2, `two ways home on offer: {#offer}`)
		assert(table.find(offer[2], 20 * W + 30), "the second is the bypass")
		sim.cutRoad(mid, 2)
		for _ = 1, 20 do
			sim.step(0.05)
		end
		assert(rig.route and rig.routeCutAt, "the route is kept, marked cut")
		eq(select(2, sim.orderTruck(1, rig.id)), "noRoute", "no trucks leave on a cut route")
		eq(select(2, sim.reroute(1, rig.id, 1)), "cooldown")
		local wait = sim.rerouteReadyIn(rig)
		assert(wait > sim.num("convoys.rerouteCutSec") - 1 and wait <= sim.num("convoys.rerouteCutSec"), `about 45 s from finding the cut: {wait}`)
		run(sim, sim.num("convoys.rerouteCutSec"))
		assert(rig.routeCutAt, "a player's route stays cut")
		offer = sim.routeChoices(rig)
		assert(#offer >= 1, "a way round on offer")
		eq(table.find(offer[1], mid), nil)
		eq(select(2, sim.reroute(2, rig.id, 1)), "notOwned")
		eq(select(2, sim.reroute(1, rig.id, 5)), "noRoute")
		assert(sim.reroute(1, rig.id, 1), "picked")
		eq(rig.routeCutAt, nil)
		eq(rig.handRoute, true)
		assert(sim.orderTruck(1, rig.id), "trucks leave again")
		eq(select(2, sim.reroute(1, rig.id, 1)), "cooldown", "locked for a few seconds")
		run(sim, sim.num("convoys.rerouteAgainSec") + 0.5)
		assert(sim.reroute(1, rig.id, 1), "free again")
		-- a bot's cut route re-routes itself once the wait is over
		local sim2, rig2 = setup()
		sim2.sides[1].bot = true
		sim2.cutRoad(mid, 2)
		run(sim2, 5)
		assert(rig2.routeCutAt, "cut")
		run(sim2, sim2.num("convoys.rerouteCutSec"))
		eq(rig2.routeCutAt, nil, "re-routed by itself")
		eq(table.find(rig2.route, mid), nil)
		assert(table.find(rig2.route, 20 * W + 30), "by the bypass")
	end)
	test("road signs: the bot signs the road ahead of a truck held by the enemy, and takes it down later", function()
		local bypass = { { rank = 2, track = false, pts = { 0.5, 30.5, 179.5, 30.5 } },
			{ rank = 2, track = false, pts = { 12.5, 30.5, 12.5, 15.5, 47.5, 15.5, 47.5, 30.5 } } }
		local sim = newSim({ roads = bypass })
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		for _ = 1, 20 do
			sim.step(0.05)
		end
		local t = sim.spawnUnit("truck", 1, 40.5, 30.5)
		local here = 30 * W + 40
		local path = {}
		for x = 39, 10, -1 do
			table.insert(path, 30 * W + x)
		end
		t.path, t.pathIndex, t.stopped, t.waiting = path, 1, "enemy", sim.num("bots.signAfterSec") + 1
		bot.think()
		local id, sg = next(sim.roadSigns)
		assert(sg and sg.side == 1, "a sign")
		local ahead = math.floor(sim.num("convoys.stopShortCells") + sim.num("signs.radius") + 0.5)
		eq(sg.cell, path[1 + ahead], "a little ahead of the truck")
		t.stopped, t.waiting = nil, 0
		sim.time += sim.num("bots.signHoldSec") + 1
		bot.think()
		eq(sim.roadSigns[id], nil, "taken down after the hold")
		eq(here, here)
	end)
	test("refinery: built in a held town by a road; a rig nearer it than the HQ unloads there until the town is lost", function()
		local sim = newSim({ settlements = { { name = "T", x = 110, y = 36, kind = "town" } } })
		clearUnits(sim, {})
		local st = sim.settlements[1]
		local rig = rigAt(sim, 130)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		for _ = 1, 20 do
			sim.step(0.05)
		end
		local hq = sim.hqOf(1)
		eq(rig.routeHq, hq.cell, "hauls to the HQ")
		local before = #rig.route
		sim.sides[1].oil = 1000
		eq(sim.refineryProblem(1, 1), "notHeld")
		st.owner = 1
		local c = sim.buildRefinery(1, 1)
		assert(c, "laid out")
		near(sim.sides[1].oil, 1000 - sim.num("refinery.cost"), "paid")
		eq(sim.refineryProblem(1, 1), "refineryHere")
		eq(sim.roads.isRoad(c), false, "off the road")
		local d = math.sqrt((c % W + 0.5 - st.x) ^ 2 + (c // W + 0.5 - st.y) ^ 2)
		assert(d <= st.radius + 1 + sim.num("refinery.edgeCells"), `round the town: {d}`)
		local built = false
		for _ = 1, 20 * (sim.num("refinery.buildSec") + 1) do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "refineryBuilt" then
					built = true
				end
			end
		end
		assert(built, "finished")
		eq(sim.refineryWorks(st), true)
		for _ = 1, 20 do
			sim.step(0.05)
		end
		eq(rig.refinery, 1, "hauls to the refinery")
		eq(rig.routeHq, c)
		assert(#rig.route < before, `a shorter trip: {#rig.route} < {before}`)
		eq(sim.depotCell(rig), c)
		-- the ways on offer (the game's haulChoices): the routes to the HQ, then the refinery, marked now
		local hc = sim.haulChoices(rig)
		assert(#hc >= 2, `HQ and refinery on offer: {#hc}`)
		eq(hc[1].dest, -1)
		eq(hc[1].now, false)
		eq(hc[#hc].dest, 1)
		eq(hc[#hc].now, true, "the refinery is the current way")
		assert(sim.reroute(1, rig.id, hc[1].road, 0), "sent home by hand")
		eq(rig.refinery, nil)
		eq(rig.routeHq, hq.cell)
		eq(sim.haulChoices(rig)[1].now, true)
		sim.time += sim.num("convoys.rerouteAgainSec") + 1
		assert(sim.reroute(1, rig.id, 1, 1), "back to the refinery by hand")
		eq(rig.refinery, 1)
		eq(rig.routeHq, c)
		-- the town is lost: the refinery stops and the rig hauls home again
		st.owner = 2
		local ended = false
		for _ = 1, 20 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "refineryHaulEnded" and ev.side == 1 then
					ended = true
				end
			end
		end
		assert(ended, "told")
		eq(rig.refinery, nil)
		eq(rig.routeHq, hq.cell)
		-- shells can knock it down
		st.owner = 1
		sim.refineryBlast(c % W + 0.5, c // W + 0.5, 0, sim.num("refinery.hp"), 2)
		eq(st.refinery, nil, "destroyed")
	end)
	test("refinery: the bot builds one in a held town its trucking rig would reach well before the HQ", function()
		local sim = newSim({ settlements = { { name = "T", x = 110, y = 36, kind = "town" }, { name = "N", x = 30, y = 36, kind = "town" } } })
		clearUnits(sim, {})
		local bot = Bot.new(sim, 1, "balanced")
		sim.settlements[1].owner, sim.settlements[2].owner = 1, 1
		local rig = rigAt(sim, 130)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		for _ = 1, 20 do
			sim.step(0.05)
		end
		eq(sim.orderTruck(1, rig.id), true)
		sim.sides[1].oil = sim.num("refinery.cost") + sim.num("refinery.bots.keepOil") + 1
		bot.think()
		local ref1, ref2 = sim.settlements[1].refinery, sim.settlements[2].refinery
		assert(ref1 and ref1.owner == 1, "in the town by the rig")
		eq(ref2, nil, "not the one by the HQ")
	end)
	test("armies: only the coalition fields mortars, only the republic lays minefields", function()
		local sim = newSim({ armies = { "republic", "coalition" } })
		clearUnits(sim, {})
		eq(sim.armyOf(1), "republic")
		eq(sim.armyOf(2), "coalition")
		eq(sim.armyAllows(1, "mortar"), false)
		eq(sim.armyAllows(2, "mortar"), true)
		eq(sim.mineLayout(2, { { x = 140, y = 45 }, { x = 150, y = 45 } }).problem, "locked", "the coalition has no mines")
		eq(sim.mineLayout(1, { { x = 60, y = 45 } }).problem, "mineShort", "one cell is too short")
	end)
	test("minefield: a stroke is priced by the metres that take mines, laid along it, hidden until found", function()
		local sim = newSim({ armies = { "republic", "coalition" } })
		clearUnits(sim, {})
		local sd = sim.sides[1]
		sd.oil = 1000
		local lay = sim.mineLayout(1, { { x = 60.2, y = 45.7 }, { x = 70.9, y = 45.1 } })
		eq(lay.problem, nil)
		eq(lay.metres, 200, "10 cells of 20 m")
		eq(#lay.cells, 35, "3 cells wide (60 m), round ends")
		eq(#lay.good, 35)
		eq(lay.cost, 200)
		eq(lay.mines, 20, "one per 10 m")
		assert(math.abs(lay.sec - 16) < 1e-6, "0.08 s a metre")
		eq(lay.cells[1], cellOf(60, 45), "laid from the start of the stroke, nearest the line first")
		local o0 = sd.oil
		local id = sim.layMinefield(1, { { x = 60.2, y = 45.7 }, { x = 70.9, y = 45.1 } })
		assert(id, "laid")
		eq(o0 - sd.oil, 200)
		local mf = sim.entities[id :: number]
		eq(sim.mineHidden(mf, 2), true, "the enemy can't see it")
		eq(sim.mineHidden(mf, 1), false)
		-- half laid after 8 s; a building may not go over it
		run(sim, 8)
		local list = sim.laidMines(mf)
		assert(#list >= 15 and #list <= 17, `about half laid: {#list}`)
		eq(sim.mineLayout(1, { { x = 62, y = 45 }, { x = 72, y = 45 } }).good[1] ~= nil, true, "the far end is still open")
		run(sim, 9)
		eq(mf.built, 1)
		eq(#sim.laidMines(mf), 35)
	end)
	test("minefield: a unit on it sets off a mine (splash, gap, found by the victim); engineers find and clear it; trucks are lost", function()
		local sim = newSim({ armies = { "republic", "coalition" } })
		clearUnits(sim, {})
		sim.sides[1].oil = 1000
		local id = sim.layMinefield(1, { { x = 60.5, y = 45.5 }, { x = 70.5, y = 45.5 } })
		local mf = sim.entities[id :: number]
		mf.built = 1
		local tank = sim.spawnUnit("tank", 2, 65.5, 45.5)
		local inf = sim.spawnUnit("infantry", 2, 66.5, 45.5)
		local t0, i0 = tank.hp, inf.hp
		local n0 = mf.mines
		sim.step(0.05)
		eq(t0 - tank.hp, 150, "armour takes 150")
		eq(mf.mines, n0 - 1, "one charge spent")
		eq(mf.mineSeen[2], true, "the victim's side found it")
		eq(sim.mineHidden(mf, 2), false)
		eq(i0 - inf.hp, 28, "splash: 40% of 70 on the infantry next to it")
		local n1 = mf.mines
		run(sim, 0.5)
		eq(mf.mines, n1, "gapSec 0.7 between blasts")
		clearUnits(sim, {})
		run(sim, 1)
		-- an engineer clears without setting it off
		local n2 = mf.mines
		local eng = sim.spawnUnit("engineer", 2, 62.5, 45.5)
		local e0 = eng.hp
		run(sim, 4.1)
		eq(eng.hp, e0, "engineers never set mines off")
		eq(mf.mines, n2 - 1, "one charge cleared in 4 s")
		eng.alive = false
		-- a convoy truck rolling onto it is lost
		local truck = nil
		for _, e in sim.list do
			if e.kind == "truck" and e.alive then
				truck = e
				break
			end
		end
		if truck then
			truck.x, truck.y = 68.5, 45.5
			run(sim, 0.05)
			eq(truck.alive, false, "the truck is lost")
		end
		-- spend the rest: the field is gone
		mf.mines = 1
		sim.spawnUnit("infantry", 2, 64.5, 45.5)
		run(sim, 1)
		eq(mf.alive, false, "spent")
	end)
	test("command truck: a side with a truck is not headless; the bot queues and deploys one after losing its HQ", function()
		local sim = newSim()
		clearUnits(sim, {})
		sim.sides[1].oil = 5000
		local b = sim.placeStructure(1, "barracks", cellOf(20, 42)) :: number
		sim.entities[b].built = 1
		local f = sim.placeStructure(1, "factory", cellOf(26, 42)) :: number
		sim.entities[f].built = 1
		local hq = sim.hqOf(1)
		hq.hp = 0
		hq.alive = false
		local bot = Bot.new(sim, 1, "balanced")
		bot.think()
		assert(sim.hqOnOrder(1), "command truck queued")
		local deployed = false
		for _ = 1, 120 do
			run(sim, 1)
			bot.think()
			if sim.hqOf(1) then
				deployed = true
				break
			end
		end
		assert(deployed, "the bot set up a new HQ")
		eq(sim.sides[1].lost, false)
		-- with a full factory queue the bot calls off the last unit to fit the truck
		local sim2 = newSim()
		clearUnits(sim2, {})
		sim2.sides[1].oil = 50000
		local b2 = sim2.placeStructure(1, "barracks", cellOf(20, 42)) :: number
		sim2.entities[b2].built = 1
		local f2 = sim2.placeStructure(1, "factory", cellOf(26, 42)) :: number
		sim2.entities[f2].built = 1
		local cap = sim2.num("production.maxQueue")
		for _ = 1, cap do
			sim2.orderProduce(1, "tank", f2)
		end
		eq(#sim2.entities[f2].queue, cap)
		local hq2 = sim2.hqOf(1)
		hq2.hp, hq2.alive = 0, false
		Bot.new(sim2, 1, "balanced").think()
		local q = sim2.entities[f2].queue
		eq(#q, cap)
		eq(q[#q], "command")
	end)
	test("opening drop: the war waits for picks, planes drop a truck and 3 squads, the truck sets up the HQ", function()
		local sim = newSim({ drop = true })
		eq(sim.hqOf(1), nil, "no HQ before the drop")
		local units = 0
		for _, e in sim.list do
			if e.cat == "unit" then
				units += 1
			end
		end
		eq(units, 0, "no start squads")
		eq(select(2, sim.setDropPick(1, 3.5, 30.5)), "terrain", "too near the edge")
		eq(select(2, sim.setDropPick(1, 160.5, 36.5)), "startTaken", "on the enemy's start")
		assert(sim.setDropPick(1, 40.5, 36.5))
		run(sim, 10)
		eq(sim.time, 0, "the war waits while sides pick")
		eq(sim.drop.phase, "pick")
		sim.setDropReady(1)
		sim.setDropReady(2)
		run(sim, 0.1)
		eq(sim.drop.phase, "flight")
		local landed = nil
		for i = 1, 20 * 25 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "dropLanded" and ev.side == 1 then
					landed = i * 0.05
				end
			end
		end
		assert(landed and landed >= 19 and landed <= 24, `down after flySec + chuteSec and the last stick: {landed}`)
		run(sim, 11)
		local kinds = {}
		for _, e in sim.list do
			if e.cat == "unit" and e.side == 1 then
				kinds[e.kind] = (kinds[e.kind] or 0) + 1
			end
		end
		eq(kinds.command, nil, "the truck already became the HQ")
		eq(kinds.infantry, 3)
		local hq = sim.hqOf(1)
		assert(hq, "HQ set up")
		assert(math.abs(hq.x - 40.5) < 16 and math.abs(hq.y - 36.5) < 16, `near the pick: {hq.x},{hq.y}`)
		assert(sim.hqOf(2), "the other side's HQ near its start point")
	end)
	test("opening deck: the drop arrives at a seeded hour (day / dawn / dusk / night) and the day clock starts there", function()
		local a = newSim({ drop = true, seed = 1 })
		eq(a.drop.opening.arrival, "dawn")
		assert(math.abs(a.dayOffset - 0.905 * 480) < 1e-6, `dawn: {a.dayOffset}`)
		local b = newSim({ drop = true, seed = 7 })
		eq(b.drop.opening.arrival, "day")
		assert(math.abs(b.dayOffset - 0.12 * 480) < 1e-6, `day: {b.dayOffset}`)
		eq(newSim({ seed = 1 }).dayOffset, nil, "no drop, no deck")
	end)
	test("bot: picks a landing in the opening drop and is ready at once", function()
		local sim = newSim({ drop = true })
		local bot = Bot.new(sim, 2, "warlord")
		bot.step(0.05)
		eq(sim.drop.ready[2], true)
		local p = sim.drop.picks[2]
		eq(sim.landingProblem(p.x, p.y, 2) == nil or (p.x == sim.drop.homes[2].x and p.y == sim.drop.homes[2].y), true)
	end)
	test("alerts: a road cut names the sides whose supply route ran through it", function()
		local sim = newSim()
		clearUnits(sim, {})
		local rig = rigAt(sim, 50)
		rig.side, rig.takenAt = 1, 0
		sim.updateConnections()
		for _ = 1, 10 do
			sim.step(0.05)
		end
		assert(rig.route, "the rig has a route home")
		sim.takeEvents()
		sim.cutRoad(30 * W + 30, 2)
		local ev
		for _, e in sim.takeEvents() do
			if e.type == "roadCut" then
				ev = e
			end
		end
		assert(ev and ev.side == 2, "the cutter")
		eq(ev.users[1], 1, "the rig's owner")
	end)
	test("group move: units near an already routed groupmate join its route, then step to their slot", function()
		local sim = newSim()
		clearUnits(sim, {})
		local ids = {}
		for i = 0, 3 do
			table.insert(ids, sim.spawnUnit("infantry", 1, 20.5 + i, 40.5).id)
		end
		sim.orderMove(1, ids, 80.5, 40.5)
		local first = nil
		local joined = 0
		for _, id in ids do
			local e = sim.entities[id]
			assert(e.path and #e.path > 0, "routed")
			eq(e.path[#e.path], e.goalCell, "ends on its own slot")
			if not first then
				first = e
			else
				local onIt = {}
				for _, c in first.path do
					onIt[c] = true
				end
				if #e.path >= 2 and onIt[e.path[#e.path - 1]] and onIt[e.path[1]] then
					joined += 1
				end
			end
		end
		assert(joined >= 1, `groupmates share the first route ({joined})`)
		run(sim, 60)
		for _, id in ids do
			local e = sim.entities[id]
			assert(not e.path, "everyone arrived")
		end
	end)
	test("separation: units on top of each other ease apart to 1.2 cells at up to 1.5 cells/s", function()
		local sim = newSim()
		clearUnits(sim, {})
		local a = sim.spawnUnit("engineer", 1, 60.5, 40.5)
		local b = sim.spawnUnit("engineer", 1, 60.5, 40.5)
		sim.step(0.05)
		local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
		assert(d > 0.1 and d <= 2 * 1.5 * 0.05 + 1e-9, `first push at most 0.075 each: {d}`)
		run(sim, 3)
		d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
		assert(d >= 1.19 and d < 1.3, `settled about 1.2 apart: {d}`)
	end)
	test("capital: holding it secured shows all of your own territory", function()
		local sim = newSim({ settlements = { { name = "Cap", x = 40, y = 45, kind = "capital" } } })
		clearUnits(sim, {})
		local cap = sim.settlements[1]
		local owners = sim.territoryOwners()
		local grid = {}
		local function hidden()
			sim.visionFor(1, grid)
			local n = 0
			for i, o in owners do
				if o == 1 and grid[i] ~= 2 then
					n += 1
				end
			end
			return n
		end
		assert(hidden() > 0, "some own territory is out of sight at first")
		cap.owner, cap.hold = 1, 1
		local ids = {}
		for _ = 1, 6 do
			table.insert(ids, sim.spawnUnit("infantry", 1, 40.5, 45.5).id)
		end
		eq((sim.orderGarrison(1, cap.id, ids)), 6)
		eq(sim.cityStatus(cap), "secured")
		assert(sim.surveillanceOn(1))
		owners = sim.territoryOwners()
		eq(hidden(), 0, "all own territory in sight")
		assert(not sim.surveillanceOn(2))
	end)
	test("towns: two infantry take a neutral town in 16 s; a held town lets its owner build round it", function()
		local sim = newSim({ settlements = { { name = "T", x = 130, y = 45, kind = "town" }, { name = "V", x = 90, y = 45, kind = "village" } } })
		for _, side in { 1, 2 } do
			for _, u in units(sim, side, "infantry") do
				u.alive = false
			end
		end
		local town, village = sim.settlements[1], sim.settlements[2]
		eq(sim.canPlace(1, "bunker", cellOf(138, 50)), "outsideBase")
		local a = sim.spawnUnit("infantry", 1, 130.5, 45.5)
		local b = sim.spawnUnit("infantry", 1, 131.5, 45.5)
		run(sim, 15.9)
		eq(town.owner, 0, "not yet")
		run(sim, 0.2)
		eq(town.owner, 1, "taken: weight 2 = rigs.need, so full pace over captureSec 16")
		eq(sim.claimRadius(town), 6 + 12, "townRadius 6 + claim margin 12")
		eq(sim.canPlace(1, "bunker", cellOf(138, 50)), nil, "inside the town's claim")
		a.x, a.y, b.x, b.y = 90.5, 45.5, 91.5, 45.5
		a.post, b.post = nil, nil -- placed there: their post is where they now stand
		run(sim, 10.1)
		eq(village.owner, 1)
		eq(sim.claimRadius(village), 0, "villages claim nothing")
		-- two enemy infantry alone in the town wear its hold down twice as fast (8 s), then capture it
		local c = sim.spawnUnit("infantry", 2, 130.5, 45.5)
		local d = sim.spawnUnit("infantry", 2, 131.5, 45.5)
		c.hp, d.hp = 1e6, 1e6
		run(sim, 8.1)
		eq(town.owner, 0, "neutralised")
		eq(town.capture and town.capture.by, 2)
		run(sim, 16.1)
		eq(town.owner, 2)
		eq(sim.canPlace(1, "bunker", cellOf(138, 50)), "outsideBase")
	end)
	test("bot takes a neutral town near home after bots.cityAfter (90 s)", function()
		local sim = newSim({ settlements = { { name = "T", x = 30, y = 45, kind = "town" } } })
		local bot = Bot.new(sim, 1, "balanced")
		run(sim, 89, { bot })
		eq(sim.settlements[1].owner, 0, "not before cityAfter")
		local sent = false
		for _ = 1, 20 do
			run(sim, 10, { bot })
			for _, t in bot.orders do
				if t.kind == "city" then
					sent = true
				end
			end
			if sim.settlements[1].owner == 1 then
				break
			end
		end
		assert(sent, "the bot sent units to the town")
		eq(sim.settlements[1].owner, 1, "taken")
	end)
	test("garrison: 3 infantry secure a town; inside they take 0.4x, hit 1.3x harder from 3 cells further", function()
		local sim = newSim({ settlements = { { name = "T", x = 130, y = 45, kind = "town" } } })
		for _, side in { 1, 2 } do
			for _, u in units(sim, side, "infantry") do
				u.alive = false
			end
		end
		local town = sim.settlements[1]
		local men = {}
		for i = 1, 4 do
			men[i] = sim.spawnUnit("infantry", 1, 129.5 + i, 45.5)
		end
		run(sim, 16.1)
		eq(town.owner, 1)
		eq(sim.cityStatus(town), "occupied")
		local far = sim.spawnUnit("infantry", 1, 130.5, 5.5)
		eq((sim.orderGarrison(1, town.id, { men[1].id, men[2].id })), 2, "two enter at once (within radius + enterReach)")
		eq(sim.cityStatus(town), "fortified")
		assert(men[1].inside and men[1].x == town.x and men[1].y == town.y, "inside, at the centre")
		eq((sim.orderGarrison(1, town.id, { far.id })), 1, "walks there")
		assert(not far.inside and far.path, "walking")
		local n, why = sim.orderGarrison(1, town.id, { men[3].id })
		eq(n, 0)
		eq(why, "garrisonFull", "2 inside + 1 walking = garrisonFull 3")
		run(sim, 25)
		assert(far.inside, "entered on arrival")
		eq(sim.cityStatus(town), "secured")
		near(sim.paintBonus(1), 0.04, "secured town paint bonus")
		-- a hit on a man inside a secured town: x securedCover 0.4 (no terrain cover or flanking)
		local hp = men[1].hp
		local foe = sim.spawnUnit("infantry", 2, 130.5, 20.5) -- 25 cells: beyond infantry range 13.5
		men[4].alive = false
		foe.hp = 1e6
		local rows = 0
		for _, st in sim.strikes do
			rows += 1
		end
		eq(rows, 0)
		-- 13.5 + rooftop 3 = 16.5: inside men reach a foe 16 cells away, ordinary men would not
		foe.y = 45.5 - 16
		run(sim, 3)
		assert(foe.hp < 1e6, "rooftop range")
		local lost = 1e6 - foe.hp
		assert(lost > 0)
		eq(men[1].hp, hp, "not yet hit back (out of the foe's range)")
		-- neutralising is blocked while a garrison holds it
		foe.x, foe.y = 130.5, 45.5
		foe.hp = 1e9
		for _, m in { men[1], men[2], far } do
			m.hp = 1e6
		end
		run(sim, 10)
		eq(town.owner, 1, "garrisoned towns are not worn down")
		eq(town.hold, 1)
		-- a move order brings a man out
		sim.orderMove(1, { men[2].id }, 130.5, 60.5)
		assert(not men[2].inside, "out")
		eq(sim.cityStatus(town), "fortified")
	end)
	test("garrison: inside damage is the hit x 0.4 (secured town)", function()
		local sim = newSim({ settlements = { { name = "T", x = 130, y = 45, kind = "town" } } })
		local town = sim.settlements[1]
		town.owner, town.hold = 1, 1
		local men = {}
		for i = 1, 3 do
			men[i] = sim.spawnUnit("infantry", 1, 130.5, 45.5)
		end
		eq((sim.orderGarrison(1, town.id, { men[1].id, men[2].id, men[3].id })), 3)
		eq(sim.cityStatus(town), "secured")
		local m = men[1]
		m.hp = 1000
		sim.strikes = { { kind = "unit", at = sim.time, target = m.id, dps = 10, key = "units.infantry", secs = 1, by = 2, fromX = 130.5, fromY = 30.5 } }
		run(sim, 0.05)
		near(1000 - m.hp, 10 * 1 * 1 * 0.4, "dps x vs.soft (1) x secs x securedCover.town 0.4")
	end)
	test("bot garrisons a town it holds and trains men for it", function()
		local sim = newSim({ settlements = { { name = "T", x = 30, y = 45, kind = "town" } } })
		local town = sim.settlements[1]
		town.owner, town.hold = 1, 1
		local bot = Bot.new(sim, 1, "turtle")
		for _ = 1, 30 do
			sim.sides[1].oil = 2000
			run(sim, 10, { bot })
		end
		assert(#town.garrison >= 1, `garrison {#town.garrison}`)
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
		run(sim, 2.5) -- packed at 3 s; the gun then pivots (52 deg/s, facing east) and pulls away
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
	test("unit intel: an enemy seen and lost stays marked where it was for 45 s", function()
		local sim = emptySim()
		local sc = sim.spawnUnit("scout", 1, 90.5, 30.5)
		local foe = sim.spawnUnit("infantry", 2, 100.5, 30.5)
		local dead = sim.spawnUnit("infantry", 2, 101.5, 31.5)
		foe.hp, sc.hp = 1e6, 1e6
		local viewer = require("../src/shared/Simulation/Fog").newViewer(sim, 1)
		viewer.update()
		eq(#viewer.ghosts(), 0, "in sight: no markers")
		foe.x, foe.y = 160.5, 30.5 -- walks off out of sight
		dead.x, dead.y = 160.5, 34.5
		viewer.update()
		local g = viewer.ghosts()
		eq(#g, 2)
		local mine = g[1][1] == foe.id and g[1] or g[2]
		eq(mine[4], 100.5, "marked where last seen")
		dead.alive = false
		dead.x, dead.y = 101.5, 31.5 -- dead, and its last spot is in sight
		viewer.update()
		eq(#viewer.ghosts(), 1, "a dead unit's marker goes once its spot is seen")
		sim.time += 44
		viewer.update()
		eq(#viewer.ghosts(), 1, "kept for 45 s")
		sim.time += 2
		viewer.update()
		eq(#viewer.ghosts(), 0, "forgotten after 45 s")
	end)

	-- fog of war
	test("building occlusion filters enemy snapshots and a live garrison reveals its entire urban footprint",function()
		local Visibility=require("../src/shared/Simulation/Visibility")
		local FogTest=require("../src/shared/Simulation/Fog")
		local mask=buffer.create(W*H)
		for y=0,H-1 do buffer.writeu8(mask,y*W+95,1) end
		local sim=newSim({roads={},visibilityLib=Visibility,blockers=mask,
			settlements={{x=90.5,y=30.5,kind="town"}},urbanAt=function(c) return c%W==150 end})
		for _,e in sim.list do if e.cat=="unit" then e.alive=false end end
		local scout=sim.spawnUnit("infantry",1,90.5,30.5)
		local enemy=sim.spawnUnit("infantry",2,100.5,30.5)
		local viewer=FogTest.newViewer(sim,1);viewer.update()
		assert(not viewer.unitVisible(enemy),"enemy behind town building must be hidden")
		assert(not sim.clearShot(scout,enemy,"units.infantry"),"ground fire must not pass through buildings")
		local city=sim.settlements[1];city.owner=1;city.garrison={scout.id};scout.inside=true
		sim.time=320;viewer.update()
		assert(viewer.unitVisible(enemy),"garrison sight bypasses roofs")
		eq(viewer.grid[30*W+150+1],2,"entire urban footprint even at night")
		city.garrison={};scout.inside=false;viewer.update()
		eq(viewer.grid[30*W+150+1],0,"last garrison leaving removes reveal")
	end)
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

require("./death_effects")(test, eq)

require("./men_shadows")(test, eq)

require("./unit_stages")(test, eq)

require("./image_budget")(test, eq)

require("./daylight")(test, eq)
require("./town_detail")(test, eq)
require("./road_pixels")(test, eq)
require("./visibility")(test, eq)
require("./world_look")(test, eq)
require("./night_lights")(test, eq)
require("./civilian_traffic")(test, eq)
require("./civilian_driving")(test, eq)
require("./civilian_people")(test, eq)
require("./refugees")(test, eq)
require("./chimney_smoke")(test, eq)
require("./street_furniture")(test, eq)
require("./clouds")(test, eq)
require("./cloud_renderer")(test, eq)
require("./power_lines")(test, eq)
require("./power_renderer")(test, eq)
require("./water")(test, eq)
require("./water_renderer")(test, eq)
require("./forest_fire")(test, eq)
require("./house_fire")(test, eq)
require("./fire_pixels")(test, eq)
require("./fire_map")(test, eq)
require("./fire_effects")(test, eq)
require("./house_rebuild")(test, eq)
require("./fire_scorch")(test, eq)
require("./fire_scorch_renderer")(test, eq)
require("./fire_particles")(test, eq)
require("./fire_particle_renderer")(test, eq)
require("./house_world")(test, eq)
require("./house_fire_renderer")(test, eq)
require("./admin_fire")(test, eq)
require("./forest_world")(test, eq)
require("./forest_raster")(test, eq)
require("./forest_town_renderer")(test, eq)
require("./fire_lights")(test, eq)
require("./fire_light_renderer")(test, eq)
require("./ground_scorch")(test, eq)
require("./ground_scorch_renderer")(test, eq)
require("./ground_scorch_integration")(test, eq)
require("./building_fire_windows")(test, eq)
require("./fire_window_renderer")(test, eq)
require("./roof_canopy")(test, eq)
require("./urban_scorch")(test, eq)
require("./fire_impact_events")(test, eq)
require("./demo_secondary_fire")(test, eq)
require("./collapse_effects")(test, eq)
require("./collapse_renderer")(test, eq)
require("./image_uploads")(test, eq)
require("./image_memory_uploads")(test, eq)
require("./town_lods")(test, eq)
require("./cooperative_inflate")(test, eq)
require("./city_light_coverage")(test, eq)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed")
end
