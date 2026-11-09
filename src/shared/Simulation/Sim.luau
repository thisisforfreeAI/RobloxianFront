--!strict
--[[
	Sim: the authoritative match simulation for milestone 1B. Pure Luau (no Roblox services), so it runs
	in Lune tests and on the server. MatchService owns one Sim and calls Sim.step at match.tickHz (20 Hz).

	Systems (values from WarFront's rules unless marked PROVISIONAL):
	  economy     sides start with match.startOil; HQ trickle rigs.hqOil per second
	  production  HQ trains infantry: cost units.infantry.cost, units.infantry.buildSec, queue production.maxQueue
	  rigs        capture within rigs.radius when one side's capture weight >= rigs.need, rigs.captureSec;
	              an enemy rig is first neutralised in rigs.takeoverSec (PROVISIONAL reading); pumps rigs.oilPerSec
	              into a rigs.tank store
	  trucks      PROVISIONAL: on capture the owner gets trucks.startIdle free light trucks (max trucks.perRig).
	              Loop: drive to rig, wait for rigs.truckMinLoad, load trucks.loadPerSec up to capacity, drive to HQ,
	              unload in trucks.unloadSec, oil credited. Straight-line driving at convoys.speed (TEMP-002: no roads)
	  combat      units fire at the ordered target or the nearest enemy in range; damage per shot =
	              dps x reloadSec x vs[class] x armour facing (armoured targets) x armour.movingFire if moving.
	              Trucks are shootable (convoys.shootable); cargo is lost with the truck. The HQ fires too
	  victory     PROVISIONAL: a side loses when its HQ is destroyed (no command truck in the slice)
	Not in the slice: rigs taking damage, rich rigs, upgrades, roads, fog (TEMP-001), pathfinding (TEMP-002).
]]

local Sim = {}

export type Rules = {
	number: (any, string) -> number,
	has: (any, string) -> boolean,
	flag: (any, string) -> boolean,
}

export type Entity = {
	id: number,
	kind: string, -- "infantry", "tank", "scout", "truck", "hq", "rig"
	cat: string, -- "unit" | "structure"
	class: string, -- damage class: "soft" | "armour" | "structure"
	side: number, -- 0 = neutral
	x: number,
	y: number,
	heading: number,
	hp: number,
	maxHp: number,
	target: { x: number, y: number }?, -- move target (Movement)
	attackId: number?, -- explicit attack order
	cooldown: number,
	moved: boolean,
	-- rig
	store: number?,
	capSide: number?,
	capProgress: number?,
	-- truck
	rigId: number?,
	phase: string?,
	cargo: number?,
	timer: number?,
	-- hq
	queue: { { item: string, left: number } }?,
}

export type Side = { oil: number, hqId: number, lost: boolean }

export type Deps = {
	rules: Rules,
	movement: any, -- Shared.Simulation.Movement
	paceAt: (kind: string, x: number, y: number) -> number,
	unitClass: (kind: string) -> string, -- "soft" | "armour"
	starts: { { x: number, y: number } },
	rigs: { { x: number, y: number, name: string? } },
	width: number,
	height: number,
}

export type Event = { type: string, [string]: any }

local TRUCK = "truck"

local function dist(ax: number, ay: number, bx: number, by: number): number
	local dx, dy = bx - ax, by - ay
	return math.sqrt(dx * dx + dy * dy)
end

function Sim.new(deps: Deps)
	local r = deps.rules
	local self = {
		deps = deps,
		entities = {} :: { [number]: Entity },
		sides = {} :: { [number]: Side },
		nextId = 1,
		time = 0,
		winner = nil :: number?,
		events = {} :: { Event },
	}

	local function num(key: string): number
		return r:number(key)
	end
	self.num = num

	local function add(e: Entity): Entity
		e.id = self.nextId
		self.nextId += 1
		self.entities[e.id] = e
		return e
	end

	function self.spawnUnit(kind: string, side: number, x: number, y: number): Entity
		local hp = if kind == TRUCK then num("trucks.kinds.light.hp") else num(`units.{kind}.hp`)
		return add({
			id = 0, kind = kind, cat = "unit", class = if kind == TRUCK then "soft" else deps.unitClass(kind),
			side = side, x = x, y = y, heading = 0, hp = hp, maxHp = hp, cooldown = 0, moved = false,
		})
	end

	-- Map setup: HQs at the start positions, neutral rigs, start oil and start infantry.
	for side, s in deps.starts do
		local hpHq = num("structures.hq.hp")
		local hq = add({
			id = 0, kind = "hq", cat = "structure", class = "structure", side = side, x = s.x, y = s.y,
			heading = 0, hp = hpHq, maxHp = hpHq, cooldown = 0, moved = false, queue = {},
		})
		self.sides[side] = { oil = num("match.startOil"), hqId = hq.id, lost = false }
	end
	for _, rig in deps.rigs do
		local hpRig = num("rigs.damage.hp")
		add({
			id = 0, kind = "rig", cat = "structure", class = "structure", side = 0, x = rig.x, y = rig.y,
			heading = 0, hp = hpRig, maxHp = hpRig, cooldown = 0, moved = false,
			store = 0, capSide = 0, capProgress = 0,
		})
	end
	local centerX, centerY = deps.width / 2, deps.height / 2
	-- Units leave the HQ towards the map centre (rally point production.rallyCells away).
	local function rallyPoint(hq: Entity, slot: number): (number, number)
		local dx, dy = centerX - hq.x, centerY - hq.y
		local d = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
		local cells = num("production.rallyCells")
		local px, py = -dy / d, dx / d
		local spread = ((slot % 5) - 2) * 1.2
		return hq.x + dx / d * cells + px * spread, hq.y + dy / d * cells + py * spread
	end
	self.rallyPoint = rallyPoint
	for side, s in self.sides do
		local hq = self.entities[s.hqId]
		for i = 1, num("match.startInfantry") do
			local x, y = rallyPoint(hq, i + 1)
			self.spawnUnit("infantry", side, x, y)
		end
	end

	---------------------------------------------------------------- orders (already validated for shape)

	-- Returns the ids refused because the side does not own them.
	function self.orderMove(side: number, ids: { number }, x: number, y: number): { number }
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if e and e.cat == "unit" and e.side == side and e.kind ~= TRUCK then
				e.target = { x = x, y = y }
				e.attackId = nil
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
			if e and e.cat == "unit" and e.side == side and e.kind ~= TRUCK then
				e.target, e.attackId = nil, nil
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		return refused
	end

	function self.orderAttack(side: number, ids: { number }, targetId: number): ({ number }, string?)
		local t = self.entities[targetId]
		if not t or t.side == side or t.side == 0 or t.hp <= 0 then
			return {}, "invalid target"
		end
		local refused = {}
		for _, id in ids do
			local e = self.entities[id]
			if e and e.cat == "unit" and e.side == side and e.kind ~= TRUCK then
				e.attackId, e.target = targetId, nil
			elseif e and e.side ~= side then
				table.insert(refused, id)
			end
		end
		return refused, nil
	end

	function self.orderProduce(side: number, item: string): (boolean, string?)
		local s = self.sides[side]
		if not s or s.lost or self.winner then
			return false, "no side"
		end
		if item ~= "infantry" then
			return false, "HQ cannot make " .. item
		end
		local hq = self.entities[s.hqId]
		local queue = assert(hq.queue)
		if #queue >= num("production.maxQueue") then
			return false, "queue full"
		end
		local cost = num(`units.{item}.cost`)
		if s.oil < cost then
			return false, "not enough oil"
		end
		s.oil -= cost
		table.insert(queue, { item = item, left = num(`units.{item}.buildSec`) })
		return true, nil
	end

	---------------------------------------------------------------- systems

	local function damageClassMult(attackerKey: string, target: Entity): number
		local key = `{attackerKey}.vs.{target.class}`
		return if r:has(key) then num(key) else 0
	end

	local function facingMult(attacker: Entity, target: Entity): number
		if target.class ~= "armour" then
			return 1
		end
		local toAttacker = math.atan2(attacker.y - target.y, attacker.x - target.x)
		local diff = math.abs(((toAttacker - target.heading) + math.pi) % (2 * math.pi) - math.pi)
		local deg = math.deg(diff)
		if deg <= num("armour.frontDeg") then
			return num("armour.front")
		elseif deg >= num("armour.rearDeg") then
			return num("armour.rear")
		end
		return num("armour.side")
	end

	local function kill(e: Entity, by: Entity?)
		e.hp = 0
		self.entities[e.id] = nil
		table.insert(self.events, { type = "destroyed", id = e.id, kind = e.kind, side = e.side, by = by and by.side })
		if e.kind == "hq" then
			local s = self.sides[e.side]
			if s then
				s.lost = true
			end
		end
	end

	local function nearestEnemy(e: Entity, range: number): Entity?
		local best, bestD = nil, range
		for _, o in self.entities do
			if o.side ~= 0 and o.side ~= e.side and o.hp > 0 and o.kind ~= "rig" then
				local d = dist(e.x, e.y, o.x, o.y)
				if d <= bestD then
					best, bestD = o, d
				end
			end
		end
		return best
	end

	local function combat(dt: number)
		for _, e in self.entities do
			local key = if e.kind == "hq" then "structures.hq" elseif e.cat == "unit" and e.kind ~= TRUCK then `units.{e.kind}` else nil
			if key and e.hp > 0 then
				local dps = num(key .. ".dps")
				if dps > 0 then
					e.cooldown = math.max(0, e.cooldown - dt)
					local range = num(key .. ".range")
					local target: Entity? = nil
					if e.attackId then
						local t = self.entities[e.attackId]
						if not t or t.hp <= 0 then
							e.attackId = nil
						else
							target = t
							local d = dist(e.x, e.y, t.x, t.y)
							if d > range then
								-- close to combat.attackRangeShare of range, re-aiming as the target moves
								local share = num("combat.attackRangeShare")
								local k = 1 - (range * share) / d
								e.target = { x = e.x + (t.x - e.x) * k, y = e.y + (t.y - e.y) * k }
								target = nil
							else
								e.target = nil
							end
						end
					end
					if not target and not e.attackId then
						target = nearestEnemy(e, range)
					end
					if target and e.cooldown <= 0 then
						local reload = num(key .. ".reloadSec")
						local dmg = dps * reload * damageClassMult(key, target) * facingMult(e, target)
						if e.moved then
							dmg *= num("armour.movingFire")
						end
						e.cooldown = reload
						if e.cat == "unit" then
							e.heading = math.atan2(target.y - e.y, target.x - e.x)
						end
						if dmg > 0 then
							target.hp -= dmg
							if target.hp <= 0 then
								kill(target, e)
							end
						end
					end
				end
			end
		end
	end

	local function countTrucks(rigId: number): number
		local n = 0
		for _, o in self.entities do
			if o.kind == TRUCK and o.rigId == rigId then
				n += 1
			end
		end
		return n
	end

	local function rigs(dt: number)
		local radius = num("rigs.radius")
		local need = num("rigs.need")
		for _, rig in self.entities do
			if rig.kind == "rig" then
				local weight: { [number]: number } = {}
				for _, u in self.entities do
					if u.cat == "unit" and u.kind ~= TRUCK and u.side ~= 0 and dist(u.x, u.y, rig.x, rig.y) <= radius then
						local key = `units.{u.kind}.capture`
						weight[u.side] = (weight[u.side] or 0) + (if r:has(key) then num(key) else 0)
					end
				end
				local present, only = 0, 0
				for side, w in weight do
					if w > 0 then
						present += 1
						only = side
					end
				end
				local owner = rig.side
				if present == 1 and only ~= owner and weight[only] >= need then
					if owner ~= 0 then
						-- enemy rig: neutralise first (PROVISIONAL reading of rigs.takeoverSec)
						rig.capSide = only
						rig.capProgress = (rig.capProgress or 0) + dt / num("rigs.takeoverSec")
						if rig.capProgress >= 1 then
							rig.side, rig.capProgress, rig.store = 0, 0, 0
							table.insert(self.events, { type = "rigLost", id = rig.id, side = owner })
						end
					else
						if rig.capSide ~= only then
							rig.capSide, rig.capProgress = only, 0
						end
						rig.capProgress = (rig.capProgress or 0) + dt / num("rigs.captureSec")
						if rig.capProgress >= 1 then
							rig.side, rig.capProgress, rig.capSide = only, 0, 0
							table.insert(self.events, { type = "rigCaptured", id = rig.id, side = only })
							local s = self.sides[only]
							local hq = s and self.entities[s.hqId]
							if hq then
								local give = math.min(num("trucks.startIdle"), num("trucks.perRig") - countTrucks(rig.id))
								for i = 1, give do
									local t = self.spawnUnit(TRUCK, only, hq.x + (i - 2) * 0.9, hq.y + 1.5)
									t.rigId, t.phase, t.cargo, t.timer = rig.id, "toRig", 0, 0
								end
							end
						end
					end
				elseif present == 0 and (rig.capProgress or 0) > 0 then
					rig.capProgress = math.max(0, (rig.capProgress :: number) - num("rigs.decayPerSec") * dt)
				end
				if rig.side ~= 0 then
					rig.store = math.min(num("rigs.tank"), (rig.store or 0) + num("rigs.oilPerSec") * dt)
				end
			end
		end
	end

	local function trucks(dt: number)
		local speed = num("convoys.speed") * num("trucks.kinds.light.paceShare")
		local capacity = num("trucks.kinds.light.capacity")
		for _, t in self.entities do
			if t.kind == TRUCK then
				local rig = t.rigId and self.entities[t.rigId]
				local s = self.sides[t.side]
				local hq = s and self.entities[s.hqId]
				local function driveTo(x: number, y: number): boolean
					local d = dist(t.x, t.y, x, y)
					if d <= 1 then
						return true
					end
					local stepLen = math.min(d, speed * dt)
					t.heading = math.atan2(y - t.y, x - t.x)
					t.x += (x - t.x) / d * stepLen
					t.y += (y - t.y) / d * stepLen
					t.moved = true
					return false
				end
				if not rig or rig.side ~= t.side or not hq then
					-- rig lost or HQ gone: drive home and idle there (cargo kept until a rig is assigned)
					t.phase = "idle"
					if hq then
						driveTo(hq.x, hq.y + 1.5)
					end
				else
					if t.phase == "toRig" or t.phase == "idle" then
						t.phase = "toRig"
						if driveTo(rig.x, rig.y) then
							t.phase = "loading"
						end
					elseif t.phase == "loading" then
						local store = rig.store or 0
						if (t.cargo or 0) < capacity and (store >= num("rigs.truckMinLoad") or (t.cargo or 0) > 0) then
							local take = math.min(num("trucks.loadPerSec") * dt, store, capacity - (t.cargo or 0))
							rig.store = store - take
							t.cargo = (t.cargo or 0) + take
						end
						if (t.cargo or 0) >= capacity or ((t.cargo or 0) > 0 and (rig.store or 0) <= 0) then
							t.phase = "toHq"
						end
					elseif t.phase == "toHq" then
						if driveTo(hq.x, hq.y) then
							t.phase, t.timer = "unloading", num("trucks.unloadSec")
						end
					elseif t.phase == "unloading" then
						t.timer = (t.timer or 0) - dt
						if (t.timer :: number) <= 0 then
							s.oil += t.cargo or 0
							table.insert(self.events, { type = "delivered", side = t.side, oil = t.cargo })
							t.cargo, t.phase = 0, "toRig"
						end
					end
				end
			end
		end
	end

	local function production(dt: number)
		for side, s in self.sides do
			local hq = self.entities[s.hqId]
			if hq and hq.queue then
				local job = hq.queue[1]
				if job then
					job.left -= dt
					if job.left <= 0 then
						table.remove(hq.queue, 1)
						local x, y = rallyPoint(hq, self.nextId)
						self.spawnUnit(job.item, side, x, y)
					end
				end
			end
		end
	end

	local function economy(dt: number)
		for _, s in self.sides do
			if not s.lost then
				s.oil += num("rigs.hqOil") * dt
			end
		end
	end

	local function victory()
		if self.winner then
			return
		end
		local alive = {}
		for side, s in self.sides do
			if not s.lost then
				table.insert(alive, side)
			end
		end
		if #alive == 1 then
			self.winner = alive[1]
			table.insert(self.events, { type = "victory", side = alive[1] })
		elseif #alive == 0 then
			self.winner = 0
			table.insert(self.events, { type = "victory", side = 0 })
		end
	end

	local moveCtx = {
		speedOf = function(kind: string): number
			return num(`units.{kind}.speed`)
		end,
		paceAt = deps.paceAt,
	}

	function self.step(dt: number)
		if self.winner then
			return
		end
		self.time += dt
		for _, e in self.entities do
			e.moved = false
			if e.cat == "unit" and e.kind ~= TRUCK then
				e.moved = deps.movement.step(e, dt, moveCtx)
			end
		end
		trucks(dt)
		combat(dt)
		rigs(dt)
		production(dt)
		economy(dt)
		victory()
	end

	-- Drains events (for networking / logging).
	function self.takeEvents(): { Event }
		local ev = self.events
		self.events = {}
		return ev
	end

	return self
end

return Sim
