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

print("Milestone 1B simulation (needs RulesData)")
if fs.isFile(rulesPath) then
	local Sim = require("../src/shared/Simulation/Sim")
	local Bot = require("../src/shared/Simulation/Bot")
	local Movement = require("../src/shared/Simulation/Movement")
	local rulesData = require("../src/shared/GameData/RulesData") :: any
	local CLASS = { infantry = "soft", at = "soft", tank = "armour", scout = "soft" }
	local function newSim()
		return Sim.new({
			rules = Rules.new(rulesData) :: any,
			movement = Movement,
			paceAt = function(_kind, x, y)
				return if x >= 0 and y >= 0 and x < 60 and y < 20 then 1 else 0
			end,
			unitClass = function(kind)
				return CLASS[kind] or "soft"
			end,
			starts = { { x = 5, y = 10 }, { x = 55, y = 10 } },
			rigs = { { x = 14, y = 10 }, { x = 46, y = 10 } },
			width = 60,
			height = 20,
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
		for _, e in sim.entities do
			if e.side == side and e.kind == kind then
				table.insert(list, e)
			end
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		return list
	end
	local function ids(list)
		local out = {}
		for _, e in list do
			table.insert(out, e.id)
		end
		return out
	end

	test("setup: HQs 3000 hp, 600 oil, 3 infantry per side, neutral rigs", function()
		local sim = newSim()
		eq(sim.sides[1].oil, 600)
		eq(sim.entities[sim.sides[1].hqId].hp, 3000)
		eq(#units(sim, 1, "infantry"), 3)
		eq(#units(sim, 2, "infantry"), 3)
		eq(#units(sim, 0, "rig"), 2)
	end)

	test("production: costs 36, takes 7 s, queue capped at 6, refuses without oil", function()
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
		assert(not ok and why == "queue full", why)
		sim.sides[2].oil = 10
		local ok2, why2 = sim.orderProduce(2, "infantry")
		assert(not ok2 and why2 == "not enough oil", why2)
		local ok3 = sim.orderProduce(1, "tank")
		assert(not ok3, "HQ must not build tanks")
	end)

	test("orders for the other side's units are refused", function()
		local sim = newSim()
		local enemy = ids(units(sim, 2, "infantry"))
		local refused = sim.orderMove(1, enemy, 30, 10)
		eq(#refused, 3)
		for _, e in units(sim, 2, "infantry") do
			assert(e.target == nil, "enemy unit got an order")
		end
	end)

	test("rig capture takes 12 s with weight 2, gives 3 trucks, trucks deliver oil", function()
		local sim = newSim()
		local inf = units(sim, 1, "infantry")
		for i, u in inf do -- stand three infantry (weight 3 >= rigs.need 2) on the rig
			u.x, u.y = 14 + (i - 2) * 0.5, 10
		end
		run(sim, 11.9)
		eq(#units(sim, 1, "rig"), 0, "not before 12 s")
		run(sim, 0.2)
		eq(#units(sim, 1, "rig"), 1, "captured")
		eq(#units(sim, 1, "truck"), 3, "startIdle trucks")
		sim.takeEvents()
		local oilBefore = sim.sides[1].oil
		local delivered = 0
		for _ = 1, 20 * 120 do
			sim.step(0.05)
			for _, ev in sim.takeEvents() do
				if ev.type == "delivered" then
					delivered += ev.oil
				end
			end
		end
		assert(delivered > 0, "no truck delivered in 120 s")
		local trickle = 0.5 * 120
		assert(math.abs(sim.sides[1].oil - (oilBefore + delivered + trickle)) < 1e-6, "oil = deliveries + HQ trickle")
	end)

	test("combat: infantry vs infantry, 8 damage per shot, kill in 13 shots", function()
		local sim = newSim()
		local a = units(sim, 1, "infantry")[1]
		local b = units(sim, 2, "infantry")[1]
		for _, e in sim.entities do -- clear the field except a and b and the HQs
			if e.cat == "unit" and e ~= a and e ~= b then
				sim.entities[e.id] = nil
			end
		end
		a.x, a.y, b.x, b.y = 30, 10, 32, 10
		run(sim, 0.05)
		eq(b.hp, 92, "first shot")
		run(sim, 12)
		assert(b.hp <= 0 and sim.entities[b.id] == nil, `b hp {b.hp}`)
	end)

	test("armour facing: rear hits do 1.35x, front 0.7x", function()
		local sim = newSim()
		local tank = sim.spawnUnit("tank", 2, 30, 10)
		tank.heading = 0 -- facing east
		local front = sim.spawnUnit("infantry", 1, 32, 10)
		for _, e in sim.entities do
			if e.cat == "unit" and e ~= tank and e ~= front then
				sim.entities[e.id] = nil
			end
		end
		tank.cooldown = math.huge -- tank holds fire
		local hp0 = tank.hp
		run(sim, 0.05)
		near(hp0 - tank.hp, 8 * 0.25 * 0.7, "front")
		front.x = 28
		front.cooldown = 0
		local hp1 = tank.hp
		run(sim, 0.05)
		near(hp1 - tank.hp, 8 * 0.25 * 1.35, "rear")
	end)

	test("trucks are shootable and their cargo is lost", function()
		local sim = newSim()
		local truck = sim.spawnUnit("truck", 1, 30, 10) -- rigless truck drives home (west) past an ambush
		truck.cargo = 50
		for i = 1, 3 do
			sim.spawnUnit("infantry", 2, 20, 8.5 + i * 0.5)
		end
		local before = sim.sides[1].oil
		run(sim, 30)
		assert(sim.entities[truck.id] == nil, "truck survived the ambush")
		assert(sim.sides[1].oil < before + 50, "cargo was credited")
	end)

	test("destroying the HQ ends the match", function()
		local sim = newSim()
		local hq2 = sim.entities[sim.sides[2].hqId]
		hq2.hp = 5
		local inf = units(sim, 1, "infantry")
		sim.orderAttack(1, ids(inf), hq2.id)
		run(sim, 200)
		eq(sim.winner, 1)
		assert(sim.sides[2].lost)
	end)

	test("bot captures rigs and trains infantry within 5 minutes", function()
		local sim = newSim()
		local bot = Bot.new(sim, 2)
		run(sim, 300, { bot })
		assert(#units(sim, 2, "rig") >= 1, "bot owns no rig")
		assert(#units(sim, 2, "infantry") > 3 or sim.winner ~= nil, "bot did not train")
	end)
else
	print("  skip  RulesData.luau not generated")
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
