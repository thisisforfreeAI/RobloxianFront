--!strict
--[[
	FogOverlay: darkens the ground your side cannot see right now, from the vision runs the server
	sends with snapshots (cells seen now = clear). One pixel per cell on an EditableImage laid just
	above the ground. If EditableImage is unavailable there is no overlay (units and buildings are
	still hidden, since the server never sends them). PLACEHOLDER look (TEMP-003).
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local FogOverlay = {}

local S = World.STUDS_PER_CELL
local DARK_ALPHA = 150 -- 0..255 over unseen cells
local image: any = nil
local width, height = 0, 0
local pixels: buffer

function FogOverlay.start(mapWidth: number, mapHeight: number)
	width, height = mapWidth, mapHeight
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(mapWidth, mapHeight) })
	end)
	if not ok or not img then
		warn("[FogOverlay] EditableImage unavailable, no fog overlay:", img)
		return
	end
	image = img
	pixels = buffer.create(mapWidth * mapHeight * 4)
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
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(image)
	label.Parent = gui
	gui.Parent = part
	part.Parent = workspace
	FogOverlay.apply({}, false)
end

-- vision: row runs { y, x0, x1, ... } of seen cells; seeAll: no fog for this player
function FogOverlay.apply(vision: { number }, seeAll: boolean)
	if not image then
		return
	end
	local n = width * height
	local alpha = if seeAll then 0 else DARK_ALPHA
	for i = 0, n - 1 do
		buffer.writeu32(pixels, i * 4, 0)
		buffer.writeu8(pixels, i * 4 + 3, alpha)
	end
	if not seeAll then
		for i = 1, #vision, 3 do
			local y, x0, x1 = vision[i], vision[i + 1], vision[i + 2]
			for x = x0, x1 do
				buffer.writeu8(pixels, (y * width + x) * 4 + 3, 0)
			end
		end
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
end

return FogOverlay
