--!strict
-- One small numerical state for all renderers. This creates no EditableImages or image variants.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Daylight = require(Shared.Presentation.Daylight)
local Controller = {}
local data = Shared:FindFirstChild("GameData")
local mod = data and data:FindFirstChild("Daylight")
local config: any = nil
if mod then
	local ok, value = pcall(require, mod :: ModuleScript)
	if ok then config = value else warn("[Daylight] Local settings could not load:", value) end
else
	warn("[Daylight] Generate local settings with tools/conversion/export_daylight.cjs; static noon fallback stays")
end
-- APPROX fallback for a clone missing the private settings: retain the old fixed noon shadow.
local current: any = if config then Daylight.sample(config, config.clock.sunUp / 2) else {
	phase = 0.31, mul = { 1, 1, 1 }, add = { 0, 0, 0 }, night = 0, shadow = { 0, 1 / 1.35 }, shadowAlpha = 1,
}

function Controller.apply(day: { number }?)
	if not day or not config then return end
	local phase = day[1]
	if type(phase) ~= "number" or phase ~= phase or math.abs(phase) == math.huge then return end
	if phase % 1 ~= current.phase then current = Daylight.sample(config, phase) end
end
function Controller.get(): any return current end
function Controller.postEffect(): any return Daylight.postEffect(current) end
function Controller.hourToPhase(hour: number): number
	return if config then Daylight.hourToPhase(config, hour) else ((hour - 6) / 24) % 1
end
function Controller.phaseToHour(phase: number): number
	return if config then Daylight.phaseToHour(config, phase) else (6 + phase * 24) % 24
end
function Controller.preset(name: string, hour: number): number
	return if config then Daylight.preset(config, name, hour) else Controller.hourToPhase(hour)
end

return Controller
