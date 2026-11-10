--!strict
--!native
-- Source road widths/colours/mark locations. APPROX: straight repeating strips replace the GPU's
-- world-space noise, junction distance fields, town medians, damage, bridges and lights.
local RoadPixels = {}
function RoadPixels.kind(road: any): string
	-- Source IT: highway takes precedence over track.
	return if road.rank >= 2 then "major" elseif road.track then "track" else "minor"
end
local function rgb(hex: string): { number }
	return { tonumber(string.sub(hex, 2, 3), 16) :: number, tonumber(string.sub(hex, 4, 5), 16) :: number, tonumber(string.sub(hex, 6, 7), 16) :: number }
end
local function blend(pixels: buffer, at: number, color: { number }, alpha: number)
	local old = buffer.readu8(pixels, at + 3) / 255
	local combined = alpha + old * (1 - alpha)
	if combined <= 0 then return end
	for ch = 0, 2 do
		buffer.writeu8(pixels, at + ch, math.clamp(math.floor((color[ch + 1] * alpha + buffer.readu8(pixels, at + ch) * old * (1 - alpha)) / combined + 0.5), 0, 255))
	end
	buffer.writeu8(pixels, at + 3, math.floor(combined * 255 + 0.5))
end
function RoadPixels.paint(pixels: buffer, width: number, height: number, mapW: number, mapH: number, xOffset: number, fullWidth: number, roads: { any }, config: any)
	-- The persistent far roads are painted into the existing ground buffer before upload. They
	-- cannot be culled as hundreds of very thin Parts or disappear with streamed town detail.
	local scaleX, scaleY = fullWidth / mapW, height / mapH
	local ordered = table.clone(roads)
	local priorities = { track = 1, minor = 2, major = 3 }
	table.sort(ordered, function(a, b) return priorities[RoadPixels.kind(a)] < priorities[RoadPixels.kind(b)] end)
	for _, road in ordered do
		local kind = RoadPixels.kind(road)
		local half = config.widths[kind].half
		local color = rgb(config.roads.far[if kind == "major" then "asphalt" elseif kind == "minor" then "road" else "dust"])
		local opacity = if kind == "major" then 1 elseif kind == "minor" then config.roads.far.roadAlpha else config.roads.far.trackAlpha
		for i = 1, #road.pts - 3, 2 do
			local ax, ay, bx, by = road.pts[i], road.pts[i + 1], road.pts[i + 2], road.pts[i + 3]
			local dx, dy = bx - ax, by - ay
			local squared = dx * dx + dy * dy
			if squared == 0 then continue end
			local aa = math.max(1 / scaleX, 1 / scaleY) / 2
			local reach = half + aa
			local x0 = math.max(0, math.floor((math.min(ax, bx) - reach) * scaleX - xOffset))
			local x1 = math.min(width - 1, math.ceil((math.max(ax, bx) + reach) * scaleX - xOffset))
			local y0 = math.max(0, math.floor((math.min(ay, by) - reach) * scaleY))
			local y1 = math.min(height - 1, math.ceil((math.max(ay, by) + reach) * scaleY))
			for y = y0, y1 do
				for x = x0, x1 do
					local px, py = (x + xOffset + 0.5) / scaleX, (y + 0.5) / scaleY
					local t = math.clamp(((px - ax) * dx + (py - ay) * dy) / squared, 0, 1)
					local distance = math.sqrt((px - ax - t * dx)^2 + (py - ay - t * dy)^2)
					local alpha = math.clamp((half + aa - distance) / (2 * aa), 0, 1) * opacity
					if alpha > 0 then blend(pixels, (y * width + x) * 4, color, alpha) end
				end
			end
		end
	end
end
return RoadPixels
