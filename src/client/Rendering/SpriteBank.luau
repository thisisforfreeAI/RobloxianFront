--!strict
--[[
	SpriteBank: unit art cut from WarFront's own units sheet (units-top.png), loaded into EditableImages.

	The art lives in git-ignored DevAssets modules (OrigTank, OrigTruck, ...) written by
	tools/asset_pipeline/pack_original.py. When a module is missing (a fresh clone of the public repo) the
	bank returns nil and UnitRenderer keeps drawing its placeholder blocks.

	How the game draws a unit (traced from its renderer): the colour row, then the paint row multiplied by
	the nation colour and clipped to the paint's own alpha, drawn over it. Roblox's ImageColor3 multiplies
	the same way, so the paint is a second ImageLabel tinted with the side colour. A turreted unit draws
	its turret rows the same way on top. Frame for heading h: Facing.index(h, 16); the rest of the angle
	turns the quad. Drawn width in cells = cells * 1.3 / art.w: cells and art.w from the game's unit
	table (fa.units), 1.3 its unit scale (za.scale), which every unit size is multiplied by.
	Men (men-top.png, 48 px frames): SpriteBank.figure("rifle", "leader", "gunner", ... "tube") gives each pose's colour and
	paint strips; SquadMen places them.
	The shape row feeds three looks the game derives at run time, baked by pack_original.py into modules
	of their own: <module>Rim (the dark rim, plus the turret's plain shape), <module>RimHalf (the rim the
	game swaps in when units are drawn small) and <module>Shade (the soft shadow, 1/3 size). They come
	back as look.fx; a kind without them is drawn without rim and shadow.
	Not drawn yet: wrecks.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapCodec = require(Shared.Maps.MapCodec)
local PixelCodec = require(Shared.Assets.PixelCodec)

local SpriteBank = {}

export type Layer = { content: Content, colour: number, paint: number, base: string }
export type FxSheet = { content: Content, frame: number, columns: number, strips: { [string]: number } }
export type Look = {
	frame: number, -- pixels per frame side
	columns: number,
	cells: number, -- drawn width of one frame, in map cells
	body: Layer,
	turret: Layer?,
	empty: Layer?, -- trucks: the look while driving out or carrying nothing
	size: number, -- the unit's size in cells (fa cells x za.scale): what the game's shadow is worked from
	artH: number, -- fa art.h / art.w: the body's depth over its length
	tall: number, -- za.shadow.tall: how far the shadow reaches, in sizes
	fx: { rim: FxSheet, rimHalf: FxSheet?, shade: FxSheet? }?,
}

-- kind -> module, strips, game cells and art.w (fa.units in the bundle)
local UNIT_SCALE = 1.3 -- za.scale
local FIGURES = {
	rifle = "OrigMenRifle", leader = "OrigMenLeader", para = "OrigMenPara", gunner = "OrigMenGunner",
	loader = "OrigMenLoader", mortarman = "OrigMenMortarman", bearer = "OrigMenBearer", tube = "OrigMenTube",
}

-- tall: za.shadow.tall (rest 0.3 for kinds it does not list)
local KINDS: { [string]: { module: string, body: string, turret: string?, empty: string?, cells: number, artW: number, artH: number, tall: number } } = {
	tank = { module = "OrigTank", body = "hull", turret = "turret", cells = 1, artW = 0.492, artH = 0.283, tall = 0.32 },
	truck = { module = "OrigTruck", body = "full", empty = "empty", cells = 0.8, artW = 0.4, artH = 0.167, tall = 0.36 },
	scout = { module = "OrigScout", body = "body", cells = 0.62, artW = 0.317, artH = 0.2, tall = 0.36 },
	artillery = { module = "OrigArtillery", body = "body", cells = 1.4, artW = 0.683, artH = 0.267, tall = 0.24 },
	infantry = { module = "OrigInfantry", body = "body", cells = 0.78, artW = 0.5, artH = 0.5, tall = 0.5 },
}

local pages: { [string]: any } = {} -- module name -> { content, meta } or false when unavailable
local looks: { [string]: Look | false } = {}

local function page(name: string): any
	local got = pages[name]
	if got ~= nil then
		return got
	end
	pages[name] = false
	local folder = script.Parent.Parent:FindFirstChild("DevAssets")
	local mod = folder and folder:FindFirstChild(name)
	if not mod or not mod:IsA("ModuleScript") then
		return false
	end
	local ok, result = pcall(function()
		local meta = require(mod) :: any
		local pixels = PixelCodec.decode(MapCodec.base64Decode(meta.rle), meta.width, meta.height)
		local size = Vector2.new(meta.width, meta.height)
		local image = AssetService:CreateEditableImage({ Size = size })
		image:WritePixelsBuffer(Vector2.zero, size, pixels)
		return { content = Content.fromObject(image), meta = meta }
	end)
	if not ok then
		warn(`[SpriteBank] {name} could not be loaded, placeholder shapes stay:`, result)
		return false
	end
	pages[name] = result
	return result
end

function SpriteBank.look(kind: string): Look?
	local cached = looks[kind]
	if cached ~= nil then
		return cached or nil
	end
	looks[kind] = false
	local k = KINDS[kind]
	if not k then
		return nil
	end
	local p = page(k.module)
	if not p then
		return nil
	end
	local strips = p.meta.strips
	local function layer(base: string): Layer?
		local c, q = strips[base .. "_colour"], strips[base .. "_paint"]
		if c == nil or q == nil then
			return nil
		end
		return { content = p.content, colour = c, paint = q, base = base }
	end
	local body = layer(k.body)
	if not body then
		return nil
	end
	local function sheet(suffix: string): FxSheet?
		local f = page(k.module .. suffix)
		if not f then
			return nil
		end
		return { content = f.content, frame = f.meta.frame, columns = f.meta.columns, strips = f.meta.strips }
	end
	local rim = sheet("Rim")
	local look: Look = {
		frame = p.meta.frame,
		columns = p.meta.columns,
		cells = k.cells * UNIT_SCALE / k.artW,
		body = body,
		turret = if k.turret then layer(k.turret) else nil,
		empty = if k.empty then layer(k.empty) else nil,
		size = k.cells * UNIT_SCALE,
		artH = k.artH / k.artW,
		tall = k.tall,
		fx = if rim then { rim = rim, rimHalf = sheet("RimHalf"), shade = sheet("Shade") } else nil,
	}
	looks[kind] = look
	return look
end

export type Figure = { content: Content, frame: number, columns: number, poses: { [string]: { colour: number, paint: number } } }
local figures: { [string]: Figure | false } = {}

-- one soldier figure: per pose, the y of its colour and paint strips
function SpriteBank.figure(name: string): Figure?
	local cached = figures[name]
	if cached ~= nil then
		return cached or nil
	end
	figures[name] = false
	local mod = FIGURES[name]
	local p = mod and page(mod)
	if not p then
		return nil
	end
	local poses = {}
	for label, y0 in p.meta.strips do
		local pose, layer = string.match(label, "^(.+)_(%a+)$")
		if pose and (layer == "colour" or layer == "paint") then
			poses[pose] = poses[pose] or { colour = -1, paint = -1 }
			poses[pose][layer] = y0
		end
	end
	local fig: Figure = { content = p.content, frame = p.meta.frame, columns = p.meta.columns, poses = poses }
	figures[name] = fig
	return fig
end

-- loads every page up front, so the first unit of a kind doesn't stall a frame
function SpriteBank.preload()
	for kind in KINDS do
		SpriteBank.look(kind)
	end
	for name in FIGURES do
		SpriteBank.figure(name)
	end
end

-- top-left pixel of facing d in the strip that starts at y0
function SpriteBank.offset(look: { frame: number, columns: number }, y0: number, d: number): Vector2
	return Vector2.new((d % look.columns) * look.frame, y0 + (d // look.columns) * look.frame)
end

return SpriteBank
