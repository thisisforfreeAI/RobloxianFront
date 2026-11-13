--!strict
--[[
	MapCodec: decodes map modules written by tools/conversion/convert_map.py.
	Grids are returned as buffers of u8, row-major, index = y * width + x.
]]

local MapCodec = {}

export type MapData = {
	id: string,
	theme: string,
	seed: number,
	width: number,
	height: number,
	legend: { string },
	terrainRle: string,
	urbanRle: string,
	countryRle: string,
	elev4: string,
	elevMin: number,
	elevMax: number,
	roads: { { rank: number, track: boolean, pts: { number } } },
	starts: { { x: number, y: number, city: string } },
	rigs: { { x: number, y: number, name: string } },
	settlements: { { name: string, x: number, y: number, kind: string, pop: number, port: boolean } },
	countries: { { name: string, iso: string, slot: number, cells: number } },
	[string]: any,
}

export type DecodedMap = {
	data: MapData,
	width: number,
	height: number,
	terrain: buffer,
	urban: buffer,
	country: buffer,
	elev: buffer, -- 0..15 levels, presentation only
}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP: { [number]: number } = {}
for i = 1, #ALPHABET do
	LOOKUP[string.byte(ALPHABET, i)] = i - 1
end

function MapCodec.base64Decode(s: string, checkpoint: ((number) -> ())?): buffer
	local clean = string.gsub(s, "[^%w%+/=]", "")
	local len = #clean
	local pad = 0
	if string.sub(clean, -2) == "==" then
		pad = 2
	elseif string.sub(clean, -1) == "=" then
		pad = 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		if checkpoint and (i-1)%4096==0 then checkpoint(i-1) end
		local a = LOOKUP[string.byte(clean, i)] or 0
		local b = LOOKUP[string.byte(clean, i + 1)] or 0
		local c = LOOKUP[string.byte(clean, i + 2)] or 0
		local d = LOOKUP[string.byte(clean, i + 3)] or 0
		local n = a * 262144 + b * 4096 + c * 64 + d
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

function MapCodec.rleDecode(s: string, cells: number): buffer
	local pairsBuf = MapCodec.base64Decode(s)
	local out = buffer.create(cells)
	local o = 0
	for i = 0, buffer.len(pairsBuf) - 2, 2 do
		local value = buffer.readu8(pairsBuf, i)
		local count = buffer.readu8(pairsBuf, i + 1)
		if o + count > cells then
			error(`MapCodec: RLE overruns grid ({o + count} > {cells})`)
		end
		buffer.fill(out, o, value, count)
		o += count
	end
	if o ~= cells then
		error(`MapCodec: RLE covers {o} cells, expected {cells}`)
	end
	return out
end

function MapCodec.decode(data: MapData): DecodedMap
	local cells = data.width * data.height
	local packed = MapCodec.base64Decode(data.elev4)
	local elev = buffer.create(cells)
	for i = 0, cells - 1 do
		local byte = buffer.readu8(packed, i // 2)
		buffer.writeu8(elev, i, if i % 2 == 0 then byte % 16 else byte // 16)
	end
	return {
		data = data,
		width = data.width,
		height = data.height,
		terrain = MapCodec.rleDecode(data.terrainRle, cells),
		urban = MapCodec.rleDecode(data.urbanRle, cells),
		country = MapCodec.rleDecode(data.countryRle, cells),
		elev = elev,
	}
end

-- Terrain index (0-based into legend) at integer cell x, y; nil outside the map.
function MapCodec.terrainAt(map: DecodedMap, x: number, y: number): number?
	local cx, cy = math.floor(x), math.floor(y)
	if cx < 0 or cy < 0 or cx >= map.width or cy >= map.height then
		return nil
	end
	return buffer.readu8(map.terrain, cy * map.width + cx)
end

function MapCodec.terrainName(map: DecodedMap, x: number, y: number): string?
	local t = MapCodec.terrainAt(map, x, y)
	return if t then map.data.legend[t + 1] else nil
end

return MapCodec
