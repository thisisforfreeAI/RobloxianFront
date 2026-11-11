--!strict
-- Execute the actual renderer under a small Roblox boundary mock, not just projection helpers.
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	local luau=require("@lune/luau")
	local Clouds=require("../src/shared/Presentation/CloudField")
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	local function fixture():any
		local h:any={time=0,instances={},bindings={},writes=0,created=0,released=0,deny=false,view={cx=0,cy=0,rx=10,ry=8,time=0,cellPixels=10}}
		local function signal():any
			local s:any={listeners={}}
			function s:Connect(fn:any):any
				local item={fn=fn,on=true};table.insert(self.listeners,item)
				return {Disconnect=function() item.on=false end}
			end
			function s:fire() for _,item in table.clone(self.listeners) do if item.on then item.fn() end end end
			return s
		end
		local function instance(class:string):any
			local obj:any={ClassName=class,Name=class,Destroying=signal(),Visible=true}
			function obj:Destroy()
				if self.dead then return end;self.dead=true;self.Destroying:fire()
				for _,child in h.instances do if child.Parent==self then child:Destroy() end end
			end
			table.insert(h.instances,obj);return obj
		end
		h.parent=instance("Folder");local playerGui=instance("PlayerGui")
		h.light={night=0,golden=0,mul={1,1,1},add={0,0,0},color={1,1,1},shadow={1,0},toward={0,-1},phase=.3,elevation=1}
		local config={scale=12,dx=2,dy=.5,cover=.5,step=.1,body=.3,color={.75,.75,.7},parallax=.18,nightThin=.45,golden=.25,shadow=.22,shadowReach=8,shadowMax=16,hidePx=3,showPx=6}
		h.config=config
		local run:any={Heartbeat=signal()}
		function run:BindToRenderStep(name:string,priority:number,fn:any) h.bindings[name]={priority=priority,fn=fn} end
		function run:UnbindFromRenderStep(name:string) h.bindings[name]=nil end
		local memory:any={}
		function memory.create(_size:any,_kind:any):any
			if h.deny then return nil end
			h.created+=1
			local image:any={}
			function image:WritePixelsBuffer(_from:any,_size:any,_pixels:any) assert(not self.dead);h.writes+=1 end
			return image
		end
		function memory.release(image:any) if image then assert(not image.dead);image.dead=true;h.released+=1 end end
		function memory.register(_priority:any,fn:any):any h.reclaim=fn;return function() h.reclaim=nil end end
		local data:any={FindFirstChild=function(_self:any,name:string):any return if name=="CloudLook" then "config" elseif name=="WorldLook" then "worldlook" else nil end}
		local shared:any={Presentation={CloudField="clouds",GroundWetness="noise",ScreenLight="pixels"},Config={World="world"}}
		function shared:FindFirstChild(name:string):any return if name=="GameData" then data else nil end
		local services={RunService=run,ReplicatedStorage={WaitForChild=function() return shared end},Players={LocalPlayer={WaitForChild=function() return playerGui end}}}
		local function pair(x:number,y:number):any return {X=x,Y=y} end
		local function scale(x:number,y:number):any return {X={Scale=x},Y={Scale=y}} end
		local modules:any={clouds=Clouds,noise={valueNoise=function() return 1 end},config=config,memory=memory,
			light={get=function() return h.light end},worldlight={view=function() local v=table.clone(h.view);v.time=h.time;return v end},
			world={STUDS_PER_CELL=4,GROUND_Y=0},worldlook={},
			pixels={pixels=function(...:any):buffer h.lightArgs=select("#",...);return buffer.create(192*128*4) end}}
		local env:any=setmetatable({game={GetService=function(_self:any,name:string) return services[name] end},
			script={Parent={ImageMemory="memory",DaylightController="light",WorldLight="worldlight"}},
			require=function(name:any) assert(modules[name],"missing mock module "..tostring(name));return modules[name] end,
			Instance={new=instance},Vector2={new=pair},UDim2={fromScale=scale},Color3={new=function(r,g,b) return {R=r,G=g,B=b} end},
			Content={fromObject=function(image:any) assert(image and not image.dead);return image end},
			Enum={ResamplerMode={Default=0},RenderPriority={Camera={Value=200}}},
			workspace={CurrentCamera={CFrame={Position={X=0,Y=220,Z=0}},FieldOfView=30,ViewportSize={X=1280,Y=800}}},
			os={clock=function() return h.time end}}, {__index=getfenv()})
		function h.load(name:string):any return luau.load(fs.readFile("src/client/Rendering/"..name..".luau"),{environment=env,debugName=name.."_runtime_test"})() end
		function h.paint() run.Heartbeat:fire() end
		function h.render() for _,binding in h.bindings do binding.fn() end end
		function h.label(guiName:string):any
			for _,obj in h.instances do if obj.ClassName=="ImageLabel" and obj.Parent and obj.Parent.Name==guiName and not obj.dead then return obj end end
			return nil
		end
		function h.worldAt(label:any,u:number,v:number):(number,number)
			local sx=label.Position.X.Scale+(u-.5)*label.Size.X.Scale
			local sy=label.Position.Y.Scale+(v-.5)*label.Size.Y.Scale
			return h.view.cx+(sx-.5)*h.view.rx*2,h.view.cy+(sy-.5)*h.view.ry*2
		end
		return h
	end
	test("actual cloud renderer retains its painted cache and reprojects without another texture write",function()
		local h=fixture();h.load("CloudRenderer").start(h.parent);h.paint();h.render()
		local body=h.label("Clouds");assert(body and body.Visible,"painting must publish the cache to the render callback")
		local x,y=h.worldAt(body,.5,.5);local writes=h.writes
		h.view.cx=3;h.view.cy=-2;h.view.rx=8;h.view.ry=6;h.render()
		local afterX,afterY=h.worldAt(body,.5,.5);close(afterX,x);close(afterY,y);eq(h.writes,writes);assert(body.Visible)
		h.time=.1;h.render();afterX,afterY=h.worldAt(body,.5,.5);close(afterX,x-.2);close(afterY,y-.05)
		h.parent:Destroy()
	end)
	test("actual cloud body and shadow share one image and both stay anchored during camera movement",function()
		local h=fixture();h.load("CloudRenderer").start(h.parent);h.paint();h.render()
		local body,shadow=h.label("Clouds"),h.label("CloudShadows")
		assert(body and shadow and body.Visible and shadow.Visible)
		eq(body.ImageContent,shadow.ImageContent);eq(h.created,1)
		for _,cx in {0,2,-2} do
			h.view.cx=cx;h.render()
			local bx,by=h.worldAt(body,.5,.5);local sx,sy=h.worldAt(shadow,.5,.5)
			close(sx-bx,8);close(sy-by,0)
		end
		h.light.night=1;h.render();assert(body.Visible);assert(not shadow.Visible)
		h.parent:Destroy();eq(h.released,1);eq(h.bindings.WarFrontClouds,nil);eq(h.reclaim,nil)
	end)
	test("actual cloud renderer survives image refusal, retries, and disconnects on teardown",function()
		local h=fixture();h.deny=true
		h.load("CloudRenderer").start(h.parent);h.paint();h.render();eq(h.created,0);eq(h.writes,0)
		h.deny=false;h.time=6;h.paint();h.render();assert(h.label("Clouds").Visible);eq(h.created,1)
		h.reclaim();h.render();assert(not h.label("Clouds").Visible);eq(h.released,1)
		h.parent:Destroy();eq(h.bindings.WarFrontClouds,nil)
	end)
	test("actual world-light renderer no longer bakes camera-pinned cloud shadows",function()
		local h=fixture();h.load("WorldLight").start();eq(h.lightArgs,4)
	end)
	test("actual cloud repaints keep their texel grid fixed in world space during small pans",function()
		local h=fixture();h.config.dx=0;h.config.dy=0
		h.load("CloudRenderer").start(h.parent);h.paint();h.render()
		local body=h.label("Clouds");assert(body.Visible)
		local originX,originY=h.worldAt(body,.5/128,.5/80)
		local step=body.Size.X.Scale*h.view.rx*2/128
		for i=1,4 do
			h.time=i*.2;h.view.cx=i*.17;h.view.cy=-i*.13;h.paint();h.render()
			local x,y=h.worldAt(body,.5/128,.5/80)
			close((x-originX)/step,math.floor((x-originX)/step+.5))
			close((y-originY)/step,math.floor((y-originY)/step+.5))
		end
		eq(h.writes,5);eq(h.created,1);h.parent:Destroy()
	end)
end
