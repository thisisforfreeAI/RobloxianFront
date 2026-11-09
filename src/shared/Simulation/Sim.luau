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
	local leaveGarrison: (Entity) -> ()
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
	-- Settlements (the game's hme): neutral at the start, captured like rigs (see settlementsTick).
	-- A held town, city or capital claims territory: its urban radius (the game's PV: the larger of
	-- settlements.<kind>Radius and the radius of a disc as big as the urban cells nearest it) plus
	-- cities.claim.margin.<kind>. Villages claim nothing.
	local settlements: { Entity } = {}
	for i, sd in deps.settlements or {} do
		local cx = math.clamp(math.floor(sd.x), 0, W - 1)
		local cy = math.clamp(math.floor(sd.y), 0, H - 1)
		local key = `settlements.{sd.kind}Radius`
		table.insert(settlements, {
			id = i, name = sd.name or "", kind = sd.kind, cell = cy * W + cx, x = cx + 0.5, y = cy + 0.5,
			radius = if r:has(key) then num(key) else 0, owner = 0, capture = nil, hold = 0, takenAt = -999,
			warnedAt = -99, urbanR = 0, garrison = {},
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
		e.repairId = nil -- any new order also ends a repair job (the game's clearOrders)
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
		s.oil -= unitCost(side, item)
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
		-- the game's zwe: its settlements turn neutral
		for _, st in settlements do
			if st.owner == side then
				st.owner, st.hold, st.capture, st.takenAt = 0, 0, nil, self.time
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
	-- the game's qat: the nearest enemy ground unit within r (ties to the lower id)
	local function nearestFoe(e: Entity, rr: number): Entity?
		local best, bestD = nil, rr * rr
		for _, o in self.list do
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
		target.hp -= p
		target.hitAt, target.hitBy = self.time, by
		if s > 0 then
			for _, b in self.list do
				if b ~= target and b.alive and b.cat == "unit" and b.kind ~= TRUCK and b.side == target.side
					and d2(b.x, b.y, target.x, target.y) <= s * s and vsOf(key, b.class) > 0 then
					b.hp -= p * 0.5 * (if b.inside and not target.inside then insideCover(b) else 1)
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
		if e.cat == "unit" then
			e.firedAt = self.time
		end
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

	local function unitsFire(dt: number)
		for _, e in self.list do
			if e.alive and e.hp > 0 and e.cat == "unit" and e.kind ~= TRUCK then
				local key = unitKey(e)
				local dps = num(key .. ".dps")
				if dps > 0 then
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
	-- Workforce: secured settlements speed all training by cities.workforce.<kind> (max workforceMax).
	-- Forward training (queueForward): a held, secured town or city trains cities.forward.trains
	-- (infantry, AT) itself; the queue waits while it is not secured and is refunded if it is lost.
	-- Not in the slice: the radio trait's radar and the airfield's air drop (no radar or air units yet),
	-- integrity damage.
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
				local speed = num("convoys.speed") * num("trucks.kinds.light.paceShare") * railPace(t.side, t.x, t.y)
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
						st.queueProgress += dt / buildTime(st.side, item)
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
		for _, b in self.list do
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
					local fromX, fromY, fromIndex = e.x, e.y, e.pathIndex
					e.moved = pathing.step(e, dt)
					if e.moved and holdAtEnemy(e, fromX, fromY) then
						e.x, e.y, e.pathIndex, e.moved = fromX, fromY, fromIndex, false
						e.pace = 0
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
		rigs(dt)
		settlementsTick(dt)
		forwardTick(dt)
		cityHealing(dt)
		repairsTick(dt)
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
