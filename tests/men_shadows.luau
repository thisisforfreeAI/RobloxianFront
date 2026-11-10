--!strict
return function(test: any, eq: any)
	local fs = require("@lune/fs")
	if not fs.isFile("src/shared/GameData/MenFx.luau") then print("  skip  MenFx.luau not generated (pack_men_fx.py)"); return end
	local Shadows = require("../src/shared/Presentation/MenShadows")
	local cfg = require("../src/shared/GameData/MenFx") :: any
	local function near(a: number, b: number) assert(math.abs(a - b) < 1e-10, `{a} differs from {b}`) end
	test("soldier shadows select standing, kneeling and low pose heights", function()
		for _, pose in { "stand", "walk0", "walk3", "dig0", "dig1", "load" } do eq(Shadows.height(cfg, pose), cfg.shadow.up) end
		for _, pose in { "kneel", "plant", "set", "kick" } do eq(Shadows.height(cfg, pose), cfg.shadow.kneel) end
		for _, pose in { "prone", "fallen", "base" } do eq(Shadows.height(cfg, pose), cfg.shadow.low) end
	end)
	test("kneeling and prone soldier shadows fall shorter than standing shadows", function()
		local _, standing = Shadows.project(cfg, "rifle", "stand", 0, 1, 0, 0.74)
		local _, kneeling = Shadows.project(cfg, "rifle", "kneel", 0, 1, 0, 0.74)
		local _, prone = Shadows.project(cfg, "rifle", "prone", 0, 1, 0, 0.74)
		assert(standing > kneeling and kneeling > prone and prone > 0)
	end)
	test("soldier shadow projection has no offset or stretch without sun", function()
		local x, y, axis, stretch = Shadows.project(cfg, "rifle", "stand", 0, 1, 0, 0)
		eq(x, 0); eq(y, 0); eq(axis, 0); eq(stretch, 1)
	end)
	test("soldier shadow reach is capped and uses the source pose's length", function()
		local size = 0.6
		local x, y, _, stretch = Shadows.project(cfg, "leader", "walk0", 0, size, cfg.maxReach * 10, 0)
		local reach = size * cfg.shadow.up * cfg.maxReach
		near(x, reach / 2); near(y, 0)
		near(stretch, 1 + reach / (size * cfg.length.leader.walk0))
	end)
	test("rotating soldier and sun together rotates the shadow without changing stretch", function()
		local angle, heading = 0.8, 0.3
		local x, y, axis, stretch = Shadows.project(cfg, "rifle", "walk1", heading, 0.6, 0.2, 0.7)
		local c, s = math.cos(angle), math.sin(angle)
		local rx, ry, ra, rs = Shadows.project(cfg, "rifle", "walk1", heading + angle, 0.6, 0.2 * c - 0.7 * s, 0.2 * s + 0.7 * c)
		near(rx, x * c - y * s); near(ry, x * s + y * c); near(ra, axis + angle); near(rs, stretch)
	end)
	test("all packed soldier masks decode and retain valid crop pivots for every facing", function()
		local MapCodec = require("../src/shared/Maps/MapCodec")
		local PixelCodec = require("../src/shared/Assets/PixelCodec")
		for _, name in { "Rifle", "Leader", "Para", "Gunner", "Loader", "Mortarman", "Bearer", "Tube", "Crew", "Engineer", "Sapper" } do
			local atlas = require("../src/client/DevAssets/OrigMen" .. name .. "Fx") :: any
			local px = PixelCodec.decode(MapCodec.base64Decode(atlas.rle), atlas.width, atlas.height)
			eq(buffer.len(px), atlas.width * atlas.height * 4)
			assert(atlas.width <= 1024 and atlas.height <= 1024)
			for _, poses in atlas.poses do
				for key, frames in poses do
					eq(#frames, cfg.facings)
					for _, rect in frames do
						local x, y, w, h, ox, oy, f = table.unpack(rect)
						eq(f, if key == "rimHalf" or key == "shadeHalf" then cfg.frame / 2 else cfg.frame)
						assert(x >= 0 and y >= 0 and x + w <= atlas.width and y + h <= atlas.height)
						assert(ox >= 0 and oy >= 0 and ox + w <= f and oy + h <= f)
						if w > 0 and h > 0 then
							-- Every nonempty crop has a transparent gutter to isolate adjacent masks.
							assert(x > 0 and y > 0 and x + w < atlas.width and y + h < atlas.height)
							for i = x - 1, x + w do
								eq(buffer.readu8(px, ((y - 1) * atlas.width + i) * 4 + 3), 0)
								eq(buffer.readu8(px, ((y + h) * atlas.width + i) * 4 + 3), 0)
							end
						end
					end
				end
			end
		end
	end)
end
