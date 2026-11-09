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
	  training  the HQ (queue < 2) trains an engineer when the army is 4+ and it has fewer than
	            bots.engineers (every bots.engineerEverySec), otherwise infantry while it has no barracks
	            or the army is under 8.
	  fall back groups under strong threat (influence map) retreat to the nearest safe own point.
	  idle army one idle unit stays at each own rig; the persona's home share (max bots.homeKeepMax)
	            stays nearest the HQ; unfinished orders are re-sent up to 3 times.
	  defence   threatened HQ/rigs (threat >= guardMinThreat and own strength < threat x guardRatio)
	            and rigs under capture get enough units to answer the threat.
	  attack    after bots.assaultAfter: a push on the cheapest enemy HQ when strong enough, or with
	            bots.pushMinForce once the push timer runs out (needs bots.assaultPool idle units);
	            otherwise the best-scoring rig (neutral rigs only before bots.graceSec).
	Unit worth = hp / 100 x dps / 8 x 30. Influence map: blocks of 6 x cell scale, reach 14 x cell scale.

	Intel: like the game's bots (intel.fog and bots.fog are on) it sees only with its own vision and
	remembers what it saw (see the intel section); an unseen enemy HQ counts at least
	bots.unknownHqDefence and an unseen rig bots.unknownDefence. Not in the slice, so skipped: buildings other than barracks and factory, engineers' work,
	recon, drones, artillery, cities and the capital, bridges, rail, naval, events, sabotage.
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

	local function isArmy(e: any): boolean
		if not e.alive or e.cat ~= "unit" or e.kind == "truck" then
			return false
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

	-- Dst: what to build next. APPROX: kinds the slice cannot place (bunker, radar, SAM, night ops,
	-- artillery base, naval yard, forward HQ, guard posts) are passed over.
	local function plan(): any
		local hq = sim.hqOf(side)
		if not hq then
			return nil
		end
		local W = sim.roads.width
		local seen: { [string]: number } = {}
		local inc = income()
		for _, g in BUILD_ORDER do
			seen[g.type] = (seen[g.type] or 0) + 1
			if countOf(g.type) < seen[g.type] then
				if sim.time < g.after * diff.buildDelay or inc < g.minIncome then
					break
				end
				if sim.PLACEABLE[g.type] then
					return {
						type = g.type,
						near = { x = hq.cell % W + 0.5, y = hq.cell // W + 0.5 },
						reach = num("structures.hq.buildRadius"),
					}
				end
			end
		end
		return nil
	end

	-- Vst: up to 120 random points in the nation's base sources; a facility takes the valid spot
	-- nearest the HQ (plus up to 3 cells x cell scale of noise).
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
					local score = hypot(m - cx, y - cy) + rand() * 3 * scale
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

	local PRIORITY = { factory = 1, barracks = 2, hq = 3 }
	local function training(p: any)
		local counts: { [string]: number } = {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "unit" and e.kind ~= "truck" then
				counts[e.kind] = (counts[e.kind] or 0) + 1
			end
		end
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
				if footShort then
					-- APPROX: the slice has no mortars, so the mortar share trains infantry
					item = if k < 0.3 then "at" else "infantry"
				end
			elseif st.kind == "factory" then
				-- APPROX: scouts are not in the slice, so the game's scout pick (army >= bots.scoutArmy, fewer
				-- than round(army x bots.scoutShare) scouts, every bots.scoutEverySec) is skipped and the
				-- factory makes its usual pick; artillery and rocket picks train nothing.
				item = if k < 0.45 then "tank" elseif k < 0.75 then "ifv" else nil
			end
			if item and sim.sides[side].oil - num(`units.{item}.cost`) >= reserve then
				if sim.orderProduce(side, item, st.id) then
					counts[item] = c(item) + 1
					if item == "engineer" then
						self.lastEngineer = sim.time
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
			local target = sim.entities[t.id]
			if u and target and idle(u) and hypot(u.x - target.x, u.y - target.y) > radius then
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
		if pick then
			dispatch(pool, { kind = "rig", id = pick.id }, pick.x, pick.y, pick.need)
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
		fallBack()
		local pool = idleArmy()
		defence(pool)
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
