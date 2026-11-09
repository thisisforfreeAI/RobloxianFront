--!strict
--[[
	Sim: the authoritative match simulation (milestone 1B, parity pass). Pure Luau (no Roblox services),
	so it runs in Lune tests and on the server. MatchService owns one Sim and calls Sim.step at
	match.tickHz (20 Hz). Rules must be the match rules (GameData/RulesMatch, cell scale 3).

	Every system below was traced from WarFront 0.1.0's own match code. Lines marked APPROX are
	simplifications of the game's logic; lines marked UNCONFIRMED are guesses that still need tracing.
	Nothing else is invented.

	Tick order (as the game): connections every 10th tick, production, strikes landing, combat and
	movement, rigs, rig routes + trucks, HQ oil trickle, verdict.

	Economy     nations start with match.startOil and trucks.startIdle idle light trucks. A built HQ
	            trickles rigs.hqOil per second (x the nation's oil multiplier).
	Production  per producer (HQ, barracks, factory; units.<k>.from), paid up front (units.<k>.cost),
	            units.<k>.buildSec each, production.maxQueue, match.unitCap counts units plus every
	            queue. Refusals in the game's order: blocked, notOperational, requires, queueFull,
	            unitCap, oil. Slice units: infantry, engineer (HQ); infantry, AT, mortar (barracks);
	            tank, IFV, artillery, scout car (factory).
	Buildings   barracks, factory, bunker and AT gun (the game's placeStructure). Placement check in the game's order:
	            footprint inside the map and on buildable terrain ("terrain"), no road within the
	            footprint + max(1, round(footprint x roadClearShare)) + roadClearPad ("onRoad"), no rig
	            within footprint + rigs.padCells ("onRig"), no structure within the two footprints +
	            production.spacing ("spacing"), does not cut the passable ground around it
	            ("sealsWay", the game's seal check), every footprint cell in own territory
	            ("outsideBase", see Territory), no enemy structure within build.enemyGap + footprint
	            and no enemy rig within that + rigs.radius ("nearEnemy"), requirements built
	            ("requires"), oil. Paid at once; goes up over structures.<k>.buildSec; the footprint
	            (production.footprint.<kind> cells round the centre) blocks movement from placement on
	            (HQs too), except that trucks may enter their own HQ's yard. A facility below
	            production.damagedBelow of its hp stops working and does not repair itself; otherwise
	            buildings repair production.repairPerSec of hp per second 5 s after the last hit.
	Rigs        capture weight = sum over units within rigs.radius with dps > 0 (not air or sea) of
	            max(0.25, units.<k>.capture). One pressing side captures at
	            max(minPace, min(1, weight / need)) / captureSec per second; any rival present
	            freezes progress (contested); otherwise unfinished progress decays at decayPerSec.
	            An enemy rig is taken directly (no neutral step) unless an armed, built structure of its
	            owner stands within rigs.radius x rigs.guardShare. A taken rig keeps its tank and starts
	            pumping rigs.takeoverSec later: rigs.oilPerSec x rich into a tank of rigs.tank.
	            Rich rigs: floor(rigs x rigs.rich.richCount) rigs farthest from the starts pump
	            x rigs.rich.richMult.
	Trucks      a rig is connected when a road network near it (convoys.offRoadReach) reaches the
	            owner's HQ (offRoadReach + HQ footprint). A connected rig gets a road route home
	            (Shared.Simulation.Roads). The first time after each capture that the route exists,
	            one idle truck is sent automatically if the nation has one. More trucks can be bought
	            (orderTruck): idle trucks first, otherwise trucks.kinds.light.cost oil; at most
	            trucks.perRig per rig. Trucks drive out from the HQ, queue at the rig, the first in
	            line loads trucks.loadPerSec up to capacity and leaves when full, or when the tank is
	            empty and it holds at least min(truckMinLoad, capacity) and half its capacity. At the
	            HQ it unloads for trucks.unloadSec, the oil is credited (x oil multiplier) and it goes
	            back out. If its rig is lost it returns home and joins the idle pool. A destroyed truck
	            is gone with its load. Speed: convoys.speed x paceShare x roads.classes.<c>.truck on
	            road cells (x1 off road).
	Combat      each shooter picks the nearest valid enemy unit in range (attack orders first), then
	            trucks, then structures (armed structures count as 4x closer). A shot every reloadSec
	            (+/- combat.reloadJitter); the hit lands after the shot's flight (cells/s: bullets 70,
	            cannon 38, rocket 22, shell 13, mortar 6.5). Unit hit = dps x reloadSec x vs[target
	            armour] x (armour.movingFire if an armoured shooter moves) x terrain cover (1 - cover, or
	            flank rules when hit from behind combat.flankDeg) x armour facing (armoured targets).
	            Splash (units.<k>.splash > 0): the hit x bunching (1 + min(bunchMax, bunchSplash x (foot
	            soldiers within bunchCells - 1))), and half of it on the target's comrades within splash.
	            Artillery fire (nato "artillery": mortar, artillery) ignores flanking and armour facing.
	            Structure hit = dps x reloadSec x vs.structure. Truck hit = dps x reloadSec x vs.armour.
	            Every built, working, armed building fires (HQ, bunker, AT gun): nearest unit, else truck.
	Artillery   mortars and artillery fire only after standing still mortar.setupSec / artillery.setupSec;
	            after firing they are revealed to the enemy for artillery.revealSec (artillery.revealCells
	            of vision round them) and must pack (packSec) before moving. Mortars: no target inside
	            mortar.minRange, and with fog on only targets on cells their nation sees (vision map
	            refreshed every mortar.spotEveryTicks) unless the target is revealed; on an attack order
	            they hold between minRange x backOffShare and the reach (Kat, APPROX re-plan rule).
	Scouts      deployRecon: the scout stops and sees intel.scoutReconRadius (not shortened by night) for
	            intel.scoutDeploySec; any order packs it; then intel.scoutCooldownSec before it can
	            deploy again.
	HQ loss     a nation whose HQ dies with no active factory is eliminated at once (all its units and
	            buildings die, its rigs turn neutral and empty); with one it has hqLoss.graceSec to
	            rehouse. The command truck that does that is not in the slice, so the nation is out
	            when the grace runs out. The last nation standing wins (match.victory "annihilation").

	APPROX: unit movement follows Pathing (see its header for what is approximate); trucks follow their
	        route cell by cell without the game's curve-following, column spacing, stalls or enemy holds;
	        unit spawn spots (door/rally) are simplified; the random numbers (reload jitter) do not
	        follow the game's seeded sequence; tie order between equally near targets may differ;
	        rig routes refresh every 10 ticks per rig; units caught inside a new footprint step to the
	        nearest free cell centre; vehicles (tank, IFV) follow paths like foot units (no drive model,
	        acceleration or turning).
	UNCONFIRMED: the territory edge noise uses the map's seed (the game uses its match seed); where
	        the headless check sits in the tick order.
	UNCONFIRMED (older): new units start with no face direction and an empty shot timer; a dead nation's
	        trucks are removed; a firing vehicle's hull keeps its heading (turrets not modelled).
	Engineers can be trained (the HQ lists them) but their building and repair work is not in the slice.
	Fog: visionFor / nightAmount below; the server filters snapshots per side (Shared.Simulation.Fog).
	Not in the slice: line of sight (the game's only blockers are settlement buildings), weather, veterancy, smoke, rig damage,
	        settlements, refineries, rail, events, SAM, radar, rocket artillery (salvo barrages),
	        drones, craters, the command truck, power lines and dams.
]]

local Sim = {}

export type Rules = {
	number: (any, string) -> number,
	has: (any, string) -> boolean,
	flag: (any, string) -> boolean,
	text: (any, string) -> string,
}

export type Entity = { [string]: any }

export type Side = {
	oil: number,
	hqId: number,
	lost: boolean,
	trucksIdle: number,
	oilMult: number,
	oilEarned: number,
}

export type MapInfo = {
	width: number,
	height: number,
	terrainAt: (cell: number) -> string?,
	urbanAt: ((cell: number) -> boolean)?,
	roads: { any },
}

export type Deps = {
	rules: Rules,
	movement: any?, -- unused since unit pathfinding (kept for older callers)
	roadsLib: any, -- Shared.Simulation.Roads
	pathingLib: any, -- Shared.Simulation.Pathing
	territoryLib: any, -- Shared.Simulation.Territory
	valueNoise: any, -- Shared.Utilities.ValueNoise
	rng: any, -- Shared.Utilities.Rng
	map: MapInfo,
	starts: { { x: number, y: number } }, -- cell centres
	rigs: { { x: number, y: number, name: string? } },
	seed: number?,
}

export type Event = { type: string, [string]: any }

local TRUCK = "truck"
local BULLET_SPEED = 70 -- cells/s, the game's bullet flight speed
-- cells/s, the game's shot speeds for the other weapons
local SHOT_SPEED: { [string]: number } = {
	cannon = 38, rocket = 22, missile = 18, shell = 13, salvo = 9.5, bomb = 11, mortar = 6.5, barrage = 11,
}

function Sim.new(deps: Deps)
	local r = deps.rules
	local map = deps.map
	local Roads = deps.roadsLib
	local W, H = map.width, map.height

	local self = {
		deps = deps,
		entities = {} :: { [number]: Entity },
		list = {} :: { Entity }, -- creation order (the game iterates in creation order)
		sides = {} :: { [number]: Side },
		nextId = 1,
		time = 0,
		ticks = 0,
		winner = nil :: number?,
		events = {} :: { Event },
		strikes = {} :: { any },
	}

	local cache: { [string]: number } = {}
	local function num(key: string): number
		local v = cache[key]
		if v == nil then
			v = r:number(key)
			cache[key] = v
		end
		return v :: number
	end
	self.num = num
	local function numOr(key: string, default: number): number
		return if r:has(key) then num(key) else default
	end
	local textCache: { [string]: string } = {}
	local function text(key: string): string
		local v = textCache[key]
		if v == nil then
			v = r:text(key)
			textCache[key] = v
		end
		return v :: string
	end

	local seed = deps.seed or 1
	local matchSeed = seed
	local function rand(): number -- APPROX: not the game's sequence
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end

	local function event(e: Event)
		table.insert(self.events, e)
	end

	---------------------------------------------------------------- map, roads

	local function terrainPassable(t: string): boolean
		local key = `terrain.{t}.passable`
		return r:has(key) and r:flag(key)
	end
	local classTruck = {}
	for c = 0, 3 do
		classTruck[c] = 1 / math.max(0.05, num(`roads.classes.{Roads.CLASS_NAME[c]}.truck`))
	end
	local hqFoot = num("production.footprint.hq")
	local offReach = math.max(1, num("convoys.offRoadReach"))
	local roads = Roads.build({
		width = W,
		height = H,
		terrainAt = map.terrainAt,
		passable = terrainPassable,
		roads = map.roads or {},
		bridgeHalf = num("movement.bridgeDeck.half"),
		truckCost = classTruck,
		offRoadCost = math.max(1, num("convoys.offRoadCost")) * classTruck[1],
		offRoadReach = offReach + hqFoot,
	})
	self.roads = roads
	local function cellAt(x: number, y: number): number
		return roads.cellAt(x, y)
	end
	local function centre(cell: number): (number, number)
		return cell % W + 0.5, cell // W + 0.5
	end

	-- Unit pace multiplier on a point (the game's paceOn; speed itself comes from units.<k>.speed).
	local function paceAt(kind: string, x: number, y: number): number
		local c = cellAt(x, y)
		if c < 0 or not roads.passable(c) then
			return 0
		end
		local move = text(`units.{kind}.move`)
		if roads.isRoad(c) and move ~= "sea" and text(`units.{kind}.armour`) ~= "air" then
			local cu = num(`roads.classes.{Roads.CLASS_NAME[roads.classAt(c)]}.unit`)
			return 1 + (num(`units.{kind}.roadMult`) - 1) * cu
		end
		local t = roads.terrain(c)
		if move == "tracks" then
			return math.max(0.05, numOr(`movement.terrainPace.tracks.{t}`, 1))
		elseif move == "wheels" then
			return math.max(0.05, numOr(`movement.terrainPace.wheels.{t}`, 1))
		end
		return 1 / math.max(0.001, 1 + (num(`terrain.{t}.moveCost`) - 1) * num(`units.{kind}.rough`))
	end
	self.paceAt = paceAt

	-- unit route planning and following (the game's routeBy / groupSlots / moveUnit, see Pathing)
	local legend, seenTerrain = {}, {}
	for c = 0, W * H - 1 do
		local t = roads.terrain(c)
		if t and not seenTerrain[t] then
			seenTerrain[t] = true
			table.insert(legend, t)
		end
	end
	local pathing = deps.pathingLib.new(roads, num, text, legend)
	pathing.paceAt = paceAt
	self.pathing = pathing

	local function coverAt(c: number): number
		if c < 0 then
			return 0
		end
		local cover = numOr(`terrain.{roads.terrain(c)}.cover`, 0)
		if map.urbanAt and map.urbanAt(c) then
			cover = math.max(cover, num("cover.urban"))
		end
		return cover
	end

	---------------------------------------------------------------- entities

	local function add(e: Entity): Entity
		e.id = self.nextId
		self.nextId += 1
		self.entities[e.id] = e
		table.insert(self.list, e)
		return e
	end

	local function unitKey(e: Entity): string
		return if e.kind == "hq" then "structures.hq" else `units.{e.kind}`
	end

	function self.spawnUnit(kind: string, side: number, x: number, y: number): Entity
		local hp = num(`units.{kind}.hp`)
		return add({
			kind = kind, cat = "unit", class = text(`units.{kind}.armour`), side = side, x = x, y = y,
			heading = 0, hp = hp, maxHp = hp, shotTimer = 0, moved = false, alive = true,
		})
	end

	-- Setup: HQ on each start, neutral rigs, start oil, idle trucks and start infantry.
	for side, s in deps.starts do
		local hpHq = num("structures.hq.hp")
		local hq = add({
			kind = "hq", cat = "structure", class = "structure", side = side, x = s.x, y = s.y,
			cell = cellAt(s.x, s.y), heading = 0, hp = hpHq, maxHp = hpHq, shotTimer = 0, alive = true,
			queue = {}, queueProgress = 0, built = 1, lastHitAt = -99,
		})
		self.sides[side] = {
			oil = num("match.startOil"), hqId = hq.id, lost = false, trucksIdle = num("trucks.startIdle"),
			oilMult = 1, oilEarned = 0, headlessSince = nil,
		}
	end
	local rigList: { Entity } = {}
	for _, rig in deps.rigs do
		local cx = math.clamp(math.floor(rig.x), 0, W - 1)
		local cy = math.clamp(math.floor(rig.y), 0, H - 1)
		local hpRig = num("rigs.damage.hp")
		local e = add({
			kind = "rig", cat = "structure", class = "structure", side = 0, x = cx + 0.5, y = cy + 0.5,
			cell = cy * W + cx, name = rig.name, heading = 0, hp = hpRig, maxHp = hpRig, alive = true,
			tank = 0, rate = 0, rich = 1, capture = nil, contested = false, takenAt = -999,
			connected = false, route = nil, routeRetryAt = -math.huge, autoTruckAt = nil, warnedAt = -99,
		})
		table.insert(rigList, e)
	end
	-- rich rigs: the floor(n x richCount) farthest from any start
	do
		local n = math.floor(#rigList * num("rigs.rich.richCount"))
		if n > 0 and #deps.starts > 0 then
			local function nearestStart(e: Entity): number
				local best = math.huge
				for _, s in deps.starts do
					local sx, sy = centre(cellAt(s.x, s.y))
					best = math.min(best, math.sqrt((sx - e.x) ^ 2 + (sy - e.y) ^ 2))
				end
				return best
			end
			local sorted = table.clone(rigList)
			table.sort(sorted, function(a, b)
				local da, db = nearestStart(a), nearestStart(b)
				if da ~= db then
					return da > db
				end
				return a.id < b.id
			end)
			for i = 1, n do
				sorted[i].rich = num("rigs.rich.richMult")
			end
		end
	end
	self.rigs = rigList

	local centerX, centerY = W / 2, H / 2
	-- APPROX: produced units appear production.rallyCells beyond the footprint towards the map centre.
	local function rallyPoint(hq: Entity, slot: number): (number, number)
		local dx, dy = centerX - hq.x, centerY - hq.y
		local d = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
		local foot = if hq.kind == "hq" then hqFoot else num("production.footprint.facility")
		local cells = foot + num("production.rallyCells")
		local px, py = -dy / d, dx / d
		local spread = ((slot % 5) - 2) * 1.2
		return hq.x + dx / d * cells + px * spread, hq.y + dy / d * cells + py * spread
	end
	self.rallyPoint = rallyPoint
	-- start infantry: evenly round the HQ at footprint + 1.4 x cellScale, starting at 0.6 rad (game)
	for _, s in self.sides do
		local hq = self.entities[s.hqId]
		local count = num("match.startInfantry")
		for i = 0, count - 1 do
			local a = i / math.max(1, count) * math.pi * 2 + 0.6
			local rad = hqFoot + 1.4 * num("match.cellScale")
			self.spawnUnit("infantry", hq.side, hq.x + math.cos(a) * rad, hq.y + math.sin(a) * rad)
		end
	end

	local function hqOf(side: number): Entity?
		local s = self.sides[side]
		local hq = s and self.entities[s.hqId]
		return if hq and hq.alive then hq else nil
	end
	self.hqOf = hqOf
	local function alive(side: number): boolean
		local s = self.sides[side]
		return s ~= nil and not s.lost
	end
	local function canAttack(a: number, b: number): boolean
		return a ~= b and a > 0 and b > 0
	end
	self.canAttack = canAttack


	---------------------------------------------------------------- structures and territory

	-- The kinds the slice lets a nation place, and the units each producer may train in the slice.
	local PLACEABLE = { barracks = true, factory = true, bunker = true, atgun = true }
	local SLICE_UNITS = { infantry = true, engineer = true, at = true, tank = true, ifv = true, mortar = true, artillery = true, scout = true }
	self.PLACEABLE = PLACEABLE

	local function footprintOf(kind: string): number
		if kind == "hq" then
			return hqFoot
		end
		local k = text(`structures.{kind}.kind`)
		return num(if k == "defence" then "production.footprint.defence" else "production.footprint.facility")
	end
	self.footprintOf = footprintOf

	local function footprintCells(cell: number, r: number): { number }
		local a, b = cell % W, cell // W
		local out = {}
		for y = math.max(0, b - r), math.min(H - 1, b + r) do
			for x = math.max(0, a - r), math.min(W - 1, a + r) do
				table.insert(out, y * W + x)
			end
		end
		return out
	end

	local function isStructure(e: Entity): boolean
		return e.cat == "structure" and e.kind ~= "rig"
	end

	-- Nearest free point for a unit caught inside a new footprint (APPROX of the game's aUe).
	local function freePointNear(x: number, y: number): (number, number)
		local cx, cy = math.floor(x), math.floor(y)
		for rr = 1, 24 do
			local bestC, bestD = -1, math.huge
			for yy = cy - rr, cy + rr do
				for xx = cx - rr, cx + rr do
					if math.max(math.abs(xx - cx), math.abs(yy - cy)) == rr and xx >= 0 and yy >= 0 and xx < W and yy < H then
						local c = yy * W + xx
						local d = (xx + 0.5 - x) ^ 2 + (yy + 0.5 - y) ^ 2
						if roads.passable(c) and d < bestD then
							bestC, bestD = c, d
						end
					end
				end
			end
			if bestC >= 0 then
				return bestC % W + 0.5, bestC // W + 0.5
			end
		end
		return x, y
	end

	local planLater: (Entity) -> () = function(_e: Entity) end
	local eliminateRef: (number, number) -> () = function(_s: number, _b: number) end

	-- Block or free a structure's footprint (the game's tUe / YB): units standing inside step out
	-- (RY) and units whose route crosses it re-plan (HY).
	local function setFootprint(st: Entity, on: boolean)
		local cells = footprintCells(st.cell, footprintOf(st.kind))
		local set = {}
		for _, c in cells do
			if on then
				roads.setBlocked(c, st.id)
				set[c] = true
			elseif roads.buildingAt(c) == st.id then
				roads.setBlocked(c, -1)
			end
		end
		if not on then
			return
		end
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK then
				local c = cellAt(e.x, e.y)
				if c >= 0 and set[c] then
					e.x, e.y = freePointNear(e.x, e.y)
					e.px, e.py = e.x, e.y
					if e.path then
						planLater(e)
					end
				elseif e.path and e.pathIndex then
					for i = e.pathIndex, #e.path do
						if set[e.path[i]] then
							planLater(e)
							break
						end
					end
				end
			end
		end
	end

	for _, s in self.sides do
		setFootprint(self.entities[s.hqId], true)
	end

	-- territory (where a nation may build), see Territory
	local territory = deps.territoryLib.new({
		width = W,
		height = H,
		isDeep = function(c: number): boolean
			return roads.terrain(c) == "deep"
		end,
		isRoad = roads.isRoad,
		roadWalls = r:has("territory.roadWalls") and r:flag("territory.roadWalls"),
		wobble = num("territory.edgeWobble"),
		grain = num("territory.edgeGrain"),
		noise = deps.valueNoise.new(deps.rng.new(bit32.bxor(matchSeed, 20973))),
	})
	local function builtStructure(st: Entity): boolean
		return st.alive and isStructure(st) and st.built >= 1
	end
	local function baseSources(only: number?): { any }
		local out = {}
		for _, st in self.list do
			if builtStructure(st) and alive(st.side) and (only == nil or st.side == only) then
				table.insert(out, {
					nation = st.side, x = st.cell % W + 0.5, y = st.cell // W + 0.5, structure = st.id,
					r = num(`structures.{st.kind}.buildRadius`) * num("territory.reachShare"),
				})
			end
		end
		local join = num("territory.rigJoin") ^ 2
		for _, rig in rigList do
			if rig.side > 0 and (only == nil or rig.side == only) then
				local joined = false
				for _, st in self.list do
					if builtStructure(st) and st.side == rig.side
						and (st.cell % W + 0.5 - rig.x) ^ 2 + (st.cell // W + 0.5 - rig.y) ^ 2 <= join then
						joined = true
						break
					end
				end
				table.insert(out, {
					nation = rig.side, x = rig.x, y = rig.y, rig = rig.id,
					r = if joined then num("territory.rigReach") else num("territory.rigPad"),
				})
			end
		end
		return out
	end
	self.baseSources = baseSources
	local function territoryAt(c: number): number
		if c < 0 or c >= W * H then
			return -1
		end
		return territory.update(baseSources())[c + 1]
	end
	self.territoryAt = territoryAt
	function self.territoryOwners(): { number }
		return territory.update(baseSources())
	end

	local function hasBuilding(side: number, kind: string, active: boolean?): boolean
		for _, st in self.list do
			if builtStructure(st) and st.side == side and st.kind == kind then
				if not active or not self.inactiveReason(st) then
					return true
				end
			end
		end
		return false
	end
	self.hasBuilding = hasBuilding

	function self.inactiveReason(st: Entity): string?
		if st.built < 1 then
			return "building"
		end
		if text(`structures.{st.kind}.kind`) == "facility" and st.hp < st.maxHp * num("production.damagedBelow") then
			return "damaged"
		end
		return nil
	end

	-- the game's rUe: would this footprint split the passable ground around it?
	local function sealsWay(cell: number, a: number): boolean
		local look = num("production.sealLook")
		if not (look > 0) then
			return false
		end
		local rx, iy = cell % W, cell // W
		local function inFoot(v: number, b: number): boolean
			return math.abs(v - rx) <= a and math.abs(b - iy) <= a
		end
		local function closed(v: number, b: number): boolean
			return inFoot(v, b) and not roads.isRoad(b * W + v)
		end
		local u = {}
		local function d(v: number, b: number)
			if v < 0 or b < 0 or v >= W or b >= H then
				table.insert(u, -1)
				return
			end
			local k = b * W + v
			table.insert(u, if roads.passable(k) then k else -1)
		end
		local f = a + 1
		for v = rx - f, rx + f - 1 do d(v, iy - f) end
		for v = iy - f, iy + f - 1 do d(rx + f, v) end
		for v = rx + f, rx - f + 1, -1 do d(v, iy + f) end
		for v = iy + f, iy - f + 1, -1 do d(rx - f, v) end
		local p = 0
		for v = 1, #u do
			local prev = u[(v - 2) % #u + 1]
			if u[v] >= 0 and prev < 0 then
				p += 1
			end
		end
		if p <= 1 then
			return false
		end
		local g = roads.landPieces()
		local keys, piece = {}, {}
		for _, v in u do
			if v >= 0 and piece[v] == nil then
				piece[v] = g[v + 1]
				table.insert(keys, v)
			end
		end
		local done = {}
		for _, v in keys do
			if not done[v] then
				local b = piece[v]
				local k = 0
				for _, c in keys do
					if piece[c] == b and not done[c] then
						k += 1
					end
				end
				local seen = { [v] = true }
				local size = 1
				local x = { v }
				local C = 1
				while C <= #x and k > 0 and size <= look do
					local M = x[C]
					if piece[M] == b and not done[M] then
						done[M] = true
						k -= 1
					end
					local S = M % W
					local Y = (M - S) // W
					local function A(P: number, Q: number)
						if P < 0 or Q < 0 or P >= W or Q >= H then
							return
						end
						local O = Q * W + P
						if seen[O] or not roads.passable(O) or closed(P, Q) then
							return
						end
						seen[O] = true
						size += 1
						table.insert(x, O)
					end
					A(S - 1, Y)
					A(S + 1, Y)
					A(S, Y - 1)
					A(S, Y + 1)
					C += 1
				end
				if k > 0 then
					return true
				end
			end
		end
		return false
	end

	-- the game's placeProblem (road clearance and seal checks on)
	local function placeProblem(cell: number, kind: string): string?
		if cell < 0 or cell >= W * H then
			return "blocked"
		end
		local a = footprintOf(kind)
		local rx, iy = cell % W, cell // W
		if rx - a < 0 or iy - a < 0 or rx + a >= W or iy + a >= H then
			return "terrain"
		end
		for _, c in footprintCells(cell, a) do
			local key = `terrain.{roads.terrain(c)}.buildable`
			if not (r:has(key) and r:flag(key)) then
				return "terrain"
			end
		end
		local clear = math.max(1, math.floor(a * num("production.roadClearShare") + 0.5)) + num("production.roadClearPad")
		for _, c in footprintCells(cell, clear) do
			if roads.isRoad(c) then
				return "onRoad"
			end
		end
		local pad = a + num("rigs.padCells")
		for _, rig in rigList do
			if math.abs(rig.x - (rx + 0.5)) <= pad + 0.5 and math.abs(rig.y - (iy + 0.5)) <= pad + 0.5 then
				return "onRig"
			end
		end
		for _, st in self.list do
			if st.alive and isStructure(st) then
				local l = a + footprintOf(st.kind) + num("production.spacing")
				if math.abs(st.cell % W - rx) <= l and math.abs(st.cell // W - iy) <= l then
					return "spacing"
				end
			end
		end
		if sealsWay(cell, a) then
			return "sealsWay"
		end
		return nil
	end
	self.placeProblem = placeProblem

	-- the game's canPlace, in its order
	function self.canPlace(side: number, kind: string, cell: number): string?
		if not PLACEABLE[kind] or not alive(side) or self.winner then
			return "blocked"
		end
		local why = placeProblem(cell, kind)
		if why then
			return why
		end
		local a = footprintOf(kind)
		local owners = territory.update(baseSources())
		for _, c in footprintCells(cell, a) do
			if owners[c + 1] ~= side then
				return "outsideBase"
			end
		end
		local x, y = cell % W + 0.5, cell // W + 0.5
		local l = num("build.enemyGap") + a
		for _, st in self.list do
			if st.alive and isStructure(st) and st.side ~= side
				and (st.cell % W + 0.5 - x) ^ 2 + (st.cell // W + 0.5 - y) ^ 2 <= l * l then
				return "nearEnemy"
			end
		end
		local rr = l + num("rigs.radius")
		for _, rig in rigList do
			if rig.side > 0 and rig.side ~= side and (rig.x - x) ^ 2 + (rig.y - y) ^ 2 <= rr * rr then
				return "nearEnemy"
			end
		end
		local req = r.data[`structures.{kind}.requires`] :: { string }?
		for _, k in req or {} do
			if not hasBuilding(side, k) then
				return "requires"
			end
		end
		if self.sides[side].oil < num(`structures.{kind}.cost`) then
			return "oil"
		end
		return nil
	end

	-- the game's placeStructure: pay, then the building goes up over buildSec
	function self.placeStructure(side: number, kind: string, cell: number): (number?, string?)
		local why = self.canPlace(side, kind, cell)
		if why then
			return nil, why
		end
		self.sides[side].oil -= num(`structures.{kind}.cost`)
		local hp = num(`structures.{kind}.hp`)
		local st = add({
			kind = kind, cat = "structure", class = "structure", side = side, x = cell % W + 0.5,
			y = cell // W + 0.5, cell = cell, heading = 0, hp = hp, maxHp = hp, shotTimer = 0, alive = true,
			queue = {}, queueProgress = 0, built = 0, lastHitAt = -99,
		})
		setFootprint(st, true)
		event({ type = "buildPlaced", id = st.id, kind = kind, side = side })
		return st.id, nil
	end

	local function trucksOf(rigId: number): number
		local n = 0
		for _, e in self.list do
			if e.alive and e.kind == TRUCK and e.from == rigId then
				n += 1
			end
		end
		return n
	end
	self.trucksOf = trucksOf

	-- rig output with upgrades (rigs.upgrades.pump / .tank, one level each)
	function self.pumpRate(rig: Entity): number
		return num("rigs.oilPerSec") * rig.rich * (if rig.pumpLevel then num("rigs.upgrades.pump.mult") else 1)
	end
	function self.tankSize(rig: Entity): number
		return num("rigs.tank") * (if rig.tankLevel then num("rigs.upgrades.tank.mult") else 1)
	end
	-- seconds for one truck round trip on the rig's route (drive both ways, load a full truck, unload)
	function self.tripTime(rig: Entity): number
		local route = rig.route
		if not route or #route == 0 then
			return math.huge
		end
		local l = 0
		for _, c in route do
			if roads.isRoad(c) then
				l += 1 / num(`roads.classes.{Roads.CLASS_NAME[roads.classAt(c)]}.truck`)
			else
				l += 1 / math.max(0.05, num("convoys.offRoadShare"))
			end
		end
		return 2 * l / math.max(0.001, num("convoys.speed") * num("trucks.kinds.light.paceShare"))
			+ num("trucks.kinds.light.capacity") / math.max(0.001, num("trucks.loadPerSec"))
			+ num("trucks.unloadSec")
	end

	---------------------------------------------------------------- connections and routes

	local function updateConnections()
		local near: { [number]: { [number]: boolean } } = {}
		for side in self.sides do
			local hq = hqOf(side)
			if hq and alive(side) then
				near[side] = roads.piecesNear(hq.x, hq.y, offReach + hqFoot)
			end
		end
		for _, rig in rigList do
			local set = if rig.side > 0 then near[rig.side] else nil
			local ok = false
			if set then
				for p in roads.piecesNear(rig.x, rig.y, offReach) do
					if set[p] then
						ok = true
						break
					end
				end
			end
			rig.connected = ok
		end
	end
	self.updateConnections = updateConnections

	local function resetRoute(rig: Entity)
		rig.route, rig.back, rig.routeHq, rig.routeRetryAt = nil, nil, nil, -math.huge
	end

	local function updateRoutes()
		for i, rig in rigList do
			if rig.side > 0 and rig.connected and self.ticks % 10 == i % 10 then -- APPROX refresh cadence
				local hq = hqOf(rig.side)
				if hq and (not rig.route or rig.routeHq ~= hq.cell) and self.time >= rig.routeRetryAt then
					local path = roads.truckRoute(rig.cell, hq.cell)
					if path and #path > 0 then
						rig.route, rig.routeHq, rig.back = path, hq.cell, nil
					else
						rig.route, rig.routeRetryAt = nil, self.time + num("convoys.retrySec")
					end
				end
			end
		end
	end
	self.updateRoutes = updateRoutes

	local function routeOf(rig: Entity): { number }?
		local hq = hqOf(rig.side)
		if not hq or not rig.route or rig.routeHq ~= hq.cell then
			return nil
		end
		return rig.route
	end

	local function backPath(rig: Entity): { number }
		if not rig.back then
			local route = rig.route :: { number }
			local back = {}
			for i = #route - 1, 1, -1 do
				table.insert(back, route[i])
			end
			table.insert(back, rig.cell)
			rig.back = back
		end
		return rig.back
	end

	---------------------------------------------------------------- orders

	local function orderable(e: Entity?, side: number): boolean
		return e ~= nil and e.alive and e.cat == "unit" and e.side == side and e.kind ~= TRUCK
	end

	-- Each order returns the ids refused because the side does not own them.
	-- Plans e's route to `cell`, ending on (x, y). No route: the unit stays put (the game's empty path).
	local function planTo(e: Entity, cell: number, x: number, y: number)
		local here = cellAt(e.x, e.y)
		local path = pathing.route(here, cell, e.kind)
		if not path then
			e.target, e.path, e.spot = nil, nil, nil
			return
		end
		if #path == 0 then
			path = { cell }
		end
		e.path, e.pathIndex, e.stall, e.stallTries = path, 1, 0, 0
		e.spot = { x = x, y = y }
		e.target = { x = x, y = y } -- destination marker (Bot and UI read it)
		e.goalCell = cell
	end
	self.planTo = planTo
	planLater = function(e: Entity)
		local goal = e.goalCell
		if not goal then
			return
		end
		if roads.passable(goal) then
			local sp = e.spot or { x = goal % W + 0.5, y = goal // W + 0.5 }
			planTo(e, goal, sp.x, sp.y)
		else
			local fx, fy = freePointNear(goal % W + 0.5, goal // W + 0.5)
			planTo(e, cellAt(fx, fy), fx, fy)
		end
	end

	local function onRig(cell: number): boolean
		local cx, cy = centre(cell)
		for _, rig in self.rigs do
			if math.max(math.abs(rig.x - cx), math.abs(rig.y - cy)) < 1.5 then
				return true
			end
		end
		return false
	end

	---------------------------------------------------------------- scout recon

	-- units with the recon ability (the scout car)
	local function canRecon(e: Entity): boolean
		local ab = r.data[`units.{e.kind}.abilities`] :: { string }?
		return e.cat == "unit" and ab ~= nil and table.find(ab, "recon") ~= nil
	end
	self.canRecon = canRecon
	function self.scoutDeployed(e: Entity): boolean
		return (e.reconLeft or 0) > 0
	end
	function self.scoutReadyIn(e: Entity): number
		return math.max(0, (e.reconReadyAt or 0) - self.time)
	end
	-- the game's gwe: pack up, then intel.scoutCooldownSec before it can deploy again
	local function packRecon(e: Entity)
		e.reconLeft = 0
		e.reconReadyAt = self.time + num("intel.scoutCooldownSec")
	end
	-- any new order packs a deployed scout (the game's clearOrders -> GJe)
	local function clearRecon(e: Entity)
		if (e.reconLeft or 0) > 0 then
			packRecon(e)
		end
	end
	-- the game's deployRecon (qJe): the scout stops and sees intel.scoutReconRadius around it for
	-- intel.scoutDeploySec. Returns (count deployed, reason when none).
	function self.deployRecon(side: number, ids: { number }): (number, string?)
		local n, cooling, any = 0, false, false
		for _, id in ids do
			local e = self.entities[id]
			if e and e.alive and e.side == side and canRecon(e) then
				any = true
				if (e.reconLeft or 0) <= 0 then
					if self.scoutReadyIn(e) > 0 then
						cooling = true
					else
						e.target, e.attackId, e.path, e.spot = nil, nil, nil, nil
						e.reconLeft = num("intel.scoutDeploySec")
						n += 1
					end
				end
			end
		end
		if n > 0 then
			return n, nil
		end
		return 0, if not any then "noScouts" elseif cooling then "cooldown" else "blocked"
	end
	-- the game's ZJe: deployed scouts stay put and count down
	local function reconTick(dt: number)
		for _, e in self.list do
			if e.alive and (e.reconLeft or 0) > 0 then
				e.target, e.path = nil, nil
				e.reconLeft -= dt
				if e.reconLeft <= 0 then
					packRecon(e)
					event({ type = "scoutPacked", id = e.id, side = e.side })
				end
			end
		end
	end

	function self.orderMove(side: number, ids: { number }, x: number, y: number): { number }
		local refused = {}
		local group = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.attackId = nil
				clearRecon(e)
				table.insert(group, e)
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		local cell = cellAt(math.clamp(x, 0, W - 1e-6), math.clamp(y, 0, H - 1e-6))
		if #group == 1 and cell >= 0 and roads.passable(cell) then
			planTo(group[1], cell, x, y)
		elseif #group >= 1 then
			local slots = pathing.groupSlots(group, cell, onRig(cell))
			for i, e in group do
				local s = slots[i]
				if s then
					local sx, sy = centre(s)
					planTo(e, s, sx, sy)
				else
					e.target, e.path = nil, nil
				end
			end
		end
		return refused
	end

	function self.orderStop(side: number, ids: { number }): { number }
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.target, e.attackId, e.path = nil, nil, nil
				clearRecon(e)
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		return refused
	end

	function self.orderAttack(side: number, ids: { number }, targetId: number): ({ number }, string?)
		local t = self.entities[targetId]
		if not t or not t.alive or not canAttack(side, t.side) or t.kind == "rig" then
			return {}, "invalid target"
		end
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.attackId, e.target, e.path = targetId, nil, nil
				clearRecon(e)
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		return refused, nil
	end

	local function unitsAndQueued(side: number): number
		local n = 0
		for _, e in self.list do
			if e.alive and e.side == side then
				if e.cat == "unit" and e.kind ~= TRUCK then
					n += 1
				elseif e.queue and isStructure(e) then
					n += #e.queue
				end
			end
		end
		return n
	end

	-- the game's canProduce for a producer, in its order (slice: only SLICE_UNITS)
	local function canProduce(st: Entity, item: string): string?
		local from = r.data[`units.{item}.from`] :: { string }?
		if not SLICE_UNITS[item] or not from or not table.find(from, st.kind) then
			return "blocked"
		end
		if self.inactiveReason(st) then
			return "notOperational"
		end
		local req = r.data[`units.{item}.requires`] :: { string }?
		for _, k in req or {} do
			if not hasBuilding(st.side, k, true) then
				return "requires"
			end
		end
		if #st.queue >= num("production.maxQueue") then
			return "queueFull"
		end
		if unitsAndQueued(st.side) >= num("match.unitCap") then
			return "unitCap"
		end
		if self.sides[st.side].oil < num(`units.{item}.cost`) then
			return "oil"
		end
		return nil
	end
	self.canProduce = canProduce

	-- Queue a unit at a producer (structureId), or at the HQ when none is given.
	function self.orderProduce(side: number, item: string, structureId: number?): (boolean, string?)
		local s = self.sides[side]
		local st = if structureId then self.entities[structureId] else hqOf(side)
		if not s or s.lost or self.winner or not st or not st.alive or st.side ~= side or not isStructure(st) then
			return false, "blocked"
		end
		local why = canProduce(st, item)
		if why then
			return false, why
		end
		s.oil -= num(`units.{item}.cost`)
		table.insert(st.queue, item)
		return true, nil
	end

	local function newTruck(rig: Entity): Entity
		local hq = hqOf(rig.side) :: Entity
		local hp = num("trucks.kinds.light.hp")
		return add({
			kind = TRUCK, cat = "unit", class = "armour", side = rig.side, x = hq.x, y = hq.y,
			heading = 0, hp = hp, maxHp = hp, alive = true, from = rig.id, payload = 0, state = "out",
			path = backPath(rig), pathIndex = 1, timer = 0, queue = nil, moved = false,
		})
	end

	-- The game's refusal reasons, in its order: notOwned, noHq, noRoute, truckLimit, oil.
	local function truckRefusal(side: number, rig: Entity?): string?
		if not rig or rig.kind ~= "rig" or rig.side ~= side then
			return "notOwned"
		end
		if not hqOf(side) then
			return "noHq"
		end
		if not rig.connected or not rig.route then
			return "noRoute"
		end
		if trucksOf(rig.id) >= num("trucks.perRig") then
			return "truckLimit"
		end
		local s = self.sides[side]
		if s.trucksIdle > 0 or s.oil >= num("trucks.kinds.light.cost") then
			return nil
		end
		return "oil"
	end

	-- Send a truck to a rig: an idle one if the nation has one, else buy one.
	function self.orderTruck(side: number, rigId: number): (boolean, string?)
		local rig = self.entities[rigId]
		local why = truckRefusal(side, rig)
		if why then
			return false, why
		end
		if not routeOf(rig) then
			return false, "noRoute"
		end
		local s = self.sides[side]
		if s.trucksIdle > 0 then
			s.trucksIdle -= 1
		else
			local cost = num("trucks.kinds.light.cost")
			if s.oil < cost then
				return false, "oil"
			end
			s.oil -= cost
		end
		newTruck(rig)
		return true, nil
	end

	-- Rig upgrades: "pump" or "tank", one level each, paid up front.
	function self.upgradeRig(side: number, rigId: number, kind: string): (boolean, string?)
		local rig = self.entities[rigId]
		if not rig or rig.kind ~= "rig" or rig.side ~= side or (kind ~= "pump" and kind ~= "tank") then
			return false, "notOwned"
		end
		if (kind == "pump" and rig.pumpLevel) or (kind == "tank" and rig.tankLevel) then
			return false, "maxLevel"
		end
		local cost = num(`rigs.upgrades.{kind}.cost`)
		local s = self.sides[side]
		if s.oil < cost then
			return false, "oil"
		end
		s.oil -= cost
		if kind == "pump" then
			rig.pumpLevel = 1
		else
			rig.tankLevel = 1
		end
		return true, nil
	end

	---------------------------------------------------------------- elimination and damage

	local function eliminate(side: number, by: number)
		-- (also reached through eliminateRef by checkHeadless)
		local s = self.sides[side]
		if not s or s.lost then
			return
		end
		s.lost = true
		for _, e in self.list do
			if e.alive and e.side == side and e.kind ~= "rig" then
				e.alive, e.hp = false, 0
				if isStructure(e) then
					e.queue = {}
					setFootprint(e, false)
				end
			end
		end
		for _, rig in rigList do
			if rig.side == side then
				rig.side, rig.capture, rig.tank, rig.connected = 0, nil, 0, false
				resetRoute(rig)
			end
		end
		event({ type = "eliminated", side = side, by = by })
	end
	eliminateRef = eliminate

	local function hitStructure(by: number, st: Entity, damage: number)
		if not st.alive then
			return
		end
		st.hp -= damage
		st.lastHitAt = self.time
		if st.hp > 0 then
			return
		end
		st.alive, st.hp = false, 0
		setFootprint(st, false)
		event({ type = "destroyed", id = st.id, kind = st.kind, side = st.side, by = by })
		if st.kind == "hq" then
			-- an active factory lets the nation rehouse within hqLoss.graceSec, else it is out
			if hasBuilding(st.side, "factory", true) then
				event({ type = "hqLostRebuild", side = st.side, sec = num("hqLoss.graceSec") })
			else
				eliminate(st.side, by)
			end
		end
	end

	local function hasHull(e: Entity): boolean
		return e.cat == "unit" and e.kind ~= TRUCK and text(unitKey(e) .. ".move") ~= "foot"
	end

	-- Armour facing: the hull heading for vehicles, otherwise the face direction.
	local function facingOf(e: Entity): (number?, number?)
		local hd = e.heading
		if hasHull(e) and hd == hd and hd ~= math.huge and hd ~= -math.huge then
			return math.cos(hd), math.sin(hd)
		end
		return e.faceX, e.faceY
	end

	local function armourSide(target: Entity, ax: number, ay: number): string
		local fx, fy = facingOf(target)
		local dx, dy = ax - target.x, ay - target.y
		local d = math.sqrt(dx * dx + dy * dy)
		if not fx or not fy or d < 1e-6 then
			return "side"
		end
		local c = (dx * fx + dy * fy) / d
		if c >= math.cos(math.rad(num("armour.frontDeg"))) then
			return "front"
		elseif c <= math.cos(math.rad(num("armour.rearDeg"))) then
			return "rear"
		end
		return "side"
	end

	-- Flank check uses the unit's face direction (set each tick from its aim, hull heading or motion;
	-- a unit that has never moved or aimed has none and cannot be flanked).
	local function flanked(target: Entity, ax: number, ay: number): boolean
		local fx, fy = target.faceX, target.faceY
		local dx, dy = ax - target.x, ay - target.y
		local d = math.sqrt(dx * dx + dy * dy)
		if fx == nil or fy == nil or d < 1e-6 then
			return false
		end
		return (dx * fx + dy * fy) / d < math.cos(math.rad(num("combat.flankDeg")))
	end

	local function vsOf(key: string, armour: string): number
		return numOr(`{key}.vs.{armour}`, 0)
	end

	local function d2(ax: number, ay: number, bx: number, by: number): number
		return (ax - bx) ^ 2 + (ay - by) ^ 2
	end

	-- the game's bunchFactor: splash hurts more where foot soldiers crowd
	local function bunchFactor(by: number, x: number, y: number): number
		local cells = num("combat.bunchCells")
		local share = num("combat.bunchSplash")
		if share <= 0 or cells <= 0 then
			return 1
		end
		local n = 0
		for _, u in self.list do
			if u.alive and u.cat == "unit" and u.kind ~= TRUCK and d2(u.x, u.y, x, y) <= cells * cells
				and text(unitKey(u) .. ".move") == "foot" and (by < 0 or canAttack(by, u.side)) then
				n += 1
			end
		end
		return 1 + math.min(num("combat.bunchMax"), share * math.max(0, n - 1))
	end

	local function killIfDead(u: Entity, by: number)
		if u.hp <= 0 and u.alive then
			u.alive = false
			event({ type = "destroyed", id = u.id, kind = u.kind, side = u.side, by = by })
		end
	end

	-- the game's hitUnit. splash > 0: the hit grows with bunching and half of it also lands on the
	-- target's comrades within splash cells. bombard (artillery fire): no flanking, no armour facing.
	local function hitUnit(target: Entity, dps: number, key: string, secs: number, by: number, fromX: number, fromY: number, splash: number?, bombard: boolean?)
		local s = splash or 0
		local p = dps * vsOf(key, target.class) * secs
		if s > 0 then
			p *= bunchFactor(by, target.x, target.y)
		end
		local g = if target.class == "armour" and not bombard then num(`armour.{armourSide(target, fromX, fromY)}`) else 0
		if target.class ~= "air" then
			local y = coverAt(cellAt(target.x, target.y))
			if not bombard and flanked(target, fromX, fromY) then
				p *= (1 - y * num("combat.flankCoverKeep")) * (if g ~= 0 then 1 else num("combat.flankBonus"))
			else
				p *= 1 - y
			end
		end
		if g ~= 0 then
			p *= g
		end
		target.hp -= p
		target.hitAt, target.hitBy = self.time, by
		if s > 0 then
			for _, b in self.list do
				if b ~= target and b.alive and b.cat == "unit" and b.kind ~= TRUCK and b.side == target.side
					and d2(b.x, b.y, target.x, target.y) <= s * s and vsOf(key, b.class) > 0 then
					b.hp -= p * 0.5
					b.hitAt, b.hitBy = self.time, by
					killIfDead(b, by)
				end
			end
		end
		killIfDead(target, by)
	end

	local function hitTruck(t: Entity, dps: number, key: string, secs: number, by: number)
		t.hp -= dps * vsOf(key, "armour") * secs
		if t.hp <= 0 and t.alive then
			t.alive = false
			local rig = self.entities[t.from]
			if rig then
				rig.truckLostAt = self.time
			end
			event({ type = "convoyLost", id = t.id, side = t.side, oil = t.payload, by = by })
			if rig and rig.side == t.side and trucksOf(rig.id) == 0 then
				rig.noTrucks = true
				event({ type = "rigNoTrucks", id = rig.id, side = rig.side })
			end
		end
	end

	local function landStrikes()
		if #self.strikes == 0 then
			return
		end
		local later, now = {}, {}
		for _, s in self.strikes do
			table.insert(if s.at <= self.time then now else later, s)
		end
		self.strikes = later
		for _, s in now do
			local t = self.entities[s.target]
			if t and t.alive then
				if s.kind == "unit" then
					hitUnit(t, s.dps, s.key, s.secs, s.by, s.fromX, s.fromY, s.splash, s.bombard)
				elseif s.kind == "convoy" then
					hitTruck(t, s.dps, s.key, s.secs, s.by)
				else
					hitStructure(s.by, t, s.damage)
				end
			end
		end
	end

	---------------------------------------------------------------- combat

	local function validUnitTarget(side: number, o: Entity, key: string): boolean
		return o.alive and o.hp > 0 and o.cat == "unit" and o.kind ~= TRUCK and canAttack(side, o.side) and vsOf(key, o.class) > 0
	end

	local function nearestUnit(x: number, y: number, side: number, range: number, key: string, minR: number?, ok: ((Entity) -> boolean)?): Entity?
		local best, bestD = nil, range * range
		local lo = (minR or 0) ^ 2
		for _, o in self.list do
			if validUnitTarget(side, o, key) then
				local d = d2(x, y, o.x, o.y)
				if d >= lo and d <= bestD and (not ok or ok(o)) then -- the game keeps the last of equally near targets
					best, bestD = o, d
				end
			end
		end
		return best
	end

	local function nearestTruck(x: number, y: number, side: number, range: number, minR: number?): Entity?
		local best, bestD = nil, range * range
		local lo = (minR or 0) ^ 2
		for _, o in self.list do
			if o.alive and o.kind == TRUCK and canAttack(side, o.side) then
				local d = d2(x, y, o.x, o.y)
				if d <= bestD and d >= lo then
					best, bestD = o, d
				end
			end
		end
		return best
	end

	local function nearestStructure(x: number, y: number, side: number, range: number, key: string, minR: number?, ok: ((Entity) -> boolean)?): Entity?
		if vsOf(key, "structure") <= 0 then
			return nil
		end
		local best, bestW = nil, math.huge
		local lo = (minR or 0) ^ 2
		for _, o in self.list do
			if o.alive and o.cat == "structure" and o.kind ~= "rig" and canAttack(side, o.side) then
				local d = d2(x, y, o.x, o.y)
				if d <= range * range and d >= lo and (not ok or ok(o)) then
					local wgt = d * (if numOr(`structures.{o.kind}.dps`, 0) > 0 then 0.25 else 1)
					if wgt < bestW then
						best, bestW = o, wgt
					end
				end
			end
		end
		return best
	end

	-- The game's shot timer: count down while engaging, re-arm with jitter; returns the nominal
	-- reload (the shot's damage seconds) or 0.
	local function shoot(e: Entity, reload: number, dt: number): number
		e.shotTimer -= dt
		if e.shotTimer > 0 then
			return 0
		end
		local j = num("combat.reloadJitter")
		e.shotTimer = reload * (1 - j + rand() * 2 * j)
		return reload
	end

	-- the game's flightSec: distance / the weapon's shot speed (0 = lands at once)
	local function flight(key: string, ax: number, ay: number, bx: number, by: number): number
		local w = text(key .. ".weapon")
		local speed = if w == "bullets" then BULLET_SPEED else (SHOT_SPEED[w] or 0)
		return if speed > 0 then math.sqrt(d2(ax, ay, bx, by)) / speed else 0
	end

	local function fire(e: Entity, key: string, target: Entity, kind: string, dps: number, dt: number)
		local tx, ty = target.x, target.y
		e.firing, e.aimX, e.aimY = true, tx, ty
		if e.cat == "unit" and not hasHull(e) then
			e.heading = math.atan2(ty - e.y, tx - e.x) -- presentation only for foot units
		end
		local secs = shoot(e, num(key .. ".reloadSec"), dt)
		if secs <= 0 then
			return
		end
		local arty = e.cat == "unit" and text(key .. ".nato") == "artillery"
		if arty then
			-- the game's Jze: a firing gun is revealed to the enemy and stays deployed (packs before moving)
			e.revealedUntil = self.time + num("artillery.revealSec")
			e.packAt = -1
		end
		local strike: { [string]: any } = {
			kind = kind, at = self.time + flight(key, e.x, e.y, tx, ty), target = target.id, dps = dps,
			key = key, secs = secs, by = e.side, fromX = e.x, fromY = e.y,
		}
		if kind == "unit" and e.cat == "unit" then
			strike.splash = numOr(key .. ".splash", 0)
			strike.bombard = arty
		end
		if kind == "structure" then
			strike.damage = dps * vsOf(key, "structure") * secs
		end
		table.insert(self.strikes, strike)
	end

	-- the game's structure fire: every built, working, armed building shoots the nearest enemy unit
	-- in range, else the nearest enemy truck
	local function structuresFire(dt: number)
		for _, st in self.list do
			if st.alive and isStructure(st) and st.built >= 1 and not self.inactiveReason(st) then
				local key = `structures.{st.kind}`
				local dps = numOr(key .. ".dps", 0)
				if dps > 0 then
					local range = num(key .. ".range")
					local u = nearestUnit(st.x, st.y, st.side, range, key)
					if u then
						fire(st, key, u, "unit", dps, dt)
					else
						local t = nearestTruck(st.x, st.y, st.side, range)
						if t then
							fire(st, key, t, "convoy", dps, dt)
						end
					end
				end
			end
		end
	end

	-- mortar spotting (the game's jat / Xbe): with fog on, a mortar only fires on cells its nation
	-- sees, from a vision map refreshed every mortar.spotEveryTicks ticks
	local spotCache: { [number]: { at: number, grid: { number } } } = {}
	local function spotted(side: number, x: number, y: number): boolean
		if not self.fogOn() then
			return true
		end
		local c = cellAt(x, y)
		if c < 0 then
			return false
		end
		local at = self.ticks // math.max(1, math.floor(num("mortar.spotEveryTicks") + 0.5))
		local sc = spotCache[side]
		if not sc or sc.at ~= at then
			sc = sc or { at = at, grid = table.create(W * H, 0) }
			sc.at = at
			self.visionFor(side, sc.grid)
			spotCache[side] = sc
		end
		return sc.grid[c + 1] == 2
	end
	local function revealed(o: Entity): boolean
		return o.revealedUntil ~= nil and o.revealedUntil > self.time
	end

	-- the game's mortar attack think (Kat): hold between minRange x backOffShare and the reach
	-- (range, or sight when the target is not spotted, x attackRangeShare); back off when too close.
	-- Returns the target once in that band. APPROX: re-plans only when the approach point moves 2+
	-- cells, like the other units' approach.
	local function mortarApproach(e: Entity, t: Entity, range: number, minR: number): Entity?
		local spot = revealed(t) or spotted(e.side, t.x, t.y)
		local reach = (if spot then range else math.min(range, num(unitKey(e) .. ".sight") * self.sightFactor()))
			* num("combat.attackRangeShare")
		local f = math.min(reach * 0.9, minR * num("mortar.backOffShare"))
		local p = math.sqrt(d2(e.x, e.y, t.x, t.y))
		if p >= f and p <= reach then
			e.target, e.path = nil, nil
			return t
		end
		local ax, ay
		if p < f then
			local mid = (f + reach) / 2
			local ux, uy = if p > 1e-6 then (e.x - t.x) / p else 1, if p > 1e-6 then (e.y - t.y) / p else 0
			ax = math.clamp(t.x + ux * mid, 0.5, W - 0.5)
			ay = math.clamp(t.y + uy * mid, 0.5, H - 0.5)
		else
			local w = math.max(0.5, (reach - f) / 2)
			local keep = math.max(f + 0.25, reach - w * 0.5)
			ax, ay = t.x + (e.x - t.x) / p * keep, t.y + (e.y - t.y) / p * keep
		end
		local ac = cellAt(ax, ay)
		local g = e.goalCell
		if ac >= 0 and (not e.path or not g or math.max(math.abs(ac % W - g % W), math.abs(ac // W - g // W)) >= 2) then
			planTo(e, ac, ax, ay)
		end
		return nil
	end

	local function unitsFire(dt: number)
		for _, e in self.list do
			if e.alive and e.hp > 0 and e.cat == "unit" and e.kind ~= TRUCK then
				local key = unitKey(e)
				local dps = num(key .. ".dps")
				if dps > 0 then
					local range = num(key .. ".range")
					-- artillery (mortars too) fire only after standing still for their set-up time
					local arty = text(key .. ".nato") == "artillery"
					local mortar = text(key .. ".weapon") == "mortar"
					local minR = if mortar then num("mortar.minRange") else 0
					local spotUnit: ((Entity) -> boolean)? = nil
					local spotStructure: ((Entity) -> boolean)? = nil
					if mortar then
						spotUnit = function(o: Entity): boolean
							return revealed(o) or spotted(e.side, o.x, o.y)
						end
						spotStructure = function(o: Entity): boolean
							local cx, cy = centre(o.cell)
							return spotted(e.side, cx, cy)
						end
					end
					-- armoured shooters fire weaker on the move
					local eff = dps * (if e.class == "armour" and e.moved then num("armour.movingFire") else 1)
					local focus: Entity? = nil
					if e.attackId then
						local t = self.entities[e.attackId]
						if not t or not t.alive then
							e.attackId = nil
						elseif mortar then
							focus = mortarApproach(e, t, range, minR)
						else
							local dist = math.sqrt(d2(e.x, e.y, t.x, t.y))
							if dist > range then
								-- APPROX of the game's attack think: close to attackRangeShare of range
								local k = 1 - (range * num("combat.attackRangeShare")) / dist
								-- APPROX: re-plan only when the approach point moves 2+ cells
								local ax, ay = e.x + (t.x - e.x) * k, e.y + (t.y - e.y) * k
								local ac = cellAt(ax, ay)
								local g = e.goalCell
								if not e.path or not g or ac < 0 or math.max(math.abs(ac % W - g % W), math.abs(ac // W - g // W)) >= 2 then
									if ac >= 0 then
										planTo(e, ac, ax, ay)
									end
								end
							else
								e.target, e.path = nil, nil
								focus = t
							end
						end
					end
					local setup = if mortar then num("mortar.setupSec") else num("artillery.setupSec")
					local ready = not arty or (not e.path and (e.still or 0) >= setup)
					if focus and mortar then
						local fx, fy = focus.x, focus.y
						if focus.cat == "structure" then
							fx, fy = centre(focus.cell)
						end
						local ok = d2(e.x, e.y, fx, fy) >= minR * minR
							and (if focus.cat == "structure" then spotted(e.side, fx, fy) else (spotUnit :: any)(focus))
						if not ok then
							focus = nil
						end
					end
					if ready then
						local unitTarget: Entity? = nil
						if focus then
							if focus.cat == "unit" and focus.kind ~= TRUCK then
								unitTarget = focus
							end
						else
							unitTarget = nearestUnit(e.x, e.y, e.side, range, key, minR, spotUnit)
						end
						if unitTarget then
							fire(e, key, unitTarget, "unit", eff, dt)
						else
							local truck: Entity? = nil
							if focus then
								if focus.kind == TRUCK then
									truck = focus
								end
							else
								truck = nearestTruck(e.x, e.y, e.side, range, minR)
								if truck and spotUnit and not spotUnit(truck) then
									truck = nil
								end
							end
							if truck then
								fire(e, key, truck, "convoy", eff, dt)
							else
								local st = if focus and focus.cat == "structure" then focus else nearestStructure(e.x, e.y, e.side, range, key, minR, spotStructure)
								if st then
									fire(e, key, st, "structure", eff, dt)
								end
							end
						end

					end
				end
			end
		end
	end

	---------------------------------------------------------------- rigs

	local function strengthNear(x: number, y: number, radius: number): { [number]: number }
		local out = {}
		for _, u in self.list do
			if u.alive and u.cat == "unit" and u.kind ~= TRUCK then
				local key = unitKey(u)
				if num(key .. ".dps") > 0 and u.class ~= "air" and text(key .. ".move") ~= "sea" and d2(u.x, u.y, x, y) <= radius * radius then
					out[u.side] = (out[u.side] or 0) + math.max(0.25, numOr(key .. ".capture", 0))
				end
			end
		end
		return out
	end

	local function guarded(rig: Entity, owner: number): boolean
		local reach = num("rigs.radius") * num("rigs.guardShare")
		for _, st in self.list do
			if st.alive and st.cat == "structure" and st.kind ~= "rig" and st.side == owner and numOr(`structures.{st.kind}.dps`, 0) > 0 then
				local cx, cy = centre(st.cell)
				if d2(cx, cy, rig.x, rig.y) <= reach * reach then
					return true
				end
			end
		end
		return false
	end
	self.guarded = guarded

	local function takeRig(rig: Entity, by: number)
		local prev = rig.side
		rig.takenFrom, rig.side, rig.capture, rig.contested, rig.takenAt = prev, by, nil, false, self.time
		resetRoute(rig)
		rig.noTrucks = nil
		if prev > 0 then
			event({ type = "rigLost", id = rig.id, side = prev, by = by })
		end
		event({ type = "rigCaptured", id = rig.id, side = by, from = prev })
		updateConnections()
	end

	local function rigs(dt: number)
		local radius = num("rigs.radius")
		for _, rig in rigList do
			local weights = strengthNear(rig.x, rig.y, radius)
			local sides = {}
			for side in weights do
				if alive(side) then
					table.insert(sides, side)
				end
			end
			table.sort(sides)
			local pressing = if #sides == 1 then sides[1] else -1 -- no alliances in the slice
			rig.contested = #sides > 1 and pressing < 0
			local owner = rig.side
			if pressing > 0 and pressing ~= owner and (owner <= 0 or canAttack(pressing, owner)) and (owner <= 0 or not guarded(rig, owner)) then
				if not rig.capture or rig.capture.by ~= pressing then
					rig.capture = { by = pressing, progress = 0 }
					if owner > 0 and self.time - rig.warnedAt > 20 then
						rig.warnedAt = self.time
						event({ type = "rigCaptureStarted", id = rig.id, side = owner, by = pressing })
					end
				end
				local pace = math.max(num("rigs.minPace"), math.min(1, (weights[pressing] or 0) / math.max(0.1, num("rigs.need"))))
				rig.capture.progress = math.min(1, rig.capture.progress + dt * pace / math.max(0.1, num("rigs.captureSec")))
				if rig.capture.progress >= 1 then
					takeRig(rig, pressing)
				end
			elseif rig.capture and not rig.contested then
				rig.capture.progress -= num("rigs.decayPerSec") * dt
				if rig.capture.progress <= 0 then
					rig.capture = nil
				end
			end
			if rig.contested and rig.side > 0 and self.time - rig.warnedAt > 30 then
				rig.warnedAt = self.time
				event({ type = "rigUnderAttack", id = rig.id, side = rig.side })
			end
			-- pumping
			rig.rate = 0
			if rig.side > 0 and alive(rig.side) and self.time - rig.takenAt >= num("rigs.takeoverSec") then
				local cap = self.tankSize(rig)
				if rig.tank >= cap then
					if not rig.full then
						rig.full = true
						event({ type = "rigFull", id = rig.id, side = rig.side })
					end
				else
					rig.full = false
					rig.rate = self.pumpRate(rig)
					rig.tank = math.min(cap, rig.tank + rig.rate * dt)
				end
			end
			-- snapshot fields
			rig.capSide = if rig.capture then rig.capture.by else 0
			rig.capProgress = if rig.capture then rig.capture.progress else 0
			rig.store = rig.tank
		end
	end

	---------------------------------------------------------------- trucks

	local function sendHome(t: Entity, rig: Entity?, hq: Entity)
		t.state, t.queue, t.timer = "home", nil, 0
		local route = if rig then routeOf(rig) else nil
		if rig and route and cellAt(t.x, t.y) == rig.cell then
			t.path, t.pathIndex = route, 1
		else
			-- APPROX: a truck away from its rig re-routes to the HQ over the same cost map
			local here = cellAt(t.x, t.y)
			t.path = roads.search(here, hq.cell, roads.truckCostFn(here, hq.cell), { minCost = 1, fourWay = true }) or {}
			t.pathIndex = 1
		end
	end

	local function sendOut(t: Entity, rig: Entity)
		t.state, t.queue, t.timer = "out", nil, 0
		t.path, t.pathIndex = backPath(rig), 1
	end

	local function credit(side: number, oil: number)
		local s = self.sides[side]
		if not s or s.lost then
			return
		end
		local v = oil * s.oilMult
		s.oil += v
		s.oilEarned += v
	end

	local function trucks(dt: number)
		-- automatic first truck after each capture
		for _, rig in rigList do
			if rig.side > 0 and rig.autoTruckAt ~= rig.takenAt and rig.connected and alive(rig.side) and routeOf(rig) then
				rig.autoTruckAt = rig.takenAt
				if trucksOf(rig.id) == 0 and self.sides[rig.side].trucksIdle > 0 then
					self.orderTruck(rig.side, rig.id)
				end
			end
		end
		-- loading queues: first in line per rig (queue order, then id)
		local head: { [number]: Entity } = {}
		local lines: { [number]: { Entity } } = {}
		for _, t in self.list do
			if t.alive and t.kind == TRUCK and t.state == "loading" and t.from > 0 then
				lines[t.from] = lines[t.from] or {}
				table.insert(lines[t.from], t)
			end
		end
		for rigId, line in lines do
			table.sort(line, function(a, b)
				local qa, qb = a.queue or 1e9, b.queue or 1e9
				if qa ~= qb then
					return qa < qb
				end
				return a.id < b.id
			end)
			for i, t in line do
				t.queue = i - 1
			end
			head[rigId] = line[1]
		end

		local capacity = num("trucks.kinds.light.capacity")
		for _, t in self.list do
			if t.kind == TRUCK and t.alive then
				t.moved = false
				if not alive(t.side) then
					t.alive = false -- UNCONFIRMED
					continue
				end
				local hq = hqOf(t.side)
				if not hq then
					continue
				end
				local rig = if t.from > 0 then self.entities[t.from] else nil
				if rig and rig.side ~= t.side then
					t.from, rig = -1, nil
				end
				if not rig and (t.state == "out" or t.state == "loading") then
					sendHome(t, nil, hq)
				end
				if t.state == "loading" and rig then
					if head[rig.id] == t then
						local v = math.min(num("trucks.loadPerSec") * dt, capacity - t.payload, rig.tank)
						t.payload += v
						rig.tank -= v
						rig.store = rig.tank
						local full = t.payload >= capacity - 1e-6
						local dry = rig.tank <= 1e-6 and t.payload >= math.min(num("rigs.truckMinLoad"), capacity) and t.payload >= capacity * 0.5
						if (full or dry) and routeOf(rig) then
							sendHome(t, rig, hq)
						end
					end
					continue
				end
				if t.state == "unloading" then
					t.timer += dt
					if t.timer < num("trucks.unloadSec") then
						continue
					end
					if t.payload > 0 then
						credit(t.side, t.payload)
						event({ type = "delivered", side = t.side, oil = t.payload, rig = if rig then rig.id else nil })
						t.payload = 0
					end
					if rig then
						if routeOf(rig) then
							sendOut(t, rig)
						end
					else
						self.sides[t.side].trucksIdle += 1
						t.alive = false
						event({ type = "truckIdle", side = t.side })
					end
					continue
				end
				-- driving along the path (APPROX: cell centre to cell centre)
				local path = t.path
				local speed = num("convoys.speed") * num("trucks.kinds.light.paceShare")
				local c = cellAt(t.x, t.y)
				if roads.isRoad(c) then
					speed *= num(`roads.classes.{Roads.CLASS_NAME[roads.classAt(c)]}.truck`)
				end
				local stepLen = speed * dt
				while stepLen > 0 and t.pathIndex <= #path do
					local tx, ty = centre(path[t.pathIndex])
					local dx, dy = tx - t.x, ty - t.y
					local d = math.sqrt(dx * dx + dy * dy)
					if d > 1e-6 then
						t.heading = math.atan2(dy, dx)
					end
					if d <= stepLen then
						t.x, t.y = tx, ty
						stepLen -= d
						t.pathIndex += 1
					else
						t.x += dx / d * stepLen
						t.y += dy / d * stepLen
						stepLen = 0
					end
					t.moved = true
				end
				if t.pathIndex > #path then
					if t.state == "out" and rig then
						t.state, t.queue = "loading", nil
					else
						t.state, t.timer = "unloading", 0
					end
				end
			end
		end
	end

	---------------------------------------------------------------- production, economy, verdict

	-- the game's updateStructures: construction, repair, then the head of each production queue
	local function production(dt: number)
		for _, st in self.list do
			if st.alive and isStructure(st) then
				if st.built < 1 then
					st.built = math.min(1, st.built + dt / math.max(0.01, num(`structures.{st.kind}.buildSec`)))
					if st.built >= 1 then
						event({ type = "built", id = st.id, kind = st.kind, side = st.side })
					end
				else
					local why = self.inactiveReason(st)
					if st.kind ~= "hq" and st.hp < st.maxHp and self.time - st.lastHitAt > 5 and why ~= "damaged" then
						st.hp = math.min(st.maxHp, st.hp + st.maxHp * num("production.repairPerSec") * dt)
					end
					if #st.queue > 0 and not why then
						local item = st.queue[1]
						st.queueProgress += dt / math.max(0.01, num(`units.{item}.buildSec`))
						if st.queueProgress >= 1 then
							st.queueProgress = 0
							table.remove(st.queue, 1)
							local x, y = rallyPoint(st, self.nextId)
							if not roads.passable(cellAt(x, y)) then
								x, y = freePointNear(x, y)
							end
							local u = self.spawnUnit(item, st.side, x, y)
							event({ type = "unitReady", id = u.id, side = st.side, kind = item, from = st.id })
						end
					end
				end
			end
		end
	end

	-- seconds left on the head of a producer's queue (the HQ when none is given)
	function self.queueLeft(side: number, structureId: number?): number?
		local st = if structureId then self.entities[structureId] else hqOf(side)
		if not st or not st.alive or not st.queue or #st.queue == 0 then
			return nil
		end
		return (1 - st.queueProgress) * math.max(0.01, num(`units.{st.queue[1]}.buildSec`))
	end

	-- the game's checkHeadless: a nation without an HQ that may rehouse (an active factory) has
	-- hqLoss.graceSec; without one it is out at once. (The command truck that rebuilds an HQ is not in
	-- the slice, so a headless nation is out when the grace runs out.)
	local function checkHeadless()
		for side, s in self.sides do
			if not s.lost then
				if hqOf(side) then
					s.headlessSince = nil
				elseif not hasBuilding(side, "factory", true) then
					eliminateRef(side, -1)
				else
					s.headlessSince = s.headlessSince or self.time
					if self.time - s.headlessSince > num("hqLoss.graceSec") then
						eliminateRef(side, -1)
					end
				end
			end
		end
	end

	local function hqTrickle(dt: number)
		local o = num("rigs.hqOil") * dt
		if o <= 0 then
			return
		end
		for side, s in self.sides do
			if not s.lost and hqOf(side) then
				s.oil += o * s.oilMult
			end
		end
	end

	local function checkVerdict()
		if self.winner then
			return
		end
		local left = {}
		for side, s in self.sides do
			if not s.lost then
				table.insert(left, side)
			end
		end
		if #left == 1 then
			self.winner = left[1]
			event({ type = "victory", side = left[1] })
		elseif #left == 0 then
			self.winner = 0
			event({ type = "victory", side = 0 })
		end
	end

	local function compact()
		local keep = table.create(#self.list)
		for _, e in self.list do
			if e.alive then
				table.insert(keep, e)
			else
				self.entities[e.id] = nil
			end
		end
		self.list = keep
	end

	local function packSecOf(e: Entity): number
		return if text(unitKey(e) .. ".weapon") == "mortar" then num("mortar.packSec") else num("artillery.packSec")
	end

	function self.step(dt: number)
		if self.winner then
			return
		end
		self.time += dt
		self.ticks += 1
		if self.ticks % 10 == 0 then
			updateConnections()
		end
		production(dt)
		reconTick(dt)
		checkHeadless()
		landStrikes()
		structuresFire(dt)
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK then
				e.px, e.py, e.firing = e.x, e.y, false
				e.moved = false
				-- the game's Qze: a deployed gun (it fired) packs up for packSec before it can move
				local held = false
				if e.packAt ~= nil then
					local going = e.target ~= nil and e.path ~= nil
					if e.packAt < 0 then
						if going then
							e.packAt = self.time + packSecOf(e)
							e.still = 0
							held = true
						end
					elseif self.time < e.packAt then
						held = true
					else
						e.packAt = nil
					end
				end
				e.stillStep = if held then "held" elseif e.target and e.path then "move" else "still"
				if held then
					-- packing: stands where it is
				elseif e.target and e.path then
					e.moved = pathing.step(e, dt)
					if e.path and e.pathIndex > #e.path then
						-- arrive (idle where it stands)
						e.target, e.path, e.spot = nil, nil, nil
					end
				elseif e.target then
					e.target = nil
				end
			end
		end
		unitsFire(dt)
		-- seconds standing still (artillery sets up before firing): moving resets it, packing holds it
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.stillStep then
				if e.stillStep == "move" then
					e.still = 0
				elseif e.stillStep == "still" then
					e.still = (e.still or 0) + dt
				end
			end
		end
		-- face direction: aim while firing, else hull heading (vehicles), else motion
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK then
				local mx, my
				if e.firing then
					mx, my = e.aimX - e.x, e.aimY - e.y
				elseif hasHull(e) then
					mx, my = math.cos(e.heading), math.sin(e.heading)
				else
					mx, my = e.x - e.px, e.y - e.py
				end
				local m = math.sqrt(mx * mx + my * my)
				if m > 1e-4 then
					e.faceX, e.faceY = mx / m, my / m
				end
			end
		end
		rigs(dt)
		updateRoutes()
		trucks(dt)
		hqTrickle(dt)
		compact()
		checkVerdict()
	end

	---------------------------------------------------------------- vision (fog of war)

	-- The game's day/night: a 480 s day starting at phase 0.08; night from phase 0.62, easing in over
	-- 0.08 and out over the last 0.05 of the day. Returns 0 (day) .. 1 (full night).
	local DAY_SEC, DAY_START, SUN_UP, NIGHT_IN, NIGHT_OUT = 480, 0.08, 0.62, 0.08, 0.05
	local function smooth(a: number, b: number, o: number): number
		local n = math.clamp((o - a) / (b - a), 0, 1)
		return n * n * (3 - 2 * n)
	end
	function self.nightAmount(): number
		local clock = numOr("daylight.offsetSec", 0) + self.time * numOr("daylight.rate", 1)
		local phase = ((math.floor(clock) / DAY_SEC + DAY_START) % 1 + 1) % 1
		if phase < SUN_UP then
			return 0
		end
		return math.min(smooth(SUN_UP, SUN_UP + NIGHT_IN, phase), 1 - smooth(1 - NIGHT_OUT, 1, phase))
	end
	-- sight multiplier at night: nightOps.sightShare when night ops are on (the slice has no night
	-- vision tower), else daylight.nightSightShare
	local function sightFactor(): number
		local share = if r:has("nightOps.enabled") and r:flag("nightOps.enabled") then num("nightOps.sightShare") else num("daylight.nightSightShare")
		return 1 + (share - 1) * self.nightAmount()
	end
	self.sightFactor = sightFactor

	-- The game's PS for one nation, for the sources the slice has: fills grid (1-based by cell + 1)
	-- with 2 where the nation sees and 0 elsewhere. Sources: its structures (a building under
	-- construction sees footprint + 1 cells), its rigs (rigs.sight), its units (units.<k>.sight; units
	-- in the same 1.5 x cell scale block with the same rounded sight count once), its trucks
	-- (intel.convoySight); all x the night factor. No line-of-sight blockers in the slice (the game's
	-- only blockers are settlement buildings).
	function self.visionFor(side: number, grid: { number })
		local n = W * H
		for i = 1, n do
			grid[i] = 0
		end
		local function circle(x: number, y: number, m: number)
			local mm = m * m
			for py = math.max(0, math.floor(y - m)), math.min(H - 1, math.ceil(y + m)) do
				local hh = py + 0.5 - y
				local o = mm - hh * hh
				if o >= 0 then
					local q = math.sqrt(o)
					local t0 = math.max(0, math.ceil(x - 0.5 - q))
					local t1 = math.min(W - 1, math.floor(x - 0.5 + q))
					local base = py * W + 1
					for c = t0, t1 do
						grid[base + c] = 2
					end
				end
			end
		end
		local c = sightFactor()
		for _, st in self.list do
			if st.alive and isStructure(st) and st.side == side then
				local x, y = st.cell % W + 0.5, st.cell // W + 0.5
				if st.built < 1 then
					circle(x, y, (footprintOf(st.kind) + 1) * c)
				else
					circle(x, y, num(`structures.{st.kind}.sight`) * c)
				end
			end
		end
		for _, rig in rigList do
			if rig.side == side then
				circle(rig.x, rig.y, num("rigs.sight") * c)
			end
		end
		local seen = {}
		local f = math.max(2, math.floor(num("match.cellScale") * 1.5 + 0.5))
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.side == side then
				if e.kind == TRUCK then
					local m = numOr("intel.convoySight", 0) * c
					if m > 0 then
						circle(e.x, e.y, m)
					end
				else
					local m = num(`units.{e.kind}.sight`) * c
					local key = (math.floor(e.y / f) * 4096 + math.floor(e.x / f)) * 64 + math.floor(m + 0.5)
					if not seen[key] then
						seen[key] = true
						circle(e.x, e.y, m)
					end
				end
			end
		end
		-- deployed scouts see intel.scoutReconRadius (not shortened by night)
		local rr = num("intel.scoutReconRadius")
		for _, e in self.list do
			if e.alive and e.side == side and (e.reconLeft or 0) > 0 then
				circle(e.x, e.y, rr)
			end
		end
		-- enemy guns that fired lately are revealed (artillery.revealCells around them)
		local rc = num("artillery.revealCells")
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.side ~= side and e.revealedUntil and e.revealedUntil > self.time then
				circle(e.x, e.y, rc)
			end
		end
	end
	function self.fogOn(): boolean
		return r:has("intel.fog") and r:flag("intel.fog")
	end

	-- Drains events (for networking / logging).
	function self.takeEvents(): { Event }
		local ev = self.events
		self.events = {}
		return ev
	end

	updateConnections()
	return self
end

return Sim
