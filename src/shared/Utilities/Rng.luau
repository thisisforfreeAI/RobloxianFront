--!strict
--[[
	Rng: exact port of WarFront's seeded generator (genWorker `$t`, a mulberry32 variant).

	JS original:
		n = n + 1831565813 >>> 0
		o = imul(o ^ o >>> 15, o | 1)
		o ^= o + imul(o ^ o >>> 7, o | 61)
		return ((o ^ o >>> 14) >>> 0) / 4294967296

	All values here are kept as unsigned 32-bit numbers; bit32 operations reduce
	their arguments mod 2^32, which matches JS's ToInt32/ToUint32 behaviour.
]]

local Rng = {}

local TWO32 = 4294967296

-- Low 32 bits of a*b for unsigned 32-bit a, b (Math.imul without the sign).
local function imul(a: number, b: number): number
	local aHi, aLo = a // 65536, a % 65536
	local bHi, bLo = b // 65536, b % 65536
	local mid = (aHi * bLo + aLo * bHi) % 65536
	return (aLo * bLo + mid * 65536) % TWO32
end
Rng.imul = imul

export type Generator = () -> number

-- Returns a generator of floats in [0, 1), identical to WarFront's for the same seed.
function Rng.new(seed: number): Generator
	local n = seed % TWO32
	return function(): number
		n = (n + 1831565813) % TWO32
		local o = n
		o = imul(bit32.bxor(o, bit32.rshift(o, 15)), bit32.bor(o, 1))
		o = bit32.bxor(o, o + imul(bit32.bxor(o, bit32.rshift(o, 7)), bit32.bor(o, 61)))
		return bit32.bxor(o, bit32.rshift(o, 14)) / TWO32
	end
end

-- Integer in [lo, hi] inclusive, drawn from a generator.
function Rng.int(gen: Generator, lo: number, hi: number): number
	return lo + math.floor(gen() * (hi - lo + 1))
end

return Rng
