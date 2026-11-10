--!strict
return function(test: any, eq: any)
	local Roads = require("../src/shared/Presentation/RoadPixels")
	local config = { widths = { major = { half = 1 }, minor = { half = 0.5 }, track = { half = 0.25 } },
		roads = { far = { asphalt = "#ffffff", road = "#a0a0a0", dust = "#505050", roadAlpha = 0.8, trackAlpha = 0.5 } } }
	local roads = { { rank = 2, pts = { 0, 2.5, 8, 2.5 } }, { rank = 1, track = true, pts = { 2, 0, 2, 8 } } }
	test("far-road baking agrees across ground-strip seams", function()
		local whole, left, right = buffer.create(8 * 8 * 4), buffer.create(4 * 8 * 4), buffer.create(4 * 8 * 4)
		Roads.paint(whole, 8, 8, 8, 8, 0, 8, roads, config)
		Roads.paint(left, 4, 8, 8, 8, 0, 8, roads, config)
		Roads.paint(right, 4, 8, 8, 8, 4, 8, roads, config)
		for y = 0, 7 do for x = 0, 7 do
			local piece = if x < 4 then left else right
			eq(buffer.readu32(whole, (y * 8 + x) * 4), buffer.readu32(piece, (y * 4 + x % 4) * 4))
		end end
	end)
	test("road raster clips map edges, ignores zero-length segments and preserves unrelated ground", function()
		local pixels = buffer.create(8 * 8 * 4)
		for i = 0, 63 do buffer.writeu32(pixels, i * 4, 0xFF102030) end
		Roads.paint(pixels, 8, 8, 8, 8, 0, 8, { { rank = 2, pts = { -10, 2.5, 20, 2.5, 20, 2.5 } } }, config)
		eq(buffer.readu32(pixels, (7 * 8 + 7) * 4), 0xFF102030)
		eq(buffer.readu32(pixels, (2 * 8 + 3) * 4), 0xFFFFFFFF)
	end)
	test("source road classification gives highways priority over track flag", function()
		eq(Roads.kind({ rank = 2, track = true }), "major")
		eq(Roads.kind({ rank = 1, track = true }), "track")
		eq(Roads.kind({ rank = 1 }), "minor")
	end)
end
