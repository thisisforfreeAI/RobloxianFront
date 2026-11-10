--!strict
-- Local particle atlas + shared death presentation state. Atlas loads on the first visible death,
-- using one 96px EditableImage; vehicle art stays lazy. DeathFx/OrigDeathFx are generated privately.
-- APPROX: flat projected quads replace Pixi's additive/dithered passes. See PROJECT_STATUS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ImageMemory = require(script.Parent.ImageMemory)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathEffects = require(Shared.Presentation.DeathEffects)
local MapCodec = require(Shared.Maps.MapCodec)
local PixelCodec = require(Shared.Assets.PixelCodec)
local World = require(Shared.Config.World)
local Fog = require(script.Parent.FogOverlay)
local DeathRenderer = {}
local engine: any = nil
local content: Content? = nil
local atlasImage: EditableImage? = nil -- keep the image alive alongside its Content
local frame = 24
local tried = false
local slots: { any } = {}
local root: Folder? = nil
local FRAMES = { disc = { 1, 0 }, ring = { 2, 0 }, star = { 3, 0 }, spark = { 0, 1 }, chunk = { 1, 1 }, shard = { 2, 1 },
	puffA = { 3, 1 }, puffB = { 0, 2 }, puffC = { 1, 2 }, blobA = { 2, 2 }, blobB = { 3, 2 }, blobC = { 0, 3 }, glint = { 2, 3 } }
-- Convoys and demolition trucks have separate effect routines in the game, pending their own port.
-- Do not give either the generic light-vehicle variants just because both leave a death snapshot.
local SUPPORTED = { tank = true, ifv = true, artillery = true, rocket = true, scout = true, engineer = true, command = true }

local function load(): boolean
	if tried then return engine ~= nil end
	tried = true
	local data = Shared:FindFirstChild("GameData")
	local config = data and data:FindFirstChild("DeathFx")
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local pixels = assets and assets:FindFirstChild("OrigDeathFx")
	if not config or not pixels then
		warn("[DeathRenderer] Generate local death effects with tools/conversion/export_death_fx.cjs; wrecks still draw")
		return false
	end
	local ok, err = pcall(function()
		local meta = require(pixels :: ModuleScript) :: any
		local image = ImageMemory.create(Vector2.new(meta.width, meta.height))
		assert(image, "EditableImage budget refused particle atlas")
		atlasImage = image
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(meta.width, meta.height), PixelCodec.decode(MapCodec.base64Decode(meta.rle), meta.width, meta.height))
		content, frame = Content.fromObject(image), meta.frame
		engine = DeathEffects.new(require(config :: ModuleScript))
	end)
	if not ok then
		if atlasImage then ImageMemory.release(atlasImage); atlasImage = nil end
		content, engine = nil, nil
		warn("[DeathRenderer] Death effects unavailable; wrecks still draw:", err)
	end
	return engine ~= nil
end

function DeathRenderer.kill(kind: string, x: number, y: number): any
	if not SUPPORTED[kind] or Fog.hidden(x, y) or not load() then return nil end
	return engine:kill(kind, x, y)
end

local function slot(i: number): any
	if slots[i] then return slots[i] end
	if not root then root = Instance.new("Folder"); root.Name = "WarFrontDeathEffects"; root.Parent = workspace end
	local p = Instance.new("Part")
	p.Name = "DeathParticle"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Parent = root
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(frame, frame)
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ImageContent = content :: Content
	label.ImageRectSize = Vector2.new(frame, frame)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.Parent = gui
	local s = { part = p, gui = gui, image = label }
	slots[i] = s
	return s
end

function DeathRenderer.step(dt: number)
	if not engine then return end
	engine:step(dt)
	local used = 0
	local scale = World.STUDS_PER_CELL
	local camera = workspace.CurrentCamera
	for _, p in engine.particles do
		-- Test the source and current cell; a plume crossing the fog edge must not reveal a death.
		if Fog.hidden(p.x0, p.y0) or Fog.hidden(p.x, p.y) then continue end
		local pos = World.toWorld(p.x, p.y - p.h * math.cos(math.rad(62)), 0.55)
		local size = p.drawSize * scale
		if camera then
			local screen = camera:WorldToViewportPoint(pos)
			if screen.Z <= 0 then continue end
			local pad = size * p.len * camera.ViewportSize.Y / math.max(1, 2 * screen.Z * math.tan(math.rad(camera.FieldOfView) / 2))
			if screen.X < -pad or screen.Y < -pad or screen.X > camera.ViewportSize.X + pad or screen.Y > camera.ViewportSize.Y + pad then continue end
		end
		used += 1
		local s = slot(used)
		local cr = FRAMES[p.tex] or FRAMES.disc
		s.gui.Enabled = true
		s.image.ImageRectOffset = Vector2.new(cr[1] * frame, cr[2] * frame)
		s.image.ImageTransparency = 1 - math.clamp(p.alpha, 0, 1)
		s.image.ImageColor3 = Color3.fromRGB(bit32.extract(p.tint, 16, 8), bit32.extract(p.tint, 8, 8), bit32.extract(p.tint, 0, 8))
		s.part.Size = Vector3.new(size, 0.01, size * p.len) -- Top GUI x runs along local -Z
		s.part.CFrame = CFrame.new(pos + Vector3.new(0, used * 0.0001, 0)) * CFrame.Angles(0, World.TOP_GUI_YAW - p.rot, 0)
	end
	for i = used + 1, #slots do slots[i].gui.Enabled = false end
end

return DeathRenderer
