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
	Optional sparse lighting patches move roof shadows through the source sun/moon path, reusing each
	image. APPROX: sampled directions and a fixed-noon overview; tree shadows remain baked.
]]
local ImageMemory = require(script.Parent.ImageMemory)
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Inflate = require(Shared.Utilities.Inflate)
local ImagePixels = require(Shared.Presentation.ImagePixels)
local TownDetail = require(Shared.Presentation.TownDetail)
local TownPatch = require(Shared.Presentation.TownPatch)
local ForestMap = require(Shared.Simulation.ForestMap)
local ForestRaster = require(Shared.Presentation.ForestRaster)
local ScorchPixels = require(Shared.Presentation.GroundScorchPixels)
local DaylightController = require(script.Parent.DaylightController)

local TownRenderer = {}
local sampler: any = nil
local forestMap: any = nil
local forestApply: any = nil
local coverSampler: any = nil
local groundApply: any = nil
local appearanceRevision=0
function TownRenderer.revision():number return appearanceRevision end
function TownRenderer.getForestMap():any return forestMap end
function TownRenderer.setForestFates(rows:{any},reset:boolean?) if forestApply then forestApply(rows,reset) end end
function TownRenderer.setGroundScorch(buckets:any,config:any,source:any?) if groundApply then groundApply(buckets,config,source) end end
-- Tree/shadow foreground used to keep roof damage beneath the same current forest art.
function TownRenderer.forestCover(cx:number,cy:number,cw:number,ch:number):buffer?
	return if coverSampler then coverSampler(cx,cy,cw,ch) else nil
end
-- CPU source pixels already carry the currently sampled roof shade; this allocates no images.
function TownRenderer.sample(x:number,y:number):{number}?
	return if sampler then sampler(x,y) else nil
end

