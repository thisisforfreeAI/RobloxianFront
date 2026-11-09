--!strict
--[[
	Pathing: WarFront's unit route planning and path following for foot units, ported from the game's
	own code. Pure Luau; Sim owns one instance.

	Planning (move orders)
	  * move table per unit type: cost of a terrain = slowest speed / pace there x movement.offRoadBias;
	    road cells cost slowest speed / (speed x roadMult). Pace off road (foot) =
	    1 / (1 + (terrain.moveCost - 1) x rough); tracks/wheels use movement.terrainPace.
	  * route: the game's A* over that table (8-way, no corner cutting, octile heuristic x
	    0.95 x cheapest cost), then the "no back" check: a route that swings behind the start by more
	    than movement.noBack.cells x cell scale is re-searched inside the allowed band and replaced if
	    it costs at most noBack.worth times more.
	  * destinations: one unit goes to the cell clicked (its exact point); a group gets slots. Foot
	    groups stand in ranks of up to movement.lineRankMax, movement.lineGapCells apart, across the
	    group's travel direction, nearest units taking the front rank, left to right as they stand.
	    Without a direction (or on a rig) slots ring out from the cell, nearest first.
	Following (each tick)
	  * pace from the unit's cell (on a road stretch, a non-road gap between road cells counts as
	    road), off-road waypoints jittered per unit so units do not share one line; corner cutting to
	    the next waypoint when it is within movement.cutReachCells and the straight line costs no
	    more; sliding along walls; a unit making under a quarter of its pace for
	    movement.drive.repathSec re-plans, and gives up after movement.drive.giveUpTries.
	APPROX: no shared group routes or flow fields (each unit plans its own route; the game shares one
	        route per group), no path guide, no separation push, no bridge-deck lanes, no column
	        pacing. Vehicles' turning (drive model) is not ported: the slice trains foot units only.
]]

local Pathing = {}

