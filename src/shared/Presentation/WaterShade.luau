--!strict
--[[
	WaterShade: the water part of WarFront's ground shader, worked out on the CPU, a texel at a time.

	Roblox has no custom shaders, so WaterRenderer keeps a pixel buffer per map chunk and repaints it
	from these functions. Every number comes from the settings that tools/conversion/export_water.cjs
	pulls out of the local install (src/client/DevAssets/Water_<map>.luau, git-ignored); none are
	written here. The functions follow the game's GLSL line for line:
	  hash21, vnoise, bayer4   its noise and dither helpers;
	  depth / swell            its depthOn: flat dithered depth bands from the shore out, and the swell
	                           heaving past the shelf (split here: the bands never change, so they are
	                           baked once; only the swell is redrawn);
	  tide                     its tideOn: sand texels one or two from the sea wet and dry on a cycle,
	                           with a faint foam edge as the water comes in;
	  surf                     the foam line and the far foam line, lit for half their period;
	  crest                    a wave crest sliding one texel for half its period;
	  flow                     its flowOn: a river's swell and streamlines carried downstream;
	  glint                    every open-water texel rolls a die on its own clock; the few that come up
	                           take the light's colour.
	APPROX, by design of the port:
	  - The game's GPU works in 32-bit floats and Luau in 64-bit, so hash21 gives other numbers for the
	    same texel: which texels glint, and each foam stretch's phase, differ from the game's, while
	    the share, timing and look follow its rules.
	  - The water is repainted a band of rows at a time within a frame budget (WaterRenderer), so the
	    animation steps a little coarser than the game's every-frame draw.
	Not ported (yet): night reflections of lights and the moon's path (they need the scene's lights
	and the screen position), splash ripples (they need a hook from the shell and blast effects), the
	weather's mud and storm sea, and a burst dam's flood. Haze, the day and night tint and cloud
	shadows are global and come from the shared daylight post effect, not from this module.
]]
local WaterShade = {}

local floor = math.floor
local function fract(x: number): number
	return x - floor(x)
end

-- the game's hash21
function WaterShade.hash21(px: number, py: number): number
	local qx = fract(px * 0.1031)
	local qy = fract(py * 0.1030)
	local qz = fract(px * 0.0973)
	local d = qx * (qy + 33.33) + qy * (qz + 33.33) + qz * (qx + 33.33)
	qx += d
	qy += d
	qz += d
	return fract((qx + qy) * qz)
end
local hash21 = WaterShade.hash21

-- value noise with a cache of its lattice hashes (they never change; only where it is read moves)
export type Noise = { cache: { [number]: number } }
function WaterShade.newNoise(): Noise
	return { cache = {} }
end
local function lattice(n: Noise, i: number, j: number): number
	local key = i * 65536 + j
	local v = n.cache[key]
	if v == nil then
		v = hash21(i, j)
		n.cache[key] = v
	end
	return v
end
function WaterShade.vnoise(n: Noise, x: number, y: number): number
	local i, j = floor(x), floor(y)
	local fx, fy = x - i, y - j
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)
	local a, b = lattice(n, i, j), lattice(n, i + 1, j)
	local c, d = lattice(n, i, j + 1), lattice(n, i + 1, j + 1)
	local top = a + (b - a) * fx
	return top + ((c + (d - c) * fx) - top) * fy
end
local vnoise = WaterShade.vnoise

local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 } -- the standard 4 x 4 ordered dither
function WaterShade.bayer4(tx: number, ty: number): number
	return (BAYER[(tx % 4) + (ty % 4) * 4 + 1] + 0.5) / 16
end
local bayer4 = WaterShade.bayer4

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
WaterShade.smoothstep = smoothstep

