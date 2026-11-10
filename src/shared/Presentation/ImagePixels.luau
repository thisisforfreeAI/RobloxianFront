--!strict
--!native
-- Alpha-weighted 2x downsampling for town detail that is smaller on screen or under image pressure.
local ImagePixels = {}
function ImagePixels.half(src: buffer, width: number, height: number): (buffer, number, number)
	assert(buffer.len(src) == width * height * 4, "pixel dimensions do not match buffer")
	local w, h = math.ceil(width / 2), math.ceil(height / 2)
	local out = buffer.create(w * h * 4)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, b, a, count = 0, 0, 0, 0, 0
			for dy = 0, 1 do
				for dx = 0, 1 do
					local sx, sy = x * 2 + dx, y * 2 + dy
					if sx >= width or sy >= height then continue end
					local at = (sy * width + sx) * 4
					local alpha = buffer.readu8(src, at + 3)
					r += buffer.readu8(src, at) * alpha
					g += buffer.readu8(src, at + 1) * alpha
					b += buffer.readu8(src, at + 2) * alpha
					a += alpha; count += 1
				end
			end
			if a > 0 then
				local at = (y * w + x) * 4
				buffer.writeu8(out, at, math.floor(r / a + 0.5))
				buffer.writeu8(out, at + 1, math.floor(g / a + 0.5))
				buffer.writeu8(out, at + 2, math.floor(b / a + 0.5))
				buffer.writeu8(out, at + 3, math.floor(a / count + 0.5))
			end
		end
	end
	return out, w, h
end
return ImagePixels
