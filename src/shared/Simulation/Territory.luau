--!strict
--[[
	Territory: WarFront's base territory (where a nation may build), ported from the game's code.

	Sources (the game's base sources, in its order): every built, living structure of a living nation
	reaches buildRadius x territory.reachShare (x 1 + settlement bonus, 0 in the slice); then every
	owned rig reaches territory.rigReach when a built structure of its owner stands within
	territory.rigJoin of it, else territory.rigPad.
	Painting: each source paints the cells of its circle (radius r x (1 + edgeWobble)) that lie in the
	same land block as the source (blocks are 4-connected areas split by deep water; roads split them
	too when territory.roadWalls). Inside r a cell is always painted; between r and r x (1 + wobble) it
	is painted when it lies within r x (1 + wobble x fbm(x x edgeGrain, y x edgeGrain, 3)), the noise
	seeded with (match seed XOR 20973). A cell goes to the nearest source centre; on an exact tie the
	earlier source keeps it. Wall cells (not deep) next to painted cells are then filled in two passes
	from the nearest painted neighbour (only matters with roadWalls).
	APPROX: the game repaints only the changed area when sources change; this repaints everything,
	which gives the same owners except, possibly, on exact distance ties between overlapping sources.
	Settlement claims are not in the slice.
]]

local Territory = {}

export type Source = { nation: number, x: number, y: number, r: number }

function Territory.new(opts: {
	width: number,
	height: number,
	isDeep: (number) -> boolean,
	isRoad: (number) -> boolean,
	roadWalls: boolean,
	wobble: number,
	grain: number,
	noise: any, -- ValueNoise seeded with Rng.new(seed XOR 20973)
})
	local W, H = opts.width, opts.height
	local n = W * H
	local wobble, grain, noise = opts.wobble, opts.grain, opts.noise

	-- land blocks: -1 wall (deep water, or roads with roadWalls), else block id
	local block = table.create(n, -2)
	for c = 0, n - 1 do
		if opts.isDeep(c) or (opts.roadWalls and opts.isRoad(c)) then
			block[c + 1] = -1
		end
	end
	do
		local stack = table.create(n)
		local id = 0
		for d = 0, n - 1 do
			if block[d + 1] == -2 then
				local f = 1
				stack[1] = d
				block[d + 1] = id
				while f > 0 do
					local p = stack[f]
					f -= 1
					local g = p % W
					if g > 0 and block[p] == -2 then
						block[p] = id
						f += 1
						stack[f] = p - 1
					end
					if g + 1 < W and block[p + 2] == -2 then
						block[p + 2] = id
						f += 1
						stack[f] = p + 1
					end
					if p >= W and block[p - W + 1] == -2 then
						block[p - W + 1] = id
						f += 1
						stack[f] = p - W
					end
					if p + W < n and block[p + W + 1] == -2 then
						block[p + W + 1] = id
						f += 1
						stack[f] = p + W
					end
				end
				id += 1
			end
		end
	end

	local owner = table.create(n, -1)
	local best = table.create(n, math.huge)
	local roadPass = table.create(n, 0)
	local held: { number } = {}
	local key = ""

	-- blocks touched by the nearest ring (0..2) around the source cell (the game's art)
	local function blocksNear(x: number, y: number): { number }
		local out = {}
		local a, r = math.floor(x), math.floor(y)
		for i = 0, 2 do
			if #out > 0 then
				break
			end
			for l = -i, i do
				for c = -i, i do
					if math.max(math.abs(c), math.abs(l)) == i then
						local hx, uy = a + c, r + l
						if hx >= 0 and uy >= 0 and hx < W and uy < H then
							local d = block[uy * W + hx + 1]
							if d >= 0 and not table.find(out, d) then
								table.insert(out, d)
							end
						end
					end
				end
			end
		end
		return out
	end

	local function paintSource(o: Source, list: { number })
		local c = blocksNear(o.x, o.y)
		if #c == 0 then
			return
		end
		local single = if #c == 1 then c[1] else -3
		local v = o.r * (1 + wobble)
		local b, k = v * v, o.r * o.r
		local x0, x1 = math.max(0, math.floor(o.x - v)), math.min(W - 1, math.ceil(o.x + v))
		local y0, y1 = math.max(0, math.floor(o.y - v)), math.min(H - 1, math.ceil(o.y + v))
		for yy = y0, y1 do
			local A = yy + 0.5 - o.y
			local P = b - A * A
			if P >= 0 then
				local hh = math.sqrt(P)
				local from = math.max(x0, math.floor(o.x - hh - 0.5) - 1)
				local to = math.min(x1, math.ceil(o.x + hh - 0.5) + 1)
				for xx = from, to do
					local I = yy * W + xx
					local B = block[I + 1]
					if B >= 0 and (if single >= 0 then B == single else table.find(c, B) ~= nil) then
						local F = xx + 0.5 - o.x
						local U = F * F + A * A
						if not (U > b or (owner[I + 1] >= 0 and U >= best[I + 1])) then
							local ok = true
							if U > k then
								local D = o.r * (1 + wobble * noise:fbm(xx * grain, yy * grain, 3))
								ok = U <= D * D
							end
							if ok then
								if owner[I + 1] < 0 then
									table.insert(list, I)
								end
								best[I + 1] = U
								owner[I + 1] = o.nation
							end
						end
					end
				end
			end
		end
	end

	-- the game's YC/aP/tke: fill wall cells from their nearest painted neighbour
	local function fillWalls(list: { number })
		local d = 1
		for pass = 1, 2 do
			local found = {}
			local g = #list
			for m = d, g do
				local y = list[m]
				local wx = y % W
				local function visit(o: number)
					if block[o + 1] ~= -1 or owner[o + 1] >= 0 or opts.isDeep(o) then
						return
					end
					local bo, bd = -1, math.huge
					local function look(t: number)
						if owner[t + 1] < 0 then
							return
						end
						if block[t + 1] < 0 and not (pass == 2 and roadPass[t + 1] == 1) then
							return
						end
						if best[t + 1] < bd then
							bd, bo = best[t + 1], owner[t + 1]
						end
					end
					local ox = o % W
					if ox > 0 then look(o - 1) end
					if ox + 1 < W then look(o + 1) end
					if o >= W then look(o - W) end
					if o + W < n then look(o + W) end
					if bo >= 0 then
						table.insert(found, o)
						table.insert(found, bo)
						table.insert(found, bd)
					end
				end
				if wx > 0 then visit(y - 1) end
				if wx + 1 < W then visit(y + 1) end
				if y >= W then visit(y - W) end
				if y + W < n then visit(y + W) end
			end
			for a = 1, #found, 3 do
				local r = found[a]
				if owner[r + 1] < 0 then
					owner[r + 1] = found[a + 1]
					best[r + 1] = found[a + 2] + 0.001
					roadPass[r + 1] = pass
					table.insert(list, r)
				end
			end
			d = g + 1
		end
	end

	local self = {}

	-- Repaints when the sources differ from the last call. Returns the owner array (1-based by cell + 1).
	function self.update(sources: { Source }): { number }
		local parts = table.create(#sources)
		for i, s in sources do
			parts[i] = `{s.nation}/{s.x}/{s.y}/{s.r}`
		end
		local k = table.concat(parts, ";")
		if k == key then
			return owner
		end
		key = k
		for _, p in held do
			owner[p + 1], best[p + 1], roadPass[p + 1] = -1, math.huge, 0
		end
		local list: { number } = {}
		for _, s in sources do
			paintSource(s, list)
		end
		fillWalls(list)
		held = list
		return owner
	end

	function self.ownerAt(c: number): number
		return owner[c + 1]
	end

	return self
end

return Territory
