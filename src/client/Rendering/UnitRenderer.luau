--!strict
--[[
	UnitRenderer: draws units from server snapshots and interpolates between them.
	Tanks, trucks, scout cars, artillery and infantry draw the game's own sprites when the local art
	modules are present (SpriteBank): 16 facings, the paint layer tinted with the side colour, the rest
	of the heading turning the quad. Other kinds, or a clone without the art, keep the PLACEHOLDER shapes
	(TEMP-003): a flat body in the side colour plus a nose showing heading. Sizes follow WarFront's
	sprite footprints in cells (units-top atlas "cells" values).
	Infantry squads draw each soldier on his own (the leader and two riflemen from the men sheet),
	placed and posed by SquadMen as the game does.
	Round each sprite unit, as the game's unit drawer (S9) does, bottom to top: a soft glow in the side
	colour (its halo: 1.7 sizes wide, 0.7 as deep, alpha 0.6, hidden while selected), the shadow (the
	shape row at 1/3 size, alpha 0.34, the turret's x 0.55, pushed and stretched away from the sun by
	its Of), the dark rim (alpha 0.78; the 6 px one when the unit is drawn under 0.6 x the 120 px frame),
	the body, the turret's shadow on the hull (alpha 0.42, 0.035 sizes toward the shade), the turret.
	APPROX: one fixed noon sun, as the town bake (the game turns it through its day and fades shadows
	at night); the shadow's stretch is applied after the facing's small leftover turn rather than
	between two turns (within 11 degrees, a hair of shear).
]]
local AssetService = game:GetService("AssetService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Facing = require(Shared.Assets.Facing)
local SpriteBank = require(script.Parent.SpriteBank)
local FogOverlay = require(script.Parent.FogOverlay)
local Hash = require(Shared.Utilities.Hash)
local SquadMen = require(script.Parent.SquadMen)
local DeathRenderer = require(script.Parent.DeathRenderer)

local UnitRenderer = {}

local S = World.STUDS_PER_CELL
local SNAPSHOT_SEC = 0.1 -- server sends 10 snapshots/s
local FOOTPRINT = { infantry = 0.78, at = 0.78, mortar = 0.78, para = 0.78, tank = 1, ifv = 0.95, artillery = 1.4, rocket = 1.3, scout = 0.62, engineer = 0.8, command = 1, demo = 1.2, truck = 0.7 }
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }
local GUI_YAW = -World.TOP_GUI_YAW -- a Top-face SurfaceGui needs this turn to line up with the map
local SPRITE_Y = -0.05 -- sprite quads sit just under the unit's anchor height

export type Sprite = { quad: Part, colour: ImageLabel, paint: ImageLabel, y0c: number, y0p: number, rise: number, facing: number, turret: boolean, soot: ImageLabel?, y0s: number, sootSheet: SpriteBank.Soot? }

-- a rim, shadow or turret-shadow quad (one image, no paint)
export type Fx = { quad: Part, gui: SurfaceGui, image: ImageLabel, kind: string, layer: string, sheet: SpriteBank.FxSheet?, y0: number, facing: number }

export type ManSprite = { quad: Part, gui: SurfaceGui, colour: ImageLabel, paint: ImageLabel, fig: SpriteBank.Figure, pose: string, facing: number }

export type View = {
	id: number,
	kind: string,
	side: number,
	model: Model,
	body: Part,
	ring: Part,
	bar: Frame,
	barGui: BillboardGui,
	status: TextLabel,
	from: Vector3,
	to: Vector3,
	fromYaw: number,
	toYaw: number,
	t: number,
	seen: number,
	look: SpriteBank.Look?,
	sprites: { Sprite },
	facing: number,
	squad: SquadMen.Squad?,
	men: { ManSprite },
	hpFrac: number,
	flags: number,
	aimX: number,
	aimY: number,
	inTrench: boolean,
	statusCode: number, -- the unit row's status (u[9])
	sinceShot: number,
	tube: ManSprite?,
	empty: boolean,
	turretWant: number, -- the sim's turret angle (latest snapshot)
	turretAt: number?, -- the drawn one, easing after it
	fx: { Fx },
	halo: Part?,
	selected: boolean,
	base: SpriteBank.Look?, -- the kind's plain look; look is the one shown (a deploy stage)
	stageWant: number, -- the server's stage (u[17])
	stage: number,
	mast: number, -- the scout's mast, 0 down to 1 up, eased here as the game does
	sooted: boolean, -- soot labels made (or tried: no art)
	atWork: number, -- seconds an engineer has stood at its job
	hands: { Hand }?, -- its workers, out of the truck
}

-- a worker out of an engineer truck, or a man running from a wreck (the game's hands and crews)
export type Hand = { kind: string, x: number, y: number, heading: number, walked: number, tx: number, ty: number, at: number, there: boolean, ms: ManSprite }

local views: { [number]: View } = {}
local folder: Folder
local lastTick = 0

local function part(parent: Instance, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function spriteQuad(parent: Instance, look: SpriteBank.Look, layer: SpriteBank.Layer, color: Color3, rise: number): Sprite
	local quad = Instance.new("Part")
	quad.Name = "Sprite"
	quad.Anchored, quad.CanCollide, quad.CanQuery, quad.CanTouch, quad.CastShadow = true, false, false, false, false
	quad.Transparency = 1
	quad.Size = Vector3.new(look.cells * S, 0.05, look.cells * S)
	quad.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(look.frame, look.frame)
	gui.LightInfluence = 0
	gui.Parent = quad
	local function label(z: number): ImageLabel
		local l = Instance.new("ImageLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.ImageContent = layer.content
		l.ImageRectSize = Vector2.new(look.frame, look.frame)
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		l.ZIndex = z
		l.Parent = gui
		return l
	end
	local colour = label(1)
	local paint = label(2)
	paint.ImageColor3 = color -- multiply, as the game's paint pass
	return { quad = quad, colour = colour, paint = paint, y0c = layer.colour, y0p = layer.paint, rise = rise, facing = -1, turret = false, soot = nil, y0s = 0, sootSheet = nil }
end

-- the game's za and its noon sun
local SUN = Vector2.new(0, 1 / (0.35 + 1)) -- Hb at phase 0.31: toward (0, -1), shadow = -toward / (shadowFloor + elevation 1)
local SHADOW = { alpha = 0.34, gun = 0.55, maxReach = 2 } -- za.shadow, t2.maxReach
local RIM_ALPHA = 0.78 -- za.rim.alpha
local HALF_BELOW = 0.6 * 120 -- za.halfBelow x fa.frame: drawn smaller than this (px), the half rim
local TURRET_SHADOW = { alpha = 0.42, reach = 0.035 } -- za.turretShadow
local HALO = { share = 1.7, alpha = 0.6, flat = 0.7 } -- za.halo

local function fxQuad(parent: Instance, sheet: SpriteBank.FxSheet, kind: string, layer: string, smooth: boolean, alpha: number): Fx
	local quad = Instance.new("Part")
	quad.Name = "Fx_" .. kind
	quad.Anchored, quad.CanCollide, quad.CanQuery, quad.CanTouch, quad.CastShadow = true, false, false, false, false
	quad.Transparency = 1
	quad.Size = Vector3.new(S, 0.05, S)
	quad.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(sheet.frame, sheet.frame)
	gui.LightInfluence = 0
	gui.Parent = quad
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ImageContent = sheet.content
	image.ImageRectSize = Vector2.new(sheet.frame, sheet.frame)
	image.ResampleMode = if smooth then Enum.ResamplerMode.Default else Enum.ResamplerMode.Pixelated
	image.ImageTransparency = 1 - alpha
	image.Parent = gui
	return { quad = quad, gui = gui, image = image, kind = kind, layer = layer, sheet = nil, y0 = -1, facing = -1 }
end

-- the game's xke: the side colour out to 0.55 of the radius, fading to nothing at the edge, times a
-- falloff from 1 to 0.85 at half the radius and 0 at the edge. White here; ImageColor3 tints it.
local haloImage: Content? = nil
local function haloContent(): Content
	if haloImage then
		return haloImage
	end
	local n = 64
	local buf = buffer.create(n * n * 4)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local r = math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2)
			local a1 = if r <= 0.55 then 1 elseif r >= 1 then 0 else 1 - (r - 0.55) / 0.45
			local a2 = if r <= 0.5 then 1 - 0.15 * r / 0.5 elseif r >= 1 then 0 else 0.85 * (1 - (r - 0.5) / 0.5)
			local o = (y * n + x) * 4
			buffer.writeu8(buf, o, 255)
			buffer.writeu8(buf, o + 1, 255)
			buffer.writeu8(buf, o + 2, 255)
			buffer.writeu8(buf, o + 3, math.floor(a1 * a2 * 255 + 0.5))
		end
	end
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(n, n) })
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), buf)
	haloImage = Content.fromObject(image)
	return haloImage :: Content
