--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	if not fs.isFile("src/shared/GameData/DeathFx.luau") then return end
	local Effects=require("../src/shared/Presentation/DeathEffects")
	local config=require("../src/shared/GameData/DeathFx") ::any
	local function make():any
		local h:any={time=0,instances={},created=0,released=0,writes=0,attempts=0,warnings=0,hidden=false}
		local function signal():any
			local s:any={items={}};function s:Connect(fn:any) table.insert(self.items,fn) end
			function s:fire() for _,fn in self.items do fn() end end;return s
		end
		local function instance(class:string):any
			local obj:any={ClassName=class,Name=class,Destroying=signal()}
			function obj:Destroy() if self.dead then return end;self.dead=true;for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,obj);return obj
		end
		local memory:any={}
		function memory.create(size:any):any
			h.attempts+=1;if h.refuse then return nil end;h.created+=1
			local image:any={};function image:WritePixelsBuffer() assert(not self.dead);if h.failWrite then error("synthetic write failure") end;h.writes+=1 end;return image
		end
		function memory.release(image:any) assert(not image.dead);image.dead=true;h.released+=1 end
		local vmt:any={}
		local function vec(x:number,y:number,z:number?):any return setmetatable({X=x,Y=y,Z=z},vmt) end
		vmt.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,(a.Z or 0)+(b.Z or 0)) end
		local cf:any={};local mt={__mul=function(a:any,_b:any) return a end};cf.new=function(...:any) return setmetatable({...},mt) end;cf.Angles=cf.new
		local shared:any={Presentation={DeathEffects="effects",ImpactEffects="impacts",TracerFlight="tracers",BallisticFlight="ballistics"},Maps={MapCodec="codec"},Assets={PixelCodec="pixels"},Config={World="world"}}
		local data={FindFirstChild=function(_,name) if name=="ImpactFx" then return if h.noImpact then nil else "impactConfig" end;return if h.missing then nil else "config" end};function shared:FindFirstChild() return data end
		local assets={FindFirstChild=function() return if h.missing then nil else "art" end}
		local modules:any={memory=memory,config=config,art={width=96,height=96,frame=24,rle=""},
			ballistics=require("../src/shared/Presentation/BallisticFlight"),tracers=require("../src/shared/Presentation/TracerFlight"),impacts=require("../src/shared/Presentation/ImpactEffects"),impactConfig=if fs.isFile("src/shared/GameData/ImpactFx.luau") then require("../src/shared/GameData/ImpactFx") else nil,
			effects={new=function(c) local e=Effects.new(c,function() return .5 end);h.engine=e;return e end},
			codec={base64Decode=function() return buffer.create(0) end},pixels={decode=function() return buffer.create(96*96*4) end},
			world={STUDS_PER_CELL=4,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return vec(x*4,z,y*4) end},
			fog={water=function()return false end,hidden=function(x,y) return h.hidden or (h.fog and h.fog(x,y)) or false end}}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",FogOverlay="fog",Parent={FindFirstChild=function() return assets end}}},
			require=function(name) assert(modules[name],tostring(name));return modules[name] end,
			Instance={new=instance},Vector2={new=vec},Vector3={new=vec},UDim2={fromScale=vec},CFrame=cf,Color3={fromRGB=vec},
			Content={fromObject=function(image) assert(image and not image.dead);return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}},workspace={},os={clock=function() return h.time end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/DeathRenderer.luau"),{environment=env,debugName="DeathRenderer_world_fire_test"})()
		function h.parts():number local n=0;for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then n+=1;eq(obj.CanCollide,false);eq(obj.CanQuery,false);eq(obj.CanTouch,false) end end;return n end
		function h.enabled():number local n=0;for _,obj in h.instances do if obj.ClassName=="SurfaceGui" and obj.Enabled and not obj.dead then n+=1 end end;return n end
		return h
	end
	local function flame():any return {tex="blobA",x=1,y=1,h=.3,vh=1,size=.5,life=3,color=config.colors.fire,a0=1,a1=1} end
	test("actual death renderer routes fire requests through one atlas and cleans map-tagged views",function()
		local h=make();h.renderer.clearTag(nil);eq(h.created,0);eq(h.renderer.request("bad",flame(),"a"),false);eq(h.created,0)
		eq(h.renderer.request("spawn",flame(),"a"),true);h.renderer.step(.05);eq(h.created,1);eq(h.writes,1);eq(h.parts(),1);eq(h.enabled(),1)
		h.renderer.request("embers",{x=1,y=1,h=.4,count=3,spread=.3},"b");h.renderer.step(.05);eq(h.created,1);eq(h.parts(),4)
		h.renderer.clearTag("a");eq(#h.engine.particles,3);eq(h.enabled(),0);h.renderer.step(.05);eq(h.enabled(),3)
		h.renderer.clearTag("b");eq(#h.engine.particles,0);eq(h.parts(),0);eq(h.warnings,0)
	end)
	test("actual fire particle requests retry image refusal without an allocation or warning loop",function()
		local h=make();h.refuse=true;eq(h.renderer.request("spawn",flame(),"a"),false);eq(h.attempts,1);eq(h.warnings,1)
		h.time=1;eq(h.renderer.request("spawn",flame(),"a"),false);eq(h.attempts,1);eq(h.warnings,1)
		h.time=6;h.refuse=false;eq(h.renderer.request("spawn",flame(),"a"),true);eq(h.attempts,2);eq(h.created,1);h.renderer.step(.05);eq(h.enabled(),1)
		local broken=make();broken.failWrite=true;eq(broken.renderer.request("spawn",flame(),"a"),false);eq(broken.created,broken.released);eq(broken.warnings,1)
		broken.failWrite=false;broken.time=6;eq(broken.renderer.request("spawn",flame(),"a"),true);eq(broken.created,2)
	end)
	test("actual fire particle renderer hides both hidden births and plumes crossing into fog",function()
		local h=make();h.hidden=true;eq(h.renderer.request("spawn",flame(),"a"),false);eq(h.created,0)
		h.hidden=false;local p=flame();p.x=4;p.vx=4;h.renderer.request("spawn",p,"a");h.fog=function(x) return x>5 end
		h.renderer.step(.1);eq(h.enabled(),1);h.renderer.step(.3);eq(h.enabled(),0)
		local missing=make();missing.missing=true;eq(missing.renderer.request("spawn",flame(),"a"),false);missing.time=10;missing.renderer.request("spawn",flame(),"a");eq(missing.created,0);eq(missing.warnings,1)
	end)
 if fs.isFile("src/shared/GameData/ImpactFx.luau") then
 test("actual impact bridge shares the existing atlas and resets only its own particles",function()
  local h=make();h.renderer.request("spawn",flame(),"fire");eq(h.created,1)
  h.renderer.impacts(1,{{1,5,5,1.8,10,"mortar"}},{10,1});h.renderer.step(.5);eq(h.created,1);eq(h.writes,1);assert(h.enabled()>1);assert(#h.engine.particles>1)
  h.renderer.resetImpacts();eq(#h.engine.particles,1);eq(h.engine.particles[1].worldTag,"fire");eq(#h.engine.later,0);h.renderer.step(.01);eq(h.enabled(),1)
 end)
 test("missing optional impact settings leave existing world fire and units usable",function()
  local h=make();h.noImpact=true;h.renderer.impacts(1,{{1,5,5,4,10,"shell"}},{10,1});h.renderer.step(.1);eq(h.created,0);eq(h.warnings,0)
  eq(h.renderer.request("spawn",flame(),"fire"),true);h.renderer.step(.05);eq(h.enabled(),1)
 end)
 end

 test("actual tracer renderer uses the existing streak crop and freezes with its shared clock",function()
  local h=make();h.renderer.impacts(1,{}, {0,1});local p={x=1,y=1,h=.5,tx=11,ty=1,targetH=0,at=0,now=0,speed=10,tail=2,width=.2,tip=3,heightFactor=.4,color=1,headColor=2}
  assert(h.renderer.request("tracer",p,"a"));h.renderer.step(.1);eq(h.created,1);eq(h.enabled(),2);for _,v in h.instances do if v.ClassName=="ImageLabel"then eq(v.ImageRectOffset.X,24);eq(v.ImageRectOffset.Y,72)end end
  h.time=.1;h.renderer.step(.1);local x=h.engine.particles[1].x;h.renderer.impacts(2,{}, {.1,0});h.time=50;h.renderer.step(2);eq(h.engine.particles[1].x,x);eq(h.engine.tracerCount,1)
  h.renderer.impacts(3,{},nil);eq(h.engine.tracerCount,0);h.renderer.step(.1);eq(h.enabled(),0)
 end)
 test("actual tracer birth and segment fog checks suppress hidden emission without another image",function()
  local h=make();local p={x=1,y=1,h=.5,tx=11,ty=1,targetH=0,at=0,now=.8,speed=10,tail=8,width=.2,tip=3,heightFactor=.4,color=1,headColor=2};h.hidden=true;eq(h.renderer.request("tracer",p,"a"),false);eq(h.created,0)
  h.hidden=false;h.renderer.impacts(1,{}, {.8,0});assert(h.renderer.request("tracer",p,"a"));h.fog=function(x)return x>=7 and x<8 end;h.renderer.step(.1);assert(h.enabled()<2);eq(h.created,1)
  h.renderer.resetImpacts();eq(h.engine.tracerCount,0);eq(#h.engine.particles,0)
 end)

 test("actual ballistic renderer shares the existing atlas follows pause and draws daylight shadows",function()
  local h=make();local cfg=require("./fixtures/ballistic_config");h.renderer.impacts(1,{}, {0,1});local p={config=cfg,weapon="rocket",x=1,y=1,h=.4,tx=11,ty=1,targetH=0,at=0,now=0,seed=7}
  assert(h.renderer.request("ballistic",p,"a"));h.time=.05;h.renderer.step(.05,.5);eq(h.created,1);eq(h.writes,1);eq(h.engine.ballisticCount,1);assert(h.enabled()>=3);eq(h.engine.particles[2].alpha,.175)
  h.renderer.impacts(2,{}, {.05,0});local x=h.engine.particles[1].x;h.time=50;h.renderer.step(2,.5);eq(h.engine.particles[1].x,x);eq(h.engine.ballisticCount,1)
  h.renderer.impacts(3,{},nil);eq(h.engine.ballisticCount,0);h.renderer.step(.1);eq(h.enabled(),0)
 end)
 test("actual ballistic origin fog reset and shared image refusal leave no orphaned flight parts",function()
  local h=make();local cfg=require("./fixtures/ballistic_config");local p={config=cfg,weapon="mortar",x=1,y=1,h=.4,tx=11,ty=1,targetH=0,at=0,now=0,seed=7}
  h.hidden=true;eq(h.renderer.request("ballistic",p,"a"),false);eq(h.created,0);h.hidden=false;h.refuse=true;eq(h.renderer.request("ballistic",p,"a"),false);eq(h.attempts,1)
  h.time=6;h.refuse=false;h.renderer.impacts(1,{}, {0,0});assert(h.renderer.request("ballistic",p,"a"));h.renderer.step(.01);eq(h.engine.ballisticCount,1);h.renderer.resetImpacts();eq(h.engine.ballisticCount,0);eq(#h.engine.particles,0)
 end)

end
