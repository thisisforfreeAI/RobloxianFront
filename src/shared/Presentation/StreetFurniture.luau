--!strict
--[[
	StreetFurniture: lamp posts at the game's street lamp spots. Pure Luau, testable in Lune.

	PORT ADDITION, not a trace of the game. WarFront marks each street lamp as one texel coloured
	like the street (invisible by day) and only lights it at night; it never draws a post. The spots
	are the game's (tools/asset_pipeline/pack_street_furniture.py reads them from the baked towns,
	git-ignored). Everything here is this port's own: the post's shape and colours, its height, the
	arm's length, the shadow, and the zoom at which posts appear.

	The art is drawn in code (no image asset): FACINGS frames of FRAME x FRAME px, SCALE px a town
	texel, the lamp head at the frame's centre so a post is placed by its head (the lit texel), the
	foot ARM texels back from it on the kerb. Two rows: row 0 the whole post as seen from above, row 1
	only its raised parts (arm and head), which StreetFurnitureRenderer shifts along the sun for the
	shadow while a thin bar draws the pole's own shadow from the foot.
]]
local StreetFurniture = {}

StreetFurniture.FACINGS = 16
StreetFurniture.FRAME = 32 -- px a frame
StreetFurniture.SCALE = 4 -- px a town texel
StreetFurniture.ARM = 2.5 -- town texels from the foot to the head
StreetFurniture.POLE_HEIGHT = 0.4 -- cells; how far the head stands off the ground, for the shadow
StreetFurniture.SHADOW_ALPHA = 0.42
StreetFurniture.FROM = 7 -- screen px a cell where posts start to fade in (port choice)
StreetFurniture.FULL = 12 -- screen px a cell where they are fully shown (port choice)

local FACINGS, FRAME, SCALE = StreetFurniture.FACINGS, StreetFurniture.FRAME, StreetFurniture.SCALE
local TAU = math.pi * 2

-- colours (0..255), this port's choice: dark painted steel, a pale lens
local FOOT = { 58, 60, 63 }
local CAP = { 104, 107, 110 }
local POLE = { 76, 79, 82 }
local HOUSING = { 66, 68, 71 }
local LENS = { 226, 221, 198 }

function StreetFurniture.facing(angle: number): number
	return math.floor(angle / TAU * FACINGS + 0.5) % FACINGS
end

function StreetFurniture.facingAngle(f: number): number
	return f * TAU / FACINGS
end

-- the post's shapes in a frame, top last: returns the colour at (x, y) or nil
local function shapeAt(x: number, y: number, dx: number, dy: number, raisedOnly: boolean): { number }?
	local c = FRAME / 2
	local reach = StreetFurniture.ARM * SCALE
	local fx, fy = c - dx * reach, c - dy * reach -- the foot
	-- relative to the head, along (u) and across (v) the arm
	local hx, hy = x - c, y - c
	local u, v = hx * dx + hy * dy, -hx * dy + hy * dx
	if (u / 1.6) ^ 2 + (v / 1.0) ^ 2 <= 1 then
		return LENS
	end
	if (u / 2.8) ^ 2 + (v / 1.8) ^ 2 <= 1 then
		return HOUSING
	end
	local px, py = x - fx, y - fy
	if not raisedOnly then
		local r2 = px * px + py * py
		if r2 <= 1.4 * 1.4 then
			return CAP
		end
		if r2 <= 2.2 * 2.2 then
			return FOOT
		end
	end
	-- the arm, from the foot to the head
	local t = math.clamp((px * dx + py * dy) / reach, 0, 1)
	local ex, ey = x - (fx + dx * reach * t), y - (fy + dy * reach * t)
	if ex * ex + ey * ey <= 0.85 * 0.85 then
		return POLE
	end
	return nil
end

-- the atlas: FACINGS * FRAME wide, 2 * FRAME tall, RGBA, 4 x 4 samples a pixel for soft edges
function StreetFurniture.atlasSize(): (number, number)
	return FACINGS * FRAME, 2 * FRAME
end

function StreetFurniture.drawAtlas(): buffer
	local w, h = StreetFurniture.atlasSize()
	local out = buffer.create(w * h * 4)
	for f = 0, FACINGS - 1 do
		local a = StreetFurniture.facingAngle(f)
		local dx, dy = math.cos(a), math.sin(a)
		for row = 0, 1 do
			for y = 0, FRAME - 1 do
				for x = 0, FRAME - 1 do
					local r, g, b, n = 0, 0, 0, 0
					for sy = 0, 3 do
						for sx = 0, 3 do
							local col = shapeAt(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4, dx, dy, row == 1)
							if col then
								r += col[1]
								g += col[2]
								b += col[3]
								n += 1
							end
						end
					end
					if n > 0 then
						local o = (((row * FRAME + y) * w) + f * FRAME + x) * 4
						buffer.writeu8(out, o, math.floor(r / n + 0.5))
						buffer.writeu8(out, o + 1, math.floor(g / n + 0.5))
						buffer.writeu8(out, o + 2, math.floor(b / n + 0.5))
						buffer.writeu8(out, o + 3, math.floor(n * 255 / 16 + 0.5))
					end
				end
			end
		end
	end
	return out
end

-- how far the posts show at this zoom, 0..1
function StreetFurniture.share(pixelsPerCell: number): number
	return math.clamp((pixelsPerCell - StreetFurniture.FROM) / (StreetFurniture.FULL - StreetFurniture.FROM), 0, 1)
end

-- the shadow of the head, in cells, and its opacity, from a DaylightController sample
-- (its shadow vector is the ground offset per unit of height; capped at 2 as the car shadows are)
function StreetFurniture.shadow(light: any): (number, number, number)
	local s = light and light.shadow or { 0, 0 }
	local len = math.sqrt(s[1] * s[1] + s[2] * s[2])
	local k = if len > 2 then 2 / len else 1
	local h = StreetFurniture.POLE_HEIGHT
	return s[1] * k * h, s[2] * k * h, StreetFurniture.SHADOW_ALPHA * (light and light.shadowAlpha or 1)
end

-- a bucket grid over the lamp list (flat x, y, angle triples) for camera queries
export type Grid = { size: number, cells: { [number]: { number } }, lamps: { number } }
function StreetFurniture.grid(lamps: { number }, size: number?): Grid
	local s = size or 8
	local cells: { [number]: { number } } = {}
	for i = 1, #lamps - 2, 3 do
		local key = math.floor(lamps[i + 1] / s) * 65536 + math.floor(lamps[i] / s)
		local list = cells[key]
		if not list then
			list = {}
			cells[key] = list
		end
		table.insert(list, i)
	end
	return { size = s, cells = cells, lamps = lamps }
end

-- indices (into the flat list) of lamps inside the box, in cells
function StreetFurniture.query(g: Grid, x0: number, y0: number, x1: number, y1: number): { number }
	local out = {}
	local s = g.size
	for by = math.floor(y0 / s), math.floor(y1 / s) do
		for bx = math.floor(x0 / s), math.floor(x1 / s) do
			local list = g.cells[by * 65536 + bx]
			if list then
				for _, i in list do
					local x, y = g.lamps[i], g.lamps[i + 1]
					if x >= x0 and x <= x1 and y >= y0 and y <= y1 then
						table.insert(out, i)
					end
				end
			end
		end
	end
	return out
end

return StreetFurniture
