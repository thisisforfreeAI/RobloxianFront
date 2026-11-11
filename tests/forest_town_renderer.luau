--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local Map=require("../src/shared/Simulation/ForestMap");local Raster=require("../src/shared/Presentation/ForestRaster")
	local ImagePixels=require("../src/shared/Presentation/ImagePixels");local TownDetail=require("../src/shared/Presentation/TownDetail");local TownPatch=require("../src/shared/Presentation/TownPatch")
	local ScorchPixels=require("../src/shared/Presentation/GroundScorchPixels")
	local function make():any
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
			shadow={dx=0,dy=0,alpha=0},fallenAnchor=.5,charColors={0x808080}}
		local bare=buffer.create(14*14*4);for at=0,buffer.len(bare)-1,4 do buffer.writeu8(bare,at+2,80);buffer.writeu8(bare,at+3,255) end
		local chunks:any={trees=rows,sprites=source,bare=bare}
		local map=Map.new(metadata,function(key) return chunks[key] end,function() return {deflate="sprites"} end)
		chunks.original=Raster.paint(map,bare,0,0,1,1,{})
		local function module(value) return {value=value,IsA=function(_,class) return class=="ModuleScript" end} end
		local baseName="City_test_0_0"
		local assetsMap:any={City_test=module({forest="Forest_test",lighting={steps=2,sunUp=.62,base=2},chunks={{0,0,1,1,baseName}}}),
			[baseName]=module({width=14,height=14,deflate="original"}),[baseName.."_Bare"]=module({width=14,height=14,deflate="bare"}),
			[baseName.."_Light1"]=module({bytes=0}),[baseName.."_BareLight1"]=module({bytes=0})}
		local assets={FindFirstChild=function(_,name) if h.badBare and string.find(name,"_Bare",1,true) then return nil end;if string.find(name,"_BareLight",1,true) then h.bareLights+=1 end;return assetsMap[name] end}
		local dataMap={Forest_test=module(metadata),pixels=module({deflate="sprites"})};local data={FindFirstChild=function(_,name) return dataMap[name] end}
		local memory={};function memory.create(size,kind) if h.refuse and kind~="core" then return nil end
			local image:any={size=size};function image:WritePixelsBuffer(position,extent,px) assert(not self.dead);self.last=buffer.tostring(px);self.writes=(self.writes or 0)+1 end
			table.insert(h.images,image);return image
		end
		function memory.release(image) if image then assert(not image.dead);image.dead=true;h.releases+=1 end end
		function memory.register(_,fn) h.reclaim=fn;return function() h.unregistered=true end end
		function memory.stats() return 0 end;function memory.canDetail() return true end
		local shared:any={Config={World="world"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Simulation={ForestMap="forest"},Presentation={ImagePixels="pixels",TownDetail="detail",TownPatch="patch",ForestRaster="raster",GroundScorchPixels="scorch"},FindFirstChild=function() return data end}
		local raster={overview=Raster.overview,paint=function(...) h.compositions=(h.compositions or 0)+1;return Raster.paint(...) end}
		local modules:any={world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=0},memory=memory,codec={base64Decode=function(key) return key end},inflate={raw=function(key)
			if key=="bare" then h.bareDecodes=(h.bareDecodes or 0)+1 end
			local source=chunks[key];local fresh=buffer.create(buffer.len(source));buffer.copy(fresh,0,source);return fresh
		end},forest=Map,raster=raster,scorch=ScorchPixels,pixels=ImagePixels,detail=TownDetail,patch=TownPatch,day={get=function() return {phase=h.phase} end}}
		local env:any=setmetatable({game={GetService=function(_,name) return if name=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",DaylightController="day",Parent={FindFirstChild=function() return assets end}}},
			require=function(key) if type(key)=="table" then return key.value end;return assert(modules[key],tostring(key)) end,
			Instance={new=instance},Vector2={new=vec,zero=vec(0,0)},Vector3={new=vec},CFrame=cf,UDim2={fromScale=vec},Content={fromObject=function(image) return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0,Default=1}},task={wait=function() end},
			workspace={CurrentCamera={CFrame={Position=vec(2,80,2),LookVector=vec(0,-1,0)},FieldOfView=60,ViewportSize=vec(800,600)}},
			os={clock=function() return h.now end},warn=function() h.warnings+=1 end,print=function() end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/TownRenderer.luau"),{environment=env})()
		function h.far() env.workspace.CurrentCamera.CFrame.Position.Y=5000 end
		function h.step() h.now+=.2;h.heartbeat:fire(.2) end
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
	test("actual town scar tone-only changes repaint existing ground and preserve its tree foreground",function()
		local h=make();assert(h.renderer.build("test",{}));h.step();local images=#h.images
		local source={width=1,height=1,tileSize=14,roof=function() return false end}
		local config={color="#000000",darken=.5,palette={{color="#000000"},{color="#c08040"}}}
		h.renderer.setGroundScorch({{cells={[0]=255},tones={[0]=0}}},config,source);h.step();local before=h.renderer.sample(.2,.2)[1]
		h.renderer.setGroundScorch({{cells={[0]=255},tones={[0]=1}}},config,source);h.step();assert(h.renderer.sample(.2,.2)[1]>before)
		eq(h.renderer.sample(.5,.5)[2],200);eq(#h.images,images)
		h.renderer.setGroundScorch({},config,nil);h.step();eq(h.renderer.sample(.2,.2)[1],0);h.destroy()
	end)
end
