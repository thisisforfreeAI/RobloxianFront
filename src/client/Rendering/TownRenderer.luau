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
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=ImageMemory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Inflate = require(Shared.Utilities.Inflate)
local ImagePixels = require(Shared.Presentation.ImagePixels)
local TownDetail = require(Shared.Presentation.TownDetail)
local TownPatch = require(Shared.Presentation.TownPatch)
local TownLods = require(Shared.Presentation.TownLods)
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
local diagnostics:any=nil
function TownRenderer.stats():any return if diagnostics then diagnostics() else nil end
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
local MAX_LOADED = 32 -- bounded visible coverage; aggregate LOD still obeys the same image budget
local CHECK_SEC = 0.1
local RETRY_SEC = 1.5 -- after the budget refused an image
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
	return ImageMemory.create(size, kind or "terrain")
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
	local groundKnown:any={};local groundKnownTones:any={};local groundConfig:any=nil;local groundSource:any=nil
	local function applyGround(buckets:any,config:any,source:any?)
		-- A matching tree-free bake is required to preserve trees above scars and restore cleanly.
		if not forest then return end
		local values,tones={},{};for _,b in buckets do for cell,value in b.cells do values[cell]=value;tones[cell]=if b.tones then b.tones[cell] or 0 else 0 end end
		if next(values)~=nil then
			if not source or source.width~=mapW or source.height~=mapH or source.tileSize~=TILE_PX then return end
			groundSource,groundConfig=source,config
		end
		local function update(cell,value)
			local x,y=cell%mapW,math.floor(cell/mapW)
			for _,c in chunks do if x>=c.cx and y>=c.cy and x<c.cx+c.cw and y<c.cy+c.ch then
				local chunk=c :: any;chunk.groundScars=chunk.groundScars or {};chunk.groundScars[cell]=if value>0 then value else nil
				chunk.groundTones=chunk.groundTones or {};chunk.groundTones[cell]=if value>0 then tones[cell] else nil
				chunk.forestDirty=true;break
			end end
		end
		for cell in groundKnown do if not values[cell] then update(cell,0) end end
		for cell,value in values do if groundKnown[cell]~=value or groundKnownTones[cell]~=tones[cell] then update(cell,value) end end
		groundKnown,groundKnownTones=values,tones
		if next(groundKnown)==nil then groundConfig,groundSource=nil,nil end
	end
	groundApply=applyGround
	local function sample(x:number,y:number):{number}?
		for _,c in chunks do
			local pixels=c.px or (c :: any).preview
			if pixels and x>=c.cx and y>=c.cy and x<c.cx+c.cw and y<c.cy+c.ch then
				local w,h=if c.px then c.w else c.iw,if c.px then c.h else c.ih
				local px,py=math.floor((x-c.cx)*w/c.cw),math.floor((y-c.cy)*h/c.ch)
				local at=(py*w+px)*4
				if at+3<buffer.len(pixels) and buffer.readu8(pixels,at+3)>0 then
					return {buffer.readu8(pixels,at),buffer.readu8(pixels,at+1),buffer.readu8(pixels,at+2)}
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
		if scars and next(scars) and groundSource then ScorchPixels.apply(px,c.cx,c.cy,c.cw,c.ch,TILE_PX,mapW,scars,groundConfig,groundSource.roof,(c :: any).groundTones) end
		return ForestRaster.paint(forest,px,c.cx,c.cy,c.cw,c.ch,fates)
	end
	local mipHits,mipMisses=0,0
	local function dynamic(c:Chunk):boolean
		local dynamic=(c :: any).groundScars and next((c :: any).groundScars)~=nil or false
		if forest then for _,t in forest.inWindow(c.cx,c.cy,c.cw,c.ch) do if fates[t.key] then dynamic=true;break end end end
		return dynamic
	end
	local function fastPixels(c:Chunk,stride:number,frame:number):buffer?
		if stride<2 or dynamic(c) then return nil end
		local cached=(c :: any).prefetched
		if cached and cached.stride==stride and cached.frame==frame then (c :: any).prefetched=nil;mipHits+=1;return cached.pixels end
		local name=c.name.."_Mip"..stride
		local module=assets:FindFirstChild(name);if not module then return nil end
		local key=name..":"..frame
		local state=c :: any;state.lodFailed=state.lodFailed or {};if state.lodFailed[key] then return nil end
		local ok,px=pcall(function()
			local source=require(c.mod);state.lodSourceHash=state.lodSourceHash or TownLods.signature(source.deflate)
			state.lodPatchHashes=state.lodPatchHashes or {}
			local hash=state.lodPatchHashes[frame]
			if not hash then
				local patch=if frame==baseFrame then nil else assets:FindFirstChild(c.name.."_Light"..frame)
				if frame~=baseFrame and not patch then return nil end
				hash=TownLods.signature(if patch then require(patch).deflate or "" else "");state.lodPatchHashes[frame]=hash
			end
			return TownLods.decode(require(module),stride,frame,source.width,source.height,state.lodSourceHash,hash,function(text,bytes)
				return Inflate.raw(MapCodec.base64Decode(text),bytes)
			end,baseFrame)
		end)
		if not ok or not px then state.lodFailed[key]=true;mipMisses+=1;return nil end
		mipHits+=1;return px
	end
	local function decode(c: Chunk,frame:number?): (buffer, number, number)
		(c :: any).prefetched=nil
		(c :: any).warmPixels=nil
		local dynamic=dynamic(c)
		;(c :: any).dynamicForest=dynamic
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
		if not c.px then
			local stride=if c.iw>0 then math.round(c.w/c.iw) else 1
			local fast=fastPixels(c,stride,frame)
			if fast then (c :: any).preview=fast;c.frame=frame;c.patch=nil;c.missed=nil;appearanceRevision+=1;return end
			local ok,px,w,h=pcall(decode,c,frame)
			if not ok then c.missed=frame;return end
			c.px,c.w,c.h,c.patch=px,w,h,nil;c.frame=if (c :: any).dynamicForest then frame else baseFrame
			appearanceRevision+=1
			if c.frame==frame then return end
		end
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
		if not c.px then
			local preview=(c :: any).preview;assert(preview and buffer.len(preview)==math.ceil(c.w/stride)*math.ceil(c.h/stride)*4,"missing town pixels")
			return preview
		end
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
	local pooledBytes = 0
	local alive = true
	local warming:any=nil
	local function startWarm(c:Chunk)
		if warming then return end
		local job:any={chunk=c,produced=0}
		job.thread=coroutine.create(function()
			local source=require(c.mod);local encoded=c.packed or MapCodec.base64Decode(source.deflate);c.packed=encoded
			local began=os.clock()
			local px=Inflate.raw(encoded,source.width*source.height*4,function(produced)
				job.produced=produced
				if os.clock()-began>=.002 then coroutine.yield();began=os.clock() end
			end)
			return {pixels=px,w=source.width,h=source.height}
		end)
		warming=job
	end
	local clock = 0
	local wantedCount,visibleCount,targetStride=0,0,0
	local wantedChunks:any={}
	local function stats()
		local shown,pending,ready,sourceBytes,previewBytes,prefetchBytes,nativeBytes=0,0,0,0,0,0,pooledBytes
		for _,c in chunks do
			if c.part then shown+=1 elseif c.image then pending+=1 end
			if c.part and wantedChunks[c] then ready+=1 end
			if c.image then nativeBytes+=c.iw*c.ih*4 end
			local old=(c :: any).retiring;if old then nativeBytes+=old.iw*old.ih*4;if old.preview then previewBytes+=buffer.len(old.preview) end end
			if c.px then sourceBytes+=buffer.len(c.px) end
			if (c :: any).warmPixels then sourceBytes+=buffer.len((c :: any).warmPixels.pixels) end
			if (c :: any).preview then previewBytes+=buffer.len((c :: any).preview) end
			if (c :: any).prefetched then prefetchBytes+=buffer.len((c :: any).prefetched.pixels) end
		end
		return {visible=visibleCount,selected=wantedCount,ready=ready,shown=shown,pending=pending,stride=targetStride,nativeBytes=nativeBytes,sourceBytes=sourceBytes,previewBytes=previewBytes,prefetchBytes=prefetchBytes,mipHits=mipHits,mipMisses=mipMisses,warming=warming~=nil,warmProduced=if warming then warming.produced else 0}
	end
	diagnostics=stats
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
		local accepted=upload(overview,Vector2.new(x,y),Vector2.new(w,h),pixels,{priority=1,key=x..":"..y,done=function(ok)
			if ok and alive then (c :: any).overviewShown=not covered end
		end})
		;(c :: any).overviewRetry=if accepted then nil else covered
	end
	local function unload(c: Chunk,discard:boolean?)
		local old=(c :: any).retiring
		if old then old.part:Destroy();ImageMemory.release(old.image);(c :: any).retiring=nil;coverOverview(c,false) end
		if c.image and ImageMemory.cancelUploads then ImageMemory.cancelUploads(c.image) end
		(c :: any).uploading=nil
		(c :: any).preview=nil
		if c.part then
			c.part:Destroy()
			c.part = nil
			coverOverview(c, false)
		end
		if c.image then
			-- Full source pixels stay in the bounded CPU cache; native images may be half-size.
			c.used = clock
			local k = sizeKey(c.iw, c.ih)
			if not discard and pooled < POOL_MAX then
				pool[k] = pool[k] or {}
				table.insert(pool[k], c.image)
				pooled += 1
				pooledBytes += c.iw*c.ih*4
			else
				ImageMemory.release(c.image)
			end
			c.image = nil
			loaded -= 1
		end
	end
	local function retire(c:Chunk)
		if not c.part or not c.image then unload(c);return end
		if ImageMemory.cancelUploads then ImageMemory.cancelUploads(c.image) end
		(c :: any).retiring={part=c.part,label=(c :: any).label,image=c.image,iw=c.iw,ih=c.ih,preview=(c :: any).preview}
		c.part,c.image=nil,nil;(c :: any).preview=nil;loaded-=1
	end
	local function rollback(c:Chunk)
		local old=(c :: any).retiring;(c :: any).retiring=nil
		unload(c,true)
		if old then c.part,c.image,c.iw,c.ih=old.part,old.image,old.iw,old.ih;(c :: any).label=old.label;(c :: any).preview=old.preview;loaded+=1 end
	end
	local function writeChunk(c:Chunk,pixels:buffer,priority:number):boolean
		local image=c.image;if not image then return false end
		return upload(image,Vector2.zero,Vector2.new(c.iw,c.ih),pixels,{priority=priority,done=function(ok)
			if not alive or c.image~=image then return end
			(c :: any).uploading=nil
			if not ok then rollback(c);return end
			(c :: any).preview=if c.iw<c.w then pixels else nil
			if not c.part then
				local size=Vector2.new(c.iw,c.ih)
				local old=(c :: any).retiring
				if old then
					old.label.Parent.CanvasSize=size;old.label.ImageContent=Content.fromObject(image)
					c.part=old.part;(c :: any).label=old.label;(c :: any).retiring=nil;ImageMemory.release(old.image)
				else
					local part,label=imagePart(c.name,c.cx,c.cy,c.cw,c.ch,size,HEIGHT+.01,true)
					label.ImageContent=Content.fromObject(image);part.Parent=folder;c.part=part;(c :: any).label=label;coverOverview(c,true)
				end
			end
		end})
	end
	local function takeImage(w: number, h: number): any
		local list = pool[sizeKey(w, h)]
		if list and #list > 0 then
			pooled -= 1
			pooledBytes -= w*h*4
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
			pooledBytes = 0
			image = newImage(Vector2.new(w, h))
		end
		return image
	end
	-- drop the least recently used inflated pixels beyond the cache size
	local function trimPixels()
		local spare: { Chunk } = {}
		for _, c in chunks do
			if (c.px or (c :: any).prefetched or (c :: any).warmPixels) and (not c.image or c.iw<c.w) then
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
			(spare[i] :: any).prefetched=nil
			(spare[i] :: any).warmPixels=nil
			appearanceRevision+=1
			spare[i].patch=nil
			if not spare[i].image then spare[i].frame=baseFrame end
		end
	end
	-- returns false when the budget refused the image
	local function show(c: Chunk, stride: number,ready:buffer?): boolean
		-- Admission may reclaim inactive CPU caches as well as native detail. Keep this chunk's
		-- full source and reversible patch alive until it becomes a shown chunk.
		local source, oldPatch, oldFrame = c.px, c.patch, c.frame
		local iw, ih = math.ceil(c.w / stride), math.ceil(c.h / stride)
		local image = takeImage(iw, ih)
		while not image and stride < 4 do
			if ready then ready=ImagePixels.half(ready,iw,ih) end
			stride *= 2
			iw, ih = math.ceil(c.w / stride), math.ceil(c.h / stride)
			image = takeImage(iw, ih)
		end
		if not image then rollback(c);return false end
		c.px, c.patch, c.frame = source, oldPatch, oldFrame
		c.image,c.iw,c.ih=image,iw,ih;(c :: any).uploading=true
		loaded += 1
		local ok,accepted=pcall(writeChunk,c,ready or pixelsAt(c,stride),1)
		if not ok or not accepted then rollback(c);return false end
		return true
	end
	local function drainPool()
		for _, list in pool do
			for _, image in list do ImageMemory.release(image) end
			table.clear(list)
		end
		pooled = 0
		pooledBytes = 0
	end
	-- Core image pressure first drops optional layers (10) and unused art (20).
	local unregister = ImageMemory.register(30, function(needed: number, _protected: any)
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
		alive=false
		warming=nil
		if diagnostics==stats then diagnostics=nil end
		if sampler==sample then sampler=nil end
		if forestMap==forest then forestMap=nil end
		if forestApply==applyForest then forestApply=nil end
		if coverSampler==sampleCover then coverSampler=nil end
		if groundApply==applyGround then groundApply=nil end
		appearanceRevision+=1;table.clear(bareCache);table.clear(bareOrder)
		groundKnown,groundKnownTones={},{};groundConfig,groundSource=nil,nil
		table.clear(covers);table.clear(coverOrder)
		if connection then connection:Disconnect() end
		unregister()
		for _, c in chunks do if c.image then unload(c) end end
		for _,c in chunks do c.px=nil;c.patch=nil;(c :: any).preview=nil;(c :: any).prefetched=nil;(c :: any).warmPixels=nil end
		drainPool(); ImageMemory.release(overview)
	end)
	local warnedPressure = false
	local acc = 0
	local zoomStride = 0
	local paintedLast = false
	local lastX,lastY,lastAt=nil,nil,nil
	local lastCellPixels,steadySince,lastUpgrade=nil,0,-math.huge
	connection = RunService.Heartbeat:Connect(function(dt)
		-- One cooperative static-source warmup per frame; keep its existing native preview bound.
		if warming then
			local job=warming;local c=job.chunk
			if not wantedChunks[c] or dynamic(c) then warming=nil
			else
				local ok,result=coroutine.resume(job.thread)
				if not ok then warming=nil;(c :: any).warmFailed=true;warn("[TownRenderer] Full source warmup failed; preview stays:",result)
				elseif coroutine.status(job.thread)=="dead" then (c :: any).warmPixels=result;warming=nil end
			end
		end
		acc += dt
		if acc < CHECK_SEC then
			return
		end
		acc = 0
		clock += 1
		for _,c in chunks do
			if (c :: any).overviewRetry~=nil then
				local covered=(c :: any).overviewRetry;(c :: any).overviewRetry=nil;coverOverview(c,covered)
			end
		end
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
		local ry=dist*tanHalf/S*1.08;local rx=ry*cam.ViewportSize.X/math.max(1,cam.ViewportSize.Y)
		local now=os.clock();local px,py=TownDetail.predict(fx,fy,lastX,lastY,if lastAt then now-lastAt else 0,rx,ry)
		if not lastX or math.abs(fx-lastX)>.05 or math.abs(fy-lastY)>.05 or lastCellPixels and math.abs(cellPx-lastCellPixels)>lastCellPixels*.03 then steadySince=now end
		lastX,lastY,lastAt=fx,fy,now
		lastCellPixels=cellPx
		local want,keep,prefetch,seen={},{},{},0
		if detail then want,keep,prefetch,seen=TownDetail.plan(chunks,fx,fy,rx,ry,MAX_LOADED,px,py) end
		wantedCount,visibleCount=#want,seen
		wantedChunks={};for _,c in want do wantedChunks[c]=true end
		local allReady=true;for _,c in want do if not c.part then allReady=false;break end end
		-- One changed source chunk per check, including the far overview. Reuse native images.
		local dirty:any=nil
		for _,c in chunks do if (c :: any).forestDirty and (not dirty or c.distance<dirty.distance) then dirty=c end end
		local missing=false
		if detail then for _,c in want do if not c.image then missing=true;break end end end
		-- Changing fires/scars cannot occupy every check while camera-visible detail is missing.
		if dirty and (not missing or not paintedLast) then
			paintedLast=true
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
					local wrote,accepted=pcall(writeChunk,dirty,pixelsAt(dirty,math.round(w/dirty.iw)),if dirty.part then 2 else 1)
					if not wrote then unload(dirty);drainPool() end
					if wrote and not accepted then dirty.forestDirty=true end
				end
				coverOverview(dirty,dirty.part~=nil);trimPixels()
			else
				dirty.forestDirty=nil
				if not warnedForest then warnedForest=true;warn("[TownRenderer] Forest repaint unavailable:",px) end
			end
			return
		end
		paintedLast=false
		if detail and #want>0 and ImageMemory.detailHeadroom then
			local held=pooledBytes;local visibleHeld=0;local visible={}
			for _,c in want do visible[c]=true;if c.image then visibleHeld+=c.iw*c.ih*4 end end
			for _,c in chunks do if c.image then held+=c.iw*c.ih*4 end;local old=(c :: any).retiring;if old then held+=old.iw*old.ih*4 end end
			local allowance=ImageMemory.detailHeadroom(held)
			stride=TownDetail.fitStride(stride,want,TILE_PX,allowance)
			if TownDetail.bytes(want,stride,TILE_PX)>ImageMemory.detailHeadroom(visibleHeld) then
				-- Native overscan/spares yield before a camera-visible chunk is left on the overview.
				for _,c in chunks do if c.image and not visible[c] then unload(c) end end
				drainPool()
			end
		end
		targetStride=if detail then stride else 0
		-- Free oversized allocations first, then fill missing detail, then refresh existing shade.
		table.sort(want,function(a,b)
			local function priority(c)
				if c.image and c.iw>math.ceil(c.cw*TILE_PX/stride) then return 0 end
				return if c.image then 2 else 1
			end
			local pa,pb=priority(a),priority(b)
			if pa~=pb then return pa<pb end
			if a.distance~=b.distance then return a.distance<b.distance end
			return (a.cx+a.cw/2-fx)^2+(a.cy+a.ch/2-fy)^2<(b.cx+b.cw/2-fx)^2+(b.cy+b.ch/2-fy)^2
		end)
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
			if (c :: any).retiring then continue end -- keep one transition intact through rapid zoom changes
			local upgrading=false
			if c.image then
				local targetW, targetH = math.ceil(c.w / stride), math.ceil(c.h / stride)
				if targetW < c.iw then
					if ImageMemory.canDetail(Vector2.new(targetW,targetH)) then retire(c)
					elseif c.part and not (c :: any).overviewShown then coverOverview(c,false);continue
					else unload(c);drainPool() end
				elseif targetW>c.iw and allReady and now-steadySince>=.35 and now-lastUpgrade>=.35
					and ImageMemory.canDetail(Vector2.new(targetW,targetH)) then
					if not c.px and not dynamic(c) then
						local warm=(c :: any).warmPixels
						if warm then c.px,c.w,c.h,c.frame,c.patch=warm.pixels,warm.w,warm.h,baseFrame,nil;(c :: any).warmPixels=nil
						elseif not (c :: any).warmFailed then startWarm(c);continue
						else continue end -- a bad optional source must not destroy the working preview
					end
					lastUpgrade=now
					upgrading=true
					retire(c)
				elseif c.frame ~= frame and c.missed ~= frame then
					relight(c, frame)
					if not c.px and not (c :: any).preview then break end
					local shownStride = math.round(c.w / c.iw)
					local ok,accepted=pcall(writeChunk,c,pixelsAt(c,shownStride),if c.part then 2 else 1)
					if not ok then unload(c); drainPool() end
					if ok and not accepted then c.missed=nil;c.frame=-1 end
					break -- at most one shadow refresh per check; nearest chunks first
				else
					continue
				end
			end
			local ready:buffer?=nil
			local initialStride=stride
			if not c.px and not upgrading then
				initialStride=math.max(2,stride)
				ready=fastPixels(c,initialStride,frame)
				if ready then
					c.w,c.h,c.frame,c.patch=c.cw*TILE_PX,c.ch*TILE_PX,frame,nil
				end
			end
			if not c.px and not ready then
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
			if not ready then relight(c, frame) end
			if not show(c,if ready then initialStride else stride,ready) then
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
			for _,c in prefetch do
				local cached=(c :: any).prefetched;local prefetchStride=math.max(2,stride)
				if not c.px and not c.image and (not cached or cached.frame~=frame or cached.stride~=prefetchStride) then
					local fast=fastPixels(c,prefetchStride,frame)
					if fast then (c :: any).prefetched={pixels=fast,stride=prefetchStride,frame=frame};c.used=clock
					else
						local ok,px,w,h=pcall(decode,c)
						if ok then c.px,c.w,c.h,c.used=px,w,h,clock;appearanceRevision+=1 end
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
