--!strict
-- Soldier shape rows: full/half rims and full/half shadows, from the game's jht/XF/Kht/T8.
-- Separate from SpriteBank so this does not change its preload/lazy-loading policy.
-- One cropped atlas per figure is loaded only when that figure is first drawn.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ImageMemory = require(script.Parent.ImageMemory)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenShadows = require(Shared.Presentation.MenShadows)
local MapCodec = require(Shared.Maps.MapCodec)
local PixelCodec = require(Shared.Assets.PixelCodec)
local Facing = require(Shared.Assets.Facing)
local World = require(Shared.Config.World)
local ManEffects = {}
local warned: { [string]: boolean } = {}
local pages: { [string]: any } = {}
local config: any = nil
local tried = false

local function page(kind: string): any
	if pages[kind] ~= nil then
		if pages[kind] then pages[kind].at = os.clock() end
		return pages[kind] or nil
	end
	pages[kind] = false
	if not tried then
		tried = true
		local data = Shared:FindFirstChild("GameData")
		local mod = data and data:FindFirstChild("MenFx")
		if mod then
			local ok, value = pcall(require, mod :: ModuleScript)
			if ok then config = value else warn("[ManEffects] Local MenFx configuration could not load:", value) end
		end
	end
	if not config then return nil end -- older local assets retain their existing body/paint drawing
	local folder = script.Parent.Parent:FindFirstChild("DevAssets")
	local name = "OrigMen" .. string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2) .. "Fx"
	local mod = folder and folder:FindFirstChild(name)
	if not mod then return nil end
	local image: EditableImage? = nil
	local ok, value = pcall(function()
		local meta = require(mod :: ModuleScript) :: any
		local size = Vector2.new(meta.width, meta.height)
		local created = ImageMemory.create(size,"detail") -- Optional figure rims/shadows preserve terrain coverage.
		assert(created, "EditableImage budget refused figure masks")
		image = created
		created:WritePixelsBuffer(Vector2.zero, size, PixelCodec.decode(MapCodec.base64Decode(meta.rle), meta.width, meta.height))
		return { image = created, content = Content.fromObject(created), meta = meta, at = os.clock() }
	end)
	if not ok then
		ImageMemory.release(image)
		if not warned[kind] then warned[kind] = true; warn(`[ManEffects] {kind} masks unavailable; its body still draws:`, value) end
		return nil
	end
	pages[kind] = value
	return value
end

local function label(parent: Instance, content: Content, smooth: boolean): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.ImageContent = content
	image.ResampleMode = if smooth then Enum.ResamplerMode.Default else Enum.ResamplerMode.Pixelated
	image.Visible = false
	image.Parent = parent
	return image
end

local function crop(image: ImageLabel, rect: { number }?)
	if not rect or rect[3] <= 0 or rect[4] <= 0 then image.Visible = false; return end
	image.Visible = true
	image.ImageRectOffset = Vector2.new(rect[1], rect[2])
	image.ImageRectSize = Vector2.new(rect[3], rect[4])
	-- rect: atlas x/y, cropped w/h, offset inside original facing frame x/y, original frame size.
	image.Size = UDim2.fromScale(rect[3] / rect[7], rect[4] / rect[7])
	image.Position = UDim2.fromScale(rect[5] / rect[7], rect[6] / rect[7])
end

