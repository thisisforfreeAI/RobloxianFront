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
function TownRenderer.stats(detailed:boolean?):any return if diagnostics then diagnostics(detailed) else nil end
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

local function newImage(size: Vector2, kind: string?,previous:any?): any
	local image=ImageMemory.create(size, kind or "terrain")
	if not image and previous and ImageMemory.replaceTerrain then image=ImageMemory.replaceTerrain(size,previous) end
	return image
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
	local paintEpoch=0
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
	local function markDirty(c:any)
		c.forestDirty=true;c.contentVersion=(c.contentVersion or 0)+1
	end
	local function sameFate(a:any,b:any):boolean
		if not a or not b then return a==b end
		return a.kind==b.kind and a.char==b.char and a.rot==b.rot
	end
	local function applyForest(rows:{any},reset:boolean?)
		if not forest then return end
		if reset then paintEpoch+=1 end
		local before={};local touched={}
		if reset then before=fates;for key in before do touched[key]=true end;fates={} end
		for _,row in rows do
			local key,fate=row[1],row[2];if not forest.byKey[key] then continue end
			if not touched[key] then before[key]=fates[key];touched[key]=true end
			-- Own the fields used by the raster; packet tables can be reused or mutated by callers.
			fates[key]=if fate then {kind=fate.kind,char=fate.char,rot=fate.rot} else nil
		end
		local changed={};local dirty={}
		for key in touched do if not sameFate(before[key],fates[key]) then
			changed[key]=true;for _,c in affected[key] or {} do dirty[c]=true end
		end end
		for c in dirty do markDirty(c) end
		if reset then for _,c in chunks do
			if (c :: any).contentVersion and (c :: any).pixelVersion~=(c :: any).contentVersion then (c :: any).forestDirty=true end
		end end -- An explicit reset can retry pixels left behind by an earlier rendering failure.
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
				markDirty(chunk);break
			end end
		end
		if next(groundKnown)~=nil and next(values)==nil then paintEpoch+=1 end
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
	local preparePaint:any=nil
	local preparedPaint:any=nil
	local fastPixels:any=nil
	local prepareMip:any=nil
	local function cacheBare(c:Chunk,base:buffer)
		if bareCache[c.name] then return end
		if #bareOrder>=2 then bareCache[table.remove(bareOrder,1)]=nil end
		bareCache[c.name]=base;table.insert(bareOrder,c.name)
	end
	-- the compressed bytes stay cached (small); inflating is the slow part
	local function forestPixels(c:Chunk,frame:number,checkpoint:any?,snapshot:any?,phase:any?):buffer
		local base=bareCache[c.name]
		if not base then
			if phase then phase("bare") end
			local module=assets:FindFirstChild(c.name.."_Bare");assert(module,"missing tree-free town chunk")
			local bare=require(module)
			assert(bare.width==c.cw*TILE_PX and bare.height==c.ch*TILE_PX,"tree-free chunk dimensions differ")
			base=Inflate.raw(MapCodec.base64Decode(bare.deflate,checkpoint),bare.width*bare.height*4,checkpoint)
			cacheBare(c,base)
		end
		if phase then phase("damage") end
		local px=buffer.create(buffer.len(base));buffer.copy(px,0,base)
		if lighting and frame~=baseFrame then
			local patch=assets:FindFirstChild(c.name.."_BareLight"..frame);assert(patch,"missing tree-free lighting patch")
			local data=require(patch);local delta=if data.bytes==0 then buffer.create(0) else Inflate.raw(MapCodec.base64Decode(data.deflate,checkpoint),data.bytes,checkpoint)
			TownPatch.apply(px,delta,checkpoint) -- apply validates the entire delta before mutating.
		end
		local scars=if snapshot then snapshot.scars else (c :: any).groundScars
		local source=if snapshot then snapshot.source else groundSource
		if scars and next(scars) and source then ScorchPixels.apply(px,c.cx,c.cy,c.cw,c.ch,TILE_PX,mapW,scars,if snapshot then snapshot.config else groundConfig,source.roof,if snapshot then snapshot.tones else (c :: any).groundTones,checkpoint) end
		local result=ForestRaster.paint(forest,px,c.cx,c.cy,c.cw,c.ch,if snapshot then snapshot.fates else fates,checkpoint)
		if not checkpoint then (c :: any).producedVersion=(c :: any).contentVersion or 0 end
		return result
	end
	local mipHits,mipMisses=0,0
	local function dynamic(c:Chunk):boolean
		local dynamic=(c :: any).groundScars and next((c :: any).groundScars)~=nil or false
		if forest then for _,t in forest.inWindow(c.cx,c.cy,c.cw,c.ch) do if fates[t.key] then dynamic=true;break end end end
		return dynamic
	end
	local function decodeFast(c:Chunk,stride:number,frame:number,checkpoint:any?):buffer?
		if stride<2 or dynamic(c) then return nil end
		local name=c.name.."_Mip"..stride
		local module=assets:FindFirstChild(name);if not module then return nil end
		local key=name..":"..frame
		local state=c :: any;state.lodFailed=state.lodFailed or {};if state.lodFailed[key] then return nil end
		local ok,px=pcall(function()
			local source=require(c.mod);state.lodSourceHash=state.lodSourceHash or TownLods.signature(source.deflate,checkpoint)
			state.lodPatchHashes=state.lodPatchHashes or {}
			local hash=state.lodPatchHashes[frame]
			if not hash then
				local patch=if frame==baseFrame then nil else assets:FindFirstChild(c.name.."_Light"..frame)
				if frame~=baseFrame and not patch then return nil end
				hash=TownLods.signature(if patch then require(patch).deflate or "" else "",checkpoint);state.lodPatchHashes[frame]=hash
			end
			return TownLods.decode(require(module),stride,frame,source.width,source.height,state.lodSourceHash,hash,function(text,bytes)
				return Inflate.raw(MapCodec.base64Decode(text,checkpoint),bytes,checkpoint)
			end,baseFrame,checkpoint)
		end)
		if not ok or not px then state.lodFailed[key]=true;mipMisses+=1;return nil end
		mipHits+=1;return px
	end
	local function decode(c: Chunk,frame:number?,checkpoint:any?): (buffer, number, number,number,buffer?)
		(c :: any).prefetched=nil
		(c :: any).warmPixels=nil
		if preparedPaint and preparedPaint.chunk==c and preparedPaint.frame==(frame or baseFrame) and preparedPaint.epoch==paintEpoch then
			local ready=preparedPaint;preparedPaint=nil
			local state=c :: any;state.pixelVersion=ready.version;state.dynamicForest=ready.dynamic
			state.preparedMip=ready.mip
			state.preparedOverview=if state.forestDirty then {pixels=ready.small,version=ready.version,frame=ready.frame} else nil
			return ready.pixels,c.cw*TILE_PX,c.ch*TILE_PX,ready.frame,ready.patch
		end
		local dynamic=dynamic(c)
		;(c :: any).dynamicForest=dynamic
		if dynamic then
			local px=forestPixels(c,frame or baseFrame,checkpoint);(c :: any).pixelVersion=(c :: any).producedVersion
			return px,c.cw*TILE_PX,c.ch*TILE_PX,frame or baseFrame,nil
		end
		local chunk = require(c.mod) :: any
		if not c.packed then
			c.packed = MapCodec.base64Decode(chunk.deflate,checkpoint)
		end
		local px=Inflate.raw(c.packed :: buffer, chunk.width * chunk.height * 4,checkpoint)
		;(c :: any).pixelVersion=(c :: any).contentVersion or 0
		return px, chunk.width, chunk.height,baseFrame,nil
	end
	local warnedLighting = false
	local function relight(c: Chunk, frame: number)
		if (not lighting or c.frame==frame) and (c :: any).pixelVersion==((c :: any).contentVersion or 0) then return end
		if not c.px and not dynamic(c) then
			local stride=if c.iw>0 then math.round(c.w/c.iw) else 1
			local fast=fastPixels(c,stride,frame)
			if fast then (c :: any).preview=fast;(c :: any).pixelVersion=(c :: any).contentVersion or 0;(c :: any).dynamicForest=false;c.frame=frame;c.patch=nil;c.missed=nil;appearanceRevision+=1;return end
		end
		if not preparePaint or not preparePaint(c,frame) then return end
		local ok,px,w,h,painted,patch=pcall(decode,c,frame)
		if not ok then
			c.missed=frame
			if not warnedLighting then warnedLighting=true;warn("[TownRenderer] roof lighting unavailable; existing lighting stays:",px) end
			return
		end
		c.px,c.w,c.h,c.frame,c.patch,c.missed=px,w,h,painted,patch,nil;appearanceRevision+=1
	end
	local function pixelsAt(c: Chunk, stride: number): buffer
		local cached=(c :: any).preparedMip
		if cached and cached.version==(c :: any).pixelVersion and cached.frame==c.frame and (cached.stride==stride or stride==4 and cached.lower) then
			return if cached.stride==stride then cached.pixels else cached.lower.pixels
		end
		;(c :: any).preparedMip=nil
		local preview=(c :: any).preview
		if preview and (c :: any).previewVersion==(c :: any).pixelVersion and (c :: any).previewFrame==c.frame
			and buffer.len(preview)==math.ceil(c.w/stride)*math.ceil(c.h/stride)*4 then return preview end
		if not c.px then
			local preview=(c :: any).preview;assert(preview and buffer.len(preview)==math.ceil(c.w/stride)*math.ceil(c.h/stride)*4,"missing town pixels")
			return preview
		end
		assert(stride==1,"town scale must be prepared before presentation")
		return c.px :: buffer
	end

	-- the overview: every chunk sampled down to 2 px a cell (2 x 2 samples a pixel), in one image
	local ow, oh = mapW * OVERVIEW_PX, mapH * OVERVIEW_PX
	local overviewPixels = buffer.create(ow * oh * 4)
	local step = TILE_PX / OVERVIEW_PX
	local drawn = 0
	local startupAt=os.clock()
	local function startupCheckpoint(_produced:any?)
		if os.clock()-startupAt>=.002 then task.wait();startupAt=os.clock() end
	end
	for i, c in chunks do
		local ok, err = pcall(function()
			local px, w, h = decode(c,nil,startupCheckpoint)
			c.w, c.h = w, h
			local x0, y0 = c.cx * OVERVIEW_PX, c.cy * OVERVIEW_PX
			for oy = 0, c.ch * OVERVIEW_PX - 1 do
				startupCheckpoint()
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
	-- shows the detail at once; one cooperative worker prepares missing chunks, nearest first.
	local loaded = 0
	local holdUntil = 0
	local pool: { [string]: { any } } = {}
	local pooled = 0
	local pooledBytes = 0
	local alive = true
	local warming:any=nil
	local warmAdvanced=false
	local wantedChunks:any={}
	local workerWanted:any={}
	local lastSlice,maxSlice=0,0
	local wantedCount,visibleCount,targetStride=0,0,0
	local function scales(px:buffer,w:number,h:number,stride:number,version:number,frame:number,checkpoint:any):any
		if stride<2 then stride=2 end
		local half,mw,mh=ImagePixels.half(px,w,h,checkpoint)
		local quarter=ImagePixels.half(half,mw,mh,checkpoint)
		return {pixels=if stride==4 then quarter else half,stride=stride,version=version,frame=frame,
			lower={pixels=quarter,stride=4,version=version,frame=frame}}
	end
	local function startPaint(c:Chunk,frame:number,followClock:boolean)
		if warming or preparedPaint then return end
		local needsForest=dynamic(c)
		local snapshot={fates={},scars=if (c :: any).groundScars then table.clone((c :: any).groundScars) else nil,
			tones=if (c :: any).groundTones then table.clone((c :: any).groundTones) else nil,source=groundSource,config=groundConfig}
		if needsForest then for _,tree in forest.inWindow(c.cx,c.cy,c.cw,c.ch) do snapshot.fates[tree.key]=fates[tree.key] end end
		local job:any={kind="paint",dynamic=needsForest,phase=if not needsForest then "restore" elseif bareCache[c.name] then "damage" else "bare",chunk=c,frame=frame,followClock=followClock,version=(c :: any).contentVersion or 0,epoch=paintEpoch,produced=0}
		local stride=if c.image then math.round(c.cw*TILE_PX/c.iw) elseif wantedChunks[c] then math.max(1,targetStride) else 1
		job.thread=coroutine.create(function()
			local began=os.clock()
			local function checkpoint(produced:any?)
				if (job.phase=="bare" or job.phase=="restore") and produced then job.produced=produced end
				if os.clock()-began>=.002 then coroutine.yield();began=os.clock() end
			end
			local px:buffer;local patch:buffer?=nil
			if needsForest then px=forestPixels(c,frame,checkpoint,snapshot,function(value) job.phase=value end)
			else
				local source=require(c.mod)
				if c.px and (c :: any).pixelVersion==job.version and not (c :: any).dynamicForest then
					px=buffer.create(buffer.len(c.px));buffer.copy(px,0,c.px)
					if c.patch then TownPatch.apply(px,c.patch,checkpoint) end
				else
					local encoded=c.packed or MapCodec.base64Decode(source.deflate,checkpoint);c.packed=encoded
					px=Inflate.raw(encoded,source.width*source.height*4,checkpoint)
				end
				if lighting and frame~=baseFrame then
					local module=assets:FindFirstChild(c.name.."_Light"..frame);assert(module,"missing local lighting patch")
					local data=require(module);patch=if data.bytes==0 then buffer.create(0) else Inflate.raw(MapCodec.base64Decode(data.deflate,checkpoint),data.bytes,checkpoint)
					TownPatch.apply(px,patch,checkpoint)
				end
			end
			local w,h=c.cw*TILE_PX,c.ch*TILE_PX
			local small=ForestRaster.overview(px,w,h,TILE_PX,OVERVIEW_PX,checkpoint)
			local mip=scales(px,w,h,stride,job.version,frame,checkpoint)
			return {chunk=c,pixels=px,small=small,mip=mip,patch=patch,dynamic=needsForest,version=job.version,epoch=job.epoch,frame=frame,followClock=followClock}
		end)
		warming=job
	end
	local function advanceWarm()
		local currentFrame=if lighting then TownDetail.frame(DaylightController.get().phase,lighting.sunUp,lighting.steps) else baseFrame
		if preparedPaint and (preparedPaint.epoch~=paintEpoch or dynamic(preparedPaint.chunk)~=preparedPaint.dynamic
			or not (wantedChunks[preparedPaint.chunk] or preparedPaint.chunk.forestDirty)
			or preparedPaint.followClock and not (preparedPaint.chunk.image or wantedChunks[preparedPaint.chunk])
			or preparedPaint.frame~=(if preparedPaint.followClock then currentFrame else baseFrame)) then preparedPaint=nil end
		if not warming or warmAdvanced then return end
		local job=warming;local c=job.chunk
		local painting=job.kind=="paint"
		if painting and (job.epoch~=paintEpoch or dynamic(c)~=job.dynamic or not (wantedChunks[c] or (c :: any).forestDirty)
			or job.followClock and not (c.image or wantedChunks[c])
			or job.frame~=(if job.followClock then currentFrame else baseFrame))
			or not painting and (not workerWanted[c] or job.kind=="lod" and dynamic(c) or job.epoch~=paintEpoch or job.version~=((c :: any).contentVersion or 0)
				or job.frame~=currentFrame) then warming=nil;return end
		warmAdvanced=true
		local began=os.clock()
		local ok,result=coroutine.resume(job.thread)
		lastSlice=os.clock()-began;maxSlice=math.max(maxSlice,lastSlice)
		if not ok then
			warming=nil
			if painting then
				(c :: any).forestDirty=nil
				if job.phase=="bare" then (c :: any).bareFailed=true;warn("[TownRenderer] Damage source warmup failed; existing view stays:",result)
				else (c :: any).paintFailed={version=job.version,frame=job.frame,epoch=job.epoch};if not warnedForest then warnedForest=true;warn("[TownRenderer] Terrain preparation failed; existing view stays:",result) end end
			elseif job.kind=="lod" then
				local state=c :: any;state.lodFailed=state.lodFailed or {};state.lodFailed[c.name.."_Mip"..job.stride..":"..job.frame]=true
			else (c :: any).scaleFailed={version=job.version,frame=job.frame,stride=job.stride};warn("[TownRenderer] Scaling failed; existing view stays:",result) end
		elseif coroutine.status(job.thread)=="dead" then
			if painting then preparedPaint=result
			elseif job.kind=="lod" then
				if result then (c :: any).prefetched=result end
			else (c :: any).preparedMip=result end
			warming=nil
		end
	end
	fastPixels=function(c:Chunk,stride:number,frame:number):buffer?
		if stride<2 or dynamic(c) then return nil end
		local state=c :: any;local cached=state.prefetched
		if cached and cached.stride==stride and cached.frame==frame and cached.version==(state.contentVersion or 0) then
			state.prefetched=nil;state.preparedMip=cached;mipHits+=1;return cached.pixels
		end
		local key=c.name.."_Mip"..stride..":"..frame
		if state.lodFailed and state.lodFailed[key] or not assets:FindFirstChild(c.name.."_Mip"..stride) then return nil end
		if not warming then
			local job:any={kind="lod",phase="lod",chunk=c,stride=stride,frame=frame,epoch=paintEpoch,version=state.contentVersion or 0,produced=0}
			job.thread=coroutine.create(function()
				local began=os.clock()
				local function checkpoint(produced:any?)
					if produced then job.produced=produced end
					if os.clock()-began>=.002 then coroutine.yield();began=os.clock() end
				end
				local px=decodeFast(c,stride,frame,checkpoint);if not px then return nil end
				local lower=nil
				if stride==2 then lower={pixels=ImagePixels.half(px,math.ceil(c.cw*TILE_PX/2),math.ceil(c.ch*TILE_PX/2),checkpoint),stride=4,version=job.version,frame=frame} end
				return {pixels=px,stride=stride,frame=frame,version=job.version,lower=lower}
			end)
			warming=job
		end
		advanceWarm()
		cached=state.prefetched
		if cached and cached.stride==stride and cached.frame==frame and cached.version==(state.contentVersion or 0) then
			state.prefetched=nil;state.preparedMip=cached;return cached.pixels
		end
		return nil
	end
	prepareMip=function(c:Chunk,stride:number):boolean
		if stride<2 then return c.px~=nil end
		local state=c :: any;local cached=state.preparedMip
		if cached and cached.frame==c.frame and cached.version==state.pixelVersion and (cached.stride==stride or stride==4 and cached.lower) then return true end
		local preview=state.preview
		if not c.px and not (stride==4 and preview and buffer.len(preview)==math.ceil(c.w/2)*math.ceil(c.h/2)*4) then return false end
		local failed=state.scaleFailed
		if failed and failed.version==state.pixelVersion and failed.frame==c.frame and failed.stride==stride then return false end
		if not warming then
			local source=c.px or preview;local fromPreview=c.px==nil;local version=state.pixelVersion;local frame=c.frame
			local job:any={kind="mip",phase="scale",chunk=c,stride=stride,frame=frame,epoch=paintEpoch,version=version,produced=0}
			job.thread=coroutine.create(function()
				local began=os.clock()
				local function checkpoint()
					if os.clock()-began>=.002 then coroutine.yield();began=os.clock() end
				end
				if fromPreview then return {pixels=ImagePixels.half(source,math.ceil(c.w/2),math.ceil(c.h/2),checkpoint),stride=4,version=version,frame=frame} end
				return scales(source,c.w,c.h,stride,version,frame,checkpoint)
			end)
			warming=job
		end
		advanceWarm();cached=state.preparedMip
		return cached~=nil and cached.frame==c.frame and cached.version==state.pixelVersion and (cached.stride==stride or stride==4 and cached.lower~=nil)
	end
	preparePaint=function(c:Chunk,frame:number,followClock:boolean?):boolean
		if c.px and (c :: any).pixelVersion==((c :: any).contentVersion or 0) and c.frame==frame then return true end
		if preparedPaint and preparedPaint.chunk==c and preparedPaint.frame==frame and preparedPaint.epoch==paintEpoch then return true end
		if (c :: any).bareFailed and dynamic(c) then return false end
		local failed=(c :: any).paintFailed
		if failed and failed.version==((c :: any).contentVersion or 0) and failed.frame==frame and failed.epoch==paintEpoch then return false end
		startPaint(c,frame,followClock~=false);advanceWarm()
		return preparedPaint~=nil and preparedPaint.chunk==c and preparedPaint.frame==frame
	end
	local clock = 0
	local function stats(detailed:boolean?)
		local shown,pending,ready,sourceBytes,previewBytes,prefetchBytes,nativeBytes,preparedBytes=0,0,0,0,0,0,pooledBytes,0
		local atTarget=0;local rows=if detailed then {}else nil
		for _,c in chunks do
			local old=(c :: any).retiring
			local drawn=if old then old.part else c.part
			local iw,ih=if old then old.iw else c.iw,if old then old.ih else c.ih
			if c.part then shown+=1 elseif c.image then pending+=1 end
			if c.part and wantedChunks[c] then ready+=1 end
			if drawn and wantedChunks[c] and targetStride>0 and iw>=math.ceil(c.cw*TILE_PX/targetStride) then atTarget+=1 end
			if rows and wantedChunks[c] then table.insert(rows,{name=c.name,shown=drawn~=nil,width=iw,height=ih,dirty=(c :: any).forestDirty==true,frame=c.frame,
				state=if old then "replacement"elseif (c :: any).uploading then "upload"elseif warming and warming.chunk==c then "preparing"elseif drawn then "shown"else "queued"})end
			if c.image then nativeBytes+=c.iw*c.ih*4 end
			if old then nativeBytes+=old.iw*old.ih*4;if old.preview then previewBytes+=buffer.len(old.preview) end end
			if c.px then sourceBytes+=buffer.len(c.px) end
			if (c :: any).warmPixels then sourceBytes+=buffer.len((c :: any).warmPixels.pixels) end
			if (c :: any).preview then previewBytes+=buffer.len((c :: any).preview) end
			if (c :: any).prefetched then prefetchBytes+=buffer.len((c :: any).prefetched.pixels) end
			if (c :: any).preparedMip then preparedBytes+=buffer.len((c :: any).preparedMip.pixels) end
			if (c :: any).preparedOverview then preparedBytes+=buffer.len((c :: any).preparedOverview.pixels) end
		end
		if preparedPaint then sourceBytes+=buffer.len(preparedPaint.pixels);preparedBytes+=buffer.len(preparedPaint.small);if preparedPaint.mip then preparedBytes+=buffer.len(preparedPaint.mip.pixels) end end
		return {visible=visibleCount,selected=wantedCount,ready=ready,atTarget=atTarget,shown=shown,pending=pending,stride=targetStride,nativeBytes=nativeBytes,sourceBytes=sourceBytes,previewBytes=previewBytes,prefetchBytes=prefetchBytes,mipHits=mipHits,mipMisses=mipMisses,warming=warming~=nil,warmKind=if warming then warming.phase or warming.kind else nil,warmChunk=if warming then warming.chunk.name else nil,warmProduced=if warming then warming.produced else 0,paintReady=preparedPaint~=nil,paintChunk=if preparedPaint then preparedPaint.chunk.name else nil,chunks=rows,preparedBytes=preparedBytes,lastSliceMs=lastSlice*1000,maxSliceMs=maxSlice*1000}
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
		(c :: any).retiring={part=c.part,label=(c :: any).label,image=c.image,iw=c.iw,ih=c.ih,preview=(c :: any).preview,previewVersion=(c :: any).previewVersion,previewFrame=(c :: any).previewFrame}
		c.part,c.image=nil,nil;(c :: any).preview=nil;loaded-=1
	end
	local function rollback(c:Chunk)
		local old=(c :: any).retiring;(c :: any).retiring=nil
		unload(c,true)
		if old then c.part,c.image,c.iw,c.ih=old.part,old.image,old.iw,old.ih;(c :: any).label=old.label;(c :: any).preview=old.preview;(c :: any).previewVersion=old.previewVersion;(c :: any).previewFrame=old.previewFrame;loaded+=1 end
	end
	local function writeChunk(c:Chunk,pixels:buffer,priority:number):boolean
		local image=c.image;if not image then return false end
		local version,paintedFrame=(c :: any).pixelVersion,c.frame
		return upload(image,Vector2.zero,Vector2.new(c.iw,c.ih),pixels,{priority=priority,done=function(ok)
			if not alive or c.image~=image then return end
			(c :: any).uploading=nil
			if not ok then rollback(c);return end
			(c :: any).preview=if c.iw<c.w then pixels else nil
			(c :: any).previewVersion=version;(c :: any).previewFrame=paintedFrame
			if c.iw>=c.w then (c :: any).preparedMip=nil end -- coarse views retain their already prepared lower fallback
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
	local function takeImage(w: number, h: number,previous:any?): any
		local list = pool[sizeKey(w, h)]
		if list and #list > 0 then
			pooled -= 1
			pooledBytes -= w*h*4
			return table.remove(list)
		end
		local image = newImage(Vector2.new(w, h),nil,previous)
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
			image = newImage(Vector2.new(w, h),nil,previous)
		end
		return image
	end
	-- drop the least recently used inflated pixels beyond the cache size
	local function trimPixels()
		local spare: { Chunk } = {}
		for _, c in chunks do
			if (c.px or (c :: any).prefetched or (c :: any).warmPixels or (c :: any).preparedMip) and (not c.image or c.iw<c.w) then
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
			(spare[i] :: any).preparedMip=nil;(spare[i] :: any).preparedOverview=nil
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
		local old=(c :: any).retiring
		local image = takeImage(iw, ih,if old then old.image else nil)
		while not image and stride < 4 do
			if ready then ready=pixelsAt(c,stride*2) end
			stride *= 2
			iw, ih = math.ceil(c.w / stride), math.ceil(c.h / stride)
			image = takeImage(iw, ih,if old then old.image else nil)
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
		preparedPaint=nil
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
		for _,c in chunks do c.px=nil;c.patch=nil;(c :: any).preview=nil;(c :: any).prefetched=nil;(c :: any).warmPixels=nil;(c :: any).preparedMip=nil;(c :: any).preparedOverview=nil end
		drainPool(); ImageMemory.release(overview)
	end)
	local warnedPressure = false
	local acc = 0
	local zoomStride = 0
	local paintedLast = false
	local lastX,lastY,lastAt=nil,nil,nil
	local lastCellPixels,steadySince,lastUpgrade=nil,0,-math.huge
	connection = RunService.Heartbeat:Connect(function(dt)
		-- Static and damage-source jobs share one resume per Heartbeat; keep current pixels bound.
		warmAdvanced=false;advanceWarm()
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
		wantedChunks={};workerWanted={};for _,c in want do wantedChunks[c]=true;workerWanted[c]=true end
		for _,c in prefetch do workerWanted[c]=true end
		local allReady=true;for _,c in want do if not c.part then allReady=false;break end end
		-- One changed source chunk per check, including the far overview. Reuse native images.
		local dirty:any=if preparedPaint and preparedPaint.chunk.forestDirty then preparedPaint.chunk else nil
		if not dirty then for _,c in chunks do if (c :: any).forestDirty and (not (c :: any).bareFailed or not dynamic(c)) and (not dirty or c.distance<dirty.distance) then dirty=c end end end
		local missing=false
		if detail then for _,c in want do if not c.image then missing=true;break end end end
		-- Changing fires/scars cannot occupy every check while camera-visible detail is missing.
		local dirtyFrame=if dirty and dirty.image then frame else baseFrame
		if dirty and (not missing or not paintedLast) and preparePaint(dirty,dirtyFrame,dirty.image~=nil) then
			paintedLast=true
			local paintedFrame=if dirty.image then frame else baseFrame
			local ok,px,w,h,resultFrame,resultPatch=pcall(function()
				if dirty.px and dirty.pixelVersion==(dirty.contentVersion or 0) and dirty.frame==paintedFrame then
					return dirty.px,dirty.w,dirty.h,dirty.frame,dirty.patch -- retry already owns this exact state.
				end
				return decode(dirty,paintedFrame)
			end)
			if ok then
				dirty.px,dirty.w,dirty.h,dirty.frame,dirty.patch,dirty.missed=px,w,h,resultFrame,resultPatch,nil
				appearanceRevision+=1
				dirty.forestDirty=if dirty.pixelVersion~=(dirty.contentVersion or 0) then true else nil;dirty.used=clock
				local cached=dirty.preparedOverview
				local small=if cached and cached.version==dirty.pixelVersion and cached.frame==dirty.frame then cached.pixels else ForestRaster.overview(px,w,h,TILE_PX,OVERVIEW_PX)
				dirty.preparedOverview=nil
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
			if ImageMemory.recoverTerrain and ImageMemory.terrainLimit and now-steadySince>=.35 then
				-- A feasible better tier may be blocked only by expired battle art in the detail pool.
				-- Recovery is throttled by ImageMemory and visits guarded unused-art reclaimers only.
				local ideal=TownDetail.fitStride(stride,want,TILE_PX,ImageMemory.terrainLimit())
				local required=TownDetail.bytes(want,ideal,TILE_PX)
				if required>allowance then allowance=ImageMemory.recoverTerrain(required,held) end
			end
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
			local transition:buffer?=nil
			if c.image then
				local targetW, targetH = math.ceil(c.w / stride), math.ceil(c.h / stride)
				if targetW < c.iw then
					if not prepareMip(c,stride) then continue end
					transition=pixelsAt(c,stride)
					if ImageMemory.canDetail(Vector2.new(targetW,targetH)) or ImageMemory.canReplaceTerrain and ImageMemory.canReplaceTerrain(Vector2.new(targetW,targetH),c.image) then retire(c)
					elseif c.part and not (c :: any).overviewShown then coverOverview(c,false);continue
					else unload(c);drainPool() end
				elseif targetW>c.iw and allReady and now-steadySince>=.35 and now-lastUpgrade>=.35
					and (ImageMemory.canDetail(Vector2.new(targetW,targetH)) or ImageMemory.canReplaceTerrain and ImageMemory.canReplaceTerrain(Vector2.new(targetW,targetH),c.image)) then
					if not c.px then
						if not preparePaint(c,frame) then continue end
						local ok,px,w,h,painted,patch=pcall(decode,c,frame)
						if not ok then continue end
						c.px,c.w,c.h,c.frame,c.patch=px,w,h,painted,patch
					end
					if not prepareMip(c,stride) then continue end
					lastUpgrade=now
					upgrading=true
					retire(c)
				elseif c.frame ~= frame and c.missed ~= frame then
					relight(c, frame)
					if c.frame~=frame then break end -- preparation is pending; retain the currently bound pixels.
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
			local ready:buffer?=transition
			local initialStride=stride
			if not c.px and not upgrading and not ready then
				initialStride=math.max(2,stride)
				ready=fastPixels(c,initialStride,frame)
				if ready then
					c.w,c.h,c.frame,c.patch=c.cw*TILE_PX,c.ch*TILE_PX,frame,nil
					(c :: any).pixelVersion=(c :: any).contentVersion or 0
					(c :: any).dynamicForest=false
				end
			end
			if (not c.px or preparedPaint and preparedPaint.chunk==c and preparedPaint.frame==frame) and not ready then
				if not preparePaint(c,frame) then continue end
				if inflated then
					continue
				end
				local ok, px, w, h,decodedFrame,decodedPatch = pcall(decode, c,frame)
				inflated = true
				if not ok then
					continue -- unreadable: skip it
				end
				c.px, c.w, c.h = px, w, h
				c.frame,c.patch,c.missed=decodedFrame,decodedPatch,nil
				appearanceRevision+=1
			end
			if not ready then
				relight(c, frame)
				if c.frame~=frame or not prepareMip(c,stride) then continue end
			end
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
					-- Offscreen prefetch must not fall back to a synchronous damaged-source decode.
					if dynamic(c) then continue end
					local fast=fastPixels(c,prefetchStride,frame)
					if fast then (c :: any).prefetched={pixels=fast,stride=prefetchStride,frame=frame,version=(c :: any).contentVersion or 0,lower=(c :: any).preparedMip and (c :: any).preparedMip.lower};c.used=clock
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
