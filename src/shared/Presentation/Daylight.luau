--!strict
-- The game's active clear-skirmish palette interpolation (Sqt), sun/moon geometry (xH), night
-- transition (Oh), shadow fade (H0) and two-segment clock (CW/Lqt). Tables are generated locally.
local Daylight = {}
local function smooth(a: number, b: number, value: number): number
	local t = math.clamp((value - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
function Daylight.hourToPhase(config: any, hour: number): number
	local t = (hour - 6) % 24
	return if t < 12 then t / 12 * config.clock.sunUp else config.clock.sunUp + (t - 12) / 12 * (1 - config.clock.sunUp)
end
function Daylight.phaseToHour(config: any, phase: number): number
	local p, up = phase % 1, config.clock.sunUp
	return (if p < up then 6 + 12 * p / up else 18 + 12 * (p - up) / (1 - up)) % 24
end
function Daylight.preset(config: any, name: string, hour: number): number
	-- Admin UX choice derived from the source fade windows: place Dawn/Dusk halfway through the
	-- corresponding transition, so those labels do not jump to full night on the nonuniform clock.
	if name == "Dawn" then return 1 - config.transition.out / 2 end
	if name == "Dusk" then return config.clock.sunUp + config.transition["in"] / 2 end
	return Daylight.hourToPhase(config, hour)
end
function Daylight.sample(config: any, phase: number): any
	assert(phase == phase and math.abs(phase) < math.huge, "invalid daylight phase")
	local p, up, style = phase % 1, config.clock.sunUp, config.style
	local keys = style.keys
	local a, b = keys[#keys], keys[1]
	local span = 1 - a.at + b.at
	local t = if p >= a.at then (p - a.at) / span else (p + 1 - a.at) / span
	for i = 1, #keys - 1 do
		if p >= keys[i].at and p < keys[i + 1].at then
			a, b = keys[i], keys[i + 1]
			span = b.at - a.at
			t = if span > 0 then (p - a.at) / span else 0
			break
		end
	end
	local mul, add = {}, {}
	for i = 1, 3 do mul[i] = a.mul[i] + (b.mul[i] - a.mul[i]) * t; add[i] = a.add[i] + (b.add[i] - a.add[i]) * t end
	local luma = mul[1] * 0.299 + mul[2] * 0.587 + mul[3] * 0.114 -- source palette luminance weights
	if luma < style.minBrightness then for i = 1, 3 do mul[i] *= style.minBrightness / luma end end
	local night = if p < up then 0 else math.min(smooth(up, up + config.transition["in"], p), 1 - smooth(1 - config.transition.out, 1, p))
	local golden = if p < up then math.max(1 - smooth(0, style.goldenSpan, p), smooth(up - style.goldenSpan, up, p)) else 0
	local progress = if p < up then p / up else (p - up) / (1 - up)
	local elevation, east = math.sin(math.pi * progress), math.cos(math.pi * progress)
	local norm = math.sqrt(east * east + style.north * style.north)
	local toward = { east / norm, -style.north / norm }
	local length = 1 / (style.shadowFloor + elevation)
	local color = {}
	for i = 1, 3 do color[i] = if p < up then style.sunNoon[i] + (config.sunGolden[i] - style.sunNoon[i]) * golden else style.moon[i] end
	return { phase = p, mul = mul, add = add, night = night, golden = golden, elevation = elevation,
		toward = toward, shadow = { -toward[1] * length, -toward[2] * length }, color = color,
		shadowAlpha = 1 - config.shadow.nightFade * night }
end
function Daylight.postEffect(sample: any): any
	-- APPROX: Roblox exposes a common brightness/contrast and a multiplicative RGB tint, rather than
	-- the game's per-channel additive shader. Fit a common offset to its source RGB add vector.
	-- This is a source-derived adapter, not a claim about Roblox's exact GPU transfer/tonemapping.
	local mul, add = sample.mul, sample.add
	local gain = math.max(1, mul[1], mul[2], mul[3])
	local dot, square = 0, 0
	for i = 1, 3 do dot += mul[i] * add[i]; square += mul[i] * mul[i] end
	local offset = if square > 0 then dot / square else 0
	return { tint = { mul[1] / gain, mul[2] / gain, mul[3] / gain },
		brightness = math.clamp(gain * offset + (gain - 1) / 2, -1, 1), contrast = math.clamp(gain - 1, -1, 1) }
end
return Daylight