-- the game's depthOn, its fixed part: the band tint by distance from the shore (cells)
function WaterShade.depthBands(r: number, g: number, b: number, tx: number, ty: number, shore: number, D: any): (number, number, number)
	local lvl = math.clamp((shore + (bayer4(tx, ty) - 0.5) * D.blend) / D.far, 0, 1)
	local k = floor(lvl * D.steps + 0.5) / D.steps
	local s, st = D.shallow * (1 - k), D.shallowTint
	r, g, b = r + (st[1] - r) * s, g + (st[2] - g) * s, b + (st[3] - b) * s
	local d, dt = D.deep * k, D.deepTint
	return r + (dt[1] - r) * d, g + (dt[2] - g) * d, b + (dt[3] - b) * d
end

-- how far past the shelf a texel is, 0 to 1 (the swell's strength there)
function WaterShade.openOf(shore: number, D: any): number
	return math.clamp((shore - D.swell.from) / D.swell.fade, 0, 1)
end

-- the game's depthOn, its moving part: the swell's light and shade
function WaterShade.swell(n: Noise, r: number, g: number, b: number, tx: number, ty: number, open: number, now: number, D: any): (number, number, number)
	local sw = D.swell
	local qx = tx / (3 * sw.cells) + now * (sw.drift / sw.cells)
	local qy = ty / (3 * sw.cells) + now * (sw.drift * 0.4 / sw.cells)
	local v = vnoise(n, qx, qy) * 0.65 + vnoise(n, qx * 2.3 + 5.7, qy * 2.3 + 5.7) * 0.35
	if v + (bayer4(tx, ty) - 0.5) * 0.04 >= 0.62 then
		local k = sw.sheen * open
		r, g, b = r + (sw.light[1] - r) * k, g + (sw.light[2] - g) * k, b + (sw.light[3] - b) * k
	end
	if v <= 0.36 then
		local k = 1 - sw.shade * open
		r, g, b = r * k, g * k, b * k
	end
	return r, g, b
end

-- the per-texel lots the game draws from fixed inputs, worked out once
function WaterShade.surfLot(cx: number, cy: number, segment: number, far: boolean): number
	local ox = if far then 17 else 0
	return hash21(floor(cx / segment) + ox, floor(cy / segment) + ox)
end
function WaterShade.crestLot(tx: number, cy: number, texels: number): number
	return hash21(floor(tx / texels), cy)
end
function WaterShade.tideLot(cx: number, cy: number, segment: number): number
	return hash21(floor(cx / segment) + 23, floor(cy / segment) + 23)
end
function WaterShade.raggedOf(tx: number, ty: number, T: any): boolean
	return hash21(tx * 0.53 + 4.9, ty * 0.53 + 4.9) <= T.ragged
end
function WaterShade.glintLot(tx: number, ty: number): number
	return hash21(tx * 0.917 + 3.1, ty * 0.917 + 3.1) * 97
end

-- the game's tideOn: d texels (1 or 2) from the sea
function WaterShade.tide(r: number, g: number, b: number, d: number, lot: number, ragged: boolean, now: number, T: any, foam: { number }): (number, number, number)
	local ph = fract(now / T.periodSec + lot)
	local k = floor(ph * T.steps)
	local reach = if k < 1 then 0 elseif k < 2 then 1 elseif k < 4 then 2 elseif k < 5 then 1 else 0
	local wet = if d <= reach and (d < 2 or ragged) then 1 else 0
	if wet == 0 then
		return r, g, b
	end
	local coming = k >= 1 and k <= 2.5
	local edge = coming and math.abs(d - reach) <= 0.5
	local m = 1 - T.wet
	r, g, b = r * m, g * m, b * m
	if edge then
		local f = T.foam
		r, g, b = r + (foam[1] - r) * f, g + (foam[2] - g) * f, b + (foam[3] - b) * f
	end
	return r, g, b
end

-- the surf: a foam line lit for half its period
function WaterShade.surf(r: number, g: number, b: number, lot: number, far: boolean, now: number, U: any): (number, number, number)
	local on = fract(now / (if far then U.farPeriod else U.period) + lot) >= 0.5
	local col = if on then U.color elseif far then U.farOff else U.off
	local k = U.mix
	return r + (col[1] - r) * k, g + (col[2] - g) * k, b + (col[3] - b) * k
end

-- a wave crest: its head sinks into the sea and the texel past its tail lights for half its period
function WaterShade.crest(r: number, g: number, b: number, lot: number, head: boolean, now: number, C: any, sea: { number }): (number, number, number)
	if fract(now / C.period + lot) < 0.5 then
		return r, g, b
	end
	local col = if head then sea else C.color
	local k = C.step
	return r + (col[1] - r) * k, g + (col[2] - g) * k, b + (col[3] - b) * k
end

local function band(d: number, w: number, px: number): number
	-- the game's band(), with px its device pixels a cell (uRoad.y); WaterRenderer passes the fine texel
	return math.clamp((math.max(w, px * 0.5) - d) / px + 0.5, 0, 1) * math.min(1, w / (px * 0.5))
end

-- the game's flowOn: p (cells) the texel's centre, dir/speed/shore from the water map
function WaterShade.flow(n: Noise, r: number, g: number, b: number, px: number, py: number, dx: number, dy: number, speed: number, shore: number, now: number, Fl: any, cellPx: number): (number, number, number)
	local amp = smoothstep(Fl.cut, Fl.full, speed)
	if amp <= 0 then
		return r, g, b
	end
	local u = now / Fl.phaseSec
	local f = fract(u)
	local reach = Fl.phaseSec * Fl.cellsPerSec * speed
	local ax, ay = px - dx * (f * reach), py - dy * (f * reach)
	local f2 = fract(u + 0.5)
	local bx, by = px - dx * (f2 * reach), py - dy * (f2 * reach)
	local blend = math.abs(1 - 2 * f)
	local sm, fq = Fl.swell.smear, Fl.swell.freq
	local sa = vnoise(n, ax * fq, ay * fq) + vnoise(n, (ax + dx * sm) * fq, (ay + dy * sm) * fq)
	local sb = vnoise(n, bx * fq, by * fq) + vnoise(n, (bx + dx * sm) * fq, (by + dy * sm) * fq)
	local swell = (sa + (sb - sa) * blend) * 0.5 - 0.5
	local swellAmp = amp * Fl.swellAmpRiver
	if swell > 0 then
		local k = swell * Fl.swell.sheen * 2 * swellAmp
		r, g, b = r + (Fl.light[1] - r) * k, g + (Fl.light[2] - g) * k, b + (Fl.light[3] - b) * k
	elseif swell < 0 then
		local k = -swell * Fl.swell.shade * 2 * swellAmp
		r, g, b = r + (Fl.dark[1] - r) * k, g + (Fl.dark[2] - g) * k, b + (Fl.dark[3] - b) * k
	end
	local q = (shore + swell * Fl.lane.meander * 2) / Fl.lane.spacing
	local d = math.abs(fract(q) - 0.5) * Fl.lane.spacing
	local dq = Fl.dash.freq
	local la = vnoise(n, ax * dq + 11.3, ay * dq + 11.3)
	local lb = vnoise(n, bx * dq + 11.3, by * dq + 11.3)
	local on = smoothstep(Fl.dash.from, Fl.dash.from + Fl.dash.soft, la + (lb - la) * blend)
	local k = band(d, Fl.lane.half, cellPx) * on * amp * Fl.strength
	return r + (Fl.color[1] - r) * k, g + (Fl.color[2] - g) * k, b + (Fl.color[3] - b) * k
end

-- a glint: true when the texel's die comes up now
function WaterShade.glints(tx: number, ty: number, lot: number, now: number, G: any): boolean
	local t = floor(now * G.perSec + lot)
	return hash21(tx + t, ty + t) >= 1 - G.share
end

-- how strong a glint is at this light (the game's uGlints.z): night 0..1, elevation of the sun or moon
function WaterShade.glintStrength(G: any, night: number, elevation: number): number
	return (G.sun * (1 - night) + G.moon * night) * math.max(0.25, elevation)
end

return WaterShade
