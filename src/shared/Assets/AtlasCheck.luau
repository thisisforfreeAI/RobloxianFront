--!strict
--[[
	AtlasCheck: checks a decoded atlas page in memory, the same way tools/asset_pipeline/validate_atlas.py
	checks the PNG. Runs in Lune tests and again in Studio on the pixels read back from the EditableImage,
	which proves the decode, rectangle offsets, direction order, pivot and transparency survive the trip.
	Orientation/pivot checks only make sense for the synthetic arrow frames.
]]
local AtlasCheck = {}

local function px(buf: buffer, pageW: number, x: number, y: number): (number, number, number, number)
	local o = (y * pageW + x) * 4
	return buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2), buffer.readu8(buf, o + 3)
end

export type Result = { ok: boolean, failures: { string }, worstDegrees: number, partialAlpha: boolean }

function AtlasCheck.run(pixels: buffer, pageW: number, meta: any, synthetic: boolean): Result
	local fw, fh, pvx, pvy = meta.frameWidth, meta.frameHeight, meta.pivot.x, meta.pivot.y
	local failures, worst, partial = {}, 0, false
	for d = 0, meta.directions - 1 do
		local cell = meta.frames.idle[1][d + 1]
		local x0, y0 = cell[2], cell[3]
		if x0 ~= (d % meta.columns) * (fw + 2 * meta.padding) + meta.padding then
			table.insert(failures, `direction {d}: column offset {x0}`)
		end
		local edgeClear = true
		for t = 0, fw - 1 do
			local _, _, _, a1 = px(pixels, pageW, x0 + t, y0)
			local _, _, _, a2 = px(pixels, pageW, x0 + t, y0 + fh - 1)
			local _, _, _, a3 = px(pixels, pageW, x0, y0 + t)
			local _, _, _, a4 = px(pixels, pageW, x0 + fw - 1, y0 + t)
			if a1 + a2 + a3 + a4 > 0 then
				edgeClear = false
			end
		end
		if not edgeClear then
			table.insert(failures, `direction {d}: frame edge not transparent (bleed risk)`)
		end
		if synthetic then
			local r, g, b = px(pixels, pageW, x0 + pvx, y0 + pvy)
			if not (r == 255 and g == 0 and b == 255) then
				table.insert(failures, `direction {d}: pivot cross missing at ({pvx}, {pvy})`)
			end
			local sx, sy = 0, 0
			for y = 0, fh - 1 do
				for x = 0, fw - 1 do
					local cr, cg, cb, ca = px(pixels, pageW, x0 + x, y0 + y)
					if ca > 0 and ca < 255 then
						partial = true
					end
					local hi, lo = math.max(cr, cg, cb), math.min(cr, cg, cb)
					if ca == 255 and hi - lo > 100 and not (cr == 255 and cg == 0 and cb == 255) then
						local dx, dy = x - pvx, y - pvy
						if dx * dx + dy * dy > 900 then
							sx += dx
							sy += dy
						end
					end
				end
			end
			local ang = math.deg(math.atan2(sy, sx)) % 360
			local err = math.abs((ang - d * 22.5 + 180) % 360 - 180)
			worst = math.max(worst, err)
			if err > 3 then
				table.insert(failures, `direction {d}: arrow points {math.floor(ang + 0.5)} deg, expected {d * 22.5}`)
			end
		end
	end
	if synthetic and not partial then
		table.insert(failures, "no partially transparent pixels (alpha lost?)")
	end
	return { ok = #failures == 0, failures = failures, worstDegrees = worst, partialAlpha = partial }
end

return AtlasCheck
