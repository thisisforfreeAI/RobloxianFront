--!strict
return function(test: any, eq: any)
	local Stages = require("../src/shared/Presentation/UnitStages")
	test("missile rack stays loaded until a shot, empty throughout reload and loaded at zero", function()
		eq(Stages.artillery(true, nil, 40, 0), Stages.MISSILE_LOADED, "a timer without a shot is not an empty rack")
		eq(Stages.artillery(true, 0, 40, 0), Stages.MISSILE_EMPTY, "a shot at time zero counts")
		eq(Stages.artillery(true, 0, 0.00001, 1), Stages.MISSILE_EMPTY, "positive timer overrides raised rack")
		eq(Stages.artillery(true, 0, 0, 0), Stages.MISSILE_LOADED)
		eq(Stages.artillery(true, 0, -0.05, 0), Stages.MISSILE_LOADED)
	end)
	test("missile empty rack overrides deploy and packing while regular artillery keeps its looks", function()
		for _, raised in { 0, 0.39, 0.4, 0.998, 0.999, 1 } do
			eq(Stages.artillery(true, 10, 1, raised), Stages.MISSILE_EMPTY)
		end
		eq(Stages.artillery(false, 10, 40, 0), 0)
		eq(Stages.artillery(false, 10, 40, 0.4), 1)
		eq(Stages.artillery(false, 10, 40, 0.999), 2)
		eq(Stages.artillery(true, nil, 0, 0.39), Stages.MISSILE_LOADED)
		eq(Stages.artillery(true, nil, 0, 0.4), Stages.MISSILE_SET1)
		eq(Stages.artillery(true, nil, 0, 0.999), Stages.MISSILE_SET2)
	end)
	local fs = require("@lune/fs")
	if not fs.isFile("src/client/DevAssets/OrigArtillery_rep_empty.luau") then
		print("  skip  local missile rack art not generated (pack_missile_rack.py)")
		return
	end
	test("missile rack atlases decode with complete facings, geometry and derived masks", function()
		local MapCodec = require("../src/shared/Maps/MapCodec")
		local PixelCodec = require("../src/shared/Assets/PixelCodec")
		for _, state in { "rep_loaded", "rep_set1", "rep_set2", "rep_empty" } do
			local base = require("../src/client/DevAssets/OrigArtillery_" .. state) :: any
			assert(base.cells > 0 and base.size > 0 and base.artH > 0)
			for _, suffix in { "", "Rim", "RimHalf", "Shade" } do
				local atlas = require("../src/client/DevAssets/OrigArtillery_" .. state .. suffix) :: any
				local pixels = PixelCodec.decode(MapCodec.base64Decode(atlas.rle), atlas.width, atlas.height)
				eq(buffer.len(pixels), atlas.width * atlas.height * 4)
				eq(atlas.directions, 16)
				local y = atlas.strips[state .. (if suffix == "" then "_colour" else "")]
				assert(y ~= nil)
				for facing = 0, 15 do
					local x, row = (facing % atlas.columns) * atlas.frame, y + math.floor(facing / atlas.columns) * atlas.frame
					assert(x + atlas.frame <= atlas.width and row + atlas.frame <= atlas.height)
				end
			end
		end
	end)
end
