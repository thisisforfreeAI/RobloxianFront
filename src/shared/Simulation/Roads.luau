--!strict
--[[
	Roads: WarFront's road grid, road networks and truck routing, rebuilt from the game's own logic.
	Pure Luau (runs in Lune tests and on the server). Traced from WarFront 0.1.0's match code:
	  * road cells: every map road with rank >= 1 is rasterised segment by segment (the game's own
	    grid line walk); cells on deep water are skipped. Class = highway if rank >= 2, else track if
	    the road is a track, else road; overlapping roads keep the higher class.
	  * bridge decks: road cells on impassable terrain widen into impassable neighbours within
	    movement.bridgeDeck.half cells (never deep water), copying the class.
	  * road networks ("pieces"): 4-way connected road cells.
	  * truck route cost per cell: road cell = 1 / roads.classes.<class>.truck (no-class cells cost as
	    "road"); off-road = convoys.offRoadCost / roads.classes.track.truck, allowed only within
	    convoys.offRoadReach + HQ footprint (Chebyshev) of the route's start or end cell; elsewhere
	    impassable. Impassable terrain without a road is impassable.
	  * search: the game's A* (4-way, octile heuristic x minCost, binary heap, float32 distances), so
	    ties resolve the same way.
	Not modelled (not in the slice): road damage/wear, traffic jams, road signs, rail crossings,
	structures blocking cells.
]]

local Roads = {}

local CLASS_NONE, CLASS_TRACK, CLASS_ROAD, CLASS_HIGHWAY = 0, 1, 2, 3
Roads.CLASS = { none = CLASS_NONE, track = CLASS_TRACK, road = CLASS_ROAD, highway = CLASS_HIGHWAY }
Roads.CLASS_NAME = { [0] = "road", [1] = "track", [2] = "road", [3] = "highway" }

export type RoadLine = { rank: number, track: boolean?, pts: { number } }

export type Config = {
	width: number,
	height: number,
	terrainAt: (cell: number) -> string?, -- terrain name of a 0-based cell index
	passable: (terrain: string) -> boolean,
	roads: { RoadLine },
	bridgeHalf: number, -- movement.bridgeDeck.half
	truckCost: { [number]: number }, -- 1 / roads.classes.<class>.truck, indexed by class 0..3
	offRoadCost: number, -- convoys.offRoadCost * (1 / track.truck)
	offRoadReach: number, -- convoys.offRoadReach + HQ footprint radius (cells, Chebyshev)
}

local function f32(x: number): number
	return (string.unpack("<f", string.pack("<f", x)))
end
Roads.f32 = f32

-- The game's grid line walk between two points (cells in visiting order, clipped to the map).
function Roads.line(w: number, h: number, x0: number, y0: number, x1: number, y1: number): { number }
	local a, r = math.floor(x0), math.floor(y0)
	local i, l = math.floor(x1), math.floor(y1)
	local c, hh = math.abs(i - a), math.abs(l - r)
	local u = if a < i then 1 else -1
	local d = if r < l then 1 else -1
	local out = {}
	local function push()
		if a >= 0 and r >= 0 and a < w and r < h then
			table.insert(out, r * w + a)
		end
	end
	push()
	local g, m = 0, 0
	while g < c or m < hh do
		-- JS: (.5+g)/c < (.5+m)/h ; division by zero gives Infinity there, emulate it
		local lhs = if c == 0 then math.huge else (0.5 + g) / c
		local rhs = if hh == 0 then math.huge else (0.5 + m) / hh
		if lhs < rhs then
			a += u
			g += 1
		else
			r += d
			m += 1
		end
		push()
	end
	return out
end

-- Binary min-heap identical to the game's (ties keep the game's order).
local function newHeap()
	local items, keys = {}, {}
	local heap = { size = 0 }
	function heap.clear()
		heap.size = 0
	end
	function heap.push(e: number, o: number)
		local a = heap.size
		heap.size += 1
		while a > 0 do
			local r = (a - 1) // 2
			if keys[r] <= o then
				break
			end
			items[a], keys[a] = items[r], keys[r]
			a = r
		end
		items[a], keys[a] = e, o
	end
	function heap.pop(): number
		local n = items[0]
		heap.size -= 1
		local s = heap.size
		if s > 0 then
			local a, r = items[s], keys[s]
			local i = 0
			while true do
				local l = 2 * i + 1
				if l >= s then
					break
				end
				local c = l + 1
				local hIdx = if c < s and keys[c] < keys[l] then c else l
				if keys[hIdx] >= r then
					break
				end
				items[i], keys[i] = items[hIdx], keys[hIdx]
				i = hIdx
			end
			items[i], keys[i] = a, r
		end
		return n
	end
	return heap
