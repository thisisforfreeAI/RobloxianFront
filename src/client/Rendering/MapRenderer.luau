--!strict
--[[
	MapRenderer: draws the map as a flat ground plane seen from above.
	Terrain: one EditableImage (1 pixel per cell) on the ground part, pixelated.
	Fallback if EditableImage is unavailable: merged rectangle Parts.
	All colours are PLACEHOLDER (TEMP-003). Gameplay never reads anything drawn here.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapCodec = require(Shared.Maps.MapCodec)
local Terrain = require(Shared.Definitions.Terrain)
local World = require(Shared.Config.World)
local Rules = require(Shared.Config.Rules)
local DevFlags = require(script.Parent.Parent.Dev.DevFlags)

local MapRenderer = {}

local S = World.STUDS_PER_CELL
local URBAN = { 92, 92, 96 }

local function cellColor(map: MapCodec.DecodedMap, i: number): (number, number, number)
	local t = buffer.readu8(map.terrain, i)
	local rgb = Terrain.placeholderColor[Terrain.names[t + 1]] or { 255, 0, 255 }
	local r, g, b = rgb[1], rgb[2], rgb[3]
	if buffer.readu8(map.urban, i) > 0 then
		r, g, b = (r + URBAN[1] * 2) / 3, (g + URBAN[2] * 2) / 3, (b + URBAN[3] * 2) / 3
	end
	local shade = 0.82 + buffer.readu8(map.elev, i) / 15 * 0.3
	return math.clamp(r * shade, 0, 255), math.clamp(g * shade, 0, 255), math.clamp(b * shade, 0, 255)
end

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function buildImageGround(map: MapCodec.DecodedMap, ground: Part): boolean
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(map.width, map.height) })
	end)
	if not ok or not image then
		warn("[MapRenderer] EditableImage unavailable, using Part fallback:", image)
		return false
	end
	local cells = map.width * map.height
	local pixels = buffer.create(cells * 4)
	for i = 0, cells - 1 do
		local r, g, b = cellColor(map, i)
		buffer.writeu8(pixels, i * 4, r)
		buffer.writeu8(pixels, i * 4 + 1, g)
		buffer.writeu8(pixels, i * 4 + 2, b)
		buffer.writeu8(pixels, i * 4 + 3, 255)
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(map.width, map.height), pixels)

	-- Top face: GUI x runs along +X and GUI y (down) along +Z, so row 0 is the map's north edge.
	-- VERIFY IN STUDIO (renderer check 3): if the map shows mirrored, flip with ImageLabel.Rotation/ImageRectSize.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(map.width * 4, map.height * 4)
	gui.LightInfluence = 0
	gui.Adornee = ground
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(image)
	label.Parent = gui
	gui.Parent = ground
	print(`[MapRenderer] EditableImage ground {map.width}x{map.height}`)
	return true
end

-- Fallback: merge equal-colour horizontal runs, then stack identical runs vertically.
local function buildPartGround(map: MapCodec.DecodedMap, folder: Folder)
	local w, h = map.width, map.height
	local open: { [string]: { x0: number, x1: number, y0: number, t: number } } = {}
	local count = 0
	local function emit(run)
		local width, depth = run.x1 - run.x0 + 1, run.y1 - run.y0 + 1
		local i = run.y0 * w + run.x0
		local r, g, b = cellColor(map, i)
		newPart({
			Size = Vector3.new(width * S, 0.2, depth * S),
			Position = Vector3.new((run.x0 + width / 2) * S, World.GROUND_Y + 0.1, (run.y0 + depth / 2) * S),
			Color = Color3.fromRGB(r, g, b),
			Parent = folder,
		})
		count += 1
	end
	for y = 0, h - 1 do
		local nextOpen = {}
		local x = 0
		while x < w do
			local t = buffer.readu8(map.terrain, y * w + x) + buffer.readu8(map.urban, y * w + x) * 16
			local x1 = x
			while x1 + 1 < w and buffer.readu8(map.terrain, y * w + x1 + 1) + buffer.readu8(map.urban, y * w + x1 + 1) * 16 == t do
				x1 += 1
			end
			local key = `{x}:{x1}:{t}`
			local run = open[key]
			if run then
				run.y1 = y
				open[key] = nil
			else
				run = { x0 = x, x1 = x1, y0 = y, y1 = y, t = t } :: any
			end
			nextOpen[key] = run
			x = x1 + 1
		end
		for _, run in open do
			emit(run)
		end
		open = nextOpen
	end
	for _, run in open do
		emit(run)
	end
	print(`[MapRenderer] fallback ground: {count} parts`)
