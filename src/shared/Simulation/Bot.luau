--!strict
--[[
	Bot: WarFront's skirmish bot, ported from the game's own code for the parts the slice has
	(HQ production, trucks, rig upgrades, rigs, the army). It plays through the same order
	functions as a player. Personas (balanced / turtle / warlord) and every tuning value come from
	the generated match rules (bots.*, bots.personaDefaults.*, skirmish.difficulty.*).

	Think: first think 0.5 + 0.37 x nation index seconds in, then every
	bots.thinkSec x difficulty think (x warlord edge) x (0.8 .. 1.2). Each think, in the game's order:
	  trucks    every connected rig without a truck gets one (idle first, then bought); then more trucks
	            while hauling capacity < pump rate x bots.truckFill (keeping bots.truckReserve oil once a
	            rig has bots.truckSaveFor trucks); then tank upgrades where a round trip outpumps
	            tankTripShare of the tank; then a pump upgrade on the richest rig with 2+ trucks once oil
	            >= bots.upgradeOil. While saving for a truck it trains nothing.
	  building  the build order (Pst: barracks, factory, a bunker at the nearest rig it does not own,
	            barracks, radar (skipped), factory), then home guards after 300 s (bunker or AT gun
	            50/50 near the HQ while fewer than round(homeGuards x (0.5 + persona defence)) armed
	            buildings stand there), then rig guards after 180 s (bunker 60% / AT gun at far rigs).
	  training  producers factory, barracks, HQ (queue < 2). HQ: an engineer when the army is 4+ and it
	            has fewer than bots.engineers (every bots.engineerEverySec), otherwise infantry while it
	            has no barracks or the army is under 8. Barracks (while foot units are under half the
	            army): AT 30%, mortar bots.mortarShare x (0.5 + defence), else infantry. Factory: a scout
	            (army >= scoutArmy, every scoutEverySec, up to round(army x scoutShare)), else tank 45%,
	            IFV 30%, artillery 13% (the rocket 12% trains nothing: not in the slice).
	  scouts    an idle scout near an enemy HQ (scoutStandOff x 1.6) deploys for recon; otherwise
	            sometimes (scoutSendChance) drives to scoutStandOff short of one.
	  fall back groups under strong threat (influence map) retreat to the nearest safe own point.
	  idle army one idle unit stays at each own rig; the persona's home share (max bots.homeKeepMax)
	            stays nearest the HQ; unfinished orders are re-sent up to 3 times.
	  defence   threatened HQ/rigs (threat >= guardMinThreat and own strength < threat x guardRatio)
	            and rigs under capture get enough units to answer the threat.
	  attack    after bots.assaultAfter: a push on the cheapest enemy HQ when strong enough, or with
	            bots.pushMinForce once the push timer runs out (needs bots.assaultPool idle units);
	            otherwise the best-scoring rig (neutral rigs only before bots.graceSec) or, after
	            bots.cityAfter, settlement (cityValue x (0.5 + defence) for neutral ones, scored down by
	            distance from its army and from home; at most cityHeld / maxOccupied x (0.5 + defence)).
	Unit worth = hp / 100 x dps / 8 x 30. Influence map: blocks of 6 x cell scale, reach 14 x cell scale.

	Intel: like the game's bots (intel.fog and bots.fog are on) it sees only with its own vision and
	remembers what it saw (see the intel section); an unseen enemy HQ counts at least
	bots.unknownHqDefence and an unseen rig bots.unknownDefence. Not in the slice, so skipped: SAM, radar, night ops, artillery base, naval yard,
	forward HQ, engineers' work, drones, rocket barrages, garrisons and the capital, bridges, rail, naval,
	events, sabotage.
	APPROX: the bot's random numbers are not the game's sequence; held-truck rescues are skipped
	(trucks are never held by enemies in the slice). UNCONFIRMED: which persona a lobby slot defaults to
	(MatchService picks one).
]]
local Bot = {}

export type Persona = { id: string, attackMargin: number, home: number, defence: number, raid: number }

