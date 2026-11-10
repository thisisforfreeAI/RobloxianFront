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
	Production  per producer (HQ, barracks, factory; units.<k>.from), paid up front (unitCost: units.<k>.cost
	            less settlement discounts), units.<k>.buildSec / (1 + workforce) each, production.maxQueue, match.unitCap counts units plus every
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
	        nearest free cell centre; vehicles drive with the game's model (Pathing: accelerate, brake,
	        corner, pivot / three-point turn, reverse) minus formations, overtaking and dodging; a
	        standing vehicle without a turret turns its hull to its target (the game's Wat).
	UNCONFIRMED: the territory edge noise uses the map's seed (the game uses its match seed); where
	        the headless check sits in the tick order.
	UNCONFIRMED (older): new units start with no face direction and an empty shot timer; a dead nation's
	        trucks are removed; a firing vehicle's hull keeps its heading (turrets not modelled).
	Idle units (idleThink / holdAtEnemy below): each unit keeps a post (where it was sent, stopped or
	        arrived). Standing idle, an armed unit chases enemies within movement.leashCells of its post
	        and walks back once more than half the leash away; a unit walking straight into an enemy it
	        can hurt holds movement.enemySpaceCells short. Idle foot soldiers step into better cover
	        nearby when an enemy is in range (seekCover). APPROX: unarmed units are
	        not slid round enemies, and smoke does not hide chase targets.
	Engineers (orderRepair below): mend a damaged own structure, footprint + engineers.reach away, at
	        maxHp x engineers.structureSharePerSec per engineer per second (up to crewMax). Not in the
	        slice: road wear and cuts, rig blowouts, rail, sabotage, trenches, building with engineers.
	Fog: visionFor / nightAmount below; the server filters snapshots per side (Shared.Simulation.Fog).
	Not in the slice: line of sight (the game's only blockers are settlement buildings), weather, veterancy, smoke, rig damage,
	        settlement traits and damage, refineries, rail, events, SAM, radar, rocket artillery (salvo barrages),
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
	settlements: { { name: string?, x: number, y: number, kind: string } }?, -- map order
	seed: number?,
	drop: boolean?, -- start with the game's opening drop instead of HQs on the start points
	armies: { string }?, -- per side: "coalition" (the default) or "republic"
	deckSeed: number?, -- the match's own seed for the opening deck (the game draws one per match); else seed
}

export type Event = { type: string, [string]: any }

local TRUCK = "truck"
local BULLET_SPEED = 70 -- cells/s, the game's bullet flight speed
-- cells/s, the game's shot speeds for the other weapons
local SHOT_SPEED: { [string]: number } = {
	cannon = 38, rocket = 22, missile = 18, shell = 13, salvo = 9.5, bomb = 11, mortar = 6.5, barrage = 11, flare = 12,
	tbm = 15, -- the republic's heavy missile
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
	self.rules = r
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

	-- the game's N7e: how much road wear slows traffic on a cell (0 below roads.wear.from, up to
	-- 1 - roads.wear.slow on a fully worn road)
	local function wearSlow(c: number): number
		local n = roads.wearAt(c)
		local from = num("roads.wear.from")
		if n <= from then
			return 0
		end
		return (n - from) / math.max(1e-6, 1 - from) * (1 - num("roads.wear.slow"))
	end
	self.wearSlow = wearSlow
	-- Unit pace multiplier on a point (the game's paceOn; speed itself comes from units.<k>.speed).
	local function paceAt(kind: string, x: number, y: number): number
		local c = cellAt(x, y)
		if c < 0 or not roads.passable(c) then
			return 0
		end
		local move = text(`units.{kind}.move`)
		if roads.isRoad(c) and move ~= "sea" and text(`units.{kind}.armour`) ~= "air" then
			local cu = num(`roads.classes.{Roads.CLASS_NAME[roads.classAt(c)]}.unit`) * (1 - wearSlow(c))
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
	-- the game's traffic: trucks and road vehicles slow each other within traffic.cells (FWe / BWe)
	local trafficTick, trafficTrucks, trafficCars = -1, {} :: { Entity }, {} :: { Entity }
	local function trafficLists()
		if trafficTick ~= self.ticks then
			trafficTick = self.ticks
			table.clear(trafficTrucks)
			table.clear(trafficCars)
			for _, e in self.list do
				if e.alive and e.cat == "unit" and not e.inside then
					if e.kind == TRUCK then
						table.insert(trafficTrucks, e)
					else
						local mv = text(`units.{e.kind}.move`)
						if (mv == "tracks" or mv == "wheels") and roads.isRoad(cellAt(e.x, e.y)) then
							table.insert(trafficCars, e)
						end
					end
				end
			end
		end
		return trafficTrucks, trafficCars
	end
	local function anyWithin(list: { Entity }, x: number, y: number, rr: number): boolean
		for _, o in list do
			if (o.x - x) ^ 2 + (o.y - y) ^ 2 <= rr * rr then
				return true
			end
		end
		return false
	end
	-- a tracked or wheeled unit on a road with a truck near keeps only traffic.unitShare of its road
	-- bonus (the game's UWe)
	pathing.trafficPace = function(e: Entity, cell: number, speed: number, u: number): number
		if cell < 0 or not roads.isRoad(cell) then
			return u
		end
		local mv = text(`units.{e.kind}.move`)
		if mv ~= "tracks" and mv ~= "wheels" then
			return u
		end
		local trucks = trafficLists()
		if anyWithin(trucks, e.x, e.y, num("traffic.cells")) then
			return speed + math.max(0, u - speed) * num("traffic.unitShare")
		end
		return u
	end
	-- a truck on a road with a road vehicle within traffic.cells drives at traffic.truckShare (FWe)
	local function truckJammed(t: Entity): boolean
		local _, cars = trafficLists()
		return anyWithin(cars, t.x, t.y, num("traffic.cells"))
	end
	self.truckJammed = truckJammed
	self.trafficPace = pathing.trafficPace
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

	local gridTick = -1 -- the unit grid's tick (see unitsNear); a new entity drops the grid
	local function add(e: Entity): Entity
		e.id = self.nextId
		self.nextId += 1
		self.entities[e.id] = e
		table.insert(self.list, e)
		gridTick = -1
		return e
	end

	-- the game's armyDef: a republic unit with an armyUnits.republic.<kind> entry reads its stats from
	-- there (the rest from units.<kind>, filled in once below)
	local unitKey = (function()
		local armyKinds: { [string]: { [string]: boolean } } = {}
		local fill = {}
		for k in r.data do
			local army, kind = string.match(k, "^armyUnits%.([%w_]+)%.([%w_]+)%.")
			if army and kind then
				armyKinds[army] = armyKinds[army] or {}
				if not armyKinds[army][kind] then
					armyKinds[army][kind] = true
					table.insert(fill, { army, kind })
				end
			end
		end
		for _, f in fill do
			local base, over = `units.{f[2]}.`, `armyUnits.{f[1]}.{f[2]}.`
			local add = {}
			for k, v in r.data do
				if string.sub(k, 1, #base) == base then
					local rest = string.sub(k, #base + 1)
					-- an overridden table (vs, missile) replaces the base one whole
					local head = string.match(rest, "^([%w_]+)%.")
					if r.data[over .. rest] == nil and not (head and r.data[over .. head .. ".soft"] ~= nil) then
						add[over .. rest] = v
					end
				end
			end
			for k, v in add do
				r.data[k] = v
			end
		end
		return function(e: Entity): string
			if e.kind == "hq" then
				return "structures.hq"
			end
			local army = deps.armies and deps.armies[e.side]
			if army and armyKinds[army] and armyKinds[army][e.kind] then
				return `armyUnits.{army}.{e.kind}`
			end
			return `units.{e.kind}`
		end
	end)()
	self.unitKey = unitKey

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
		local hq = if deps.drop then nil else add({
			kind = "hq", cat = "structure", class = "structure", side = side, x = s.x, y = s.y,
			cell = cellAt(s.x, s.y), heading = 0, hp = hpHq, maxHp = hpHq, shotTimer = 0, alive = true,
			queue = {}, queueProgress = 0, built = 1, lastHitAt = -99,
		})
		self.sides[side] = {
			oil = num("match.startOil"), hqId = if hq then hq.id else -1, lost = false, trucksIdle = num("trucks.startIdle"),
			oilMult = 1, oilEarned = 0, headlessSince = nil, kills = 0, killsSpent = 0,
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
	for _, s in if deps.drop then {} else self.sides do
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
	local PLACEABLE = { barracks = true, factory = true, bunker = true, atgun = true, radar = true, sam = true, artybase = true, nightops = true }
	local SLICE_UNITS = { infantry = true, engineer = true, at = true, tank = true, ifv = true, mortar = true, artillery = true, scout = true, rocket = true, command = true }
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
	local leaveGarrison: (Entity) -> ()
	local eliminateRef: (number, number) -> () = function(_s: number, _b: number) end

	-- Block or free a structure's footprint (the game's tUe / YB): units standing inside step out
	-- (RY) and units whose route crosses it re-plan (HY).
	local function setFootprint(st: Entity, on: boolean)
		if st.kind == "minefield" then
			return -- the game's tUe: mines never block the way
		end
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
		local hq0 = self.entities[s.hqId]
		if hq0 then
			setFootprint(hq0, true)
		end
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
		return st.alive and isStructure(st) and st.built >= 1 and st.kind ~= "minefield"
	end
	-- Settlements (the game's hme): neutral at the start, captured like rigs (see settlementsTick).
	-- A held town, city or capital claims territory: its urban radius (the game's PV: the larger of
	-- settlements.<kind>Radius and the radius of a disc as big as the urban cells nearest it) plus
	-- cities.claim.margin.<kind>. Villages claim nothing.
	local settlements: { Entity } = {}
	for i, sd in deps.settlements or {} do
		local cx = math.clamp(math.floor(sd.x), 0, W - 1)
		local cy = math.clamp(math.floor(sd.y), 0, H - 1)
		local key = `settlements.{sd.kind}Radius`
		local ikey = `settlements.{sd.kind}Integrity`
		local integ = if r:has(ikey) then num(ikey) else 0
		table.insert(settlements, {
			id = i, name = sd.name or "", kind = sd.kind, cell = cy * W + cx, x = cx + 0.5, y = cy + 0.5,
			radius = if r:has(key) then num(key) else 0, owner = 0, capture = nil, hold = 0, takenAt = -999,
			warnedAt = -99, urbanR = 0, garrison = {},
			integrity = integ, maxIntegrity = integ, destroyed = false, lastHitAt = -99,
		})
	end
	self.settlements = settlements
	if #settlements > 0 and map.urbanAt then
		local counts = {}
		for c = 0, W * H - 1 do
			if map.urbanAt(c) then
				local x, y = c % W + 0.5, c // W + 0.5
				local best, bd = settlements[1], math.huge
				for _, st in settlements do
					local d = (st.x - x) ^ 2 + (st.y - y) ^ 2
					if d < bd then
						best, bd = st, d
					end
				end
				counts[best.id] = (counts[best.id] or 0) + 1
			end
		end
		for _, st in settlements do
			st.urbanR = math.sqrt((counts[st.id] or 0) / math.pi)
		end
	end
	local function claimRadius(st: Entity): number
		if not r:flag("cities.claim.on") or st.owner <= 0 then
			return 0
		end
		local kinds = r.data["cities.claim.kinds"] :: { string }?
		if not kinds or not table.find(kinds, st.kind) then
			return 0
		end
		return math.max(st.radius, st.urbanR) + num(`cities.claim.margin.{st.kind}`)
	end
	self.claimRadius = claimRadius

	-- the game's e2: neutral; occupied (held, nobody inside); fortified; secured (cities.garrisonFull)
	local function cityStatus(st: Entity): string
		if st.owner <= 0 then
			return "neutral"
		end
		local n = #st.garrison
		return if n <= 0 then "occupied" elseif n >= num(`cities.garrisonFull.{st.kind}`) then "secured" else "fortified"
	end
	self.cityStatus = cityStatus
	-- the game's Iwe: each secured settlement widens its owner's building territory (capped)
	local function paintBonus(side: number): number
		local n = 0
		for _, st in settlements do
			if st.owner == side and cityStatus(st) == "secured" then
				n += num(`cities.paintBonus.{st.kind}`)
			end
		end
		return math.min(num("cities.paintBonusMax"), n)
	end
	self.paintBonus = paintBonus

	-- the game's eZe: traits for towns and cities (cities.traits.kinds). Each settlement goes to the
	-- start nearest it; starts within contestShare x that distance of the nearest share it. Each group
	-- (same set of starts), nearest first, takes cities.traits.order in turn, a contested group
	-- starting at the number of starts sharing it, so both sides' nearest towns get the same traits.
	if r:flag("cities.traits.on") then
		local order = (r.data["cities.traits.order"] :: { string }?) or {}
		local kinds = (r.data["cities.traits.kinds"] :: { string }?) or {}
		local share = num("cities.traits.contestShare")
		if #order > 0 and #deps.starts > 0 then
			local groups: { [string]: { from: number, list: { any } } } = {}
			local keys = {}
			for _, st in settlements do
				if table.find(kinds, st.kind) then
					local ds = {}
					local best = 1
					for i, sp in deps.starts do
						ds[i] = math.sqrt((st.x - (math.floor(sp.x) + 0.5)) ^ 2 + (st.y - (math.floor(sp.y) + 0.5)) ^ 2)
						if ds[i] < ds[best] then
							best = i
						end
					end
					local near = {}
					for i, d in ds do
						if d - ds[best] <= ds[best] * share then
							table.insert(near, tostring(i - 1))
						end
					end
					local key = table.concat(near, ",")
					local g = groups[key]
					if not g then
						g = { from = if #near > 1 then #near else 0, list = {} }
						groups[key] = g
						table.insert(keys, key)
					end
					table.insert(g.list, { s = st, d = ds[best] })
				end
			end
			for _, key in keys do
				local g = groups[key]
				table.sort(g.list, function(a, b)
					if a.d ~= b.d then
						return a.d < b.d
					end
					return a.s.id < b.s.id
				end)
				for i, it in g.list do
					it.s.trait = order[(g.from + i - 1) % #order + 1]
				end
			end
		end
	end
	-- the game's eA: a trait works while its settlement is held and secured (power is off in match rules)
	local function traitActive(st: Entity): boolean
		return r:flag("cities.traits.on") and st.trait ~= nil and st.owner > 0 and cityStatus(st) == "secured"
	end
	self.traitActive = traitActive
	-- the game's Owe: a side holding a secured capital sees all of its own territory
	function self.surveillanceOn(side: number): boolean
		for _, st in settlements do
			if st.kind == "capital" and st.owner == side and cityStatus(st) == "secured" then
				return true
			end
		end
		return false
	end
	-- the game's tZe: a truck within radius + rail.reach of its owner's working rail town drives
	-- rail.pace times faster
	local function railPace(side: number, x: number, y: number): number
		if not r:flag("cities.traits.on") then
			return 1
		end
		for _, st in settlements do
			if st.trait == "rail" and st.owner == side then
				local l = st.radius + num("cities.traits.rail.reach")
				if (st.x - x) ^ 2 + (st.y - y) ^ 2 <= l * l and traitActive(st) then
					return num("cities.traits.rail.pace")
				end
			end
		end
		return 1
	end
	self.railPace = railPace
	-- the game's unitCost: secured settlements (hN, cities.discount.<kind>) and working factory towns
	-- (factory.discount each, vehicles only) cut the price, together at most cities.discountMax
	local function unitCost(side: number, item: string): number
		local base = num(`units.{item}.cost`)
		local disc = 0
		for _, st in settlements do
			if st.owner == side and cityStatus(st) == "secured" then
				disc += num(`cities.discount.{st.kind}`)
			end
		end
		disc = math.min(num("cities.discountMax"), disc)
		local mv = text(`units.{item}.move`)
		if mv ~= "foot" and mv ~= "sea" and r:flag("cities.traits.on") then
			local f = 0
			for _, st in settlements do
				if st.trait == "factory" and st.owner == side and traitActive(st) then
					f += num("cities.traits.factory.discount")
				end
			end
			disc = math.min(num("cities.discountMax"), disc + f)
		end
		local v = base * (1 - disc)
		return math.floor(v + 0.5) -- Math.round (no negative costs)
	end
	self.unitCost = unitCost
	-- the game's ile / productionSpeed / buildTime: secured settlements add cities.workforce.<kind>
	-- (max workforceMax) to production speed; a unit takes buildSec / (1 + workforce)
	local function workforce(side: number): number
		local n = 0
		for _, st in settlements do
			if st.owner == side and cityStatus(st) == "secured" then
				n += num(`cities.workforce.{st.kind}`)
			end
		end
		return math.min(num("cities.workforceMax"), n)
	end
	self.workforce = workforce
	local function buildTime(side: number, item: string): number
		return math.max(0.01, num(`units.{item}.buildSec`)) / (1 + workforce(side))
	end
	self.buildTime = buildTime
	-- the game's Fpe: a held, secured town or city (cities.forward.kinds) trains units itself
	local function forwardActive(st: Entity): boolean
		local kinds = r.data["cities.forward.kinds"] :: { string }?
		return r:flag("cities.forward.on") and st.owner > 0 and kinds ~= nil and table.find(kinds, st.kind) ~= nil
			and cityStatus(st) == "secured"
	end
	self.forwardActive = forwardActive

	local function baseSources(only: number?): { any }
		local out = {}
		for _, st in self.list do
			if builtStructure(st) and alive(st.side) and (only == nil or st.side == only) then
				table.insert(out, {
					nation = st.side, x = st.cell % W + 0.5, y = st.cell // W + 0.5, structure = st.id,
					r = num(`structures.{st.kind}.buildRadius`) * num("territory.reachShare") * (1 + paintBonus(st.side)),
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
		for _, st in settlements do
			if st.owner > 0 and (only == nil or st.owner == only) and alive(st.owner) then
				local cr = claimRadius(st)
				if cr > 0 then
					table.insert(out, { nation = st.owner, x = st.x, y = st.y, r = cr, settlement = st.id })
				end
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
		if st.demolishAt then
			return "demolishing"
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
			if st.alive and isStructure(st) and st.kind == "minefield" then
				for _, c in st.mineCells or {} do
					if math.abs(c % W - rx) <= a and math.abs(c // W - iy) <= a then
						return "spacing" -- APPROX: the game clears mines under a new building (guardsInWay)
					end
				end
			elseif st.alive and isStructure(st) then
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

	-- the game's killsOf / payKills: enemy units a side has killed, less what it has spent
	function self.killsOf(side: number): number
		local s = self.sides[side]
		return if s then math.max(0, (s.kills or 0) - (s.killsSpent or 0)) else 0
	end
	function self.payKills(side: number, n: number): boolean
		if n <= 0 then
			return true
		end
		local s = self.sides[side]
		if not s or s.lost or self.killsOf(side) < n then
			return false
		end
		s.killsSpent = (s.killsSpent or 0) + n
		return true
	end

	-- the game's canPlace, in its order
	function self.canPlace(side: number, kind: string, cell: number): string?
		if not PLACEABLE[kind] or not alive(side) or self.winner then
			return "blocked"
		end
		if kind == "nightops" and self.nightOpsRebuildIn(side) > 0 then
			return "rebuildWait"
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
			if st.alive and isStructure(st) and st.side ~= side and st.kind ~= "minefield"
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
		local kc = numOr(`structures.{kind}.killCost`, 0)
		if kc > 0 and self.killsOf(side) < kc then
			return "kills"
		end
		return nil
	end

	-- the game's placeStructure: pay, then the building goes up over buildSec
	function self.placeStructure(side: number, kind: string, cell: number): (number?, string?)
		local why = self.canPlace(side, kind, cell)
		if why then
			return nil, why
		end
		self.payKills(side, numOr(`structures.{kind}.killCost`, 0))
		self.sides[side].oil -= num(`structures.{kind}.cost`)
		local paid = num(`structures.{kind}.cost`)
		local hp = num(`structures.{kind}.hp`)
		local st = add({
			kind = kind, cat = "structure", class = "structure", side = side, x = cell % W + 0.5,
			y = cell // W + 0.5, cell = cell, heading = 0, hp = hp, maxHp = hp, shotTimer = 0, alive = true,
			queue = {}, queueProgress = 0, built = 0, lastHitAt = -99, paid = paid,
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
		return e ~= nil and e.alive and e.cat == "unit" and e.side == side and e.kind ~= TRUCK and e.carrier == nil
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
		e.post, e.chasing = cell, nil -- the game's walkTo: the unit's post is where it was sent
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
		e.repairId, e.roadJob, e.sabotageCell = nil, nil, nil -- any new order also ends a repair job (the game's clearOrders)
		e.barrage = nil -- and a rocket barrage order
		e.boarding = nil -- and boarding a carrier
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

	---------------------------------------------------------------- engineers' repair

	local function sq(ax: number, ay: number, bx: number, by: number): number
		return (ax - bx) ^ 2 + (ay - by) ^ 2
	end
	-- the game's Km for a structure job: where the crew works from, footprint + engineers.reach
	local function repairSpot(st: Entity): (number, number, number)
		local x, y = centre(st.cell)
		return x, y, footprintOf(st.kind) + num("engineers.reach")
	end
	-- the game's jX for a structure job: nil when it can be repaired, else the reason
	local function repairProblem(side: number, st: Entity?): string?
		if not st or not st.alive or st.cat ~= "structure" or st.side ~= side then
			return "notOwned"
		end
		if st.kind == "rig" then
			return "blocked" -- rig repair (blowouts) is a different job, not in the slice
		end
		if st.hp < st.maxHp and (st.built or 1) >= 1 then
			return nil
		end
		return "notDamaged"
	end
	local function isEngineer(e: Entity): boolean
		local ab = r.data[`units.{e.kind}.abilities`] :: { string }?
		return e.cat == "unit" and ab ~= nil and table.find(ab, "engineer") ~= nil
	end
	self.isEngineer = isEngineer
	-- the game's walkNear: walk to the nearest passable cell within r of (x, y); nothing when already
	-- there. APPROX: the game's route search ends on the first such cell its search reaches.
	local function walkNear(e: Entity, x: number, y: number, rr: number)
		e.path, e.target, e.spot = nil, nil, nil
		e.still = 0
		if sq(e.x, e.y, x, y) <= rr * rr then
			return
		end
		local q = math.max(0.5, rr)
		local best, bestD = -1, math.huge
		local k = math.ceil(q)
		local bx, by = math.floor(x), math.floor(y)
		for dy = -k, k do
			for dx = -k, k do
				local cx, cy = bx + dx, by + dy
				if cx >= 0 and cy >= 0 and cx < W and cy < H then
					local c = cy * W + cx
					if sq(cx + 0.5, cy + 0.5, x, y) <= q * q and roads.passable(c) then
						local g = sq(cx + 0.5, cy + 0.5, e.x, e.y)
						if g < bestD then
							best, bestD = c, g
						end
					end
				end
			end
		end
		if best >= 0 then
			local cx, cy = centre(best)
			planTo(e, best, cx, cy)
		end
	end
	-- the game's Th: the job ends and the engineer idles where it stands
	local function endJob(e: Entity)
		e.repairId, e.path, e.target, e.spot = nil, nil, nil, nil
		e.post = cellAt(e.x, e.y)
	end
	-- the game's repair (KX) for a damaged own structure: the given engineers, or with none given the
	-- engineers.crewMax nearest idle ones, walk to within 0.8 x reach of it and mend it.
	-- Returns (count sent, reason when none).
	function self.orderRepair(side: number, structureId: number, ids: { number }?): (number, string?)
		local st = self.entities[structureId]
		local why = repairProblem(side, st)
		if why then
			return 0, why
		end
		local x, y, reach = repairSpot(st :: Entity)
		local crew = {}
		if ids and #ids > 0 then
			for _, id in ids do
				local e = self.entities[id]
				if e and orderable(e, side) and isEngineer(e :: Entity) then
					table.insert(crew, e)
				end
			end
		else
			for _, e in self.list do
				if orderable(e, side) and isEngineer(e) and not e.repairId and not e.attackId then
					table.insert(crew, e)
				end
			end
			table.sort(crew, function(a: Entity, b: Entity)
				return sq(a.x, a.y, x, y) < sq(b.x, b.y, x, y)
			end)
			for i = #crew, num("engineers.crewMax") + 1, -1 do
				crew[i] = nil
			end
		end
		if #crew == 0 then
			return 0, "noEngineers"
		end
		for _, e in crew do
			e.attackId, e.chasing = nil, nil
			clearRecon(e)
			leaveGarrison(e)
			e.repairId = structureId
			walkNear(e, x, y, reach * 0.8)
		end
		return #crew, nil
	end
	-- the game's taskThink (Sme) for repair, every 20 ticks while the engineer stands: drop a job that
	-- is done or gone, walk back within reach if it drifted out.
	local function repairThink(e: Entity)
		local st = self.entities[e.repairId :: number]
		if repairProblem(e.side, st) then
			endJob(e)
			return
		end
		local x, y, reach = repairSpot(st :: Entity)
		if sq(e.x, e.y, x, y) > reach * reach then
			walkNear(e, x, y, reach * 0.8)
		end
	end
	-- the game's updateRepairs (Mme), structures: engineers within reach stop and work; each
	-- structure gains maxHp x engineers.structureSharePerSec x min(crew, crewMax) per second; when it
	-- is whole the crew is released.
	local function repairsTick(dt: number)
		local crews: { [number]: number } = {}
		for _, e in self.list do
			if e.alive and e.repairId then
				local st = self.entities[e.repairId]
				if st and st.alive then
					local x, y, reach = repairSpot(st)
					if sq(e.x, e.y, x, y) <= reach * reach then
						e.path, e.target, e.spot = nil, nil, nil
						e.aimX, e.aimY = x, y
						crews[st.id] = (crews[st.id] or 0) + 1
					end
				end
			end
		end
		for id, n in crews do
			local st = self.entities[id]
			if st and st.alive then
				local crew = math.min(n, num("engineers.crewMax"))
				st.hp = math.min(st.maxHp, st.hp + st.maxHp * num("engineers.structureSharePerSec") * crew * dt)
				if st.hp >= st.maxHp then
					event({ type = "repaired", id = st.id, side = st.side, kind = st.kind })
					for _, e in self.list do
						if e.alive and e.repairId == id then
							endJob(e)
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- road cuts, wear and road repair

	-- the game's XY: the class rules of a road cell (roads.classes.<class>)
	local function roadClassName(c: number): string
		return Roads.CLASS_NAME[roads.classAt(c)]
	end
	-- the game's uI with the class factor
	local function wearRoad(c: number, amount: number)
		if roads.isRoad(c) then
			roads.addWear(c, amount, numOr(`roads.classes.{roadClassName(c)}.wear`, 1))
		end
	end
	self.wearRoad = wearRoad
	-- the game's IWe: a tracked or wheeled unit entering a road cell wears it
	local function unitWear(kind: string, c: number)
		local move = text(`units.{kind}.move`)
		if move == "tracks" then
			wearRoad(c, num("roads.wear.tracks"))
		elseif move == "wheels" then
			wearRoad(c, num("roads.wear.wheels"))
		end
	end

	self.roadCuts = {} :: { [number]: any }
	local roadStrikes: { [number]: { damage: number, lastHitAt: number } } = {}
	local nextCutId = 1
	-- road cells (still road) whose centre lies within r of (x, y) (the game's H4 filtered to road)
	local function roadCellsNear(x: number, y: number, rr: number): { number }
		local out = {}
		local r2 = rr * rr
		for cy = math.floor(y - rr), math.ceil(y + rr) do
			if cy >= 0 and cy < H then
				for cx = math.floor(x - rr), math.ceil(x + rr) do
					if cx >= 0 and cx < W and (cx + 0.5 - x) ^ 2 + (cy + 0.5 - y) ^ 2 <= r2 then
						local c = cy * W + cx
						if roads.isRoad(c) then
							table.insert(out, c)
						end
					end
				end
			end
		end
		return out
	end
	-- the game's wh (cutRoad): every road cell within roads.cutRadius of the cell's centre stops being
	-- road until repaired; a cut on a bridge deck drops the bridge (impassable). Trucks whose way
	-- crosses it re-route, rig routes are redone and rig links re-checked.
	local function cutRoad(cell: number, by: number): any?
		if not roads.isRoad(cell) then
			return nil
		end
		local x, y = centre(cell)
		local cells = roadCellsNear(x, y, math.max(0.5, num("roads.cutRadius")))
		local hit = {}
		for _, c in cells do
			roads.setRoad(c, false)
			roadStrikes[c] = nil
			hit[c] = true
		end
		local bridge = false
		for _, c in cells do
			if not roads.passable(c) and roads.buildingAt(c) < 0 then
				bridge = true
			end
		end
		local cut = { id = nextCutId, cell = cell, x = x, y = y, cells = cells, by = by, at = self.time, repair = 0, repairBy = -1, bridge = bridge }
		nextCutId += 1
		self.roadCuts[cut.id] = cut
		local users: { [number]: boolean } = {} -- sides whose rig routes or trucks used it (the game's Ig)
		for _, rig in rigList do
			if rig.route then
				for _, c in rig.route do
					if hit[c] then
						users[rig.side] = true
						resetRoute(rig)
						break
					end
				end
			end
		end
		for _, t in self.list do
			if t.alive and t.kind == TRUCK and t.path and t.pathIndex then
				for i = t.pathIndex, #t.path do
					if hit[t.path[i]] then
						users[t.side] = true
						t.reroute = true
						break
					end
				end
			end
		end
		updateConnections()
		local list = {}
		for sd in users do
			if sd > 0 then
				table.insert(list, sd)
			end
		end
		table.sort(list)
		event({ type = if bridge then "bridgeDown" else "roadCut", id = cut.id, x = x, y = y, side = by, users = list })
		return cut
	end
	self.cutRoad = cutRoad
	-- the game's GX: a shell landing near a road wears the nearest road cell within roads.blastReach
	-- and adds to its strike damage; when the strikes within roads.cutRadius add up to
	-- roads.strikeHp the road is cut there.
	local function roadBlast(x: number, y: number, damage: number, by: number)
		local share = num("roads.blastShare")
		if damage <= 0 or share <= 0 then
			return
		end
		local rr = math.max(0.5, num("roads.blastReach"))
		local best, bestD = -1, rr * rr
		for cy = math.floor(y - rr), math.floor(y + rr) do
			for cx = math.floor(x - rr), math.floor(x + rr) do
				if cx >= 0 and cy >= 0 and cx < W and cy < H then
					local c = cy * W + cx
					if roads.isRoad(c) then
						local d = (cx + 0.5 - x) ^ 2 + (cy + 0.5 - y) ^ 2
						if d <= bestD then
							best, bestD = c, d
						end
					end
				end
			end
		end
		if best < 0 then
			return
		end
		wearRoad(best, damage * num("roads.wear.blast"))
		local s = roadStrikes[best]
		if not s then
			s = { damage = 0, lastHitAt = self.time }
			roadStrikes[best] = s
		end
		s.damage += damage * share * (1 - 0.5 * math.sqrt(bestD) / rr)
		s.lastHitAt = self.time
		local hx, hy = best % W, best // W
		local cr = num("roads.cutRadius")
		local sum = 0
		for c, k in roadStrikes do
			if (c % W - hx) ^ 2 + (c // W - hy) ^ 2 <= cr * cr then
				sum += k.damage
			end
		end
		if sum >= num("roads.strikeHp") then
			cutRoad(best, by)
		end
	end
	self.roadBlast = roadBlast
	-- strikes older than roads.strikeForgetSec are forgotten (checked every 10 ticks)
	local function forgetStrikes()
		if self.ticks % 10 ~= 0 then
			return
		end
		local keep = num("roads.strikeForgetSec")
		for c, s in roadStrikes do
			if self.time - s.lastHitAt > keep then
				roadStrikes[c] = nil
			end
		end
	end
	function self.roadStrikeAt(c: number): number
		local s = roadStrikes[c]
		return if s then s.damage else 0
	end

	-- the game's JY: road cells within roads.wear.repairRadius of a cell worn at least `atLeast` (0..255)
	local function wornNear(cell: number, atLeast: number): { number }
		local x, y = centre(cell)
		local out = {}
		for _, c in roadCellsNear(x, y, num("roads.wear.repairRadius")) do
			if roads.wearRaw(c) >= atLeast then
				table.insert(out, c)
			end
		end
		return out
	end
	-- the game's Km for road jobs: where the crew works from and how close it must be
	local function roadJobSpot(job: any): (number?, number?, number?)
		if job.kind == "wear" then
			if not roads.isRoad(job.id) then
				return nil
			end
			local x, y = centre(job.id)
			return x, y, num("roads.repairReach")
		end
		local cut = self.roadCuts[job.id]
		if not cut then
			return nil
		end
		return cut.x, cut.y, num("roads.cutRadius") + num("roads.repairReach")
	end
	-- the game's jX for road jobs
	local function roadJobProblem(job: any): string?
		if job.kind == "wear" then
			if not roads.isRoad(job.id) then
				return "notRoad"
			end
			if #wornNear(job.id, num("roads.wear.repairFrom") * roads.WEAR_MAX) == 0 then
				return "notWorn"
			end
			return nil
		end
		return if self.roadCuts[job.id] then nil else "noCut"
	end
	-- the cut whose cells (or centre) lie nearest (x, y) within r, for clicks and the bot
	function self.cutNear(x: number, y: number, rr: number): any?
		local best, bestD = nil, rr * rr
		for _, cut in self.roadCuts do
			local d = sq(cut.x, cut.y, x, y)
			if d <= bestD then
				best, bestD = cut, d
			end
		end
		return best
	end
	-- the game's Jke: the most worn road cell (at least roads.wear.repairFrom) in the 3x3 round a cell
	function self.wornCellNear(cell: number): number
		if cell < 0 then
			return -1
		end
		local from = num("roads.wear.repairFrom")
		local cx, cy = cell % W, cell // W
		local best, top = -1, 0
		for dy = -1, 1 do
			for dx = -1, 1 do
				local x, y = cx + dx, cy + dy
				if x >= 0 and y >= 0 and x < W and y < H then
					local c = y * W + x
					local v = roads.wearAt(c)
					if roads.isRoad(c) and v >= from and v > top then
						best, top = c, v
					end
				end
			end
		end
		return best
	end
	-- the game's KX for a road job: kind "cut" (id = cut id) or "wear" (id = road cell). Taking on a
	-- cut costs roads.repairCost oil once per side. Returns (count sent, reason when none).
	function self.orderRoadRepair(side: number, kind: string, id: number, ids: { number }?): (number, string?)
		local job = { kind = kind, id = id }
		local why = roadJobProblem(job)
		if why then
			return 0, why
		end
		local x, y, reach = roadJobSpot(job)
		if not x then
			return 0, "blocked"
		end
		local crew = {}
		if ids and #ids > 0 then
			for _, eid in ids do
				local e = self.entities[eid]
				if e and orderable(e, side) and isEngineer(e :: Entity) then
					table.insert(crew, e)
				end
			end
		else
			for _, e in self.list do
				if orderable(e, side) and isEngineer(e) and not e.repairId and not e.roadJob and not e.attackId then
					table.insert(crew, e)
				end
			end
			table.sort(crew, function(a: Entity, b: Entity)
				return sq(a.x, a.y, x :: number, y :: number) < sq(b.x, b.y, x :: number, y :: number)
			end)
			local max = if kind == "cut" then num("roads.repairCrewMax") else num("engineers.crewMax")
			for i = #crew, max + 1, -1 do
				crew[i] = nil
			end
		end
		if #crew == 0 then
			return 0, "noEngineers"
		end
		if kind == "cut" then
			local cut = self.roadCuts[id]
			if cut.repairBy ~= side then
				local s = self.sides[side]
				local cost = num("roads.repairCost")
				if s.oil < cost then
					return 0, "oil"
				end
				s.oil -= cost
				cut.repairBy = side
			end
		end
		for _, e in crew do
			e.attackId, e.chasing = nil, nil
			clearRecon(e)
			leaveGarrison(e)
			e.roadJob = job
			walkNear(e, x :: number, y :: number, (reach :: number) * 0.8)
		end
		return #crew, nil
	end
	local function endRoadJob(e: Entity)
		e.roadJob = nil
		endJob(e)
	end
	local function roadThink(e: Entity)
		local job = e.roadJob
		-- the game's Sme: a wear job only ends here when the cell is no longer road
		if (job.kind == "wear" and not roads.isRoad(job.id)) or (job.kind ~= "wear" and roadJobProblem(job)) then
			endRoadJob(e)
			return
		end
		local x, y, reach = roadJobSpot(job)
		if x and sq(e.x, e.y, x, y :: number) > (reach :: number) ^ 2 then
			walkNear(e, x, y :: number, (reach :: number) * 0.8)
		end
	end
	-- the game's updateRepairs (Mme), road part: a worn stretch loses
	-- max(1, round(roads.wear.repairPerSec x crew x dt x 255)) wear on every cell within
	-- wear.repairRadius each tick; a cut fills dt / (roads.repairSec) x crew (crew up to
	-- roads.repairCrewMax, only for the side that paid for it) and is road again at 1.
	local function roadRepairsTick(dt: number)
		local crews: { [string]: { job: any, n: number, by: number } } = {}
		for _, e in self.list do
			if e.alive and e.roadJob then
				local x, y, reach = roadJobSpot(e.roadJob)
				if x and sq(e.x, e.y, x, y :: number) <= (reach :: number) ^ 2 then
					e.path, e.target, e.spot = nil, nil, nil
					e.aimX, e.aimY = x, y
					local key = e.roadJob.kind .. e.roadJob.id
					local g = crews[key]
					if g then
						g.n += 1
					else
						crews[key] = { job = e.roadJob, n = 1, by = e.side }
					end
				end
			end
		end
		local function release(job: any)
			for _, e in self.list do
				if e.alive and e.roadJob and e.roadJob.kind == job.kind and e.roadJob.id == job.id then
					endRoadJob(e)
				end
			end
		end
		for _, g in crews do
			local job = g.job
			if job.kind == "wear" then
				local d = math.min(g.n, num("engineers.crewMax"))
				local by = math.max(1, math.floor(num("roads.wear.repairPerSec") * d * dt * roads.WEAR_MAX + 0.5))
				local left = false
				for _, c in wornNear(job.id, 1) do
					if not roads.mendWear(c, by) then
						left = true
					end
				end
				if not left then
					event({ type = "roadMended", cell = job.id, side = g.by })
					release(job)
				end
			else
				local cut = self.roadCuts[job.id]
				if cut and cut.repairBy == g.by then
					local d = math.min(g.n, num("roads.repairCrewMax"))
					cut.repair = math.min(1, cut.repair + dt / math.max(0.01, num("roads.repairSec")) * d)
					if cut.repair >= 1 then
						for _, c in cut.cells do
							roads.setRoad(c, true)
							roads.clearWear(c)
						end
						self.roadCuts[cut.id] = nil
						updateConnections()
						event({ type = "roadRepaired", id = cut.id, x = cut.x, y = cut.y, side = g.by })
						release(job)
					end
				end
			end
		end
	end

	---------------------------------------------------------------- road sabotage

	-- the game's sabotages: engineers plant a charge on a road cell (sabotage.plantSec while one of
	-- the crew stands within sabotage.reach), then it is armed and blows after fuseMinSec..fuseMaxSec,
	-- cutting the road like a shell strike would. A crew member that dies, takes damage or gets
	-- another order ends the planting ("sabotageFailed").
	self.sabotages = {} :: { [number]: any }
	local nextSabotageId = 1
	local function sabotageAt(cell: number): any?
		for _, s in self.sabotages do
			if s.cell == cell then
				return s
			end
		end
		return nil
	end
	self.sabotageAt = sabotageAt
	-- the game's Ig: sides whose rig routes or trucks' ways cross the cells
	local function routeUsers(cell: number): { [number]: boolean }
		local out = {}
		for _, rig in rigList do
			if rig.side > 0 and rig.route and table.find(rig.route, cell) then
				out[rig.side] = true
			end
		end
		for _, t in self.list do
			if t.alive and t.kind == TRUCK and t.path and table.find(t.path, cell) then
				out[t.side] = true
			end
		end
		return out
	end
	-- the game's XX: send engineers (the given ones, or the engineers.crewMax nearest idle ones) to
	-- sabotage a road cell. Returns (count sent, reason when none).
	function self.orderSabotage(side: number, cell: number, ids: { number }?): (number, string?)
		if cell < 0 or cell >= W * H then
			return 0, "notRoad"
		end
		if not roads.isRoad(cell) then
			for _, cut in self.roadCuts do
				if table.find(cut.cells, cell) then
					return 0, "alreadyCut"
				end
			end
			return 0, "notRoad"
		end
		local s = sabotageAt(cell)
		if s and s.phase == "armed" then
			return 0, "alreadyCut"
		end
		local x, y = centre(cell)
		local crew = {}
		if ids and #ids > 0 then
			for _, eid in ids do
				local e = self.entities[eid]
				if e and orderable(e, side) and isEngineer(e :: Entity) then
					table.insert(crew, e)
				end
			end
		else
			for _, e in self.list do
				if orderable(e, side) and isEngineer(e) and not e.repairId and not e.roadJob and not e.sabotageCell and not e.attackId then
					table.insert(crew, e)
				end
			end
			table.sort(crew, function(a: Entity, b: Entity)
				return sq(a.x, a.y, x, y) < sq(b.x, b.y, x, y)
			end)
			for i = #crew, num("engineers.crewMax") + 1, -1 do
				crew[i] = nil
			end
		end
		if #crew == 0 then
			return 0, if ids and #ids > 0 then "noSaboteurs" else "noEngineers"
		end
		for _, e in crew do
			e.attackId, e.chasing = nil, nil
			clearRecon(e)
			leaveGarrison(e)
			e.sabotageCell = cell
			walkNear(e, x, y, num("sabotage.reach") * 0.8)
		end
		return #crew, nil
	end
	local function endSabotageJob(e: Entity)
		e.sabotageCell = nil
		endJob(e)
	end
	-- the game's l1e
	local function failSabotage(s: any, notify: boolean)
		self.sabotages[s.id] = nil
		for _, id in s.crew do
			local e = self.entities[id]
			if e and e.alive and e.sabotageCell == s.cell then
				endSabotageJob(e)
			end
		end
		if notify then
			event({ type = "sabotageFailed", id = s.id, side = s.side, x = s.x, y = s.y })
		end
	end
	-- the game's Sme for sabotage, every 20 ticks while standing
	local function sabotageThink(e: Entity)
		local cell = e.sabotageCell :: number
		if not roads.isRoad(cell) then
			endSabotageJob(e)
			return
		end
		local x, y = centre(cell)
		local rr = num("sabotage.reach")
		if sq(e.x, e.y, x, y) > rr * rr then
			walkNear(e, x, y, rr * 0.8)
		end
	end
	-- the game's _me
	local function sabotageTick(dt: number)
		local rr = num("sabotage.reach")
		for _, e in self.list do
			if e.alive and e.sabotageCell then
				local cell = e.sabotageCell
				local x, y = centre(cell)
				if sq(e.x, e.y, x, y) <= rr * rr then
					if e.path then
						e.path, e.target, e.spot = nil, nil, nil
					end
					if not roads.isRoad(cell) then
						endSabotageJob(e)
						continue
					end
					e.aimX, e.aimY = x, y
					local s = sabotageAt(cell)
					if not s then
						local victims = {}
						for v in routeUsers(cell) do
							if v ~= e.side then
								table.insert(victims, v)
							end
						end
						s = { id = nextSabotageId, side = e.side, cell = cell, x = x, y = y, phase = "planting", progress = 0,
							fuseAt = 0, crew = {}, crewHp = {}, victims = victims }
						nextSabotageId += 1
						self.sabotages[s.id] = s
					end
					if s.side == e.side and s.phase == "planting" and not table.find(s.crew, e.id) then
						table.insert(s.crew, e.id)
						table.insert(s.crewHp, e.hp)
					end
				end
			end
		end
		for id, s in self.sabotages do
			if s.phase == "armed" then
				if self.time >= s.fuseAt then
					-- the game's FZe: the charge blows and cuts the road
					self.sabotages[id] = nil
					local cut = cutRoad(s.cell, s.side)
					if cut then
						cut.sabotage = true
						event({ type = "sabotageDone", id = s.id, side = s.side, x = s.x, y = s.y })
						for _, v in s.victims do
							event({ type = "roadSabotaged", id = cut.id, side = v, x = s.x, y = s.y })
						end
					end
				end
				continue
			end
			if not roads.isRoad(s.cell) then
				failSabotage(s, false)
				continue
			end
			local anyone, working, broken = false, false, false
			for i, eid in s.crew do
				local e = self.entities[eid]
				if not e or not e.alive or e.sabotageCell ~= s.cell then
					broken = true
					continue
				end
				if e.hp < s.crewHp[i] - 0.001 then
					broken = true
				end
				s.crewHp[i] = e.hp
				anyone = true
				if not e.path and sq(e.x, e.y, s.x, s.y) <= rr * rr then
					working = true
				end
			end
			if broken or not anyone then
				failSabotage(s, true)
				continue
			end
			if working then
				s.progress = math.min(1, s.progress + dt / math.max(0.01, num("sabotage.plantSec")))
				if s.progress >= 1 then
					-- the game's DZe: armed; the crew walks off to the nearest own finished building
					s.phase, s.progress = "armed", 1
					s.fuseAt = self.time + num("sabotage.fuseMinSec") + rand() * math.max(0, num("sabotage.fuseMaxSec") - num("sabotage.fuseMinSec"))
					event({ type = "sabotageArmed", id = s.id, side = s.side, x = s.x, y = s.y })
					local home, hd = nil, math.huge
					for _, st in self.list do
						if st.alive and st.cat == "structure" and st.side == s.side and (st.built or 1) >= 1 and st.kind ~= "rig" then
							local d = sq(st.x, st.y, s.x, s.y)
							if d < hd then
								home, hd = st, d
							end
						end
					end
					for _, eid in s.crew do
						local e = self.entities[eid]
						if e and e.alive then
							endSabotageJob(e)
							if home then
								walkNear(e, home.x, home.y, footprintOf(home.kind) + 1)
							end
						end
					end
				end
			end
		end
	end

	local joinShared: (Entity, number, number, number, { any }) -> boolean
	-- the game's straightPassable: a straight walk from (x, y) to a cell's centre over passable cells,
	-- sampled 8 times a cell, with 0.32-cell corners clear after the first step
	local function straightPassable(x: number, y: number, cell: number): boolean
		local ax, ay = centre(cell)
		local n = math.max(1, math.ceil(math.sqrt((ax - x) ^ 2 + (ay - y) ^ 2) * 8))
		local l = 0.32
		local function ok(px: number, py: number): boolean
			local c = cellAt(px, py)
			return c >= 0 and roads.passable(c)
		end
		for h = 0, n do
			local u, d = x + (ax - x) * h / n, y + (ay - y) * h / n
			if not ok(u, d) or (h > 0 and not (ok(u - l, d - l) and ok(u + l, d - l) and ok(u - l, d + l) and ok(u + l, d + l))) then
				return false
			end
		end
		return true
	end
	-- the game's joinAt: where a unit can step straight onto another's path (nearest point of it, then
	-- further along it as far as a straight walk allows), or -1
	local function joinAt(e: Entity, path: { number }): number
		local n = #path - 1
		if n < 1 then
			return -1
		end
		local best, bestD = 1, math.huge
		for r = 1, n do
			local cx, cy = centre(path[r])
			local d = (cx - e.x) ^ 2 + (cy - e.y) ^ 2
			if d < bestD then
				best, bestD = r, d
			end
		end
		local r = math.min(n - best, math.floor(math.sqrt(bestD) + 0.5))
		while r >= 0 do
			if straightPassable(e.x, e.y, path[best + r]) then
				return best + r
			end
			r = if r > 1 then r // 2 else r - 1
		end
		return -1
	end
	-- the game's route sharing in orderMove: a unit within movement.shareCells (x cell scale) of a
	-- groupmate already routed, whose route ends where a straight walk reaches this unit's slot, takes
	-- that route from where it can join it, then steps to its own slot. Returns true when it did.
	function joinShared(e: Entity, slot: number, sx: number, sy: number, shared: { any }): boolean
		local reach = num("movement.shareCells") * num("match.cellScale")
		local c = nil
		for _, p in shared do
			if (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 <= reach * reach then
				c = p
				break
			end
		end
		if not c or #c.path <= 2 then
			return false
		end
		local lx, ly = centre(c.path[#c.path])
		if not straightPassable(lx, ly, slot) then
			return false
		end
		local m = joinAt(e, c.path)
		if m < 0 then
			return false
		end
		local path = {}
		for i = m, #c.path - 1 do
			table.insert(path, c.path[i])
		end
		table.insert(path, slot)
		e.path, e.pathIndex, e.stall, e.stallTries = path, 1, 0, 0
		e.spot = { x = sx, y = sy }
		e.target = { x = sx, y = sy }
		e.goalCell = slot
		e.post, e.chasing = slot, nil
		return true
	end

	function self.orderMove(side: number, ids: { number }, x: number, y: number): { number }
		local refused = {}
		local group = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.attackId = nil
				clearRecon(e)
				leaveGarrison(e)
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
			local shared = {}
			for i, e in group do
				local s = slots[i]
				if s then
					local sx, sy = centre(s)
					if not joinShared(e, s, sx, sy, shared) then
						planTo(e, s, sx, sy)
						if e.path and #e.path > 0 then
							table.insert(shared, { x = e.x, y = e.y, path = e.path })
						end
					end
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
				e.target, e.attackId, e.path, e.chasing = nil, nil, nil, nil
				e.post = cellAt(e.x, e.y)
				clearRecon(e)
				leaveGarrison(e)
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
				leaveGarrison(e)
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
		for _, st in settlements do -- the game's sZe: forward queues count too
			if st.forward and st.forward.owner == side then
				n += #st.forward.queue
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
		if not self.armyAllows(st.side, item) then
			return "locked"
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
		if self.sides[st.side].oil < unitCost(st.side, item) then
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
		local cost = unitCost(side, item)
		s.oil -= cost
		table.insert(st.queue, item)
		st.queuePaid = st.queuePaid or {}
		table.insert(st.queuePaid, cost)
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
		-- the game's zwe: its settlements turn neutral
		for _, st in settlements do
			if st.owner == side then
				st.owner, st.hold, st.capture, st.takenAt = 0, 0, nil, self.time
			end
		end
		event({ type = "eliminated", side = side, by = by })
	end
	eliminateRef = eliminate

	-- the game's settlementCoreAt: the settlement whose radius holds (x, y), nearest centre first
	local function settlementCoreAt(x: number, y: number): Entity?
		local best, bd = nil, math.huge
		for _, st in settlements do
			local d = (st.x - x) ^ 2 + (st.y - y) ^ 2
			if d <= st.radius * st.radius and d < bd then
				best, bd = st, d
			end
		end
		return best
	end
	-- the game's lf (settlement part): shell fire landing in a settlement takes damage x
	-- settlements.collateral off its integrity; at 0 it lies in ruins (OD)
	local function collateral(x: number, y: number, damage: number, by: number)
		if damage <= 0 then
			return
		end
		local st = settlementCoreAt(x, y)
		if not st then
			return
		end
		st.integrity = math.max(0, st.integrity - damage * num("settlements.collateral"))
		st.lastHitAt = self.time
		if not st.destroyed and st.integrity <= 0 then
			st.destroyed, st.integrity = true, 0
			event({ type = "settlementDestroyed", id = st.id, side = st.owner, by = by })
		end
	end
	-- the game's integrityBand
	function self.integrityBand(st: Entity): string
		if st.destroyed or st.integrity <= 0 then
			return "destroyed"
		end
		local o = st.integrity / math.max(1, st.maxIntegrity)
		return if o < num("settlements.criticalBelow") then "critical" elseif o < num("settlements.damagedBelow") then "damaged" else "intact"
	end
	-- the game's RZe: after settlements.rebuild.quietSec without hits a settlement mends to full over
	-- rebuild.fullSec; ruins stand again at rebuild.standShare
	local function rebuildTick(dt: number)
		local full = num("settlements.rebuild.fullSec")
		if full <= 0 then
			return
		end
		for _, st in settlements do
			if st.integrity < st.maxIntegrity and self.time - st.lastHitAt >= num("settlements.rebuild.quietSec") then
				st.integrity = math.min(st.maxIntegrity, st.integrity + st.maxIntegrity / full * dt)
				if st.destroyed and st.integrity >= st.maxIntegrity * num("settlements.rebuild.standShare") then
					st.destroyed = false
					event({ type = "settlementRebuilt", id = st.id, side = st.owner })
				end
			end
		end
	end

	local function hitStructure(by: number, st: Entity, damage: number, bombard: boolean?)
		if not st.alive then
			return
		end
		if bombard then
			local cx, cy = centre(st.cell)
			collateral(cx, cy, damage, by)
			roadBlast(cx, cy, damage, by)
		end
		st.hp -= damage
		st.lastHitAt = self.time
		if st.hp > 0 then
			return
		end
		st.alive, st.hp = false, 0
		setFootprint(st, false)
		event({ type = "destroyed", id = st.id, kind = st.kind, side = st.side, by = by })
		if st.kind == "nightops" and self.sides[st.side] then
			-- the game's Mje: a lost tower can be replaced only after nightOps.rebuildSec
			local sd = self.sides[st.side]
			sd.nvRebuildAt = math.max(sd.nvRebuildAt or 0, self.time + num("nightOps.rebuildSec"))
			event({ type = "nightOpsLost", side = st.side, sec = num("nightOps.rebuildSec") })
		end
		if st.kind == "hq" then
			-- an active factory lets the nation rehouse within hqLoss.graceSec, else it is out
			if hasBuilding(st.side, "factory", true) or self.truckOf(st.side) then
				event({ type = "hqLostRebuild", side = st.side, sec = num("hqLoss.graceSec") })
			else
				eliminate(st.side, by)
			end
		end
	end

	local function hasHull(e: Entity): boolean
		return e.cat == "unit" and e.kind ~= TRUCK and text(unitKey(e) .. ".move") ~= "foot"
	end
	-- A per-tick grid of units (8-cell buckets) so that "who is near" questions do not scan every
	-- unit. Candidates come in bucket order; callers that break ties by list order use listIndex, so
	-- results (ties included) match a full scan. Built at
	-- the first question of a tick from positions then; queries pad the radius by 2 cells for units
	-- that move later in the same tick. Spawning a unit drops the grid.
	local GRID_B = 8
	local gridBuckets: { [number]: { Entity } } = {}
	local gridIndex: { [Entity]: number } = {}
	local function unitsNear(x: number, y: number, rr: number): { Entity }
		if gridTick ~= self.ticks then
			gridTick = self.ticks
			table.clear(gridBuckets)
			table.clear(gridIndex)
			for i, o in self.list do
				if o.alive and o.cat == "unit" then
					gridIndex[o] = i
					local k = (o.y // GRID_B) * 1024 + (o.x // GRID_B)
					local b = gridBuckets[k]
					if b then
						table.insert(b, o)
					else
						gridBuckets[k] = { o }
					end
				end
			end
		end
		local r = rr + 2
		local out = {}
		for by = (y - r) // GRID_B, (y + r) // GRID_B do
			for bx = (x - r) // GRID_B, (x + r) // GRID_B do
				local b = gridBuckets[by * 1024 + bx]
				if b then
					for _, o in b do
						table.insert(out, o)
					end
				end
			end
		end
		return out
	end
	self.unitsNear = unitsNear
	local function listIndex(o: Entity): number
		return gridIndex[o] or math.huge -- spawned after the grid was built: last in the list
	end
	-- the game's separate: each tick units ease apart. Friends closer than movement.separationCells
	-- (contactSpaceCells for a foot soldier in contact: firing or hit within contactSec) push at up to
	-- separationPace; enemies closer than enemySpaceCells push at up to enemySpacePace. A push that
	-- would leave passable ground (or move a soldier in contact to worse cover) is dropped; vehicles
	-- only slide along their heading. APPROX: no yard clearance, trenches or traffic jams.
	local function separate(dt: number)
		local sepPace = num("movement.separationPace") * dt
		local foePace = num("movement.enemySpacePace") * dt
		local foeSpace = if num("movement.enemySpaceCells") > 0 and foePace > 0 then num("movement.enemySpaceCells") else 0
		local sepCells = num("movement.separationCells")
		if (sepCells <= 0 or sepPace <= 0) and foeSpace <= 0 then
			return
		end
		local contactSec = num("movement.contactSec")
		for _, i in self.list do
			if not i.alive or i.cat ~= "unit" or i.kind == TRUCK or i.inside or i.class == "air" then
				continue
			end
			local move = text(unitKey(i) .. ".move")
			if move == "sea" or ((i.repairId or i.roadJob or i.sabotageCell) and not i.path) then
				continue
			end
			local contact = move == "foot" and (i.firing or (i.hitAt ~= nil and self.time - i.hitAt < contactSec))
			local h = if sepPace > 0 then (if contact then math.max(sepCells, num("movement.contactSpaceCells")) else sepCells) else 0
			local u = math.max(h, foeSpace)
			if u <= 0 then
				continue
			end
			local fx, fy, ex, ey = 0, 0, 0, 0
			for _, o in unitsNear(i.x, i.y, u) do
				if o == i or not o.alive or o.inside or o.cat ~= "unit" or o.kind == TRUCK then
					continue
				end
				local same = o.side == i.side
				local p = if same then h else foeSpace
				if p <= 0 or o.class == "air" or (not same and (text(unitKey(o) .. ".move") == "sea" or not canAttack(i.side, o.side))) then
					continue
				end
				local dx, dy = i.x - o.x, i.y - o.y
				local t = dx * dx + dy * dy
				if t < p * p then
					local dist = math.sqrt(t)
					local b = (p - dist) / p
					local px, py
					if dist > 1e-6 then
						px, py = dx / dist * b, dy / dist * b
					else
						local ang = ((math.min(i.id, o.id) * 0.618034 + math.max(i.id, o.id) * 0.381966) % 1) * math.pi * 2
						local z = if i.id < o.id then 1 else -1
						px, py = math.cos(ang) * z * b, math.sin(ang) * z * b
					end
					if same then
						fx += px
						fy += py
					else
						ex += px
						ey += py
					end
				end
			end
			if fx == 0 and fy == 0 and ex == 0 and ey == 0 then
				continue
			end
			local here = cellAt(i.x, i.y)
			local function ok(x: number, y: number): boolean
				local c = cellAt(x, y)
				return c >= 0 and roads.passable(c) and (c == here or roads.buildingAt(c) < 0)
			end
			local kx, ky = 0, 0
			if fx ~= 0 or fy ~= 0 then
				local m = math.sqrt(fx * fx + fy * fy)
				local sp = sepPace * math.min(1, m)
				kx, ky = fx / m * sp, fy / m * sp
				if contact and here >= 0 then
					local c = cellAt(i.x + kx, i.y + ky)
					if c >= 0 and c ~= here and coverAt(c) < coverAt(here) then
						kx, ky = 0, 0
					end
				end
			end
			if ex ~= 0 or ey ~= 0 then
				local m = math.sqrt(ex * ex + ey * ey)
				local sp = foePace * math.min(1, m)
				kx += ex / m * sp
				ky += ey / m * sp
			end
			local hull = hasHull(i) and i.heading ~= nil
			if hull then
				local cx, cy = math.cos(i.heading), math.sin(i.heading)
				local along = kx * cx + ky * cy
				kx, ky = cx * along, cy * along
			end
			if math.abs(kx) >= 1e-9 or math.abs(ky) >= 1e-9 then
				if ok(i.x + kx, i.y + ky) then
					i.x += kx
					i.y += ky
				elseif not hull then
					if kx ~= 0 and ok(i.x + kx, i.y) then
						i.x += kx
					elseif ky ~= 0 and ok(i.x, i.y + ky) then
						i.y += ky
					end
				end
			end
		end
	end

	-- the game's qat: the nearest enemy ground unit within r (ties to the lower id)
	local function nearestFoe(e: Entity, rr: number): Entity?
		local best, bestD = nil, rr * rr
		for _, o in unitsNear(e.x, e.y, rr) do
			if o.alive and o.cat == "unit" and o.kind ~= TRUCK and not o.inside and canAttack(e.side, o.side)
				and o.class ~= "air" and text(unitKey(o) .. ".move") ~= "sea" then
				local h = (o.x - e.x) ^ 2 + (o.y - e.y) ^ 2
				if h < bestD or (h == bestD and best and o.id < best.id) then
					best, bestD = o, h
				end
			end
		end
		return best
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

	-- the game's GM: units inside a settlement take cities.cover of a hit (securedCover.<kind> once secured)
	local function insideCover(u: Entity): number
		local st = u.garrisonCity and settlements[u.garrisonCity]
		if not st then
			return 1
		end
		return if cityStatus(st) == "secured" then num(`cities.securedCover.{st.kind}`) else num("cities.cover")
	end
	-- the game's Dwe: the secured settlement a unit sits in, if any
	local function securedIn(u: Entity): Entity?
		local st = u.inside and u.garrisonCity and settlements[u.garrisonCity]
		return if st and cityStatus(st) == "secured" then st else nil
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
			if u.alive and u.cat == "unit" and u.kind ~= TRUCK and not u.inside and d2(u.x, u.y, x, y) <= cells * cells
				and text(unitKey(u) .. ".move") == "foot" and (by < 0 or canAttack(by, u.side)) then
				n += 1
			end
		end
		return 1 + math.min(num("combat.bunchMax"), share * math.max(0, n - 1))
	end

	-- Veterancy (the game's $5 / Yat / AN / A0e / TN / PN / Jat / Qat): a unit that finishes off an enemy
	-- unit counts a kill; at veterancy.killsFor kills it ranks up (veteran, elite, hero). Each rank adds
	-- damagePerRank to its damage, takes reloadPerRank off its reload (not below half) and makes hits on
	-- it hurt 1 / (1 + healthPerRank x rank). From healFromRank it heals healPerSec of its hp a second
	-- when out of contact.
	self.RANKS = { "veteran", "elite", "hero" }
	function self.vetDamage(e: Entity): number
		local rk = e.rank or 0
		return if rk > 0 then 1 + rk * num("veterancy.damagePerRank") else 1
	end
	function self.vetReload(e: Entity): number
		local rk = e.rank or 0
		return if rk > 0 then math.max(0.5, 1 - rk * num("veterancy.reloadPerRank")) else 1
	end
	function self.vetTaken(e: Entity): number
		local rk = e.rank or 0
		return if rk > 0 then 1 / (1 + rk * num("veterancy.healthPerRank")) else 1
	end
	-- hp loss with the veterancy share; remembers which unit downed it (the game's PN)
	function self.vetHit(u: Entity, p: number, shooter: number?)
		local before = u.hp
		u.hp -= p * self.vetTaken(u)
		if shooter and p > 0 and u.hp <= 0 and before > 0 then
			u.downBy = shooter
		end
	end
	function self.vetPromote(u: Entity)
		if not (r:has("veterancy.on") and r:flag("veterancy.on")) or not u.downBy then
			return
		end
		local o = self.entities[u.downBy]
		if not o or not o.alive or o.cat ~= "unit" or o.side == u.side or not canAttack(o.side, u.side) then
			return
		end
		o.kills = (o.kills or 0) + 1
		local need = r.data["veterancy.killsFor"] :: { number }
		local rk = 0
		for i, k in need do
			if o.kills >= k then
				rk = i
			end
		end
		rk = math.min(rk, #self.RANKS)
		if rk > (o.rank or 0) then
			o.rank, o.promotedAt = rk, self.time
			event({ type = "unitPromoted", id = o.id, side = o.side, kind = o.kind, rank = self.RANKS[rk] })
		end
	end
	function self.vetHeal(dt: number)
		if not (r:has("veterancy.on") and r:flag("veterancy.on")) or num("veterancy.healPerSec") <= 0 then
			return
		end
		local n = math.max(1, math.floor(num("veterancy.healEveryTicks") + 0.5))
		if self.ticks % n ~= 0 then
			return
		end
		local from, rate, contactSec = num("veterancy.healFromRank"), num("veterancy.healPerSec"), num("movement.contactSec")
		for _, u in self.list do
			if u.alive and u.cat == "unit" and (u.rank or 0) >= from and u.hp > 0 then
				local base = num(unitKey(u) .. ".hp")
				local contact = u.firing or (u.hitAt ~= nil and self.time - u.hitAt < contactSec)
				if u.hp < base and not contact then
					u.hp = math.min(base, u.hp + base * rate * dt * n)
				end
			end
		end
	end

	local function killIfDead(u: Entity, by: number)
		if u.hp <= 0 and u.alive then
			u.alive = false
			self.vetPromote(u)
			if u.cargo and #u.cargo > 0 then
				self.bail(u) -- the game's gbe: riders jump out of a destroyed carrier
			end
			-- the game's killUnit: the side that hit it last gets a kill if they are enemies
			local ks = self.sides[by]
			if ks and u.cat == "unit" and by ~= u.side and canAttack(by, u.side) then
				ks.kills = (ks.kills or 0) + 1
			end
			event({ type = "destroyed", id = u.id, kind = u.kind, side = u.side, by = by })
		end
	end

	-- the game's hitUnit. splash > 0: the hit grows with bunching and half of it also lands on the
	-- target's comrades within splash cells. bombard (artillery fire): no flanking, no armour facing.
	local function hitUnit(target: Entity, dps: number, key: string, secs: number, by: number, fromX: number, fromY: number, splash: number?, bombard: boolean?, shooter: number?)
		local s = splash or 0
		local p = dps * vsOf(key, target.class) * secs
		if s > 0 then
			p *= bunchFactor(by, target.x, target.y)
		end
		local g = if target.class == "armour" and not bombard then num(`armour.{armourSide(target, fromX, fromY)}`) else 0
		if target.inside then
			p *= insideCover(target)
		elseif target.class ~= "air" then
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
		self.vetHit(target, p, shooter)
		target.hitAt, target.hitBy = self.time, by
		if bombard and target.class ~= "air" then
			collateral(target.x, target.y, p, by) -- shells landing in a town damage it
			roadBlast(target.x, target.y, p, by) -- and near a road wear it, and can cut it
		end
		if s > 0 then
			for _, b in self.list do
				if b ~= target and b.alive and b.cat == "unit" and b.kind ~= TRUCK and b.side == target.side
					and d2(b.x, b.y, target.x, target.y) <= s * s and vsOf(key, b.class) > 0 then
					self.vetHit(b, p * 0.5 * (if b.inside and not target.inside then insideCover(b) else 1), shooter)
					b.hitAt, b.hitBy = self.time, by
					killIfDead(b, by)
				end
			end
		end
		killIfDead(target, by)
	end

	local function hitTruck(t: Entity, dps: number, key: string, secs: number, by: number)
		t.hp -= dps * (if key == "" then 1 else vsOf(key, "armour")) * secs
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

	local rocketLands: (by: number, x: number, y: number, damage: number, key: string, aimed: Entity?, splash: number?, shooter: number?) -> ()
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
			if s.kind == "rocket" then
				rocketLands(s.by, s.x, s.y, s.damage, s.key, if t and t.alive then t else nil, s.splash, s.shooter)
			elseif t and t.alive then
				if s.kind == "unit" then
					hitUnit(t, s.dps, s.key, s.secs, s.by, s.fromX, s.fromY, s.splash, s.bombard, s.shooter)
				elseif s.kind == "convoy" then
					hitTruck(t, s.dps, s.key, s.secs, s.by)
				else
					hitStructure(s.by, t, s.damage, s.bombard)
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
		local bestI = -1
		for _, o in unitsNear(x, y, range) do
			if validUnitTarget(side, o, key) then
				local d = d2(x, y, o.x, o.y)
				-- the game keeps the last (in list order) of equally near targets
				if d >= lo and (d < bestD or (d == bestD and listIndex(o) > bestI)) and (not ok or ok(o)) then
					best, bestD, bestI = o, d, listIndex(o)
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
			if o.alive and o.cat == "structure" and o.kind ~= "rig" and canAttack(side, o.side) and not self.mineHidden(o, side) then
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
		local vr = if e.cat == "unit" then self.vetReload(e) else 1
		local secs = shoot(e, num(key .. ".reloadSec") * vr, dt)
		if secs <= 0 then
			return
		end
		local arty = e.cat == "unit" and text(key .. ".nato") == "artillery"
		if e.cat == "unit" then
			e.firedAt = self.time
			dps = dps * self.vetDamage(e) / vr -- the game's AN / A0e: same reload share off, more damage on
		end
		if arty then
			-- the game's Jze: a firing gun is revealed to the enemy and stays deployed (packs before moving)
			e.revealedUntil = self.time + num("artillery.revealSec")
			e.packAt = -1
		end
		local strike: { [string]: any } = {
			kind = kind, at = self.time + flight(key, e.x, e.y, tx, ty), target = target.id, dps = dps,
			key = key, secs = secs, by = e.side, fromX = e.x, fromY = e.y, shooter = if e.cat == "unit" then e.id else nil,
		}
		if kind == "unit" and e.cat == "unit" then
			strike.splash = numOr(key .. ".splash", 0)
			strike.bombard = arty
		end
		if kind == "structure" then
			strike.damage = dps * vsOf(key, "structure") * secs
			strike.bombard = arty
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
				if dps > 0 and numOr(key .. ".vs.air", 0) < 1 then -- SAM sites shoot only aircraft and drones
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
		local reach = (if spot then range else math.min(range, num(unitKey(e) .. ".sight") * self.sightFactor(e.side)))
			* num("combat.attackRangeShare")
		local f = math.min(reach * 0.9, minR * num("mortar.backOffShare"))
		local p = math.sqrt(d2(e.x, e.y, t.x, t.y))
		if p >= f and p <= reach then
			if e.path then
				e.post = cellAt(e.x, e.y)
			end
			e.target, e.path, e.chasing = nil, nil, nil
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

	-- Rocket artillery (weapon "salvo"; the game's orderBarrage / salvo / rocketLands / Qze / eUe):
	-- it fires only on an order. Sent at a point at least artillery.rocketMinRange away, it drives to
	-- 0.9 x range if out of range, raises its rails for raiseSec once stopped, then (when reloaded,
	-- reloadSec 45) fires artillery.rockets rockets about stagger 0.75 s apart (+-45%), each landing
	-- within rocketSpread of the point (random angle, sqrt-spread radius, from a seed of its id and the
	-- time, as the game). Each rocket carries dps x reloadSec / rockets and hits everything within
	-- rocketSplash: units x hit table x cover x bunching, buildings whose edge is within the splash
	-- (and the building aimed at), trucks, and the nearest road. After the last rocket it lowers its
	-- rails for lowerSec, then drives scootCells away from where it fired.
	local salvoTick: (e: Entity, key: string, dt: number) -> ()
	do
		local R: any = {}
		function R.imul(a: number, b: number): number
			a, b = a % 4294967296, b % 4294967296
			local ah, al = a // 65536, a % 65536
			local bh, bl = b // 65536, b % 65536
			return (((ah * bl + al * bh) % 65536) * 65536 + al * bl) % 4294967296
		end
		-- the game's Xb: a seed from the launcher's id and the time
		function R.seed(id: number, t: number): number
			return bit32.bxor(R.imul(id + 1, 2654435761), R.imul(math.floor(t * 1000 + 0.5) + 1, 2246822507))
		end
		-- the game's P_: n rockets { at, a, r } from a seed
		function R.pattern(seed: number, n: number, stagger: number, jitter: number): { any }
			local st = seed % 4294967296
			local function nextR(): number
				st = (st + 1831565813) % 4294967296
				local l = R.imul(bit32.bxor(st, bit32.rshift(st, 15)), bit32.bor(1, st))
				l = bit32.bxor((l + R.imul(bit32.bxor(l, bit32.rshift(l, 7)), bit32.bor(61, l))) % 4294967296, l)
				return bit32.bxor(l, bit32.rshift(l, 14)) / 4294967296
			end
			local out, at = {}, 0
			for i = 0, n - 1 do
				if i > 0 then
					at += stagger * (1 + (nextR() * 2 - 1) * jitter)
				end
				local a = nextR() * math.pi * 2
				local rr = math.sqrt(nextR())
				table.insert(out, { at = at, a = a, r = rr })
			end
			return out
		end
		local STAGGER, JITTER = 0.75, 0.45 -- the game's Hu.stagger / staggerJitter
		self.salvoSeed = R.seed
		function self.salvoPattern(seed: number, n: number, stagger: number, jitter: number?): { any }
			return R.pattern(seed, n, stagger, jitter or JITTER)
		end
		function rocketLands(by: number, x: number, y: number, damage: number, key: string, aimed: Entity?, splash: number?, shooter: number?)
			local c = splash or num("artillery.rocketSplash")
			local bunch = bunchFactor(by, x, y)
			for _, u in self.list do
				if u.alive and u.cat == "unit" and u.kind ~= TRUCK and canAttack(by, u.side) and u.class ~= "air" then
					local vs = vsOf(key, u.class)
					if vs > 0 and (u.x - x) ^ 2 + (u.y - y) ^ 2 <= c * c then
						local cover = if u.inside then insideCover(u) else 1 - coverAt(cellAt(u.x, u.y))
						self.vetHit(u, damage * vs * cover * bunch, shooter)
						u.hitAt, u.hitBy = self.time, by
						killIfDead(u, by)
					end
				end
			end
			for _, st in self.list do
				if st.alive and isStructure(st) and st.kind ~= "rig" and canAttack(by, st.side) then
					local cx, cy = centre(st.cell)
					if math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2) - footprintOf(st.kind) <= c or st == aimed then
						hitStructure(by, st, damage * vsOf(key, "structure"), false)
					end
				end
			end
			for _, t in self.list do
				if t.alive and t.kind == TRUCK and canAttack(by, t.side) and (t.x - x) ^ 2 + (t.y - y) ^ 2 <= c * c then
					hitTruck(t, damage, key, 1, by)
				end
			end
			roadBlast(x, y, damage, by)
		end
		-- the game's salvo(): the rockets as strikes; returns when the last one leaves
		function R.salvo(e: Entity, key: string, tx: number, ty: number, total: number): number
			local n = math.max(1, math.floor(num("artillery.rockets") + 0.5))
			local spread = num("artillery.rocketSpread")
			local each = total / n
			local cell = cellAt(tx, ty)
			local bid = if cell >= 0 then roads.buildingAt(cell) else -1
			local aimed = if bid >= 0 then self.entities[bid] else nil
			if aimed and not (aimed.alive and canAttack(e.side, aimed.side)) then
				aimed = nil
			end
			local list = R.pattern(R.seed(e.id, self.time), n, STAGGER, JITTER)
			for _, k in list do
				local x, y = tx + math.cos(k.a) * k.r * spread, ty + math.sin(k.a) * k.r * spread
				table.insert(self.strikes, { kind = "rocket", at = self.time + k.at + flight(key, e.x, e.y, x, y), x = x, y = y,
					damage = each, key = key, by = e.side, target = if aimed then aimed.id else -1, shooter = e.id })
			end
			return list[#list].at
		end
		-- the game's lS: the launcher's own minimum range (the missile's), else artillery.rocketMinRange
		function self.minRangeOf(key: string): number
			return numOr(key .. ".missile.minRange", num("artillery.rocketMinRange"))
		end
		-- the game's launchMissile: one heavy missile on the point (flight at the tbm speed), its whole
		-- damage over missile.splash; it leaves at once
		function R.missile(e: Entity, key: string, tx: number, ty: number, total: number): number
			local cell = cellAt(tx, ty)
			local bid = if cell >= 0 then roads.buildingAt(cell) else -1
			local aimed = if bid >= 0 then self.entities[bid] else nil
			if aimed and not (aimed.alive and canAttack(e.side, aimed.side)) then
				aimed = nil
			end
			table.insert(self.strikes, { kind = "rocket", at = self.time + math.sqrt(d2(e.x, e.y, tx, ty)) / SHOT_SPEED.tbm,
				x = tx, y = ty, damage = total, key = key, by = e.side, target = if aimed then aimed.id else -1,
				splash = num(key .. ".missile.splash"), shooter = e.id })
			return 0
		end
		function salvoTick(e: Entity, key: string, dt: number)
			e.shotTimer -= dt
			local b = e.barrage
			local moving = e.target ~= nil and e.path ~= nil
			if not b or moving then
				return
			end
			local range = num(key .. ".range")
			local p = math.sqrt((b.x - e.x) ^ 2 + (b.y - e.y) ^ 2)
			if p > range then
				if (e.id + self.ticks) % 20 == 0 then
					walkNear(e, b.x, b.y, range * 0.9)
				end
			elseif p < self.minRangeOf(key) then
				e.barrage = nil
			else
				e.firing, e.aimX, e.aimY = true, b.x, b.y
				if (e.still or 0) >= num("artillery.raiseSec") and e.shotTimer <= 0 then
					local reload = num(key .. ".reloadSec")
					local j = num("combat.reloadJitter")
					e.shotTimer = reload * self.vetReload(e) * (1 - j + rand() * 2 * j)
					e.firedAt = self.time
					e.revealedUntil = self.time + num("artillery.revealSec")
					local total = num(key .. ".dps") * reload * self.vetDamage(e)
					local last = if r:has(key .. ".missile.splash") then R.missile(e, key, b.x, b.y, total) else R.salvo(e, key, b.x, b.y, total)
					e.packAt = self.time + last + num("artillery.lowerSec")
					e.barrage = nil
					event({ type = "barrageFired", id = e.id, side = e.side, x = b.x, y = b.y })
				end
			end
		end
		-- the game's eUe: once the rails are down, an idle launcher drives scootCells away from its aim
		function self.scoot(e: Entity)
			if e.barrage or (e.target and e.path) or e.attackId then
				return
			end
			local sx, sy = e.x - (e.aimX or e.x), e.y - (e.aimY or e.y)
			local r = math.sqrt(sx * sx + sy * sy)
			if r < 1e-6 then
				sx, sy = 0, 1
			else
				sx, sy = sx / r, sy / r
			end
			local d = num("artillery.scootCells")
			walkNear(e, math.clamp(e.x + sx * d, 0.5, W - 0.5), math.clamp(e.y + sy * d, 0.5, H - 0.5), num("match.cellScale"))
		end
	end
	-- Artillery base (the game's artyBase: cA / vI / mJ / mge / gJ / wge). Built for structures.artybase.killCost
	-- kills (no oil); strikes are paid in kills too. A barrage (barrage.price kills, then waitSec before
	-- the next) lands barrage.rounds shells about gapSec apart (+-45%) within barrage.spread of the point,
	-- barrage.damage shared out, each hitting barrage.splash round it with the barrage.vs table. Enemy SAM
	-- sites that are built, reloaded and in range of a landing point each stop up to intercept.perSam
	-- shells and then reload for intercept.reloadSec. A flare shot (flare.price kills) fires flare.count
	-- flares about shellGapSec apart within flare.spread; each bursts on arrival and lights flare.radius
	-- for burnSec for its side, drifting downwind at flare.drift cells/s. Range artyBase.range from the
	-- base's cell.
	self.flares = {} :: { any }
	self.samShotAt = {} :: { [number]: number }
	do
	local nextFlare = 1
	local WIND_X, WIND_Y = 0.85, 0.25 -- the game's Ks.windX / windY
	function self.artyProblem(side: number, baseId: number, kind: string, x: number, y: number): string?
		local b = self.entities[baseId]
		if not b or b.kind ~= "artybase" or not b.alive or b.side ~= side then
			return "notOwned"
		end
		if not alive(side) then
			return "blocked"
		end
		if self.inactiveReason(b) then
			return "notOperational"
		end
		if x ~= x or y ~= y or cellAt(x, y) < 0 then
			return "blocked"
		end
		local cx, cy = centre(b.cell)
		local rg = num("artyBase.range")
		if (x - cx) ^ 2 + (y - cy) ^ 2 > rg * rg then
			return "outOfRange"
		end
		if ((b.strikeReady or {})[kind] or 0) - self.time > 0 then
			return "cooldown"
		end
		if self.killsOf(side) < num(`artyBase.{kind}.price`) then
			return "kills"
		end
		return nil
	end
	-- the game's mge: SAM sites stop shells headed into their cover
	local function intercept(side: number, list: { any }): { [number]: boolean }
		local stopped: { [number]: boolean } = {}
		local per = numOr("artyBase.barrage.intercept.perSam", 0)
		if per <= 0 or #list == 0 then
			return stopped
		end
		local order = {}
		for i = 1, #list do
			order[i] = i
		end
		table.sort(order, function(a, b)
			return if list[a].at ~= list[b].at then list[a].at < list[b].at else a < b
		end)
		local n, total = 0, 0
		local bySide: { [number]: number } = {}
		local reload, samReload = num("artyBase.barrage.intercept.reloadSec"), num("structures.sam.reloadSec")
		for _, st in self.list do
			if st.alive and st.kind == "sam" and st.built >= 1 and canAttack(st.side, side)
				and self.time - (self.samShotAt[st.id] or -math.huge) >= samReload then
				local sx, sy = centre(st.cell)
				local range = num("structures.sam.range")
				local d = 0
				for _, i in order do
					if d >= per then
						break
					end
					if not stopped[i] and (list[i].x - sx) ^ 2 + (list[i].y - sy) ^ 2 <= range * range then
						stopped[i] = true
						d += 1
					end
				end
				if d > 0 then
					self.samShotAt[st.id] = self.time + math.max(0, reload) - samReload
					bySide[st.side] = (bySide[st.side] or 0) + d
					n += d
				end
			end
		end
		total = #list
		if n > 0 then
			local first = list[order[1]]
			event({ type = "barrageIntercepted", side = side, n = n, total = total, x = first.x, y = first.y })
			for s, k in bySide do
				event({ type = "barrageStopped", side = s, n = k, x = first.x, y = first.y })
			end
		end
		return stopped
	end
	-- the game's vI: pay, set the wait, fire
	function self.artyStrike(side: number, baseId: number, kind: string, x: number, y: number): (boolean, string?)
		local why = self.artyProblem(side, baseId, kind, x, y)
		if why then
			return false, why
		end
		if not self.payKills(side, num(`artyBase.{kind}.price`)) then
			return false, "kills"
		end
		local b = self.entities[baseId]
		local wait = num("artyBase.cooldownSec")
		if kind == "barrage" then
			wait = math.max(wait, numOr("artyBase.barrage.waitSec", 0))
		end
		b.strikeReady = b.strikeReady or {}
		b.strikeReady[kind] = self.time + wait
		b.firedAt, b.fired = self.time, kind
		local bx, by = centre(b.cell)
		if kind == "barrage" then
			local seed = self.salvoSeed(-2 - b.id, self.time)
			local n = math.max(1, math.floor(num("artyBase.barrage.rounds") + 0.5))
			local spread = num("artyBase.barrage.spread")
			local list = {}
			for _, k in self.salvoPattern(seed, n, num("artyBase.barrage.gapSec")) do
				local px, py = x + math.cos(k.a) * k.r * spread, y + math.sin(k.a) * k.r * spread
				table.insert(list, { x = px, y = py, at = k.at + math.sqrt(d2(bx, by, px, py)) / SHOT_SPEED.barrage })
			end
			local stopped = intercept(side, list)
			local cell = cellAt(x, y)
			local bid = if cell >= 0 then roads.buildingAt(cell) else -1
			local aimed = if bid >= 0 then self.entities[bid] else nil
			local aimId = if aimed and aimed.alive and canAttack(side, aimed.side) then aimed.id else -1
			local each = num("artyBase.barrage.damage") / n
			for i, k in list do
				if not stopped[i] then
					table.insert(self.strikes, { kind = "rocket", at = self.time + k.at, x = k.x, y = k.y, damage = each,
						key = "artyBase.barrage", by = side, target = aimId, splash = num("artyBase.barrage.splash") })
				end
			end
			event({ type = "artyBarrage", id = b.id, side = side, x = x, y = y, seed = seed })
		else
			local count = math.max(1, math.floor(num("artyBase.flare.count") + 0.5))
			local spread, gap, jit = num("artyBase.flare.spread"), num("artyBase.flare.shellGapSec"), num("artyBase.flare.shellGapJitter")
			local t = self.time
			for i = 1, count do
				if i > 1 then
					t += gap * (1 + (rand() * 2 - 1) * jit)
				end
				local a = rand() * math.pi * 2
				local f = math.sqrt(rand()) * spread
				local px, py = math.clamp(x + math.cos(a) * f, 0.5, W - 0.5), math.clamp(y + math.sin(a) * f, 0.5, H - 0.5)
				local burst = t + math.sqrt(d2(bx, by, px, py)) / SHOT_SPEED.flare
				table.insert(self.flares, { id = nextFlare, side = side, x = px, y = py, firedAt = t, burstAt = burst,
					untilT = burst + num("artyBase.flare.burnSec"), r = num("artyBase.flare.radius") })
				nextFlare += 1
			end
			event({ type = "artyFlares", id = b.id, side = side, x = x, y = y })
		end
		return true, nil
	end
	-- the game's wge: burning flares drift downwind; spent ones go
	function self.flaresTick(dt: number)
		if #self.flares == 0 then
			return
		end
		local w = math.max(1e-6, math.sqrt(WIND_X * WIND_X + WIND_Y * WIND_Y))
		local o = num("artyBase.flare.drift") * dt
		local keep = {}
		for _, f in self.flares do
			if self.time < f.untilT then
				if self.time >= f.burstAt then
					f.x = math.clamp(f.x + WIND_X / w * o, 0.5, W - 0.5)
					f.y = math.clamp(f.y + WIND_Y / w * o, 0.5, H - 0.5)
				end
				table.insert(keep, f)
			end
		end
		self.flares = keep
	end
	end

	-- the game's orderBarrage: launchers among ids that are at least rocketMinRange from the point
	-- take the order; those out of range drive to 0.9 x range. Returns (count, reason when none).
	function self.orderBarrage(side: number, ids: { number }, x: number, y: number): (number, string?)
		local launchers = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) and not e.inside and text(unitKey(e) .. ".weapon") == "salvo" then
				table.insert(launchers, e)
			end
		end
		if #launchers == 0 then
			return 0, "noLaunchers"
		end
		local n = 0
		for _, e in launchers do
			if math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2) >= self.minRangeOf(unitKey(e)) then
				e.target, e.attackId, e.path, e.chasing = nil, nil, nil, nil
				clearRecon(e)
				e.barrage = { x = x, y = y }
				local range = num(unitKey(e) .. ".range")
				if math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2) > range then
					walkNear(e, x, y, range * 0.9)
				end
				n += 1
			end
		end
		if n == 0 then
			return 0, "tooClose"
		end
		return n, nil
	end

	local function unitsFire(dt: number)
		for _, e in self.list do
			if e.alive and e.hp > 0 and e.cat == "unit" and e.kind ~= TRUCK then
				local key = unitKey(e)
				local dps = num(key .. ".dps")
				if text(key .. ".weapon") == "salvo" then
					salvoTick(e, key, dt) -- rocket artillery fires only on a barrage order
				elseif dps > 0 then
					local range = num(key .. ".range")
					-- inside a secured settlement: cities.securedFire.<kind> x dps, + rooftopRange.<kind>
					local sec = securedIn(e)
					if sec then
						dps *= num(`cities.securedFire.{sec.kind}`)
						range += num(`cities.rooftopRange.{sec.kind}`)
					end
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
								if e.path then
									e.post = cellAt(e.x, e.y)
								end
								e.target, e.path, e.chasing = nil, nil, nil
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

	---------------------------------------------------------------- garrisons

	-- the game's _m: out of the settlement (or no longer heading there); it stands where it is
	function leaveGarrison(e: Entity)
		if not e.garrisonCity then
			return
		end
		local st = settlements[e.garrisonCity]
		if st then
			local i = table.find(st.garrison, e.id)
			if i then
				table.remove(st.garrison, i)
			end
		end
		e.inside, e.garrisonCity = nil, nil
		e.post = cellAt(e.x, e.y)
	end
	self.leaveGarrison = leaveGarrison
	-- the game's Vwe: in, at the settlement's centre
	local function enterGarrison(st: Entity, e: Entity)
		e.inside, e.garrisonCity = true, st.id
		e.target, e.path, e.spot, e.attackId, e.chasing = nil, nil, nil, nil, nil
		e.x, e.y, e.px, e.py = st.x, st.y, st.x, st.y
		e.still, e.post = 0, st.cell
		table.insert(st.garrison, e.id)
	end
	local function canGarrison(e: Entity): boolean
		local kinds = r.data["cities.garrisonUnits"] :: { string }?
		return e.cat == "unit" and kinds ~= nil and table.find(kinds, e.kind) ~= nil and e.class ~= "air"
	end
	self.canGarrison = canGarrison
	-- units walking to garrison a settlement (the game's Pw)
	local function garrisonWalking(st: Entity): number
		local n = 0
		for _, e in self.list do
			if e.alive and e.garrisonCity == st.id and not e.inside and e.side == st.owner then
				n += 1
			end
		end
		return n
	end
	self.garrisonWalking = garrisonWalking
	-- the game's orderGarrison (Fwe): the nearest eligible units, up to the free slots
	-- (cities.garrisonFull.<kind> - inside - walking), go in; those within radius + enterReach enter at
	-- once, the rest walk there. Returns (count, reason when none).
	function self.orderGarrison(side: number, cityId: number, ids: { number }): (number, string?)
		local st = settlements[cityId]
		if not st or st.owner ~= side or not alive(side) then
			return 0, "notHeld"
		end
		local list = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) and canGarrison(e :: Entity) and (e :: Entity).garrisonCity ~= st.id then
				table.insert(list, e)
			end
		end
		if #list == 0 then
			return 0, "noGarrisonUnits"
		end
		local free = num(`cities.garrisonFull.{st.kind}`) - #st.garrison - garrisonWalking(st)
		if free <= 0 then
			return 0, "garrisonFull"
		end
		table.sort(list, function(a, b)
			local da, db = d2(a.x, a.y, st.x, st.y), d2(b.x, b.y, st.x, st.y)
			if da ~= db then
				return da < db
			end
			return a.id < b.id
		end)
		local reach = st.radius + num("cities.enterReach")
		local n = 0
		for i = 1, math.min(free, #list) do
			local e = list[i]
			e.attackId = nil
			clearRecon(e)
			leaveGarrison(e)
			if d2(e.x, e.y, st.x, st.y) <= reach * reach then
				enterGarrison(st, e)
				n += 1
			else
				planTo(e, st.cell, st.x, st.y) -- APPROX of the game's walkNear(centre, radius)
				if e.path then
					e.garrisonCity = st.id
					n += 1
				end
			end
		end
		if n > 0 then
			return n, nil
		end
		return 0, "unreachable"
	end
	-- the game's PQe and Bwe, each tick: walkers enter on reaching radius + enterReach (or give up
	-- when it is full, lost or out of reach); the garrison list drops dead or departed units.
	local function garrisonTick()
		for _, e in self.list do
			if e.alive and e.garrisonCity and not e.inside then
				local st = settlements[e.garrisonCity]
				if not st or st.owner ~= e.side then
					leaveGarrison(e)
				else
					local reach = st.radius + num("cities.enterReach")
					if d2(e.x, e.y, st.x, st.y) <= reach * reach then
						if #st.garrison >= num(`cities.garrisonFull.{st.kind}`) then
							leaveGarrison(e)
						else
							enterGarrison(st, e)
						end
					elseif not e.path then
						leaveGarrison(e)
					end
				end
			end
		end
		for _, st in settlements do
			for i = #st.garrison, 1, -1 do
				local e = self.entities[st.garrison[i]]
				if not e or not e.alive or e.side ~= st.owner or not e.inside or e.garrisonCity ~= st.id then
					table.remove(st.garrison, i)
					if e and e.alive and e.inside and e.garrisonCity == st.id then
						e.inside, e.garrisonCity = nil, nil
						e.post = cellAt(e.x, e.y)
					end
				end
			end
		end
	end
	-- the game's kQ: everyone inside comes out
	local function emptyGarrison(st: Entity)
		for _, id in table.clone(st.garrison) do
			local e = self.entities[id]
			if e then
				e.inside, e.garrisonCity = nil, nil
				e.post = cellAt(e.x, e.y)
			end
		end
		table.clear(st.garrison)
	end
	-- the game's LQe / Ewe: a hurt unit near a secured settlement of its own (radius + repairReach)
	-- heals cities.repairMen (foot) / repairVehicles x max hp per second, unless it fired, was hit
	-- or is firing within cities.repairQuietSec. A hospital town heals foot units within its radius +
	-- traits.hospital.reach at least traits.hospital.menPerSec.
	local function cityHealing(dt: number)
		local any = false
		for _, st in settlements do
			if st.owner > 0 and #st.garrison > 0 then
				any = true
				break
			end
		end
		if not any then
			return
		end
		local quiet = num("cities.repairQuietSec")
		local reachPad = num("cities.repairReach")
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK and e.hp < e.maxHp and not e.firing
				and self.time - (e.hitAt or -999) >= quiet and self.time - (e.firedAt or -999) >= quiet then
				local mv = text(unitKey(e) .. ".move")
				local rate = 0
				for _, st in settlements do
					if st.owner == e.side and cityStatus(st) == "secured" then
						local l = st.radius + reachPad
						if d2(st.x, st.y, e.x, e.y) <= l * l then
							local c = if mv == "air" or mv == "sea" then 0
								elseif mv == "foot" then num(`cities.repairMen.{st.kind}`)
								else num(`cities.repairVehicles.{st.kind}`)
							rate = math.max(rate, c)
						end
						if mv == "foot" and st.trait == "hospital" and r:flag("cities.traits.on") then
							local h = st.radius + num("cities.traits.hospital.reach")
							if d2(st.x, st.y, e.x, e.y) <= h * h then
								rate = math.max(rate, num("cities.traits.hospital.menPerSec"))
							end
						end
					end
				end
				if rate > 0 then
					e.hp = math.min(e.maxHp, e.hp + e.maxHp * rate * dt)
				end
			end
		end
	end

	---------------------------------------------------------------- settlements (the game's RQe)

	-- Capture weight is the rigs' (strengthNear over the settlement radius, pace max(rigs.minPace,
	-- min(1, weight / rigs.need))). Neutral: one pressing side gains progress / cities.captureSec.<kind>
	-- (a different side first wears the old progress down); with nobody there progress decays at
	-- cities.decayPerSec. Held: enemies alone in it wear its hold down neutraliseMult times as fast,
	-- and at 0 it turns neutral with their capture started; with no enemies the hold recovers at
	-- decayPerSec. The owner's own units there stop neutralising.
	-- A garrison (orderGarrison) blocks neutralising. Garrisons: up to cities.garrisonFull.<kind>
	-- infantry / AT inside (occupied 0, fortified, secured when full). Inside: hits x cities.cover
	-- (securedCover once secured) instead of terrain cover; secured adds securedFire x dps and
	-- rooftopRange; the settlement sees max(cities.sight, the garrison's sight); a secured one heals
	-- nearby own units and widens its owner's building territory (paintBonus, max paintBonusMax).
	-- Discounts: secured settlements cut unit prices (cities.discount.<kind>, max discountMax).
	-- Traits (towns and cities, assigned at the start, work while secured): hospital heals foot units
	-- nearby, rail speeds own trucks within rail.reach, factory cuts vehicle prices.
	-- Capital: holding it secured shows all of your territory (surveillance); its holder gets the
	-- paratroopers and bomb truck powers (see air drops below).
	-- Integrity: artillery and mortar shells landing in a settlement (on units or buildings there) take
	-- damage x settlements.collateral off it; at 0 it lies in ruins until it mends (rebuild.quietSec
	-- without hits, full over rebuild.fullSec, standing again at standShare). Ruins only change the look
	-- in the slice (the game's refineries, dams and events that read them are not in the slice).
	-- Workforce: secured settlements speed all training by cities.workforce.<kind> (max workforceMax).
	-- Forward training (queueForward): a held, secured town or city trains cities.forward.trains
	-- (infantry, AT) itself; the queue waits while it is not secured and is refunded if it is lost.
	-- A secured radio town sweeps cities.traits.radio.radar for radar contacts (radarsOf); a secured
	-- airfield town calls air drops (callAirfield, below).
	local function settlementsTick(dt: number)
		local minPace, need = num("rigs.minPace"), math.max(0.1, num("rigs.need"))
		garrisonTick()
		for _, st in settlements do
			if st.owner > 0 and not alive(st.owner) then
				table.clear(st.garrison)
				st.owner, st.hold, st.capture, st.takenAt = 0, 0, nil, self.time
			end
			local weights = strengthNear(st.x, st.y, st.radius)
			local sides = {}
			for side in weights do
				if alive(side) then
					table.insert(sides, side)
				end
			end
			table.sort(sides)
			local c = math.max(0.1, num(`cities.captureSec.{st.kind}`))
			local function h(side: number): number
				return math.max(minPace, math.min(1, (weights[side] or 0) / need))
			end
			if st.owner <= 0 then
				local f = if #sides == 1 then sides[1] else -1 -- no alliances in the slice
				if f > 0 then
					if st.capture and st.capture.by ~= f then
						st.capture.progress -= dt * h(f) / c
						if st.capture.progress <= 0 then
							st.capture = nil
						end
					end
					if st.capture then
						if st.capture.by == f then
							st.capture.progress = math.min(1, st.capture.progress + dt * h(f) / c)
							if st.capture.progress >= 1 then
								emptyGarrison(st)
								st.owner, st.capture, st.hold, st.takenAt = f, nil, 1, self.time
								event({ type = "cityTaken", id = st.id, side = f })
							end
						end
					else
						st.capture = { by = f, progress = 0 }
						event({ type = "cityCaptureStarted", id = st.id, side = f })
					end
				elseif st.capture and #sides == 0 then
					st.capture.progress -= num("cities.decayPerSec") * dt
					if st.capture.progress <= 0 then
						st.capture = nil
					end
				end
			else
				st.capture = nil
				local foes = {}
				for _, side in sides do
					if side ~= st.owner and canAttack(side, st.owner) then
						table.insert(foes, side)
					end
				end
				if #foes == 0 then
					if st.hold < 1 then
						st.hold = math.min(1, st.hold + num("cities.decayPerSec") * dt)
					end
				elseif #st.garrison > 0 or #foes ~= #sides or #foes > 1 then
					-- a garrison, the owner's units, or several enemies: under attack, no progress
					if self.time - st.warnedAt > num("cities.noticeSec") then
						st.warnedAt = self.time
						event({ type = "cityUnderAttack", id = st.id, side = st.owner })
					end
				else
					local p = foes[1]
					st.hold -= dt * h(p) * num("cities.neutraliseMult") / c
					if st.hold <= 0 then
						emptyGarrison(st)
						local prev = st.owner
						st.owner, st.hold, st.takenAt, st.capture = 0, 0, self.time, { by = p, progress = 0 }
						event({ type = "cityLost", id = st.id, side = prev, by = p })
					end
				end
			end
		end
	end

	---------------------------------------------------------------- trucks

	local function sendHome(t: Entity, rig: Entity?, hq: Entity)
		t.state, t.queue, t.timer = "home", nil, 0
		t.stopped, t.waiting, t.convoySpeed = nil, 0, 0
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
		t.stopped, t.waiting, t.convoySpeed = nil, 0, 0
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

	-- the game's convoy driving (kme / wUe / gUe / SZe / MZe), on the slice's cell-centre paths
	local function stopShort(): number
		-- convoys.stopShortCells is not scaled in the match data (like movement.shareCells)
		return num("convoys.stopShortCells") * num("match.cellScale")
	end
	-- a path cell a truck can no longer use: a road that was cut, or ground that is no longer
	-- passable (a dropped bridge); building yards are left to the route search
	local function brokenOn(path: { number }, from: number): number?
		for i = math.max(1, from), #path do
			local c = path[i]
			if (roads.wasRoad(c) and not roads.isRoad(c)) or (not roads.passable(c) and roads.buildingAt(c) < 0) then
				return i
			end
		end
		return nil
	end
	-- distance along the path from the truck to the centre of path[i]
	local function alongTo(t: Entity, path: { number }, i: number): number
		local x, y, d = t.x, t.y, 0
		for k = t.pathIndex, math.min(i, #path) do
			local cx, cy = centre(path[k])
			d += math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
			x, y = cx, cy
		end
		return d
	end
	-- the game's hostileNear: an armed enemy ground unit within r
	local function hostileNear(side: number, x: number, y: number, r: number): boolean
		for _, o in unitsNear(x, y, r) do
			if o.alive and o.kind ~= TRUCK and canAttack(side, o.side) and o.class ~= "air"
				and numOr(`units.{o.kind}.dps`, 0) > 0 and text(`units.{o.kind}.move`) ~= "sea"
				and (o.x - x) ^ 2 + (o.y - y) ^ 2 <= r * r then
				return true
			end
		end
		return false
	end
	self.hostileNear = hostileNear
	-- the game's MZe: the first path index within convoys.lookAhead with armed enemies near it
	-- (every other cell, and the last)
	local function hostileAhead(t: Entity, path: { number }): number?
		local look, reach = num("convoys.lookAhead"), num("convoys.enemyReach")
		local d, x, y = 0, t.x, t.y
		for i = t.pathIndex, #path do
			if d > look then
				break
			end
			local cx, cy = centre(path[i])
			d += math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
			x, y = cx, cy
			-- the game's path is 0-based: it checks even indices
			if ((i - 1) % 2 == 0 or i == #path) and hostileNear(t.side, cx, cy, reach) then
				return i
			end
		end
		return nil
	end
	-- the game's SZe: on a road, the speed that keeps convoys.spacingCells behind the own truck
	-- ahead (same way within spacingDeg, at most half a spacing to the side); also whether that
	-- truck is stopped
	local function convoyLeader(t: Entity): (number, boolean)
		local s = num("convoys.spacingCells")
		if s <= 0 then
			return math.huge, false
		end
		local c = cellAt(t.x, t.y)
		if c < 0 or not roads.isRoad(c) then
			return math.huge, false
		end
		local hd = t.heading or 0
		local cx, cy = math.cos(hd), math.sin(hd)
		local cosDeg = math.cos(math.rad(num("convoys.spacingDeg")))
		local best, bestSpeed, held = math.huge, 0, false
		for _, m in trafficLists() do
			if m ~= t and m.alive and m.kind == TRUCK and m.side == t.side then
				local dx, dy = m.x - t.x, m.y - t.y
				if dx * dx + dy * dy < 4 * s * s then
					local v = dx * cx + dy * cy
					if v > 0 and v < math.min(best, s * 2) and math.abs(-dx * cy + dy * cx) <= s * 0.5
						and math.cos((m.heading or hd) - hd) >= cosDeg then
						local mc = cellAt(m.x, m.y)
						local merging = v < s * num("convoys.mergeShare") and (m.convoySpeed or 0) < 0.001 and not m.stopped and m.id > t.id
						if mc >= 0 and roads.isRoad(mc) and not merging then
							best, bestSpeed, held = v, m.convoySpeed or 0, m.stopped ~= nil
						end
					end
				end
			end
		end
		if best == math.huge then
			return math.huge, false
		end
		return math.max(0, bestSpeed + (best - s) * num("movement.columnCatchUp")), held
	end
	-- the game's gUe cruise for the leg into path[i]: truck speed, x offRoadShare off road, x
	-- bridgeShare over impassable ground, x townShare in town; x bendShare in a bend
	-- (APPROX: the bend uses the turn at the next cell, not the game's bendCells window)
	local function legCruise(path: { number }, i: number, fromX: number, fromY: number): number
		local c = path[i]
		local v = num("convoys.speed")
		if not roads.isRoad(c) then
			v *= num("convoys.offRoadShare")
		else
			local tName = map.terrainAt(c)
			if tName and not terrainPassable(tName) then
				v *= num("convoys.bridgeShare")
			elseif map.urbanAt and map.urbanAt(c) then
				v *= num("convoys.townShare")
			end
		end
		local nxt = path[i + 1]
		if nxt then
			local ax, ay = centre(c)
			local bx, by = centre(nxt)
			local ux, uy, wx, wy = ax - fromX, ay - fromY, bx - ax, by - ay
			local m = math.sqrt(ux * ux + uy * uy) * math.sqrt(wx * wx + wy * wy)
			if m > 0 then
				local ang = math.acos(math.clamp((ux * wx + uy * wy) / m, -1, 1))
				local free = math.rad(num("convoys.bendFreeDeg"))
				local k = math.clamp((ang - free) / math.max(1e-6, math.pi / 2 - free), 0, 1)
				v *= 1 - (1 - num("convoys.bendShare")) * k
			end
		end
		return v
	end
	self.truckCruise = legCruise
	-- the game's wUe speed profile: pull away over pullAwaySec, brake to the next leg's cruise
	-- and to a stop point over brakeSec, crawl at crawlShare when nothing holds it
	local function driveTruck(t: Entity, path: { number }, dt: number, stopAt: number, limit: number)
		local u = t.convoySpeed or 0
		if t.pathIndex > #path then
			t.convoySpeed = 0
			return
		end
		local i = t.pathIndex
		local tx, ty = centre(path[i])
		local cruise = legCruise(path, i, t.x, t.y)
		local y = cruise / math.max(0.001, num("convoys.brakeSec"))
		local toNext = math.sqrt((tx - t.x) ^ 2 + (ty - t.y) ^ 2)
		local nextCap = if path[i + 1] then legCruise(path, i + 1, tx, ty) else 0
		local w = math.min(cruise, math.sqrt(nextCap * nextCap + 2 * y * toNext))
		local stopping = stopAt < math.huge
		w = math.min(w, limit)
		if stopping then
			w = math.min(w, if stopAt > 0 then math.sqrt(2 * y * stopAt) else math.max(0, u - 2 * y * dt))
		end
		if u < w then
			u = math.min(w, u + cruise / math.max(0.001, num("convoys.pullAwaySec")) * dt)
		else
			u = if stopping then w else math.max(w, u - 2 * y * dt)
		end
		if not stopping then
			u = math.max(u, math.min(cruise * num("convoys.crawlShare"), limit))
		end
		t.convoySpeed = u
		local stepLen = u * dt
		if stopping then
			stepLen = math.min(stepLen, math.max(0, stopAt))
		end
		while stepLen > 0 and t.pathIndex <= #path do
			local px, py = centre(path[t.pathIndex])
			local dx, dy = px - t.x, py - t.y
			local d = math.sqrt(dx * dx + dy * dy)
			if d > 1e-6 then
				t.heading = math.atan2(dy, dx)
			end
			if d <= stepLen then
				t.x, t.y = px, py
				stepLen -= d
				wearRoad(path[t.pathIndex], num("roads.wear.truck")) -- the game's $We
				t.pathIndex += 1
			else
				t.x += dx / d * stepLen
				t.y += dy / d * stepLen
				stepLen = 0
			end
			t.moved = true
		end
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
					t.convoySpeed = 0
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
					t.convoySpeed = 0
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
				-- driving along the path: cell centre to cell centre (APPROX: the game smooths corners
				-- into curves, mUe/QO, and snaps to the road's drawn line)
				local path = t.path
				local truckSpeed = num("convoys.speed")
				local c = cellAt(t.x, t.y)
				-- the game's NWe: road class x wear x traffic, 1 off road
				local pace = 1
				t.jam = nil
				if roads.isRoad(c) then
					pace = num(`roads.classes.{Roads.CLASS_NAME[roads.classAt(c)]}.truck`) * (1 - wearSlow(c))
					if truckJammed(t) then
						pace *= num("traffic.truckShare")
						t.jam = true
					end
				end
				-- the game's kme checks: every 10 ticks (every tick while waiting) look for a cut on
				-- the way, else for armed enemies ahead (MZe)
				local stopAt = math.huge -- distance along the path it may still drive (the game's w)
				local checkNow = (t.waiting or 0) > 0 or #path == 0 or t.reroute or (self.ticks + t.id) % 10 == 0
				if checkNow then
					local broken = if t.reroute then (brokenOn(path, t.pathIndex) or t.pathIndex) else brokenOn(path, t.pathIndex)
					local ahead = if broken then nil else hostileAhead(t, path)
					if broken then
						local fixed = false
						if t.reroute or self.time >= (t.retryAt or -math.huge) then
							local goal = if t.state == "out" and rig then rig.cell else hq.cell
							local p2 = roads.search(c, goal, roads.truckCostFn(c, goal), { minCost = 1, fourWay = true })
							if p2 and #p2 > 0 and not brokenOn(p2, 1) then
								t.path, t.pathIndex, t.waiting = p2, 1, 0
								path = p2
								fixed = true
							else
								t.retryAt = self.time + 2 -- the game's retryAt + 2 s
							end
						end
						t.reroute = nil
						if fixed then
							t.stopped = nil
						else
							t.stopped = "cut"
							local was = t.waiting or 0
							t.waiting = was + dt * (if was > 0 then 1 else 10)
							if was < num("convoys.waitSec") and t.waiting >= num("convoys.waitSec") then
								event({ type = "convoyStranded", id = t.id, side = t.side, x = t.x, y = t.y, rig = t.from })
							end
							stopAt = alongTo(t, path, broken) - stopShort()
						end
					elseif ahead then
						if (t.waiting or 0) == 0 then
							event({ type = "convoyHeld", id = t.id, side = t.side, x = t.x, y = t.y, rig = t.from })
						end
						t.stopped = "enemy"
						t.waiting = (t.waiting or 0) + dt * (if (t.waiting or 0) > 0 then 1 else 10)
						stopAt = alongTo(t, path, ahead) - stopShort()
					else
						t.waiting, t.stopped = 0, nil
					end
				elseif t.stopped then
					stopAt = -math.huge
				end
				-- spacing behind the truck ahead, and the stall creep (the game's SZe / stallSec)
				local held = false
				local limit
				limit, held = convoyLeader(t)
				local creep = truckSpeed * num("convoys.stallCreepShare")
				if stopAt == math.huge and limit < creep and not held then
					t.convoyStall = (t.convoyStall or 0) + dt
					if t.convoyStall >= num("convoys.stallSec") then
						limit = creep
					end
				else
					t.convoyStall = nil
				end
				limit = math.min(limit, truckSpeed * num("trucks.kinds.light.paceShare") * pace * railPace(t.side, t.x, t.y))
				driveTruck(t, path, dt, stopAt, limit)
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

	---------------------------------------------------------------- air drops and the capital's powers
	local airTick: (dt: number) -> ()
	do
		local A: any = {}

		-- The game's paradrops ($X / G_ / KGe): a transport flies in from the map edge and drops sticks
		-- along its line; each lands drop.chuteSec after leaving the plane. Called by a secured airfield
		-- town (callAirfield: cities.traits.airfield.squads rifle squads within reach, then cooldownSec)
		-- or by the capital (callParatroopers: capital.paraCount paratroopers, then cooldownSec.para).
		-- The capital also sends a bomb truck (deployDemo, cooldownSec.demo) that blows up at an enemy
		-- building or the unit it was sent at (the game's GGe / XGe / pq).
		self.paradrops = {} :: { any }
		local nextDropId = 1
		function A.capitalOf(): Entity?
			for _, st in settlements do
				if st.kind == "capital" then
					return st
				end
			end
			return nil
		end
		self.capitalOf = A.capitalOf
		-- the game's AD: how many of n more units the side may still field (match.unitCap)
		function A.unitRoom(side: number, n: number): number
			return math.max(0, math.min(math.floor(n + 0.5), num("match.unitCap") - unitsAndQueued(side)))
		end
		-- the game's gS: a drop point away from the map edge, on passable ground (not water)
		function A.dropProblem(x: number, y: number): string?
			local e = num("capital.paraEdgeCells")
			if x < e or y < e or x > W - e or y > H - e then
				return "terrain"
			end
			local c = cellAt(x, y)
			if c < 0 or not roads.passable(c) then
				return "terrain"
			end
			local t = map.terrainAt(c)
			if t == "deep" or t == "shallow" then
				return "terrain"
			end
			return nil
		end
		self.dropProblem = A.dropProblem
		-- the game's jie: distance from (x, y) to the map edge going along angle a
		function A.edgeDist(x: number, y: number, a: number): number
			local c, s = math.cos(a), math.sin(a)
			local rx = if c > 1e-6 then (W - x) / c elseif c < -1e-6 then -x / c else math.huge
			local ry = if s > 1e-6 then (H - y) / s elseif s < -1e-6 then -y / s else math.huge
			return math.max(0, math.min(rx, ry))
		end
		function A.openSpot(x: number, y: number): boolean -- the game's fI
			local c = cellAt(x, y)
			return c >= 0 and roads.passable(c) and roads.buildingAt(c) < 0
		end
		function A.freeSpotAt(x: number, y: number): (number, number) -- the game's freeSpotAt
			if A.openSpot(x, y) then
				return x, y
			end
			return freePointNear(math.clamp(x, 0, W - 1e-6), math.clamp(y, 0, H - 1e-6))
		end
		self.freeSpotAt = A.freeSpotAt
		-- the game's G_: the plane picks, of 16 headings from a random start, the one whose run in from the
		-- edge is closest to drop.approachShare of the map's short side; sticks leave it gap apart
		-- (centred on the point), each blown up to 0.6 x cellScale aside
		function A.planeFor(side: number, x: number, y: number, loads: { string }, flySec: number, gap: number): any
			local want = math.min(W, H) * num("drop.approachShare")
			local bestH, bestD = 0, -1
			local f = rand() * math.pi * 2
			local function score(d: number): number
				return if d >= want then d - want else (want - d) * 4
			end
			for i = 0, 15 do
				local a = f + i / 16 * math.pi * 2
				local d = A.edgeDist(x, y, a)
				if bestD < 0 or score(d) < score(bestD) then
					bestH, bestD = a, d
				end
			end
			local heading = bestH + math.pi
			local run = bestD + 4
			local speed = run / flySec
			local fromX, fromY = x - math.cos(heading) * run, y - math.sin(heading) * run
			local overT = self.time + flySec
			local goneT = overT + (A.edgeDist(x, y, heading) + 6) / speed
			local out = {}
			local spin = rand() * math.pi * 2
			local chute = num("drop.chuteSec")
			for i, kind in loads do
				local m = i - 1
				local along = (m - (#loads - 1) / 2) * gap
				local side_ = (if m % 2 == 1 then 1 else -1) * gap * 0.35
				local ax = x + math.cos(heading) * along - math.sin(heading) * side_
				local ay = y + math.sin(heading) * along + math.cos(heading) * side_
				local h = 0.6 * num("match.cellScale") * (0.6 + rand() * 0.8)
				local px, py = ax + math.cos(spin) * h, ay + math.sin(spin) * h
				if not A.openSpot(px, py) then
					px, py = ax, ay
					if not A.openSpot(px, py) then
						px, py = A.freeSpotAt(x, y)
					end
				end
				local outT = overT + along / speed
				table.insert(out, { kind = kind, x = px, y = py, outT = outT, landT = outT + chute })
			end
			return { side = side, fromX = fromX, fromY = fromY, heading = heading, speed = speed, startT = self.time, overT = overT, goneT = goneT, loads = out }
		end
		self.planeFor = A.planeFor
		function A.launchDrop(side: number, x: number, y: number, loads: { string }, airfield: number?): number
			local plane = A.planeFor(side, x, y, loads, num("capital.paraFlySec"), num("capital.paraStickGap"))
			local id = nextDropId
			nextDropId += 1
			table.insert(self.paradrops, { id = id, side = side, x = x, y = y, plane = plane, landed = 0, airfield = airfield })
			event({ type = if airfield then "airfieldAway" else "paraAway", id = id, side = side, x = x, y = y, n = #loads,
				sec = math.ceil(num("capital.paraFlySec") + num("drop.chuteSec")), city = airfield })
			return id
		end
		-- the game's KGe: land each stick at its time, then forget the drop once the plane is gone
		function A.paradropTick()
			if #self.paradrops == 0 then
				return
			end
			for _, d in self.paradrops do
				local loads = d.plane.loads
				while d.landed < #loads and self.time >= loads[d.landed + 1].landT do
					d.landed += 1
					local a = loads[d.landed]
					if alive(d.side) then
						local x, y = A.freeSpotAt(a.x, a.y)
						local u = self.spawnUnit(a.kind, d.side, x, y)
						if d.landed == #loads then
							event({ type = if d.airfield then "airfieldLanded" else "paraLanded", id = u.id, side = d.side, x = d.x, y = d.y, n = #loads })
						end
					end
				end
			end
			local linger = num("capital.paraLingerSec")
			local keep = {}
			for _, d in self.paradrops do
				local last = d.plane.loads[#d.plane.loads]
				if d.landed < #d.plane.loads or self.time <= math.max(d.plane.goneT, (if last then last.landT else 0) + linger) then
					table.insert(keep, d)
				end
			end
			self.paradrops = keep
		end

		-- the game's TD / EX: can this side call the airfield town st now, onto (x, y)?
		function A.airfieldProblem(side: number, st: Entity?, x: number?, y: number?): string?
			if not st or st.trait ~= "airfield" or not r:flag("cities.traits.on") then
				return "blocked"
			end
			if st.owner ~= side or side <= 0 then
				return "notHeld"
			end
			if cityStatus(st) ~= "secured" then
				return "notSecured"
			end
			if not alive(side) then
				return "blocked"
			end
			if (st.airfieldReady or 0) > self.time then
				return "cooldown"
			end
			if x == nil or y == nil then
				return nil
			end
			if A.unitRoom(side, 1) <= 0 then
				return "unitCap"
			end
			local reach = num("cities.traits.airfield.reach")
			if (x - st.x) ^ 2 + (y - st.y) ^ 2 > reach * reach then
				return "outOfRange"
			end
			return A.dropProblem(x, y)
		end
		self.airfieldProblem = A.airfieldProblem
		-- the game's zpe: rifle squads from a secured airfield town
		function self.callAirfield(side: number, cityId: number, x: number, y: number): (boolean, any)
			local st = settlements[cityId]
			local why = A.airfieldProblem(side, st, x, y)
			if why then
				return false, why
			end
			local loads = table.create(math.max(1, A.unitRoom(side, num("cities.traits.airfield.squads"))), "infantry")
			local id = A.launchDrop(side, x, y, loads, cityId)
			st.airfieldReady = self.time + num("cities.traits.airfield.cooldownSec")
			return true, id
		end
		-- the game's Dpe / UGe: the capital's powers work for whoever holds it; each has its own cooldown
		function A.powerLeft(side: number, power: string): number
			local s = self.sides[side]
			local at = s and s.capitalReady and s.capitalReady[power] or 0
			return math.max(0, at - self.time)
		end
		function A.powerProblem(side: number, power: string): string?
			local s = self.sides[side]
			if not s or s.lost then
				return "blocked"
			end
			local cap = A.capitalOf()
			if not cap or cap.owner ~= side then
				return "noCapital"
			end
			return if A.powerLeft(side, power) > 0 then "cooldown" else nil
		end
		function self.capitalPower(side: number, power: string): (string, number)
			local left = A.powerLeft(side, power)
			local cap = A.capitalOf()
			if not cap then
				return "none", left
			end
			if cap.owner ~= side or side <= 0 then
				return "locked", left
			end
			return if left > 0 then "cooldown" else "ready", left
		end
		function A.powerUsed(side: number, power: string)
			local s = self.sides[side]
			s.capitalReady = s.capitalReady or {}
			s.capitalReady[power] = self.time + num(`capital.cooldownSec.{power}`)
		end
		-- the game's qGe / RX: paratroopers from the capital
		function self.callParatroopers(side: number, x: number, y: number): (boolean, any)
			local why = A.powerProblem(side, "para") or (if A.unitRoom(side, 1) <= 0 then "unitCap" else nil) or A.dropProblem(x, y)
			if why then
				return false, why
			end
			local loads = table.create(math.max(1, A.unitRoom(side, num("capital.paraCount"))), "para")
			local id = A.launchDrop(side, x, y, loads, nil)
			A.powerUsed(side, "para")
			return true, id
		end
		function A.isDemo(e: Entity): boolean
			local ab = r.data[`units.{e.kind}.abilities`] :: { string }?
			return ab ~= nil and table.find(ab, "demolition") ~= nil
		end
		self.isDemo = A.isDemo
		-- the game's JGe: an enemy building within capital.demoAimCells of the point
		function A.demoBuildingNear(side: number, x: number, y: number): Entity?
			for _, st in self.list do
				if st.alive and isStructure(st) and st.kind ~= "rig" and canAttack(side, st.side) then
					local cx, cy = centre(st.cell)
					if math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2) - footprintOf(st.kind) <= num("capital.demoAimCells") then
						return st
					end
				end
			end
			return nil
		end
		-- the game's QGe: the nearest enemy ground unit within capital.demoAimCells of the point
		function A.demoUnitNear(side: number, x: number, y: number): Entity?
			local best, bestD = nil, num("capital.demoAimCells")
			for _, u in self.list do
				if u.alive and u.cat == "unit" and u.kind ~= TRUCK and not u.inside and canAttack(side, u.side) and u.class ~= "air" then
					local d = math.sqrt((u.x - x) ^ 2 + (u.y - y) ^ 2)
					if d <= bestD then
						best, bestD = u, d
					end
				end
			end
			return best
		end
		-- the game's GGe: a bomb truck leaves the capital's edge toward the point; it is sent at the unit
		-- there unless an enemy building is near the point
		function self.deployDemo(side: number, x: number, y: number): (boolean, any)
			local why = A.powerProblem(side, "demo")
			if why then
				return false, why
			end
			local cap = A.capitalOf() :: Entity
			local d = math.sqrt((x - cap.x) ^ 2 + (y - cap.y) ^ 2)
			local k = if d > 1e-6 then math.min(d, cap.radius) / d else 0
			local sx, sy = A.freeSpotAt(cap.x + (x - cap.x) * k, cap.y + (y - cap.y) * k)
			local u = self.spawnUnit("demo", side, sx, sy)
			A.powerUsed(side, "demo")
			local target = if A.demoBuildingNear(side, x, y) then nil else A.demoUnitNear(side, x, y)
			if target then
				u.attackId = target.id
			else
				self.orderMove(side, { u.id }, x, y)
			end
			event({ type = "demoOut", id = u.id, side = side, x = sx, y = sy, city = cap.id })
			return true, u.id
		end
		-- the game's pq: the blast. Buildings within demoBlastCells (edge distance) take
		-- demoStructureDamage x (1 - half the way past demoReachCells); units within demoLethalCells die,
		-- beyond it they take demoUnitDamage x demoVs, falling to demoEdgeShare at the edge, x cover (x
		-- bunching for foot units); trucks take demoUnitDamage x demoVs.armour; the nearest road takes
		-- demoStructureDamage x demoRoadShare of strike damage. APPROX: rigs can't be damaged in the slice.
		function A.demoBlast(e: Entity)
			if not e.alive then
				return
			end
			local n = math.max(0.01, num("capital.demoBlastCells"))
			local lethal = math.min(n, math.max(0, num("capital.demoLethalCells")))
			local x, y, by = e.x, e.y, e.side
			local function falloff(u: number): number
				return 1 - 0.5 * math.clamp(u / n, 0, 1)
			end
			local function edge(u: number): number
				return 1 - (1 - num("capital.demoEdgeShare")) * math.clamp((u - lethal) / math.max(1e-6, n - lethal), 0, 1)
			end
			local hitName: string? = nil
			for _, st in self.list do
				if st.alive and isStructure(st) and st.kind ~= "rig" and canAttack(by, st.side) then
					local cx, cy = centre(st.cell)
					local f = math.max(math.abs(cx - x), math.abs(cy - y)) - (footprintOf(st.kind) + 0.5)
					if f <= n then
						hitName = hitName or st.kind
						hitStructure(by, st, num("capital.demoStructureDamage") * num("capital.demoVs.structure") * falloff(f - num("capital.demoReachCells")))
					end
				end
			end
			local bunch = bunchFactor(by, x, y)
			for _, u in self.list do
				if u ~= e and u.alive and u.cat == "unit" and canAttack(by, u.side) then
					local vs = numOr(`capital.demoVs.{u.class}`, 0)
					local p = math.sqrt((u.x - x) ^ 2 + (u.y - y) ^ 2)
					if vs > 0 and p <= n then
						if u.kind == TRUCK then
							hitTruck(u, num("capital.demoUnitDamage") * num("capital.demoVs.armour"), "", 1, by)
						else
							u.hitAt, u.hitBy = self.time, by
							if p <= lethal then
								u.hp = math.min(u.hp, 0)
							else
								local cover = if u.inside then insideCover(u) else 1 - coverAt(cellAt(u.x, u.y))
								local foot = text(unitKey(u) .. ".move") == "foot"
								self.vetHit(u, num("capital.demoUnitDamage") * vs * edge(p) * cover * (if foot then bunch else 1))
							end
							killIfDead(u, by)
						end
					end
				end
			end
			roadBlast(x, y, num("capital.demoStructureDamage") * num("capital.demoRoadShare"), by)
			event({ type = "demoBlast", id = e.id, side = by, x = x, y = y, target = hitName })
			e.hp, e.alive = 0, false
			event({ type = "destroyed", id = e.id, kind = e.kind, side = e.side, by = by })
		end
		-- the game's ZGe: blow up the side's bomb trucks among ids now
		function self.detonate(side: number, ids: { number }): (boolean, any)
			local n = 0
			for _, id in ids do
				local e = self.entities[id]
				if e and e.alive and e.side == side and A.isDemo(e) then
					A.demoBlast(e)
					n += 1
				end
			end
			if n == 0 then
				return false, "noDemo"
			end
			return true, n
		end
		-- the game's YGe / XGe: a bomb truck blows at an enemy building within demoReachCells (while
		-- driving, only one near where it is going), or next to the unit it was sent at
		-- (combat.demoUnitReachCells x cellScale). It has no gun, so it chases its unit itself.
		function A.demoTick()
			local unitReach = num("combat.demoUnitReachCells") * num("match.cellScale")
			for _, e in self.list do
				if e.alive and e.cat == "unit" and not e.inside and A.isDemo(e) then
					local goal = if e.path and e.pathIndex and e.pathIndex <= #e.path then e.path[#e.path] else nil
					local gx, gy
					if goal then
						gx, gy = centre(goal)
					end
					local hit = nil
					local bestF = math.huge
					for _, st in self.list do
						if st.alive and isStructure(st) and st.kind ~= "rig" and canAttack(e.side, st.side) then
							local cx, cy = centre(st.cell)
							local foot = footprintOf(st.kind)
							local f = math.max(math.abs(cx - e.x), math.abs(cy - e.y)) - (foot + 0.5)
							if f <= num("capital.demoReachCells") and not (gx and math.sqrt((cx - gx) ^ 2 + (cy - gy) ^ 2) - foot > num("capital.demoAimCells")) and f < bestF then
								hit, bestF = st, f
							end
						end
					end
					if hit then
						A.demoBlast(e)
					elseif e.attackId then
						local t = self.entities[e.attackId]
						if not t or not t.alive then
							e.attackId = nil
						elseif math.sqrt(d2(e.x, e.y, t.x, t.y)) <= unitReach then
							A.demoBlast(e)
						elseif (e.id + self.ticks) % 10 == 0 then
							local c = cellAt(t.x, t.y)
							if c >= 0 and (not e.goalCell or e.goalCell ~= c) then
								planTo(e, c, t.x, t.y)
							end
						end
					end
				end
			end
		end
		-- the game's jGe ready notices: the capital's powers and airfield towns coming off cooldown
		function airTick(dt: number)
			A.paradropTick()
			A.demoTick()
			local cap = A.capitalOf()
			if cap and cap.owner > 0 then
				local s = self.sides[cap.owner]
				if s and not s.lost and s.capitalReady then
					for _, p in { "para", "demo" } do
						local at = s.capitalReady[p]
						if at and at > self.time - dt and at <= self.time then
							event({ type = "capitalPowerReady", side = cap.owner, power = p })
						end
					end
				end
			end
			for _, st in settlements do
				local at = st.airfieldReady
				if at and st.trait == "airfield" and at > self.time - dt and at <= self.time and traitActive(st) then
					event({ type = "airfieldReady", side = st.owner, city = st.id })
				end
			end
		end
	end

	---------------------------------------------------------------- recon drone and SAM sites

	-- The game's recon drone (NJe / WJe / mwe): bought once for intel.reconCost oil, it flies from the
	-- finished HQ to a point at intel.droneSpeed, circles it at droneOrbitShare of its scan radius for
	-- intel.reconSec while showing scoutReconRadius x droneVsScout round the point, then flies home and
	-- refuels for droneRefuelSec. Shot down, it is gone; a new one can be bought after droneReplaceSec.
	-- SAM sites (UJe / lA / sge / rje) fire a missile at an enemy drone within range every reloadSec;
	-- the missile flies at samMissile.speed and downs the drone if it gets within hitCells before
	-- maxSec. SAMs don't shoot at ground targets.
	self.drones = {} :: { any }
	self.samMissiles = {} :: { any }
	local droneTick: (dt: number) -> ()
	do
		local D: any = {}
		local nextDrone, nextMissile = 1, 1
		local samShotAt: { [number]: number } = self.samShotAt
		function D.droneOf(side: number): any
			for _, d in self.drones do
				if d.alive and d.side == side then
					return d
				end
			end
			return nil
		end
		function D.hqFor(side: number): Entity?
			local hq = hqOf(side)
			return if hq and hq.built >= 1 then hq else nil
		end
		function self.droneScanRadius(): number
			return num("intel.scoutReconRadius") * num("intel.droneVsScout")
		end
		-- the game's mwe: out, refuel, ready, replace or buy
		function self.droneState(side: number): (string, number)
			local s = self.sides[side]
			if not s then
				return "replace", 0
			end
			if D.droneOf(side) then
				return "out", 0
			end
			local left = math.max(0, (s.reconReadyAt or 0) - self.time)
			if s.droneOwned then
				return if left > 0 then "refuel" else "ready", left
			end
			return if left > 0 then "replace" else "buy", left
		end
		function self.launchDrone(side: number, x: number, y: number): (boolean, any)
			local s = self.sides[side]
			if not s or s.lost then
				return false, "blocked"
			end
			local hq = D.hqFor(side)
			if not hq then
				return false, "noHq"
			end
			local state = self.droneState(side)
			if state == "out" then
				return false, "droneOut"
			elseif state == "refuel" then
				return false, "cooldown"
			elseif state == "replace" then
				return false, "replaceCooldown"
			end
			if state == "buy" then
				if s.oil < num("intel.reconCost") then
					return false, "oil"
				end
				s.oil -= num("intel.reconCost")
				s.droneOwned = true
			end
			local hx, hy = centre(hq.cell)
			local d = { id = nextDrone, side = side, x = hx, y = hy, tx = math.clamp(x, 0.5, W - 0.5), ty = math.clamp(y, 0.5, H - 0.5),
				radius = self.droneScanRadius(), phase = "out", scanLeft = num("intel.reconSec"), hp = 1, alive = true }
			nextDrone += 1
			table.insert(self.drones, d)
			event({ type = "droneOut", id = d.id, side = side, x = d.tx, y = d.ty })
			return true, d.id
		end
		function D.orbit(d: any): number -- the game's j1e
			return math.max(1, d.radius * num("intel.droneOrbitShare"))
		end
		-- the game's Z1e: fly toward (tx, ty) until `stop` short of it; true once there
		function D.fly(d: any, dt: number, stop: number): boolean
			local dx, dy = d.tx - d.x, d.ty - d.y
			local r = math.sqrt(dx * dx + dy * dy)
			local left = r - stop
			if left <= 0 then
				return true
			end
			local step = math.min(num("intel.droneSpeed") * dt, left)
			d.x += dx / r * step
			d.y += dy / r * step
			return step >= left
		end
		-- the game's K1e: shot down (or homeless)
		function D.lose(d: any, shot: boolean)
			d.alive, d.hp = false, 0
			local s = self.sides[d.side]
			if s then
				s.droneOwned = false
				s.reconReadyAt = self.time + num("intel.droneReplaceSec")
			end
			event({ type = "droneLost", id = d.id, side = d.side, x = d.x, y = d.y, shot = shot })
		end
		function D.targeted(id: number): boolean -- the game's iA
			for _, m in self.samMissiles do
				if m.alive and m.target == id then
					return true
				end
			end
			return false
		end
		-- the game's UJe / rA / lA: the first SAM in range and reloaded fires at the drone
		function D.samFire(d: any)
			if D.targeted(d.id) then
				return
			end
			for _, st in self.list do
				if st.alive and st.kind == "sam" and st.built >= 1 and canAttack(st.side, d.side) then
					local sx, sy = centre(st.cell)
					local range = num("structures.sam.range")
					if (sx - d.x) ^ 2 + (sy - d.y) ^ 2 <= range * range
						and self.time - (samShotAt[st.id] or -math.huge) >= num("structures.sam.reloadSec") then
						samShotAt[st.id] = self.time
						table.insert(self.samMissiles, { id = nextMissile, side = st.side, site = st.id, x = sx, y = sy, tx = d.x, ty = d.y,
							heading = math.atan2(d.y - sy, d.x - sx), target = d.id, launchedAt = self.time, alive = true })
						nextMissile += 1
						event({ type = "samFired", id = st.id, side = st.side, drone = d.id })
						return
					end
				end
			end
		end
		-- the game's sge: missiles home on their drone; a hit within hitCells downs it
		function D.missilesTick(dt: number)
			local keep = {}
			for _, m in self.samMissiles do
				local tgt = nil
				for _, d in self.drones do
					if d.id == m.target and d.alive and d.hp > 0 then
						tgt = d
					end
				end
				if tgt then
					m.tx, m.ty = tgt.x, tgt.y
				end
				local dx, dy = m.tx - m.x, m.ty - m.y
				local r = math.sqrt(dx * dx + dy * dy)
				local step = num("samMissile.speed") * dt
				if r > 1e-6 then
					m.heading = math.atan2(dy, dx)
				end
				local hit = r <= step + num("samMissile.hitCells")
				local late = self.time - m.launchedAt >= num("samMissile.maxSec")
				if not hit and not late then
					m.x += dx / r * step
					m.y += dy / r * step
					table.insert(keep, m)
				else
					if hit then
						m.x, m.y = m.tx, m.ty
					end
					m.alive = false
					if hit and tgt then
						tgt.hp = 0
						event({ type = "samHit", side = m.side, drone = tgt.id, x = m.x, y = m.y })
					end
				end
			end
			self.samMissiles = keep
		end
		-- the game's WJe
		function droneTick(dt: number)
			D.missilesTick(dt)
			if #self.drones == 0 then
				return
			end
			local keep = {}
			for _, d in self.drones do
				if d.alive and not alive(d.side) then
					d.alive = false
				elseif d.alive and d.hp <= 0 then
					D.lose(d, true)
				elseif d.alive then
					if d.phase == "out" then
						if D.fly(d, dt, D.orbit(d)) then
							d.phase, d.scanLeft = "scan", num("intel.reconSec")
							d.orbitAt = math.atan2(d.y - d.ty, d.x - d.tx)
							event({ type = "droneScanned", id = d.id, side = d.side, x = d.tx, y = d.ty })
						end
					elseif d.phase == "scan" then
						local o = D.orbit(d)
						d.orbitAt = (d.orbitAt or 0) + num("intel.droneSpeed") / o * dt
						d.x, d.y = d.tx + math.cos(d.orbitAt) * o, d.ty + math.sin(d.orbitAt) * o
						d.scanLeft -= dt
						if d.scanLeft <= 0 then
							d.scanLeft, d.phase = 0, "home"
						end
					else
						local hq = D.hqFor(d.side)
						if not hq then
							D.lose(d, false)
						else
							d.tx, d.ty = centre(hq.cell)
							if D.fly(d, dt, 0) then
								d.alive = false
								self.sides[d.side].reconReadyAt = self.time + num("intel.droneRefuelSec")
								event({ type = "droneHome", id = d.id, side = d.side })
							end
						end
					end
					if d.alive then
						D.samFire(d)
					end
				end
				if d.alive then
					table.insert(keep, d)
				end
			end
			self.drones = keep
		end
	end

	---------------------------------------------------------------- production, economy, verdict

	-- the game's updateStructures: construction, repair, then the head of each production queue
	local function production(dt: number)
		for _, st in self.list do
			if st.alive and isStructure(st) then
				if st.built < 1 then
					st.built = math.min(1, st.built + dt / math.max(0.01, st.buildSec or num(`structures.{st.kind}.buildSec`)))
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
						st.queueProgress += dt / buildTime(st.side, item)
						if st.queueProgress >= 1 then
							st.queueProgress = 0
							table.remove(st.queue, 1)
							table.remove(st.queuePaid or {}, 1)
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
		return (1 - st.queueProgress) * buildTime(side, st.queue[1])
	end

	---------------------------------------------------------------- forward training (the game's DX, Upe, Wpe, rZe)

	-- why a settlement cannot queue `item` for `side` now (nil = it can)
	local function forwardProblem(side: number, st: Entity?, item: string): string?
		local trains = r.data["cities.forward.trains"] :: { string }?
		local kinds = r.data["cities.forward.kinds"] :: { string }?
		if not st or not trains or not table.find(trains, item) or not SLICE_UNITS[item] then
			return "blocked"
		end
		if not r:flag("cities.forward.on") or not kinds or not table.find(kinds, st.kind) then
			return "blocked"
		end
		if st.owner ~= side or side <= 0 then
			return "notHeld"
		end
		if cityStatus(st) ~= "secured" then
			return "notSecured"
		end
		if (if st.forward then #st.forward.queue else 0) >= num("production.maxQueue") then
			return "queueFull"
		end
		if unitsAndQueued(side) >= num("match.unitCap") then
			return "unitCap"
		end
		if self.sides[side].oil < unitCost(side, item) then
			return "oil"
		end
		return nil
	end
	self.forwardProblem = forwardProblem
	-- the game's queueForward (Upe): pay now, train in the settlement
	function self.queueForward(side: number, cityId: number, item: string): (boolean, string?)
		local st = settlements[cityId]
		local s = self.sides[side]
		if not s or s.lost or self.winner then
			return false, "blocked"
		end
		local why = forwardProblem(side, st, item)
		if why then
			return false, why
		end
		local cost = unitCost(side, item)
		s.oil -= cost
		local f = st.forward or { owner = side, queue = {}, paid = {}, progress = 0 }
		st.forward = f
		table.insert(f.queue, item)
		table.insert(f.paid, cost)
		return true, nil
	end
	-- the game's Wpe: cancel queue entry `index` (1-based) for a refund of what was paid
	function self.cancelForward(side: number, cityId: number, index: number): (boolean, string?)
		local st = settlements[cityId]
		local f = st and st.forward
		if not st or not f or f.owner ~= side then
			return false, "notOwned"
		end
		if index < 1 or index > #f.queue then
			return false, "blocked"
		end
		table.remove(f.queue, index)
		local paid = table.remove(f.paid, index)
		if index == 1 then
			f.progress = 0
		end
		self.sides[side].oil += paid or 0
		if #f.queue == 0 then
			st.forward = nil
		end
		return true, nil
	end
	-- seconds left on a settlement's head unit
	function self.forwardLeft(cityId: number): number?
		local st = settlements[cityId]
		local f = st and st.forward
		if not f or #f.queue == 0 then
			return nil
		end
		return (1 - f.progress) * buildTime(f.owner, f.queue[1])
	end
	-- the game's rZe: a queue whose settlement changed hands (or whose nation is out) is refunded and
	-- dropped; one whose settlement is not secured waits; the head unit appears radius + 0.5 from the
	-- centre at a random angle (the nearest free spot).
	local function forwardTick(dt: number)
		for _, st in settlements do
			local f = st.forward
			if f then
				local s = self.sides[f.owner]
				if f.owner ~= st.owner or not s or s.lost then
					if s and not s.lost then
						for _, p in f.paid do
							s.oil += p
						end
					end
					st.forward = nil
				elseif #f.queue == 0 then
					st.forward = nil
				elseif forwardActive(st) then
					f.progress += dt / buildTime(f.owner, f.queue[1])
					if f.progress >= 1 then
						f.progress = 0
						table.remove(f.paid, 1)
						local item = table.remove(f.queue, 1) :: string
						local a = rand() * math.pi * 2
						local x, y = st.x + math.cos(a) * (st.radius + 0.5), st.y + math.sin(a) * (st.radius + 0.5)
						local c = cellAt(x, y)
						if c < 0 or not roads.passable(c) then
							x, y = freePointNear(math.clamp(x, 0, W - 1e-6), math.clamp(y, 0, H - 1e-6))
						end
						local u = self.spawnUnit(item, f.owner, x, y)
						event({ type = "forwardReady", id = u.id, side = f.owner, kind = item, city = st.id })
						if #f.queue == 0 then
							st.forward = nil
						end
					end
				end
			end
		end
	end

	-- the game's checkHeadless: a nation without an HQ that may rehouse (an active factory) has
	-- hqLoss.graceSec; without one it is out at once. (The command truck that rebuilds an HQ is not in
	-- the slice, so a headless nation is out when the grace runs out.)
	-- the game's checkHeadless: a side with no HQ and no command truck is out at once unless it has a
	-- working factory (mayRehouse); with one, it has hqLoss.graceSec, not counted while a command truck
	-- is on order
	local function checkHeadless()
		for side, s in self.sides do
			if not s.lost then
				if hqOf(side) or self.truckOf(side) then
					s.headlessSince = nil
				elseif not hasBuilding(side, "factory", true) then
					eliminateRef(side, -1)
				elseif self.hqOnOrder(side) then
					-- waiting on the truck
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

	local seekCover: (Entity, string) -> boolean
	-- the game's holdAtEnemy: an armed unit that would step within movement.enemySpaceCells of an
	-- enemy unit it can hurt, moving towards it, stays where it was (it holds and fights there).
	-- APPROX: unarmed units are not slid round enemies as in the game; they walk on.
	local function holdAtEnemy(e: Entity, n: number, s: number): boolean
		local r = num("movement.enemySpaceCells")
		if r <= 0 or e.inside then
			return false
		end
		local l, c = e.x - n, e.y - s
		if l * l + c * c < 1e-18 then
			return false
		end
		local key = unitKey(e)
		if num(key .. ".dps") <= 0 then
			return false
		end
		for _, b in unitsNear(n + l, s + c, r) do
			if b ~= e and b.alive and not b.inside and b.cat == "unit" and b.kind ~= TRUCK and canAttack(e.side, b.side) and b.class ~= "air"
				and text(unitKey(b) .. ".move") ~= "sea" then
				local x, y = b.x - n, b.y - s
				local m = math.sqrt(x * x + y * y)
				if m >= 1e-6 and (n + l - b.x) ^ 2 + (s + c - b.y) ^ 2 < r * r and l * x / m + c * y / m > 0
					and vsOf(key, b.class) > 0 then
					return true
				end
			end
		end
		return false
	end

	-- the game's seekCover: with an enemy it can hurt within range, an idle foot soldier looks up to
	-- cover.seekCells round it for a free passable cell (no structure, no comrade's cover cell) with at
	-- least cover.minGain more cover than where it stands (best cover, then nearest), that keeps the
	-- nearest such enemy between enemySpaceCells and range x cover.rangeShare away and lies within
	-- leashCells of its post; a route of at most 3 x seekCells cells takes it there and makes it its post.
	-- APPROX: comrades' cover cells are gathered by distance, not the game's bucket squares.
	function seekCover(e: Entity, key: string): boolean
		local a = cellAt(e.x, e.y)
		local seek = num("cover.seekCells")
		if a < 0 or seek <= 0 then
			return false
		end
		local range = num(key .. ".range")
		local reach = math.max(range, seek + num("movement.separationCells"))
		local taken: { [number]: boolean } = {}
		local foe, foeD = nil, range * range
		for _, o in self.list do
			if o ~= e and o.alive and o.cat == "unit" and o.kind ~= TRUCK then
				local g = d2(o.x, o.y, e.x, e.y)
				if o.side == e.side then
					if o.coverCell and g <= reach * reach * 2 then
						taken[o.coverCell] = true
					end
				elseif canAttack(e.side, o.side) and o.class ~= "air" and text(unitKey(o) .. ".move") ~= "sea"
					and vsOf(key, o.class) > 0 and g <= foeD then
					foe, foeD = o, g
				end
			end
		end
		if not foe then
			return false
		end
		local far, near, leash = range * num("cover.rangeShare"), num("movement.enemySpaceCells"), num("movement.leashCells")
		local px, py = centre(e.post or a)
		local ax, ay = a % W, a // W
		local v = math.ceil(seek)
		local best, bestCover, bestA = -1, coverAt(a) + num("cover.minGain") - 1e-9, math.huge
		for dy = -v, v do
			for dx = -v, v do
				local A = dx * dx + dy * dy
				local cx, cy = ax + dx, ay + dy
				if A > 0 and A <= seek * seek and cx >= 0 and cy >= 0 and cx < W and cy < H then
					local o = cy * W + cx
					if roads.passable(o) and not taken[o] then
						local cv = coverAt(o)
						if not (cv < bestCover or (cv == bestCover and A >= bestA)) then
							local tx, ty = cx + 0.5, cy + 0.5
							local B = d2(foe.x, foe.y, tx, ty)
							if B <= far * far and B >= near * near and d2(px, py, tx, ty) <= leash * leash then
								best, bestCover, bestA = o, cv, A
							end
						end
					end
				end
			end
		end
		if best < 0 then
			return false
		end
		local path = pathing.route(a, best, e.kind)
		if not path or #path == 0 or #path > v * 3 then
			return false
		end
		local bx, by = centre(best)
		e.path, e.pathIndex, e.stall, e.stallTries = path, 1, 0, 0
		e.spot, e.target, e.goalCell = { x = bx, y = by }, { x = bx, y = by }, best
		e.still, e.post, e.coverCell, e.chasing = 0, best, best, nil
		return true
	end

	-- the game's idleThink (every 20 ticks per unit, for armed units standing idle): chase the nearest
	-- enemy unit within min(sight, movement.chaseCells + range) whose position is within
	-- movement.leashCells of the unit's post, stopping range x 0.6 cells short; with none, walk back
	-- to the post once more than leashCells / 2 from it. Chasing keeps the unit idle (its post stays).
	-- Before that, every round(cover.seekSec x tickHz) ticks an idle armed foot soldier (not artillery)
	-- may step into better cover (seekCover).
	local function idleThink(e: Entity)
		if e.garrisonCity or text(unitKey(e) .. ".move") == "sea" then
			return
		end
		-- a unit that left its cover cell no longer holds it
		if e.coverCell and e.coverCell ~= cellAt(e.x, e.y) then
			e.coverCell = nil
		end
		local key = unitKey(e)
		local dps = num(key .. ".dps")
		-- APPROX: a unit with no post yet (fresh, or placed by a test) takes the cell it stands on
		local post = e.post or cellAt(e.x, e.y)
		e.post = post
		if text(key .. ".move") == "foot" and not e.attackId and dps > 0 and text(key .. ".nato") ~= "artillery" then
			local every = math.max(1, math.floor(num("cover.seekSec") * num("match.tickHz") + 0.5))
			if (e.id + self.ticks) % every == 0 and seekCover(e, key) then
				return
			end
		end
		if (e.id + self.ticks) % 20 ~= 0 then
			return
		end
		if e.repairId then
			repairThink(e)
			return
		end
		if e.roadJob then
			roadThink(e)
			return
		end
		if e.sabotageCell then
			sabotageThink(e)
			return
		end
		if e.attackId or e.firing or (e.reconLeft or 0) > 0 then
			return
		end
		if dps <= 0 or text(key .. ".weapon") == "salvo" then
			return
		end
		local sx, sy = centre(post)
		local leash = num("movement.leashCells")
		local range = num(key .. ".range")
		local reach = math.min(num(key .. ".sight"), num("movement.chaseCells") + range)
		local best, bestD = nil, reach * reach
		for _, p in self.list do
			if p.alive and p.cat == "unit" and p.kind ~= TRUCK and canAttack(e.side, p.side) and vsOf(key, p.class) > 0
				and d2(p.x, p.y, sx, sy) <= leash * leash then
				local g = d2(p.x, p.y, e.x, e.y)
				if g < bestD then
					best, bestD = p, g
				end
			end
		end
		if best then
			if math.sqrt(bestD) > range * 0.8 then
				local path = pathing.route(cellAt(e.x, e.y), cellAt(best.x, best.y), e.kind)
				if path and #path > 0 then
					local keep = math.max(1, #path - math.floor(range * 0.6))
					local cut = table.move(path, 1, keep, 1, {})
					local last = cut[#cut]
					local lx, ly = centre(last)
					e.path, e.pathIndex, e.stall, e.stallTries = cut, 1, 0, 0
					e.spot, e.target, e.goalCell = { x = lx, y = ly }, { x = lx, y = ly }, last
					e.chasing = true
				end
			end
			return
		end
		if d2(e.x, e.y, sx, sy) > (leash * 0.5) ^ 2 then
			planTo(e, post, sx, sy)
			if e.path then
				e.chasing = true
			end
		end
	end

	local function packSecOf(e: Entity): number
		return if text(unitKey(e) .. ".weapon") == "mortar" then num("mortar.packSec") else num("artillery.packSec")
	end

	-- Transport (the game's B3 / $S / Pk / Tm / VV / IQ / EQ / OQ / Up / VQ / gbe / uG / ybe / wbe, land
	-- only): an IFV carries transport.capacity riders (infantry, AT). Ordered to board, riders (nearest
	-- first, as many as there is room for) walk to it and get in within boardCells; they give up if it
	-- drives off more than chaseCells away. Riders inside are out of the world: nothing sees or hits them
	-- and they move with the carrier. Unloading sets them down behind it, unloadCells back, spread
	-- across. If the carrier is destroyed each rider takes bailDamage of its full hp and jumps out
	-- round the wreck.
	self.carried = {} :: { [number]: Entity }
	do
		local T: any = {}
		function T.isCarrier(e: Entity): boolean
			return table.find((r.data["transport.carriers"] :: { string }?) or {}, e.kind) ~= nil
		end
		function self.canRide(e: Entity): boolean
			return e.alive and e.cat == "unit" and e.carrier == nil and not e.inside and not e.garrisonCity
				and table.find((r.data["transport.riders"] :: { string }?) or {}, e.kind) ~= nil
		end
		function T.boarders(c: Entity): { Entity }
			local out = {}
			for _, u in self.list do
				if u.alive and u.boarding == c.id then
					table.insert(out, u)
				end
			end
			return out
		end
		function self.roomIn(c: Entity): number
			if not T.isCarrier(c) then
				return 0
			end
			return num("transport.capacity") - #(c.cargo or {}) - #T.boarders(c)
		end
		function T.stopBoarding(u: Entity)
			u.boarding, u.path, u.target, u.spot = nil, nil, nil, nil
		end
		-- the game's wbe: into the carrier and out of the world
		function T.stow(u: Entity, c: Entity)
			T.stopBoarding(u)
			u.firing, u.attackId, u.chasing, u.coverCell = false, nil, nil, nil
			u.carrier, u.x, u.y = c.id, c.x, c.y
			self.carried[u.id] = u
			local keep = table.create(#self.list)
			for _, e in self.list do
				if e ~= u then
					table.insert(keep, e)
				end
			end
			self.list = keep
			c.cargo = c.cargo or {}
			table.insert(c.cargo, u.id)
			gridTick = -1
		end
		-- the game's VQ: back into the world at a free spot near (x, y), facing (fx, fy)
		function T.setDown(u: Entity, x: number, y: number, fx: number, fy: number)
			local px, py = self.freeSpotAt(math.clamp(x, 0.5, W - 0.5), math.clamp(y, 0.5, H - 0.5))
			self.carried[u.id] = nil
			u.carrier = nil
			u.x, u.y = px, py
			u.path, u.target, u.spot = nil, nil, nil
			u.post = cellAt(px, py)
			u.still, u.firing = 0, false
			u.heading = math.atan2(fy, fx)
			table.insert(self.list, u)
			gridTick = -1
		end
		function self.orderBoard(side: number, carrierId: number, ids: { number }): (number, string?)
			local c = self.entities[carrierId]
			if not c or not c.alive or c.side ~= side or c.carrier then
				return 0, "notCarrier"
			end
			local riders = {}
			for _, id in ids do
				local u = self.entities[id]
				if u and u.side == side and u.id ~= carrierId and self.canRide(u) then
					table.insert(riders, u)
				end
			end
			if not T.isCarrier(c) then
				return 0, "notCarrier"
			end
			if #riders == 0 then
				return 0, "noRiders"
			end
			local room = self.roomIn(c)
			if room <= 0 then
				return 0, "carrierFull"
			end
			table.sort(riders, function(a, b)
				local da, db = d2(a.x, a.y, c.x, c.y), d2(b.x, b.y, c.x, c.y)
				return if da ~= db then da < db else a.id < b.id
			end)
			local n = 0
			for i = 1, math.min(room, #riders) do
				local u = riders[i]
				u.target, u.attackId, u.path, u.chasing = nil, nil, nil, nil
				clearRecon(u)
				u.boarding = c.id
				local bc = num("transport.boardCells")
				if d2(u.x, u.y, c.x, c.y) > bc * bc then
					walkNear(u, c.x, c.y, bc * 0.5)
				end
				n += 1
			end
			return n, nil
		end
		-- the game's Up: riders out behind the carrier
		function T.unload(c: Entity): number
			local list = {}
			for _, id in c.cargo or {} do
				local u = self.carried[id]
				if u then
					table.insert(list, u)
				end
			end
			c.cargo = {}
			local fx, fy = math.cos(c.heading or 0), math.sin(c.heading or 0)
			local uc = num("transport.unloadCells")
			local ax, ay = c.x - fx * uc, c.y - fy * uc
			for i, u in list do
				local k = (i - 1 - (#list - 1) / 2) * uc * 0.6
				T.setDown(u, ax - fy * k, ay + fx * k, -fx, -fy)
			end
			return #list
		end
		function self.orderUnload(side: number, ids: { number }): (number, string?)
			local any, n = false, 0
			for _, id in ids do
				local c = self.entities[id]
				if c and c.alive and c.side == side and (T.isCarrier(c) or (c.cargo and #c.cargo > 0)) then
					any = true
					if c.cargo and #c.cargo > 0 then
						n += T.unload(c)
					end
				end
			end
			if not any then
				return 0, "notCarrier"
			end
			if n == 0 then
				return 0, "noCargo"
			end
			return n, nil
		end
		-- the game's gbe / uG: out of a wreck, hurt
		function self.bail(c: Entity)
			local list = {}
			for _, id in c.cargo or {} do
				local u = self.carried[id]
				if u then
					table.insert(list, u)
				end
			end
			c.cargo = {}
			T.bailOut(list, c.x, c.y)
		end
		function T.bailOut(list: { Entity }, x: number, y: number)
			local uc = num("transport.unloadCells")
			for i, u in list do
				u.hp -= num(unitKey(u) .. ".hp") * num("transport.bailDamage")
				u.hitAt = self.time
				if u.hp <= 0 then
					self.carried[u.id] = nil
					u.alive, u.hp = false, 0
					self.entities[u.id] = nil
					event({ type = "destroyed", id = u.id, kind = u.kind, side = u.side, by = -1 })
				else
					local a = (i - 1) / math.max(1, #list) * math.pi * 2 + 0.5
					T.setDown(u, x + math.cos(a) * uc, y + math.sin(a) * uc, math.cos(a), math.sin(a))
				end
			end
		end
		-- the game's ybe (land part): boarders walk to their carrier and get in; riders ride along
		function self.transportTick()
			local bc, chase = num("transport.boardCells"), num("transport.chaseCells")
			local ready = {}
			for _, u in self.list do
				if u.alive and u.boarding then
					local c = self.entities[u.boarding]
					if not c or not c.alive or c.side ~= u.side or not T.isCarrier(c) or #(c.cargo or {}) >= num("transport.capacity") then
						T.stopBoarding(u)
					else
						local dd = d2(u.x, u.y, c.x, c.y)
						if dd <= bc * bc then
							table.insert(ready, { u, c })
						elseif c.path and c.target and dd > chase * chase then
							T.stopBoarding(u)
						elseif not u.path or (u.id + self.ticks) % 10 == 0 then
							local id = u.boarding
							walkNear(u, c.x, c.y, bc * 0.5)
							u.boarding = id
							if not u.path and d2(u.x, u.y, c.x, c.y) > bc * bc then
								T.stopBoarding(u)
							end
						end
					end
				end
			end
			for _, pr in ready do
				local u, c = pr[1], pr[2]
				if #(c.cargo or {}) < num("transport.capacity") then
					T.stow(u, c)
				else
					T.stopBoarding(u)
				end
			end
			if next(self.carried) == nil then
				return
			end
			local orphans = {}
			for _, u in self.carried do
				local c = self.entities[u.carrier :: number]
				if c and c.alive and c.cargo and table.find(c.cargo, u.id) then
					u.x, u.y = c.x, c.y
				else
					table.insert(orphans, u)
				end
			end
			for _, u in orphans do
				if alive(u.side) then
					T.bailOut({ u }, u.x, u.y)
				else
					self.carried[u.id] = nil
					u.alive = false
					self.entities[u.id] = nil
				end
			end
		end
	end

	-- Command truck / mobile HQ (the game's Z7e / QY / rk / D9 / j7e / hqOnOrder): the factory builds a
	-- command truck. Ordered to deploy, it stops and after mobileHq.deploySec becomes an HQ on a free cell
	-- within deployReach (preferring one near a road that reaches the rigs), with the truck's share of
	-- hp; moving cancels it. The new HQ is the side's HQ.
	function self.truckOf(side: number): Entity?
		for _, e in self.list do
			if e.alive and e.side == side and e.cat == "unit" and e.kind == "command" then
				return e
			end
		end
		return nil
	end
	function self.hqOnOrder(side: number): boolean
		for _, st in self.list do
			if st.alive and st.side == side and isStructure(st) and st.queue and table.find(st.queue, "command") then
				return true
			end
		end
		return false
	end
	do
		local M: any = {}
		-- the game's D9: a road piece near the cell that also reaches a rig (any piece when no rig has one)
		function M.roadOk(cell: number): boolean
			local cx, cy = centre(cell)
			local here = roads.piecesNear(cx, cy, offReach + hqFoot)
			if next(here) == nil then
				return false
			end
			local rigPieces = {}
			for _, rig in rigList do
				for p in roads.piecesNear(rig.x, rig.y, offReach) do
					rigPieces[p] = true
				end
			end
			if next(rigPieces) == nil then
				return true
			end
			for p in here do
				if rigPieces[p] then
					return true
				end
			end
			return false
		end
		-- the game's freeCellNear: the closest cell within n where an HQ fits (and pred holds)
		function M.freeCellNear(cell: number, n: number, pred: ((number) -> boolean)?): number
			local x0, y0 = cell % W, cell // W
			local best, bd = -1, math.huge
			for dy = -n, n do
				for dx = -n, n do
					local x, y = x0 + dx, y0 + dy
					local d = dx * dx + dy * dy
					if x >= 0 and y >= 0 and x < W and y < H and d <= n * n and d < bd then
						local c = y * W + x
						if not placeProblem(c, "hq") and (not pred or pred(c)) then
							best, bd = c, d
						end
					end
				end
			end
			return best
		end
		-- the game's rk
		function M.deployCell(e: Entity): number
			local c = cellAt(e.x, e.y)
			if c < 0 then
				return -1
			end
			local n = math.max(1, math.floor(num("mobileHq.deployReach") + 0.5))
			local best = M.freeCellNear(c, n, M.roadOk)
			return if best >= 0 then best else M.freeCellNear(c, n, nil)
		end
		self.hqDeployCell = M.deployCell
		self.hqRoadOk = M.roadOk
		function self.deployHq(side: number, id: number): (boolean, string?)
			local e = self.entities[id]
			if not e or not e.alive or e.side ~= side or e.kind ~= "command" or e.carrier then
				return false, "noTruck"
			end
			if e.deployAt then
				return false, "alreadyDeploying"
			end
			local c = M.deployCell(e)
			if c < 0 then
				return false, "noRoom"
			end
			self.orderStop(side, { e.id })
			e.deployAt, e.deployCell = self.time + num("mobileHq.deploySec"), c
			event({ type = "hqDeploying", id = e.id, side = side, sec = num("mobileHq.deploySec") })
			return true, nil
		end
		-- the game's j7e
		function self.deployTick()
			for _, e in self.list do
				if e.alive and e.kind == "command" and e.deployAt then
					if e.path and e.target then
						e.deployAt, e.deployCell = nil, nil
					elseif self.time >= e.deployAt then
						local c = e.deployCell or -1
						if c < 0 or placeProblem(c, "hq") then
							c = M.deployCell(e)
						end
						e.deployAt, e.deployCell = nil, nil
						if c < 0 then
							event({ type = "blocked", side = e.side, reason = "noRoom" })
						else
							local had = hqOf(e.side) ~= nil
							local hpHq = num("structures.hq.hp")
							local hq = add({
								kind = "hq", cat = "structure", class = "structure", side = e.side, x = c % W + 0.5,
								y = c // W + 0.5, cell = c, heading = 0, hp = math.max(1, hpHq * (e.hp / num("units.command.hp"))),
								maxHp = hpHq, shotTimer = 0, alive = true, queue = {}, queueProgress = 0, built = 1, lastHitAt = -99,
							})
							setFootprint(hq, true)
							self.sides[e.side].hqId = hq.id
							self.sides[e.side].headlessSince = nil
							e.alive = false
							updateConnections()
							event({ type = if had then "hqDeployed" else "hqSetUp", id = hq.id, side = e.side })
						end
					end
				end
			end
		end
	end

	-- The opening drop (the game's u9e / lk / cD / f9e / p9e / nq / vqe / G_ / bqe, started with deps.drop):
	-- the war waits while each side picks where to land (drop.pickSec, or until every side is ready).
	-- A pick must keep edgeCells off the map's edge, be open ground with room for an HQ within
	-- deployReach and be at least drop.apart from the other sides' start points; otherwise the side's
	-- start point is used. A plane per side then flies in (flySec) and drops drop.loads (the command
	-- truck and three squads) under chutes (chuteSec). Once all are down the war starts and each command
	-- truck sets up its HQ at once if a road there reaches the rigs. Not ported: the opening deck (the
	-- game's random arrival scene and conditions).
	do
		local O: any = {}
		function O.init()
			local homes, picks, ready = {}, {}, {}
			for side, st in deps.starts do
				homes[side] = { x = math.floor(st.x) + 0.5, y = math.floor(st.y) + 0.5 }
				picks[side] = { x = homes[side].x, y = homes[side].y }
				ready[side] = false
			end
			self.drop = { phase = "pick", t = 0, pickEnds = num("drop.pickSec"), homes = homes, picks = picks, ready = ready,
				planes = {}, landT = -1 }
			if r:has("opening.on") and r:flag("opening.on") then
				O.opening()
			end
		end
		-- the game's Pg: a small seeded stream (seed, salt) used by the opening deck
		function O.stream(seedN: number, salt: number)
			local function imul(a: number, b: number): number
				local al, ah = bit32.band(a, 0xffff), bit32.rshift(a, 16)
				local bl, bh = bit32.band(b, 0xffff), bit32.rshift(b, 16)
				return bit32.band(al * bl + bit32.lshift(bit32.band(ah * bl + al * bh, 0xffff), 16), 0xffffffff)
			end
			local st = (seedN * 2654435761 + salt * 2246822507) % 4294967296
			local g = {}
			function g.next(): number
				st = (st + 1831565813) % 4294967296
				local e = st
				e = imul(bit32.bxor(e, bit32.rshift(e, 15)), bit32.bor(e, 1))
				e = bit32.bxor(e, (e + imul(bit32.bxor(e, bit32.rshift(e, 7)), bit32.bor(e, 61))) % 4294967296)
				return bit32.bxor(e, bit32.rshift(e, 14)) / 4294967296
			end
			function g.pick(list: { string }, w: (string) -> number): string?
				local n = 0
				for _, a in list do
					n += math.max(0, w(a))
				end
				if #list == 0 or n <= 0 then
					return nil
				end
				local x = g.next() * n
				for _, a in list do
					local k = math.max(0, w(a))
					if k > 0 then
						x -= k
						if x < 0 then
							return a
						end
					end
				end
				for i = #list, 1, -1 do
					if w(list[i]) > 0 then
						return list[i]
					end
				end
				return nil
			end
			return g
		end
		-- The opening deck (the game's hqe / sqe / uqe): the hour the drop arrives, drawn from the match
		-- seed with opening.deck.arrival weights (storm and sandstorm need the weather, off in skirmish),
		-- moves the day clock to opening.deck.hour.<arrival> unless the rules already shift it.
		-- Not ported: the opening scene (a picture only), the operation name and intel tip (text), and the
		-- conditions (need the events system, off in skirmish).
		function O.opening()
			local g = O.stream(deps.deckSeed or seed, 23)
			local weather = r:has("weather.on") and r:flag("weather.on")
			local arrival = g.pick({ "day", "dawn", "dusk", "night", "storm", "sandstorm" }, function(k: string): number
				if (k == "storm" or k == "sandstorm") and not weather then
					return 0
				end
				return numOr(`opening.deck.arrival.{k}`, 0)
			end) or "day"
			self.drop.opening = { arrival = arrival }
			if numOr("daylight.offsetSec", 0) == 0 and numOr("daylight.rate", 1) == 1 then
				local hour = num(`opening.deck.hour.{if arrival == "storm" or arrival == "sandstorm" then "day" else arrival}`)
				self.dayOffset = ((hour - 0.08) % 1 + 1) % 1 * 480 -- the game's daylight startPhase and lengthSec
			end
		end
		if deps.drop then
			O.init()
		end
		function O.apartFrom(x: number, y: number, list: { any }, apart: number): boolean
			for _, p in list do
				if math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2) < apart then
					return false
				end
			end
			return true
		end
		function O.otherHomes(side: number): { any }
			local out = {}
			for s, h in self.drop.homes do
				if s ~= side and alive(s) then
					table.insert(out, h)
				end
			end
			return out
		end
		-- the game's lk
		function self.landingProblem(x: number, y: number, side: number): string?
			local d = self.drop
			if d and side > 0 and not O.apartFrom(x, y, O.otherHomes(side), num("drop.apart")) then
				return "startTaken"
			end
			local e = num("drop.edgeCells")
			if x < e or y < e or x > W - e or y > H - e then
				return "terrain"
			end
			local c = cellAt(x, y)
			if c < 0 or not roads.passable(c) then
				return "terrain"
			end
			local t = roads.terrain(c)
			if t == "deep" or t == "shallow" then
				return "terrain"
			end
			if self.hqDeployCell({ x = x, y = y } :: any) < 0 then
				return "noRoom"
			end
			return nil
		end
		-- the game's cD: a warning, not a refusal
		function self.dropWarning(x: number, y: number): string?
			local c = cellAt(x, y)
			if c < 0 then
				return nil
			end
			local e = { x = x, y = y } :: any
			local cell = self.hqDeployCell(e)
			return if cell >= 0 and self.hqRoadOk(cell) then nil else "noRoad"
		end
		function self.setDropPick(side: number, x: number, y: number): (boolean, string?)
			local d = self.drop
			if not d or d.phase ~= "pick" or not alive(side) then
				return false, "notInMode"
			end
			local why = self.landingProblem(x, y, side)
			if why then
				return false, why
			end
			d.picks[side] = { x = x, y = y }
			return true, nil
		end
		function self.setDropReady(side: number): (boolean, string?)
			local d = self.drop
			if not d or d.phase ~= "pick" then
				return false, "notInMode"
			end
			d.ready[side] = true
			return true, nil
		end
		function self.dropLeft(): number
			local d = self.drop
			if not d or d.phase == "done" then
				return 0
			end
			if d.phase == "pick" then
				return math.max(0, d.pickEnds - d.t) + num("drop.flySec") + num("drop.chuteSec")
			end
			return math.max(0, d.landT - d.t)
		end
		-- the game's vqe: picks are checked again (and kept apart), then the planes go
		function O.launch()
			local d = self.drop
			d.phase = "flight"
			d.pickEnds = math.min(d.pickEnds, d.t)
			local taken = {}
			local sides = {}
			for side in self.sides do
				if alive(side) then
					table.insert(sides, side)
				end
			end
			table.sort(sides)
			for _, side in sides do
				local p = d.picks[side]
				if self.landingProblem(p.x, p.y, side) or not O.apartFrom(p.x, p.y, taken, num("drop.apart")) then
					p = d.homes[side]
				end
				d.picks[side] = { x = p.x, y = p.y }
				table.insert(taken, d.picks[side])
			end
			local landT = d.t
			-- the plane maths runs on the war clock; shift its times onto the drop clock
			for _, side in sides do
				local p = d.picks[side]
				local pl = self.planeFor(side, p.x, p.y, (r.data["drop.loads"] :: { string }) or {}, num("drop.flySec"), num("drop.stickGap"))
				local k = d.t - self.time
				pl.startT += k
				pl.overT += k
				pl.goneT += k
				for _, l in pl.loads do
					l.outT += k
					l.landT += k
					landT = math.max(landT, l.landT)
				end
				table.insert(d.planes, pl)
				event({ type = "dropAway", side = side, sec = math.ceil(num("drop.flySec")), x = p.x, y = p.y })
			end
			d.landT = landT
		end
		-- the game's bqe: everyone down, the war starts
		function O.land()
			local d = self.drop
			d.phase = "done"
			for _, pl in d.planes do
				if alive(pl.side) then
					local truck = nil
					for _, l in pl.loads do
						local x, y = self.freeSpotAt(l.x, l.y)
						local u = self.spawnUnit(l.kind, pl.side, x, y)
						if l.kind == "command" and not truck then
							truck = u
						end
					end
					local first = pl.loads[1] or { x = pl.fromX, y = pl.fromY }
					event({ type = "dropLanded", side = pl.side, x = first.x, y = first.y })
					if truck and r:flag("drop.autoDeploy") then
						local c = self.hqDeployCell(truck)
						if c >= 0 and self.hqRoadOk(c) then
							self.deployHq(pl.side, truck.id)
						else
							event({ type = "dropNoRoad", side = pl.side, x = first.x, y = first.y })
						end
					end
				end
			end
		end
		-- the game's nq
		function self.dropTick(dt: number)
			local d = self.drop
			d.t += dt
			if d.phase == "pick" then
				local all = true
				for side, rd in d.ready do
					if not rd and alive(side) then
						all = false
					end
				end
				if d.t >= d.pickEnds or all then
					O.launch()
				end
			elseif d.phase == "flight" and d.t >= d.landT then
				O.land()
			end
		end
	end

	-- Cancel and demolish (the game's cancelQueued / cancelBuilding / ert / trt / Qbe / ort): a queued unit
	-- can be called off for what was paid; a building still going up for the unfinished share of its
	-- price (and kill cost); a finished one (not the HQ) is pulled down over demolish.sec, its queue
	-- refunded first, giving back demolish.refundShare of its price and kill cost. While it comes down
	-- it does nothing.
	function self.cancelQueued(side: number, id: number, index: number): (boolean, string?)
		local st = self.entities[id]
		if not st or not st.alive or st.side ~= side or not st.queue or index < 1 or index > #st.queue then
			return false, "blocked"
		end
		table.remove(st.queue, index)
		local paid = table.remove(st.queuePaid or {}, index)
		if index == 1 then
			st.queueProgress = 0
		end
		self.sides[side].oil += paid or 0
		return true, nil
	end
	function self.priceOf(st: Entity): number
		return st.paid or numOr(`structures.{st.kind}.cost`, 0)
	end
	function self.removeStructure(st: Entity)
		st.alive, st.hp = false, 0
		st.queue = {}
		setFootprint(st, false)
		gridTick = -1
	end
	function self.cancelBuilding(side: number, id: number): (boolean, string?)
		local st = self.entities[id]
		if not st or not st.alive or st.side ~= side or not isStructure(st) or st.built >= 1 then
			return false, "blocked"
		end
		self.sides[side].oil += math.floor(self.priceOf(st) * (1 - st.built) + 0.5)
		local kc = numOr(`structures.{st.kind}.killCost`, 0)
		if kc > 0 then
			self.sides[side].killsSpent = math.max(0, (self.sides[side].killsSpent or 0) - math.floor(kc * (1 - st.built) + 0.5))
		end
		self.removeStructure(st)
		event({ type = "buildCancelled", id = st.id, side = side, kind = st.kind })
		return true, nil
	end
	function self.demolishProblem(side: number, st: Entity?): string?
		if not st or not st.alive or not isStructure(st) then
			return "blocked"
		end
		if st.side ~= side then
			return "notOwned"
		end
		if st.built < 1 or st.demolishAt or st.kind == "hq" then
			return "blocked"
		end
		return nil
	end
	function self.demolish(side: number, id: number): (boolean, string?)
		local st = self.entities[id]
		local why = self.demolishProblem(side, st)
		if why then
			return false, why
		end
		local s = st :: Entity
		for i = #(s.queue or {}), 1, -1 do
			self.cancelQueued(side, s.id, i)
		end
		s.demolishFrom, s.demolishAt = self.time, self.time + num("demolish.sec")
		return true, nil
	end
	function self.demolishTick()
		for _, st in self.list do
			if st.alive and st.demolishAt and self.time >= st.demolishAt then
				local share = num("demolish.refundShare")
				local oil = math.floor(self.priceOf(st) * share + 0.5)
				local kills = math.floor(numOr(`structures.{st.kind}.killCost`, 0) * share + 0.5)
				local sd = self.sides[st.side]
				if sd then
					sd.oil += oil
					sd.killsSpent = math.max(0, (sd.killsSpent or 0) - kills)
				end
				self.removeStructure(st)
				event({ type = "demolished", id = st.id, side = st.side, kind = st.kind, oil = oil })
			end
		end
	end

	-- Armies (the game's nations[].army, allows, N$ and armyUnits): each side fights as the coalition
	-- (the default) or the republic. Only the coalition fields mortars; only the republic lays
	-- minefields (and has the sea units, not in the slice).
	function self.armyOf(side: number): string
		return (deps.armies and deps.armies[side]) or "coalition"
	end
	function self.armyAllows(side: number, item: string): boolean
		if item == "mortar" then
			return self.armyOf(side) == "coalition"
		end
		if item == "minefield" then
			return self.armyOf(side) == "republic"
		end
		return true
	end

	-- Minefields (the game's Tk / Tet / Aet / Cve / kve / layMinefield / yle / LA / Pet / Ret / vle / Yq /
	-- Lve / EI): drawn as a stroke, clipped at maxMetres; every cell within half of widthMetres of it
	-- that is open, buildable, off a rig pad, clear of other buildings and minefields and enemyGap from
	-- enemy buildings takes mines. Price oilPerMetre, one charge per metresPerMine and secPerMetre to lay,
	-- all on the metres that take mines. Cells are laid in order along the stroke. A non-engineer
	-- (either side's) on a laid cell sets one off: damage by armour, splashShare of it on everyone within
	-- splashCells, then gapSec before the next; a truck on it is lost. Enemy engineers on or next to it
	-- find it and, standing on it, clear a charge every clearSec. Hidden from the enemy until found.
	do
		local M: any = {}
		local function mpc(): number
			return math.max(1e-6, num("minefield.metresPerCell"))
		end
		-- the game's Tet: snap to cell centres, drop repeats, clip at maxCells
		function M.snap(pts: { { x: number, y: number } }, maxCells: number)
			local n = {}
			for _, a in pts do
				local x = math.min(W - 1, math.max(0, math.floor(a.x))) + 0.5
				local y = math.min(H - 1, math.max(0, math.floor(a.y))) + 0.5
				local l = n[#n]
				if not l or l.x ~= x or l.y ~= y then
					table.insert(n, { x = x, y = y })
				end
			end
			local sum = 0
			for i = 2, #n do
				local a, b = n[i - 1], n[i]
				local l = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
				if sum + l > maxCells + 1e-6 then
					local c = (maxCells - sum) / l
					local h = { x = math.floor(a.x + (b.x - a.x) * c) + 0.5, y = math.floor(a.y + (b.y - a.y) * c) + 0.5 }
					local u = table.move(n, 1, i - 1, 1, {})
					local d = math.sqrt((h.x - a.x) ^ 2 + (h.y - a.y) ^ 2)
					if (h.x ~= a.x or h.y ~= a.y) and sum + d <= maxCells + 1e-6 then
						table.insert(u, h)
						sum += d
					end
					return u, sum, true
				end
				sum += l
			end
			return n, sum, false
		end
		-- the game's Cve: cells taken by buildings and minefields
		function M.taken(): { [number]: boolean }
			local set = {}
			for _, st in self.list do
				if st.alive and isStructure(st) then
					for _, c in (if st.kind == "minefield" then st.mineCells or {} else footprintCells(st.cell, footprintOf(st.kind))) do
						set[c] = true
					end
				end
			end
			return set
		end
		-- the game's Aet
		function M.cellProblem(side: number, c: number, taken: { [number]: boolean }): string?
			if c < 0 or c >= W * H then
				return "blocked"
			end
			local key = `terrain.{roads.terrain(c)}.buildable`
			if not (r:has(key) and r:flag(key)) or not roads.passable(c) then
				return "mineGround"
			end
			if taken[c] then
				return "spacing"
			end
			local x, y = c % W + 0.5, c // W + 0.5
			local pad = num("rigs.padCells") + 0.5
			for _, rig in rigList do
				if math.abs(rig.x - x) <= pad and math.abs(rig.y - y) <= pad then
					return "onRig"
				end
			end
			local gap = num("build.enemyGap")
			for _, st in self.list do
				if st.alive and isStructure(st) and st.side ~= side and st.kind ~= "minefield" then
					local l = gap + footprintOf(st.kind)
					if (st.cell % W + 0.5 - x) ^ 2 + (st.cell // W + 0.5 - y) ^ 2 <= l * l then
						return "nearEnemy"
					end
				end
			end
			return nil
		end
		-- the game's Tk: the layout of a stroke, its price and what is wrong with it
		function self.mineLayout(side: number, pts: { { x: number, y: number } }, free: boolean?): { [string]: any }
			local a = mpc()
			local line, cellsLong, clipped = M.snap(pts, num("minefield.maxMetres") / a)
			local width = math.max(1, 2 * math.floor((num("minefield.widthMetres") / a - 1) / 2 + 0.5) + 1)
			local l = (width - 1) / 2
			local found = {}
			if #line > 0 then
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
				for _, p in line do
					x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
				end
				local along = { 0 }
				for i = 2, #line do
					along[i] = along[i - 1] + math.sqrt((line[i].x - line[i - 1].x) ^ 2 + (line[i].y - line[i - 1].y) ^ 2)
				end
				local reach = l + 0.01
				for y = math.max(0, math.floor(y0 - l - 1)), math.min(H - 1, math.floor(y1 + l + 1)) do
					for x = math.max(0, math.floor(x0 - l - 1)), math.min(W - 1, math.floor(x1 + l + 1)) do
						local px, py = x + 0.5, y + 0.5
						local best, at = math.huge, 0
						if #line == 1 then
							best = math.sqrt((px - line[1].x) ^ 2 + (py - line[1].y) ^ 2)
						else
							for i = 2, #line do
								local p0, p1 = line[i - 1], line[i]
								local bx, by = p1.x - p0.x, p1.y - p0.y
								local u = bx * bx + by * by
								local t = if u > 0 then math.clamp(((px - p0.x) * bx + (py - p0.y) * by) / u, 0, 1) else 0
								local z = math.sqrt((px - (p0.x + bx * t)) ^ 2 + (py - (p0.y + by * t)) ^ 2)
								if z < best - 1e-9 then
									best, at = z, along[i - 1] + math.sqrt(u) * t
								end
							end
						end
						if best <= reach then
							table.insert(found, { c = y * W + x, along = at, d = best })
						end
					end
				end
			end
			table.sort(found, function(p, q)
				if p.along ~= q.along then
					return p.along < q.along
				end
				if p.d ~= q.d then
					return p.d < q.d
				end
				return p.c < q.c
			end)
			local taken = M.taken()
			local cells, why, good = {}, {}, {}
			for i, f in found do
				cells[i] = f.c
				why[i] = M.cellProblem(side, f.c, taken) or false
				if not why[i] then
					table.insert(good, f.c)
				end
			end
			local metres = cellsLong * a
			local laid = if #cells > 0 then metres * #good / #cells else 0
			local cost = math.floor(laid * num("minefield.oilPerMetre") + 0.5)
			local mines = math.max(1, math.floor(laid / math.max(1e-6, num("minefield.metresPerMine")) + 0.5))
			local sec = math.max(0.5, laid * num("minefield.secPerMetre"))
			local problem: string? = nil
			if not free and not self.armyAllows(side, "minefield") then
				problem = "locked"
			elseif not free and not alive(side) then
				problem = "blocked"
			elseif #good == 0 and #cells > 0 and metres >= num("minefield.minMetres") then
				for _, w in why do
					if w then
						problem = w
						break
					end
				end
				problem = problem or "mineGround"
			elseif laid < num("minefield.minMetres") - 1e-6 then
				problem = "mineShort"
			elseif not free and self.sides[side].oil < cost then
				problem = "oil"
			end
			return {
				pts = line, cells = cells, why = why, good = good, metres = metres, laidMetres = laid,
				cost = cost, mines = mines, sec = sec, clipped = clipped, problem = problem,
			}
		end
		-- the game's layMinefield + yle
		function self.layMinefield(side: number, pts: { { x: number, y: number } }): (number?, string?)
			if self.winner then
				return nil, "blocked"
			end
			local lay = self.mineLayout(side, pts)
			if lay.problem then
				return nil, lay.problem
			end
			self.sides[side].oil -= lay.cost
			local cell = lay.good[#lay.good // 2 + 1] or -1
			local hp = num("structures.minefield.hp")
			local st = add({
				kind = "minefield", cat = "structure", class = "structure", side = side, x = cell % W + 0.5,
				y = cell // W + 0.5, cell = cell, heading = 0, hp = hp, maxHp = hp, shotTimer = 0, alive = true,
				queue = {}, queueProgress = 0, built = 0, lastHitAt = -99, paid = lay.cost,
				mineCells = table.clone(lay.good), mineMetres = math.floor(lay.laidMetres + 0.5),
				buildSec = lay.sec, mines = lay.mines, mineSeen = {},
			})
			event({ type = "buildPlaced", id = st.id, kind = "minefield", side = side })
			return st.id, nil
		end
		-- the game's LA / xve: the cells laid so far (in order along the stroke)
		function self.laidMines(st: Entity): ({ number }, { [number]: boolean })
			local cells = st.mineCells or {}
			local n = if st.built >= 1 then #cells else math.floor(#cells * math.max(0, st.built))
			if st.laidCache and st.laidCache.n == n then
				return st.laidCache.list, st.laidCache.set
			end
			local list, set = table.move(cells, 1, n, 1, {}), {}
			for _, c in list do
				set[c] = true
			end
			st.laidCache = { n = n, list = list, set = set }
			return list, set
		end
		-- the game's EI / Mve: hidden from this side (a minefield the side has not found)
		function self.mineHidden(st: Entity, side: number): boolean
			return st.kind == "minefield" and side > 0 and st.side ~= side and not (st.mineSeen and st.mineSeen[side])
		end
		function M.spend(st: Entity)
			st.mines = (st.mines or num("minefield.charges")) - 1
			if st.mines <= 0 then
				self.removeStructure(st)
				event({ type = "minefieldSpent", id = st.id, side = st.side, x = st.x, y = st.y })
			end
		end
		function M.eligible(u: Entity): boolean
			return u.alive and u.cat == "unit" and u.hp > 0 and not u.inside and not u.carrier
				and text(`units.{u.kind}.armour`) ~= "air"
		end
		-- the game's vle: a mine goes off under a unit or a truck
		function M.blast(st: Entity, u: Entity)
			local cfgDamage = function(e: Entity): number
				return numOr(`minefield.damage.{text(`units.{e.kind}.armour`)}`, 0)
			end
			st.mineAt = self.time
			st.mineSeen = st.mineSeen or {}
			st.mineSeen[u.side] = true
			local x, y = u.x, u.y
			local victims = {}
			if u.kind == TRUCK then
				u.hp = 0
				hitTruck(u, 0, "", 0, st.side)
			else
				local dmg = cfgDamage(u)
				if dmg > 0 then
					u.hp -= dmg
					u.lastHitAt = self.time
					table.insert(victims, u)
				end
			end
			local sc = num("minefield.splashCells")
			for _, o in unitsNear(x, y, sc) do
				if o ~= u and o.kind ~= TRUCK and M.eligible(o) and (o.x - x) ^ 2 + (o.y - y) ^ 2 <= sc * sc then
					local dmg = cfgDamage(o) * num("minefield.splashShare")
					if dmg > 0 then
						o.hp -= dmg
						o.lastHitAt = self.time
						table.insert(victims, o)
					end
				end
			end
			for _, o in victims do
				killIfDead(o, st.side)
			end
			event({ type = "mineBlast", id = st.id, side = u.side, owner = st.side, kind = u.kind, x = x, y = y })
			M.spend(st)
		end
		-- the game's Met: within s cells of any of its cells
		function M.near(st: Entity, x: number, y: number, s: number): boolean
			for _, c in st.mineCells or {} do
				local dx = math.max(0, math.abs(x - (c % W + 0.5)) - 0.5)
				local dy = math.max(0, math.abs(y - (c // W + 0.5)) - 0.5)
				if dx * dx + dy * dy <= s * s then
					return true
				end
			end
			return false
		end
		-- the game's Pet / Ret, every tick
		function self.minesTick(dt: number)
			local spot = num("minefield.spotCells")
			for _, st in self.list do
				if st.alive and st.kind == "minefield" and st.built > 0 then
					local list, set = self.laidMines(st)
					if not st.box then
						local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
						for _, c in st.mineCells do
							x0, y0 = math.min(x0, c % W), math.min(y0, c // W)
							x1, y1 = math.max(x1, c % W + 1), math.max(y1, c // W + 1)
						end
						st.box = { x0, y0, x1, y1 }
					end
					local b = st.box
					local clearing, first, truck = false, nil, nil
					if #list > 0 then
						for _, u in self.list do
							if M.eligible(u) and u.x >= b[1] - spot and u.x <= b[3] + spot and u.y >= b[2] - spot and u.y <= b[4] + spot then
								local on = set[cellAt(u.x, u.y)] == true
								local ab = r.data[`units.{u.kind}.abilities`] :: { string }?
								if u.kind == TRUCK then
									if on and not truck then
										truck = u
									end
								elseif ab and table.find(ab, "engineer") then
									if canAttack(st.side, u.side) then
										if on or M.near(st, u.x, u.y, spot) then
											st.mineSeen[u.side] = true
										end
										if on then
											clearing = true
										end
									end
								elseif on and not first then
									first = u
								end
							end
						end
					end
					local stop = false
					if clearing then
						st.mineClear = (st.mineClear or 0) + dt
						if st.mineClear >= num("minefield.clearSec") then
							st.mineClear = 0
							M.spend(st)
							stop = not st.alive
						end
					end
					if not stop and self.time - (st.mineAt or -99) >= num("minefield.gapSec") then
						if first then
							M.blast(st, first)
						elseif truck then
							M.blast(st, truck)
						end
					end
				end
			end
		end
	end

	function self.step(dt: number)
		if self.winner then
			return
		end
		if self.drop and self.drop.phase ~= "done" then
			-- the game freezes the war while the sides pick and the planes fly in
			self.ticks += 1
			self.dropTick(dt)
			return
		end
		self.time += dt
		self.ticks += 1
		if self.ticks % 10 == 0 then
			updateConnections()
		end
		production(dt)
		reconTick(dt)
		self.deployTick()
		self.demolishTick()
		self.minesTick(dt)
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
						if not going and text(unitKey(e) .. ".weapon") == "salvo" then
							self.scoot(e) -- the game's eUe
						end
					end
				end
				e.stillStep = if held then "held" elseif e.target and e.path then "move" else "still"
				if held then
					-- packing: stands where it is
				elseif e.target and e.path then
					local fromX, fromY, fromIndex = e.x, e.y, e.pathIndex
					e.moved = pathing.step(e, dt)
					if e.moved and holdAtEnemy(e, fromX, fromY) then
						e.x, e.y, e.pathIndex, e.moved = fromX, fromY, fromIndex, false
						e.pace = 0
					end
					if e.moved then
						local c = cellAt(e.x, e.y)
						if c >= 0 and c ~= cellAt(fromX, fromY) and roads.isRoad(c) then
							unitWear(e.kind, c) -- the game's IWe
						end
					end
					if e.path and e.pathIndex > #e.path then
						-- arrive (idle where it stands; the game's arrive sets its post there)
						e.target, e.path, e.spot, e.chasing = nil, nil, nil, nil
						e.post = cellAt(e.x, e.y)
					end
				elseif e.target then
					e.target = nil
				end
			end
		end
		unitsFire(dt)
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK then
				-- an idle unit that finds a target while chasing or walking back stops there
				if e.chasing and e.firing and e.path then
					e.target, e.path, e.spot, e.chasing = nil, nil, nil, nil
				elseif not e.path then
					if hasHull(e) then
						pathing.idleTurn(e, dt, self.ticks, nearestFoe)
					end
					idleThink(e)
				end
			end
		end
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
		separate(dt)
		self.transportTick()
		rigs(dt)
		settlementsTick(dt)
		forwardTick(dt)
		cityHealing(dt)
		repairsTick(dt)
		roadRepairsTick(dt)
		sabotageTick(dt)
		airTick(dt)
		droneTick(dt)
		self.flaresTick(dt)
		self.vetHeal(dt)
		forgetStrikes()
		rebuildTick(dt)
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
		local clock = (self.dayOffset or numOr("daylight.offsetSec", 0)) + self.time * numOr("daylight.rate", 1)
		local phase = ((math.floor(clock) / DAY_SEC + DAY_START) % 1 + 1) % 1
		if phase < SUN_UP then
			return 0
		end
		return math.min(smooth(SUN_UP, SUN_UP + NIGHT_IN, phase), 1 - smooth(1 - NIGHT_OUT, 1, phase))
	end
	-- Night operations (the game's wb / vge / nV / kje / xje / Cje / m1e / Lje): with nightOps.enabled a
	-- side sees nightOps.sightShare of its sight at full night, or nvSightShare while it has a finished,
	-- switched-on Night Operations Tower; without the rules, daylight.nightSightShare. A side without a
	-- tower also gets no nightOps.quietNotices alerts once night reaches blindFrom.
	function self.nightOpsOn(): boolean
		return r:has("nightOps.enabled") and r:flag("nightOps.enabled")
	end
	function self.nightVisionFor(side: number): boolean
		if not self.nightOpsOn() then
			return false
		end
		for _, st in self.list do
			if st.alive and st.kind == "nightops" and st.side == side and st.built >= 1 and not st.nvOff then
				return true
			end
		end
		return false
	end
	function self.nightOpsRebuildIn(side: number): number
		local sd = self.sides[side]
		return if sd and sd.nvRebuildAt then math.max(0, sd.nvRebuildAt - self.time) else 0
	end
	function self.quietAtNight(kind: string, side: number): boolean
		if not self.nightOpsOn() then
			return false
		end
		local q = r.data["nightOps.quietNotices"] :: { string }?
		if not q or not table.find(q, kind) or self.nightAmount() < num("nightOps.blindFrom") then
			return false
		end
		return not self.nightVisionFor(side)
	end
	function self.switchNightOps(side: number, id: number, on: boolean): (boolean, string?)
		local st = self.entities[id]
		if not st or not st.alive or st.side ~= side then
			return false, "notOwned"
		end
		if st.kind ~= "nightops" then
			return false, "blocked"
		end
		st.nvOff = if on then nil else true
		return true, nil
	end
	-- the game's wQ: a side's sight multiplier now
	local function sightFactor(side: number): number
		local share = if not self.nightOpsOn() then num("daylight.nightSightShare")
			elseif self.nightVisionFor(side) then num("nightOps.nvSightShare") else num("nightOps.sightShare")
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
		local c = sightFactor(side)
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
		-- a garrisoned settlement sees max(cities.sight, its garrison's sight) (the game's AQe)
		for _, st in settlements do
			if st.owner == side and #st.garrison > 0 then
				local m = num("cities.sight")
				for _, id in st.garrison do
					local u = self.entities[id]
					if u then
						m = math.max(m, num(`units.{u.kind}.sight`))
					end
				end
				circle(st.x, st.y, m * c)
			end
		end
		local seen = {}
		local f = math.max(2, math.floor(num("match.cellScale") * 1.5 + 0.5))
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.side == side and not e.inside then
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
		-- the game's surveillanceOn (Owe): holding a secured capital shows all of the side's territory
		if self.surveillanceOn(side) then
			local owners = territory.update(baseSources())
			for i = 1, W * H do
				if owners[i] == side then
					grid[i] = 2
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
		-- a recon drone shows its scan circle while circling (x night) and a small trail where it flies
		local trail = num("intel.droneTrailRadius")
		for _, d in self.drones do
			if d.alive and d.side == side then
				if d.phase == "scan" then
					circle(d.tx, d.ty, d.radius * c)
				end
				if trail > 0 then
					circle(d.x, d.y, trail)
				end
			end
		end
		-- burning flares light flare.radius round them (the game's yge in its vision pass)
		for _, f in self.flares do
			if f.side == side and self.time >= f.burstAt and self.time < f.untilT then
				circle(f.x, f.y, f.r)
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

	-- the game's radars(): own finished buildings with a radar sweep (structures.<k>.radar), and
	-- secured radio-trait towns (cities.traits.radio.radar). APPROX: no radar boost, no power.
	function self.radarsOf(side: number): { { x: number, y: number, r: number } }
		local out = {}
		for _, st in self.list do
			if st.alive and st.cat == "structure" and st.side == side and (st.built or 1) >= 1 then
				local rr = numOr(`structures.{st.kind}.radar`, 0)
				if rr > 0 then
					local x, y = centre(st.cell)
					table.insert(out, { x = x, y = y, r = rr })
				end
			end
		end
		for _, st in settlements do
			if st.owner == side and st.trait == "radio" and traitActive(st) then
				table.insert(out, { x = st.x, y = st.y, r = num("cities.traits.radio.radar") })
			end
		end
		return out
	end
	-- the game's wwe: enemy units in a sweep grouped in chains of units within
	-- intel.radarClusterCells of each other; a group's strength comes from its members' capture
	-- values (air units count intel.radarAirControl): medium from radarMediumControl, heavy from
	-- radarHeavyControl.
	local function clusters(list: { Entity }): { { members: { Entity }, strength: string } }
		local n = math.max(1, num("intel.radarClusterCells"))
		local buckets: { [number]: { Entity } } = {}
		local function key(e: Entity, dx: number, dy: number): number
			return (math.floor(e.y / n) + dy) * 4096 + math.floor(e.x / n) + dx
		end
		for _, e in list do
			local k = key(e, 0, 0)
			buckets[k] = buckets[k] or {}
			table.insert(buckets[k], e)
		end
		local done: { [Entity]: boolean } = {}
		local out = {}
		for _, e in list do
			if done[e] then
				continue
			end
			local air = text(`units.{e.kind}.armour`) == "air"
			done[e] = true
			local group = { e }
			local control = 0
			local i = 1
			while i <= #group do
				local p = group[i]
				control += if air then num("intel.radarAirControl") else numOr(`units.{p.kind}.capture`, 0)
				for dy = -1, 1 do
					for dx = -1, 1 do
						local b = buckets[key(p, dx, dy)]
						if b then
							for _, k in b do
								if not done[k] and (text(`units.{k.kind}.armour`) == "air") == air and (k.x - p.x) ^ 2 + (k.y - p.y) ^ 2 <= n * n then
									done[k] = true
									table.insert(group, k)
								end
							end
						end
					end
				end
				i += 1
			end
			local strength = if control >= num("intel.radarHeavyControl") then "heavy"
				elseif control >= num("intel.radarMediumControl") then "medium" else "light"
			table.insert(out, { members = group, strength = strength })
		end
		return out
	end
	-- the game's ywe as the bot's knowledge uses it (eQe): enemy units inside its sweeps but out of
	-- sight on `vis`, one entry per group at the group's mean position.
	function self.contactGroups(side: number, vis: { number }?): { any }
		local radars = self.radarsOf(side)
		if #radars == 0 then
			return {}
		end
		local foes = {}
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK and e.side ~= side and e.side > 0 and not e.inside then
				local c = cellAt(e.x, e.y)
				local inSight = vis == nil or (c >= 0 and vis[c + 1] == 2)
				if not inSight then
					for _, rd in radars do
						if (e.x - rd.x) ^ 2 + (e.y - rd.y) ^ 2 <= rd.r * rd.r then
							table.insert(foes, e)
							break
						end
					end
				end
			end
		end
		local out = {}
		for _, g in clusters(foes) do
			local sx, sy = 0, 0
			for _, m in g.members do
				sx += m.x
				sy += m.y
			end
			table.insert(out, { x = sx / #g.members, y = sy / #g.members, strength = g.strength, count = #g.members })
		end
		return out
	end
	-- the game's jJe: radar contacts for a side, one per enemy unit (and truck, always light) inside
	-- any of its sweeps, with its group's strength; `seen` when that cell is in sight on `vis`.
	function self.contactsFor(side: number, vis: { number }?): { any }
		local radars = self.radarsOf(side)
		if #radars == 0 then
			return {}
		end
		local function swept(x: number, y: number): boolean
			for _, rd in radars do
				if (x - rd.x) ^ 2 + (y - rd.y) ^ 2 <= rd.r * rd.r then
					return true
				end
			end
			return false
		end
		local function seen(x: number, y: number): boolean
			local c = cellAt(x, y)
			return vis ~= nil and c >= 0 and vis[c + 1] == 2
		end
		local hz = num("match.tickHz")
		local foes, out = {}, {}
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.side ~= side and e.side > 0 and swept(e.x, e.y) then
				if e.kind == TRUCK then
					table.insert(out, { x = e.x, y = e.y, dx = 0, dy = 0, strength = "light", count = 1, seen = seen(e.x, e.y) })
				else
					table.insert(foes, e)
				end
			end
		end
		for _, g in clusters(foes) do
			for _, m in g.members do
				table.insert(out, { x = m.x, y = m.y, dx = (m.x - (m.px or m.x)) * hz, dy = (m.y - (m.py or m.y)) * hz,
					strength = g.strength, count = 1, seen = seen(m.x, m.y) })
			end
		end
		return out
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
