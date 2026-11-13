--!strict
-- Soldier shape rows: full/half rims and full/half shadows, from the game's jht/XF/Kht/T8.
-- Lazy cropped atlases share SpriteBank camera residency, zoom tiers and complete-image swaps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenShadows = require(Shared.Presentation.MenShadows)
local Facing = require(Shared.Assets.Facing)
local World = require(Shared.Config.World)
local ManEffects = {}
local Bank=require(script.Parent.SpriteBank)
local config:any=nil
local tried=false
local function page(kind:string):any
	if not tried then
		tried=true;local data=Shared:FindFirstChild("GameData");local source=data and data:FindFirstChild("MenFx")
		if source then local ok,value=pcall(require,source);if ok then config=value end end
	end
	if not config then return nil end
	return Bank.cropped("OrigMen"..kind:sub(1,1):upper()..kind:sub(2).."Fx")
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

local function crop(image: ImageLabel, rect: { number }?,atlas:any,key:string)
	if not rect then image.Visible=false;return end
	image.Visible = true
	Bank.bindCrop(image,atlas,key,rect)
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
		crop(handle.rim, poses[if half then "rimHalf" else "rim"][facing + 1],handle.atlas,pose..":"..(if half then "rimHalf"else "rim")..":"..(facing+1))
		crop(handle.shade, poses[if half then "shadeHalf" else "shade"][facing + 1],handle.atlas,pose..":"..(if half then "shadeHalf"else "shade")..":"..(facing+1))
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

return ManEffects
