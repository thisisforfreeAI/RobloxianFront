--!strict
return function(test: any, eq: any)
	local fs = require("@lune/fs")
	if not fs.isFile("src/shared/GameData/Daylight.luau") or not fs.isFile("src/shared/GameData/DaylightVectors.luau") then
		print("  skip  daylight settings/reference vectors not generated (export_daylight.cjs)")
		return
	end
	local Daylight = require("../src/shared/Presentation/Daylight")
	local config = require("../src/shared/GameData/Daylight") :: any
	local vectors = require("../src/shared/GameData/DaylightVectors") :: any
	local function near(a: number, b: number) assert(math.abs(a - b) < 1e-10, `{a} differs from {b}`) end
	test("daylight palette, sun and night match the game's functions across 21 reference phases", function()
		for _, vector in vectors do
			local sample = Daylight.sample(config, vector.phase)
			for _, key in { "night", "golden", "elevation" } do near(sample[key], vector[key]) end
			for _, key in { "mul", "add", "toward", "shadow", "color" } do
				for i, value in vector[key] do near(sample[key][i], value) end
			end
		end
	end)
	test("game clock roundtrips hours across the unequal daylight/night segments", function()
		for hour = -24, 48, 0.5 do near(Daylight.phaseToHour(config, Daylight.hourToPhase(config, hour)), hour % 24) end
		near(Daylight.hourToPhase(config, 6), 0)
		near(Daylight.hourToPhase(config, 12), config.clock.sunUp / 2)
		near(Daylight.hourToPhase(config, 18), config.clock.sunUp)
		near(Daylight.hourToPhase(config, 0), config.clock.sunUp + (1 - config.clock.sunUp) / 2)
	end)
	test("sun shadows sweep through the day and shorten at noon", function()
		local morning = Daylight.sample(config, config.clock.sunUp * 0.1)
		local noon = Daylight.sample(config, config.clock.sunUp / 2)
		local evening = Daylight.sample(config, config.clock.sunUp * 0.9)
		assert(morning.shadow[1] < 0 and evening.shadow[1] > 0)
		near(noon.shadow[1], 0); near(noon.elevation, 1)
		local function length(v: any): number return math.sqrt(v[1]^2 + v[2]^2) end
		assert(length(morning.shadow) > length(noon.shadow))
		near(length(morning.shadow), length(evening.shadow))
	end)
	test("admin Dawn and Dusk presets select the middle of the source fade transitions", function()
		near(Daylight.sample(config, Daylight.preset(config, "Dawn", 5)).night, 0.5)
		near(Daylight.sample(config, Daylight.preset(config, "Dusk", 21)).night, 0.5)
		near(Daylight.preset(config, "Noon", 12), config.clock.sunUp / 2)
	end)
	test("shadow night fade follows the source transition and returns at dawn", function()
		local noon = Daylight.sample(config, Daylight.hourToPhase(config, 12))
		local midnight = Daylight.sample(config, Daylight.hourToPhase(config, 0))
		local dawn = Daylight.sample(config, 0)
		near(noon.night, 0); near(noon.shadowAlpha, 1)
		near(midnight.night, 1); near(midnight.shadowAlpha, 1 - config.shadow.nightFade)
		near(dawn.night, 0); near(dawn.shadowAlpha, 1)
	end)
	test("daylight wraps phase and palette continuously at the day boundary", function()
		local a, b = Daylight.sample(config, -0.001), Daylight.sample(config, 0.999)
		for i = 1, 3 do near(a.mul[i], b.mul[i]); near(a.add[i], b.add[i]) end
		local wrapped, start = Daylight.sample(config, 1), Daylight.sample(config, 0)
		for i = 1, 3 do near(wrapped.mul[i], start.mul[i]); near(wrapped.add[i], start.add[i]) end
	end)
	test("post-effect adapter remains finite and uses valid Roblox property ranges", function()
		for i = 0, 1000 do
			local state = Daylight.postEffect(Daylight.sample(config, i / 1000))
			assert(state.brightness >= -1 and state.brightness <= 1)
			assert(state.contrast >= -1 and state.contrast <= 1)
			for _, value in state.tint do assert(value == value and value >= 0 and value <= 1) end
		end
		assert(not pcall(Daylight.sample, config, 0/0), "NaN must not reach geometry")
		assert(not pcall(Daylight.sample, config, math.huge), "infinity must not reach geometry")
	end)
end
