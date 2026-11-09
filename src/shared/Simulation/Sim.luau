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
	Production  paid up front (units.<k>.cost), units.<k>.buildSec each, production.maxQueue,
	            match.unitCap counts units plus queued.
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
	            (+/- combat.reloadJitter); the hit lands after the bullet flight (70 cells/s). Unit hit =
	            dps x reloadSec x vs[target armour] x (armour.movingFire if an armoured shooter moves)
	            x terrain cover (1 - cover, or flank rules when hit from behind combat.flankDeg)
	            x armour facing (armoured targets). Structure hit = dps x reloadSec x vs.structure.
	            Truck hit = dps x reloadSec x vs.armour. The HQ shoots too.
	HQ loss     a nation whose HQ dies with no factory and no command vehicle is eliminated at once
	            (all its units and buildings die, its rigs turn neutral and empty). The last nation
	            standing wins (match.victory "annihilation").

	APPROX: unit movement is straight-line (TEMP-002, no pathfinding/formations); trucks follow their
	        route cell by cell without the game's curve-following, column spacing, stalls or enemy holds;
	        unit spawn spots (door/rally) are simplified; the random numbers (reload jitter) do not
	        follow the game's seeded sequence; tie order between equally near targets may differ;
	        rig routes refresh every 10 ticks per rig.
	UNCONFIRMED: new units start with no face direction and an empty shot timer; a dead nation's
	        trucks are removed; a firing vehicle's hull keeps its heading (turrets not modelled).
	Not in the slice: fog (TEMP-001), line of sight, weather, veterancy, smoke, rig damage, upgrades,
	        settlements, refineries, rail, events, the real bot.
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
	movement: any, -- Shared.Simulation.Movement
	roadsLib: any, -- Shared.Simulation.Roads
	map: MapInfo,
	starts: { { x: number, y: number } }, -- cell centres
	rigs: { { x: number, y: number, name: string? } },
	seed: number?,
}

export type Event = { type: string, [string]: any }

