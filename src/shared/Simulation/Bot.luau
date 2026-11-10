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
	            barracks, radar, factory), then home guards after 300 s (bunker or AT gun
	            50/50 near the HQ while fewer than round(homeGuards x (0.5 + persona defence)) armed
	            buildings stand there), then rig guards after 180 s (bunker 60% / AT gun at far rigs).
	  training  producers factory, barracks, HQ (queue < 2). HQ: an engineer when the army is 4+ and it
	            has fewer than bots.engineers (every bots.engineerEverySec), otherwise infantry while it
	            has no barracks or the army is under 8. Barracks (while foot units are under half the
	            army): AT 30%, mortar bots.mortarShare x (0.5 + defence), else infantry. Factory: a scout
	            (army >= scoutArmy, every scoutEverySec, up to round(army x scoutShare)), else tank 45%,
	            IFV 30%, artillery 13%, rocket artillery 12%.
	            Then, while short of foot units or garrison men, secured towns nearer the enemy than any
	            barracks / HQ train infantry or AT there (forward training, bots.forwardShare).
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
	  refinery  (the game's Ist) see refinery() below: a refinery in the held town most of our
	            trucking rigs would reach well before the HQ.
	  signs     (the game's iat) a truck held by the enemy for bots.signAfterSec gets a road sign a
	            little ahead of it, taken down after bots.signHoldSec.
	  trenches  (the game's JUe) see Sim.botTrenches: fire trench lines in front of the HQ once it has
	            trenchWorks.bots.digFrom oil, idle infantry man them, and trenches cutting the way to an
	            enemy HQ are breached or filled.
	Unit worth = hp / 100 x dps / 8 x 30. Influence map: blocks of 6 x cell scale, reach 14 x cell scale.

	Intel: like the game's bots (intel.fog and bots.fog are on) it sees only with its own vision and
	remembers what it saw (see the intel section); an unseen enemy HQ counts at least
	bots.unknownHqDefence and an unseen rig bots.unknownDefence. Not in the slice, so skipped: naval yard,
	forward HQ, bridges, rail, naval, events.
	APPROX: the bot's random numbers are not the game's sequence; held-truck rescues are skipped
	(trucks are never held by enemies in the slice). UNCONFIRMED: which persona a lobby slot defaults to
	(MatchService picks one).
]]
local Bot = {}

export type Persona = { id: string, attackMargin: number, home: number, defence: number, raid: number }

function Bot.new(sim: any, side: number, personaId: string?, level: string?)
	local num = sim.num
	sim.sides[side].bot = true -- the game's !isPlayer: e.g. its cut supply routes re-route themselves
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
		muster = {} :: { [number]: boolean }, -- units gathering for the capital assault
		rigStruck = {} :: { [number]: number }, -- rig id -> when our rockets last hit it
		mending = {} :: { [number]: { city: number, tries: number } }, -- hurt units sent to heal in a town
		mendRest = {} :: { [number]: number }, -- unit id -> not sent to heal again before
		nextMend = -math.huge,
		guards = {} :: { [number]: { key: number, post: number } }, -- bridge guards (nat)
		lastBlow = -math.huge, -- when an engineer last went to blow a bridge (Yst)
		musterSince = -1,
		musterRest = -math.huge,
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
		contacts = {} :: { any }, -- radar contacts out of sight (the game's knowledge contacts)
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
		-- the game's eQe: groups of enemy units in our radar sweeps but out of sight
		intel.contacts = if fogged then sim.contactGroups(side, vis) else {}
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
		-- a unit chasing, walking back or taking cover on its own (the game's idleThink) is still idle
		-- a launcher with a barrage order is busy until it fires (APPROX: the game keeps it out of the pool)
		return (e.target == nil or e.chasing == true or e.coverCell ~= nil) and e.attackId == nil and e.barrage == nil
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
		-- radar contact groups count bots.contactWorth.<strength> each (the game's H5)
		for _, ct in intel.contacts do
			if (ct.x - x) ^ 2 + (ct.y - y) ^ 2 <= r2 then
				total += num(`bots.contactWorth.{ct.strength}`)
			end
		end
		return total
	end
	-- the game's YQ: fresh enemy army the bot knows of within r of (x, y): total worth and its centre
	local function armyNear(x: number, y: number, r: number): (number, number, number)
		local w, sx, sy = 0, 0, 0
		local function add(px: number, py: number, f: number)
			if f > 0 and (px - x) ^ 2 + (py - y) ^ 2 <= r * r then
				w += f
				sx += px * f
				sy += py * f
			end
		end
		for _, u in intel.units do
			local k = `units.{u.kind}`
			if sim.time - u.t <= num("bots.armyFreshSec") and canAttack(side, u.owner) and text(k .. ".armour") ~= "air" and text(k .. ".move") ~= "sea" then
				add(u.x, u.y, unitWorth(u.kind))
			end
		end
		for _, ct in intel.contacts do
			if not ct.air then
				add(ct.x, ct.y, num(`bots.contactWorth.{ct.strength}`))
			end
		end
		if w > 0 then
			return w, sx / w, sy / w
		end
		return 0, x, y
	end
	-- the game's v7e: bridge spans that matter to us: on one of our rig routes, or within near +
	-- sqrt(span size) of our territory
	local function ourBridges(near: number): { any }
		local onRoute: { [number]: boolean } = {}
		for _, r in sim.rigs do
			if r.side == side and r.route then
				for _, c in r.route do
					onRoute[c] = true
				end
			end
		end
		local out = {}
		local W = sim.roads.width
		for _, sp in sim.bridgeSpans() do
			local ok = false
			for _, c in sp.cells do
				if onRoute[c] then
					ok = true
					break
				end
			end
			if not ok then
				local rr = near + math.sqrt(#sp.cells)
				for yy = math.max(0, math.floor(sp.y - rr)), math.min(sim.roads.height - 1, math.ceil(sp.y + rr)) do
					for xx = math.max(0, math.floor(sp.x - rr)), math.min(W - 1, math.ceil(sp.x + rr)) do
						if (xx + 0.5 - sp.x) ^ 2 + (yy + 0.5 - sp.y) ^ 2 <= rr * rr and sim.territoryAt(yy * W + xx) == side then
							ok = true
							break
						end
					end
					if ok then
						break
					end
				end
			end
			if ok then
				table.insert(out, sp)
			end
		end
		return out
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

	-- the game's Fst: with no HQ, deploy the command truck where it stands if a road there reaches the
	-- rigs, else drive it back to the old HQ's site and set up there; with no truck, queue one at a
	-- working factory (APPROX: a full queue is not trimmed first). True while rehousing.
	local function rehouse(): boolean
		if sim.hqOf(side) then
			return false
		end
		local tr = sim.truckOf(side)
		if tr then
			if tr.deployAt then
				return true
			end
			local c = sim.hqDeployCell(tr)
			if c >= 0 and sim.hqRoadOk(c) and sim.deployHq(side, tr.id) then
				return true
			end
			local old: any = sim.entities[sim.sides[side].hqId]
			if not old and sim.drop then
				old = sim.drop.homes[side] -- the game's g9e: after the drop, drive to the start point
			end
			local idleNow = not tr.path
			if old and idleNow then
				if hypot(tr.x - old.x, tr.y - old.y) > scaled(2) then
					sim.orderMove(side, { tr.id }, old.x, old.y)
				elseif c >= 0 then
					sim.deployHq(side, tr.id)
				end
			end
			return true
		end
		if sim.hqOnOrder(side) then
			return true
		end
		for _, st in sim.list do
			if st.alive and st.side == side and st.kind == "factory" and not sim.inactiveReason(st) then
				-- a full queue gives up its last unit to make room (the game's cancelQueued)
				if st.queue and #st.queue >= num("production.maxQueue") then
					sim.cancelQueued(side, st.id, #st.queue)
				end
				sim.orderProduce(side, "command", st.id)
				return true
			end
		end
		return false
	end

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

	-- Dst: what to build next. APPROX: kinds the slice cannot place (naval yard, forward HQ) are passed
	-- over; SAM sites (only wanted after seeing enemy aircraft) are not built; the radar goes near the HQ like a facility.
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
		-- a night operations tower once it has a barracks and a factory (not while a lost one's wait runs)
		if sim.nightOpsOn() and countOf("nightops") == 0 and sim.nightOpsRebuildIn(side) <= 0
			and sim.hasBuilding(side, "barracks") and sim.hasBuilding(side, "factory") then
			return { type = "nightops", near = { x = ax, y = ay }, reach = hqReach }
		end
		-- the artillery base once it has a barracks and the kills to pay for it
		if countOf("artybase") == 0 and sim.hasBuilding(side, "barracks")
			and sim.killsOf(side) >= num("structures.artybase.killCost") then
			return { type = "artybase", near = { x = ax, y = ay }, reach = hqReach }
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
	-- the game's Nst: secured towns (forward queue under 2) at least bots.forwardCloser nearer the
	-- nearest known enemy building than any own built barracks / HQ train there, each with chance
	-- bots.forwardShare: AT 30% of the time, else infantry, keeping `reserve` oil.
	local function forwardTrain(reserve: number)
		local rules = sim.deps.rules
		if not rules:flag("cities.forward.on") then
			return
		end
		local towns = {}
		for _, st in sim.settlements do
			if st.owner == side and sim.forwardActive(st) and (if st.forward then #st.forward.queue else 0) < 2 then
				table.insert(towns, st)
			end
		end
		if #towns == 0 then
			return
		end
		local W = sim.roads.width
		local hq = sim.hqOf(side)
		local hx, hy = 0, 0
		if hq then
			hx, hy = hq.cell % W + 0.5, hq.cell // W + 0.5
		end
		local tx, ty, best = nil, nil, math.huge
		for _, k in intel.structures do
			if k.owner ~= side and k.owner > 0 and sim.canAttack(side, k.owner) then
				local x, y = k.cell % W + 0.5, k.cell // W + 0.5
				local d = if hq then hypot(x - hx, y - hy) else 0
				if d < best then
					tx, ty, best = x, y, d
				end
			end
		end
		if not tx then
			return
		end
		local near = math.huge
		for _, st in sim.list do
			if st.alive and st.side == side and st.cat == "structure" and (st.built or 1) >= 1 and (st.kind == "barracks" or st.kind == "hq") then
				near = math.min(near, hypot(st.cell % W + 0.5 - tx, st.cell // W + 0.5 - ty))
			end
		end
		local trains = (rules.data["cities.forward.trains"] :: { string }?) or {}
		for _, st in towns do
			if hypot(st.x - tx, st.y - ty) + scaled(num("bots.forwardCloser")) > near or rand() >= num("bots.forwardShare") then
				continue
			end
			local pick = if rand() < 0.3 and table.find(trains, "at") then "at" else "infantry"
			local item = if table.find(trains, pick) then pick else trains[1]
			if item and sim.sides[side].oil - sim.unitCost(side, item) >= reserve then
				sim.queueForward(side, st.id, item)
			end
		end
	end

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
				if item == "mortar" and not sim.armyAllows(side, "mortar") then
					item = "infantry" -- the republic has no mortars
				end
			elseif st.kind == "factory" then
				-- a scout once the army is bots.scoutArmy, up to round(army x scoutShare) (max intel.scoutMax),
				-- one per bots.scoutEverySec; otherwise the usual pick.
				local maxScouts = math.min(num("intel.scoutMax"), math.max(1, math.floor(h * num("bots.scoutShare") + 0.5)))
				if h >= num("bots.scoutArmy") and c("scout") < maxScouts and sim.time - self.lastScout >= num("bots.scoutEverySec") then
					item = "scout"
				else
					item = if k < 0.45 then "tank" elseif k < 0.75 then "ifv" elseif k < 0.88 then "artillery" else "rocket"
				end
			end
			if item and sim.sides[side].oil - sim.unitCost(side, item) >= reserve then
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
		if not hasFactory or c("infantry") + c("at") + c("mortar") < h * 0.5 or menShort then
			forwardTrain(reserve)
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
		for _, st in myCities() do -- held towns are fall-back points too (zV in the game's rat)
			table.insert(points, { x = st.x, y = st.y })
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

	---------------------------------------------------------------- mending (hat)

	-- the game's hat: every bots.mendEverySec, hurt units (below mendBelow of their hp; idle, or moving and
	-- armed; quiet for mendQuietSec, nobody hostile in sight, not on a job at their order's target) go to
	-- the nearest of our secured towns that heals their kind and has no known enemy near (within
	-- mendReach x cellScale), up to mendShare of the army at once. Sent units are watched: one in contact,
	-- or that can't get there, rests mendRetrySec; healed ones go back to the pool.
	local function mendUnits()
		local cfg = "bots."
		local secured = {}
		for _, st in sim.settlements do
			if st.owner == side and sim.cityStatus(st) == "secured" then
				table.insert(secured, st)
			end
		end
		local function isSecured(st: any): boolean
			return table.find(secured, st) ~= nil
		end
		local function inReach(u: any, st: any): boolean
			return (u.x - st.x) ^ 2 + (u.y - st.y) ^ 2 <= (st.radius + num("cities.repairReach")) ^ 2
		end
		local function inContact(u: any): boolean
			return u.firing == true or (u.hitAt ~= nil and sim.time - u.hitAt < num("movement.contactSec"))
		end
		local function rest(id: number)
			self.mending[id] = nil
			self.mendRest[id] = sim.time + num(cfg .. "mendRetrySec")
		end
		local function stillOrMoving(u: any): (boolean, boolean)
			local still = u.target == nil and u.attackId == nil
			local moving = u.target ~= nil and u.attackId == nil and not u.chasing
			return still, moving
		end
		for id, m in self.mending do
			local u = sim.entities[id]
			local st = sim.settlements[m.city]
			local still, moving = if u then stillOrMoving(u) else false, false
			if not u or not u.alive or u.side ~= side or u.inside or not (still or moving) or u.hp >= u.maxHp or not st or not isSecured(st) then
				self.mending[id] = nil
			elseif inContact(u) then
				rest(id)
			elseif still and not inReach(u, st) then
				if m.tries >= 1 then
					rest(id)
				else
					sim.orderMove(side, { id }, st.x, st.y)
					if u.path and #u.path > 0 then
						m.tries += 1
					else
						rest(id)
					end
				end
			end
		end
		if sim.time < self.nextMend then
			return
		end
		self.nextMend = sim.time + num(cfg .. "mendEverySec")
		for id, t in self.mendRest do
			local u = sim.entities[id]
			if sim.time >= t or not u or not u.alive then
				self.mendRest[id] = nil
			end
		end
		if #secured == 0 then
			return
		end
		local mendingCount = 0
		for _ in self.mending do
			mendingCount += 1
		end
		local left = math.ceil(#army() * num(cfg .. "mendShare")) - mendingCount
		if left <= 0 then
			return
		end
		local safe = {}
		for _, st in secured do
			if enemyNear(st.x, st.y, st.radius * 2) <= 0 then
				table.insert(safe, st)
			end
		end
		if #safe == 0 then
			return
		end
		local reach = scaled(num(cfg .. "mendReach"))
		local groups: { [number]: { st: any, ids: { number } } } = {}
		local order: { number } = {}
		for _, u in sim.list do
			if left <= 0 then
				break
			end
			if not u.alive or u.side ~= side or u.cat ~= "unit" or u.kind == "truck" or u.inside or self.mending[u.id] or self.mendRest[u.id] then
				continue
			end
			local k = `units.{u.kind}`
			local still, moving = stillOrMoving(u)
			if u.hp >= u.maxHp * num(cfg .. "mendBelow") or text(k .. ".armour") == "air" or text(k .. ".move") == "sea"
				or text(k .. ".nato") == "recon" or u.kind == "demo" or u.kind == "command"
				or not (still or (moving and num(k .. ".dps") > 0)) or u.barrage or inContact(u)
				or sim.time - math.max(u.hitAt or -999, u.firedAt or -999) < num(cfg .. "mendQuietSec") then
				continue
			end
			local hostile = false
			for _, o in sim.unitsNear(u.x, u.y, num(k .. ".sight")) do
				local ok = `units.{o.kind}`
				if o.alive and o.cat == "unit" and canAttack(side, o.side) and num(ok .. ".dps") > 0 and text(ok .. ".armour") ~= "air"
					and text(ok .. ".move") ~= "sea" and (o.x - u.x) ^ 2 + (o.y - u.y) ^ 2 <= num(k .. ".sight") ^ 2 then
					hostile = true
					break
				end
			end
			if hostile then
				continue
			end
			local t = self.orders[u.id]
			local at = if t and t.kind ~= "structure" then orderTarget(t) else nil
			if at then
				local r = if t.kind == "city" then at.radius else num("rigs.radius")
				if hypot(u.x - at.x, u.y - at.y) <= r then
					continue -- on its job
				end
			end
			local foot = text(k .. ".move") == "foot"
			local best, bd = nil, reach
			for _, st in safe do
				local d = hypot(st.x - u.x, st.y - u.y)
				local heals = num(`cities.{if foot then "repairMen" else "repairVehicles"}.{st.kind}`) > 0
				if d <= bd and heals then
					best, bd = st, d
				end
			end
			if not best then
				continue
			end
			left -= 1
			self.orders[u.id], self.resent[u.id], self.muster[u.id], self.guards[u.id] = nil, nil, nil, nil
			if still and inReach(u, best) then
				self.mending[u.id] = { city = best.id, tries = 0 }
				continue
			end
			local gk = best.id * 2 + (if foot then 1 else 0)
			if not groups[gk] then
				groups[gk] = { st = best, ids = {} }
				table.insert(order, gk)
			end
			table.insert(groups[gk].ids, u.id)
		end
		for _, gk in order do
			local g = groups[gk]
			sim.orderMove(side, g.ids, g.st.x, g.st.y)
			for _, id in g.ids do
				local u = sim.entities[id]
				if u and ((u.path and #u.path > 0) or inReach(u, g.st)) then
					self.mending[id] = { city = g.st.id, tries = 0 }
				else
					self.mendRest[id] = sim.time + num(cfg .. "mendRetrySec")
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
			if idle(u) and not self.orders[u.id] and not self.muster[u.id] and not self.mending[u.id] and not self.guards[u.id] then
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
		-- the game's sat, last part: a truck of ours held up by the enemy for bots.truckHeldSec (the one
		-- from the rig with the most trucks) gets enough units sent to clear the way
		local held = nil
		for _, t in sim.list do
			if t.alive and t.side == side and t.kind == "truck" and t.stopped == "enemy" and (t.from or -1) > 0
				and (t.waiting or 0) >= num("bots.truckHeldSec") then
				if not held then
					held = t
				else
					local a, b = sim.trucksOf(t.from), sim.trucksOf(held.from)
					if a > b or (a == b and t.id < held.id) then
						held = t
					end
				end
			end
		end
		if held then
			local i = enemyNear(held.x, held.y, num("convoys.lookAhead") * 1.5)
			if i > 0 then
				dispatch(pool, { kind = "rig", id = held.from }, held.x, held.y, i * num("bots.margin"))
			end
		end
	end

	---------------------------------------------------------------- bridge guards (nat)

	-- the game's nat: the bridgeGuardSpans spans of ours nearest the HQ each get bridgeGuards units
	-- posted at the span's end nearest the HQ, while the army has at least bridgeGuardMinArmy units and
	-- at most bridgeGuardShare of it guards; an idle guard that wandered more than 3 x cellScale off
	-- walks back. Guards leave the idle pool.
	local function bridgeGuards(pool: { any })
		local hq = sim.hqOf(side)
		if not hq then
			return
		end
		local spans = ourBridges(scaled(num("bots.bridgeNearCells")))
		table.sort(spans, function(a: any, b: any)
			return hypot(a.x - hq.x, a.y - hq.y) < hypot(b.x - hq.x, b.y - hq.y)
		end)
		local keep: { [number]: any } = {}
		for i = 1, math.min(#spans, num("bots.bridgeGuardSpans")) do
			keep[spans[i].key] = spans[i]
		end
		local W = sim.roads.width
		local back = scaled(3)
		local count = 0
		for id, g in self.guards do
			local u = sim.entities[id]
			if not u or not u.alive or u.side ~= side or not keep[g.key] then
				self.guards[id] = nil
			else
				count += 1
				local px, py = g.post % W + 0.5, g.post // W + 0.5
				if u.target == nil and u.attackId == nil and hypot(u.x - px, u.y - py) > back then
					sim.orderMove(side, { id }, px, py)
				end
			end
		end
		local n = #army()
		if n < num("bots.bridgeGuardMinArmy") then
			return
		end
		local cap = math.floor(n * num("bots.bridgeGuardShare"))
		for i = 1, math.min(#spans, num("bots.bridgeGuardSpans")) do
			local sp = spans[i]
			local have = 0
			for _, g in self.guards do
				if g.key == sp.key then
					have += 1
				end
			end
			local post = sim.bridgeEnd(sp, hq.x, hq.y)
			if post >= 0 then
				local px, py = post % W + 0.5, post // W + 0.5
				while have < num("bots.bridgeGuards") and count < cap and #pool > 0 do
					local bi, bd = 1, math.huge
					for k, u in pool do
						local d = (u.x - px) ^ 2 + (u.y - py) ^ 2
						if d < bd then
							bi, bd = k, d
						end
					end
					local u = table.remove(pool, bi)
					sim.orderMove(side, { u.id }, px, py)
					if u.path then
						self.guards[u.id] = { key = sp.key, post = post }
						have += 1
						count += 1
					end
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
								-- a settlement with a trait is worth 1 + bots.traitValue
								local trait = if st.trait and rules:flag("cities.traits.on") then 1 + num("bots.traitValue") else 1
								local value = num(`bots.cityValue.{st.kind}`) * trait
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
	-- the game's fat: the capital assault. While the capital is someone else's (or neutral), after
	-- bots.capitalAfter / appetite seconds and with bots.capitalRigs rigs, idle units gather 30% of the
	-- way from our HQ to the capital; once their worth reaches max(threat there x margin,
	-- capitalForce x appetite) they all go in. A muster that takes longer than capitalMusterSec breaks
	-- up and rests as long. Holding the capital ourselves, the pool defends it against any threat.
	local function capital(pool: { any })
		local cap = nil
		for _, st in sim.settlements do
			if st.kind == "capital" then
				cap = st
				break
			end
		end
		local members = {}
		for id in self.muster do
			local u = sim.entities[id]
			if u and u.alive and u.side == side and u.attackId == nil and not u.garrisonCity then
				table.insert(members, u)
			else
				self.muster[id] = nil
			end
		end
		local function release()
			table.clear(self.muster)
			self.musterSince = -1
			for _, u in members do
				if idle(u) and u.target == nil then
					table.insert(pool, u)
				end
			end
		end
		if not cap then
			release()
			return
		end
		local target = { kind = "city", id = cap.id }
		local radius = num(`settlements.{cap.kind}Radius`)
		local threat = enemyNear(cap.x, cap.y, radius * 2)
		local owner = cityOwner(cap)
		if owner == side then
			release()
			if threat > 0 then
				dispatch(pool, target, cap.x, cap.y, threat * num("bots.margin"))
			end
			return
		end
		local appetite = (sim.rules.data[`bots.capitalAppetite.{persona.id}`] :: number?) or 1
		local guarded = owner >= 0 and (sim.time < num("bots.graceSec") or not canAttack(side, owner))
		local early = sim.time < num("bots.capitalAfter") / appetite or #myRigs() < num("bots.capitalRigs")
		local ordered = false
		for _, t in self.orders do
			if t.kind == "city" and t.id == cap.id then
				ordered = true
				break
			end
		end
		if guarded or early or ordered or sim.time < self.musterRest then
			release()
			return
		end
		if self.musterSince < 0 then
			self.musterSince = sim.time
		end
		if sim.time - self.musterSince > num("bots.capitalMusterSec") then
			self.musterRest = sim.time + num("bots.capitalMusterSec")
			release()
			return
		end
		local hq = sim.hqOf(side)
		local hx, hy = if hq then hq.x else cap.x, if hq then hq.y else cap.y
		local share = num("bots.capitalMusterShare")
		local mx, my = hx + (cap.x - hx) * share, hy + (cap.y - hy) * share
		local need = math.max(threat * (if owner >= 0 then marginH() else num("bots.margin")), num("bots.capitalForce") * math.max(1, appetite))
		if #pool > 0 then
			local ids = {}
			for _, u in pool do
				table.insert(ids, u.id)
			end
			sim.orderMove(side, ids, mx, my)
			for _, u in pool do
				self.muster[u.id] = true
				table.insert(members, u)
			end
			table.clear(pool)
		end
		local worth = 0
		for _, u in members do
			worth += unitWorth(u.kind)
		end
		if worth < need then
			return
		end
		local ids = {}
		for _, u in members do
			table.insert(ids, u.id)
		end
		table.clear(self.muster)
		self.musterSince = -1
		sim.orderMove(side, ids, cap.x, cap.y)
		for _, id in ids do
			self.orders[id] = target
			self.resent[id] = nil
		end
	end

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

	---------------------------------------------------------------- engineers

	-- the game's engineer think (zst), then raids (Jst): idle engineers first mend road cuts near our rigs or HQ (within
	-- 40 x cellScale) or on a rig's road home, unless a crew of the paying side is already on it; then
	-- the most worn cell (at least bots.wearMendFrom) on our rig routes; then the first own built
	-- structure below 70% hp; then damaged rigs (kat). A cut it could not reach is left for bots.bridgeHoldSec.
	-- Before all that a defensive bot may blow a threatened bridge (Yst); it leaves bridges it blew
	-- itself unmended while the threat lasts (Kst). The game's reachability check (Rb) is APPROX: a
	-- path was found, or it is already there.
	local cutHold: { [number]: number } = {}
	local lastSabotage = -math.huge
	local function mend()
		local idleEng = {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "unit" and sim.isEngineer(e) and not e.repairId and not e.roadJob and not e.sabotageCell
				and e.target == nil and e.attackId == nil then
				table.insert(idleEng, e)
			end
		end
		if #idleEng == 0 then
			return
		end
		local function nearest(x: number, y: number): any
			local best, bd = nil, math.huge
			for _, e in idleEng do
				local d = (e.x - x) ^ 2 + (e.y - y) ^ 2
				if d < bd then
					best, bd = e, d
				end
			end
			return best
		end
		local W = sim.roads.width
		-- the game's Yst: a defensive bot (persona defence >= bridgeBlowMinDefence), now and then
		-- (bridgeBlowEverySec, chance defence x bridgeBlowChance), blows one of its bridges that a
		-- known enemy force (bridgeThreatWorth within bridgeThreatCells) is massing beyond: the
		-- nearest idle engineer plants a charge on the span's road cell nearest our HQ
		do
			local hq0 = sim.hqOf(side)
			if hq0 and persona.defence >= num("bots.bridgeBlowMinDefence") and sim.time - self.lastBlow >= num("bots.bridgeBlowEverySec")
				and rand() <= persona.defence * num("bots.bridgeBlowChance") then
				local planted: { [number]: boolean } = {}
				for _, sb in sim.sabotages do
					if sb.side == side then
						planted[sb.cell] = true
					end
				end
				for _, e in sim.list do
					if e.alive and e.side == side and e.sabotageCell then
						planted[e.sabotageCell] = true
					end
				end
				for _, sp in ourBridges(scaled(num("bots.bridgeNearCells"))) do
					local taken = sp.blown
					for _, c in sp.cells do
						if planted[c] then
							taken = true
						end
					end
					if not taken then
						local worth, tx, ty = armyNear(sp.x, sp.y, scaled(num("bots.bridgeThreatCells")))
						if worth >= num("bots.bridgeThreatWorth") and hypot(tx - hq0.x, ty - hq0.y) > hypot(sp.x - hq0.x, sp.y - hq0.y) then
							local cell, bd = sp.cells[1], math.huge -- the game's Xst
							for _, c in sp.cells do
								if sim.roads.isRoad(c) then
									local d = (c % W + 0.5 - hq0.x) ^ 2 + (c // W + 0.5 - hq0.y) ^ 2
									if d < bd then
										cell, bd = c, d
									end
								end
							end
							local e = nearest(sp.x, sp.y)
							if sim.orderSabotage(side, cell, { e.id }) > 0 then
								local rr = num("sabotage.reach")
								if e.path or (e.x - (cell % W + 0.5)) ^ 2 + (e.y - (cell // W + 0.5)) ^ 2 <= rr * rr then
									self.lastBlow = sim.time
									return
								end
								sim.orderStop(side, { e.id })
							end
						end
					end
				end
			end
		end
		local reach = 40 * num("match.cellScale")
		local hq = sim.entities[sim.sides[side].hqId]
		local onRoute: { [number]: boolean } = {}
		local mine = {}
		for _, r in sim.rigs do
			if r.side == side then
				table.insert(mine, r)
				if r.route then
					for _, c in r.route do
						onRoute[c] = true
					end
				end
			end
		end
		local function closeToUs(x: number, y: number): boolean
			for _, r in mine do
				if math.sqrt((r.x - x) ^ 2 + (r.y - y) ^ 2) <= reach then
					return true
				end
			end
			return hq ~= nil and hq.alive and math.sqrt((hq.x - x) ^ 2 + (hq.y - y) ^ 2) <= reach
		end
		local manned: { [number]: boolean } = {}
		for _, e in sim.list do
			if e.alive and e.roadJob and e.roadJob.kind == "cut" then
				local cut = sim.roadCuts[e.roadJob.id]
				if cut and cut.repairBy == e.side then
					manned[cut.id] = true
				end
			end
		end
		-- the game's Kst: a bridge we blew ourselves is left alone for bridgeHoldSec, then mended once no
		-- known enemy force (bridgeThreatWorth within bridgeThreatCells) is near it, and after
		-- bridgeHoldMaxSec in any case
		local function holdOwnBlow(cut: any): boolean
			if cut.by ~= side then
				return false
			end
			local deck = false
			for _, c in cut.cells do
				if sim.deckGround(c) then
					deck = true
					break
				end
			end
			if not deck then
				return false
			end
			if sim.time - cut.at < num("bots.bridgeHoldSec") then
				return true
			end
			if sim.time - cut.at > num("bots.bridgeHoldMaxSec") then
				return false
			end
			return (armyNear(cut.x, cut.y, scaled(num("bots.bridgeThreatCells")))) >= num("bots.bridgeThreatWorth")
		end
		for id, cut in sim.roadCuts do
			if manned[id] or (cutHold[id] or -1) > sim.time or holdOwnBlow(cut) then
				continue
			end
			local ours = closeToUs(cut.x, cut.y)
			if not ours then
				for _, c in cut.cells do
					if onRoute[c] then
						ours = true
						break
					end
				end
			end
			if ours then
				local e = nearest(cut.x, cut.y)
				local n = sim.orderRoadRepair(side, "cut", id, { e.id })
				if n > 0 then
					if e.path or (e.x - cut.x) ^ 2 + (e.y - cut.y) ^ 2 <= (num("roads.cutRadius") + num("roads.repairReach")) ^ 2 then
						return
					end
					sim.orderStop(side, { e.id })
					cutHold[id] = sim.time + num("bots.bridgeHoldSec")
				end
			end
		end
		-- the game's VWe: the most worn route cell at or above the threshold
		local best, top = -1, math.max(1, math.ceil(num("bots.wearMendFrom") * sim.roads.WEAR_MAX))
		for c in onRoute do
			if sim.roads.isRoad(c) and sim.roads.wearRaw(c) >= top then
				best, top = c, sim.roads.wearRaw(c) + 1
			end
		end
		if best >= 0 then
			local e = nearest(best % W + 0.5, best // W + 0.5)
			if sim.orderRoadRepair(side, "wear", best, { e.id }) > 0 then
				return
			end
		end
		local first = idleEng[1]
		for _, st in sim.list do
			if st.alive and st.cat == "structure" and st.side == side and st.kind ~= "rig" and (st.built or 1) >= 1
				and st.hp < st.maxHp * 0.7 then
				local n = sim.orderRepair(side, st.id, { first.id })
				if n > 0 then
					return
				end
			end
		end
		-- the game's kat: damaged rigs of ours that nobody contests, wrecked first, then the lowest hp,
		-- each get the nearest idle engineer unless one of ours already mends it; one it can't reach
		-- is called off
		local hurt = {}
		for _, rg in sim.rigs do
			if rg.side == side and rg.hp < rg.maxHp and not rg.contested and not rg.capture then
				table.insert(hurt, rg)
			end
		end
		table.sort(hurt, function(a: any, b: any)
			if (a.wrecked and 1 or 0) ~= (b.wrecked and 1 or 0) then
				return a.wrecked == true
			end
			if a.hp ~= b.hp then
				return a.hp < b.hp
			end
			return a.id < b.id
		end)
		for _, rg in hurt do
			local busy = false
			for _, e in sim.list do
				if e.alive and e.side == side and e.repairId == rg.id then
					busy = true
					break
				end
			end
			if not busy then
				local e = nearest(rg.x, rg.y)
				if sim.orderRepair(side, rg.id, { e.id }) > 0 then
					local rr = num("rigs.radius") + num("engineers.reach")
					if e.path or (e.x - rg.x) ^ 2 + (e.y - rg.y) ^ 2 <= rr * rr then
						return
					end
					sim.orderStop(side, { e.id })
				end
			end
		end
		-- the game's Jst: now and then the last idle engineer goes to sabotage an enemy rig's road home,
		-- 30-70% of the way along it, picking among the rigs with the most trucks in sight.
		-- APPROX: the rig's owner is taken as known.
		if #idleEng < num("bots.sabotageSpare") or sim.time < num("bots.graceSec")
			or sim.time - lastSabotage < num("bots.sabotageEverySec") or rand() > persona.raid * num("bots.sabotageChance") then
			return
		end
		local targets = {}
		for _, rg in sim.rigs do
			if rg.side > 0 and rg.side ~= side and rg.connected and rg.route and #rg.route > 0 then
				table.insert(targets, rg)
			end
		end
		if #targets == 0 then
			return
		end
		local grid = {}
		sim.visionFor(side, grid)
		local function trucksSeen(rg: any): number
			local n = 0
			for _, t in sim.list do
				if t.alive and t.kind == "truck" and t.from == rg.id then
					local c = sim.roads.cellAt(t.x, t.y)
					if c >= 0 and grid[c + 1] == 2 then
						n += 1
					end
				end
			end
			return n
		end
		local most = 0
		for _, rg in targets do
			most = math.max(most, trucksSeen(rg))
		end
		local pool = targets
		if most > 0 then
			pool = {}
			for _, rg in targets do
				if trucksSeen(rg) == most then
					table.insert(pool, rg)
				end
			end
		end
		local rg = pool[math.floor(rand() * #pool) + 1]
		local route = rg.route
		local d = math.floor(#route * 0.3)
		local cell = route[d + math.floor(rand() * math.max(1, math.floor(#route * 0.4))) + 1]
		if cell and sim.roads.isRoad(cell) and sim.orderSabotage(side, cell, { idleEng[#idleEng].id }) > 0 then
			lastSabotage = sim.time
		end
	end

	---------------------------------------------------------------- air drops and bomb trucks (pat)

	-- the game's CN: the point, or the first of 12 spots bots.paraShiftCells x cellScale round it
	-- that a drop can land on
	local function dropSpot(x: number, y: number): any
		if not sim.dropProblem(x, y) then
			return { x = x, y = y }
		end
		local n = scaled(num("bots.paraShiftCells"))
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			local px, py = x + math.cos(a) * n, y + math.sin(a) * n
			if not sim.dropProblem(px, py) then
				return { x = px, y = py }
			end
		end
		return nil
	end
	-- the game's y0e: where to drop from `from` (within reach): on it if it is ours and threatened,
	-- else on a target our groups are sent at, else on the nearest rig that is not ours
	local function dropTarget(from: any, reach: number): any
		local function ok(p: any): boolean
			return p ~= nil and (reach == math.huge or hypot(p.x - from.x, p.y - from.y) <= reach)
		end
		if from.owner == side and enemyNear(from.x, from.y, from.radius * 2) > 0 then
			local p = dropSpot(from.x, from.y)
			if ok(p) then
				return p
			end
		end
		local seen = {}
		for _, t in self.orders do
			local k = key(t)
			if not seen[k] then
				seen[k] = true
				if targetValid(t) then
					local e = orderTarget(t)
					if e then
						local x, y = e.x, e.y
						if e.cell and t.kind ~= "rig" and t.kind ~= "city" then
							x, y = e.cell % MW + 0.5, e.cell // MW + 0.5
						end
						local p = dropSpot(x, y)
						if ok(p) then
							return p
						end
					end
				end
			end
		end
		local rigs = {}
		for _, rg in sim.rigs do
			local o = rigOwner(rg)
			if o ~= side and (o < 0 or canAttack(side, o)) then
				table.insert(rigs, rg)
			end
		end
		table.sort(rigs, function(a, b)
			return hypot(a.x - from.x, a.y - from.y) < hypot(b.x - from.x, b.y - from.y)
		end)
		for _, rg in rigs do
			local p = dropSpot(rg.x, rg.y)
			if ok(p) then
				return p
			end
		end
		return nil
	end
	-- the game's w0e: the known enemy building worth a bomb truck most from (x, y): factory 5, SAM
	-- 4, barracks 3, radar / AT gun / HQ 2, bunker 1.5, else 1; x 1.5 if armed; / (1 + distance /
	-- bots.demoFarCells x cellScale)
	local DEMO_WORTH = { factory = 5, sam = 4, barracks = 3, radar = 2, atgun = 2, bunker = 1.5, hq = 2 }
	local function demoTarget(x: number, y: number): any
		local far = scaled(num("bots.demoFarCells"))
		local best, bestV = nil, 0
		for _, st in intel.structures do
			if canAttack(side, st.owner) then
				local cx, cy = st.cell % MW + 0.5, st.cell // MW + 0.5
				local key_ = `structures.{st.kind}.dps`
				local armed = sim.rules:has(key_) and num(key_) > 0
				local v = (DEMO_WORTH[st.kind] or 1) * (if armed then 1.5 else 1) / (1 + hypot(cx - x, cy - y) / far)
				if v > bestV then
					best, bestV = { x = cx, y = cy }, v
				end
			end
		end
		return best
	end
	local function airPowers()
		-- idle bomb trucks go for the best building in sight
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "unit" and sim.isDemo(e) and not (e.path and e.pathIndex and e.pathIndex <= #e.path) then
				local t = demoTarget(e.x, e.y)
				if t then
					sim.orderMove(side, { e.id }, t.x, t.y)
				end
			end
		end
		for _, st in sim.settlements do
			if st.owner == side and st.trait == "airfield" and not sim.airfieldProblem(side, st) then
				local p = dropTarget(st, num("cities.traits.airfield.reach"))
				if p then
					sim.callAirfield(side, st.id, p.x, p.y)
				end
			end
		end
		local cap = sim.capitalOf()
		if cap then
			if (sim.capitalPower(side, "para")) == "ready" then
				local p = dropTarget(cap, math.huge)
				if p then
					sim.callParatroopers(side, p.x, p.y)
				end
			end
			if (sim.capitalPower(side, "demo")) == "ready" then
				local t = demoTarget(cap.x, cap.y)
				if t then
					sim.deployDemo(side, t.x, t.y)
				end
			end
		end
	end

	---------------------------------------------------------------- recon drone (tat)

	-- the game's eat: a known enemy SAM could reach a drone circling there
	local function samCovered(x: number, y: number): boolean
		local reach = num("structures.sam.range") + sim.droneScanRadius() * num("intel.droneOrbitShare") + num("intel.droneTrailRadius")
		for _, st in intel.structures do
			if st.kind == "sam" and canAttack(st.owner, side) then
				if hypot(st.cell % MW + 0.5 - x, st.cell // MW + 0.5 - y) <= reach then
					return true
				end
			end
		end
		return false
	end
	-- the game's tat: after bots.droneAfterSec, now and then (droneChance per think) send the drone
	-- over a target our groups are going for, a radar contact near home, an enemy rig or an enemy HQ
	-- that we don't see now, skipping spots a known SAM covers. It is bought only with droneBuyOil x
	-- its price in hand.
	local function drone()
		if sim.time < num("bots.droneAfterSec") then
			return
		end
		local state = sim.droneState(side)
		if state ~= "ready" and state ~= "buy" then
			return
		end
		if state == "buy" and sim.sides[side].oil < num("intel.reconCost") * num("bots.droneBuyOil") then
			return
		end
		if rand() >= num("bots.droneChance") then
			return
		end
		local hq = sim.hqOf(side)
		if not hq then
			return
		end
		local hx, hy = hq.cell % MW + 0.5, hq.cell // MW + 0.5
		local function unseen(p: any): boolean
			return not fresh(p.x, p.y)
		end
		local function byDist(a: any, b: any): boolean
			return hypot(a.x - hx, a.y - hy) < hypot(b.x - hx, b.y - hy)
		end
		local orders = {}
		local seen = {}
		for _, t in self.orders do
			local k = key(t)
			if not seen[k] and targetValid(t) then
				seen[k] = true
				local e = orderTarget(t)
				local owner = if t.kind == "rig" then rigOwner(e) elseif t.kind == "city" then cityOwner(e) else (if e then e.side else -1)
				if e and owner > 0 and owner ~= side then
					local x, y = e.x, e.y
					if e.cell and t.kind ~= "rig" and t.kind ~= "city" then
						x, y = e.cell % MW + 0.5, e.cell // MW + 0.5
					end
					local p = { x = x, y = y }
					if unseen(p) then
						table.insert(orders, p)
					end
				end
			end
		end
		local watch = scaled(num("bots.droneWatchCells"))
		local near = {}
		for _, ct in intel.contacts do
			if hypot(ct.x - hx, ct.y - hy) <= watch then
				table.insert(near, { x = ct.x, y = ct.y })
			end
		end
		table.sort(near, byDist)
		local rigs = {}
		for _, rg in sim.rigs do
			local o = rigOwner(rg)
			if o > 0 and o ~= side and canAttack(side, o) and unseen(rg) then
				table.insert(rigs, { x = rg.x, y = rg.y })
			end
		end
		table.sort(rigs, byDist)
		local hqs = {}
		for _, e in sim.list do
			if e.alive and e.kind == "hq" and canAttack(side, e.side) then
				local p = { x = e.cell % MW + 0.5, y = e.cell // MW + 0.5 }
				if unseen(p) then
					table.insert(hqs, p)
				end
			end
		end
		table.sort(hqs, byDist)
		local list = {}
		local first = if rand() < persona.defence then { near, orders } else { orders, near }
		local groups = { first[1], first[2], rigs, hqs }
		for gi, g in groups do
			for i, p in g do
				if not (g == near and i > 1) then
					table.insert(list, p)
				end
			end
		end
		for _, p in list do
			if not samCovered(p.x, p.y) then
				sim.launchDrone(side, p.x, p.y)
				return
			end
		end
	end

	---------------------------------------------------------------- rocket barrages (Gst / Gbe)

	-- the game's Gbe: enemy rigs worth a strike (after bots.graceSec, at least rigStrike.farCells x
	-- cellScale from our HQ, not struck in the last againSec, not a wreck seen lately): pump rate x paySec
	local function rigStrikes(): { any }
		if not sim.rules:flag("bots.rigStrike.on") or sim.time < num("bots.graceSec") then
			return {}
		end
		local hq = sim.hqOf(side)
		local out = {}
		for _, rg in sim.rigs do
			local o = rigOwner(rg)
			if o > 0 and o ~= side and canAttack(side, o)
				and not (hq and hypot(rg.x - hq.x, rg.y - hq.y) < scaled(num("bots.rigStrike.farCells")))
				and not (rg.wrecked and fresh(rg.x, rg.y)) -- a wreck seen lately is left alone
				and sim.time - (self.rigStruck[rg.id] or -math.huge) >= num("bots.rigStrike.againSec") then
				table.insert(out, { rig = rg, x = rg.x, y = rg.y, worth = sim.pumpRate(rg) * num("bots.rigStrike.paySec") })
			end
		end
		return out
	end
	-- the game's Gst: each reloaded, idle launcher fires at the best thing in its reach: a known enemy
	-- building (cost, +200 if armed), an enemy unit seen this think (its worth), or an enemy rig
	-- (rigStrikes, if worth more)
	local function barrages()
		local strikes = rigStrikes()
		for _, e in sim.list do
			if e.alive and e.side == side and e.cat == "unit" and not e.inside and text(sim.unitKey(e) .. ".weapon") == "salvo"
				and not e.barrage and (e.shotTimer or 0) <= 0 and not e.attackId and not e.garrisonCity then
				local range = num(sim.unitKey(e) .. ".range")
				local minR = sim.minRangeOf(sim.unitKey(e)) -- the game's lS (the republic's missile reaches less close)
				local best, bestV, rigId = nil, 0, nil
				for _, st in intel.structures do
					if canAttack(side, st.owner) then
						local x, y = st.cell % MW + 0.5, st.cell // MW + 0.5
						local d = hypot(x - e.x, y - e.y)
						if d <= range and d >= minR then
							local k = `structures.{st.kind}`
							local v = num(k .. ".cost") + (if num(k .. ".dps") > 0 then 200 else 0)
							if v > bestV then
								best, bestV = { x = x, y = y }, v
							end
						end
					end
				end
				for _, u in intel.units do
					if u.t >= sim.time - num("bots.thinkSec") and canAttack(side, u.owner) then
						local d = hypot(u.x - e.x, u.y - e.y)
						if d <= range and d >= minR then
							local v = unitWorth(u.kind)
							if v > bestV then
								best, bestV = { x = u.x, y = u.y }, v
							end
						end
					end
				end
				for _, rs in strikes do
					local d = hypot(rs.x - e.x, rs.y - e.y)
					if d <= range and d >= minR and rs.worth > bestV then
						best, bestV, rigId = { x = rs.x, y = rs.y }, rs.worth, rs.rig.id
					end
				end
				if best then
					local n = sim.orderBarrage(side, { e.id }, best.x, best.y)
					if n > 0 then
						if rigId then
							self.rigStruck[rigId] = sim.time
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- artillery base (Zst / m0e)

	-- the game's m0e: the known enemy unit or building whose neighbourhood (within r) is worth most,
	-- among points ok() accepts. Units seen this think are worth max(their worth, half their cost);
	-- buildings their cost plus a firepower worth (the game's KQ)
	local function bestCluster(r: number, ok: (number, number) -> boolean): any
		local pts = {}
		for _, u in intel.units do
			if u.t >= sim.time - num("bots.thinkSec") and canAttack(side, u.owner)
				and text(`units.{u.kind}.armour`) ~= "air" then
				table.insert(pts, { x = u.x, y = u.y, w = math.max(unitWorth(u.kind), num(`units.{u.kind}.cost`) * 0.5) })
			end
		end
		for _, st in intel.structures do
			if canAttack(side, st.owner) then
				local k = `structures.{st.kind}`
				local dps = num(k .. ".dps")
				local kq = 0
				if dps > 0 then
					local vs = math.max(num(k .. ".vs.soft"), num(k .. ".vs.armour"), 0.3)
					kq = st.hp / 100 * (dps * vs / 8) * 30
				end
				table.insert(pts, { x = st.cell % MW + 0.5, y = st.cell // MW + 0.5, w = kq + num(k .. ".cost") })
			end
		end
		local best = nil
		for _, p in pts do
			if ok(p.x, p.y) then
				local w = 0
				for _, q in pts do
					if (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 <= r * r then
						w += q.w
					end
				end
				if not best or w > best.worth then
					best = { x = p.x, y = p.y, worth = w }
				end
			end
		end
		return best
	end
	-- the game's Zst: each working base fires a barrage at the best cluster in range when it is worth
	-- bots.artyBarrageWorth x (margin / 1.5), and a flare (over what an attack group is going for, or at
	-- night the best cluster) with artyFlareChance by night / artyFlareDayChance by day
	local function artyStrikes()
		local bases = {}
		for _, e in sim.list do
			if e.alive and e.side == side and e.kind == "artybase" and not sim.inactiveReason(e) then
				table.insert(bases, e)
			end
		end
		if #bases == 0 then
			return
		end
		local night = sim.nightAmount() >= num("daylight.nightNoticeAt")
		local goal = nil
		for _, o in self.orders do
			if o.kind == "structure" then
				local st = sim.entities[o.id]
				if st then
					local W = sim.roads.width
					goal = { x = st.cell % W + 0.5, y = st.cell // W + 0.5 }
					break
				end
			end
		end
		local rg = num("artyBase.range")
		for _, b in bases do
			local W = sim.roads.width
			local bx, by = b.cell % W + 0.5, b.cell // W + 0.5
			local function inRange(x: number, y: number): boolean
				return hypot(x - bx, y - by) <= rg
			end
			local ready = b.strikeReady or {}
			if sim.killsOf(side) >= num("artyBase.barrage.price") and (ready.barrage or 0) - sim.time <= 0 then
				local d = bestCluster(num("artyBase.barrage.spread") + num("artyBase.barrage.splash"), inRange)
				if d and d.worth >= num("bots.artyBarrageWorth") * (persona.attackMargin / 1.5) then
					sim.artyStrike(side, b.id, "barrage", d.x, d.y)
				end
			end
			if sim.killsOf(side) >= num("artyBase.flare.price") and ((b.strikeReady or {}).flare or 0) - sim.time <= 0 then
				local d = if goal and inRange(goal.x, goal.y) then goal
					elseif night then bestCluster(num("artyBase.flare.spread") + num("artyBase.flare.radius"), inRange)
					else nil
				if d and rand() < (if night then num("bots.artyFlareChance") else num("bots.artyFlareDayChance")) then
					sim.artyStrike(side, b.id, "flare", d.x, d.y)
				end
			end
		end
	end

	---------------------------------------------------------------- IFV transport (jst)

	-- the game's jst: a loaded IFV unloads when an armed enemy is within its sight, or when it stands
	-- idle away from home (botHomeCells of the HQ); an idle IFV at home with room takes idle riders
	-- within botGatherCells. Boarders and the IFVs they board leave this think's pool.
	local function transports(pool: { any })
		local hq = sim.hqOf(side)
		local home = num("transport.botHomeCells")
		local function atHome(e: any): boolean
			return hq ~= nil and hypot(e.x - hq.x, e.y - hq.y) <= home
		end
		local carriers = (sim.rules.data["transport.carriers"] :: { string }?) or {}
		for _, c in sim.list do
			if c.alive and c.side == side and c.cargo and #c.cargo > 0 and table.find(carriers, c.kind) then
				local idleNow = not c.path and not c.attackId
				if sim.hostileNear(side, c.x, c.y, num(`units.{c.kind}.sight`)) or (idleNow and not atHome(c)) then
					sim.orderUnload(side, { c.id })
				end
			end
		end
		local busy: { [number]: boolean } = {}
		for _, u in sim.list do
			if u.alive and u.side == side and u.boarding then
				busy[u.boarding] = true
			end
		end
		local gather = num("transport.botGatherCells")
		for _, c in pool do
			if table.find(carriers, c.kind) and idle(c) and not c.path and atHome(c) and sim.roomIn(c) > 0 then
				local near = {}
				for _, u in pool do
					if idle(u) and not u.path and sim.canRide(u) and hypot(u.x - c.x, u.y - c.y) <= gather then
						table.insert(near, u.id)
					end
				end
				if #near > 0 then
					local n = sim.orderBoard(side, c.id, near)
					if n > 0 then
						busy[c.id] = true
					end
				end
			end
		end
		for i = #pool, 1, -1 do
			if pool[i].boarding or busy[pool[i].id] then
				table.remove(pool, i)
			end
		end
	end

	---------------------------------------------------------------- refineries
	-- the game's Ist, every refinery.bots.everySec: with refinery.cost + bots.keepOil oil and none of
	-- ours going up, build one in the held town that the most of our trucking rigs (not already
	-- hauling to a refinery) would reach at least saveShare closer, and saveCells x cell scale
	-- closer, than the HQ
	self.refineryAt = 0
	local function refinery()
		if not (sim.rules:has("refinery.on") and sim.rules:flag("refinery.on")) or sim.time < self.refineryAt then
			return
		end
		self.refineryAt = sim.time + num("refinery.bots.everySec")
		local hq = sim.hqOf(side)
		if not hq then
			return
		end
		local keep = 1 - num("refinery.bots.saveShare")
		local cells = num("refinery.bots.saveCells") * num("match.cellScale")
		if sim.sides[side].oil < num("refinery.cost") + num("refinery.bots.keepOil") then
			return
		end
		for _, st in sim.settlements do
			if st.refinery and st.refinery.owner == side and st.refinery.built < 1 then
				return
			end
		end
		local rigs = {}
		for _, rg in sim.rigs do
			if rg.side == side and rg.connected and rg.route and #rg.route > 0 and sim.trucksOf(rg.id) > 0 then
				table.insert(rigs, rg)
			end
		end
		local best, bestN = nil, 0
		for _, st in sim.settlements do
			if st.owner == side and not sim.refineryProblem(side, st.id) then
				local n = 0
				for _, rg in rigs do
					local toTown = hypot(rg.x - st.x, rg.y - st.y)
					local toHq = hypot(rg.x - hq.x, rg.y - hq.y)
					if rg.refinery == nil and toTown <= toHq * keep and toHq - toTown >= cells then
						n += 1
					end
				end
				if n > bestN then
					best, bestN = st, n
				end
			end
		end
		if best then
			sim.buildRefinery(side, best.id)
		end
	end

	---------------------------------------------------------------- road signs
	-- the game's iat: signs it put up come down after bots.signHoldSec (or once gone); a truck of ours
	-- held by the enemy for bots.signAfterSec gets a sign on the road a little ahead of it (one a think)
	self.signs = {} :: { [number]: number }
	local function roadSigns()
		for id, untilT in self.signs do
			if sim.time >= untilT or not sim.roadSigns[id] then
				sim.removeRoadSign(side, id)
				self.signs[id] = nil
			end
		end
		local ahead = math.floor(num("convoys.stopShortCells") + num("signs.radius") + 0.5)
		for _, t in sim.list do
			if t.alive and t.side == side and t.kind == "truck" and t.stopped == "enemy" and (t.waiting or 0) >= num("bots.signAfterSec")
				and t.path and #t.path > 0 then
				local c = t.path[math.min(#t.path, (t.pathIndex or 1) + ahead)]
				if c and sim.roads.isRoad(c) then
					local id = sim.placeRoadSign(side, c)
					if id then
						self.signs[id] = sim.time + num("bots.signHoldSec")
						return
					end
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
		local housing = rehouse()
		local p = if housing then nil else plan()
		roadSigns()
		local saving = not housing and trucks()
		if not housing and not saving then
			refinery()
			placeBuilding(p)
			training(p)
		end
		mend()
		scouts()
		drone()
		barrages()
		artyStrikes()
		mendUnits()
		fallBack()
		local pool = idleArmy()
		transports(pool)
		bridgeGuards(pool)
		defence(pool)
		garrison(pool)
		capital(pool)
		airPowers()
		attack(pool)
		sim.botTrenches(side) -- the game's JUe: trench lines, clearing the way, manning
	end
	self.think = think

	-- the game's hX: where to land. By the persona's drop.bots shares: near home (its start point), by
	-- one of the drop.middleRigs rigs farthest from every start, or drop.rivalStandOff in from a rival's
	-- start towards the middle; each tried up to 12 times with drop.jitter (twice that after 6 tries)
	-- for a spot the drop accepts, with room by a road, apart from other bots' picks
	local function dropPick(): { x: number, y: number }
		local d = sim.drop
		local share = function(k: string): number
			local key = `drop.bots.{persona.id}.{k}`
			return if sim.rules:has(key) then num(key) else num(`drop.bots.balanced.{k}`)
		end
		local home, middle = share("home"), share("middle")
		local others = {}
		for s2, p in d.picks do
			if s2 ~= side and d.ready[s2] then
				table.insert(others, p)
			end
		end
		local apart = num("drop.apart")
		local function try(c: any, r: number): any
			for f = 0, 11 do
				local a = rand() * math.pi * 2
				local g = r * math.sqrt(rand()) * (if f < 6 then 1 else 2)
				local x, y = c.x + math.cos(a) * g, c.y + math.sin(a) * g
				local ok = not sim.landingProblem(x, y, side) and not sim.dropWarning(x, y)
				if ok then
					for _, o in others do
						if hypot(o.x - x, o.y - y) < apart then
							ok = false
						end
					end
				end
				if ok then
					return { x = x, y = y }
				end
			end
			return nil
		end
		local jitter = num("drop.jitter")
		local c = rand()
		local h = nil
		if c >= home and c < home + middle then
			local rigs = {}
			for _, rg in sim.rigs do
				local near = math.huge
				for _, hm in d.homes do
					near = math.min(near, hypot(rg.x - hm.x, rg.y - hm.y))
				end
				table.insert(rigs, { x = rg.x, y = rg.y, near = near })
			end
			table.sort(rigs, function(a, b)
				return a.near > b.near
			end)
			for i = 1, math.max(1, num("drop.middleRigs")) do
				local rg = rigs[i]
				if rg then
					local a = rand() * math.pi * 2
					local so = num("drop.rigStandOff")
					h = try({ x = rg.x + math.cos(a) * so, y = rg.y + math.sin(a) * so }, jitter)
					if h then
						break
					end
				end
			end
		elseif c >= home + middle then
			local rivals = {}
			for s2, hm in d.homes do
				if s2 ~= side and canAttack(side, s2) then
					table.insert(rivals, hm)
				end
			end
			local rv = rivals[math.floor(rand() * #rivals) + 1]
			if rv then
				local fx, fy = sim.roads.width / 2 - rv.x, sim.roads.height / 2 - rv.y
				local g = math.max(1e-9, hypot(fx, fy))
				local so = num("drop.rivalStandOff")
				h = try({ x = rv.x + fx / g * so, y = rv.y + fy / g * so }, jitter)
			end
		end
		h = h or try(d.homes[side], jitter)
		return h or { x = d.homes[side].x, y = d.homes[side].y }
	end

	function self.step(_dt: number)
		if sim.drop and sim.drop.phase ~= "done" then
			if sim.drop.phase == "pick" and not sim.drop.ready[side] then
				local p = dropPick()
				sim.setDropPick(side, p.x, p.y)
				sim.setDropReady(side)
			end
			return
		end
		if sim.time < self.nextThink then
			return
		end
		self.nextThink = sim.time + num("bots.thinkSec") * diff.think * (0.8 + rand() * 0.4)
		think()
	end

	return self
end

return Bot
