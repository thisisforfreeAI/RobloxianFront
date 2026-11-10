--!strict
--[[
	TownRenderer: draws a designed map's towns and trees from the game's own art.

	The game ships every designed map's towns pre-drawn (dist/cities/<id>.city: a sheet of 14 px tiles,
	one per town cell, and an index of which tile goes where). tools/asset_pipeline/pack_city.py lays
	the tiles out into map chunks of 64 x 64 cells (896 px) and stores each, raw DEFLATE, in a local
	module (src/client/DevAssets/City_<id>*.luau, git-ignored: it is the game's art). Here each chunk is
	inflated into an EditableImage on a flat part just above the ground and under the roads, so the
	main roads show through the gaps the game leaves for them (its own road layer draws those).
	No modules for the map (a fresh clone, or a map without a .city file): nothing is drawn and the
	placeholder town discs stay.
	The chunks also carry every tree (forests, scattered trees, town yard trees), placed by the game's
	own tree code (tools/conversion/export_trees.cjs) and drawn from trees-top.png with their shadows.
	Not yet: the roof shading (the file's aux data drives the game's lighting), trees swaying, burning
	or being cleared round new buildings.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Inflate = require(Shared.Utilities.Inflate)

local TownRenderer = {}

local S = World.STUDS_PER_CELL
local HEIGHT = 0.07 -- above the ground (0), under the roads (0.15)

-- returns true when the town art was drawn
function TownRenderer.build(mapId: string, parent: Instance): boolean
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local metaModule = assets and assets:FindFirstChild("City_" .. mapId)
	if not metaModule or not metaModule:IsA("ModuleScript") then
		return false
	end
	local meta = require(metaModule) :: any
	local folder = Instance.new("Folder")
	folder.Name = "Towns"
	local drawn = 0
	for _, c in meta.chunks do
		local cx, cy, cw, ch, name = c[1], c[2], c[3], c[4], c[5]
		local mod = assets:FindFirstChild(name)
		if not mod or not mod:IsA("ModuleScript") then
			warn(`[TownRenderer] {name} missing, that part of the map has no towns drawn`)
			continue
		end
		local ok, err = pcall(function()
			local chunk = require(mod) :: any
			local size = Vector2.new(chunk.width, chunk.height)
			local pixels = Inflate.raw(MapCodec.base64Decode(chunk.deflate), chunk.width * chunk.height * 4)
			local image = AssetService:CreateEditableImage({ Size = size })
			image:WritePixelsBuffer(Vector2.zero, size, pixels)
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
			part.Transparency = 1
			-- turned by TOP_GUI_YAW like the ground, so image x runs east and y south (local X/Z swap)
			part.Size = Vector3.new(ch * S, 0.05, cw * S)
			part.CFrame = CFrame.new((cx + cw / 2) * S, World.GROUND_Y + HEIGHT, (cy + ch / 2) * S) * CFrame.Angles(0, World.TOP_GUI_YAW, 0)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = size
			gui.LightInfluence = 0
			gui.Parent = part
			local label = Instance.new("ImageLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ImageContent = Content.fromObject(image)
			label.Parent = gui
			part.Parent = folder
		end)
		if ok then
			drawn += 1
		else
			warn(`[TownRenderer] {name} could not be drawn:`, err)
		end
	end
	folder.Parent = parent
	print(`[TownRenderer] {mapId}: {drawn} of {#meta.chunks} town chunks drawn`)
	return drawn > 0
end

return TownRenderer
