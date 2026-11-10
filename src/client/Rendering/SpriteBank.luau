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
	turns the quad. Drawn width in cells = cells / art.w from the game's unit table (fa.units).
	Not drawn yet: the shape row (the game uses it for the dark rim and shadow), wrecks, the men sheet.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapCodec = require(Shared.Maps.MapCodec)
local PixelCodec = require(Shared.Assets.PixelCodec)

local SpriteBank = {}

export type Layer = { content: Content, colour: number, paint: number }
export type Look = {
	frame: number, -- pixels per frame side
	columns: number,
	cells: number, -- drawn width of one frame, in map cells
	body: Layer,
	turret: Layer?,
}

-- kind -> module, strips, game cells and art.w (fa.units in the bundle)
local KINDS: { [string]: { module: string, body: string, turret: string?, cells: number, artW: number } } = {
	tank = { module = "OrigTank", body = "hull", turret = "turret", cells = 1, artW = 0.492 },
	truck = { module = "OrigTruck", body = "full", cells = 0.8, artW = 0.4 },
	scout = { module = "OrigScout", body = "body", cells = 0.62, artW = 0.317 },
	artillery = { module = "OrigArtillery", body = "body", cells = 1.4, artW = 0.683 },
	infantry = { module = "OrigInfantry", body = "body", cells = 0.78, artW = 0.5 },
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
		return { content = p.content, colour = c, paint = q }
	end
	local body = layer(k.body)
	if not body then
		return nil
	end
	local look: Look = {
		frame = p.meta.frame,
		columns = p.meta.columns,
		cells = k.cells / k.artW,
		body = body,
		turret = if k.turret then layer(k.turret) else nil,
	}
	looks[kind] = look
	return look
end

-- loads every page up front, so the first unit of a kind doesn't stall a frame
function SpriteBank.preload()
	for kind in KINDS do
		SpriteBank.look(kind)
	end
end

-- top-left pixel of facing d in the strip that starts at y0
function SpriteBank.offset(look: Look, y0: number, d: number): Vector2
	return Vector2.new((d % look.columns) * look.frame, y0 + (d // look.columns) * look.frame)
end

return SpriteBank