end

function Roads.build(cfg: Config)
	local w, h = cfg.width, cfg.height
	local n = w * h
	local road = buffer.create(n)
	local class = buffer.create(n)
	local terrain = table.create(n) :: { string }
	local pass = table.create(n) :: { boolean }
	for c = 0, n - 1 do
		local t = cfg.terrainAt(c) or "deep"
		terrain[c + 1] = t
		pass[c + 1] = cfg.passable(t)
	end

	-- 1. rasterise roads (rank >= 1), skipping deep water
	for _, line in cfg.roads do
		if line.rank >= 1 then
			local cls = if line.rank >= 2 then CLASS_HIGHWAY elseif line.track then CLASS_TRACK else CLASS_ROAD
			local pts = line.pts
			local b = 3 -- JS b=2 (0-based) -> pts[b-1], pts[b], pts[b+1], pts[b+2] in 1-based
			while b + 1 <= #pts do
				for _, k in Roads.line(w, h, pts[b - 2], pts[b - 1], pts[b], pts[b + 1]) do
					if terrain[k + 1] ~= "deep" then
						buffer.writeu8(road, k, 1)
						buffer.writeu8(class, k, math.max(buffer.readu8(class, k), cls))
					end
				end
				b += 2
			end
		end
	end

	-- 2. bridge decks
	local half = cfg.bridgeHalf
	if half > 0 then
		local adds, from = {}, {}
		for c = 0, n - 1 do
			if buffer.readu8(road, c) == 1 and not pass[c + 1] then
				local x = c % w
				local y = (c - x) // w
				for dy = -half, half do
					for dx = -half, half do
						local gx, gy = x + dx, y + dy
						if gx >= 0 and gy >= 0 and gx < w and gy < h then
							local k = gy * w + gx
							if not (buffer.readu8(road, k) == 1 or terrain[k + 1] == "deep" or pass[k + 1]) then
								table.insert(adds, k)
								table.insert(from, c)
							end
						end
					end
				end
			end
		end
		for i, k in adds do
			buffer.writeu8(road, k, 1)
			buffer.writeu8(class, k, math.max(buffer.readu8(class, k), buffer.readu8(class, from[i])))
		end
	end

	-- 3. road networks (4-way flood fill, the game's scan order)
	local piece = table.create(n, -1) :: { number }
	local count = 0
	for c = 0, n - 1 do
		if buffer.readu8(road, c) == 1 and piece[c + 1] < 0 then
			local stack = { c }
			piece[c + 1] = count
			while #stack > 0 do
				local d = table.remove(stack) :: number
				local x = d % w
				local function try(k: number)
					if buffer.readu8(road, k) == 1 and piece[k + 1] < 0 then
						piece[k + 1] = count
						table.insert(stack, k)
					end
				end
				if x > 0 then
					try(d - 1)
				end
				if x < w - 1 then
					try(d + 1)
				end
				if d >= w then
					try(d - w)
				end
				if d < n - w then
					try(d + w)
				end
			end
			count += 1
		end
	end

	local self = { width = w, height = h, pieces = count }

	function self.isRoad(c: number): boolean
		return c >= 0 and c < n and buffer.readu8(road, c) == 1
	end
	function self.classAt(c: number): number
		return buffer.readu8(class, c)
	end
	function self.passable(c: number): boolean
		return pass[c + 1] or buffer.readu8(road, c) == 1
	end
	function self.terrain(c: number): string
		return terrain[c + 1]
	end
	function self.cellAt(x: number, y: number): number
		local cx, cy = math.floor(x), math.floor(y)
		if cx < 0 or cy < 0 or cx >= w or cy >= h then
			return -1
		end
		return cy * w + cx
	end

	-- Road networks touching cells whose centre lies within r of (x, y).
	function self.piecesNear(x: number, y: number, r: number): { [number]: boolean }
		local out = {}
		local r2 = r * r
		for cy = math.floor(y - r), math.ceil(y + r) do
			if cy >= 0 and cy < h then
				for cx = math.floor(x - r), math.ceil(x + r) do
					if cx >= 0 and cx < w then
						local dx, dy = cx + 0.5 - x, cy + 0.5 - y
						if dx * dx + dy * dy <= r2 then
							local p = piece[cy * w + cx + 1]
							if p >= 0 then
								out[p] = true
							end
						end
					end
				end
			end
		end
		return out
	end

	-- Truck cost function for a route between two cells.
	function self.truckCostFn(fromCell: number, toCell: number): (number) -> number
		local gx, gy = fromCell % w, fromCell // w
		local tx, ty = toCell % w, toCell // w
		local reach = cfg.offRoadReach
		return function(v: number): number
			if not self.passable(v) then
				return math.huge
			end
			if buffer.readu8(road, v) == 1 then
				return cfg.truckCost[buffer.readu8(class, v)]
			end
			local bx, by = v % w, v // w
			if math.max(math.abs(bx - gx), math.abs(by - gy)) <= reach or math.max(math.abs(bx - tx), math.abs(by - ty)) <= reach then
				return cfg.offRoadCost
			end
			return math.huge
		end
	end

	-- The game's A*: returns the cells after `start` up to and including the goal, {} if start is the
	-- goal, nil if unreachable.
	local dist = table.create(n, 0) :: { number }
	local from = table.create(n, -1) :: { number }
	local seen = table.create(n, 0) :: { number }
	local done = table.create(n, 0) :: { number }
	local gen = 0
	local heap = newHeap()
	function self.search(start: number, goal: number, cost: (number) -> number, opts: { minCost: number?, fourWay: boolean?, maxNodes: number? }?): { number }?
		if start < 0 then
			return nil
		end
		if start == goal then
			return {}
		end
		local o = opts or {}
		local m = o.minCost or 0.4
		local fourWay = o.fourWay == true
		gen += 1
		local hx, hy = goal % w, goal // w
		local function heur(c: number): number
			local ax = c % w
			local ay = (c - ax) // w
			local dx, dy = math.abs(ax - hx), math.abs(ay - hy)
			return (math.max(dx, dy) + 0.414 * math.min(dx, dy)) * m
		end
		heap.clear()
		seen[start + 1], dist[start + 1], from[start + 1] = gen, 0, -1
		heap.push(start, heur(start))
		local budget = o.maxNodes or n
		while heap.size > 0 and budget > 0 do
			budget -= 1
			local cur = heap.pop()
			if done[cur + 1] ~= gen then
				done[cur + 1] = gen
				if cur == goal then
					local path = {}
					local c = cur
					while c ~= start and c >= 0 do
						table.insert(path, c)
						c = from[c + 1]
					end
					local out = table.create(#path)
					for i = #path, 1, -1 do
						table.insert(out, path[i])
					end
					return out
				end
				local ax = cur % w
				local ay = (cur - ax) // w
				local base = dist[cur + 1]
				for dy = -1, 1 do
					local yy = ay + dy
					if yy >= 0 and yy < h then
						for dx = -1, 1 do
							if not (dx == 0 and dy == 0) and not (fourWay and dx ~= 0 and dy ~= 0) then
								local xx = ax + dx
								if xx >= 0 and xx < w then
									local b = yy * w + xx
									local f = cost(b)
									local ok = f < math.huge
									if ok and dx ~= 0 and dy ~= 0 then
										ok = cost(ay * w + xx) < math.huge and cost(yy * w + ax) < math.huge
									end
									if ok then
										local u = base + f * (if dx ~= 0 and dy ~= 0 then 1.414 else 1)
										if seen[b + 1] ~= gen or u < dist[b + 1] then
											seen[b + 1], dist[b + 1], from[b + 1] = gen, f32(u), cur
											heap.push(b, u + heur(b))
										end
									end
								end
							end
						end
					end
				end
			end
		end
		return nil
	end

	-- Route a rig's trucks take home: from the rig cell to the HQ cell (cells after the rig cell).
	function self.truckRoute(rigCell: number, hqCell: number): { number }?
		local path = self.search(rigCell, hqCell, self.truckCostFn(rigCell, hqCell), { minCost = 1, fourWay = true, maxNodes = n })
		if path and #path > 0 and path[#path] ~= hqCell then
			local last = path[#path]
			local tail = Roads.line(w, h, last % w, last // w, hqCell % w, hqCell // w)
			for i = 2, #tail do
				table.insert(path, tail[i])
			end
		end
		return path
	end

	return self
end

return Roads
