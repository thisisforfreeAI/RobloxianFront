--!strict
--[[
	AtlasTestBoard (Studio only): shows the SYNTHETIC 8x2 atlas through the renderer path real unit
	sprites will use, so direction order, rotation mapping, pivot, transparency and rectangle offsets can
	be checked by eye, plus an automatic read-back check of the EditableImage pixels.

	Sprite path under test: flat Part -> SurfaceGui (Top) -> ImageLabel with ImageRectOffset/ImageRectSize
	into one atlas page, ResampleMode Pixelated. Frame = Facing.index(heading), quad yaw = -residual.

	What you should see (docs/STUDIO_TESTS.md, test 6), north of your start:
	  * a ring of 16 sprites; sprite i shows the number i and its arrow points OUTWARD along the thin white
	    reference line (white lines are plain Parts in world space, not sprites);
	  * 0 points east (screen right), 4 south (down), 8 west (left), 12 north (up);
	  * the magenta cross in every sprite sits on the small yellow pivot dot;
	  * the dark shadow disc is see-through (ground visible through it); no slivers of neighbouring frames;
	  * the centre sprite turns slowly and its arrow stays on the yellow needle.
	Keys: R toggles residual rotation (off = pure 16-step snapping), G rotates the SurfaceGui
	compensation by 90 degrees (only needed if every arrow is off by the same quarter turn: report it).
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Facing = require(Shared.Assets.Facing)
local PixelCodec = require(Shared.Assets.PixelCodec)
local AtlasCheck = require(Shared.Assets.AtlasCheck)
local meta = require(Shared.Assets.Atlases.SynVehicleArrow) :: any

local AtlasTestBoard = {}

local S = World.STUDS_PER_CELL
local FRAME_CELLS = 3 -- a 120 px frame drawn 3 cells (12 studs) wide on the board
local RING_CELLS = 11
local Y = 0.3

local function neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function sprite(parent: Instance, content: Content): (Part, ImageLabel)
	local quad = Instance.new("Part")
	quad.Anchored, quad.CanCollide, quad.CanQuery, quad.CanTouch, quad.CastShadow = true, false, false, false, false
	quad.Transparency = 1
	quad.Size = Vector3.new(FRAME_CELLS * S, 0.05, FRAME_CELLS * S)
	quad.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(meta.frameWidth, meta.frameHeight)
	gui.LightInfluence = 0
	gui.Parent = quad
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ImageContent = content
	label.ImageRectSize = Vector2.new(meta.frameWidth, meta.frameHeight)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.Parent = gui
	return quad, label
end

local function setFrame(label: ImageLabel, direction: number)
	local _, x, y = Facing.rect(meta, "idle", 0, direction)
	label.ImageRectOffset = Vector2.new(x, y)
end

function AtlasTestBoard.start(center: Vector2) -- center in map cells
	if not RunService:IsStudio() then
		return
	end
	local page = meta.pages[1]
	local dev = require(script.Parent.Parent.DevAssets:WaitForChild(page.devPixels)) :: any
	local pixels = PixelCodec.decode(MapCodec.base64Decode(dev.rle), dev.width, dev.height)
	local size = Vector2.new(dev.width, dev.height)
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = size })
	end)
	if not ok or not image then
		warn("[AtlasTestBoard] EditableImage unavailable, sprite board skipped:", image)
		return
	end
	local editable = image :: EditableImage
	editable:WritePixelsBuffer(Vector2.zero, size, pixels)

	-- Automatic check on what Roblox actually stores, not on our input buffer.
	local readBack = editable:ReadPixelsBuffer(Vector2.zero, size)
	local identical = buffer.len(readBack) == buffer.len(pixels) and buffer.tostring(readBack) == buffer.tostring(pixels)
	local result = AtlasCheck.run(readBack, dev.width, meta, true)
	print(`[AtlasTestBoard] read-back identical to packed atlas: {identical}; frame checks: {result.ok and "PASS" or "FAIL"} (worst arrow error {string.format("%.2f", result.worstDegrees)} deg, partial alpha {result.partialAlpha})`)
	for _, f in result.failures do
		warn("[AtlasTestBoard] " .. f)
	end

	local content = Content.fromObject(editable)
	local folder = Instance.new("Folder")
	folder.Name = "AtlasTestBoard"
	folder.Parent = workspace

	local guiYaw = -World.TOP_GUI_YAW -- quads are turned by -guiYaw = TOP_GUI_YAW; G adds quarter turns
	local ring: { { quad: Part, pos: Vector3, angle: number } } = {}
	local cx, cy = center.X, center.Y
	local origin = World.toWorld(cx, cy, Y)
	for d = 0, meta.directions - 1 do
		local angle = d * 2 * math.pi / meta.directions
		local x, y = cx + math.cos(angle) * RING_CELLS, cy + math.sin(angle) * RING_CELLS
		local pos = World.toWorld(x, y, Y)
		local quad, label = sprite(folder, content)
		setFrame(label, Facing.index(angle, meta.directions))
		-- reference line from the ring centre outward through the sprite, and the pivot dot
		local tip = World.toWorld(cx + math.cos(angle) * (RING_CELLS + 2.2), cy + math.sin(angle) * (RING_CELLS + 2.2), 0.1)
		local base = World.toWorld(cx, cy, 0.1)
		local from = base + (tip - base).Unit * 4
		neon(folder, Vector3.new(0.4, 0.05, (tip - from).Magnitude), CFrame.lookAt((from + tip) / 2, tip), Color3.new(1, 1, 1))
		neon(folder, Vector3.new(0.1, 1.2, 1.2), CFrame.new(pos - Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 230, 0), Enum.PartType.Cylinder)
		table.insert(ring, { quad = quad, pos = pos, angle = angle })
	end

	local spinner, spinLabel = sprite(folder, content)
	local needle = neon(folder, Vector3.new(0.4, 0.05, 2.6 * S), CFrame.new(origin), Color3.fromRGB(255, 230, 0))
	local useResidual = true
	local heading = 0

	local function placeAll()
		for _, r in ring do
			r.quad.CFrame = CFrame.new(r.pos) * CFrame.Angles(0, -(guiYaw), 0)
		end
	end
	placeAll()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			useResidual = not useResidual
			print(`[AtlasTestBoard] residual rotation {useResidual and "on" or "off (16-step snapping)"}`)
		elseif input.KeyCode == Enum.KeyCode.G then
			guiYaw = (guiYaw + math.pi / 2) % (2 * math.pi)
			placeAll()
			print(`[AtlasTestBoard] SurfaceGui compensation now {math.deg(guiYaw)} deg`)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		heading = (heading + dt * math.rad(20)) % (2 * math.pi)
		local d = Facing.index(heading, meta.directions)
		setFrame(spinLabel, d)
		local residual = if useResidual then Facing.residual(heading, d, meta.directions) else 0
		spinner.CFrame = CFrame.new(origin) * CFrame.Angles(0, -(residual + guiYaw), 0)
		local dir = Vector3.new(math.cos(heading), 0, math.sin(heading))
		needle.CFrame = CFrame.lookAt(origin + dir * 1.3 * S - Vector3.new(0, 0.2, 0), origin + dir * 3 * S - Vector3.new(0, 0.2, 0))
	end)
	print("[AtlasTestBoard] ready, 16 sprites north of your start. R residual on/off, G GUI compensation. See docs/STUDIO_TESTS.md test 6.")
end

return AtlasTestBoard
