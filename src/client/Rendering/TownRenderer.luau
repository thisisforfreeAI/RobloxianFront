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
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Inflate = require(Shared.Utilities.Inflate)

local TownRenderer = {}

local S = World.STUDS_PER_CELL
local HEIGHT = 0.07 -- above the ground (0), under the roads (0.15)
local OVERVIEW_PX = 2 -- overview pixels a cell
local TILE_PX = 14 -- chunk pixels a cell (the game's 14 px town tiles)
local MAX_LOADED = 9 -- full chunks shown at once
local DETAIL_FROM = 5 -- screen pixels a cell from which the full chunks are worth loading
local CHECK_SEC = 0.1
local RETRY_SEC = 1.5 -- after the budget refused an image
local KEEP_REACH = 1.6 -- shown chunks stay until this far past the view (so panning back is instant)
local PIXEL_CACHE = 6 -- chunk pixels kept in memory for chunks not shown (3.2 MB each)
local SHOW_MS = 6 -- per check, time spent showing chunks whose pixels are ready
local POOL_MAX = 2 -- spare images kept for reuse instead of asking the budget again

-- a flat part turned like the ground (image x east, y south) carrying one image
local function imagePart(name: string, cx: number, cy: number, cw: number, ch: number, size: Vector2, rise: number, pixelated: boolean): (Part, ImageLabel)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(ch * S, 0.05, cw * S)
	part.CFrame = CFrame.new((cx + cw / 2) * S, World.GROUND_Y + rise, (cy + ch / 2) * S) * CFrame.Angles(0, World.TOP_GUI_YAW, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = size
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ResampleMode = if pixelated then Enum.ResamplerMode.Pixelated else Enum.ResamplerMode.Default
	label.Parent = gui
	return part, label
end

local function newImage(size: Vector2): any
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = size })
	end)
	return if ok then image else nil
end