end

local function haloQuad(parent: Instance, look: SpriteBank.Look, color: Color3): Part
	local d = look.size * HALO.share * S
	local quad = Instance.new("Part")
	quad.Name = "Halo"
	quad.Anchored, quad.CanCollide, quad.CanQuery, quad.CanTouch, quad.CastShadow = true, false, false, false, false
	quad.Transparency = 1
	quad.Size = Vector3.new(d * HALO.flat, 0.05, d) -- local X runs north-south once turned (as the ground)
	quad.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(64, 64)
	gui.LightInfluence = 0
	gui.Parent = quad
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	local ok = pcall(function()
		image.ImageContent = haloContent()
	end)
	image.Visible = ok
	image.ImageColor3 = color
	image.ImageTransparency = 1 - HALO.alpha
	image.Parent = gui
	return quad
end

local function manQuad(parent: Instance, fig: SpriteBank.Figure, color: Color3): ManSprite
	local quad = Instance.new("Part")
	quad.Name = "Man"
	quad.Anchored, quad.CanCollide, quad.CanQuery, quad.CanTouch, quad.CastShadow = true, false, false, false, false
	quad.Transparency = 1
	quad.Size = Vector3.new(SquadMen.FRAME_CELLS * S, 0.05, SquadMen.FRAME_CELLS * S)
	quad.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(fig.frame, fig.frame)
	gui.LightInfluence = 0
	gui.Parent = quad
	local function label(z: number): ImageLabel
		local l = Instance.new("ImageLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.ImageContent = fig.content
		l.ImageRectSize = Vector2.new(fig.frame, fig.frame)
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		l.ZIndex = z
		l.Parent = gui
		return l
	end
	local colour = label(1)
	local paint = label(2)
	paint.ImageColor3 = color
	return { quad = quad, gui = gui, colour = colour, paint = paint, fig = fig, pose = "", facing = -1 }
end

local function create(id: number, kind: string, side: number): View
	local cells = FOOTPRINT[kind] or 0.8
	local model = Instance.new("Model")
	model.Name = `Unit{id}`
	local color = SIDE_COLOR[side] or Color3.new(0.7, 0.7, 0.7)
	local body = part(model, Vector3.new(cells * S, 0.6, cells * S * 0.6), color)
	local nose = part(model, Vector3.new(cells * S * 0.3, 0.7, cells * S * 0.25), color:Lerp(Color3.new(1, 1, 1), 0.5))
	nose.Name = "Nose"
	local ring = part(model, Vector3.new(0.1, cells * S * 1.5, cells * S * 1.5), Color3.fromRGB(120, 255, 120))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	if kind == "truck" then
		body.Material = Enum.Material.Metal -- trucks: darker, so they read apart from combat units
		body.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	-- health bar, shown only when damaged
	local barGui = Instance.new("BillboardGui")
	barGui.Size = UDim2.fromOffset(28, 4)
	barGui.StudsOffsetWorldSpace = Vector3.new(0, 2, -cells * S * 0.6)
	barGui.AlwaysOnTop = true
	barGui.Enabled = false
	barGui.Adornee = body
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = barGui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(110, 220, 90)
	bar.BorderSizePixel = 0
	bar.Parent = back
	barGui.Parent = body
	-- status tag: RECON (scout deployed), PACKING / SETTING UP (artillery and mortars), INSIDE
	-- (garrison), REPAIR (engineer on a repair job)
	local tagGui = Instance.new("BillboardGui")
	tagGui.Size = UDim2.fromOffset(70, 12)
	tagGui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, cells * S * 0.7)
	tagGui.AlwaysOnTop = true
	tagGui.Adornee = body
	local status = Instance.new("TextLabel")
	status.Size = UDim2.fromScale(1, 1)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.fromRGB(255, 240, 170)
	status.TextStrokeTransparency = 0.3
	status.Font = Enum.Font.GothamBold
	status.TextSize = 9
	status.Text = ""
	status.Parent = tagGui
	tagGui.Parent = body
	-- a squad drawn man by man when the men sheet is present, else its icon sprite, else the block
	local men: { ManSprite } = {}
	local roster = SquadMen.ROSTER[kind]
	if roster then
		for _, name in roster do
			local fig = SpriteBank.figure(name)
			if not fig then
				table.clear(men)
				break
			end
			table.insert(men, manQuad(model, fig, color))
		end
	end
	local tube: ManSprite? = nil
	if #men > 0 and kind == "mortar" then
		local fig = SpriteBank.figure("tube")
		if fig then
			tube = manQuad(model, fig, color)
		end
	end
	local look = if #men > 0 then nil else SpriteBank.look(kind)
	local sprites: { Sprite } = {}
	if #men > 0 then
		body.Transparency = 1
		nose.Transparency = 1
	elseif look then
		body.Transparency = 1
		nose.Transparency = 1
		table.insert(sprites, spriteQuad(model, look, look.body, color, 0))
		if look.turret then
			local tq = spriteQuad(model, look, look.turret, color, 0.04)
			tq.turret = true
			table.insert(sprites, tq)
		end
	end
	local fx: { Fx } = {}
	local halo: Part? = nil
	if look then
		halo = haloQuad(model, look, color)
		local sheets = look.fx
		if sheets then
			local layers = if look.turret then { "body", "turret" } else { "body" }
			for _, layer in layers do
				if sheets.shade then
					table.insert(fx, fxQuad(model, sheets.shade, "shadow", layer, true, if layer == "turret" then SHADOW.alpha * SHADOW.gun else SHADOW.alpha))
				end
			end
			for _, layer in layers do
				table.insert(fx, fxQuad(model, sheets.rim, "rim", layer, false, RIM_ALPHA))
			end
			if look.turret and sheets.rim.strips.turret_plain then
				table.insert(fx, fxQuad(model, sheets.rim, "plain", "turret", false, TURRET_SHADOW.alpha))
			end
		end
	end
	model.PrimaryPart = body
	model.Parent = folder
	return {
		id = id, kind = kind, side = side, model = model, body = body, ring = ring, bar = bar, barGui = barGui, status = status,
		from = Vector3.zero, to = Vector3.zero, fromYaw = 0, toYaw = 0, t = 1, seen = 0,
		look = look, sprites = sprites, facing = -1,
		squad = nil, men = men, hpFrac = 1, flags = 0, aimX = 0, aimY = 0, inTrench = false, statusCode = 0, sinceShot = 9, tube = tube, empty = false,
		turretWant = 0, turretAt = nil, fx = fx, halo = halo, selected = false,
		base = look, stageWant = 0, stage = 0, mast = 0, sooted = false, atWork = 0, hands = nil,
	}
