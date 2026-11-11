--!strict
--!native
--[[
	Inflate: decodes raw DEFLATE data (RFC 1951, no zlib or gzip wrapper) from a buffer.
	Used for the baked town images, which are packed by tools/asset_pipeline/pack_city.py with
	zlib.compress(..., wbits=-15). Codes are decoded through a full lookup table per Huffman table
	(2^longest entries, index = the next bits as they arrive), so each symbol is one table read.

	Inflate.raw(src, outSize) -> buffer of exactly outSize bytes (errors on bad data or a size mismatch).
]]

local Inflate = {}

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

type Table = { codes: buffer, bits: number, mask: number }

-- lengths[sym + 1] = code length (0 = unused), for n symbols
local function build(lengths: { number }, n: number): Table
	local count = table.create(16, 0)
	local longest = 0
	for s = 1, n do
		local l = lengths[s]
		if l > 0 then
			count[l] += 1
			if l > longest then
				longest = l
			end
		end
	end
	longest = math.max(longest, 1)
	local nextCode = table.create(16, 0)
	local code = 0
	for l = 1, 15 do
		code = (code + (count[l - 1] or 0)) * 2
		nextCode[l] = code
	end
	local size = bit32.lshift(1, longest)
	local codes = buffer.create(size * 2)
	for s = 1, n do
		local l = lengths[s]
		if l > 0 then
			local c = nextCode[l]
			nextCode[l] = c + 1
			-- reverse the l bits of c: Huffman codes arrive most significant bit first
			local r = 0
			for _ = 1, l do
				r = r * 2 + c % 2
				c = c // 2
			end
			local entry = (s - 1) * 16 + l
			local step = bit32.lshift(1, l)
			while r < size do
				buffer.writeu16(codes, r * 2, entry)
				r += step
			end
		end
	end
	return { codes = codes, bits = longest, mask = size - 1 }
end

local fixedLit: Table? = nil
local fixedDist: Table? = nil

local function fixedTables(): (Table, Table)
	if not fixedLit then
		local l = table.create(288, 0)
		for s = 0, 287 do
			l[s + 1] = if s < 144 then 8 elseif s < 256 then 9 elseif s < 280 then 7 else 8
		end
		fixedLit = build(l, 288)
		fixedDist = build(table.create(30, 5), 30)
	end
	return fixedLit :: Table, fixedDist :: Table
end

function Inflate.raw(src: buffer, outSize: number, checkpoint:((number)->())?): buffer
	local out = buffer.create(outSize)
	local n = buffer.len(src)
	local pos, bitBuf, bitCnt, o = 0, 0, 0, 0
	local nextCheck=4096

	local function need(k: number)
		while bitCnt < k do
			local byte = if pos < n then buffer.readu8(src, pos) else 0
			pos += 1
			bitBuf += byte * bit32.lshift(1, bitCnt)
			bitCnt += 8
		end
	end
	local function bits(k: number): number
		if k == 0 then
			return 0
		end
		need(k)
		local v = bit32.band(bitBuf, bit32.lshift(1, k) - 1)
		bitBuf = bit32.rshift(bitBuf, k)
		bitCnt -= k
		return v
	end
	local function decode(t: Table): number
		need(t.bits)
		local e = buffer.readu16(t.codes, bit32.band(bitBuf, t.mask) * 2)
		local l = e % 16
		if l == 0 then
			error("inflate: bad code")
		end
		bitBuf = bit32.rshift(bitBuf, l)
		bitCnt -= l
		return e // 16
	end

	local final = 0
	repeat
		final = bits(1)
		local kind = bits(2)
		if kind == 0 then
			-- stored: drop to a byte edge, then LEN, NLEN and LEN raw bytes
			bits(bitCnt % 8)
			local len = bits(16)
			local nlen = bits(16)
			if bit32.bxor(len, nlen) ~= 0xFFFF then
				error("inflate: bad stored block")
			end
			for _ = 1, len do
				buffer.writeu8(out, o, bits(8))
				o += 1
				if checkpoint and o>=nextCheck then nextCheck=o+4096;checkpoint(o) end
			end
		elseif kind == 1 or kind == 2 then
			local lit, dist
			if kind == 1 then
				lit, dist = fixedTables()
			else
				local hlit, hdist, hclen = bits(5) + 257, bits(5) + 1, bits(4) + 4
				local cl = table.create(19, 0)
				for i = 1, hclen do
					cl[ORDER[i] + 1] = bits(3)
				end
				local clTable = build(cl, 19)
				local lens = table.create(hlit + hdist, 0)
				local i = 1
				while i <= hlit + hdist do
					local sym = decode(clTable)
					if sym < 16 then
						lens[i] = sym
						i += 1
					else
						local value, rep = 0, 0
						if sym == 16 then
							if i == 1 then
								error("inflate: repeat with no previous length")
							end
							value, rep = lens[i - 1], 3 + bits(2)
						elseif sym == 17 then
							rep = 3 + bits(3)
						else
							rep = 11 + bits(7)
						end
						for _ = 1, rep do
							lens[i] = value
							i += 1
						end
					end
				end
				local litLens, distLens = table.create(hlit, 0), table.create(hdist, 0)
				for k = 1, hlit do
					litLens[k] = lens[k]
				end
				for k = 1, hdist do
					distLens[k] = lens[hlit + k]
				end
				lit, dist = build(litLens, hlit), build(distLens, hdist)
			end
			while true do
				if checkpoint and o>=nextCheck then nextCheck=o+4096;checkpoint(o) end
				local sym = decode(lit)
				if sym < 256 then
					buffer.writeu8(out, o, sym)
					o += 1
				elseif sym == 256 then
					break
				else
					local li = sym - 256
					local len = LEN_BASE[li] + bits(LEN_EXTRA[li])
					local di = decode(dist) + 1
					local d = DIST_BASE[di] + bits(DIST_EXTRA[di])
					if d > o or o + len > outSize then
						error("inflate: bad distance or output overrun")
					end
					if d >= len then
						buffer.copy(out, o, out, o - d, len)
						o += len
					else
						for _ = 1, len do
							buffer.writeu8(out, o, buffer.readu8(out, o - d))
							o += 1
						end
					end
				end
			end
		else
			error("inflate: bad block type")
		end
	until final == 1
	if o ~= outSize then
		error(`inflate: got {o} bytes, expected {outSize}`)
	end
	return out
end

return Inflate
