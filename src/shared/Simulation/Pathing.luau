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
	        pacing.
	Vehicles (tracks / wheels) drive with the game's model (Uat, below): they accelerate and brake to a
	look-ahead point on the path, slow for corners, pivot on the spot (tracks) or make three-point turns
	(wheels), back up to a close goal behind them, and re-plan when stuck.
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

	-- `direct` (the game's moveTable(.., true), for a "straight over the land" move): no off-road bias,
	-- and roads cost what the land under them costs (1 where that land is impassable, as on a bridge)
	local tables: { [string]: { [string]: number } } = {}
	function self.moveTable(kind: string, direct: boolean?): { [string]: number }
		local key = if direct then kind .. "@direct" else kind
		local t = tables[key]
		if t then
			return t
		end
		t = {}
		local speed = num(`units.{kind}.speed`)
		local bias = if direct then 1 else math.max(1, num("movement.offRoadBias"))
		for _, terrain in legend do
			t[terrain] = speed / math.max(1e-6, paceBy(kind, terrain, false)) * bias
		end
		t["@road"] = if direct then 0 else speed / math.max(1e-6, paceBy(kind, "plains", true))
		tables[key] = t
		return t
	end

	-- the game's softShare: a crossable trench cell costs 1 / its pace share (never crossable at 0)
	local function softMove(kind: string): string
		return if text(`units.{kind}.armour`) == "air" then "air" else text(`units.{kind}.move`)
	end
	local function costFn(tab: { [string]: number }, kind: string?): (number) -> number
		local move = if kind then softMove(kind) else "foot"
		local fire, traps, wire = num("trenchWorks.kinds.fire.footPace"), num("trenchWorks.kinds.traps.footPace"), num("trenchWorks.kinds.wire.footPace")
		return function(c: number): number
			if not passable(c) then
				return math.huge
			end
			if roads.isRoad(c) then
				local r = tab["@road"]
				if r <= 0 then
					local t = tab[roads.terrain(c)]
					return if t and roads.landPassable(c) then t else 1
				end
				return r
			end
			local code = roads.trenchSoft(c)
			if code > 0 then
				local p = roads.softPace(move, code, fire, traps, wire)
				if p <= 0 then
					return math.huge
				end
				return (tab[roads.terrain(c)] or math.huge) * math.max(1, 1 / p)
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
		local cost = costFn(tab, kind)
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
				return a < b -- the game's sort is stable over cells listed in ascending order
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
	self.ringSlots = ringSlots

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

	---------------------------------------------------------------- vehicle drive model (the game's Uat)

	local DEG = math.pi / 180
	local TAU = math.pi * 2
	local function wrap(a: number): number -- the game's y6
		a %= TAU
		return if a > math.pi then a - TAU elseif a < -math.pi then a + TAU else a
	end
	local function clampTurn(a: number, m: number): number -- the game's IH
		return if a > m then m elseif a < -m then -m else a
	end
	local function drv(key: string): number
		return num("movement.drive." .. key)
	end
	local function opt(key: string, default: number): number
		local ok, v = pcall(num, key)
		return if ok and type(v) == "number" then v else default
	end
	-- the game's $at: top speed, acceleration, braking, turn rates and radius of a vehicle
	local function driveSpec(kind: string): any
		local k = `units.{kind}`
		local top = num(k .. ".speed") * math.max(1, opt(k .. ".roadMult", 1))
		local a = opt(k .. ".accelSec", 0)
		local accelSec = math.max(0.05, if a ~= 0 then a else 1)
		local brakeSec = math.max(0.05, opt(k .. ".brakeSec", accelSec))
		local tracks = text(k .. ".move") == "tracks"
		return {
			top = top, accel = top / accelSec, brake = top / brakeSec,
			turn = opt(k .. ".turnDegSec", 60) * DEG, pivot = if tracks then opt(k .. ".pivotDegSec", 30) * DEG else 0,
			radius = math.max(0.001, opt(k .. ".turnRadiusCells", 0.5)), tracks = tracks,
		}
	end
	local specs: { [string]: any } = {}
	local function specOf(kind: string): any
		local sp = specs[kind]
		if not sp then
			sp = driveSpec(kind)
			specs[kind] = sp
		end
		return sp
	end
	function self.isVehicle(kind: string): boolean -- the game's d2
		local m = text(`units.{kind}.move`)
		return m == "tracks" or m == "wheels"
	end
	-- the game's steer state (GI) and its reset (C0e)
	local function steerOf(e: any): any
		local st = e.steer
		if not st then
			st = { goal = -1, len = 0, best = math.huge, held = 0, repathed = false, back = false, pivot = false,
				shunt = false, tight = false, tries = 0, face = -1 }
			e.steer = st
		end
		return st
	end
	local function resetSteer(st: any, goal: number, len: number)
		st.goal, st.len, st.best, st.held, st.repathed, st.tries = goal, len, math.huge, 0, false, 0
		st.back, st.pivot, st.shunt, st.tight = false, false, false, false
	end
	-- the game's Ybe: stop
	local function halt(e: any, st: any)
		e.pace, e.reversing = 0, false
		st.back, st.shunt, st.pivot, st.tight = false, false, false, false
	end
	-- the game's _N: give up or finish here (the path is dropped unless this is its last cell)
	local function finish(e: any, st: any, here: number)
		if here ~= e.path[#e.path] then
			e.path = {}
		end
		st.goal = -1
		e.pathIndex = #e.path + 1
		halt(e, st)
	end
	-- the game's z8: every cell the straight line from the unit to (x, y) enters is passable
	local function lineOpen(e: any, x: number, y: number): boolean
		local sx, sy = e.x, e.y
		local n = math.max(1, math.ceil(math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) * 3))
		local last = roads.cellAt(sx, sy)
		for i = 1, n do
			local c = roads.cellAt(sx + (x - sx) * i / n, sy + (y - sy) * i / n)
			if c ~= last then
				if not passable(c) then
					return false
				end
				last = c
			end
		end
		return true
	end
	-- the game's SN: the point `dist` along the path from the unit, and the path index it lies on
	local function along(e: any, dist: number, d: number, f: number): (number, number, number)
		local rx, ry, left = e.x, e.y, dist
		for i = e.pathIndex, #e.path do
			local px, py = waypoint(e, i, d, f)
			local h = math.sqrt((px - rx) ^ 2 + (py - ry) ^ 2)
			if h >= left then
				local u = if h > 1e-9 then left / h else 0
				return rx + (px - rx) * u, ry + (py - ry) * u, i
			end
			left -= h
			rx, ry = px, py
		end
		return rx, ry, #e.path + 1
	end
	-- the game's Vat: path length ahead, up to `cap`
	local function lengthAhead(e: any, cap: number, d: number, f: number): number
		local rx, ry, l = e.x, e.y, 0
		local i = e.pathIndex
		while i <= #e.path and l < cap do
			local px, py = waypoint(e, i, d, f)
			l += math.sqrt((px - rx) ^ 2 + (py - ry) ^ 2)
			rx, ry = px, py
			i += 1
		end
		return l
	end
	-- the game's jbe: distance to the current waypoint plus the waypoints after it
	local function remaining(e: any, d: number, f: number): number
		if e.pathIndex > #e.path then
			return 0
		end
		local px, py = waypoint(e, e.pathIndex, d, f)
		return math.sqrt((px - e.x) ^ 2 + (py - e.y) ^ 2) + (#e.path - e.pathIndex)
	end
	-- the game's Bat: waypoint i counts as passed
	local function passedPoint(e: any, i: number, d: number, f: number): boolean
		local pass = drv("passCells")
		local ix, iy = waypoint(e, i, d, f)
		local c = math.sqrt((ix - e.x) ^ 2 + (iy - e.y) ^ 2)
		if c <= pass then
			return true
		end
		if c > pass * 3 then
			return false
		end
		local nx, ny = waypoint(e, i + 1, d, f)
		return (e.x - ix) * (nx - ix) + (e.y - iy) * (ny - iy) > 0
	end
	-- the game's Fat: advance past waypoints, cut a corner, arrive within arriveCells of the end
	local function advance(e: any, st: any, d: number, f: number)
		local n, before = #e.path, e.pathIndex
		while e.pathIndex < n and passedPoint(e, e.pathIndex, d, f) do
			e.pathIndex += 1
		end
		if e.pathIndex + 1 <= n then
			local nx, ny = waypoint(e, e.pathIndex + 1, d, f)
			local cut = num("movement.cutReachCells")
			if (nx - e.x) ^ 2 + (ny - e.y) ^ 2 <= cut * cut and lineClear(e, nx, ny, e.path[e.pathIndex]) and lineOpen(e, nx, ny) then
				e.pathIndex += 1
			end
		end
		if e.pathIndex ~= before then
			st.tight = false
		end
		if e.pathIndex == n then
			local lx, ly = waypoint(e, n, d, f)
			if math.sqrt((lx - e.x) ^ 2 + (ly - e.y) ^ 2) <= drv("arriveCells") then
				e.pathIndex = n + 1
			end
		end
	end
	-- the game's lineCells: the cells of a Bresenham line from a to b (a left out), added to `out`
	function self.lineCells(a: number, b: number, out: { number }?): { number }
		local o = out or {}
		local x, y = a % W, a // W
		local tx, ty = b % W, b // W
		local dx, dy = math.abs(tx - x), math.abs(ty - y)
		local sx, sy = if tx > x then 1 else -1, if ty > y then 1 else -1
		local err = dx - dy
		while x ~= tx or y ~= ty do
			local e2 = err * 2
			if e2 > -dy then
				err -= dy
				x += sx
			end
			if e2 < dx then
				err += dx
				y += sy
			end
			table.insert(o, y * W + x)
		end
		return o
	end

	-- the game's straightWay, for a "straight over the land" move: the straight line when it is open;
	-- otherwise a route on the direct move table (roads no cheaper than the land), pulled straight:
	-- from each corner it looks up to movement.directLookCells x cellScale cells along the route
	-- (halving) for the farthest cell it can walk to in a line. nil when there is no way.
	-- APPROX: no path guide or shared group route (the game's groupWayFrom).
	function self.straightWay(e: any, from: number, to: number): { number }?
		if from == to then
			return {}
		end
		if self.straightPassable(e.x, e.y, to) then
			return self.lineCells(from, to)
		end
		local tab = self.moveTable(e.kind, true)
		local cost = costFn(tab, e.kind)
		if cost(to) == math.huge then
			return nil
		end
		local p = roads.search(from, to, cost, { minCost = minCost(tab), maxNodes = math.floor(cellScale * cellScale * 60000) })
		if not p then
			return nil
		end
		local g = math.max(1, math.floor(num("movement.directLookCells") * cellScale + 0.5))
		local out = {}
		local y, wx, wy, b = from, e.x, e.y, 1
		while b <= #p do
			local k = b
			local x = math.min(g, #p - b)
			while x >= 1 do
				if self.straightPassable(wx, wy, p[b + x]) then
					k = b + x
					break
				end
				x = x // 2
			end
			if k == b then
				table.insert(out, p[b])
			else
				self.lineCells(y, p[k], out)
			end
			y = p[k]
			wx, wy = y % W + 0.5, y // W + 0.5
			b = k + 1
		end
		return out
	end

	local function cellAhead(x: number, y: number, g: number, dist: number): number
		return roads.cellAt(x + math.cos(g) * dist, y + math.sin(g) * dist)
	end
	local function rewalk(e: any, goal: number)
		e.path = self.route(roads.cellAt(e.x, e.y), goal, e.kind) or {}
		e.pathIndex = 1
	end

	-- one tick of the game's vehicle drive (Uat) at terrain pace `s`. Returns true if it moved.
	-- APPROX: no formations / shared group lanes, no overtaking, no dodging round blockers, no yard
	-- clearance, no traffic slowdown next to trucks, no column pacing.
	local function drive(e: any, dt: number, s: number): boolean
		local h = #e.path
		if e.pathIndex > h then
			return false
		end
		local L = specOf(e.kind)
		local st = steerOf(e)
		if st.goal ~= e.path[h] or st.len ~= h then
			resetSteer(st, e.path[h], h)
		end
		local d, f = jitter(e.id)
		if not e.headed then
			local px, py = waypoint(e, e.pathIndex, d, f)
			local nx, ny = px - e.x, py - e.y
			e.heading = if nx ~= 0 or ny ~= 0 then math.atan2(ny, nx)
				elseif e.faceX and e.faceY then math.atan2(e.faceY, e.faceX)
				else 0
			e.headed = true
		end
		local g = e.heading
		local gx0, gy0 = e.x, e.y
		advance(e, st, d, f)
		if e.pathIndex > h then
			halt(e, st)
			return false
		end
		local m = e.pace or 0
		local y = roads.cellAt(e.x, e.y)
		local pass = drv("passCells")
		-- lost sight of the waypoint: step back to one up to 3 behind that is clear
		do
			local px, py = waypoint(e, e.pathIndex, d, f)
			if e.pathIndex > 1 and not lineOpen(e, px, py) then
				for N = e.pathIndex - 1, math.max(1, e.pathIndex - 3), -1 do
					local qx, qy = waypoint(e, N, d, f)
					if not (math.sqrt((qx - e.x) ^ 2 + (qy - e.y) ^ 2) <= pass or not lineOpen(e, qx, qy)) then
						e.pathIndex = N
						st.tight = true
						break
					end
				end
			end
		end
		local v = remaining(e, d, f)
		local b = if st.tight then 0 else math.min(drv("lookMaxCells"), drv("lookCells") + m * drv("lookSec"))
		local C, M = waypoint(e, e.pathIndex, d, f)
		local k, x = C, M
		if b > 0 then
			k, x = along(e, b, d, f)
			if not lineOpen(e, k, x) then
				k, x = C, M
			end
		end
		local A = if math.sqrt((k - e.x) ^ 2 + (x - e.y) ^ 2) > 1e-9 then math.atan2(x - e.y, k - e.x) else g
		local P, Hh = wrap(A - g), wrap(A - g - math.pi)
		if e.pathIndex == h and y == e.path[h] and st.held >= 0.5 and math.abs(if st.back then Hh else P) > 60 * DEG then
			finish(e, st, y)
			return false
		end
		-- reverse to a close goal behind
		local revCells = if e.firing and e.aimX and math.abs(wrap(math.atan2(e.aimY - e.y, e.aimX - e.x) - g)) < math.pi / 2
			then drv("reverseThreatCells")
			else drv("reverseCells")
		if not st.back and not st.shunt and m <= L.top * 0.25 and v <= revCells then
			local lx, ly = waypoint(e, h, d, f)
			if math.abs(wrap(math.atan2(ly - e.y, lx - e.x) - g)) > drv("reverseDeg") * DEG then
				st.back, st.pivot = true, false
			end
		end
		if st.back and v > math.max(drv("reverseCells"), drv("reverseThreatCells")) * 1.5 then
			st.back = false
		end
		local T = math.min(pass, 0.5)
		local I = cellAhead(e.x, e.y, g, -T)
		local B = I == y or passable(I)
		local F = cellAhead(e.x, e.y, g, T)
		local U = not L.tracks
			and ((not B and F ~= y and not passable(F)) or (st.tight and st.held >= drv("shuffleSec") and math.abs(P) > 20 * DEG))
		if U then
			st.back = false
		end
		local D = math.huge
		if not st.back then
			if L.tracks then
				local N = (if st.tight then drv("pivotDoneDeg") * 2 else drv("pivotDeg")) * DEG
				if not st.pivot and math.abs(P) > N then
					st.pivot = true
				end
				if st.pivot and math.abs(P) <= drv("pivotDoneDeg") * DEG then
					st.pivot = false
				end
			else
				-- a point inside the turning circle on its side cannot be reached going forward
				local function inCircle(px: number, py: number): boolean
					local sg = math.sign(wrap(math.atan2(py - e.y, px - e.x) - g))
					if sg == 0 then
						sg = 1
					end
					local cx = e.x + math.cos(g + sg * math.pi / 2) * L.radius
					local cy = e.y + math.sin(g + sg * math.pi / 2) * L.radius
					return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2) < L.radius * 0.9
				end
				local yx, yy = along(e, math.max(b, L.radius * 2), d, f)
				local oe = inCircle(k, x) and inCircle(yx, yy)
				if not st.shunt and (math.abs(P) > drv("shuntDeg") * DEG or oe or (st.tight and math.abs(P) > 30 * DEG)) then
					if m <= L.top * 0.2 and B then
						st.shunt = true
					elseif B then
						D = s * 0.25
					end
				elseif
					st.shunt
					and ((math.abs(P) <= (if st.tight then math.min(drv("shuntDoneDeg"), 15) else drv("shuntDoneDeg")) * DEG and not oe) or not B)
				then
					st.shunt = false
				end
			end
		end
		local z = st.back or st.shunt
		local ne = if m > 0.001 then (e.reversing == true) else z
		local ee = if ne then Hh else P
		local Q = s
		if z then
			Q = s * drv("reversePace")
		else
			local N = m * m / (2 * L.brake)
			local oe = b + N + drv("cornerLookCells")
			local ie = 0
			for j = 1, 3 do
				local ax, ay, idx = along(e, oe * j / 3, d, f)
				local lx, ly = ax - e.x, ay - e.y
				if lx * lx + ly * ly > 1e-6 then
					ie = math.max(ie, math.abs(wrap(math.atan2(ly, lx) - g)))
				end
				if idx > h then
					break
				end
			end
			local free, full = drv("cornerFreeDeg") * DEG, drv("cornerFullDeg") * DEG
			local he = math.clamp((ie - free) / math.max(1e-6, full - free), 0, 1)
			Q *= 1 - (1 - drv("cornerShare")) * he
			Q *= if L.tracks
				then math.max(0.15, 1 - math.abs(P) / (drv("pivotDeg") * DEG))
				else math.max(0.35, 1 - math.abs(P) / (drv("shuntDeg") * DEG))
			local ue = cellAhead(e.x, e.y, g, math.max(pass, N))
			if ue ~= y and not passable(ue) then
				Q = math.min(Q, s * 0.3)
			end
		end
		if st.pivot or U then
			Q = 0
		end
		Q = math.min(Q, D)
		local E = lengthAhead(e, L.top * L.top / (2 * L.brake) + 1, d, f)
		Q = math.min(Q, math.max(L.top * num("movement.brakeFloor"), math.sqrt(2 * L.brake * E)))
		if ne ~= z then
			Q = 0 -- switching between forward and reverse: stop first
		end
		local Y = Q
		local te = m
		te = if te < Q then math.min(Q, te + L.accel * dt) else math.max(Q, te - L.brake * dt)
		if L.tracks then
			local N = if te < L.top * 0.05 then math.max(L.pivot, 1e-6) else L.turn
			g += clampTurn(if math.abs(ee) > math.pi - drv("asternDeg") * DEG then math.abs(ee) else ee, N * dt)
		elseif U then
			g += clampTurn(P, drv("idleWheelDegSec") * DEG * dt)
		else
			local N = math.min(L.turn, te / L.radius)
			g += clampTurn(if st.shunt and ne then P else ee, N * dt)
		end
		g = wrap(g)
		local re = if ne then g + math.pi else g
		local stepLen = te * dt
		local X, Z = e.x + math.cos(re) * stepLen, e.y + math.sin(re) * stepLen
		local se = roads.cellAt(X, Z)
		if se ~= y and not passable(se) then
			te = 0
			st.tight = true
		else
			e.x, e.y = X, Z
		end
		e.heading, e.pace = g, te
		e.reversing = if te > 0.001 then ne else z
		if v < st.best - 0.02 then
			st.best, st.held = v, 0
		elseif Y > 0 or st.pivot or U then
			st.held += dt
		end
		local moved = (e.x - gx0) ^ 2 + (e.y - gy0) ^ 2 > 1e-12
		if drv("closeCells") > 0 and v <= drv("closeCells") and st.held >= drv("closeSec") then
			finish(e, st, y)
			return moved
		end
		if st.held > drv("repathSec") and not st.repathed then
			rewalk(e, e.path[h])
			st.goal = if #e.path > 0 then e.path[#e.path] else -1
			st.len = #e.path
			st.repathed, st.tight, st.held, st.best = true, true, 0, math.huge
		elseif st.repathed and st.held > math.max(0, drv("giveUpSec") - drv("repathSec")) then
			local here = roads.cellAt(e.x, e.y)
			local goal = e.path[h]
			if here ~= goal and (st.tries or 0) < drv("giveUpTries") then
				local tries = (st.tries or 0) + 1
				rewalk(e, goal)
				if #e.path > 0 then
					resetSteer(st, e.path[#e.path], #e.path)
					st.tries, st.tight = tries, true
					return moved
				end
			end
			finish(e, st, here)
		end
		return moved
	end

	-- the game's Wat: a standing vehicle without a turret turns its hull towards what it is shooting
	-- at, else (rechecked every drive.faceSec) the nearest enemy within sight, kept while within
	-- sight x 1.25, at its pivot rate (tracks) or drive.idleWheelDegSec (wheels).
	-- `nearestEnemy(e, r)` is supplied by Sim.
	function self.idleTurn(e: any, dt: number, ticks: number, nearestEnemy: (any, number) -> any?)
		e.reversing = false
		local st = e.steer
		if st then
			st.back, st.shunt, st.pivot, st.tight = false, false, false, false
		end
		if e.inside then
			return
		end
		local k = `units.{e.kind}`
		local sight = num(k .. ".sight")
		local rx, ry
		if e.firing and e.aimX then
			rx, ry = e.aimX, e.aimY
		else
			local every = math.max(1, math.floor(drv("faceSec") * num("match.tickHz") + 0.5))
			if (e.id + ticks) % every == 0 then
				local t = nearestEnemy(e, sight)
				if t or st then
					steerOf(e).face = if t then t.id else -1
				end
				e.faceTarget = t
			end
			local u = e.faceTarget
			if not u or not u.alive or u.inside or (u.x - e.x) ^ 2 + (u.y - e.y) ^ 2 > (sight * 1.25) ^ 2 then
				return
			end
			rx, ry = u.x, u.y
		end
		if not e.headed then
			e.heading = if e.faceX and e.faceY then math.atan2(e.faceY, e.faceX) else (e.heading or 0)
			e.headed = true
		end
		if opt(k .. ".turretDegSec", 0) > 0 or (rx - e.x) ^ 2 + (ry - e.y) ^ 2 < 1e-6 then
			return -- a turret turns instead of the hull (Sim turnTurret)
		end
		local l = wrap(math.atan2(ry - e.y, rx - e.x) - e.heading)
		local rate = if text(k .. ".move") == "tracks" then opt(k .. ".pivotDegSec", 30) * DEG else drv("idleWheelDegSec") * DEG
		e.heading = wrap(e.heading + clampTurn(l, rate * dt))
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
		if self.trafficPace then
			u = self.trafficPace(e, paceCell, speed, u)
		end
		if self.retreating and self.retreating(e) then
			u *= num("movement.retreatPace") -- the game's mode "retreat"
		end
		if self.isVehicle(e.kind) then
			return drive(e, dt, u)
		end
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