end

-- where the turret turns: the hull's centre, or off it by the look's pivot (frames, along and across
-- the hull, as the game's S9)
local function turretAt(look: SpriteBank.Look, pos: Vector3, hull: number): Vector3
	local p = look.pivot
	if not p then
		return pos
	end
	local f = look.cells * S
	return pos + Vector3.new((p[1] * math.cos(hull) - p[2] * math.sin(hull)) * f, 0, (p[1] * math.sin(hull) + p[2] * math.cos(hull)) * f)
end

-- the game's Of: the shadow is pushed half its reach away from the sun and stretched along that line by
-- (l + reach) / l, l being how long the body lies along it
local function shadowOf(look: SpriteBank.Look, hull: number): (number, number, number)
	local a = SUN.Magnitude
	if a < 1e-6 then
		return 0, 0, 1
	end
	local r = look.size * look.tall * math.min(a, SHADOW.maxReach)
	local axis = math.atan2(SUN.Y, SUN.X)
	local l = math.max(0.001, math.abs(math.cos(hull - axis)) * look.size + math.abs(math.sin(hull - axis)) * look.size * look.artH)
	return SUN.X / a * r * 0.5, SUN.Y / a * r * 0.5, (l + r) / l
end

local function placeFx(v: View, look: SpriteBank.Look, pos: Vector3, hull: number, turret: number)
	local sheets = look.fx :: any
	-- how big the unit is on screen: the game swaps in the thicker half-size rim under 0.6 x the frame
	local cam = workspace.CurrentCamera
	local px = math.huge
	if cam then
		local dist = (cam.CFrame.Position - pos).Magnitude
		px = look.cells * S * cam.ViewportSize.Y / math.max(1e-3, 2 * dist * math.tan(math.rad(cam.FieldOfView) / 2))
	end
	local rimSheet = if px < HALF_BELOW and sheets.rimHalf then sheets.rimHalf else sheets.rim
	local sx, sy, stretch = shadowOf(look, hull)
	local W = look.cells * S
	local tpos = turretAt(look, pos, hull)
	for _, f in v.fx do
		local at = if f.layer == "turret" then tpos else pos
		if f.layer == "turret" and not look.turret then
			f.image.Visible = false -- a look without a turret (the HQ truck setting up)
			continue
		end
		local h = (if f.layer == "turret" then turret else hull) % (2 * math.pi)
		local d = Facing.index(h, 16)
		local residual = Facing.residual(h, d, 16)
		local sheet = if f.kind == "shadow" then sheets.shade elseif f.kind == "rim" then rimSheet else sheets.rim
		local base = if f.kind == "plain" then (look.turret :: SpriteBank.Layer).base .. "_plain"
			elseif f.layer == "turret" then (look.turret :: SpriteBank.Layer).base
			elseif v.empty and look.empty then look.empty.base
			else look.body.base
		local y0 = sheet.strips[base]
		if y0 == nil then
			f.image.Visible = false
			continue
		end
		f.image.Visible = true
		if sheet ~= f.sheet then
			f.sheet = sheet
			f.image.ImageContent = sheet.content
			f.image.ImageRectSize = Vector2.new(sheet.frame, sheet.frame)
			f.gui.CanvasSize = Vector2.new(sheet.frame, sheet.frame)
			f.facing = -1
		end
		if d ~= f.facing or y0 ~= f.y0 then
			f.facing, f.y0 = d, y0
			f.image.ImageRectOffset = SpriteBank.offset(sheet, y0, d)
		end
		if f.kind == "shadow" then
			-- squared to the ground, stretched along the sun's line (local X runs north-south), the
			-- facing's leftover turn done inside the canvas
			f.quad.Size = Vector3.new(W * stretch, 0.05, W)
			f.image.Rotation = math.deg(residual)
			local rise = if f.layer == "turret" then -0.025 else -0.03
			f.quad.CFrame = CFrame.new(at + Vector3.new(sx * S, SPRITE_Y + rise, sy * S)) * CFrame.Angles(0, -GUI_YAW, 0)
		else
			f.quad.Size = Vector3.new(W, 0.05, W)
			local off = Vector3.zero
			local rise = -0.01
			if f.kind == "plain" then
				off = Vector3.new(SUN.X, 0, SUN.Y) * look.size * TURRET_SHADOW.reach * S
				rise = 0.02
			end
			f.quad.CFrame = CFrame.new(at + off + Vector3.new(0, SPRITE_Y + rise, 0)) * CFrame.Angles(0, -(residual + GUI_YAW), 0)
		end
	end
end

local MAST = { sec = 1.5, stages = { 0.35, 0.95 } } -- Ai.mast.sec, Ai.stages.mast

-- show another look of the kind (a deploy stage) or the plain one again
local function setLook(v: View, look: SpriteBank.Look)
	v.look = look
	local body = v.sprites[1]
	if body then
		body.colour.ImageContent = look.body.content
		body.paint.ImageContent = look.body.content
		body.y0c, body.y0p = look.body.colour, look.body.paint
		body.facing = -1
	end
	for _, sp in v.sprites do
		if sp.turret then
			local gui = sp.quad:FindFirstChildOfClass("SurfaceGui")
			if gui then
				gui.Enabled = look.turret ~= nil
			end
		end
	end
	v.facing = -1
end

local function stageOf(t: number, list: { number }): number
	local o = 0
	while o < #list and t >= list[o + 1] do
		o += 1
	end
	return o
end

-- which look to show this frame: the server's stage, or for the scout its eased mast
local function updateStage(v: View, dt: number)
	local base = v.base
	if not base then
		return
	end
	local stage = v.stageWant
	if v.kind == "scout" then
		local want = if v.statusCode == 1 then 1 else 0
		v.mast += math.clamp(want - v.mast, -dt / MAST.sec, dt / MAST.sec)
		stage = stageOf(v.mast, MAST.stages)
	end
	if stage == v.stage then
		return
	end
	v.stage = stage
	local look = if stage > 0 then SpriteBank.state(v.kind, stage) or base else base
	if look ~= v.look then
		setLook(v, look)
	end
end

-- Soot, as the game's vehicle dress: s.soot = clamp((soot.from - hp/maxHp) / (soot.from - soot.full), 0, 1),
-- drawn as the paint rows of the kind's wreck look over the body (and turret) at that alpha
local SOOT = { from = 0.6, full = 0.15 } -- the game's vehicle soot settings

local function sootOf(v: View): number
	return math.clamp((SOOT.from - v.hpFrac) / (SOOT.from - SOOT.full), 0, 1)
end

-- made the first time the vehicle is hurt enough, so healthy units never load wreck art
local function addSoot(v: View)
	v.sooted = true
	local sheet = SpriteBank.soot(v.kind)
	if not sheet then
		return
	end
	for _, sp in v.sprites do
		local y0 = if sp.turret then sheet.turret else sheet.body
		local gui = sp.quad:FindFirstChildOfClass("SurfaceGui")
		if y0 == nil or not gui then
			continue
		end
		local l = Instance.new("ImageLabel")
		l.Name = "Soot"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.ImageContent = sheet.content
		l.ImageRectSize = Vector2.new(sheet.frame, sheet.frame)
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		l.ZIndex = 3
		l.Parent = gui
		sp.soot, sp.y0s, sp.sootSheet = l, y0, sheet
		sp.facing = -1
	end
	v.facing = -1
end

local TURRET_FOLLOW = 20 -- the game's za.turretFollowPerSec: the drawn turret eases after the sim's

local function place(v: View, pos: Vector3, yaw: number, dt: number)
	-- Rotating about Y by -heading turns local +X towards (cos h, 0, sin h): east = +X, south = +Z.
	local cf = CFrame.new(pos) * CFrame.Angles(0, -yaw, 0)
	v.body.CFrame = cf
	local nose = v.model:FindFirstChild("Nose") :: Part
	nose.CFrame = cf * CFrame.new(v.body.Size.X / 2, 0.05, 0)
	v.ring.CFrame = CFrame.new(pos - Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	updateStage(v, dt)
	local look = v.look
	if look then
		-- hull layers face the hull; the turret layer faces the turret (the sim turns it, the drawing eases after it)
		local tAt = v.turretAt
		local moving = (v.to - v.from).Magnitude > 1e-3 and v.t < 1
		if tAt == nil then
			tAt = v.turretWant
		elseif look.radarTurns and not moving then
			tAt += look.radarTurns * 2 * math.pi * dt -- the HQ truck's mast turns on its own while it stands
		else
			local d = (v.turretWant - tAt + math.pi) % (2 * math.pi) - math.pi
			tAt += d * (1 - math.exp(-TURRET_FOLLOW * dt))
		end
		v.turretAt = tAt
		local hullH = yaw % (2 * math.pi)
		local turretH = (tAt :: number) % (2 * math.pi)
		local tpos = turretAt(look, pos, yaw)
		local soot = sootOf(v)
		if soot > 0 and not v.sooted then
			addSoot(v)
		end
		for _, sp in v.sprites do
			local h = if sp.turret then turretH else hullH
			local d = Facing.index(h, 16)
			local sl = sp.soot
			if d ~= sp.facing or v.facing == -1 then
				sp.facing = d
				sp.colour.ImageRectOffset = SpriteBank.offset(look, sp.y0c, d)
				sp.paint.ImageRectOffset = SpriteBank.offset(look, sp.y0p, d)
				if sl then
					sl.ImageRectOffset = SpriteBank.offset(sp.sootSheet :: SpriteBank.Soot, sp.y0s, d)
				end
			end
			if sl then
				sl.Visible = soot > 0
				sl.ImageTransparency = 1 - soot
			end
			local residual = Facing.residual(h, d, 16)
			sp.quad.CFrame = CFrame.new((if sp.turret then tpos else pos) + Vector3.new(0, SPRITE_Y + sp.rise, 0)) * CFrame.Angles(0, -(residual + GUI_YAW), 0)
		end
		v.facing = 0
		local halo = v.halo
		if halo then
			halo.CFrame = CFrame.new(pos + Vector3.new(0, SPRITE_Y - 0.04, 0)) * CFrame.Angles(0, -GUI_YAW, 0)
		end
		if #v.fx > 0 then
			placeFx(v, look, pos, yaw, turretH)
		end
	end
end

local mortarSec = { setting = 1, packing = 1 } -- set by UnitRenderer.configure from the rules

local function setFigure(ms: ManSprite, pose: string, heading: number, x: number, y: number, height: number)
	local h = heading % (2 * math.pi)
	local d = Facing.index(h, 16)
	pose = if ms.fig.poses[pose] then pose elseif ms.fig.poses.stand then "stand" else next(ms.fig.poses) :: string
	if d ~= ms.facing or pose ~= ms.pose then
		ms.facing, ms.pose = d, pose
		local p = ms.fig.poses[pose]
		ms.colour.ImageRectOffset = SpriteBank.offset(ms.fig, p.colour, d)
		ms.paint.ImageRectOffset = SpriteBank.offset(ms.fig, p.paint, d)
	end
	ms.quad.CFrame = CFrame.new(World.toWorld(x, y, height)) * CFrame.Angles(0, -(Facing.residual(h, d, 16) + GUI_YAW), 0)
end

local function placeMen(v: View, pos: Vector3, dt: number)
	local vel = (v.to - v.from) / (SNAPSHOT_SEC * S)
	local phase: string? = nil
	if v.kind == "mortar" then
		phase = if v.statusCode == 3 then "setting" elseif v.statusCode == 2 then "packing" else "set"
	end
	local inp: SquadMen.Input = {
		x = pos.X / S, y = pos.Z / S, vx = vel.X, vy = vel.Z,
		hpFrac = v.hpFrac, firing = bit32.btest(v.flags, 1), aimX = v.aimX, aimY = v.aimY,
		road = bit32.btest(v.flags, 2), contact = bit32.btest(v.flags, 4), cover = v.inTrench,
		mortar = phase, phaseSec = if phase then mortarSec[phase] else nil, sinceShot = v.sinceShot + v.t * SNAPSHOT_SEC,
	}
	local sq = v.squad
	if not sq then
		sq = SquadMen.new(v.id, v.kind, inp)
		v.squad = sq
	end
	SquadMen.step(sq :: SquadMen.Squad, inp, dt)
	for i, m in (sq :: SquadMen.Squad).men do
		local ms = v.men[i]
		if not ms then
			continue
		end
		ms.gui.Enabled = m.up
		if not m.up then
			continue
		end
		setFigure(ms, m.pose, m.heading, m.x, m.y, pos.Y - World.GROUND_Y + SPRITE_Y)
	end
	local tube, at = v.tube, (sq :: SquadMen.Squad).tube
	if tube then
		tube.gui.Enabled = at ~= nil
		if at then
			setFigure(tube, at.pose, at.heading, at.x, at.y, pos.Y - World.GROUND_Y + SPRITE_Y - 0.02)
		end
	end
end

-- seconds a mortar takes to set up and to pack (rules mortar.setupSec, mortar.packSec)
function UnitRenderer.configure(cfg: { mortarSetupSec: number, mortarPackSec: number })
	mortarSec.setting, mortarSec.packing = cfg.mortarSetupSec, cfg.mortarPackSec
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

------------------------------------------------------------------------------------------------
-- Wrecks, as the game leaves them (its wMe.leave, paintWrecks and Mke): where a vehicle dies its
-- <kind>_wreck look stays for holdSec, then fades out over fadeSec; at most max of them (the oldest
-- go first); hidden under fog. The turret is knocked round by up to turretSpin and slid back off the
-- hull by up to turretSlide x the unit's cells, both from a hash of the spot (the game's kc). A tank
-- can instead lose its turret in a toss (the game picks a death look by weights per class): it flies
-- to 1.6-2.3 cells off over 1.25-1.6 s, up 2.8-3.8 and down, turning and flipping end over end, drawn
-- at the game's 12 frames a second, and lies where it lands. DeathRenderer shares the variant and
-- trajectory for its blast, fire, smoke and landing effects; workers bail out below.
------------------------------------------------------------------------------------------------
local WRECK = { holdSec = 120, fadeSec = 25, max = 48, turretSpin = 0.8, turretSlide = 0.08 } -- Ai.wreck
local TOSS = { reach = { 1.6, 2.3 }, sec = { 1.25, 1.6 }, height = { 2.8, 3.8 }, turn = { 5, 11 }, flips = { 1.5, 2.5 }, grow = 0.12 } -- Kv.variants.toss
local DEATH_WEIGHTS = { -- Kv.variants.weights, by the game's class (jmt)
	tank = { blast = 3, cook = 2, toss = 2, brew = 2, quiet = 1 },
	gun = { blast = 3, cook = 3, toss = 0, brew = 1, quiet = 1 },
	light = { blast = 5, cook = 0, toss = 0, brew = 1, quiet = 4 },
}
local DEATH_ORDER = { "blast", "cook", "toss", "brew", "quiet" }
local DEATH_CLASS = { tank = "tank", artillery = "gun" } -- others: light
local LIFT_COS = math.cos(math.rad(62)) -- the game's z3e: how a height shows on its tilted view
local TOSS_FPS = 12 -- the game's Oi
local TOSS_SHADOW_THROW = 0.35 -- za.shadow.airThrow

local kc = Hash.kc

type Wreck = {
	look: SpriteBank.Look, x: number, y: number, hull: number, turret: number, tx: number, ty: number, at: number,
	tossSec: number, tossHeight: number, tossTurn: number, tossFlips: number,
	model: Model, quads: { Fx }, shown: boolean,
}
local wrecks: { Wreck } = {}

local function between(r: { number }): number
	return r[1] + math.random() * (r[2] - r[1])
end

local function deathLook(kind: string): string
	local w = DEATH_WEIGHTS[DEATH_CLASS[kind] or "light"]
	local total = 0
	for _, k in DEATH_ORDER do
		total += w[k]
	end
	local n = math.random() * total
	for _, k in DEATH_ORDER do
		n -= w[k]
		if n < 0 and w[k] > 0 then
			return k
		end
	end
	return "blast"
end

local function leaveWreck(kind: string, x: number, y: number, hull: number, turret: number, death: any?)
	local look = SpriteBank.wreck(kind)
	if not look then
		return
	end
	if #wrecks >= WRECK.max then
		local old = table.remove(wrecks, 1) :: Wreck
		old.model:Destroy()
	end
	local h = math.floor(x * 97 + y * 131 + 0.5)
	local spin = (kc(h, 2) - 0.5) * 2 * WRECK.turretSpin
	local slide = kc(h, 3) * WRECK.turretSlide * look.size / 1.3
	local w: Wreck = {
		look = look, x = x, y = y, hull = hull, turret = turret + spin,
		tx = math.cos(turret + spin + math.pi) * slide, ty = math.sin(turret + spin + math.pi) * slide,
		at = os.clock(), tossSec = 0, tossHeight = 0, tossTurn = 0, tossFlips = 0,
		model = Instance.new("Model"), quads = {}, shown = true,
	}
	-- Without local effect data, retain the earlier wreck-only fallback.
	if look.turret and (if death then death.variant else deathLook(kind)) == "toss" then
		if death then
			w.tossTurn, w.turret = death.turn, turret + death.turn
			w.tx, w.ty = death.x / 1.3, death.y / 1.3
			w.tossSec, w.tossHeight, w.tossFlips = death.sec, death.height, death.flips
		else
			local a = math.random() * math.pi * 2
			local reach = between(TOSS.reach)
			w.tossTurn = between(TOSS.turn) * (if math.random() < 0.5 then -1 else 1)
			w.turret = turret + w.tossTurn
			w.tx, w.ty = math.cos(a) * reach / 1.3, math.sin(a) * reach / 1.3
			w.tossSec, w.tossHeight, w.tossFlips = between(TOSS.sec), between(TOSS.height), between(TOSS.flips)
		end
	end
	w.model.Name = "Wreck"
	local colourSheet: SpriteBank.FxSheet = { content = look.body.content, frame = look.frame, columns = look.columns, strips = {} }
	colourSheet.strips[look.body.base] = look.body.colour
	if look.turret then
		colourSheet.strips[look.turret.base] = look.turret.colour
	end
	local sheets = look.fx
	local layers = if look.turret then { "body", "turret" } else { "body" }
	for _, layer in layers do
		if sheets and sheets.shade then
			table.insert(w.quads, fxQuad(w.model, sheets.shade, "shadow", layer, true, if layer == "turret" then SHADOW.alpha * SHADOW.gun else SHADOW.alpha))
		end
	end
	for _, layer in layers do
		if sheets then
			table.insert(w.quads, fxQuad(w.model, sheets.rim, "rim", layer, false, RIM_ALPHA))
		end
	end
	table.insert(w.quads, fxQuad(w.model, colourSheet, "colour", "body", false, 1))
	if look.turret then
		if sheets and sheets.rim.strips[look.turret.base .. "_plain"] then
			table.insert(w.quads, fxQuad(w.model, sheets.rim, "plain", "turret", false, TURRET_SHADOW.alpha))
		end
		table.insert(w.quads, fxQuad(w.model, colourSheet, "colour", "turret", false, 1))
	end
	for _, q in w.quads do
		q.sheet = if q.kind == "colour" then colourSheet else nil
		q.image:SetAttribute("alpha", 1 - q.image.ImageTransparency)
	end
	w.model.Parent = folder
	table.insert(wrecks, w)
end

local RISE = { shadow = -0.03, rim = -0.01, colour = 0, plain = 0.02 }

local function placeWreck(w: Wreck, now: number): boolean
	local p = now - w.at
	local alpha = if p <= WRECK.holdSec then 1 else 1 - (p - WRECK.holdSec) / WRECK.fadeSec
	if alpha <= 0 then
		w.model:Destroy()
		return false
	end
	local hidden = FogOverlay.hidden(w.x, w.y)
	if hidden == w.shown then
		w.shown = not hidden
		w.model.Parent = if hidden then nil else folder
	end
	if hidden then
		return true
	end
	local look = w.look
	local sheets = look.fx :: any
	local pos = World.toWorld(w.x, w.y, 0.4)
	local W = look.cells * S
	local cam = workspace.CurrentCamera
	local px = math.huge
	if cam then
		local dist = (cam.CFrame.Position - pos).Magnitude
		px = W * cam.ViewportSize.Y / math.max(1e-3, 2 * dist * math.tan(math.rad(cam.FieldOfView) / 2))
	end
	local rimSheet = if sheets and px < HALF_BELOW and sheets.rimHalf then sheets.rimHalf elseif sheets then sheets.rim else nil
	local sx, sy, stretch = shadowOf(look, w.hull)
	-- the turret: slid or tossed off the hull
	local tossing = w.tossSec > 0 and p < w.tossSec
	local k, lift, flip, grow = 1, 0, 1, 1
	local tAng = w.turret
	if tossing then
		k = math.min(1, math.floor(math.max(0, p) * TOSS_FPS + 1e-6) / TOSS_FPS / w.tossSec)
		local up = 4 * w.tossHeight * k * (1 - k)
		tAng = w.turret - w.tossTurn * (1 - k)
		lift = up * LIFT_COS
		flip = math.max(0.3, math.abs(math.cos(math.pi * w.tossFlips * k)))
		grow = 1 + up * TOSS.grow
	end
	local tpos = pos + Vector3.new(w.tx * k * 1.3 * S, 0, w.ty * k * 1.3 * S)
	for _, f in w.quads do
		local turretLayer = f.layer == "turret"
		local ang = (if turretLayer then tAng else w.hull) % (2 * math.pi)
		local d = Facing.index(ang, 16)
		local residual = Facing.residual(ang, d, 16)
		local sheet: SpriteBank.FxSheet? = if f.kind == "colour" then f.sheet elseif f.kind == "shadow" then sheets.shade elseif f.kind == "rim" then rimSheet else sheets.rim
		local base = if turretLayer then (look.turret :: SpriteBank.Layer).base else look.body.base
		if f.kind == "plain" then
			base ..= "_plain"
		end
		local y0 = sheet and sheet.strips[base]
		if not sheet or y0 == nil or (f.kind == "plain" and tossing) then
			f.image.Visible = false
			continue
		end
		f.image.Visible = true
		if f.kind ~= "colour" and sheet ~= f.sheet then
			f.sheet = sheet
			f.image.ImageContent = sheet.content
			f.image.ImageRectSize = Vector2.new(sheet.frame, sheet.frame)
			f.gui.CanvasSize = Vector2.new(sheet.frame, sheet.frame)
			f.facing = -1
		end
		if d ~= f.facing or y0 ~= f.y0 then
			f.facing, f.y0 = d, y0
			f.image.ImageRectOffset = SpriteBank.offset(sheet, y0, d)
		end
		f.image.ImageTransparency = 1 - alpha * (f.image:GetAttribute("alpha") or 1)
		local at = if turretLayer then tpos else pos
		local rise = RISE[f.kind] + (if turretLayer then 0.005 else 0)
		if turretLayer and tossing then
			-- squashed along the barrel as it flips, grown as it rises: the quad turns with the turret and
			-- the frame turns back inside it, so the squash runs along the barrel
			local throw = if f.kind == "shadow" then Vector3.new(SUN.X, 0, SUN.Y) * lift * TOSS_SHADOW_THROW * S + Vector3.new(sx * S, 0, sy * S)
				else Vector3.new(0, 0, -lift * S)
			local g = if f.kind == "shadow" then 1 else grow -- the game grows the turret and its rim, not the shadow
			f.quad.Size = Vector3.new(W * g, 0.05, W * g * flip)
			f.image.Rotation = -d * 22.5
			f.quad.CFrame = CFrame.new(at + throw + Vector3.new(0, SPRITE_Y + rise + 0.05, 0)) * CFrame.Angles(0, -(ang + GUI_YAW), 0)
		elseif f.kind == "shadow" then
			f.quad.Size = Vector3.new(W * stretch, 0.05, W)
			f.image.Rotation = math.deg(residual)
			f.quad.CFrame = CFrame.new(at + Vector3.new(sx * S, SPRITE_Y + rise, sy * S)) * CFrame.Angles(0, -GUI_YAW, 0)
		else
			local off = if f.kind == "plain" then Vector3.new(SUN.X, 0, SUN.Y) * look.size * TURRET_SHADOW.reach * S else Vector3.zero
			f.quad.Size = Vector3.new(W, 0.05, W)
			f.image.Rotation = 0
			f.quad.CFrame = CFrame.new(at + off + Vector3.new(0, SPRITE_Y + rise, 0)) * CFrame.Angles(0, -(residual + GUI_YAW), 0)
		end
	end
	return true
end

------------------------------------------------------------------------------------------------
-- Workers and crews, as the game's wMe.work, knockedOut, bolt and drawCrews. An engineer truck that
-- has stood at its job (repair, sabotage, a trench) for atWorkSec puts out two men at its door, an
-- engineer and a sapper; they walk out to their spots outCells beyond the truck's side toward the job
-- and work there (the engineer digs, the sapper plants), facing the job. When the job ends they run
-- back and climb in. If the truck is destroyed they bolt: each runs 1.3-2.4 cells away from the wreck,
-- then stands, stays holdSec and fades out over fadeSec; hidden under fog. The game's crew count table
-- is empty, so no other vehicle puts out a crew; the loop for it is kept for when it is filled.
------------------------------------------------------------------------------------------------
local WORKERS = { outCells = 0.75, pace = 0.6, runPace = 1.4, digHz = 1.4, inCells = 0.15, lostCells = 3, atWorkSec = 0.6, door = { 0.19, 0.18 }, spots = { 0.12, -0.28 } } -- Ai.workers
local CREW = { count = {} :: { [string]: number }, runCells = { 1.3, 2.4 }, pace = 1.2, holdSec = 5, fadeSec = 3, max = 48, spread = 0.8, hatch = 0.12, veer = 0.6 } -- Ai.crew
local WALKS = { "walk0", "walk1", "walk2", "walk3" } -- the game's U3e
local STEP = 0.17 -- the game's qP: cells a walk frame lasts
local MAX_DT = 0.1 -- Ai.maxDt
local AT_WORK = { [5] = true, [6] = true, [10] = true, [11] = true, [12] = true } -- repair, sabotage, trench jobs
local MAN_RISE = 0.03

local crews: { Hand } = {}

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function newHand(parent: Instance, kind: string, color: Color3, x: number, y: number, heading: number, walked: number): Hand?
	local fig = SpriteBank.figure(kind)
	if not fig then
		return nil
	end
	return { kind = kind, x = x, y = y, heading = heading, walked = walked, tx = x, ty = y, at = os.clock(), there = false, ms = manQuad(parent, fig, color) }
end

local function dropHands(v: View)
	for _, h in v.hands or {} do
		h.ms.quad:Destroy()
	end
	v.hands = nil
end

-- the game's work(): x, y the truck in cells, hull its heading
local function work(v: View, x: number, y: number, hull: number, dt: number)
	dt = math.min(MAX_DT, math.max(0, dt))
	local moving = (v.to - v.from).Magnitude > 1e-3 and v.t < 1
	v.atWork = if AT_WORK[v.statusCode] and not moving then v.atWork + dt else 0
	local d, f = math.cos(hull), math.sin(hull)
	local p = FOOTPRINT[v.kind] or 0.8
	local gx = x + (d * WORKERS.door[1] - f * WORKERS.door[2]) * p
	local gy = y + (f * WORKERS.door[1] + d * WORKERS.door[2]) * p
	local out = v.atWork >= WORKERS.atWorkSec
	if out and not v.hands then
		local color = SIDE_COLOR[v.side] or Color3.new(0.7, 0.7, 0.7)
		local hands = {}
		for i, kind in { "engineer", "sapper" } do
			local h = newHand(v.model, kind, color, gx, gy, hull + math.pi / 2, (i - 1) * STEP * 2)
			if h then
				table.insert(hands, h)
			end
		end
		v.hands = if #hands > 0 then hands else nil
	end
	local hands = v.hands
	if not hands then
		return
	end
	-- the job: the server's aim point while the truck is not firing
	local jobX: number?, jobY: number? = nil, nil
	if not bit32.btest(v.flags, 1) and (v.aimX ~= 0 or v.aimY ~= 0) then
		jobX, jobY = v.aimX, v.aimY
	end
	local bx, by = -f, d
	if jobX and jobY then
		local s = math.sqrt((jobX - x) ^ 2 + (jobY - y) ^ 2)
		if s > 0.2 and s < 4 then
			bx, by = (jobX - x) / s, (jobY - y) / s
		end
	end
	local home = 0
	for i, h in hands do
		local spot = WORKERS.spots[i] or 0
		if out then
			h.tx = x + bx * (WORKERS.outCells + p * WORKERS.door[2]) + d * spot * p
			h.ty = y + by * (WORKERS.outCells + p * WORKERS.door[2]) + f * spot * p
		else
			h.tx, h.ty = gx, gy
		end
		local px, py = h.tx - h.x, h.ty - h.y
		local o = math.sqrt(px * px + py * py)
		local step = math.min(o, (if out then WORKERS.pace else WORKERS.runPace) * dt)
		if o > 1e-4 then
			h.x += px / o * step
			h.y += py / o * step
			h.walked += step
		end
		h.there = out and o - step < 0.03
		local want = if h.there then (if jobX and jobY then math.atan2(jobY - h.y, jobX - h.x) else math.atan2(by, bx))
			elseif o > 0.001 then math.atan2(py, px)
			else h.heading
		h.heading = wrapAngle(h.heading + wrapAngle(want - h.heading) * (1 - math.exp(-10 * dt)))
		if not out and (o < WORKERS.inCells or o > WORKERS.lostCells) then
			home += 1
		end
	end
	if home == #hands then
		dropHands(v)
		return
	end
	local now = os.clock()
	for _, h in hands do
		local pose = if h.there
			then (if h.kind == "engineer" then (if math.floor(now * WORKERS.digHz * 2 + kc(v.id, 14) * 2) % 2 == 1 then "dig1" else "dig0") else "plant")
			else WALKS[math.floor(h.walked / STEP) % 4 + 1]
		setFigure(h.ms, pose, h.heading, h.x, h.y, 0.4 + SPRITE_Y + MAN_RISE)
	end
end

-- the game's bolt: a man runs off along heading (give or take veer), seed picks how far
local function bolt(h: Hand, heading: number, seed: number)
	if #crews >= CREW.max then
		local old = table.remove(crews, 1) :: Hand
		old.ms.quad:Destroy()
	end
	local reach = CREW.runCells[1] + kc(seed, 5) * (CREW.runCells[2] - CREW.runCells[1])
	local a = heading + (kc(seed, 6) - 0.5) * CREW.veer
	h.heading, h.walked = a, kc(seed, 7) * STEP * 4
	h.tx, h.ty = h.x + math.cos(a) * reach, h.y + math.sin(a) * reach
	h.at, h.there = os.clock(), false
	h.ms.quad.Parent = folder
	table.insert(crews, h)
end

-- the game's knockedOut, for the men: the dead vehicle's hands bolt from the wreck, and its crew (none
-- by the game's table) climbs out of the hatch
local function knockedOut(v: View?, kind: string, side: number, x: number, y: number)
	local seed = math.floor(x * 97 + y * 131 + 0.5)
	if v and v.hands then
		for _, h in v.hands do
			bolt(h, math.atan2(h.y - y, h.x - x), seed)
		end
		v.hands = nil
	end
	local n = CREW.count[kind] or 0
	local g = kc(seed, 4) * math.pi * 2
	for i = 0, n - 1 do
		local w = g + (i - (n - 1) / 2) * CREW.spread
		local r = CREW.hatch * (FOOTPRINT[kind] or 1)
		local h = newHand(folder, "crew", SIDE_COLOR[side] or Color3.new(0.7, 0.7, 0.7), x + math.cos(w) * r, y + math.sin(w) * r, w, 0)
		if h then
			bolt(h, w, seed + i * 7)
		end
	end
end

-- the game's drawCrews
local function stepCrews(dt: number)
	dt = math.min(MAX_DT, math.max(0, dt))
	local now = os.clock()
	local drop = 0
	while drop < #crews and now - crews[drop + 1].at > CREW.holdSec + CREW.fadeSec + CREW.runCells[2] / CREW.pace do
		drop += 1
	end
	for _ = 1, drop do
		local h = table.remove(crews, 1) :: Hand
		h.ms.quad:Destroy()
	end
	for _, h in crews do
		if not h.there then
			local mx, my = h.tx - h.x, h.ty - h.y
			local w = math.sqrt(mx * mx + my * my)
			local c = math.min(w, CREW.pace * dt)
			if w > 1e-4 then
				h.x += mx / w * c
				h.y += my / w * c
				h.walked += c
			end
			if w - c < 0.02 then
				h.there, h.at = true, now
			end
		end
		local k = if h.there then now - h.at else 0
		local alpha = if k <= CREW.holdSec then 1 else 1 - (k - CREW.holdSec) / CREW.fadeSec
		local shown = alpha > 0 and not FogOverlay.hidden(h.x, h.y)
		h.ms.gui.Enabled = shown
		if shown then
			h.ms.colour.ImageTransparency = 1 - alpha
			h.ms.paint.ImageTransparency = 1 - alpha
			setFigure(h.ms, if h.there then "stand" else WALKS[math.floor(h.walked / STEP) % 4 + 1], h.heading, h.x, h.y, 0.4 + SPRITE_Y + MAN_RISE)
		end
	end
end

function UnitRenderer.start()
	folder = Instance.new("Folder")
	folder.Name = "WarFrontUnits"
	folder.Parent = workspace
	SpriteBank.preload()
	RunService.RenderStepped:Connect(function(dt)
		DeathRenderer.step(dt)
		for _, v in views do
			v.t = math.min(1, v.t + dt / SNAPSHOT_SEC)
			local pos = v.from:Lerp(v.to, v.t)
			place(v, pos, lerpAngle(v.fromYaw, v.toYaw, v.t), dt)
			if #v.men > 0 then
				placeMen(v, pos, dt)
			end
			if v.kind == "engineer" then
				work(v, pos.X / S, pos.Z / S, lerpAngle(v.fromYaw, v.toYaw, v.t), dt)
			end
		end
		if #crews > 0 then
			stepCrews(dt)
		end
		if #wrecks > 0 then
			local now = os.clock()
			local keep = 0
			for i = 1, #wrecks do
				local w = wrecks[i]
				if placeWreck(w, now) then
					keep += 1
					wrecks[keep] = w
				end
			end
			for i = #wrecks, keep + 1, -1 do
				wrecks[i] = nil
			end
		end
	end)
end

local STATUS = { [1] = "RECON", [2] = "PACKING", [3] = "SETTING UP", [4] = "INSIDE", [5] = "REPAIR", [6] = "SABOTAGE", [7] = "HELD", [8] = "CUT OFF", [9] = "SETTING UP HQ", [10] = "DIGGING", [11] = "FILLING", [12] = "MENDING", [13] = "IN TRENCH" }

-- units: { {id, kind, side, x, y, heading, hp, maxHp, status}, ... }
-- deaths: vehicles destroyed since the last snapshot, { id, kind, x, y, hull, turret } (wrecks)
function UnitRenderer.apply(tick: number, units: { any }, deaths: { any }?)
	if tick <= lastTick then
		return -- stale or duplicate snapshot
	end
	for _, d in deaths or {} do
		-- the game leaves the wreck at the hull and turret it was drawing
		local v = views[d[1]]
		if v and v.kind ~= d[2] then
			v = nil -- a convoy's id, not this unit's
		end
		local hull, turret = d[5], d[6]
		if v then
			hull = lerpAngle(v.fromYaw, v.toYaw, v.t)
			turret = v.turretAt or turret
		end
		local death = DeathRenderer.kill(d[2], d[3], d[4])
		leaveWreck(d[2], d[3], d[4], hull, turret, death)
		if d[2] ~= "demo" then -- Ai.wreck.none
			knockedOut(v, d[2], v and v.side or 0, d[3], d[4])
		end
	end
	lastTick = tick
	for _, u in units do
		local id, kind, side, x, y, heading = u[1], u[2], u[3], u[4], u[5], u[6]
		local v = views[id]
		local target = World.toWorld(x, y, 0.4)
		if not v then
			v = create(id, kind, side)
			views[id] = v
			v.from, v.fromYaw = target, heading
		else
			local t = v.t
			v.from = v.from:Lerp(v.to, t)
			v.fromYaw = lerpAngle(v.fromYaw, v.toYaw, t)
		end
		v.to, v.toYaw, v.t, v.seen = target, heading, 0, tick
		local frac = math.clamp((u[7] or 1) / math.max(1, u[8] or u[7] or 1), 0, 1)
		v.barGui.Enabled = frac < 0.999
		-- rank chevrons (veteran, elite, hero) before the status
		local rank = string.rep("^", u[10] or 0)
		local st = STATUS[u[9] or 0] or ""
		local aboard = if (u[11] or 0) > 0 then `+{u[11]}` else ""
		local bits = {}
		for _, b in { rank, aboard, st } do
			if b ~= "" then
				table.insert(bits, b)
			end
		end
		v.status.Text = table.concat(bits, " ")
		v.hpFrac, v.flags, v.aimX, v.aimY, v.inTrench = frac, u[12] or 0, u[13] or 0, u[14] or 0, u[9] == 13
		v.statusCode, v.sinceShot = u[9] or 0, u[15] or 9
		v.turretWant = u[16] or heading
		v.stageWant = u[17] or 0
		-- an oil truck driving out or carrying nothing shows its empty look (the game's truck_empty)
		local empty = bit32.btest(v.flags, 8)
		if empty ~= v.empty and v.look and v.look.empty and v.sprites[1] then
			v.empty = empty
			local layer = if empty then v.look.empty else v.look.body
			v.sprites[1].y0c, v.sprites[1].y0p = layer.colour, layer.paint
			v.facing = -1
		end
		v.bar.Size = UDim2.fromScale(frac, 1)
		v.bar.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(110, 220, 90) elseif frac > 0.25 then Color3.fromRGB(240, 200, 60) else Color3.fromRGB(230, 70, 60)
	end
	for id, v in views do
		if v.seen ~= tick then -- gone from the snapshot (dead, or later hidden by fog)
			v.model:Destroy()
			views[id] = nil
		end
	end
end

function UnitRenderer.each(): { [number]: View }
	return views
end

function UnitRenderer.setSelected(selected: { [number]: boolean })
	for id, v in views do
		v.ring.Transparency = if selected[id] then 0.3 else 1
		v.selected = selected[id] == true
		if v.halo then
			v.halo.Transparency = 1
			local gui = v.halo:FindFirstChildOfClass("SurfaceGui")
			if gui then
				gui.Enabled = not v.selected -- the game hides the halo of a selected unit
			end
		end
	end
end

return UnitRenderer