end

local function label(parent: Instance, text: string, size: number)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 22)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 600
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.TextSize = size
	t.Font = Enum.Font.GothamBold
	t.Parent = bb
	bb.Parent = parent
end

function MapRenderer.build(map: MapCodec.DecodedMap): Folder
	local rules = Rules.new(require(Shared:WaitForChild("GameData").RulesData) :: any)
	local folder = Instance.new("Folder")
	folder.Name = "WarFrontMap"

	-- The ground is the only queryable part: selection raycasts hit it and nothing else.
	local ground = newPart({
		Name = "Ground",
		Size = Vector3.new(map.width * S, 1, map.height * S),
		Position = Vector3.new(map.width * S / 2, World.GROUND_Y - 0.5, map.height * S / 2),
		Color = Color3.fromRGB(70, 80, 60),
		CanQuery = true,
		Parent = folder,
	})
	if DevFlags.FORCE_PART_GROUND or not buildImageGround(map, ground) then
		buildPartGround(map, folder)
	end

	-- Roads (placeholder look): highway rank 2, road rank 1, tracks thinner and brown.
	for _, road in map.data.roads do
		local width = if road.track then 0.35 elseif road.rank >= 2 then 0.9 else 0.6
		local color = if road.track then Color3.fromRGB(120, 96, 64) else Color3.fromRGB(58, 58, 60)
		local pts = road.pts
		for i = 1, #pts - 3, 2 do
			local a = World.toWorld(pts[i], pts[i + 1], 0.15)
			local b = World.toWorld(pts[i + 2], pts[i + 3], 0.15)
			local len = (b - a).Magnitude
			if len > 0 then
				newPart({
					Size = Vector3.new(width * S, 0.1, len + width * S),
					CFrame = CFrame.lookAt((a + b) / 2, b),
					Color = color,
					Parent = folder,
				})
			end
		end
	end

	for _, rig in map.data.rigs do
		local r = rules:number("rigs.radius")
		local disc = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, r * 2 * S, r * 2 * S),
			CFrame = CFrame.new(World.toWorld(rig.x + 0.5, rig.y + 0.5, 0.25)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(20, 20, 20),
			Transparency = 0.35,
			Parent = folder,
		})
		label(disc, rig.name, 13)
	end

	for _, s in map.data.settlements do
		local key = `settlements.{s.kind}Radius`
		local r = if rules:has(key) then rules:number(key) else 1.4
		local disc = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, r * 2 * S, r * 2 * S),
			CFrame = CFrame.new(World.toWorld(s.x + 0.5, s.y + 0.5, 0.2)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(200, 200, 200),
			Transparency = 0.6,
			Parent = folder,
		})
		label(disc, s.name, if s.kind == "capital" then 16 else 12)
	end

	-- HQ placeholders at each start: the HQ sprite in WarFront is 5 cells wide.
	for i, s in map.data.starts do
		local hq = newPart({
			Size = Vector3.new(5 * S, 2, 5 * S),
			Position = World.toWorld(s.x + 0.5, s.y + 0.5, 1),
			Color = if i == 1 then Color3.fromRGB(60, 110, 200) else Color3.fromRGB(200, 70, 60),
			Parent = folder,
		})
		label(hq, `HQ · {s.city}`, 14)
	end

	folder.Parent = workspace
	return folder
end

return MapRenderer
