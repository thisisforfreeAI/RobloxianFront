--!strict
-- StreetFurniture: lamp posts at the game's lamp spots (a port addition). Synthetic data; the data
-- test runs when DevAssets/StreetFurniture_saddle.luau has been generated locally.
return function(test: any, eq: any)
	local SF = require("../src/shared/Presentation/StreetFurniture")
	local F, N = SF.FRAME, SF.FACINGS
	local function near(a: number, b: number, tol: number?)
		assert(math.abs(a - b) <= (tol or 1e-9), `{a} differs from {b}`)
	end

	test("street furniture facing rounds to the nearest of 16 and wraps", function()
		eq(SF.facing(0), 0)
		eq(SF.facing(math.pi / 2), 4)
		eq(SF.facing(math.pi), 8)
		eq(SF.facing(-math.pi / 2), 12)
		eq(SF.facing(2 * math.pi - 0.01), 0)
		eq(SF.facing(math.pi / 16 + 0.01), 1)
		near(SF.facingAngle(4), math.pi / 2)
	end)

	local atlas = SF.drawAtlas()
	local aw, ah = SF.atlasSize()
	local function px(x: number, y: number): (number, number, number, number)
		local o = (y * aw + x) * 4
		return buffer.readu8(atlas, o), buffer.readu8(atlas, o + 1), buffer.readu8(atlas, o + 2), buffer.readu8(atlas, o + 3)
	end

	test("street furniture atlas is 16 frames by 2 rows of RGBA", function()
		eq(aw, N * F)
		eq(ah, 2 * F)
		eq(buffer.len(atlas), aw * ah * 4)
	end)

	test("street furniture head sits at each frame's centre with a pale lens", function()
		for f = 0, N - 1 do
			for row = 0, 1 do
				-- the head's centre is the corner shared by the four middle texels
				for _, d in { { -1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 0 } } do
					local r, g, b, a = px(f * F + F / 2 + d[1], row * F + F / 2 + d[2])
					eq(a, 255)
					assert(r > 150 and g > 150 and b > 130, `frame {f} row {row}: lens {r},{g},{b}`)
				end
			end
		end
	end)

	test("street furniture foot stands back from the head, against the facing", function()
		local reach = SF.ARM * SF.SCALE
		for _, f in { 0, 4, 8, 12 } do
			local a = SF.facingAngle(f)
			-- a texel on the foot disc beside the arm (1.5 px across it)
			local fx = math.floor(F / 2 - math.cos(a) * reach - math.sin(a) * 1.5)
			local fy = math.floor(F / 2 - math.sin(a) * reach + math.cos(a) * 1.5)
			local _, _, _, whole = px(f * F + fx, fy)
			local _, _, _, raised = px(f * F + fx, F + fy)
			assert(whole > 100, `frame {f}: no foot at {fx},{fy} ({whole})`)
			-- row 1 has no foot disc
			assert(raised < whole, `frame {f}: the shadow row should leave out the foot`)
			-- the opposite side of the head is empty
			local ox = math.floor(F / 2 + math.cos(a) * reach + 0.5)
			local oy = math.floor(F / 2 + math.sin(a) * reach + 0.5)
			local _, _, _, empty = px(f * F + ox, oy)
			eq(empty, 0)
		end
	end)

	test("street furniture frames have clear corners and stay inside their frame", function()
		for f = 0, N - 1 do
			for _, c in { { 0, 0 }, { F - 1, 0 }, { 0, F - 1 }, { F - 1, F - 1 } } do
				local _, _, _, a = px(f * F + c[1], c[2])
				eq(a, 0)
			end
			for y = 0, 2 * F - 1 do
				local _, _, _, a = px(f * F, y)
				eq(a, 0)
			end
		end
	end)

	test("street furniture zoom share clamps between FROM and FULL", function()
		eq(SF.share(0), 0)
		eq(SF.share(SF.FROM), 0)
		eq(SF.share(SF.FULL), 1)
		eq(SF.share(1000), 1)
		near(SF.share((SF.FROM + SF.FULL) / 2), 0.5)
	end)

	test("street furniture shadow follows the light, is capped and fades at night", function()
		local x, y, a = SF.shadow({ shadow = { 1, 0 }, shadowAlpha = 1 })
		near(x, SF.POLE_HEIGHT)
		near(y, 0)
		near(a, SF.SHADOW_ALPHA)
		x, y = SF.shadow({ shadow = { 0, 10 }, shadowAlpha = 1 })
		near(x, 0)
		near(y, 2 * SF.POLE_HEIGHT)
		local _, _, dim = SF.shadow({ shadow = { 0, 1 }, shadowAlpha = 0.25 })
		near(dim, SF.SHADOW_ALPHA * 0.25)
		x, y, a = SF.shadow(nil)
		eq(x, 0)
		eq(y, 0)
		near(a, SF.SHADOW_ALPHA)
	end)

	test("street furniture grid query finds exactly the lamps in the box", function()
		local lamps = {}
		for i = 0, 99 do
			table.insert(lamps, (i * 37) % 200 + 0.5)
			table.insert(lamps, (i * 53) % 120 + 0.5)
			table.insert(lamps, 0)
		end
		local g = SF.grid(lamps)
		for _, box in { { 0, 0, 200, 120 }, { 10, 10, 40, 30 }, { 150.2, 3, 151, 119 }, { -5, -5, -1, -1 } } do
			local want = {}
			for i = 1, #lamps, 3 do
				local x, y = lamps[i], lamps[i + 1]
				if x >= box[1] and x <= box[3] and y >= box[2] and y <= box[4] then
					want[i] = true
				end
			end
			local got = SF.query(g, box[1], box[2], box[3], box[4])
			local n = 0
			for _ in want do
				n += 1
			end
			eq(#got, n)
			for _, i in got do
				assert(want[i], `lamp {i} outside the box`)
			end
		end
	end)

	local ok, data = pcall(require, "../src/client/DevAssets/StreetFurniture_saddle")
	if ok and type(data) == "table" then
		test("street furniture saddle data: game lamp spots on the map, angles in range", function()
			eq(data.id, "saddle")
			eq(#data.lamps % 3, 0)
			assert(#data.lamps // 3 > 0, "no lamps")
			for i = 1, #data.lamps, 3 do
				local x, y, a = data.lamps[i], data.lamps[i + 1], data.lamps[i + 2]
				assert(x > 0 and x < 384 and y > 0 and y < 240, `lamp at {x},{y} off the map`)
				assert(a >= -math.pi - 1e-3 and a <= math.pi + 1e-3, `angle {a}`)
			end
		end)
	else
		print("  skip  street furniture saddle data (generate StreetFurniture_saddle.luau to run it)")
	end
end
