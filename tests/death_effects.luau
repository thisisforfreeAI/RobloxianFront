--!strict
-- Register pure presentation regressions with tests/run; generated configuration stays private.
return function(test: any, eq: any)
	local fs = require("@lune/fs")
	if not fs.isFile("src/shared/GameData/DeathFx.luau") then
		print("  skip  DeathFx.luau not generated (export_death_fx.cjs)")
		return
	end
	local Effects = require("../src/shared/Presentation/DeathEffects")
	local config = require("../src/shared/GameData/DeathFx") :: any
	local function advance(e: any, seconds: number)
		for _ = 1, math.floor(seconds / 0.05 + 0.5) do e:step(0.05) end
	end
	test("death variants use each class's weighted intervals, including IFV and launcher", function()
		for kind, class in { tank = "tank", ifv = "ifv", rocket = "launcher", artillery = "gun", scout = "light" } do
			local weights, total, before = config.death.variants.weights[class], 0, 0
			for _, name in { "blast", "cook", "toss", "brew", "quiet" } do total += weights[name] end
			for _, name in { "blast", "cook", "toss", "brew", "quiet" } do
				if weights[name] > 0 then
					local sample = (before + weights[name] / 2) / total
					local e = Effects.new(config, function() return sample end)
					eq(e:kill(kind, 10, 10).variant, name, kind)
				end
				before += weights[name]
			end
		end
	end)
	test("quiet death has no blast and can smoulder without catching fire", function()
		local e = Effects.new(config, function() return 0.99 end)
		e:kill("scout", 10, 10, "quiet")
		eq(#e.later, 0)
		for _, p in e.particles do assert(p.tex ~= "star" and p.tex ~= "disc" and not string.find(p.tex, "blob")) end
		advance(e, 2)
		local smoke = false
		for _, p in e.particles do if string.find(p.tex, "puff") then smoke = true end end
		assert(smoke)
	end)
	test("quiet fire waits for ignition delay then ends", function()
		local e = Effects.new(config, function() return 0.01 end)
		e:kill("truck", 10, 10, "quiet")
		eq(#e.later, 1)
		local due = e.later[1].at
		advance(e, due - 0.1)
		eq(#e.emitters, 1, "only smoulder before ignition")
		advance(e, 0.2)
		eq(#e.emitters, 2, "burn starts after delay")
		advance(e, 30)
		eq(#e.emitters, 0); eq(#e.later, 0); eq(#e.particles, 0)
	end)
	test("cook-off pops before its final blast and keeps the wreck burning", function()
		local e = Effects.new(config, function() return 0.5 end)
		e:kill("tank", 10, 10, "cook")
		local finale = 0
		for _, event in e.later do finale = math.max(finale, event.at) end
		local pop = false
		for _ = 1, 14 do
			e:step(0.05)
			for _, p in e.particles do if p.tex == "star" then pop = true end end
		end
		assert(pop, "cook pops before finale")
		advance(e, finale - e.time + 0.05)
		local blast = false
		for _, p in e.particles do
			if p.size == config.death.variants.cook["end"].blast * config.blast.bands[1].share then blast = true end
		end
		assert(blast, "final blast was scheduled")
		eq(#e.emitters, 1, "wreck burns after cook finale")
	end)
	test("brew-up makes a rising jet and starts the wreck burn before the jet ends", function()
		local e = Effects.new(config, function() return 0.5 end)
		e:kill("ifv", 10, 10, "brew")
		advance(e, 0.3)
		local jet = false
		for _, p in e.particles do if p.len == config.death.variants.brew.stretch and p.vh > 0 then jet = true end end
		assert(jet)
		advance(e, 1.05)
		eq(#e.emitters, 2, "jet and wreck burn overlap")
	end)
	test("long death budget falls back to blast and recovers after expiry", function()
		local e = Effects.new(config, function() return 0.5 end)
		for _ = 1, config.death.variants.maxLong do eq(e:kill("tank", 10, 10, "cook").variant, "cook") end
		eq(e:kill("tank", 10, 10, "brew").variant, "blast")
		advance(e, config.death.variants.cook.sec[2] + 0.1)
		eq(e:kill("tank", 10, 10, "brew").variant, "brew")
	end)
	test("toss shares a single trajectory with its smoke trail and landing", function()
		local e = Effects.new(config, function() return 0.5 end)
		local toss = e:kill("tank", 10, 10, "toss")
		assert(toss.sec > 0 and toss.height > 0 and toss.turn ~= 0)
		advance(e, toss.sec + 0.05)
		local landing = false
		for _, p in e.particles do
			if p.tex == "ring" and math.abs(p.x - (10 + toss.x)) < 1e-8 and math.abs(p.y - (10 + toss.y)) < 1e-8 then landing = true end
		end
		assert(landing, "landing uses the trajectory returned to the wreck drawer")
	end)
	test("death particles stay capped and every variant releases its timers and particles", function()
		for _, variant in { "blast", "cook", "brew", "toss", "quiet" } do
			local e = Effects.new(config, function() return 0.5 end)
			e.maxParticles = 20
			for _ = 1, 10 do e:kill("tank", 10, 10, variant) end
			for _ = 1, 600 do
				e:step(0.05)
				assert(#e.particles <= 20)
				for _, p in e.particles do assert(p.x == p.x and p.h >= 0 and p.alpha >= 0 and p.alpha <= 1) end
			end
			eq(#e.particles, 0, variant); eq(#e.emitters, 0, variant); eq(#e.later, 0, variant)
		end
	end)
	test("local particle atlas decodes to its declared dimensions", function()
		local atlas = require("../src/client/DevAssets/OrigDeathFx") :: any
		local MapCodec = require("../src/shared/Maps/MapCodec")
		local PixelCodec = require("../src/shared/Assets/PixelCodec")
		local pixels = PixelCodec.decode(MapCodec.base64Decode(atlas.rle), atlas.width, atlas.height)
		eq(buffer.len(pixels), atlas.width * atlas.height * 4)
		eq(atlas.width, atlas.frame * 4)
		assert(buffer.readu8(pixels, ((atlas.frame / 2) * atlas.width + atlas.frame * 1.5) * 4 + 3) > 0, "disc has opaque centre")
	end)
end
