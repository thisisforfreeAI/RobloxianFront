--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	if not fs.isFile("src/shared/GameData/FireRules.luau") then return end
	local Scorch=require("../src/shared/Presentation/FireScorch")
	local settings=require("../src/shared/GameData/FireRules") ::any
	local function make():any
		local h:any={time=0,instances={},tasks={},created=0,released=0,writes=0,attempts=0,warnings=0,decodes=0,hidden=false,light=.6}
		local function signal():any
			local s:any={items={}}
			function s:Connect(fn:any):any local item={fn=fn,on=true};table.insert(self.items,item);return{Disconnect=function() item.on=false end} end
			function s:fire(dt:number?) for _,item in self.items do if item.on then item.fn(dt) end end end
			function s:active():number local count=0;for _,item in self.items do if item.on then count+=1 end end;return count end
			return s
		end
		local function instance(class:string):any
			local obj:any={ClassName=class,Name=class,Destroying=signal()}
			function obj:Destroy()
				if self.dead then return end;self.dead=true;self.Destroying:fire()
				for _,child in h.instances do if child.Parent==self then child:Destroy() end end
			end
			table.insert(h.instances,obj);return obj
		end
		h.parent=instance("Folder");h.heartbeat=signal();h.meta={width=16,height=16,tileSize=2}
		local memory:any={}
		function memory.create(size:any):any
			h.attempts+=1;if h.refuse then return nil end
			h.created+=1;local image:any={}
			function image:WritePixelsBuffer(_pos:any,sz:any,pixels:buffer)
				assert(not self.dead);if h.failWrite then error("synthetic failed paint") end
				eq(buffer.len(pixels),sz.X*sz.Y*4);self.last=buffer.tostring(pixels);h.writes+=1
			end
			return image
		end
		function memory.release(image:any) assert(not image.dead);image.dead=true;h.released+=1 end
		function memory.register(_p:any,fn:any):any h.reclaim=fn;return function() h.reclaim=nil end end
		local function vec(x:number,y:number,z:number?):any return {X=x,Y=y,Z=z} end
		local cf:any={};local mt={__mul=function(a:any,_b:any) return a end}
		cf.new=function(...:any) return setmetatable({...},mt) end;cf.Angles=cf.new
		local sampler={width=16,height=16,tileSize=2,roof=function(x,y) return x>=0 and y>=0 and x<32 and y<32 end,
			sourceId=function(x,y) return y*32+x end,original=function() return {100,120,140,226} end}
		local shared:any={Config={World="world"},Simulation={FireMap="map"},Presentation={FireScorch="scorch"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"}}
		local data={FindFirstChild=function(_self,name) return if h.missing then nil elseif name=="FireMap_test" then "source" elseif name=="FireRules" then "rules" else "page" end}
		function shared:FindFirstChild() return data end
		local modules:any={source=h.meta,rules=settings,page={},world={STUDS_PER_CELL=4,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return vec(x*4,z,y*4) end},
			scorch=Scorch,codec={base64Decode=function() return buffer.create(4) end},inflate={raw=function(b) return b end},
			map={new=function(_meta,decode,load) h.decodes+=1;decode("raw",4);load("page");return sampler end},
			memory=memory,fog={hidden=function(x,y) return h.hidden or (h.fog and h.fog(x,y)) or false end},
			town={sample=function() return {100*h.light,120*h.light,140*h.light} end,forestCover=function(_x,_y,w,hg)
				if not h.cover then return nil end
				local px=buffer.create(w*hg*h.meta.tileSize^2*4)
				for at=0,buffer.len(px)-1,4 do for c=0,3 do buffer.writeu8(px,at+c,h.cover[c+1]) end end;return px
			end},view={view=function() return h.view end}}
		h.view={cx=8,cy=4,rx=20,ry=20,cellPixels=12}
		local env:any=setmetatable({game={GetService=function(_s,name) return if name=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",FogOverlay="fog",TownRenderer="town",WorldLight="view"}},require=function(name) assert(modules[name],tostring(name));return modules[name] end,
			Instance={new=instance},Vector2={new=vec},Vector3={new=vec},UDim2={fromScale=vec},CFrame=cf,Content={fromObject=function(image) assert(image and not image.dead);return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}},workspace={CurrentCamera={}},
			task={spawn=function(fn) table.insert(h.tasks,fn) end,wait=function() end},os={clock=function() return h.time end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/FireScorchRenderer.luau"),{environment=env,debugName="FireScorchRenderer_runtime_test"})()
		function h.frame() h.heartbeat:fire(.21) end
		function h.flush() local tasks=h.tasks;h.tasks={};for _,fn in tasks do fn() end end
		function h.parts():number
			local count=0;for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then
				count+=1;eq(obj.CanCollide,false);eq(obj.CanQuery,false);eq(obj.CanTouch,false);eq(obj.CFrame[1].Y,.12)
			end end;return count
		end
		return h
	end
	test("actual scorch renderer stays lazy, paints world tiles and restores unchanged underlying art",function()
		local h=make();eq(h.renderer.start({data={id="test"}},h.parent),true);h.frame();eq(h.created,0);eq(#h.tasks,0)
		h.renderer.apply({{33,1},{49,3}});h.frame();eq(#h.tasks,1);eq(h.created,0);h.flush();h.frame();eq(h.created,2);eq(h.parts(),2);eq(h.writes,2)
		h.frame();eq(h.writes,2);h.light=.3;h.frame();eq(h.writes,4)
		h.renderer.apply({{33,0},{49,0}});h.frame();eq(h.parts(),0);eq(h.released,2);h.parent:Destroy();eq(h.reclaim,nil)
	end)
	test("actual scorch renderer gates individual fogged texels and avoids loading wholly hidden sources",function()
		local h=make();h.hidden=true;h.renderer.start({data={id="test"}},h.parent);h.renderer.apply({{33,1},{49,3}});h.frame();eq(#h.tasks,0);eq(h.decodes,0)
		h.hidden=false;h.fog=function(x) return x>=8 end;h.frame();h.flush();h.frame();eq(h.parts(),1);eq(h.created,1)
		h.hidden=true;h.frame();eq(h.parts(),0);eq(h.released,1);h.parent:Destroy()
	end)
	test("actual scorch renderer backs off after refusal, yields detail and tears down pending loads",function()
		local h=make();h.refuse=true;h.renderer.start({data={id="test"}},h.parent);h.renderer.apply({{33,2}});h.frame();h.flush();h.frame();eq(h.attempts,1);eq(h.parts(),0)
		h.frame();eq(h.attempts,1);h.time=6;h.refuse=false;h.frame();eq(h.parts(),1)
		h.reclaim();eq(h.parts(),0);eq(h.released,1);h.frame();eq(h.parts(),0);h.time=12;h.frame();eq(h.parts(),1)
		h.parent:Destroy();eq(h.created,h.released);eq(h.heartbeat:active(),0);eq(h.reclaim,nil);eq(h.warnings,0)
		local pending=make();pending.renderer.start({data={id="test"}},pending.parent);pending.renderer.apply({{33,1}});pending.frame();eq(#pending.tasks,1)
		pending.parent:Destroy();pending.flush();eq(pending.created,0);eq(pending.heartbeat:active(),0);eq(pending.warnings,0)
	end)
	test("actual scorch renderer isolates failed paints and skips missing source data",function()
		local h=make();h.missing=true;eq(h.renderer.start({data={id="test"}},h.parent),false);eq(h.heartbeat:active(),0)
		h.missing=false;h.failWrite=true;h.renderer.start({data={id="test"}},h.parent);h.renderer.apply({{33,1}});h.frame();h.flush();h.frame();eq(h.parts(),0);eq(h.created,h.released);eq(h.warnings,1)
		assert(h.renderer.source(),"a failed native char image must not discard the shared CPU roof map")
		h.frame();eq(h.warnings,1);h.parent:Destroy()
		local bad=make();bad.meta.width=0;eq(bad.renderer.start({data={id="test"}},bad.parent),false);eq(bad.heartbeat:active(),0)
	end)
	test("actual roof-char renderer preserves changing tree foreground with the same native image",function()
		local h=make();h.cover={20,200,40,255};h.renderer.start({data={id="test"}},h.parent);h.renderer.apply({{33,2}});h.frame();h.flush();h.frame();eq(h.created,1)
		local image;for _,o in h.instances do if o.ClassName=="ImageLabel" and not o.dead then image=o.ImageContent;break end end;assert(image)
		local px=buffer.fromstring(image.last);local at=(1*16+1)*4;eq(buffer.readu8(px,at+1),200);local before=image.last
		h.cover=nil;h.frame();assert(image.last~=before);eq(h.created,1);h.parent:Destroy();eq(h.created,h.released)
	end)
	test("actual fire roof map is lazily shared without duplicate decode or native image allocation",function()
		local h=make();h.renderer.start({data={id="test"}},h.parent);eq(h.renderer.source(),nil);eq(#h.tasks,1)
		eq(h.renderer.source(),nil);eq(#h.tasks,1);h.flush();local source=h.renderer.source();assert(source);eq(h.renderer.source(),source)
		eq(h.decodes,1);eq(h.created,0);h.parent:Destroy();eq(h.renderer.source(),nil)
	end)
end
