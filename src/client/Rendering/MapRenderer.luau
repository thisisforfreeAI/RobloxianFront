--!strict
--[[
	MapRenderer: draws the map as a flat ground plane seen from above.
	Terrain: the game's own baked ground (3 px a cell, Ground_<id> in DevAssets, packed by
	tools/asset_pipeline/pack_ground.py) when it is there, else one EditableImage of placeholder
	colours (1 pixel per cell), on the ground part, pixelated.
	Fallback if EditableImage is unavailable: merged rectangle Parts.
	All colours are PLACEHOLDER (TEMP-003). Gameplay never reads anything drawn here.
]]

local ImageMemory = require(script.Parent.ImageMemory)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapCodec = require(Shared.Maps.MapCodec)
local Terrain = require(Shared.Definitions.Terrain)
local World = require(Shared.Config.World)
local Rules = require(Shared.Config.Rules)
local DevFlags = require(script.Parent.Parent.Dev.DevFlags)
local TownRenderer = require(script.Parent.TownRenderer)
local Inflate = require(Shared.Utilities.Inflate)
local RoadRenderer = require(script.Parent.RoadRenderer)

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

-- the game's baked ground as image strips, or nil when the local module is missing or fails
local function bakedGround(map: MapCodec.DecodedMap): { { content: Content, x: number, width: number, image: EditableImage } }?
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local mod = assets and assets:FindFirstChild("Ground_" .. map.data.id)
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local allocated = {}
	local ok, result = pcall(function()
		local g = require(mod) :: any
		local out = {}
		for _, piece in g.pieces do
			local size = Vector2.new(piece.width, g.height)
			local image = ImageMemory.create(size)
			assert(image, "EditableImage memory unavailable for ground strip")
			table.insert(allocated, image)
			local pixels = Inflate.raw(MapCodec.base64Decode(piece.deflate), piece.width * g.height * 4)
			RoadRenderer.paint(pixels, piece.width, g.height, map, piece.x, g.width)
			image:WritePixelsBuffer(Vector2.zero, size, pixels)
			table.insert(out, { content = Content.fromObject(image), x = piece.x / g.width, width = piece.width / g.width, image = image })
		end
		return out
	end)
	if not ok then
		for _, image in allocated do ImageMemory.release(image) end
		warn("[MapRenderer] baked ground could not be loaded, placeholder colours instead:", result)
		return nil
	end
	return result
end

local function buildImageGround(map: MapCodec.DecodedMap, ground: Part): boolean
	local baked = bakedGround(map)
	if baked then
		ground.Destroying:Connect(function() for _, piece in baked do ImageMemory.release(piece.image) end end)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(map.width * 4, map.height * 4)
		gui.LightInfluence = 0
		gui.Adornee = ground
		for _, piece in baked do
			local label = Instance.new("ImageLabel")
			label.Position = UDim2.fromScale(piece.x, 0)
			label.Size = UDim2.fromScale(piece.width, 1)
			label.BackgroundTransparency = 1
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ImageContent = piece.content
			label.Parent = gui
		end
		gui.Parent = ground
		print(`[MapRenderer] the game's baked ground, {#baked} strips`)
		return true
	end
	local ok, image = pcall(function()
		return ImageMemory.create(Vector2.new(map.width, map.height))
	end)
	if not ok or not image then
		warn("[MapRenderer] EditableImage unavailable, using Part fallback:", image)
		return false
	end
	ground.Destroying:Connect(function() ImageMemory.release(image) end)
	local cells = map.width * map.height
	local pixels = buffer.create(cells * 4)
	for i = 0, cells - 1 do
		local r, g, b = cellColor(map, i)
		buffer.writeu8(pixels, i * 4, r)
		buffer.writeu8(pixels, i * 4 + 1, g)
		buffer.writeu8(pixels, i * 4 + 2, b)
		buffer.writeu8(pixels, i * 4 + 3, 255)
	end
	RoadRenderer.paint(pixels, map.width, map.height, map, 0, map.width)
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(map.width, map.height), pixels)

	-- The ground part is turned by World.TOP_GUI_YAW, so GUI x runs east (+X) and GUI y south (+Z):
	-- row 0 is the map's north edge. Studio test 2b compares this with the Part ground.
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
		-- Turned by TOP_GUI_YAW so the terrain image's x runs east and y runs south; local X/Z swap.
		Size = Vector3.new(map.height * S, 1, map.width * S),
		CFrame = CFrame.new(map.width * S / 2, World.GROUND_Y - 0.5, map.height * S / 2) * CFrame.Angles(0, World.TOP_GUI_YAW, 0),
		Color = Color3.fromRGB(70, 80, 60),
		CanQuery = true,
		Parent = folder,
	})
	if DevFlags.FORCE_PART_GROUND or not buildImageGround(map, ground) then
		buildPartGround(map, folder)
	end

	-- The game's own town art, when the local modules are there (TownRenderer).
	local towns = TownRenderer.build(map.data.id, folder)

	-- Persistent far roads are already in the ground; close detail uses tiny shared source-derived
	-- procedural strips. Missing local look data retains the former plain Parts as a fallback.
	if not RoadRenderer.build(map, folder) then
	-- Roads: widths from the game's city painter (half widths major 0.7, minor 0.36, track 0.2, plus
	-- shoulder 0.08 / 0.1 / 0), so they fill the gaps the town art leaves; asphalt #4d5357, road
	-- #70777a. APPROX: rank 2+ taken as major, rank 1 as minor; tracks keep the placeholder brown.
	for _, road in map.data.roads do
		local width = if road.track then 0.4 elseif road.rank >= 2 then 2 * (0.7 + 0.08) else 2 * (0.36 + 0.1)
		local color = if road.track then Color3.fromRGB(120, 96, 64) elseif road.rank >= 2 then Color3.fromRGB(0x4d, 0x53, 0x57) else Color3.fromRGB(0x70, 0x77, 0x7a)
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
			Transparency = if towns then 1 else 0.6, -- the drawn town replaces the placeholder disc
			Parent = folder,
		})
		label(disc, s.name, if s.kind == "capital" then 16 else 12)
	end

	-- (HQs are drawn from the server's structures: with the opening drop they go up where each truck lands.)

	folder.Parent = workspace
	return folder
end

return MapRenderer
