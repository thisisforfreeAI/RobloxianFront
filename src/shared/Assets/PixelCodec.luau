--!strict
--[[
	PixelCodec: expands the RLE RGBA format written by tools/asset_pipeline/pack_atlas.py --dev-pixels.
	Input is the base64-decoded byte buffer (use MapCodec.base64Decode); output is width*height*4 bytes,
	the layout EditableImage:WritePixelsBuffer expects.
]]
local PixelCodec = {}

function PixelCodec.decode(raw: buffer, width: number, height: number,checkpoint:any?): buffer
	local total = width * height * 4
	local out = buffer.create(total)
	local o, i, n = 0, 0, buffer.len(raw)
	local nextCheck=0
	while i < n do
		local count = buffer.readu16(raw, i)
		local px = buffer.readu32(raw, i + 2)
		for _ = 1, count do
			if checkpoint and o>=nextCheck then checkpoint(o);nextCheck=o+4096 end
			buffer.writeu32(out, o, px)
			o += 4
		end
		i += 6
	end
	assert(o == total, `pixel run total {o} does not match {total}`)
	return out
end

return PixelCodec
