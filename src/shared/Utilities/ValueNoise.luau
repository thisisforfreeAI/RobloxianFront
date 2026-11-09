--!strict
--[[
	ValueNoise: exact port of WarFront's lattice value noise (genWorker class `Xt`),
	used by its map generator. grads are stored as float32 in the original, so values
	are rounded through a float32 buffer to stay bit-identical.
]]

local ValueNoise = {}
ValueNoise.__index = ValueNoise

export type ValueNoise = typeof(setmetatable({} :: { perm: { number }, grads: { number } }, ValueNoise))

local f32 = buffer.create(4)
local function toFloat32(x: number): number
	buffer.writef32(f32, 0, x)
	return buffer.readf32(f32, 0)
end

-- rng: a generator from Rng.new(seed).
function ValueNoise.new(rng: () -> number): ValueNoise
	local s = table.create(256, 0)
	for i = 0, 255 do
		s[i + 1] = i
	end
	for e = 255, 1, -1 do
		local r = math.floor(rng() * (e + 1))
		s[e + 1], s[r + 1] = s[r + 1], s[e + 1]
	end
	local perm = table.create(512, 0)
	for e = 0, 511 do
		perm[e + 1] = s[bit32.band(e, 255) + 1]
	end
	local grads = table.create(256, 0)
	for e = 0, 255 do
		grads[e + 1] = toFloat32(rng())
	end
	return setmetatable({ perm = perm, grads = grads }, ValueNoise)
end

function ValueNoise.lattice(self: ValueNoise, x: number, y: number): number
	local p = self.perm
	local inner = p[bit32.band(x, 255) + 1]
	return self.grads[p[bit32.band(inner + y, 255) + 1] + 1]
end

local function fade(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

function ValueNoise.sample(self: ValueNoise, x: number, y: number): number
	local xi, yi = math.floor(x), math.floor(y)
	local u, v = fade(x - xi), fade(y - yi)
	local c = self:lattice(xi, yi)
	local i = self:lattice(xi + 1, yi)
	local l = self:lattice(xi, yi + 1)
	local f = self:lattice(xi + 1, yi + 1)
	local h = c + (i - c) * u
	local p = l + (f - l) * u
	return h + (p - h) * v
end

function ValueNoise.fbm(self: ValueNoise, x: number, y: number, octaves: number?, lacunarity: number?, gain: number?): number
	local oct = octaves or 5
	local lac = lacunarity or 2
	local g = gain or 0.5
	local amp, freq, sum, norm = 1, 1, 0, 0
	for _ = 1, oct do
		sum += self:sample(x * freq, y * freq) * amp
		norm += amp
		amp *= g
		freq *= lac
	end
	return sum / norm
end

return ValueNoise