local S = World.STUDS_PER_CELL
local HEIGHT = 0.07 -- above the ground (0), under the roads (0.15)
local OVERVIEW_PX = 2 -- overview pixels a cell
local TILE_PX = 14 -- chunk pixels a cell (the game's 14 px town tiles)
local MAX_LOADED = 9 -- full chunks shown at once
local CHECK_SEC = 0.1
local RETRY_SEC = 1.5 -- after the budget refused an image
local KEEP_REACH = 1.6 -- shown chunks stay until this far past the view (so panning back is instant)
local PIXEL_CACHE = 6 -- chunk pixels kept in memory for chunks not shown (3.2 MB each)
local SHOW_MS = 6 -- per check, time spent showing chunks whose pixels are ready
local POOL_MAX = 1 -- spare images kept for reuse instead of asking the budget again

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

local function newImage(size: Vector2, kind: string?): any
	return ImageMemory.create(size, kind or "detail")
end

type Chunk = { cx: number, cy: number, cw: number, ch: number, name: string, mod: ModuleScript, part: Part?, image: any, packed: buffer?, px: buffer?, w: number, h: number, iw: number, ih: number, distance: number, used: number, frame: number, patch: buffer?, missed: number? }

-- returns true when the town art was drawn
function TownRenderer.build(mapId: string, parent: Instance): boolean
	appearanceRevision+=1
	sampler=nil
	forestMap,forestApply,coverSampler,groundApply=nil,nil,nil,nil
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local metaModule = assets and assets:FindFirstChild("City_" .. mapId)
	if not metaModule or not metaModule:IsA("ModuleScript") then
		return false
	end
	local meta = require(metaModule) :: any
	local lighting = meta.lighting
	local baseFrame = if lighting then lighting.base else 0
	local folder = Instance.new("Folder")
	folder.Name = "Towns"
	local chunks: { Chunk } = {}
	local mapW, mapH = 0, 0
	for _, c in meta.chunks do
		local mod = assets:FindFirstChild(c[5])
		if mod and mod:IsA("ModuleScript") then
			table.insert(chunks, { cx = c[1], cy = c[2], cw = c[3], ch = c[4], name = c[5], mod = mod, part = nil, image = nil, packed = nil, px = nil, w = 0, h = 0, iw = 0, ih = 0, distance = math.huge, used = 0, frame = baseFrame, patch = nil })
			mapW, mapH = math.max(mapW, c[1] + c[3]), math.max(mapH, c[2] + c[4])
		else
			warn(`[TownRenderer] {c[5]} missing, that part of the map has no towns drawn`)
		end
	end
	if #chunks == 0 then
		return false
	end
	local forest:any=nil
	local fates:any={}
	local affected:any={}
	local covers:any={};local coverOrder={};local coverDisabled=false
	local warnedForest=false
	if meta.forest then
		local data=Shared:FindFirstChild("GameData")
		local module=data and data:FindFirstChild(meta.forest)
		if module then
			local ok,value=pcall(function()
				return ForestMap.new(require(module),function(encoded,bytes) return Inflate.raw(MapCodec.base64Decode(encoded),bytes) end,function(name)
					local page=data:FindFirstChild(name);assert(page,"missing local forest sprite page");return require(page)
				end)
			end)
			if ok then
				forest=value;forestMap=forest
				for _,c in chunks do for _,t in forest.inWindow(c.cx,c.cy,c.cw,c.ch) do
					local list=affected[t.key];if not list then list={};affected[t.key]=list end;table.insert(list,c)
				end end
			else warn("[TownRenderer] Dynamic forest data unavailable:",value) end
		end
	end
	local function applyForest(rows:{any},reset:boolean?)
		if not forest then return end
		local changed={}
		if reset then for key in fates do changed[key]=true end;table.clear(fates) end
		for _,row in rows do
			local key,fate=row[1],row[2];if not forest.byKey[key] then continue end
			fates[key]=fate;changed[key]=true
		end
		for key in changed do for _,c in affected[key] or {} do (c :: any).forestDirty=true end end
		if next(changed)~=nil then
			appearanceRevision+=1
			for i=#coverOrder,1,-1 do
				local key=coverOrder[i];local cover=covers[key]
				for tree in changed do if cover.members[tree] then covers[key]=nil;table.remove(coverOrder,i);break end end
			end
		end
	end
	forestApply=applyForest
	local function sampleCover(cx:number,cy:number,cw:number,ch:number):buffer?
		if not forest or coverDisabled then return nil end
		local key=cx..":"..cy..":"..cw..":"..ch
		if covers[key] then return covers[key].px end
		local ok,px=pcall(function()
			return ForestRaster.paint(forest,buffer.create(cw*ch*TILE_PX*TILE_PX*4),cx,cy,cw,ch,fates)
		end)
		if not ok then coverDisabled=true;warn("[TownRenderer] Forest roof cover unavailable:",px);return nil end
		-- APPROX: bounded CPU-only cache, independent of the native image budget; reset on tree fates.
		if #coverOrder>=24 then covers[table.remove(coverOrder,1)]=nil end
		local members={};for _,t in forest.inWindow(cx,cy,cw,ch) do members[t.key]=true end
		covers[key]={px=px,members=members};table.insert(coverOrder,key);return px
	end
	coverSampler=sampleCover
	local groundKnown:any={};local groundConfig:any=nil;local groundSource:any=nil
	local function applyGround(buckets:any,config:any,source:any?)
		-- A matching tree-free bake is required to preserve trees above scars and restore cleanly.
		if not forest then return end
		local values={};for _,b in buckets do for cell,value in b.cells do values[cell]=value end end
		if next(values)~=nil then
			if not source or source.width~=mapW or source.height~=mapH or source.tileSize~=TILE_PX then return end
			groundSource,groundConfig=source,config
		end
		local function update(cell,value)
			local x,y=cell%mapW,math.floor(cell/mapW)
			for _,c in chunks do if x>=c.cx and y>=c.cy and x<c.cx+c.cw and y<c.cy+c.ch then
				local chunk=c :: any;chunk.groundScars=chunk.groundScars or {};chunk.groundScars[cell]=if value>0 then value else nil
				chunk.forestDirty=true;break
			end end
		end
		for cell in groundKnown do if not values[cell] then update(cell,0) end end
		for cell,value in values do if groundKnown[cell]~=value then update(cell,value) end end
		groundKnown=values
		if next(groundKnown)==nil then groundConfig,groundSource=nil,nil end
	end
	groundApply=applyGround
	local function sample(x:number,y:number):{number}?
		for _,c in chunks do
			if c.px and x>=c.cx and y>=c.cy and x<c.cx+c.cw and y<c.cy+c.ch then
				local px,py=math.floor((x-c.cx)*TILE_PX),math.floor((y-c.cy)*TILE_PX)
				local at=(py*c.w+px)*4
				if at+3<buffer.len(c.px) and buffer.readu8(c.px,at+3)>0 then
					return {buffer.readu8(c.px,at),buffer.readu8(c.px,at+1),buffer.readu8(c.px,at+2)}
				end
			end
		end
		return nil
	end
	sampler=sample
	-- Repeated fire/ground updates reuse a clean base instead of inflating the same 3 MB chunk.
	-- Two CPU-only bases are retained; every paint clones one before applying reversible changes.
	local bareCache:any={};local bareOrder={}
	-- the compressed bytes stay cached (small); inflating is the slow part
	local function forestPixels(c:Chunk,frame:number):buffer
		local base=bareCache[c.name]
		if not base then
			local module=assets:FindFirstChild(c.name.."_Bare");assert(module,"missing tree-free town chunk")
			local bare=require(module)
			assert(bare.width==c.cw*TILE_PX and bare.height==c.ch*TILE_PX,"tree-free chunk dimensions differ")
			base=Inflate.raw(MapCodec.base64Decode(bare.deflate),bare.width*bare.height*4)
			if #bareOrder>=2 then bareCache[table.remove(bareOrder,1)]=nil end
			bareCache[c.name]=base;table.insert(bareOrder,c.name)
		end
		local px=buffer.create(buffer.len(base));buffer.copy(px,0,base)
		if lighting and frame~=baseFrame then
			local patch=assets:FindFirstChild(c.name.."_BareLight"..frame);assert(patch,"missing tree-free lighting patch")
			local data=require(patch);local delta=if data.bytes==0 then buffer.create(0) else Inflate.raw(MapCodec.base64Decode(data.deflate),data.bytes)
			TownPatch.validate(delta,px);TownPatch.apply(px,delta)
		end
		local scars=(c :: any).groundScars
		if scars and next(scars) and groundSource then ScorchPixels.apply(px,c.cx,c.cy,c.cw,c.ch,TILE_PX,mapW,scars,groundConfig,groundSource.roof) end
		return ForestRaster.paint(forest,px,c.cx,c.cy,c.cw,c.ch,fates)
	end
	local function decode(c: Chunk,frame:number?): (buffer, number, number)
		local dynamic=(c :: any).groundScars and next((c :: any).groundScars)~=nil or false
		if forest then for _,t in forest.inWindow(c.cx,c.cy,c.cw,c.ch) do if fates[t.key] then dynamic=true;break end end end
		(c :: any).dynamicForest=dynamic
		if dynamic then return forestPixels(c,frame or baseFrame),c.cw*TILE_PX,c.ch*TILE_PX end
		local chunk = require(c.mod) :: any
		if not c.packed then
			c.packed = MapCodec.base64Decode(chunk.deflate)
		end
		return Inflate.raw(c.packed :: buffer, chunk.width * chunk.height * 4), chunk.width, chunk.height
	end
	local warnedLighting = false
	local function relight(c: Chunk, frame: number)
		if not lighting or c.frame == frame then return end
		if (c :: any).dynamicForest then
			local ok,px=pcall(forestPixels,c,frame)
			if ok then c.px=px;c.frame=frame;c.patch=nil;c.missed=nil;appearanceRevision+=1
			else c.missed=frame;if not warnedLighting then warnedLighting=true;warn("[TownRenderer] Forest lighting unavailable:",px) end end
			return
		end
		local ok, patch = pcall(function(): buffer
			if frame == baseFrame then return buffer.create(0) end
			local mod = assets:FindFirstChild(c.name .. "_Light" .. frame)
			assert(mod and mod:IsA("ModuleScript"), "local lighting patch missing")
			local data = require(mod :: ModuleScript) :: any
			local out = if data.bytes == 0 then buffer.create(0) else Inflate.raw(MapCodec.base64Decode(data.deflate), data.bytes)
			TownPatch.validate(out, c.px :: buffer)
			return out
		end)
		if not ok then
			c.missed = frame
			if not warnedLighting then
				warnedLighting = true
				warn("[TownRenderer] roof lighting unavailable; existing lighting stays:", patch)
			end
			return
		end
		if c.patch then TownPatch.apply(c.px :: buffer, c.patch) end -- undo the previous sample
		TownPatch.apply(c.px :: buffer, patch)
		c.patch, c.frame = patch, frame
		appearanceRevision+=1
	end
	local function pixelsAt(c: Chunk, stride: number): buffer
		local px, w, h = c.px :: buffer, c.w, c.h
		if stride >= 2 then px, w, h = ImagePixels.half(px, w, h) end
		if stride >= 4 then px = ImagePixels.half(px, w, h) end
		return px
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
	local overview = newImage(Vector2.new(ow, oh), "core")
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
	local function coverOverview(c: Chunk, covered: boolean)
		if not overviewOk then return end
		local w, h = c.cw * OVERVIEW_PX, c.ch * OVERVIEW_PX
		local x, y = c.cx * OVERVIEW_PX, c.cy * OVERVIEW_PX
		local pixels = buffer.create(w * h * 4)
		if not covered then
			for row = 0, h - 1 do buffer.copy(pixels, row * w * 4, overviewPixels, ((y + row) * ow + x) * 4, w * 4) end
		end
		-- Same overview image, with its noon pixels hidden below a shown chunk. Otherwise old
		-- ground shadows would remain visible through the newly lit chunk's transparent pixels.
		overview:WritePixelsBuffer(Vector2.new(x, y), Vector2.new(w, h), pixels)
	end
	local function unload(c: Chunk)
		if c.part then
			c.part:Destroy()
			c.part = nil
			coverOverview(c, false)
		end
		if c.image then
			-- Full source pixels stay in the bounded CPU cache; native images may be half-size.
			c.used = clock
			local k = sizeKey(c.iw, c.ih)
			if pooled < POOL_MAX then
				pool[k] = pool[k] or {}
				table.insert(pool[k], c.image)
				pooled += 1
			else
				ImageMemory.release(c.image)
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
					ImageMemory.release(im)
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
			appearanceRevision+=1
			spare[i].patch, spare[i].frame = nil, baseFrame
		end
	end
	-- returns false when the budget refused the image
	local function show(c: Chunk, stride: number): boolean
		-- Admission may reclaim inactive CPU caches as well as native detail. Keep this chunk's
		-- full source and reversible patch alive until it becomes a shown chunk.
		local source, oldPatch, oldFrame = c.px, c.patch, c.frame
		local iw, ih = math.ceil(c.w / stride), math.ceil(c.h / stride)
		local image = takeImage(iw, ih)
		while not image and stride < 4 do
			stride *= 2
			iw, ih = math.ceil(c.w / stride), math.ceil(c.h / stride)
			image = takeImage(iw, ih)
		end
		if not image then return false end
		c.px, c.patch, c.frame = source, oldPatch, oldFrame
		local size = Vector2.new(iw, ih)
		local ok = pcall(function()
			image:WritePixelsBuffer(Vector2.zero, size, pixelsAt(c, stride))
		end)
		if not ok then ImageMemory.release(image); return false end
		local part, label = imagePart(c.name, c.cx, c.cy, c.cw, c.ch, size, HEIGHT + 0.01, true)
		label.ImageContent = Content.fromObject(image)
		part.Parent = folder
		c.part, c.image, c.iw, c.ih = part, image, iw, ih
		coverOverview(c, true)
		loaded += 1
		return true
	end
	local function drainPool()
		for _, list in pool do
			for _, image in list do ImageMemory.release(image) end
			table.clear(list)
		end
		pooled = 0
	end
	local unregister = ImageMemory.register(10, function(needed: number, _protected: any)
		local before = ImageMemory.stats()
		drainPool()
		local used = ImageMemory.stats()
		if before - used >= needed then return end
		local shown = {}
		for _, c in chunks do if c.image then table.insert(shown, c) end end
		table.sort(shown, function(a, b) return a.distance > b.distance end)
		for _, c in shown do
			unload(c); drainPool()
			used = ImageMemory.stats()
			if before - used >= needed then break end
		end
		trimPixels()
	end)
	local connection: RBXScriptConnection? = nil
	folder.Destroying:Connect(function()
		if sampler==sample then sampler=nil end
		if forestMap==forest then forestMap=nil end
		if forestApply==applyForest then forestApply=nil end
		if coverSampler==sampleCover then coverSampler=nil end
		if groundApply==applyGround then groundApply=nil end
		appearanceRevision+=1;table.clear(bareCache);table.clear(bareOrder)
		groundKnown={};groundConfig,groundSource=nil,nil
		table.clear(covers);table.clear(coverOrder)
		if connection then connection:Disconnect() end
		unregister()
		for _, c in chunks do if c.image then unload(c) end end
		drainPool(); ImageMemory.release(overview)
	end)
	local warnedPressure = false
	local acc = 0
	local zoomStride = 0
	connection = RunService.Heartbeat:Connect(function(dt)
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
		for _, c in chunks do c.distance = far(c) end
		zoomStride = TownDetail.stride(cellPx, zoomStride)
		local stride = if zoomStride == 0 then 4 else zoomStride
		local detail = zoomStride ~= 0 or not overviewOk
		local frame = if lighting then TownDetail.frame(DaylightController.get().phase, lighting.sunUp, lighting.steps) else baseFrame
		-- One changed source chunk per check, including the far overview. Reuse native images.
		local dirty:any=nil
		for _,c in chunks do if (c :: any).forestDirty and (not dirty or c.distance<dirty.distance) then dirty=c end end
		if dirty then
			local paintedFrame=if dirty.image then frame else baseFrame
			local ok,px,w,h=pcall(decode,dirty,paintedFrame)
			if ok then
				dirty.px,dirty.w,dirty.h,dirty.frame,dirty.patch,dirty.missed=px,w,h,if dirty.dynamicForest then paintedFrame else baseFrame,nil,nil
				appearanceRevision+=1
				dirty.forestDirty=nil;dirty.used=clock
				local small=ForestRaster.overview(px,w,h,TILE_PX,OVERVIEW_PX)
				local sw,sh=dirty.cw*OVERVIEW_PX,dirty.ch*OVERVIEW_PX
				for row=0,sh-1 do buffer.copy(overviewPixels,((dirty.cy*OVERVIEW_PX+row)*ow+dirty.cx*OVERVIEW_PX)*4,small,row*sw*4,sw*4) end
				if dirty.image then
					relight(dirty,frame)
					local wrote=pcall(function() dirty.image:WritePixelsBuffer(Vector2.zero,Vector2.new(dirty.iw,dirty.ih),pixelsAt(dirty,math.round(w/dirty.iw))) end)
					if not wrote then unload(dirty);drainPool() end
				end
				coverOverview(dirty,dirty.image~=nil);trimPixels()
			else
				dirty.forestDirty=nil
				if not warnedForest then warnedForest=true;warn("[TownRenderer] Forest repaint unavailable:",px) end
			end
			return
		end
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
				local targetW, targetH = math.ceil(c.w / stride), math.ceil(c.h / stride)
				if targetW < c.iw then
					unload(c); drainPool() -- return the larger allocation before creating the smaller one
				elseif targetW > c.iw and ImageMemory.canDetail(Vector2.new(targetW, targetH)) then
					unload(c); drainPool()
				elseif c.frame ~= frame and c.missed ~= frame then
					relight(c, frame)
					local shownStride = math.round(c.w / c.iw)
					local ok = pcall(function()
						c.image:WritePixelsBuffer(Vector2.zero, Vector2.new(c.iw, c.ih), pixelsAt(c, shownStride))
					end)
					if not ok then unload(c); drainPool() end
					break -- at most one shadow refresh per check; nearest chunks first
				else
					continue
				end
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
				appearanceRevision+=1
			end
			relight(c, frame)
			if not show(c, stride) then
				holdUntil = os.clock() + RETRY_SEC
				if not warnedPressure then
					warnedPressure = true
					warn("[TownRenderer] detail is limited by image memory; unit art takes priority, overview stays")
				end
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
						appearanceRevision+=1
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