type Chunk = { cx: number, cy: number, cw: number, ch: number, name: string, mod: ModuleScript, part: Part?, image: any, packed: buffer?, px: buffer?, w: number, h: number, used: number }

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
	local chunks: { Chunk } = {}
	local mapW, mapH = 0, 0
	for _, c in meta.chunks do
		local mod = assets:FindFirstChild(c[5])
		if mod and mod:IsA("ModuleScript") then
			table.insert(chunks, { cx = c[1], cy = c[2], cw = c[3], ch = c[4], name = c[5], mod = mod, part = nil, image = nil, packed = nil, px = nil, w = 0, h = 0, used = 0 })
			mapW, mapH = math.max(mapW, c[1] + c[3]), math.max(mapH, c[2] + c[4])
		else
			warn(`[TownRenderer] {c[5]} missing, that part of the map has no towns drawn`)
		end
	end
	if #chunks == 0 then
		return false
	end
	-- the compressed bytes stay cached (small); inflating is the slow part
	local function decode(c: Chunk): (buffer, number, number)
		local chunk = require(c.mod) :: any
		if not c.packed then
			c.packed = MapCodec.base64Decode(chunk.deflate)
		end
		return Inflate.raw(c.packed :: buffer, chunk.width * chunk.height * 4), chunk.width, chunk.height
	end

	-- the overview: every chunk sampled down to 2 px a cell (2 x 2 samples a pixel), in one image
	local ow, oh = mapW * OVERVIEW_PX, mapH * OVERVIEW_PX
	local overviewPixels = buffer.create(ow * oh * 4)
	local step = TILE_PX / OVERVIEW_PX
	local drawn = 0
	for i, c in chunks do
		local ok, err = pcall(function()
			local px, w, h = decode(c)
			c.w, c.h = w, h
			local x0, y0 = c.cx * OVERVIEW_PX, c.cy * OVERVIEW_PX
			for oy = 0, c.ch * OVERVIEW_PX - 1 do
				for ox = 0, c.cw * OVERVIEW_PX - 1 do
					local r, g, b, a = 0, 0, 0, 0
					for sy = 0, 1 do
						for sx = 0, 1 do
							local x = math.min(w - 1, math.floor((ox + 0.25 + sx * 0.5) * step))
							local y = math.min(h - 1, math.floor((oy + 0.25 + sy * 0.5) * step))
							local o = (y * w + x) * 4
							local pa = buffer.readu8(px, o + 3)
							r += buffer.readu8(px, o) * pa
							g += buffer.readu8(px, o + 1) * pa
							b += buffer.readu8(px, o + 2) * pa
							a += pa
						end
					end
					local o = ((y0 + oy) * ow + x0 + ox) * 4
					if a > 0 then
						buffer.writeu8(overviewPixels, o, math.floor(r / a + 0.5))
						buffer.writeu8(overviewPixels, o + 1, math.floor(g / a + 0.5))
						buffer.writeu8(overviewPixels, o + 2, math.floor(b / a + 0.5))
						buffer.writeu8(overviewPixels, o + 3, math.floor(a / 4 + 0.5))
					end
				end
			end
		end)
		if ok then
			drawn += 1
		else
			warn(`[TownRenderer] {c.name} could not be read:`, err)
		end
		if i % 4 == 0 then
			task.wait() -- spread the decoding over a few frames
		end
	end
	local overviewOk = false
	local overview = newImage(Vector2.new(ow, oh))
	if overview then
		overview:WritePixelsBuffer(Vector2.zero, Vector2.new(ow, oh), overviewPixels)
		local part, label = imagePart("TownOverview", 0, 0, mapW, mapH, Vector2.new(ow, oh), HEIGHT, false)
		label.ImageContent = Content.fromObject(overview)
		part.Parent = folder
		overviewOk = true
	else
		warn("[TownRenderer] the image budget refused even the town overview; towns are not drawn")
	end
	folder.Parent = parent
	print(`[TownRenderer] {mapId}: overview of {drawn} of {#chunks} chunks ({ow}x{oh} px); full chunks stream in near the camera`)

	-- the full chunks, near the camera only. Inflated pixels are kept for a few chunks past the shown
	-- ones, and images are reused rather than given back to the budget, so panning back and forth
	-- shows the detail at once; new chunks inflate one a check, nearest first.
	local loaded = 0
	local holdUntil = 0
	local pool: { [string]: { any } } = {}
	local pooled = 0
	local clock = 0
	local function sizeKey(w: number, h: number): string
		return `{w}x{h}`
	end
	local function unload(c: Chunk)
		if c.part then
			c.part:Destroy()
			c.part = nil
		end
		if c.image then
			-- keep its pixels (a quick copy back out of the image) so it can come back without inflating
			local okRead, px = pcall(function()
				return c.image:ReadPixelsBuffer(Vector2.zero, Vector2.new(c.w, c.h))
			end)
			c.px = if okRead then px else nil
			c.used = clock
			local k = sizeKey(c.w, c.h)
			if pooled < POOL_MAX then
				pool[k] = pool[k] or {}
				table.insert(pool[k], c.image)
				pooled += 1
			else
				c.image:Destroy()
			end
			c.image = nil
			loaded -= 1
		end
	end
	local function takeImage(w: number, h: number): any
		local list = pool[sizeKey(w, h)]
		if list and #list > 0 then
			pooled -= 1
			return table.remove(list)
		end
		local image = newImage(Vector2.new(w, h))
		if not image and pooled > 0 then
			-- spare images of another size: give them back and ask again
			for _, l in pool do
				for _, im in l do
					im:Destroy()
				end
				table.clear(l)
			end
			pooled = 0
			image = newImage(Vector2.new(w, h))
		end
		return image
	end
	-- drop the least recently used inflated pixels beyond the cache size
	local function trimPixels()
		local spare: { Chunk } = {}
		for _, c in chunks do
			if c.px and not c.image then
				table.insert(spare, c)
			end
		end
		if #spare <= PIXEL_CACHE then
			return
		end
		table.sort(spare, function(a, b)
			return a.used < b.used
		end)
		for i = 1, #spare - PIXEL_CACHE do
			spare[i].px = nil
		end
	end
	-- returns false when the budget refused the image
	local function show(c: Chunk): boolean
		local px = c.px :: buffer
		local image = takeImage(c.w, c.h)
		if not image then
			return false
		end
		local size = Vector2.new(c.w, c.h)
		image:WritePixelsBuffer(Vector2.zero, size, px)
		local part, label = imagePart(c.name, c.cx, c.cy, c.cw, c.ch, size, HEIGHT + 0.01, true)
		label.ImageContent = Content.fromObject(image)
		part.Parent = folder
		c.part, c.image = part, image
		c.px = nil -- the image holds them now
		loaded += 1
		return true
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CHECK_SEC then
			return
		end
		acc = 0
		clock += 1
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		-- where the camera looks on the ground, and how big a cell is on screen there
		local cf = cam.CFrame
		local dir = cf.LookVector
		local t = if dir.Y < -1e-3 then (World.GROUND_Y - cf.Position.Y) / dir.Y else 0
		local focus = cf.Position + dir * math.max(0, t)
		local dist = math.max(1, (cf.Position - focus).Magnitude)
		local tanHalf = math.tan(math.rad(cam.FieldOfView) / 2)
		local cellPx = S * cam.ViewportSize.Y / (2 * dist * tanHalf)
		local fx, fy = focus.X / S, focus.Z / S
		local reach = dist * tanHalf * math.max(1, cam.ViewportSize.X / math.max(1, cam.ViewportSize.Y)) / S * 1.4
		local function far(c: Chunk): number
			local nx = math.clamp(fx, c.cx, c.cx + c.cw)
			local ny = math.clamp(fy, c.cy, c.cy + c.ch)
			return math.sqrt((nx - fx) ^ 2 + (ny - fy) ^ 2)
		end
		local detail = cellPx >= DETAIL_FROM or not overviewOk
		local want: { Chunk } = {}
		local keep: { [Chunk]: boolean } = {}
		if detail then
			local near: { Chunk } = {}
			for _, c in chunks do
				local d = far(c)
				if d <= reach * KEEP_REACH then
					table.insert(near, c)
				end
			end
			table.sort(near, function(a, b)
				return far(a) < far(b)
			end)
			for i = 1, math.min(#near, MAX_LOADED) do
				keep[near[i]] = true
				if far(near[i]) <= reach then
					table.insert(want, near[i])
				end
			end
		end
		for _, c in chunks do
			if c.image and not keep[c] then
				unload(c)
			end
		end
		if os.clock() < holdUntil then
			return
		end
		-- show what is ready, then inflate the nearest missing chunk (one a check: it takes a while)
		local t0 = os.clock()
		local inflated = false
		for _, c in want do
			c.used = clock
			if c.image then
				continue
			end
			if not c.px then
				if inflated then
					continue
				end
				local ok, px, w, h = pcall(decode, c)
				inflated = true
				if not ok then
					continue -- unreadable: skip it
				end
				c.px, c.w, c.h = px, w, h
			end
			if not show(c) then
				holdUntil = os.clock() + RETRY_SEC
				warn("[TownRenderer] the image budget is full; close-up town art waits (the overview stays)")
				break
			end
			if (os.clock() - t0) * 1000 > SHOW_MS then
				break
			end
		end
		-- then, with time to spare, inflate the next chunk just outside the view, ready for panning
		if not inflated and (os.clock() - t0) * 1000 < SHOW_MS then
			for c in keep do
				if not c.px and not c.image then
					local ok, px, w, h = pcall(decode, c)
					if ok then
						c.px, c.w, c.h, c.used = px, w, h, clock
					end
					break
				end
			end
		end
		trimPixels()
	end)
	return overviewOk
end

return TownRenderer
