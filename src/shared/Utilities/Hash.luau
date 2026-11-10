--!strict
-- Small hashes the game's renderer seeds its looks with, ported so the same spot gives the same look.

local Hash = {}

-- 32-bit multiply, as JavaScript's Math.imul, on unsigned values
local function imul(a: number, b: number): number
	a, b = a % 4294967296, b % 4294967296
	local ah, al = a // 65536, a % 65536
	local bh, bl = b // 65536, b % 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % 4294967296
end
Hash.imul = imul

-- the game's kc: hashes (t, e) to [0, 1) (wreck turret spin and slide, crew run-off, ...)
function Hash.kc(t: number, e: number): number
	local o = bit32.bxor(imul(bit32.bxor(t % 4294967296, 625341585), 2654435761), imul(e + 1779033703, 2246822507))
	o = imul(bit32.bxor(o, bit32.rshift(o, 16)), 2146121005)
	o = imul(bit32.bxor(o, bit32.rshift(o, 15)), 2221713035)
	return bit32.bxor(o, bit32.rshift(o, 16)) / 4294967296
end

return Hash