function ManEffects.attach(quad: Part, gui: SurfaceGui, body: ImageLabel, paint: ImageLabel, kind: string): any
	local atlas = page(kind)
	if not atlas then return nil end
	local rim = label(gui, atlas.content, false)
	rim.Name, rim.ZIndex = "ManRim", 1
	body.ZIndex, paint.ZIndex = 2, 3
	-- Ownership follows the body Part. Every existing worker/casualty destruction path destroys its
	-- shadow too, and Roblox disconnects these instance signals when the owning instances are destroyed.
	local shadow = Instance.new("Part")
	shadow.Name = "ManShadow"
	shadow.Anchored, shadow.CanCollide, shadow.CanQuery, shadow.CanTouch, shadow.CastShadow = true, false, false, false, false
	shadow.Transparency = 1
	shadow.Parent = quad
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(config.frame, config.frame)
	sg.LightInfluence, sg.Enabled = 0, false
	sg.Parent = shadow
	local turn = Instance.new("Frame")
	turn.BackgroundTransparency = 1
	turn.Size = UDim2.fromScale(1, 1)
	turn.Parent = sg
	local shade = label(turn, atlas.content, true)
	local handle = { kind = kind, atlas = atlas, rim = rim, shadow = shadow, gui = sg, turn = turn, shade = shade,
		body = body, ready = false, pose = "", facing = -1, half = false, shadowFade = 1 }
	local function alpha()
		local a = 1 - body.ImageTransparency
		rim.ImageTransparency = 1 - a * config.rim.alpha
		shade.ImageTransparency = 1 - a * config.shadow.alpha * handle.shadowFade
	end
	alpha()
	body:GetPropertyChangedSignal("ImageTransparency"):Connect(alpha)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function() sg.Enabled = gui.Enabled and handle.ready end)
	return handle
end

function ManEffects.place(handle: any, pose: string, heading: number, facing: number, x: number, y: number, height: number, size: number, frameCells: number, sunX: number, sunY: number, shadowFade: number?)
	if not handle then return end
	handle.shadowFade = shadowFade or 1
	handle.shade.ImageTransparency = 1 - (1 - handle.body.ImageTransparency) * config.shadow.alpha * handle.shadowFade
	local poses = handle.atlas.meta.poses[pose]
	if not poses then
		handle.rim.Visible, handle.gui.Enabled, handle.ready = false, false, false
		return
	end
	local scale, camera = World.STUDS_PER_CELL, workspace.CurrentCamera
	local width = frameCells * scale
	local pixels = math.huge
	if camera then
		local distance = (camera.CFrame.Position - World.toWorld(x, y, height)).Magnitude
		pixels = width * camera.ViewportSize.Y / math.max(1e-3, 2 * distance * math.tan(math.rad(camera.FieldOfView) / 2))
	end
	local half = pixels < config.frame * config.halfBelow
	if not handle.ready or handle.pose ~= pose or handle.facing ~= facing or handle.half ~= half then
		crop(handle.rim, poses[if half then "rimHalf" else "rim"][facing + 1])
		crop(handle.shade, poses[if half then "shadeHalf" else "shade"][facing + 1])
		handle.pose, handle.facing, handle.half = pose, facing, half
	end
	local dx, dy, axis, stretch = MenShadows.project(config, handle.kind, pose, heading, size, sunX, sunY)
	-- R(axis) * S(stretch,1) * R(residual-axis): apply shadow stretch in the sun direction,
	-- preserving the facing's rotation. Rotate a full-frame container so a cropped sprite still
	-- turns about the original frame centre rather than its trimmed rectangle's centre.
	handle.shadow.Size = Vector3.new(width, 0.01, width * stretch)
	handle.shadow.CFrame = CFrame.new(World.toWorld(x + dx, y + dy, height - 0.03)) * CFrame.Angles(0, World.TOP_GUI_YAW - axis, 0)
	handle.turn.Rotation = math.deg(Facing.residual(heading, facing, config.facings) - axis)
	handle.ready, handle.gui.Enabled = true, true
end

ImageMemory.register(20, function(needed: number, protected: any)
	local before = ImageMemory.stats()
	for kind, p in pages do
		if p and not protected[p.content] and os.clock() - p.at >= 1 then
			pages[kind] = nil
			ImageMemory.release(p.image)
			local used = ImageMemory.stats()
			if before - used >= needed then break end
		end
	end
end)
ImageMemory.onRelease(function()
	for kind, value in pages do if value == false then pages[kind] = nil end end
end)

return ManEffects
