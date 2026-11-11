--!strict
-- Execute the actual streaming renderer with mocked native boundaries and generated local settings.
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/client/DevAssets/Water_shoals.luau") then return end
	local luau=require("@lune/luau")
	local W=require("../src/shared/Presentation/WaterShade")
	local source=require("../src/client/DevAssets/Water_shoals") ::any
	local function make():any
		local h:any={time=0,tick=0,instances={},images={},writes=0,created=0,released=0,warnings=0,attempts=0}
		h.view={cx=2,cy=2,rx=6,ry=6,cellPixels=10}
		h.light={night=0,elevation=1,color={1,1,1}}
		local settings=source.settings
		local F=settings.fine;local side=2*F
		local raw=buffer.create(side*side*4)
		for i=1,side*side-1 do
			buffer.writeu8(raw,i*4,80);buffer.writeu8(raw,i*4+1,110);buffer.writeu8(raw,i*4+2,140)
			buffer.writeu8(raw,i*4+3,settings.codes.deep)
		end
		local wm=buffer.create(4*4*4)
		for i=0,15 do buffer.writeu8(wm,i*4,128);buffer.writeu8(wm,i*4+1,128);buffer.writeu8(wm,i*4+3,255) end
		h.meta={water=true,settings=settings,chunks={{0,0,2,2,"fine","water"},{2,0,2,2,"fine","water"},{4,0,2,2,"fine","water"}}}
		local function signal():any
			local s:any={items={}}
			function s:Connect(fn:any):any local item={fn=fn,on=true};table.insert(self.items,item);return{Disconnect=function() item.on=false end} end
			function s:fire(dt:number?) for _,item in self.items do if item.on then item.fn(dt) end end end
			function s:active():number local n=0;for _,item in self.items do if item.on then n+=1 end end;return n end
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
		h.parent=instance("Folder");h.heartbeat=signal();h.render=signal()
		local memory:any={}
		function memory.canDetail() return not h.deny end
		function memory.create(size:any):any
			h.attempts+=1;if h.refuse then return nil end
			h.created+=1
			local image:any={size=size,px=buffer.create(size.X*size.Y*4)}
			function image:WritePixelsBuffer(pos:any,sz:any,band:buffer)
				assert(not self.dead,"write to released water image")
				if h.failWrite then error("synthetic write refusal") end
				eq(buffer.len(band),sz.X*sz.Y*4);assert(pos.Y>=0 and pos.Y+sz.Y<=size.Y)
				buffer.copy(self.px,pos.Y*size.X*4,band);h.writes+=1
			end
			table.insert(h.images,image);return image
		end
		function memory.release(image:any) assert(not image.dead);image.dead=true;h.released+=1 end
		function memory.register(_p:any,fn:any):any h.reclaim=fn;return function() h.reclaim=nil end end
		function memory.stats():number return (h.created-h.released)*side*side*4 end
		local function vec(x:number,y:number,z:number?):any return {X=x,Y=y,Z=z} end
		local cf:any={};local mt={__mul=function(a:any,_b:any) return a end}
		cf.new=function(...:any) return setmetatable({...},mt) end;cf.Angles=cf.new
		local shared={Config={World="world"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Presentation={WaterShade="shade"}}
		local modules:any={world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2},shade=W,
			codec={base64Decode=function(value) return value end},inflate={raw=function(value,size)
				local out=if value=="fine" then raw elseif value=="water" then wm else error("synthetic bad chunk")
				eq(buffer.len(out),size);return out
			end},memory=memory,day={get=function() return h.light end},view={view=function() return h.view end}}
		local module={IsA=function() return true end}
		local assets={FindFirstChild=function() return if h.missing then nil else module end}
		local env:any=setmetatable({game={GetService=function(_s:any,name:string) return if name=="RunService" then {Heartbeat=h.heartbeat,RenderStepped=h.render} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",DaylightController="day",WorldLight="view",Parent={FindFirstChild=function() return assets end}}},
			require=function(name:any) if name==module then return h.meta end;assert(modules[name],tostring(name));return modules[name] end,
			Instance={new=instance},Vector2={new=vec},Vector3={new=vec},UDim2={fromScale=vec},CFrame=cf,
			Content={fromObject=function(image:any) assert(image and not image.dead);return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}},workspace={CurrentCamera={}},
			os={clock=function() h.tick+=.00025;return h.time+h.tick end},warn=function() h.warnings+=1 end}, {__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/WaterRenderer.luau"),{environment=env,debugName="WaterRenderer_runtime_test"})()
		function h.check() h.heartbeat:fire(.21) end
		function h.paint() h.render:fire() end
		function h.parts():number
			local count=0
			for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then
				count+=1;assert(obj.CanCollide==false and obj.CanQuery==false and obj.CanTouch==false)
				eq(obj.CFrame[2],.03);assert(obj.Transparency==1)
			end end
			return count
		end
		return h
	end
	test("actual water renderer skips missing and dry-map data without native resources",function()
		local h=make();h.missing=true;eq(h.renderer.build("missing",h.parent),false)
		h.missing=false;h.meta.water=false;eq(h.renderer.build("saddle",h.parent),false)
		eq(h.created,0);eq(h.parts(),0);eq(h.heartbeat:active(),0);eq(h.render:active(),0);eq(h.reclaim,nil)
	end)
	test("actual water renderer streams world chunks, paints clear land and evicts distant views",function()
		local h=make();eq(h.renderer.build("test",h.parent),true)
		for _=1,3 do h.check();h.paint() end
		eq(h.created,3);eq(h.parts(),3);assert(h.writes>0)
		for _,image in h.images do
			eq(buffer.readu8(image.px,3),0);eq(buffer.readu8(image.px,7),255)
		end
		h.view.cx=100;h.view.cy=100;h.check();eq(h.parts(),0);eq(h.released,3)
		h.parent:Destroy();eq(h.reclaim,nil)
	end)
	test("actual water renderer pauses far animation but repaints when daylight changes",function()
		local h=make();h.view.cellPixels=1;h.renderer.build("test",h.parent)
		for _=1,3 do h.check();h.paint() end
		local writes=h.writes;h.time=5;h.check();h.paint();eq(h.writes,writes)
		h.light={night=1,elevation=.1,color={.2,.3,.4}};h.check();h.paint();assert(h.writes>writes)
		h.view.cellPixels=10;h.time=10;h.check();writes=h.writes;h.paint();h.paint();assert(h.writes>writes)
		h.parent:Destroy()
	end)
	test("actual water renderer retries budget refusals and releases reclaimed images before retrying",function()
		local h=make();h.refuse=true;h.renderer.build("test",h.parent);h.check();eq(h.attempts,1);eq(h.parts(),0)
		h.check();eq(h.attempts,1);h.time=2;h.refuse=false;h.check();h.paint();eq(h.parts(),1)
		h.reclaim(1,nil);eq(h.parts(),0);eq(h.released,1)
		h.check();eq(h.parts(),0);h.time=4;h.check();h.paint();eq(h.parts(),1)
		h.parent:Destroy();eq(h.created,h.released);eq(h.warnings,0)
	end)
	test("actual water renderer disconnects on parent teardown and safely replaces an old map",function()
		local h=make();h.renderer.build("old",h.parent);h.check();h.paint();eq(h.parts(),1)
		h.renderer.build("new",h.parent);eq(h.parts(),0);eq(h.released,1)
		eq(h.heartbeat:active(),1);eq(h.render:active(),1);h.check();h.paint();eq(h.parts(),1)
		h.parent:Destroy();eq(h.parts(),0);eq(h.created,h.released);eq(h.heartbeat:active(),0);eq(h.render:active(),0);eq(h.reclaim,nil)
		local before=h.writes;h.time=20;h.check();h.paint();eq(h.writes,before);h.renderer.destroy()
	end)
	test("actual water renderer isolates invalid chunks and failed writes without warning loops",function()
		local h=make();h.meta.chunks[1][5]="broken";h.renderer.build("test",h.parent)
		for _=1,4 do h.check();h.paint() end
		eq(h.warnings,1);eq(h.parts(),2);h.parent:Destroy();eq(h.created,h.released)
		local bad=make();bad.failWrite=true;bad.renderer.build("test",bad.parent)
		for _=1,6 do bad.check();bad.paint() end
		eq(bad.warnings,3);eq(bad.parts(),0);eq(bad.created,bad.released)
		bad.parent:Destroy()
	end)
end
