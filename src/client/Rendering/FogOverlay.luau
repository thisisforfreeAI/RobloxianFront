--!strict
--[[
	FogOverlay: darkens the ground your side cannot see right now, from the vision runs the server
	sends with snapshots (cells seen now = clear). One pixel per cell on an EditableImage laid just
	above the ground. If EditableImage is unavailable there is no overlay (units and buildings are
	still hidden, since the server never sends them). Local FogLook supplies source terrain/chart
	and explored-region colours. Canvas blur is approximated by a finite Gaussian; source noise,
	hatching and zoom-adaptive feather are pending. Binary detection stays separate from the display.
]]

local ImageMemory = require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=ImageMemory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local FogPixels = require(ReplicatedStorage:WaitForChild("Shared").Presentation.FogPixels)
local Terrain = require(ReplicatedStorage:WaitForChild("Shared").Definitions.Terrain)
local data = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("GameData")
local settings = data and data:FindFirstChild("FogLook")
local profile: any = nil
if settings then
	local ok,value=pcall(require,settings :: ModuleScript)
	if ok then profile=value end
end

local FogOverlay = {}

local S = World.STUDS_PER_CELL
local DARK_ALPHA = 150 -- 0..255 over unseen cells
local image: any = nil
local width, height = 0, 0
local pixels: buffer
local visible: buffer
local explored: buffer
local terrain: buffer? = nil
local colourCache: any = {}
local revision=0
function FogOverlay.revision():number return revision end

function FogOverlay.start(mapWidth: number, mapHeight: number, terrainPixels: buffer?)
	width, height = mapWidth, mapHeight
	local ok, img = pcall(function()
		return ImageMemory.create(Vector2.new(mapWidth, mapHeight))
	end)
	if not ok or not img then
		warn("[FogOverlay] EditableImage unavailable, no fog overlay:", img)
		return
	end
	image = img
	pixels = buffer.create(mapWidth * mapHeight * 4)
	visible = buffer.create(mapWidth * mapHeight)
	explored = buffer.create(mapWidth * mapHeight)
	colourCache = {}
	terrain = terrainPixels
	if not profile then warn("[FogOverlay] Generate source fog colours with export_fog.cjs; legacy black fog stays") end
	local part = Instance.new("Part")
	part.Name = "FogOverlay"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	-- same orientation as the ground (see MapRenderer): GUI x runs east, GUI y south
	part.Size = Vector3.new(mapHeight * S, 0.1, mapWidth * S)
	part.CFrame = CFrame.new(mapWidth * S / 2, World.GROUND_Y + 0.35, mapHeight * S / 2) * CFrame.Angles(0, World.TOP_GUI_YAW, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(mapWidth * 4, mapHeight * 4)
	gui.LightInfluence = 0
	gui.Adornee = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Default
	label.ImageContent = Content.fromObject(image)
	label.Parent = gui
	gui.Parent = part
	part.Destroying:Connect(function()
		ImageMemory.release(img)
		if image == img then image = nil end
	end)
	part.Parent = workspace
	FogOverlay.apply({}, false)
end

-- vision: row runs { y, x0, x1, ... } of seen cells; seeAll: no fog for this player
function FogOverlay.apply(vision: { number }, seeAll: boolean)
	if not image then
		return
	end
	local n = width * height
	for i = 0, n - 1 do
		buffer.writeu8(visible,i,if seeAll then 1 else 0)
	end
	if not seeAll then
		for i = 1, #vision, 3 do
			local y, x0, x1 = vision[i], vision[i + 1], vision[i + 2]
			for x = x0, x1 do
				buffer.writeu8(visible,y*width+x,1)
			end
		end
	end
	if seeAll then pixels=buffer.create(n*4)
	elseif profile and terrain then pixels=FogPixels.colour(visible,terrain,explored,Terrain.names,profile,width,height,colourCache)
	else pixels=FogPixels.soften(visible,width,height,DARK_ALPHA) end
	-- Detection changes immediately; this coalesced display update cannot reveal hidden units.
	upload(image,Vector2.zero,Vector2.new(width,height),pixels,{priority=0})
	revision+=1
end

-- true when cell (x, y) is fogged for this player right now (false without the overlay)
function FogOverlay.hidden(x: number, y: number): boolean
	if not image then
		return false
	end
	local cx, cy = math.floor(x), math.floor(y)
	if cx < 0 or cy < 0 or cx >= width or cy >= height then
		return false
	end
	return buffer.readu8(visible,cy*width+cx)==0
end

return FogOverlay