local TRUCK = "truck"
local BULLET_SPEED = 70 -- cells/s, the game's bullet flight speed

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
			queue = {}, queueProgress = 0,
		})
		self.sides[side] = {
			oil = num("match.startOil"), hqId = hq.id, lost = false, trucksIdle = num("trucks.startIdle"),
			oilMult = 1, oilEarned = 0,
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
	-- APPROX: produced units appear production.rallyCells beyond the HQ footprint towards the map centre.
	local function rallyPoint(hq: Entity, slot: number): (number, number)
		local dx, dy = centerX - hq.x, centerY - hq.y
		local d = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
		local cells = hqFoot + num("production.rallyCells")
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
	function self.orderMove(side: number, ids: { number }, x: number, y: number): { number }
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.target, e.attackId = { x = x, y = y }, nil
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		return refused
	end

	function self.orderStop(side: number, ids: { number }): { number }
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if orderable(e, side) then
				e.target, e.attackId = nil, nil
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
				e.attackId, e.target = targetId, nil
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
				elseif e.queue and e.kind == "hq" then
					n += #e.queue
				end
			end
		end
		return n
	end

	function self.orderProduce(side: number, item: string): (boolean, string?)
		local s = self.sides[side]
		local hq = hqOf(side)
		if not s or s.lost or self.winner or not hq then
			return false, "blocked"
		end
		if item ~= "infantry" then
			return false, "blocked" -- the slice HQ trains infantry only (the game's HQ also lists engineer)
		end
		if #hq.queue >= num("production.maxQueue") then
			return false, "queueFull"
		end
		if unitsAndQueued(side) >= num("match.unitCap") then
			return false, "unitCap"
		end
		local cost = num(`units.{item}.cost`)
		if s.oil < cost then
			return false, "oil"
		end
		s.oil -= cost
		table.insert(hq.queue, item)
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

	---------------------------------------------------------------- elimination and damage

	local function eliminate(side: number, by: number)
		local s = self.sides[side]
		if not s or s.lost then
			return
		end
		s.lost = true
		for _, e in self.list do
			if e.alive and e.side == side and e.kind ~= "rig" then
				e.alive, e.hp = false, 0
				if e.kind == "hq" then
					e.queue = {}
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

	local function hitStructure(by: number, st: Entity, damage: number)
		if not st.alive then
			return
		end
		st.hp -= damage
		if st.hp > 0 then
			return
		end
		st.alive, st.hp = false, 0
		event({ type = "destroyed", id = st.id, kind = st.kind, side = st.side, by = by })
		if st.kind == "hq" then
			-- the slice has no factory and no command vehicle, so the nation cannot rehouse
			eliminate(st.side, by)
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

	local function hitUnit(target: Entity, dps: number, key: string, secs: number, by: number, fromX: number, fromY: number)
		local p = dps * vsOf(key, target.class) * secs
		local g = if target.class == "armour" then num(`armour.{armourSide(target, fromX, fromY)}`) else 0
		if target.class ~= "air" then
			local y = coverAt(cellAt(target.x, target.y))
			if flanked(target, fromX, fromY) then
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
		if target.hp <= 0 and target.alive then
			target.alive = false
			event({ type = "destroyed", id = target.id, kind = target.kind, side = target.side, by = by })
		end
	end

	local function hitTruck(t: Entity, dps: number, key: string, secs: number, by: number)
		t.hp -= dps * vsOf(key, "armour") * secs
		if t.hp <= 0 and t.alive then
			t.alive = false
			local rig = self.entities[t.from]
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
					hitUnit(t, s.dps, s.key, s.secs, s.by, s.fromX, s.fromY)
				elseif s.kind == "convoy" then
					hitTruck(t, s.dps, s.key, s.secs, s.by)
				else
					hitStructure(s.by, t, s.damage)
				end
			end
		end
	end

	---------------------------------------------------------------- combat

	local function d2(ax: number, ay: number, bx: number, by: number): number
		return (ax - bx) ^ 2 + (ay - by) ^ 2
	end

	local function validUnitTarget(side: number, o: Entity, key: string): boolean
		return o.alive and o.hp > 0 and o.cat == "unit" and o.kind ~= TRUCK and canAttack(side, o.side) and vsOf(key, o.class) > 0
	end

	local function nearestUnit(x: number, y: number, side: number, range: number, key: string): Entity?
		local best, bestD = nil, range * range
		for _, o in self.list do
			if validUnitTarget(side, o, key) then
				local d = d2(x, y, o.x, o.y)
				if d <= bestD then -- the game keeps the last of equally near targets
					best, bestD = o, d
				end
			end
		end
		return best
	end

	local function nearestTruck(x: number, y: number, side: number, range: number): Entity?
		local best, bestD = nil, range * range
		for _, o in self.list do
			if o.alive and o.kind == TRUCK and canAttack(side, o.side) then
				local d = d2(x, y, o.x, o.y)
				if d <= bestD then
					best, bestD = o, d
				end
			end
		end
		return best
	end

	local function nearestStructure(x: number, y: number, side: number, range: number, key: string): Entity?
		if vsOf(key, "structure") <= 0 then
			return nil
		end
		local best, bestW = nil, math.huge
		for _, o in self.list do
			if o.alive and o.cat == "structure" and o.kind ~= "rig" and canAttack(side, o.side) then
				local d = d2(x, y, o.x, o.y)
				if d <= range * range then
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

	local function flight(key: string, ax: number, ay: number, bx: number, by: number): number
		if text(key .. ".weapon") == "bullets" then
			return math.sqrt(d2(ax, ay, bx, by)) / BULLET_SPEED
		end
		return 0 -- UNCONFIRMED for other weapons (not in the slice)
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
		local strike: { [string]: any } = {
			kind = kind, at = self.time + flight(key, e.x, e.y, tx, ty), target = target.id, dps = dps,
			key = key, secs = secs, by = e.side, fromX = e.x, fromY = e.y,
		}
		if kind == "structure" then
			strike.damage = dps * vsOf(key, "structure") * secs
		end
		table.insert(self.strikes, strike)
	end

	local function structuresFire(dt: number)
		for _, st in self.list do
			if st.alive and st.kind == "hq" then
				local key = "structures.hq"
				local dps = num(key .. ".dps")
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

	local function unitsFire(dt: number)
		for _, e in self.list do
			if e.alive and e.hp > 0 and e.cat == "unit" and e.kind ~= TRUCK then
				local key = unitKey(e)
				local dps = num(key .. ".dps")
				if dps > 0 then
					local range = num(key .. ".range")
					-- armoured shooters fire weaker on the move
					local eff = dps * (if e.class == "armour" and e.moved then num("armour.movingFire") else 1)
					local focus: Entity? = nil
					if e.attackId then
						local t = self.entities[e.attackId]
						if not t or not t.alive then
							e.attackId = nil
						else
							local dist = math.sqrt(d2(e.x, e.y, t.x, t.y))
							if dist > range then
								-- APPROX of the game's attack think: close to attackRangeShare of range
								local k = 1 - (range * num("combat.attackRangeShare")) / dist
								e.target = { x = e.x + (t.x - e.x) * k, y = e.y + (t.y - e.y) * k }
							else
								e.target = nil
								focus = t
							end
						end
					end
					local unitTarget: Entity? = nil
					if focus then
						if focus.cat == "unit" and focus.kind ~= TRUCK then
							unitTarget = focus
						end
					else
						unitTarget = nearestUnit(e.x, e.y, e.side, range, key)
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
							truck = nearestTruck(e.x, e.y, e.side, range)
						end
						if truck then
							fire(e, key, truck, "convoy", eff, dt)
						else
							local st = if focus and focus.cat == "structure" then focus else nearestStructure(e.x, e.y, e.side, range, key)
							if st then
								fire(e, key, st, "structure", eff, dt)
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
				local cap = num("rigs.tank")
				if rig.tank >= cap then
					if not rig.full then
						rig.full = true
						event({ type = "rigFull", id = rig.id, side = rig.side })
					end
				else
					rig.full = false
					rig.rate = num("rigs.oilPerSec") * rig.rich
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

	local function production(dt: number)
		for side in self.sides do
			local hq = hqOf(side)
			if hq and #hq.queue > 0 then
				local item = hq.queue[1]
				hq.queueProgress += dt / math.max(0.01, num(`units.{item}.buildSec`))
				if hq.queueProgress >= 1 then
					hq.queueProgress = 0
					table.remove(hq.queue, 1)
					local x, y = rallyPoint(hq, self.nextId)
					local u = self.spawnUnit(item, side, x, y)
					event({ type = "unitReady", id = u.id, side = side, kind = item })
				end
			end
		end
	end

	function self.queueLeft(side: number): number?
		local hq = hqOf(side)
		if not hq or #hq.queue == 0 then
			return nil
		end
		return (1 - hq.queueProgress) * math.max(0.01, num(`units.{hq.queue[1]}.buildSec`))
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

	local moveCtx = {
		speedOf = function(kind: string): number
			return num(`units.{kind}.speed`)
		end,
		paceAt = paceAt,
	}

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
		landStrikes()
		structuresFire(dt)
		for _, e in self.list do
			if e.alive and e.cat == "unit" and e.kind ~= TRUCK then
				e.px, e.py, e.firing = e.x, e.y, false
				e.moved = deps.movement.step(e, dt, moveCtx)
			end
		end
		unitsFire(dt)
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