function Bot.new(sim: any, side: number, personaId: string?, level: string?)
	local num = sim.num
	local rules = sim.deps.rules
	local pid = personaId or "balanced"
	if not rules:has(`bots.personaDefaults.{pid}.attackMargin`) then
		pid = "balanced"
	end
	local persona: Persona = {
		id = pid,
		attackMargin = num(`bots.personaDefaults.{pid}.attackMargin`),
		home = num(`bots.personaDefaults.{pid}.home`),
		defence = num(`bots.personaDefaults.{pid}.defence`),
		raid = num(`bots.personaDefaults.{pid}.raid`),
	}
	local lvl = level or "normal"
	local levelOil = num(`skirmish.difficulty.{lvl}.oil`)
	local diff = {
		think = num(`skirmish.difficulty.{lvl}.think`),
		margin = num(`skirmish.difficulty.{lvl}.margin`),
		buildDelay = num(`skirmish.difficulty.{lvl}.buildDelay`),
	}
	if pid == "warlord" then
		diff.think *= num("bots.warlordEdge.think")
		diff.margin *= num("bots.warlordEdge.margin")
		diff.buildDelay *= num("bots.warlordEdge.buildDelay")
	end
	-- the nation's oil multiplier: handicap (middle = x1) x difficulty oil, and x warlordEdge.oil for a
	-- warlord (the game applies that edge when crediting oil)
	if sim.sides[side] then
		local handicap = rules.data["skirmish.handicap"] :: { number }
		sim.sides[side].oilMult = handicap[2] * levelOil * (if pid == "warlord" then num("bots.warlordEdge.oil") else 1)
	end

	local seed = 9301 + side * 49297
	local function rand(): number -- APPROX: not the game's sequence
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end

	local self = {
		side = side,
		persona = persona,
		nextThink = sim.time + 0.5 + (side - 1) * 0.37,
		orders = {} :: { [number]: { kind: string, id: number } },
		resent = {} :: { [number]: number },
		avoid = {} :: { [string]: number },
		covering = {} :: { [string]: number },
		nextPush = -1,
		lastEngineer = -999,
		lastScout = -999,
		lastBuild = -99,
		inf = nil :: any,
	}

	local function scaled(x: number): number
		return x * num("match.cellScale")
	end
	local function text(key: string): string
		return rules:text(key)
	end
	local function key(t: { kind: string, id: number }): string
		return `{t.kind}:{t.id}`
	end
	local function canAttack(a: number, b: number): boolean
		return a ~= b and a > 0 and b > 0
	end
	local function hypot(x: number, y: number): number
		return math.sqrt(x * x + y * y)
	end

	-- worth of a unit type (zg / Nbe) and of a structure with its hp (KQ / u0e)
	local function unitWorth(kind: string): number
		local dps = num(`units.{kind}.dps`)
		if dps <= 0 then
			return 0
		end
		return num(`units.{kind}.hp`) / 100 * (dps / 8) * 30
	end
	local function structureWorth(kind: string, hp: number): number
		local dps = num(`structures.{kind}.dps`)
		if dps <= 0 then
			return 0
		end
		local vs = math.max(num(`structures.{kind}.vs.soft`), num(`structures.{kind}.vs.armour`), 0.3)
		return hp / 100 * (dps * vs / 8) * 30
	end

	---------------------------------------------------------------- intel (the game's bot intel, eQe)

	-- The game's bots play with fog (intel.fog and bots.fog): each think they look with their own
	-- vision and remember enemy units for intel.unitIntelSec, enemy buildings until seen gone (an
	-- enemy HQ is always known), rig owners as last seen, and when each 8 x 8 cell block was last seen.
	local MW, MH = sim.roads.width, sim.roads.height
	local IB = 8
	local ibw = math.ceil(MW / IB)
	local intel = {
		vis = table.create(MW * MH, 0) :: { number },
		seenAt = table.create(ibw * math.ceil(MH / IB), -math.huge) :: { number },
		units = {} :: { [number]: { kind: string, owner: number, x: number, y: number, t: number } },
		structures = {} :: { [number]: { kind: string, owner: number, cell: number, hp: number, built: number, t: number } },
		rigs = {} :: { [number]: number },
		cities = {} :: { [number]: number }, -- settlement id -> owner last seen (0 = neutral)
		cityStatus = {} :: { [number]: string }, -- settlement id -> status last seen
	}
	self.intel = intel
	local fogged = sim.fogOn() and rules:has("bots.fog") and rules:flag("bots.fog")
	local function updateIntel()
		local now = sim.time
		local vis = intel.vis
		if fogged then
			sim.visionFor(side, vis)
		else
			for i = 1, MW * MH do
				vis[i] = 2
			end
		end
		for f = 0, MW * MH - 1 do
			if vis[f + 1] == 2 then
				intel.seenAt[(f // MW // IB) * ibw + (f % MW) // IB + 1] = now
			end
		end
		local function seen(c: number): boolean
			return c >= 0 and vis[c + 1] == 2
		end
		local now_ = {}
		for _, e in sim.list do
			if e.alive and e.cat == "unit" and e.kind ~= "truck" and canAttack(side, e.side) then
				if seen(sim.roads.cellAt(e.x, e.y)) then
					intel.units[e.id] = { kind = e.kind, owner = e.side, x = e.x, y = e.y, t = now }
					now_[e.id] = true
				end
			end
		end
		local keep = num("intel.unitIntelSec")
		for id, p in intel.units do
			if not now_[id] and (now - p.t > keep or seen(sim.roads.cellAt(p.x, p.y))) then
				intel.units[id] = nil
			end
		end
		for id, p in intel.structures do
			local e = sim.entities[id]
			if (not e or not e.alive) and seen(p.cell) then
				intel.structures[id] = nil
			end
		end
		for _, e in sim.list do
			if e.alive and e.cat == "structure" then
				if e.kind == "rig" then
					if seen(e.cell) then
						intel.rigs[e.id] = e.side
					end
				elseif e.side ~= side and (seen(e.cell) or e.kind == "hq") then
					intel.structures[e.id] = { kind = e.kind, owner = e.side, cell = e.cell, hp = e.hp, built = e.built or 1, t = now }
				end
			end
		end
		for _, st in sim.settlements do
			if seen(st.cell) then
				intel.cities[st.id] = st.owner
				intel.cityStatus[st.id] = sim.cityStatus(st)
			end
		end
	end
	-- the game's uf: was the block around (x, y) seen within bots.staleSec?
	local function fresh(x: number, y: number): boolean
		local bx = math.clamp(math.floor(x / IB), 0, ibw - 1)
		local by = math.clamp(math.floor(y / IB), 0, math.ceil(MH / IB) - 1)
		return sim.time - intel.seenAt[by * ibw + bx + 1] <= num("bots.staleSec")
	end
	-- the game's M4: a rig's owner as the bot knows it (-1 = neutral or never seen)
	local function rigOwner(r: any): number
		if r.side == side then
			return side
		end
		local n = intel.rigs[r.id]
		if n == nil then
			return -1
		end
		if n == side then
			n = r.side
		end
		return if n > 0 then n else -1
	end
	-- the game's Mk: a settlement's owner as the bot knows it (-1 = neutral or never seen)
	local function cityOwner(st: any): number
		if st.owner == side then
			return side
		end
		local n = intel.cities[st.id]
		if n == nil then
			return -1
		end
		if n == side then
			n = st.owner
		end
		return if n > 0 then n else -1
	end
	-- an order's target: settlements by their own id, everything else by entity id
	local function orderTarget(t: { kind: string, id: number }): any
		if t.kind == "city" then
			return sim.settlements[t.id]
		end
		return sim.entities[t.id]
	end

	local function isArmy(e: any): boolean
		if not e.alive or e.cat ~= "unit" or e.kind == "truck" or e.garrisonCity then
			return false -- garrisons (inside or on their way) are not army (the game's Ik)
		end
		local k = `units.{e.kind}`
		return num(k .. ".dps") > 0 and text(k .. ".armour") ~= "air" and text(k .. ".nato") ~= "recon" and text(k .. ".move") ~= "sea"
	end
	local function army(): { any }
		local out = {}
		for _, e in sim.list do
			if e.side == side and isArmy(e) then
				table.insert(out, e)
			end
		end
		return out
	end
	local garrisonWanted: () -> number
	local function idle(e: any): boolean
		return e.target == nil and e.attackId == nil
	end
	local function myRigs(): { any }
		local out = {}
		for _, r in sim.rigs do
			if r.side == side then
				table.insert(out, r)
			end
		end
		return out
	end
	local function enemyStructures(): { any }
		local out = {}
		for _, e in sim.list do
			if e.alive and e.cat == "structure" and e.kind ~= "rig" and canAttack(side, e.side) then
				table.insert(out, e)
			end
		end
		return out
	end

	---------------------------------------------------------------- influence map (vst)

	local function buildInfluence()
		local block = math.max(1, math.floor(scaled(num("bots.influence.blockCells")) + 0.5))
		local reach = scaled(num("bots.influence.reachCells"))
		local w = math.ceil(sim.deps.map.width / block)
		local h = math.ceil(sim.deps.map.height / block)
		local inf = { w = w, h = h, block = block, mine = table.create(w * h, 0), threat = table.create(w * h, 0) }
		local function add(grid: { number }, x: number, y: number, s: number)
			if s <= 0 then
				return
			end
			local i, l, c = x / block, y / block, reach / block
			local x0, x1 = math.max(0, math.floor(i - c)), math.min(w - 1, math.floor(i + c))
			local y0, y1 = math.max(0, math.floor(l - c)), math.min(h - 1, math.floor(l + c))
			for p = y0, y1 do
				local g = p + 0.5 - l
				for m = x0, x1 do
					local yy = m + 0.5 - i
					local d = math.sqrt(yy * yy + g * g) * block
					if d < reach then
						grid[p * w + m + 1] += s * (1 - d / reach)
					end
				end
			end
		end
		for _, e in sim.list do
			if e.alive and e.cat == "unit" and e.kind ~= "truck" then
				local k = `units.{e.kind}`
				local usable = text(k .. ".armour") ~= "air" and text(k .. ".move") ~= "sea"
				if e.side == side and usable and num(k .. ".dps") > 0 then
					add(inf.mine, e.x, e.y, unitWorth(e.kind) * math.clamp(e.hp / math.max(1, e.maxHp), 0, 1))
				end
			elseif e.alive and e.cat == "structure" and e.kind ~= "rig" and e.side == side and (e.built or 1) >= 1 then
				add(inf.mine, e.x, e.y, structureWorth(e.kind, e.hp))
			end
		end
		-- threat: what the bot knows (remembered units count memoryShare once older than memorySec)
		local memSec, memShare = num("bots.influence.memorySec"), num("bots.influence.memoryShare")
		for _, u in intel.units do
			local k = `units.{u.kind}`
			if canAttack(side, u.owner) and text(k .. ".armour") ~= "air" and text(k .. ".move") ~= "sea" then
				add(inf.threat, u.x, u.y, unitWorth(u.kind) * (if sim.time - u.t > memSec then memShare else 1))
			end
		end
		for _, st in intel.structures do
			if canAttack(side, st.owner) then
				add(inf.threat, st.cell % MW + 0.5, st.cell // MW + 0.5, structureWorth(st.kind, st.hp))
			end
		end
		return inf
	end
	local function cellOf(inf: any, x: number, y: number): number
		local n = math.clamp(math.floor(x / inf.block), 0, inf.w - 1)
		return math.clamp(math.floor(y / inf.block), 0, inf.h - 1) * inf.w + n + 1
	end
	local function threatAt(x: number, y: number): number
		return self.inf.threat[cellOf(self.inf, x, y)]
	end
	local function mineAt(x: number, y: number): number
		return self.inf.mine[cellOf(self.inf, x, y)]
	end
	-- highest threat along the way from (x0, y0) to within a of (x1, y1) (kst)
	local function approach(x0: number, y0: number, x1: number, y1: number, a: number): number
		local r = hypot(x1 - x0, y1 - y0)
		local i = r - a
		if i <= 0 then
			return 0
		end
		local steps = math.max(1, math.ceil(i / self.inf.block))
		local c = 0
		for k = 0, steps do
			local u = i * k / steps / r
			c = math.max(c, threatAt(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u))
		end
		return c
	end
	-- enemy strength near a point, from intel (H5): remembered units and known buildings
	local function enemyNear(x: number, y: number, radius: number): number
		local r2 = radius * radius
		local total = 0
		for _, u in intel.units do
			if canAttack(side, u.owner) and (u.x - x) ^ 2 + (u.y - y) ^ 2 <= r2 then
				total += unitWorth(u.kind)
			end
		end
		for _, st in intel.structures do
			if canAttack(side, st.owner) and (st.cell % MW + 0.5 - x) ^ 2 + (st.cell // MW + 0.5 - y) ^ 2 <= r2 then
				total += structureWorth(st.kind, st.hp)
			end
		end
		return total
	end
	local function marginH(): number
		return persona.attackMargin * diff.margin
	end

	-- send the nearest units, enough to meet `need` (Ef)
	local function dispatch(pool: { any }, target: { kind: string, id: number }, x: number, y: number, need: number): boolean
		if #pool == 0 then
			return false
		end
		table.sort(pool, function(a, b)
			return hypot(a.x - x, a.y - y) < hypot(b.x - x, b.y - y)
		end)
		local ids, sum = {}, 0
		for _, u in pool do
			table.insert(ids, u.id)
			sum += unitWorth(u.kind)
			if sum >= math.max(need, 30) * 1.3 and #ids >= 2 then
				break
			end
		end
		if sum < need then
			return false
		end
		sim.orderMove(side, ids, x, y)
		local chosen = {}
		for _, id in ids do
			self.orders[id] = target
			self.resent[id] = nil
			chosen[id] = true
		end
		for i = #pool, 1, -1 do
			if chosen[pool[i].id] then
				table.remove(pool, i)
			end
		end
		return true
	end

	local function targetValid(t: { kind: string, id: number }): boolean
		if t.kind == "city" then
			local st = sim.settlements[t.id]
			if not st then
				return false
			end
			local o = cityOwner(st)
			return o ~= side and (o < 0 or canAttack(side, o))
		end
		local e = sim.entities[t.id]
		if not e or not e.alive then
			return false
		end
		if t.kind == "rig" then
			local o = rigOwner(e)
			return o ~= side and (o < 0 or canAttack(side, o))
		end
		return canAttack(side, e.side)
	end

	---------------------------------------------------------------- trucks ($st)

	local function trucks(): boolean
		local s = sim.sides[side]
		local rigs = {}
		for _, r in myRigs() do
			if r.connected and sim.time - (r.truckLostAt or -math.huge) >= num("bots.truckLossHoldSec") then
				table.insert(rigs, r)
			end
		end
		local saving = false
		for _, r in rigs do
			if sim.trucksOf(r.id) == 0 then
				local ok, why = sim.orderTruck(side, r.id)
				if ok then
					return false
				end
				if why == "oil" then
					saving = true
				end
			end
		end
		if saving then
			return true
		end
		local cap = num("trucks.kinds.light.capacity")
		local cost = num("trucks.kinds.light.cost")
		for _, r in rigs do
			local trip = sim.tripTime(r)
			if trip < math.huge then
				local f = sim.trucksOf(r.id)
				local haul = f * cap / math.max(1, trip)
				if not (f >= num("trucks.perRig") or haul >= sim.pumpRate(r) * num("bots.truckFill")) then
					local hasIdle = s.trucksIdle > 0
					local early = f < num("bots.truckSaveFor")
					if not hasIdle and s.oil < cost + (if early then 0 else num("bots.truckReserve")) then
						if early then
							saving = true
						end
					elseif sim.orderTruck(side, r.id) then
						return false
					end
				end
			end
		end
		if saving then
			return true
		end
		for _, r in rigs do
			local perTrip = sim.pumpRate(r) * sim.tripTime(r)
			if not (r.tankLevel or perTrip <= sim.tankSize(r) * num("bots.tankTripShare") or s.oil < num("rigs.upgrades.tank.cost") + num("bots.truckReserve")) then
				if sim.upgradeRig(side, r.id, "tank") then
					return false
				end
			end
		end
		if s.oil < num("bots.upgradeOil") then
			return false
		end
		local cands = {}
		for _, r in rigs do
			if not r.pumpLevel and sim.trucksOf(r.id) >= 2 then
				table.insert(cands, r)
			end
		end
		table.sort(cands, function(a, b)
			if a.rich ~= b.rich then
				return a.rich > b.rich
			end
			return a.id < b.id
		end)
		if cands[1] then
			sim.upgradeRig(side, cands[1].id, "pump")
		end
		return false
	end

	---------------------------------------------------------------- training (Bst, HQ only in the slice)

	---------------------------------------------------------------- building (Dst, Vst)

	-- the game's build order (bots Pst): type, after (s x buildDelay), minimum income (oil/s)
	local BUILD_ORDER = {
		{ type = "barracks", after = 15, minIncome = 0 },
		{ type = "factory", after = 200, minIncome = 3.5 },
		{ type = "bunker", after = 260, minIncome = 3.5 },
		{ type = "barracks", after = 420, minIncome = 6 },
		{ type = "radar", after = 480, minIncome = 6 },
		{ type = "factory", after = 600, minIncome = 7 },
	}
	local function countOf(kind: string): number
		local n = 0
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "structure" and e.kind == kind then
				n += 1
			end
		end
		return n
	end
	local function income(): number
		local n = 0
		for _, r in sim.rigs do
			if r.side == side and r.connected and (r.rate or 0) > 0 then
				n += r.rate
			end
		end
		return n
	end

	-- armed buildings of this nation (not the HQ) within reach of a point, built or not (Dst's d)
	local function guardsNear(x: number, y: number, reach: number): number
		local n = 0
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "structure" and e.kind ~= "hq" and e.kind ~= "rig"
				and num(`structures.{e.kind}.dps`) > 0 and (e.x - x) ^ 2 + (e.y - y) ^ 2 <= reach * reach then
				n += 1
			end
		end
		return n
	end

	-- Dst: what to build next. APPROX: kinds the slice cannot place (radar, SAM, night ops, artillery
	-- base, naval yard, forward HQ) are passed over.
	local function plan(): any
		local hq = sim.hqOf(side)
		if not hq then
			return nil
		end
		local W = sim.roads.width
		local ax, ay = hq.cell % W + 0.5, hq.cell // W + 0.5
		local hqReach = num("structures.hq.buildRadius")
		local seen: { [string]: number } = {}
		local inc = income()
		for _, g in BUILD_ORDER do
			seen[g.type] = (seen[g.type] or 0) + 1
			if countOf(g.type) < seen[g.type] then
				if sim.time < g.after * diff.buildDelay or inc < g.minIncome then
					break
				end
				if g.type == "bunker" then
					-- at the nearest rig this nation does not own (the game's sort is stable)
					local best, bestD = nil, math.huge
					for _, rg in sim.rigs do
						if rg.side ~= side then
							local d = hypot(rg.x - ax, rg.y - ay)
							if d < bestD then
								best, bestD = rg, d
							end
						end
					end
					if best then
						return { type = "bunker", near = { x = best.x, y = best.y }, reach = math.huge }
					end
				elseif sim.PLACEABLE[g.type] then
					return { type = g.type, near = { x = ax, y = ay }, reach = hqReach }
				end
			end
		end
		-- home guards, then rig guards (bots.homeGuards / rigGuards x (0.5 + persona defence))
		local f = math.floor(num("bots.homeGuards") * (0.5 + persona.defence) + 0.5)
		if sim.time > 300 and guardsNear(ax, ay, hqReach) < f then
			return { type = if rand() < 0.5 then "bunker" else "atgun", near = { x = ax, y = ay }, reach = hqReach }
		end
		local pr = math.floor(num("bots.rigGuards") * (0.5 + persona.defence) + 0.5)
		if sim.time > 180 and pr > 0 then
			local pad = num("territory.rigPad")
			for _, rg in sim.rigs do
				if rg.side == side and hypot(rg.x - ax, rg.y - ay) >= hqReach and guardsNear(rg.x, rg.y, pad) < pr then
					return { type = if rand() < 0.6 then "bunker" else "atgun", near = { x = rg.x, y = rg.y }, reach = pad }
				end
			end
		end
		return nil
	end

	-- Vst: up to 120 random points in the nation's base sources. A spot with unlimited reach takes the
	-- valid point nearest its target; a facility the one nearest the HQ (plus up to 3 cells x cell scale
	-- of noise); a defence the one closest to 2.5 cells x cell scale from what it guards (plus up to 2).
	local function placeBuilding(p: any)
		if not p then
			return
		end
		local cost = num(`structures.{p.type}.cost`)
		if sim.sides[side].oil < cost or sim.time - self.lastBuild < 4 then
			return
		end
		local W, H = sim.roads.width, sim.roads.height
		local sources = sim.baseSources(side)
		local hq = sim.hqOf(side)
		local cx = if hq then hq.cell % W + 0.5 else p.near.x
		local cy = if hq then hq.cell // W + 0.5 else p.near.y
		local scale = num("match.cellScale")
		local best, bestScore = -1, math.huge
		for _ = 1, 120 do
			local f = sources[math.floor(rand() * #sources) + 1]
			if not f then
				break
			end
			local ang = rand() * math.pi * 2
			local g = math.sqrt(rand()) * f.r
			local m, y = f.x + math.cos(ang) * g, f.y + math.sin(ang) * g
			if hypot(m - p.near.x, y - p.near.y) <= p.reach then
				local w = math.floor(y) * W + math.floor(m)
				if m >= 0 and y >= 0 and m < W and y < H and sim.territoryAt(w) == side and not sim.canPlace(side, p.type, w) then
					local score
				if p.reach == math.huge then
					score = hypot(m - p.near.x, y - p.near.y)
				elseif sim.deps.rules:text(`structures.{p.type}.kind`) == "facility" then
					score = hypot(m - cx, y - cy) + rand() * 3 * scale
				else
					-- a defence: about 2.5 cells (x cell scale) out from the point it guards
					score = math.abs(hypot(m - p.near.x, y - p.near.y) - 2.5 * scale) + rand() * 2 * scale
				end
					if score < bestScore then
						best, bestScore = w, score
					end
				end
			end
		end
		if best >= 0 and sim.placeStructure(side, p.type, best) then
			self.lastBuild = sim.time
		end
	end

	---------------------------------------------------------------- training (Bst)

	---------------------------------------------------------------- garrisons (Wbe, uat, dat)

	-- free garrison slots: cities.garrisonFull.<kind> - inside - walking (the game's qI)
	local function citySlots(st: any): number
		return num(`cities.garrisonFull.{st.kind}`) - #st.garrison - sim.garrisonWalking(st)
	end
	-- own settlements, most valuable first, then fewest free slots, then id (the game's zV)
	local function myCities(): { any }
		local out = {}
		for _, st in sim.settlements do
			if st.owner == side then
				table.insert(out, st)
			end
		end
		table.sort(out, function(a, b)
			local va, vb = num(`bots.cityValue.{a.kind}`), num(`bots.cityValue.{b.kind}`)
			if va ~= vb then
				return va > vb
			end
			local sa, sb = citySlots(a), citySlots(b)
			if sa ~= sb then
				return sa < sb
			end
			return a.id < b.id
		end)
		return out
	end
	-- garrisoned men outside the capital, and the cap: (army + them) x bots.garrisonShare x (0.5 + defence)
	local function garrisonCap(): (number, number)
		local capital = nil
		for _, st in sim.settlements do
			if st.kind == "capital" then
				capital = st.id
				break
			end
		end
		local inside = 0
		for _, e in sim.list do
			if e.alive and e.side == side and e.garrisonCity and e.garrisonCity ~= capital then
				inside += 1
			end
		end
		return inside, math.floor((#army() + inside) * num("bots.garrisonShare") * (0.5 + persona.defence))
	end
	-- men still wanted for garrisons (the game's uat): barracks train infantry while idle men fall short
	function garrisonWanted(): number
		local list = myCities()
		if #list == 0 then
			return 0
		end
		local inside, cap = garrisonCap()
		local room, n = math.max(0, cap - inside), 0
		for _, st in list do
			local c = math.max(0, citySlots(st))
			local h = if st.kind == "capital" then c else math.min(c, room)
			n += h
			if st.kind ~= "capital" then
				room -= h
			end
		end
		return n
	end
	-- the game's dat: send the nearest idle infantry / AT (within bots.garrisonReach; any distance for
	-- the capital) into own settlements with free slots, up to the cap
	local function garrison(pool: { any })
		local list = myCities()
		if #list == 0 then
			return
		end
		local inside, cap = garrisonCap()
		local reach = scaled(num("bots.garrisonReach"))
		for _, st in list do
			local capital = st.kind == "capital"
			if inside < cap or capital then
				local d = citySlots(st)
				if d > 0 then
					local cands = {}
					for _, u in pool do
						if sim.canGarrison(u) and (capital or hypot(u.x - st.x, u.y - st.y) <= reach) then
							table.insert(cands, u)
						end
					end
					table.sort(cands, function(a, b)
						local da, db = hypot(a.x - st.x, a.y - st.y), hypot(b.x - st.x, b.y - st.y)
						if da ~= db then
							return da < db
						end
						return a.id < b.id
					end)
					local take = if capital then d else math.min(d, cap - inside)
					local ids = {}
					for i = 1, math.min(take, #cands) do
						table.insert(ids, cands[i].id)
					end
					if #ids > 0 then
						local n = sim.orderGarrison(side, st.id, ids)
						if n > 0 then
							if not capital then
								inside += n
							end
							for i = #pool, 1, -1 do
								if pool[i].garrisonCity then
									table.remove(pool, i)
								end
							end
						end
					end
				end
			end
		end
	end

	local PRIORITY = { factory = 1, barracks = 2, hq = 3 }
	local function training(p: any)
		local counts: { [string]: number } = {}
		local idleMen = 0 -- idle units that could garrison (the game's r)
		local menKinds = sim.deps.rules.data["cities.garrisonUnits"] :: { string }? or {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "unit" and e.kind ~= "truck" and not e.garrisonCity then
				counts[e.kind] = (counts[e.kind] or 0) + 1
				if idle(e) and table.find(menKinds, e.kind) then
					idleMen += 1
				end
			end
		end
		local menShort = idleMen < garrisonWanted()
		local producers = {}
		for _, st in sim.list do
			if st.alive and st.side == side and st.cat == "structure" and st.queue then
				for _, item in st.queue do
					counts[item] = (counts[item] or 0) + 1
				end
				if #st.queue < 2 and not sim.inactiveReason(st) and PRIORITY[st.kind] then
					table.insert(producers, st)
				end
			end
		end
		local function c(k: string): number
			return counts[k] or 0
		end
		local h = #army()
		local reserve = 0
		if p and sim.deps.rules:text(`structures.{p.type}.kind`) == "facility" then
			reserve = num(`structures.{p.type}.cost`) * num("bots.buildReserve")
		end
		local hasFactory = sim.hasBuilding(side, "factory", true)
		local hasBarracks = sim.hasBuilding(side, "barracks", true)
		local position = {}
		for i, st in producers do
			position[st] = i
		end
		table.sort(producers, function(a, b)
			if PRIORITY[a.kind] ~= PRIORITY[b.kind] then
				return PRIORITY[a.kind] < PRIORITY[b.kind]
			end
			return position[a] < position[b]
		end)
		for _, st in producers do
			local item: string? = nil
			local k = rand()
			local footShort = not hasFactory or c("infantry") + c("at") + c("mortar") < h * 0.5
			if st.kind == "hq" then
				if h >= 4 and c("engineer") < num("bots.engineers") and sim.time - self.lastEngineer >= num("bots.engineerEverySec") then
					item = "engineer"
				elseif not hasBarracks or h < 8 then
					item = "infantry"
				end
			elseif st.kind == "barracks" then
				if menShort then
					item = "infantry" -- men for the garrisons
				elseif footShort then
					local mortarShare = num("bots.mortarShare") * (0.5 + persona.defence)
					item = if k < 0.3 then "at" elseif k < 0.3 + mortarShare then "mortar" else "infantry"
				end
			elseif st.kind == "factory" then
				-- a scout once the army is bots.scoutArmy, up to round(army x scoutShare) (max intel.scoutMax),
				-- one per bots.scoutEverySec; otherwise the usual pick. APPROX: rocket artillery is not in
				-- the slice, so its pick trains nothing.
				local maxScouts = math.min(num("intel.scoutMax"), math.max(1, math.floor(h * num("bots.scoutShare") + 0.5)))
				if h >= num("bots.scoutArmy") and c("scout") < maxScouts and sim.time - self.lastScout >= num("bots.scoutEverySec") then
					item = "scout"
				else
					item = if k < 0.45 then "tank" elseif k < 0.75 then "ifv" elseif k < 0.88 then "artillery" else nil
				end
			end
			if item and sim.sides[side].oil - num(`units.{item}.cost`) >= reserve then
				if sim.orderProduce(side, item, st.id) then
					counts[item] = c(item) + 1
					if item == "engineer" then
						self.lastEngineer = sim.time
					elseif item == "scout" then
						self.lastScout = sim.time
					elseif item == "infantry" then
						idleMen += 1
						menShort = idleMen < garrisonWanted()
					end
				end
			end
		end
	end

	---------------------------------------------------------------- fall back (rat)

	local function fallBack()
		if not next(self.orders) then
			return
		end
		local groups: { [string]: { t: any, units: { any } } } = {}
		local order = {}
		for id, t in self.orders do
			local u = sim.entities[id]
			if u and u.alive and targetValid(t) then
				local k = key(t)
				if not groups[k] then
					groups[k] = { t = t, units = {} }
					table.insert(order, k)
				end
				table.insert(groups[k].units, u)
			end
		end
		if #order == 0 then
			return
		end
		local i = num("bots.influence.fallBack") * (1.5 / persona.attackMargin)
		local points = {}
		local hq = sim.hqOf(side)
		if hq then
			table.insert(points, { x = hq.x, y = hq.y })
		end
		for _, r in myRigs() do
			table.insert(points, { x = r.x, y = r.y })
		end
		local safe = {}
		for _, p in points do
			if mineAt(p.x, p.y) >= threatAt(p.x, p.y) then
				table.insert(safe, p)
			end
		end
		if #safe == 0 then
			return
		end
		local reach = scaled(num("bots.influence.reachCells"))
		for _, k in order do
			local g = groups[k]
			local px, py = 0, 0
			for _, u in g.units do
				px += u.x
				py += u.y
			end
			px /= #g.units
			py /= #g.units
			local m = threatAt(px, py)
			if not (m < num("bots.influence.fallMinThreat") or m <= mineAt(px, py) * i) then
				local best, bd = safe[1], math.huge
				for _, p in safe do
					local d = hypot(p.x - px, p.y - py)
					if d < bd then
						best, bd = p, d
					end
				end
				if bd >= reach then
					local ids = {}
					for _, u in g.units do
						table.insert(ids, u.id)
					end
					sim.orderMove(side, ids, best.x, best.y)
					for _, id in ids do
						self.orders[id] = nil
						self.resent[id] = nil
					end
					self.avoid[k] = sim.time + num("bots.influence.avoidSec")
				end
			end
		end
	end

	---------------------------------------------------------------- idle army (oat)

	local function idleArmy(): { any }
		for id, t in self.orders do
			local u = sim.entities[id]
			if not u or not u.alive or not targetValid(t) then
				self.orders[id] = nil
				self.resent[id] = nil
			end
		end
		local all = army()
		local free = {}
		for _, u in all do
			if idle(u) and not self.orders[u.id] then
				table.insert(free, u)
			end
		end
		local kept: { [number]: boolean } = {}
		local radius = num("rigs.radius")
		for _, r in myRigs() do
			for _, u in free do
				if not kept[u.id] and (u.x - r.x) ^ 2 + (u.y - r.y) ^ 2 <= (radius * 2) ^ 2 then
					kept[u.id] = true
					break
				end
			end
		end
		local hq = sim.hqOf(side)
		if hq then
			local rest = {}
			for _, u in free do
				if not kept[u.id] then
					table.insert(rest, u)
				end
			end
			table.sort(rest, function(a, b)
				return hypot(a.x - hq.x, a.y - hq.y) < hypot(b.x - hq.x, b.y - hq.y)
			end)
			local keep = math.floor(#all * persona.home)
			if num("bots.homeKeepMax") > 0 then
				keep = math.min(keep, num("bots.homeKeepMax"))
			end
			for i = 1, math.min(keep, #rest) do
				kept[rest[i].id] = true
			end
		end
		for id, t in self.orders do
			local u = sim.entities[id]
			local target = orderTarget(t)
			local near = if t.kind == "city" and target then target.radius else radius
			if u and target and idle(u) and hypot(u.x - target.x, u.y - target.y) > near then
				local n = self.resent[id] or 0
				if n >= 3 then
					self.orders[id] = nil
					self.resent[id] = nil
				else
					self.resent[id] = n + 1
					sim.orderMove(side, { id }, target.x, target.y)
				end
			end
		end
		local out = {}
		for _, u in free do
			if not kept[u.id] then
				table.insert(out, u)
			end
		end
		return out
	end

	---------------------------------------------------------------- defence (sat / aat)

	local function defence(pool: { any })
		if #pool > 0 then
			local spots = {}
			local hq = sim.hqOf(side)
			if hq then
				table.insert(spots, { t = { kind = "structure", id = hq.id }, x = hq.x, y = hq.y })
			end
			local rigs = myRigs()
			table.sort(rigs, function(a, b)
				local ra, rb = sim.pumpRate(a), sim.pumpRate(b)
				if ra ~= rb then
					return ra > rb
				end
				return a.id < b.id
			end)
			for _, r in rigs do
				table.insert(spots, { t = { kind = "rig", id = r.id }, x = r.x, y = r.y })
			end
			for _, c in spots do
				if #pool == 0 then
					break
				end
				local k = key(c.t)
				if (self.covering[k] or -math.huge) <= sim.time then
					local u = threatAt(c.x, c.y)
					if u >= num("bots.influence.guardMinThreat") then
						local d = mineAt(c.x, c.y)
						local ratio = num("bots.influence.guardRatio")
						if d < u * ratio and dispatch(pool, c.t, c.x, c.y, u * ratio - d) then
							self.covering[k] = sim.time + num("bots.influence.guardSec")
						end
					end
				end
			end
		end
		for _, r in myRigs() do
			if r.contested or r.capture then
				local i = enemyNear(r.x, r.y, num("rigs.radius") * 3)
				if i > 0 then
					dispatch(pool, { kind = "rig", id = r.id }, r.x, r.y, i * num("bots.margin"))
				end
			end
		end
	end

	---------------------------------------------------------------- attack (mat)

	local function avoided(t: { kind: string, id: number }): boolean
		return (self.avoid[key(t)] or -math.huge) > sim.time
	end

	local function attack(pool: { any })
		if #pool == 0 then
			return
		end
		local force, cx, cy = 0, 0, 0
		for _, u in pool do
			force += unitWorth(u.kind)
			cx += u.x
			cy += u.y
		end
		cx /= #pool
		cy /= #pool
		local afterGrace = sim.time >= num("bots.graceSec")
		local targetedRigs = {}
		for _, t in self.orders do
			if t.kind == "rig" then
				targetedRigs[t.id] = true
			end
		end
		local massing = false
		if afterGrace and sim.time >= num("bots.assaultAfter") then
			local best = nil
			for _, hq in enemyStructures() do
				if hq.kind == "hq" and not avoided({ kind = "structure", id = hq.id }) then
					local radius = num("structures.hq.buildRadius")
					local m = enemyNear(hq.x, hq.y, radius)
					if not fresh(hq.x, hq.y) then
						m = math.max(m, num("bots.unknownHqDefence"))
					end
					m += structureWorth(hq.kind, hq.hp) * num("bots.hqWorthShare")
					local need = m * marginH()
					local cost = need + approach(cx, cy, hq.x, hq.y, radius)
					local d = hypot(hq.x - cx, hq.y - cy)
					if not best or cost < best.cost - 1e-6 or (math.abs(cost - best.cost) <= 1e-6 and d < best.d) then
						best = { id = hq.id, x = hq.x, y = hq.y, need = need, cost = cost, d = d }
					end
				end
			end
			if best then
				if self.nextPush < 0 then
					self.nextPush = sim.time + num("bots.pushMassSec")
				end
				local due = sim.time >= self.nextPush
				if (force >= best.need or (due and force >= num("bots.pushMinForce"))) and #pool >= num("bots.assaultPool") then
					dispatch(pool, { kind = "structure", id = best.id }, best.x, best.y, force)
					self.nextPush = sim.time + num("bots.pushEverySec") * persona.attackMargin / 1.5
					return
				end
				massing = due or sim.time >= self.nextPush - num("bots.pushMassSec") or force >= best.need * num("bots.assaultMassShare")
				if num("bots.massMaxSec") > 0 and #pool >= num("bots.assaultPool")
					and force >= math.max(num("bots.pushMinForce"), best.need * num("bots.assaultMassShare")) then
					self.nextPush = math.min(self.nextPush, sim.time + num("bots.massMaxSec"))
				end
			end
		end
		local pick = nil
		local radius3 = num("rigs.radius") * 3
		for _, r in sim.rigs do
			local owner = rigOwner(r)
			local skip = owner == side or targetedRigs[r.id] or avoided({ kind = "rig", id = r.id })
				or (owner >= 0 and (massing or not afterGrace or not canAttack(side, owner)))
			if not skip then
				local k = enemyNear(r.x, r.y, radius3)
				if not fresh(r.x, r.y) and (owner >= 0 or sim.time >= num("bots.neutralTrustSec")) then
					k = math.max(k, num("bots.unknownDefence"))
				end
				local x = if owner >= 0 then marginH() else num("bots.margin")
				if force >= k * x then
					local c = approach(cx, cy, r.x, r.y, radius3)
					if c <= force * num("bots.influence.approachMax") then
						local sd = 1 + hypot(r.x - cx, r.y - cy) / scaled(15)
						local score = (if owner >= 0 then 4 else 3) / (sd * sd) / (1 + k / 400) / (1 + c / num("bots.influence.approachSoft"))
						if not pick or score > pick.score then
							pick = { id = r.id, x = r.x, y = r.y, need = math.max(k * x, 20), score = score }
						end
					end
				end
			end
		end
		-- settlements (not capitals) after bots.cityAfter: neutral ones while the bot holds fewer than
		-- floor(cityHeld x (0.5 + defence)) and has fewer than max(1, floor(maxOccupied x (0.5 +
		-- defence))) without a garrison; enemy ones after the grace when not massing.
		local targetedCities, nTargeted = {}, 0
		for _, t in self.orders do
			if t.kind == "city" and not targetedCities[t.id] then
				targetedCities[t.id] = true
				nTargeted += 1
			end
		end
		local function mayTake(enemy: boolean): boolean
			local held, bare = 0, 0
			for _, st in sim.settlements do
				if st.owner == side and st.kind ~= "capital" then
					held += 1
					if #st.garrison == 0 and sim.garrisonWalking(st) == 0 then
						bare += 1
					end
				end
			end
			local l = math.floor(num("bots.cityHeld") * (0.5 + persona.defence))
			local c = math.max(1, math.floor(num("bots.maxOccupied") * (0.5 + persona.defence)))
			return held + nTargeted < l and (enemy or bare + nTargeted < c)
		end
		local takeNeutral = sim.time >= num("bots.cityAfter") and mayTake(false)
		local takeEnemy = sim.time >= num("bots.cityAfter") and afterGrace and not massing and mayTake(true)
		if takeNeutral or takeEnemy then
			local homes = {}
			for _, r in myRigs() do
				table.insert(homes, { x = r.x, y = r.y })
			end
			local hq = sim.hqOf(side)
			if hq then
				local W = sim.roads.width
				table.insert(homes, { x = hq.cell % W + 0.5, y = hq.cell // W + 0.5 })
			end
			local homeCells = scaled(num("bots.cityHomeCells"))
			for _, st in sim.settlements do
				local t = { kind = "city", id = st.id }
				if not targetedCities[st.id] and st.kind ~= "capital" and not avoided(t) then
					local owner = cityOwner(st)
					local ok = owner ~= side and (if owner < 0 then takeNeutral else takeEnemy and canAttack(side, owner))
					if ok then
						-- status as last seen (the game's vwe) and its garrison's worth (lat)
						local status = "neutral"
						if owner >= 0 then
							status = intel.cityStatus[st.id] or "occupied"
							if status == "neutral" or intel.cities[st.id] == side then
								status = "occupied"
							end
						end
						local full = num(`cities.garrisonFull.{st.kind}`)
						local men = unitWorth("infantry")
						local held = if status == "secured" then full * men * num(`cities.securedFire.{st.kind}`) / math.max(0.05, num(`cities.securedCover.{st.kind}`))
							elseif status == "fortified" then (full - 1) * men / math.max(0.05, num("cities.cover"))
							else 0
						local k = enemyNear(st.x, st.y, st.radius * 2) + held
						if not fresh(st.x, st.y) and (owner >= 0 or sim.time >= num("bots.neutralTrustSec")) then
							k = math.max(k, num("bots.unknownDefence"))
						end
						local x = if owner >= 0 then marginH() else num("bots.margin")
						if force >= k * x then
							local c = approach(cx, cy, st.x, st.y, st.radius * 2)
							if c <= force * num("bots.influence.approachMax") then
								local hd = 1 + hypot(st.x - cx, st.y - cy) / scaled(15)
								local o = math.huge
								for _, h in homes do
									o = math.min(o, hypot(st.x - h.x, st.y - h.y))
								end
								local far = 1 + (if o < math.huge then o else homeCells * 4) / homeCells
								local value = num(`bots.cityValue.{st.kind}`)
									* (if owner < 0 then 0.5 + persona.defence elseif status == "secured" then num("bots.cityEnemy") else 1)
								local score = value / (hd * hd) / far / (1 + k / 400) / (1 + c / num("bots.influence.approachSoft"))
								if not pick or score > pick.score then
									pick = { kind = "city", id = st.id, x = st.x, y = st.y, need = math.max(k * x, 20), score = score }
								end
							end
						end
					end
				end
			end
		end
		if pick then
			dispatch(pool, { kind = pick.kind or "rig", id = pick.id }, pick.x, pick.y, pick.need)
		end
	end

	---------------------------------------------------------------- scouts (Qst)

	-- An idle, ready scout within bots.scoutStandOff x 1.6 of the nearest enemy HQ deploys; otherwise,
	-- with chance bots.scoutSendChance per think, it drives to scoutStandOff short of a random enemy HQ.
	local function scouts()
		local list = {}
		for _, e in sim.list do
			if e.alive and e.side == side and sim.canRecon(e) then
				table.insert(list, e)
			end
		end
		if #list == 0 then
			return
		end
		local hqs = {}
		for _, st in sim.list do
			if st.alive and st.kind == "hq" and sim.canAttack(side, st.side) then
				table.insert(hqs, st)
			end
		end
		if #hqs == 0 then
			return
		end
		local W = sim.roads.width
		local standOff = num("bots.scoutStandOff")
		for _, u in list do
			if not sim.scoutDeployed(u) and idle(u) and sim.scoutReadyIn(u) <= 0 then
				local best, bestD = hqs[1], math.huge
				for _, h in hqs do
					local d = hypot(h.cell % W + 0.5 - u.x, h.cell // W + 0.5 - u.y)
					if d < bestD then
						best, bestD = h, d
					end
				end
				if bestD <= standOff * 1.6 then
					sim.deployRecon(side, { u.id })
				elseif rand() < num("bots.scoutSendChance") then
					local h = hqs[math.floor(rand() * #hqs) + 1] or best
					local hx, hy = h.cell % W + 0.5, h.cell // W + 0.5
					local d = math.max(1, hypot(hx - u.x, hy - u.y))
					local k = math.max(0, (d - standOff) / d)
					sim.orderMove(side, { u.id }, u.x + (hx - u.x) * k, u.y + (hy - u.y) * k)
				end
			end
		end
	end

	---------------------------------------------------------------- think loop

	local function think()
		local s = sim.sides[side]
		if not s or s.lost then
			return
		end
		updateIntel()
		self.inf = buildInfluence()
		local p = plan()
		local saving = trucks()
		if not saving then
			placeBuilding(p)
			training(p)
		end
		scouts()
		fallBack()
		local pool = idleArmy()
		defence(pool)
		garrison(pool)
		attack(pool)
	end
	self.think = think

	function self.step(_dt: number)
		if sim.time < self.nextThink then
			return
		end
		self.nextThink = sim.time + num("bots.thinkSec") * diff.think * (0.8 + rand() * 0.4)
		think()
	end

	return self
end

return Bot
