--!strict
--[[
	Bot (PROVISIONAL, milestone 1B): a small scripted opponent that plays through the same order
	functions as players (orderProduce / orderMove / orderAttack), every bots.thinkSec seconds.
	  1. keep the HQ queue busy with infantry while oil allows
	  2. send idle pairs of infantry to the nearest rig it doesn't own
	  3. once it has 8 idle infantry, send them all at the enemy HQ
	WarFront's real bot (personalities, threat maps, fog-limited) is far richer; that is later work.
]]
local Bot = {}

local ATTACK_SIZE = 8

function Bot.new(sim: any, side: number)
	local self = { side = side, timer = 0 }

	local function dist2(a: any, b: any): number
		return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
	end

	local function think()
		local s = sim.sides[side]
		if not s or s.lost then
			return
		end
		local hq = sim.entities[s.hqId]
		-- 1. production
		if hq and hq.queue and #hq.queue < 2 then
			sim.orderProduce(side, "infantry")
		end
		-- 2./3. idle infantry
		local idle, rigs, enemyHq = {}, {}, nil
		for _, e in sim.entities do
			if e.side == side and e.kind == "infantry" and not e.target and not e.attackId then
				table.insert(idle, e)
			elseif e.kind == "rig" and e.side ~= side then
				table.insert(rigs, e)
			elseif e.kind == "hq" and e.side ~= side and e.side ~= 0 then
				enemyHq = e
			end
		end
		-- units standing on a rig they are still capturing are busy
		local radius2 = sim.num("rigs.radius") ^ 2
		local free = {}
		for _, u in idle do
			local capturing = false
			for _, rig in rigs do
				if dist2(u, rig) <= radius2 then
					capturing = true
				end
			end
			if not capturing then
				table.insert(free, u)
			end
		end
		idle = free
		table.sort(idle, function(a, b)
			return a.id < b.id
		end)
		if #idle >= ATTACK_SIZE and enemyHq then
			local ids = {}
			for _, u in idle do
				table.insert(ids, u.id)
			end
			sim.orderAttack(side, ids, enemyHq.id)
			return
		end
		-- pairs go to the nearest rig not already being claimed by this bot
		local claimed: { [number]: boolean } = {}
		for _, e in sim.entities do
			if e.side == side and e.kind == "infantry" and e.target then
				for _, rig in rigs do
					if (rig.x - e.target.x) ^ 2 + (rig.y - e.target.y) ^ 2 < 1 then
						claimed[rig.id] = true
					end
				end
			end
		end
		local i = 1
		while i + 1 <= #idle do
			local a, b = idle[i], idle[i + 1]
			local best, bestD = nil, math.huge
			for _, rig in rigs do
				if not claimed[rig.id] then
					local d = dist2(a, rig)
					if d < bestD then
						best, bestD = rig, d
					end
				end
			end
			if not best then
				break
			end
			claimed[best.id] = true
			sim.orderMove(side, { a.id, b.id }, best.x, best.y)
			i += 2
		end
	end

	function self.step(dt: number)
		self.timer -= dt
		if self.timer <= 0 then
			self.timer = sim.num("bots.thinkSec")
			think()
		end
	end

	return self
end

return Bot
