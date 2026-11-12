--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local Map=require("../src/shared/Simulation/ForestMap");local Raster=require("../src/shared/Presentation/ForestRaster")
	local ImagePixels=require("../src/shared/Presentation/ImagePixels");local TownDetail=require("../src/shared/Presentation/TownDetail");local TownPatch=require("../src/shared/Presentation/TownPatch")
	local ScorchPixels=require("../src/shared/Presentation/GroundScorchPixels")
	local Lods=require("../src/shared/Presentation/TownLods")
	local function make(twoChunks:any?):any
		local h:any={now=0,phase=.3,images={},instances={},warnings=0,bareLights=0,releases=0}
		local function signal():any
			local s:any={items={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire(dt) for _,c in self.items do if not c.dead then c.fn(dt) end end end;return s
		end
		h.heartbeat=signal()
		local function instance(class)
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local mt:any={};local function vec(x,y,z):any return setmetatable({X=x,Y=y,Z=z or 0},mt) end
		mt.__index=function(a,k) return if k=="Magnitude" then math.sqrt(a.X^2+a.Y^2+a.Z^2) else nil end
		mt.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end;mt.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
		mt.__mul=function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
		local cf={};local cmt={__mul=function(a,_b) return a end};cf.new=function(...) return setmetatable({...},cmt) end;cf.Angles=cf.new
		local source=buffer.create(128);for at=0,60,4 do buffer.writeu8(source,at+1,200);buffer.writeu8(source,at+3,255) end
		local rows=buffer.create(48);buffer.writef64(rows,0,1);buffer.writef64(rows,8,.5);buffer.writef64(rows,16,.5);buffer.writef64(rows,24,.4);buffer.writeu16(rows,36,1);buffer.writei32(rows,40,5);buffer.writei32(rows,44,5)
		local family={standing={offset=0,w=4,h=4},fallen={offset=64,w=4,h=4},stump={offset=64,w=4,h=4},burnt={offset=64,w=4,h=4},shadowX=0,shadowY=0}
		local metadata={id="test",width=1,height=1,tileSize=14,stride=48,count=1,trees="trees",families={family},pixelBytes=128,pixelParts={{name="pixels",offset=0,bytes=128}},
			shadow={dx=0,dy=0,alpha=0},fallenAnchor=.5,charColors={0x808080,0x404040}}
		local bare=buffer.create(14*14*4);for at=0,buffer.len(bare)-1,4 do buffer.writeu8(bare,at+2,80);buffer.writeu8(bare,at+3,255) end
		local chunks:any={trees=rows,sprites=source,bare=bare}
		chunks.light=buffer.create(12);buffer.writeu32(chunks.light,0,0);buffer.writeu32(chunks.light,4,1);buffer.writeu32(chunks.light,8,0x100000)
		local map=Map.new(metadata,function(key) return chunks[key] end,function() return {deflate="sprites"} end)
		chunks.original=Raster.paint(map,bare,0,0,1,1,{})
		local function module(value) return {value=value,IsA=function(_,class) return class=="ModuleScript" end} end
		local baseName="City_test_0_0"
		local assetsMap:any={City_test=module({forest="Forest_test",lighting={steps=2,sunUp=.62,base=2},chunks={{0,0,1,1,baseName}}}),
			[baseName]=module({width=14,height=14,deflate="original"}),[baseName.."_Bare"]=module({width=14,height=14,deflate="bare"}),
			[baseName.."_Light1"]=module({bytes=0}),[baseName.."_BareLight1"]=module({bytes=0})}
		if twoChunks then
			for i=1,(if type(twoChunks)=="number" then twoChunks else 2)-1 do
			local name=baseName..(if i==1 then "_next" else "_"..i);table.insert(assetsMap.City_test.value.chunks,{i,0,1,1,name})
			assetsMap[name]=module({width=14,height=14,deflate="original"});assetsMap[name.."_Light1"]=module({bytes=0})
			assetsMap[name.."_Bare"]=module({width=14,height=14,deflate="bare"});assetsMap[name.."_BareLight1"]=module({bytes=0})
			end
		end
		local mip=ImagePixels.half(chunks.original,14,14);chunks.mip=mip
		for _,row in assetsMap.City_test.value.chunks do
			assetsMap[row[5].."_Mip2"]=module({format=2,stride=2,baseFrame=2,width=7,height=7,sourceHash=Lods.signature("original"),deflate="mip",patches={[2]={sourceHash=1,bytes=0,deflate=""}}})
		end
		local assets={FindFirstChild=function(_,name)
			if h.useBareLightDelta and string.match(name,"_BareLight1$") then return module({bytes=12,deflate="light"}) end
			if h.useLightDelta and string.match(name,"_Light1$") then return module({bytes=12,deflate="light"}) end
			if string.find(name,"_Mip",1,true) and not h.useMips then return nil end
			if h.staleMips and string.find(name,"_Mip",1,true) and assetsMap[name] then local bad=table.clone(assetsMap[name].value);bad.sourceHash+=1;return module(bad) end
			if h.badBare and string.find(name,"_Bare",1,true) then return nil end;if string.find(name,"_BareLight",1,true) then h.bareLights+=1 end;return assetsMap[name]
		end}
		local dataMap={Forest_test=module(metadata),pixels=module({deflate="sprites"})};local data={FindFirstChild=function(_,name) return dataMap[name] end}
		local memory={};function memory.create(size,kind) if h.refuse and kind~="core" then return nil end
			local image:any={size=size,kind=kind};function image:WritePixelsBuffer(position,extent,px) assert(not self.dead);if h.failNextWrite then h.failNextWrite=false;error("synthetic replacement failure") end;self.last=buffer.tostring(px);self.writes=(self.writes or 0)+1 end
			table.insert(h.images,image);return image
		end
		h.uploads=require("../src/shared/Presentation/ImageUploads").new(function(image,x,y,w,h,px) image:WritePixelsBuffer(vec(x,y),vec(w,h),px) end,function() return h.now end)
		function memory.upload(image,pos,size,px,options)
			if h.rejectNextUpload then h.rejectNextUpload=false;return false end
			if h.async then return h.uploads.submit(image,pos,size,px,options) end
			image:WritePixelsBuffer(pos,size,px);if options and options.done then options.done(true) end;return true
		end
		function memory.cancelUploads(image) h.uploads.cancel(image) end
		function memory.release(image) if image then h.uploads.cancel(image);assert(not image.dead);image.dead=true;h.releases+=1 end end
		function memory.register(priority,fn) h.reclaim=fn;h.reclaimPriority=priority;return function() h.unregistered=true end end
		function memory.stats() return 0 end;function memory.canDetail() return true end
		function memory.detailHeadroom() return h.headroom or math.huge end
		function memory.terrainLimit() return 2000 end
		function memory.recoverTerrain(required,held)
			if h.recoveryEnabled then h.recoveryCalls=(h.recoveryCalls or 0)+1;h.recoveryRequired=required;h.headroom=2000 end
			return h.headroom or math.huge
		end
		local shared:any={Config={World="world"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Simulation={ForestMap="forest"},Presentation={ImagePixels="pixels",TownDetail="detail",TownPatch="patch",TownLods="lods",ForestRaster="raster",GroundScorchPixels="scorch"},FindFirstChild=function() return data end}
		local raster={overview=function(...) if select(6,...) then h.cooperativeOverviews=(h.cooperativeOverviews or 0)+1 end;return Raster.overview(...) end,paint=function(...)
			if select(8,...) then
				if h.failPaint then error("synthetic private raster failure") end
				if h.yieldPaint then for _=1,3 do coroutine.yield() end end
			end
			h.compositions=(h.compositions or 0)+1;return Raster.paint(...)
		end}
		local imagePixels={half=function(...) if select(4,...) then h.cooperativeDownsamples=(h.cooperativeDownsamples or 0)+1 else h.syncDownsamples=(h.syncDownsamples or 0)+1 end;return ImagePixels.half(...) end}
		local modules:any={world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=0},memory=memory,codec={base64Decode=function(key) return key end},inflate={raw=function(key,_bytes,checkpoint)
			if checkpoint and key=="original" and h.failOriginalWarm then error("synthetic restoration source failure") end
			if checkpoint and h.yieldWarm then for _=1,3 do coroutine.yield() end end
			if key=="original" then h.fullDecodes=(h.fullDecodes or 0)+1 end
			if key=="bare" then h.bareDecodes=(h.bareDecodes or 0)+1 end
			local source=chunks[key];local fresh=buffer.create(buffer.len(source));buffer.copy(fresh,0,source);return fresh
		end},forest=Map,raster=raster,scorch=ScorchPixels,pixels=imagePixels,detail=TownDetail,patch=TownPatch,lods=Lods,day={get=function() return {phase=h.phase} end}}
		local env:any=setmetatable({game={GetService=function(_,name) return if name=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",DaylightController="day",Parent={FindFirstChild=function() return assets end}}},
			require=function(key) if type(key)=="table" then return key.value end;return assert(modules[key],tostring(key)) end,
			Instance={new=instance},Vector2={new=vec,zero=vec(0,0)},Vector3={new=vec},CFrame=cf,UDim2={fromScale=vec},Content={fromObject=function(image) return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0,Default=1}},task={wait=function() end},
			workspace={CurrentCamera={CFrame={Position=vec(2,80,2),LookVector=vec(0,-1,0)},FieldOfView=60,ViewportSize=vec(800,600)}},
			os={clock=function() return h.now end},warn=function() h.warnings+=1 end,print=function() end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/TownRenderer.luau"),{environment=env})()
		function h.far() env.workspace.CurrentCamera.CFrame.Position.Y=5000 end
		function h.pan(x) env.workspace.CurrentCamera.CFrame.Position.X=x*4 end
		function h.step(dt:any?) local elapsed=dt or .2;h.now+=elapsed;h.heartbeat:fire(elapsed) end
		function h.destroy() for _,o in h.instances do if o.Name=="Towns" then o:Destroy();break end end end
		return h
	end
	test("actual town renderer replaces baked canopy, refreshes far overview and lighting, and restores without new images",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local n=#h.images;eq(n,2);eq(h.renderer.sample(.5,.5)[2],200)
		h.renderer.setForestFates({{1,{kind="burnt"}}},true);h.step();eq(h.renderer.sample(.5,.5)[2],0);eq(h.renderer.sample(.5,.5)[3],80);eq(#h.images,n)
		h.phase=0;h.step();assert(h.bareLights>0);eq(h.renderer.sample(.5,.5)[3],80)
		h.reclaim(1,nil);eq(h.images[1].dead,nil);local changed=h.images[1].last
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.sample(.5,.5)[2],200);assert(h.images[1].last~=changed)
		h.destroy();eq(h.renderer.getForestMap(),nil);eq(h.renderer.sample(.5,.5),nil);eq(h.unregistered,true);local releases=h.releases;h.step();eq(h.releases,releases);eq(h.warnings,0)
	end)
	test("actual town overview stays core and close detail uses the protected terrain budget and last-resort reclaimer",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		eq(h.images[1].kind,"core");eq(h.images[2].kind,"terrain");eq(h.reclaimPriority,30);h.destroy()
	end)
	test("actual town forest repaint updates the overview under detail refusal and isolates missing bare art once",function()
		local h=make();h.refuse=true;assert(h.renderer.build("test",{}));h.step();eq(#h.images,1)
		h.renderer.setForestFates({{1,{kind="burnt"}}},true);h.step();eq(h.renderer.sample(.5,.5)[3],80);eq(#h.images,1)
		h.badBare=true;h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step();local warnings=h.warnings
		h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step();eq(h.warnings,warnings)
		h.destroy();h.step();eq(h.renderer.getForestMap(),nil)
	end)
	test("actual town forest cover is CPU-only, cached, invalidated by fates and cleared on teardown",function()
		local h=make();assert(h.renderer.build("test",{}));local n=#h.images
		local cover=h.renderer.forestCover(0,0,1,1);assert(cover);eq(buffer.readu8(cover,(7*14+7)*4+1),200)
		eq(h.renderer.forestCover(0,0,1,1),cover);eq(#h.images,n)
		h.renderer.setForestFates({{1,{kind="burnt"}}},true)
		local burnt=h.renderer.forestCover(0,0,1,1);assert(burnt~=cover);eq(buffer.readu8(burnt,(7*14+7)*4+3),0);eq(#h.images,n)
		h.renderer.setForestFates({},true);local restored=h.renderer.forestCover(0,0,1,1);eq(buffer.tostring(restored),buffer.tostring(cover))
		for x=0,24 do h.renderer.forestCover(x,0,1,1) end
		assert(h.renderer.forestCover(0,0,1,1)~=restored,"CPU cache must evict old regions")
		h.destroy();eq(h.renderer.forestCover(0,0,1,1),nil)
	end)
	test("failed local tree cover falls back once without breaking the town session",function()
		local h=make();assert(h.renderer.build("test",{}))
		h.renderer.getForestMap().pixels=function() error("synthetic missing tree art") end
		eq(h.renderer.forestCover(0,0,1,1),nil);eq(h.warnings,1)
		eq(h.renderer.forestCover(0,0,1,1),nil);eq(h.warnings,1)
		h.step();assert(h.renderer.sample(.5,.5));h.destroy()
	end)
	test("actual urban scorch repaints existing ground and overview beneath roofs/trees and restores cleanly",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local images=#h.images
		local source={width=1,height=1,tileSize=14,roof=function(x,y) return x==1 and y==1 end}
		local config={color="#11171f",darken=.5};local before=h.renderer.sample(.2,.2)[3]
		h.renderer.setGroundScorch({{cells={[0]=255}}},config,source);h.step()
		local stained=h.renderer.sample(.2,.2)[3];assert(stained<before);eq(h.renderer.sample(1.5/14,1.5/14)[3],80)
		eq(h.renderer.sample(.5,.5)[2],200);eq(#h.images,images)
		h.far();h.step();local overview=h.images[1].last;h.phase=0;h.step();eq(h.renderer.sample(.2,.2)[3],stained)
		h.reclaim(1,nil);h.step();eq(h.renderer.sample(.2,.2)[3],stained)
		h.renderer.setGroundScorch({},config,nil);h.step();eq(h.renderer.sample(.2,.2)[3],before);eq(h.renderer.sample(.5,.5)[2],200)
		assert(h.images[1].last~=overview);h.destroy()
	end)
	test("fire updates compose once at current light and reuse an immutable decoded town base",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();h.phase=0
		local before=h.compositions or 0;h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step()
		eq(h.compositions-before,1);eq(h.bareDecodes,1)
		local revision=h.renderer.revision();h.step();eq(h.renderer.revision(),revision)
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.bareDecodes,1);eq(h.renderer.sample(.5,.5)[3],80)
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.sample(.5,.5)[2],200)
		h.destroy()
	end)
	test("identical final tree states keep cached foreground and pixels without revision or repaint churn",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		local fate={kind="burning",char=0};h.renderer.setForestFates({{1,fate}});h.step()
		local cover=h.renderer.forestCover(0,0,1,1);local count=h.compositions;local revision=h.renderer.revision()
		fate.kind="burnt" -- Caller ownership cannot silently mutate retained render state.
		for _=1,12 do
			h.renderer.setForestFates({{1,{kind="burnt"}},{1,{kind="burning",char=0}}});h.step()
		end
		h.renderer.setForestFates({{1,{kind="burning",char=0}}},true);h.step()
		eq(h.compositions,count);eq(h.renderer.revision(),revision);assert(h.renderer.forestCover(0,0,1,1)==cover)
		eq(h.renderer.sample(.5,.5)[2],100)
		h.renderer.setForestFates({{1,nil}});h.step();eq(h.renderer.sample(.5,.5)[2],200);h.destroy()
	end)
	test("fallen tree rotation and char changes still invalidate the affected town state",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="fallen",rot=0,char=0}}});h.step();local count=h.compositions
		h.renderer.setForestFates({{1,{kind="fallen",rot=.7,char=0}}});h.step();eq(h.compositions,count+1)
		h.renderer.setForestFates({{1,{kind="fallen",rot=.7}}});h.step();eq(h.compositions,count+2)
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.sample(.5,.5)[2],200);h.destroy()
	end)
	test("cold dynamic town coverage composes directly at current light and reuses it for the overview refresh",function()
		local h=make(true);h.headroom=200;assert(h.renderer.build("test",{}));h.step();h.phase=0
		h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step();local before=h.compositions
		local scaled=h.syncDownsamples
		h.step();eq(h.compositions,before+1,"cold changed coverage must not compose base and current light separately")
		h.step();eq(h.compositions,before+1,"subsequent dirty overview refresh reuses the freshly composed version")
		eq(h.renderer.stats().ready,2);eq(h.renderer.stats().stride,4);eq(h.syncDownsamples,scaled,"cold quarter detail must use cooperatively prepared scaling")
		h.destroy();eq(h.warnings,0)
	end)
	test("a rejected town damage upload retries its pixels without recomposition or reapplying a static light delta",function()
		local h=make();h.useLightDelta=true;assert(h.renderer.build("test",{}));h.step();h.phase=0
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step()
		h.renderer.setForestFates({},true);h.rejectNextUpload=true;h.step();local before=h.compositions
		eq(h.renderer.sample(.02,.02)[3],64);h.step();eq(h.compositions,before);eq(h.renderer.sample(.02,.02)[3],64)
		eq(string.byte(h.images[2].last,3),64);h.destroy();eq(h.warnings,0)
	end)
	test("actual town scar tone-only changes repaint existing ground and preserve its tree foreground",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local images=#h.images
		local source={width=1,height=1,tileSize=14,roof=function() return false end}
		local config={color="#000000",darken=.5,palette={{color="#000000"},{color="#c08040"}}}
		h.renderer.setGroundScorch({{cells={[0]=255},tones={[0]=0}}},config,source);h.step();local before=h.renderer.sample(.2,.2)[1]
		h.renderer.setGroundScorch({{cells={[0]=255},tones={[0]=1}}},config,source);h.step();assert(h.renderer.sample(.2,.2)[1]>before)
		eq(h.renderer.sample(.5,.5)[2],200);eq(#h.images,images)
		h.renderer.setGroundScorch({},config,nil);h.step();eq(h.renderer.sample(.2,.2)[1],0);h.destroy()
	end)
	test("continuous fire dirtiness cannot starve missing town detail",function()
		local h=make(true);assert(h.renderer.build("test",{}));h.step();eq(#h.images,2)
		for i=1,4 do h.renderer.setForestFates({{1,{kind="burning",char=i%2}}});h.step() end
		eq(#h.images,3,"both detail chunks must load despite continuous fire updates")
		local found=false;for _,o in h.instances do if o.Name=="City_test_0_0_next" and not o.dead then found=true end end;assert(found)
		h.destroy();eq(h.warnings,0)
	end)
	test("limited aggregate town headroom gives every selected chunk the same affordable detail tier",function()
		local h=make(true);h.headroom=600;assert(h.renderer.build("test",{}));h.step();h.step()
		eq(#h.images,3);eq(h.images[2].size.X,7);eq(h.images[3].size.X,7)
		local n=#h.images;for _=1,4 do h.step() end;eq(#h.images,n)
		h.destroy();eq(h.warnings,0)
	end)
	test("town detail publishes only after queued pixels arrive and keeps the overview while waiting",function()
		local h=make();h.async=true;assert(h.renderer.build("test",{}));h.step();eq(#h.images,2)
		local detail=0;for _,o in h.instances do if o.Name=="City_test_0_0" and not o.dead then detail+=1 end end;eq(detail,0)
		eq(h.images[2].writes,nil);assert(h.images[1].last)
		h.uploads.step();eq(h.images[2].writes,1)
		for _,o in h.instances do if o.Name=="City_test_0_0" and not o.dead then detail+=1 end end;eq(detail,1)
		h.uploads.step();h.destroy();eq(h.uploads.bytes,0)
	end)
	test("town teardown cancels unpublished uploads and never resurrects a map part",function()
		local h=make();h.async=true;assert(h.renderer.build("test",{}));h.step();assert(h.uploads.count>0)
		h.destroy();h.uploads.step();eq(h.uploads.count,0);eq(h.images[2].writes,nil)
		for _,o in h.instances do if o.Name=="City_test_0_0" then assert(o.dead) end end
	end)
	test("wide town views cover more than nine chunks without pinning all full-resolution CPU pixels",function()
		local h=make(10);h.headroom=1000;assert(h.renderer.build("test",{}))
		for _=1,15 do h.step() end
		local stats=h.renderer.stats();eq(stats.selected,10);eq(stats.shown,10);eq(stats.ready,10);eq(stats.stride,4)
		assert(stats.sourceBytes<=6*14*14*4);assert(stats.previewBytes>0)
		for x=0,9 do assert(h.renderer.sample(x+.2,.2),"coarse CPU fallback must still sample displayed art") end
		local count=#h.images;h.phase=0;for _=1,15 do h.step() end;eq(h.warnings,0);eq(#h.images,count)
		assert(h.renderer.stats().sourceBytes<=6*14*14*4)
		h.destroy();eq(h.renderer.stats(),nil)
	end)
	test("matching optional town LODs avoid full CPU cold decodes and dynamic fire bypasses them",function()
		local h=make(true);h.useMips=true;h.headroom=600;assert(h.renderer.build("test",{}));local full=h.fullDecodes
		h.step();h.step();eq(h.fullDecodes,full);eq(h.renderer.stats().ready,2);assert(h.renderer.stats().mipHits>=2)
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();assert(h.bareDecodes and h.bareDecodes>0);eq(h.renderer.sample(.5,.5)[2],0)
		h.destroy();eq(h.warnings,0)
	end)
	test("stale optional LOD modules fall back to the current full source without a warning loop",function()
		local h=make(true);h.useMips=true;h.staleMips=true;h.headroom=600;assert(h.renderer.build("test",{}));local before=h.fullDecodes
		h.step();h.step();eq(h.renderer.stats().ready,2);assert(h.fullDecodes>before);assert(h.renderer.stats().mipMisses>0)
		local misses=h.renderer.stats().mipMisses;h.step();eq(h.renderer.stats().mipMisses,misses);eq(h.warnings,0);h.destroy()
	end)
	test("camera motion keeps fast town previews while full upgrades wait for settled coverage",function()
		local h=make(true);h.useMips=true;assert(h.renderer.build("test",{}));local before=h.fullDecodes
		for i=1,6 do h.pan(.5+i*.1);h.step() end
		eq(h.renderer.stats().ready,2);eq(h.fullDecodes,before,"panning must not repeatedly inflate full sources behind valid previews")
		for _=1,6 do h.step() end
		assert(h.fullDecodes>before,"stationary view should upgrade after coverage settles")
		h.destroy();eq(h.warnings,0)
	end)
	test("a settled town view recovers a better feasible tier after idle battle art yields",function()
		local h=make(true);h.useMips=true;h.headroom=600;h.recoveryEnabled=true;assert(h.renderer.build("test",{}))
		for i=1,6 do h.pan(.5+i*.1);h.step() end
		eq(h.recoveryCalls,nil);eq(h.renderer.stats().stride,2);eq(h.renderer.stats().ready,2)
		for _=1,10 do h.step() end
		eq(h.recoveryCalls,1);eq(h.recoveryRequired,1568);eq(h.renderer.stats().stride,1);eq(h.renderer.stats().ready,2)
		local calls=h.recoveryCalls;h.destroy();h.step();eq(h.recoveryCalls,calls)
	end)
	test("cooperative full upgrades retain the preview during yields and cancel on map teardown",function()
		local h=make(true);h.useMips=true;h.yieldWarm=true;assert(h.renderer.build("test",{}))
		h.step();h.step();h.step();eq(h.renderer.stats().ready,2);eq(h.renderer.stats().warming,true)
		local images=#h.images;h.step();eq(h.renderer.stats().ready,2);eq(#h.images,images)
		h.destroy();for _=1,6 do h.step() end;eq(h.renderer.stats(),nil);eq(#h.images,images);eq(h.warnings,0)
	end)
	test("damage source warmup yields without changing the bound town image and commits current damage afterward",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local images=#h.images;local old=h.images[2].last
		h.yieldWarm=true;h.renderer.setForestFates({{1,{kind="burnt"}}});h.step()
		eq(h.renderer.stats().warmKind,"bare");eq(h.images[2].last,old);eq(h.renderer.sample(.5,.5)[2],200)
		for _=1,2 do h.step();eq(h.images[2].last,old) end
		for _=1,5 do if not h.renderer.stats().warming then break end;h.step() end
		eq(h.renderer.stats().warming,false);eq(h.renderer.sample(.5,.5)[2],0);eq(#h.images,images);eq(h.bareDecodes,1)
		h.destroy();eq(h.warnings,0)
	end)
	test("pending damage source work cancels on reset or map teardown without publishing a stale burn",function()
		for _,reset in {true,false} do
			local h=make();assert(h.renderer.build("test",{}));h.step();h.yieldWarm=true
			h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.renderer.stats().warmKind,"bare")
			if reset then h.renderer.setForestFates({},true) else h.destroy() end
			for _=1,6 do h.step() end
			eq(h.bareDecodes,nil);eq(h.warnings,0)
			if reset then eq(h.renderer.stats().warming,false);eq(h.renderer.sample(.5,.5)[2],200);h.destroy()
			else eq(h.renderer.stats(),nil) end
		end
	end)
	test("a yielded damage source does not block unrelated cold town coverage",function()
		local h=make(3);assert(h.renderer.build("test",{}));h.step();eq(#h.images,2)
		h.yieldWarm=true;h.renderer.setForestFates({{1,{kind="burnt"}}});h.step()
		eq(h.renderer.stats().warmKind,"bare");eq(#h.images,3)
		local found=false;for _,o in h.instances do if o.Name=="City_test_0_0_2" and not o.dead then found=true end end
		assert(found,"unrelated static chunk should load while the damage base yields");h.destroy();eq(h.warnings,0)
	end)
	test("failed damage source disables that optional repaint once while explicit reset still restores the map",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();h.badBare=true
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.warnings,1);eq(h.renderer.stats().warming,false)
		for _=1,6 do h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step() end
		eq(h.warnings,1);local decoded=h.fullDecodes
		h.renderer.setForestFates({},true);h.step();assert(h.fullDecodes>decoded);eq(h.renderer.sample(.5,.5)[2],200)
		h.destroy();eq(h.warnings,1)
	end)
	test("yielded tree composition keeps native pixels stable and coalesces continuing fire changes without starvation",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local old=h.images[2].last;local images=#h.images
		h.yieldPaint=true;h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step()
		eq(h.renderer.stats().warmKind,"damage");eq(h.images[2].last,old);eq(h.renderer.sample(.5,.5)[2],200)
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.images[2].last,old)
		local intermediate=false
		for _=1,24 do h.step();local green=h.renderer.sample(.5,.5)[2];if green==100 then intermediate=true end;if green==0 then break end end
		assert(intermediate,"completed snapshots should progress instead of restarting on every update")
		eq(h.renderer.sample(.5,.5)[2],0);eq(#h.images,images);h.destroy();eq(h.warnings,0)
	end)
	test("reset or teardown during yielded tree composition cannot publish the old snapshot",function()
		for _,reset in {true,false} do
			local h=make();assert(h.renderer.build("test",{}));h.step();h.yieldPaint=true
			h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.renderer.stats().warmKind,"damage")
			if reset then h.renderer.setForestFates({},true) else h.destroy() end
			for _=1,12 do h.step() end
			if reset then eq(h.renderer.sample(.5,.5)[2],200);eq(h.renderer.stats().warming,false);h.destroy() else eq(h.renderer.stats(),nil) end
			eq(h.warnings,0)
		end
	end)
	test("clearing ground scars cancels their private snapshot even while forest damage remains",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step();local before=h.renderer.sample(.2,.2)[3]
		local config={color="#000000",darken=.8};local source={width=1,height=1,tileSize=14,roof=function() return false end}
		h.yieldPaint=true;h.renderer.setGroundScorch({{cells={[0]=255}}},config,source);h.step()
		eq(h.renderer.stats().warmKind,"damage");eq(h.renderer.sample(.2,.2)[3],before)
		h.renderer.setGroundScorch({},config,nil)
		for _=1,12 do h.step() end
		eq(h.renderer.sample(.2,.2)[3],before);eq(h.renderer.sample(.5,.5)[2],100);h.destroy();eq(h.warnings,0)
	end)
	test("private raster failure leaves the shown map intact and a later state can retry",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local old=h.images[2].last
		h.failPaint=true;h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.warnings,1);eq(h.images[2].last,old)
		for _=1,6 do h.step() end;eq(h.warnings,1)
		h.failPaint=false;h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step()
		eq(h.renderer.sample(.5,.5)[2],100);eq(h.warnings,1);h.destroy()
	end)
	test("coarse damaged detail and overview reuse scaling performed inside the cooperative job",function()
		local h=make(true);h.headroom=600;assert(h.renderer.build("test",{}));h.step();h.step()
		local count=h.syncDownsamples;h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step()
		assert(h.cooperativeDownsamples and h.cooperativeDownsamples>0);assert(h.cooperativeOverviews and h.cooperativeOverviews>0)
		eq(h.syncDownsamples,count);eq(h.renderer.sample(.5,.5)[2],100);h.destroy();eq(h.warnings,0)
	end)
	test("rejected coarse damage uploads retain prepared scaling until their pixels commit",function()
		local h=make();h.headroom=200;assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.rejectNextUpload=true;h.step()
		local count=h.syncDownsamples;h.step();eq(h.syncDownsamples,count)
		eq(h.renderer.sample(.5,.5)[2],100);h.destroy();eq(h.warnings,0)
	end)
	test("a daylight jump cancels the old damage palette before publishing a completed snapshot",function()
		local h=make();h.useBareLightDelta=true;assert(h.renderer.build("test",{}));h.step();h.yieldPaint=true
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.renderer.stats().warmKind,"damage")
		h.phase=0
		for _=1,24 do
			h.step();if h.renderer.sample(.5,.5)[2]==0 then eq(h.renderer.sample(.02,.02)[3],64);break end
		end
		eq(h.renderer.sample(.5,.5)[2],0);eq(h.renderer.sample(.02,.02)[3],64);h.destroy();eq(h.warnings,0)
	end)
	test("completed damage pixels survive native detail reclamation before publication",function()
		local h=make();h.phase=0;assert(h.renderer.build("test",{}));h.step();h.yieldPaint=true
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step()
		for _=1,24 do h.step(1/60);if h.renderer.stats().paintReady then break end end
		eq(h.renderer.stats().paintReady,true);h.reclaim(math.huge,nil)
		for _=1,12 do h.step();if h.renderer.stats().ready==1 then break end end
		eq(h.renderer.stats().ready,1);eq(h.renderer.sample(.5,.5)[2],0);h.destroy();eq(h.warnings,0)
	end)
	test("static restoration yields with its displayed damage intact and preserves the source light delta for later time changes",function()
		local h=make();h.headroom=200;h.useLightDelta=true;assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burning",char=0}}});h.step();local old=h.images[2].last
		local paints=h.compositions;local scaled=h.syncDownsamples;h.phase=0;h.yieldWarm=true
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.stats().warmKind,"restore");eq(h.images[2].last,old)
		for _=1,24 do h.step();if not h.renderer.stats().warming and h.renderer.sample(.5,.5)[2]==200 then break end end
		eq(h.renderer.sample(.5,.5)[2],200);eq(h.renderer.sample(.02,.02)[3],64);eq(h.compositions,paints);eq(h.syncDownsamples,scaled)
		h.yieldWarm=false;h.phase=.3;h.step();eq(h.renderer.sample(.02,.02)[3],80);eq(h.compositions,paints)
		h.destroy();eq(h.warnings,0)
	end)
	test("new fire cancels an in-flight static restore before intact art can overwrite it",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();eq(h.renderer.sample(.5,.5)[2],0)
		h.yieldWarm=true;h.renderer.setForestFates({},true);h.step();eq(h.renderer.stats().warmKind,"restore")
		h.renderer.setForestFates({{1,{kind="burning",char=1}}})
		for _=1,12 do h.step();assert(h.renderer.sample(.5,.5)[2]~=200,"obsolete intact state must never publish") end
		eq(h.renderer.sample(.5,.5)[2],50);h.destroy();eq(h.warnings,0)
	end)
	test("an explicit repeated reset retries a failed restore without requiring a different authoritative state",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();h.failOriginalWarm=true
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.sample(.5,.5)[2],0);eq(h.warnings,1)
		for _=1,6 do h.step() end;eq(h.warnings,1)
		h.failOriginalWarm=false;h.renderer.setForestFates({},true);h.step()
		eq(h.renderer.sample(.5,.5)[2],200);eq(h.warnings,1);h.destroy()
	end)
	test("map teardown cancels yielded restoration without creating a new image or completing its source",function()
		local h=make();assert(h.renderer.build("test",{}));h.step()
		h.renderer.setForestFates({{1,{kind="burnt"}}});h.step();h.yieldWarm=true
		h.renderer.setForestFates({},true);h.step();eq(h.renderer.stats().warmKind,"restore")
		local count,decoded=#h.images,h.fullDecodes;h.destroy();for _=1,12 do h.step() end
		eq(h.renderer.stats(),nil);eq(#h.images,count);eq(h.fullDecodes,decoded);eq(h.warnings,0)
	end)
	local function pendingSwap()
		local h=make();h.useMips=true;h.async=true;assert(h.renderer.build("test",{}));h.step();h.uploads.step();h.uploads.step()
		local part,label
		for _,o in h.instances do if o.Name=="City_test_0_0" and not o.dead then part=o end end
		for _,o in h.instances do if o.ClassName=="ImageLabel" and o.Parent and o.Parent.Parent==part then label=o end end
		assert(part and label);local old=label.ImageContent
		for _=1,8 do if #h.images>=3 then break end;h.step() end
		eq(#h.images,3);return h,part,label,old
	end
	test("funded town upgrades keep the same visible part until the new image commits",function()
		local h,part,label,old=pendingSwap();eq(part.dead,nil);eq(old.dead,nil);eq(label.ImageContent,old)
		h.uploads.step();eq(part.dead,nil);assert(label.ImageContent~=old);eq(old.dead,true)
		h.destroy();eq(h.uploads.bytes,0)
	end)
	test("failed town replacement rolls back to its existing preview",function()
		local h,part,label,old=pendingSwap();h.failNextWrite=true;h.uploads.step()
		eq(part.dead,nil);eq(label.ImageContent,old);eq(old.dead,nil);h.destroy()
	end)
end