function Pathing.new(roads: any, num: (string) -> number, text: (string) -> string, legend: { string })
	local W, H = roads.width, roads.height
	local cellScale = num("match.cellScale")
	local self = {}

	local function passable(c: number): boolean
		return c >= 0 and roads.passable(c)
	end

	-- pace multiplier like the game's paceBy (road = roadMult, no class)
	local function paceBy(kind: string, terrain: string, road: boolean): number
		local k = `units.{kind}`
		local speed = num(k .. ".speed")
		local move = text(k .. ".move")
		if road then
			return speed * num(k .. ".roadMult")
		end
		if move == "tracks" or move == "wheels" then
			local key = `movement.terrainPace.{move}.{terrain}`
			local ok, v = pcall(num, key)
			return speed * math.max(0.05, if ok then v else 1)
		end
		return speed / math.max(0.001, 1 + (num(`terrain.{terrain}.moveCost`) - 1) * num(k .. ".rough"))
	end

	local tables: { [string]: { [string]: number } } = {}
	function self.moveTable(kind: string): { [string]: number }
		local t = tables[kind]
		if t then
			return t
		end
		t = {}
		local speed = num(`units.{kind}.speed`)
		local bias = math.max(1, num("movement.offRoadBias"))
		for _, terrain in legend do
			t[terrain] = speed / math.max(1e-6, paceBy(kind, terrain, false)) * bias
		end
		t["@road"] = speed / math.max(1e-6, paceBy(kind, "plains", true))
		tables[kind] = t
		return t
	end

	local function costFn(tab: { [string]: number }): (number) -> number
		return function(c: number): number
			if not passable(c) then
				return math.huge
			end
			if roads.isRoad(c) then
				return tab["@road"]
			end
			return tab[roads.terrain(c)] or math.huge
		end
	end

	local function minCost(tab: { [string]: number }): number
		local m = math.huge
		for _, v in tab do
			if v > 0 then
				m = math.min(m, v)
			end
		end
		return math.max(0.05, m * 0.95)
	end

	-- the game's routeBy (without the path guide)
	function self.route(from: number, to: number, kind: string): { number }?
		local tab = self.moveTable(kind)
		local cost = costFn(tab)
		if cost(to) == math.huge then
			return nil
		end
		local mc = minCost(tab)
		local maxNodes = math.floor(cellScale * cellScale * 60000)
		local u = roads.search(from, to, cost, { minCost = mc, maxNodes = maxNodes })
		local cells = num("movement.noBack.cells")
		if not u or #u < 2 or cells <= 0 then
			return u
		end
		local p = u[#u]
		local gx, gy = p % W, p // W
		local sx, sy = from % W, from // W
		local v = math.sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2)
		if v < 1 then
			return u
		end
		local bx, by = (gx - sx) / v, (gy - sy) / v
		local x = cells * cellScale
		local spread = math.max(0.001, num("movement.noBack.spread"))
		local function inBand(c: number): boolean
			local px, py = c % W - sx, c // W - sy
			return (px * bx + py * by + x) * spread >= math.abs(py * bx - px * by)
		end
		local all = true
		for _, c in u do
			if not inBand(c) then
				all = false
				break
			end
		end
		if all then
			return u
		end
		local s = roads.search(from, to, function(c: number): number
			return if inBand(c) then cost(c) else math.huge
		end, { minCost = mc, maxNodes = math.min(maxNodes, math.floor(#u * num("movement.noBack.nodesPerCell") + 0.5)) })
		if not s then
			return u
		end
		local function total(path: { number }): number
			local sum, prev = 0, from
			for _, c in path do
				local diag = math.abs(c % W - prev % W) + math.abs(c // W - prev // W) > 1
				sum += cost(c) * (if diag then math.sqrt(2) else 1)
				prev = c
			end
			return sum
		end
		return if total(s) <= total(u) * num("movement.noBack.worth") then s else u
	end

	---------------------------------------------------------------- slots

	function self.straightPassable(x0: number, y0: number, cell: number): boolean
		local ax, ay = cell % W + 0.5, cell // W + 0.5
		local steps = math.max(1, math.ceil(math.sqrt((ax - x0) ^ 2 + (ay - y0) ^ 2) * 8))
		local l = 0.32
		local function ok(x: number, y: number): boolean
			return passable(roads.cellAt(x, y))
		end
		for k = 0, steps do
			local u, d = x0 + (ax - x0) * k / steps, y0 + (ay - y0) * k / steps
			if not ok(u, d) or (k > 0 and not (ok(u - l, d - l) and ok(u + l, d - l) and ok(u - l, d + l) and ok(u + l, d + l))) then
				return false
			end
		end
		return true
	end

	local function ringSlots(cell: number, n: number): { number }
		local out = {}
		local sx, sy = cell % W, cell // W
		local reach = num("movement.slotReachCells")
		local r = 0
		while #out < n and r <= reach do
			local ring = {}
			for y = sy - r, sy + r do
				for x = sx - r, sx + r do
					if math.max(math.abs(x - sx), math.abs(y - sy)) == r and x >= 0 and y >= 0 and x < W and y < H then
						local c = y * W + x
						if passable(c) then
							table.insert(ring, c)
						end
					end
				end
			end
			table.sort(ring, function(a, b)
				local da = math.sqrt((a % W - sx) ^ 2 + (a // W - sy) ^ 2)
				local db = math.sqrt((b % W - sx) ^ 2 + (b // W - sy) ^ 2)
				if da ~= db then
					return da < db
				end
				return false
			end)
			for _, c in ring do
				if #out < n then
					table.insert(out, c)
				end
			end
			r += 1
		end
		return out
	end

	local function moveSlots(cell: number, n: number, fx: number, fy: number, isRig: boolean): { number }
		local cx, cy = cell % W, cell // W
		if (fx == 0 and fy == 0) or n <= 1 or not passable(cell) or isRig then
			return ringSlots(cell, n)
		end
		local gap = math.max(1, num("movement.lineGapCells"))
		local rank = math.max(1, math.min(n, num("movement.lineRankMax")))
		local ux, uy = cx + 0.5, cy + 0.5
		local used: { [number]: boolean } = {}
		local out = {}
		local reach = math.ceil(gap) + 1
		for m = 0, n - 1 do
			local y = m // rank
			local w = math.min(rank, n - y * rank)
			local v = (m % rank - (w - 1) / 2) * gap
			local bx = ux - fy * v - fx * y * gap
			local by = uy + fx * v - fy * y * gap
			local x0, y0 = math.floor(bx), math.floor(by)
			local best, bestD = -1, math.huge
			for yy = y0 - reach, y0 + reach do
				for xx = x0 - reach, x0 + reach do
					if xx >= 0 and yy >= 0 and xx < W and yy < H then
						local c = yy * W + xx
						local d = (xx + 0.5 - bx) ^ 2 + (yy + 0.5 - by) ^ 2
						if d < bestD and not used[c] and passable(c) and self.straightPassable(ux, uy, c) then
							best, bestD = c, d
						end
					end
				end
			end
			if best >= 0 then
				used[best] = true
				table.insert(out, best)
			end
		end
		if #out < n then
			local count = 0
			for _ in used do
				count += 1
			end
			for _, c in ringSlots(cell, n + count) do
				if #out >= n then
					break
				end
				if not used[c] then
					used[c] = true
					table.insert(out, c)
				end
			end
		end
		return out
	end

	-- direction from the group to the goal (groupWay)
	local function groupWay(units: { any }, cell: number): (number, number)
		local sx, sy = cell % W + 0.5, cell // W + 0.5
		local rx, ry = 0, 0
		for _, u in units do
			rx += sx - u.x
			ry += sy - u.y
		end
		local l = math.sqrt(rx * rx + ry * ry)
		if l > 1e-6 then
			return rx / l, ry / l
		end
		return 0, 0
	end

	-- the game's groupSlots for foot ("men") formations; returns one cell per unit, in unit order
	function self.groupSlots(units: { any }, cell: number, isRig: boolean): { number }
		local sx, sy = cell % W + 0.5, cell // W + 0.5
		local fx, fy = groupWay(units, cell)
		local slots = moveSlots(cell, #units, fx, fy, isRig)
		if #slots == 0 then
			return {}
		end
		local out = {}
		if fx == 0 and fy == 0 then
			for i = 1, #units do
				out[i] = slots[(i - 1) % #slots + 1]
			end
			return out
		end
		local function lat(x: number, y: number): number
			return (x - sx) * -fy + (y - sy) * fx
		end
		local function latCell(c: number): number
			return lat(c % W + 0.5, c // W + 0.5)
		end
		local order = {}
		for i = 1, #units do
			order[i] = i
		end
		table.sort(order, function(a, b)
			local da = math.sqrt((units[a].x - sx) ^ 2 + (units[a].y - sy) ^ 2)
			local db = math.sqrt((units[b].x - sx) ^ 2 + (units[b].y - sy) ^ 2)
			if da ~= db then
				return da < db
			end
			return units[a].id < units[b].id
		end)
		local per = math.max(1, math.min(#units, num("movement.lineRankMax")))
		local g = 1
		while g <= #order do
			local m = {}
			for i = g, math.min(g + per - 1, #order) do
				table.insert(m, order[i])
			end
			table.sort(m, function(a, b)
				local la, lb = lat(units[a].x, units[a].y), lat(units[b].x, units[b].y)
				if la ~= lb then
					return la < lb
				end
				return a < b
			end)
			local ys = {}
			for v = 0, #m - 1 do
				table.insert(ys, slots[(g - 1 + v) % #slots + 1])
			end
			table.sort(ys, function(a, b)
				local la, lb = latCell(a), latCell(b)
				if la ~= lb then
					return la < lb
				end
				return a < b
			end)
			for v, idx in m do
				out[idx] = ys[v]
			end
			g += per
		end
		return out
	end

	---------------------------------------------------------------- following

	-- the game's lineClear: straight line from (x, y) to (tx, ty) through cells that cost no more than `ref`
	local function lineCost(kind: string, c: number): number
		if not passable(c) then
			return math.huge
		end
		local x, y = c % W + 0.5, c // W + 0.5
		return 1 / math.max(1e-6, self.paceAt(kind, x, y))
	end
	local function lineClear(e: any, tx: number, ty: number, refCell: number): boolean
		local r = lineCost(e.kind, refCell) * 1.000000001
		if r == math.huge then
			return false
		end
		local function ok(x: number, y: number): boolean
			return x >= 0 and y >= 0 and x < W and y < H and lineCost(e.kind, y * W + x) <= r
		end
		local l, c = e.x, e.y
		local hx, hy = math.floor(l), math.floor(c)
		local dx, dy = math.floor(tx), math.floor(ty)
		local p, g = tx - l, ty - c
		local m = if p > 0 then 1 else -1
		local yv = if g > 0 then 1 else -1
		local w = if p ~= 0 then 1 / math.abs(p) else math.huge
		local v = if g ~= 0 then 1 / math.abs(g) else math.huge
		local b = if p ~= 0 then (if p > 0 then hx + 1 - l else l - hx) * w else math.huge
		local k = if g ~= 0 then (if g > 0 then hy + 1 - c else c - hy) * v else math.huge
		while math.min(b, k) <= 1 do
			if math.abs(b - k) < 1e-9 then
				if not ok(hx + m, hy) or not ok(hx, hy + yv) then
					return false
				end
				hx += m
				hy += yv
				b += w
				k += v
			elseif b < k then
				hx += m
				b += w
			else
				hy += yv
				k += v
			end
			if hx == dx and hy == dy then
				return true
			end
			if not ok(hx, hy) then
				return false
			end
		end
		return true
	end

	self.paceAt = function(_kind: string, _x: number, _y: number): number
		return 1
	end -- set by Sim (the game's paceOn)

	local function jitter(id: number): (number, number)
		local d = ((id * 0.618034) % 1 - 0.5) * 0.6
		local f = (((id * 0.381966 + 0.5) % 1) - 0.5) * 0.6
		return d, f
	end

	local function waypoint(e: any, i: number, d: number, f: number): (number, number)
		local c = e.path[i]
		if i == #e.path and e.spot and roads.cellAt(e.spot.x, e.spot.y) == c then
			return e.spot.x, e.spot.y
		end
		local b = if roads.isRoad(c) then 0 else 1
		return c % W + 0.5 + d * b, c // W + 0.5 + f * b
	end

	-- one tick of path following (moveUnit, foot model). Returns true if the unit moved.
	function self.step(e: any, dt: number): boolean
		local path = e.path
		if not path or e.pathIndex > #path then
			return false
		end
		local here = roads.cellAt(e.x, e.y)
		local nextCell = path[e.pathIndex]
		local paceCell = here
		if here >= 0 and not roads.isRoad(here) and e.pathIndex > 1 and roads.isRoad(nextCell) and roads.isRoad(path[e.pathIndex - 1]) then
			paceCell = nextCell
		end
		local speed = num(`units.{e.kind}.speed`)
		local px, py = paceCell % W + 0.5, paceCell // W + 0.5
		local u = speed * self.paceAt(e.kind, if paceCell == here then e.x else px, if paceCell == here then e.y else py)
		local d, f = jitter(e.id)
		if e.pathIndex + 1 <= #path then
			local v = path[e.pathIndex + 1]
			local b = if roads.isRoad(v) then 0 else 1
			local kx, ky = v % W + 0.5 + d * b, v // W + 0.5 + f * b
			local cut = num("movement.cutReachCells")
			if (kx - e.x) ^ 2 + (ky - e.y) ^ 2 <= cut * cut and lineClear(e, kx, ky, path[e.pathIndex]) then
				e.pathIndex += 1
			end
		end
		e.pace = u
		local gx, gy = e.x, e.y
		local left = u * dt
		while left > 0 and e.pathIndex <= #path do
			local cx, cy = waypoint(e, e.pathIndex, d, f)
			local sx, sy = cx - e.x, cy - e.y
			local a = math.sqrt(sx * sx + sy * sy)
			if a <= left then
				e.x, e.y = cx, cy
				left -= a
				e.pathIndex += 1
			else
				local nx, ny = e.x + sx / a * left, e.y + sy / a * left
				local o = roads.cellAt(e.x, e.y)
				local n = roads.cellAt(nx, ny)
				if n ~= o and n >= 0 and o >= 0 and passable(o) and not passable(n) then
					local t = roads.cellAt(nx, e.y)
					local i = roads.cellAt(e.x, ny)
					if t >= 0 and (t == o or passable(t)) then
						ny = e.y
					elseif i >= 0 and (i == o or passable(i)) then
						nx = e.x
					else
						nx, ny = e.x, e.y
					end
				end
				e.x, e.y = nx, ny
				left = 0
			end
		end
		local moved = math.sqrt((e.x - gx) ^ 2 + (e.y - gy) ^ 2)
		if moved > 1e-6 then
			e.heading = math.atan2(e.y - gy, e.x - gx)
		end
		if e.pathIndex <= #path then
			if u > 0.001 and moved < u * dt * 0.25 then
				e.stall = (e.stall or 0) + dt
			else
				e.stall = 0
			end
			if e.stall > num("movement.drive.repathSec") then
				e.stall = 0
				e.stallTries = (e.stallTries or 0) + 1
				if e.stallTries > num("movement.drive.giveUpTries") then
					e.path, e.pathIndex, e.stallTries = {}, 1, 0
				else
					local goal = path[#path]
					e.path = self.route(roads.cellAt(e.x, e.y), goal, e.kind) or {}
					e.pathIndex = 1
				end
			end
		end
		return moved > 1e-6
	end

	return self
end

return Pathing
