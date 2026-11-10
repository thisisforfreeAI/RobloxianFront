--!strict
-- Roads in generated towns now share the town overview/detail pixels and roof-shadow pass.
-- Keeping a second coarse road beneath those chunks exposed square fringes at close zoom.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadPixels = require(Shared.Presentation.RoadPixels)
local RoadRenderer = {}
local assets = script.Parent.Parent:FindFirstChild("DevAssets")
local cached: { [string]: boolean } = {}
local function baked(id: string): boolean
	if cached[id] ~= nil then return cached[id] end
	local module = assets and assets:FindFirstChild("City_" .. id)
	local ok, meta = pcall(function() return if module then require(module :: ModuleScript) else nil end)
	cached[id] = ok and meta ~= nil and meta.roads == true
	return cached[id]
end
local data = Shared:FindFirstChild("GameData")
local settings = data and data:FindFirstChild("RoadLook")
local config: any = nil
if settings then
	local ok, value = pcall(require, settings :: ModuleScript)
	if ok then config = value end
end
function RoadRenderer.paint(pixels: buffer, width: number, height: number, map: any, xOffset: number, fullWidth: number)
	-- Legacy maps without integrated road art retain a far-road/plain-Part fallback.
	if not baked(map.data.id) and config then
		RoadPixels.paint(pixels,width,height,map.width,map.height,xOffset,fullWidth,map.data.roads,config)
	end
end
function RoadRenderer.build(map: any, _parent: Instance): boolean
	return baked(map.data.id)
end
return RoadRenderer
