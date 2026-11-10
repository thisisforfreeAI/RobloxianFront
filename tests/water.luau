--!strict
-- WaterShade: the water part of the game's ground shader, on the CPU. Synthetic settings only (the
-- real ones are generated locally); the data test runs when Water_<map>.luau has been generated.
return function(test: any, eq: any)
	local W = require("../src/shared/Presentation/WaterShade")
	local function near(a: number, b: number, tol: number?)
		assert(math.abs(a - b) <= (tol or 1e-9), `{a} differs from {b}`)
	end
	local U = { mix = 0.5, period = 4, farPeriod = 6, segment = 3, color = { 1, 1, 1 }, off = { 0, 0, 0 }, farOff = { 0.2, 0.2, 0.2 } }
	local C = { texels = 6, period = 2, step = 1, color = { 0.9, 0.9, 0.9 } }
	local T = { periodSec = 6, segment = 3, steps = 6, wet = 0.2, foam = 0.5, ragged = 0.5 }
	local D = { far = 10, blend = 1, shallow = 0.5, deep = 0.5, steps = 4, shallowTint = { 0, 1, 0 }, deepTint = { 0, 0, 1 },
		swell = { from = 2, fade = 4, cells = 7, drift = 0.2, sheen = 0.1, shade = 0.1, light = { 1, 1, 1 } } }

	test("water hash stays in 0..1 and repeats for the same texel", function()
		for i = 1, 500 do
			local h = W.hash21(i * 1.7, i * 0.3)
			assert(h >= 0 and h < 1)
			eq(h, W.hash21(i * 1.7, i * 0.3))
		end
	end)
	test("water noise reads its cached lattice the same as hashing directly", function()
		local n = W.newNoise()
		eq(W.vnoise(n, 3, 4), W.hash21(3, 4))
		local v = W.vnoise(n, 3.5, 4.25)
		assert(v >= 0 and v <= 1)
		eq(W.vnoise(n, 3.5, 4.25), v)
	end)
	test("water dither is the 4 x 4 Bayer matrix", function()
		eq(W.bayer4(0, 0), 0.5 / 16)
		eq(W.bayer4(1, 0), 8.5 / 16)
		eq(W.bayer4(0, 1), 12.5 / 16)
		eq(W.bayer4(5, 4), W.bayer4(1, 0))
	end)
	test("depth bands tint the shallows near the shore and the deep far out", function()
		local r, g, b = W.depthBands(0.5, 0.5, 0.5, 2, 2, 0, D) -- shore 0, dither 0.53: level 0.05, step 0
		near(r, 0.25); near(g, 0.75); near(b, 0.25)
		r, g, b = W.depthBands(0.5, 0.5, 0.5, 2, 2, 100, D) -- far out: full deep
		near(r, 0.25); near(g, 0.25); near(b, 0.75)
		eq(W.openOf(1, D), 0)
		eq(W.openOf(6, D), 1)
	end)
	test("surf foam is lit for half its period and settled the other half", function()
		local r = W.surf(0.4, 0.4, 0.4, 0, false, 1, U) -- phase 0.25: settled into the near band
		near(r, 0.2)
		r = W.surf(0.4, 0.4, 0.4, 0, false, 3, U) -- phase 0.75: lit
		near(r, 0.7)
		r = W.surf(0.4, 0.4, 0.4, 0, true, 1, U) -- the far line: its own off colour
		near(r, 0.3)
	end)
	test("a wave crest moves for half its period", function()
		local r = W.crest(0.5, 0.5, 0.5, 0, false, 0.5, C, { 0, 0, 0 })
		near(r, 0.5)
		r = W.crest(0.5, 0.5, 0.5, 0, false, 1.5, C, { 0, 0, 0 })
		near(r, 0.9)
		r = W.crest(0.5, 0.5, 0.5, 0, true, 1.5, C, { 0.1, 0.1, 0.1 })
		near(r, 0.1)
	end)
	test("the tide wets one then two texels of sand and leaves them dry again", function()
		local foam = { 1, 1, 1 }
		-- step k = floor(phase x 6): reach 0, 1, 2, 2, 1, 0
		local function at(k: number, d: number, ragged: boolean): number
			return (W.tide(0.5, 0.5, 0.5, d, 0, ragged, (k + 0.5) / 6 * T.periodSec, T, foam))
		end
		near(at(0, 1, true), 0.5) -- dry
		near(at(1, 1, true), 0.5 * 0.8 + (1 - 0.5 * 0.8) * 0.5) -- coming in: wet with a foam edge
		near(at(2, 1, true), 0.4) -- wet, the edge has moved on
		near(at(2, 2, true), 0.4 + 0.6 * 0.5) -- the second texel at the edge
		near(at(2, 2, false), 0.5) -- not ragged: the second texel stays dry
		near(at(4, 1, true), 0.4) -- going out: wet, no foam
		near(at(5, 1, true), 0.5)
	end)
	test("glints light about their share of open water texels", function()
		local G = { share = 0.01, perSec = 0.6, sun = 0.5, moon = 0.25 }
		local lit = 0
		for y = 0, 199 do
			for x = 0, 199 do
				if W.glints(x, y, W.glintLot(x, y), 12.3, G) then
					lit += 1
				end
			end
		end
		assert(lit > 250 and lit < 550, `{lit} of 40000 lit, expected about 400`)
		near(W.glintStrength(G, 0, 1), 0.5)
		near(W.glintStrength(G, 1, 0), 0.25 * 0.25)
	end)
	test("river flow leaves still water alone", function()
		local n = W.newNoise()
		local Fl = { cut = 0.1, full = 0.5, phaseSec = 4, cellsPerSec = 1, swell = { freq = 0.2, smear = 2, sheen = 0.2, shade = 0.2 },
			lane = { spacing = 1, half = 0.1, meander = 0.5 }, dash = { freq = 0.3, from = 0.5, soft = 0.2 }, strength = 0.3,
			light = { 1, 1, 1 }, dark = { 0, 0, 0 }, color = { 1, 1, 1 }, swellAmpRiver = 1 }
		local r, g, b = W.flow(n, 0.3, 0.3, 0.3, 5, 5, 1, 0, 0, 2, 1, Fl, 1 / 3)
		eq(r, 0.3); eq(g, 0.3); eq(b, 0.3)
		r = W.flow(n, 0.3, 0.3, 0.3, 5, 5, 1, 0, 1, 2, 1, Fl, 1 / 3)
		assert(r >= 0 and r <= 1)
	end)

	local fs = require("@lune/fs")
	local path = "src/client/DevAssets/Water_shoals.luau"
	if not fs.isFile(path) then
		print("  skip  Water_shoals.luau not generated (export_water.cjs)")
		return
	end
	test("generated water data decodes into chunks of mask codes and a water map", function()
		local MapCodec = require("../src/shared/Maps/MapCodec")
		local Inflate = require("../src/shared/Utilities/Inflate")
		local meta = require("../src/client/DevAssets/Water_shoals") :: any
		assert(meta.water and #meta.chunks > 0)
		local F = meta.settings.fine
		local e = meta.chunks[1]
		local tw, th = e[3] * F, e[4] * F
		local px = Inflate.raw(MapCodec.base64Decode(e[5]), tw * th * 4)
		local drawn, bad = 0, 0
		for i = 0, tw * th - 1 do
			local m = buffer.readu8(px, i * 4 + 3)
			if m ~= 0 then
				drawn += 1
				if m < meta.settings.codes.sand or m > meta.settings.codes.crestTail then
					bad += 1
				end
			end
		end
		assert(drawn > 0, "no water texels in the first chunk")
		eq(bad, 0)
		local wm = Inflate.raw(MapCodec.base64Decode(e[6]), (e[3] + 2) * (e[4] + 2) * 4)
		eq(buffer.len(wm), (e[3] + 2) * (e[4] + 2) * 4)
	end)
end
