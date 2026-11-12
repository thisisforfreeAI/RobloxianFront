--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	local function fixture():any
		local h:any={time=0,instances={}}
		local function signal():any local s:any={fns={}};function s:Connect(fn) table.insert(self.fns,fn) end;function s:fire() for _,fn in self.fns do fn() end end;return s end
		local function instance(class):any local o:any={ClassName=class,Destroying=signal()};function o:Destroy() self.dead=true;self.Destroying:fire() end;table.insert(h.instances,o);return o end
		local shared={Presentation={FactoryMotion="motion"},Utilities={Rng="rng"}}
		local modules={motion=require("../src/shared/Presentation/FactoryMotion"),rng=require("../src/shared/Utilities/Rng")}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},require=function(key) return modules[key] end,
			Instance={new=instance},Color3=roblox.Color3,Vector2=roblox.Vector2,UDim2=roblox.UDim2,Content={fromObject=function(image) return image end},Enum={ResamplerMode={Pixelated=1}},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/FactoryRenderer.luau"),{environment=env})()
		h.meta={factory={frame=144,cells=3,fps=12,doorSec=.5,doorHoldSec=2,door={base=1,paint=2,frame=48,cells=1},
			doors={{-.4,.3,.6,.3},{.4,.3,.6,.3}},crane={x=.6,y=.1,run=.5,sec=6},craneArt={base=1,paint=2,frame=48,cells=1},
			weld={x0=-.3,y0=.2,x1=.2,y1=.5,count=2,px=1.5,inks={"#ffffff","#ffcc88"}}}}
		h.sheet={image={},meta={rects={["1"]={2,2,48,48,0,0},["2"]={54,2,48,48,0,0}}}}
		function h:attach() local gui=instance("SurfaceGui");return self.renderer.attach(gui,self.meta,self.sheet) end
		function h:sync(view,built,stale,sample)
			self.renderer.sync(view,built,stale,sample,7,roblox.Color3.new(1,1,1),roblox.Color3.new(.5,.6,.7),if stale then .22 else 0)
		end
		return h
	end
	test("factory parts share the existing atlas and work animates at frame cadence without creating images or instances",function()
		local h=fixture();local view=h:attach();h:sync(view,1,false,{1,0});local count=#h.instances
		local initial=view.crane.base.label.Position
		for i=1,5 do h.time=i*.1;h:sync(view,1,false,{1,0});h.renderer.step() end
		assert(view.crane.base.label.Position~=initial);eq(#h.instances,count)
		for _,door in view.doors do eq(door.base.label.Visible,false);eq(door.base.label.ImageContent,h.sheet.image) end
		for _,object in h.instances do assert(object.ClassName~="EditableImage") end
	end)
	test("construction and fog suppress operational cues, with grey static remembered parts",function()
		local h=fixture();local view=h:attach();h:sync(view,.5,false,{1,0})
		for _,item in view.all do eq(item.Visible,false) end
		h:sync(view,1,false,{1,0});h.time=.1;h:sync(view,1,false,{1,1});h:sync(view,1,true,nil)
		eq(view.state.open,0);eq(view.state.busy,false)
		for _,spark in view.sparks do eq(spark.Visible,false) end
		local pos=view.crane.base.label.Position;h.time=.2;h.renderer.step();eq(view.crane.base.label.Position,pos)
		for _,door in view.doors do eq(door.base.label.Visible,true);eq(door.base.label.ImageTransparency,.22) end
	end)
	test("factory views expire offscreen and teardown removes all animation records",function()
		local h=fixture();local view=h:attach();h:sync(view,1,false,{1,0});h.time=1;h.renderer.step()
		eq(view.at,nil);eq(view.state.busy,false);for _,spark in view.sparks do eq(spark.Visible,false) end
		view.gui:Destroy();eq(h.renderer.count(),0)
		local nextView=h:attach();h:sync(nextView,1,false,{1,0});h.renderer.reset();eq(h.renderer.count(),0)
		for _,item in nextView.all do eq(item.dead,true) end
	end)
	test("legacy art remains static and Republic factory layouts omit the Coalition crane",function()
		local h=fixture();eq(h.renderer.attach({}, {}, h.sheet),nil)
		h.meta.factory.craneArt=nil;local view=h:attach();eq(next(view.crane),nil);h:sync(view,1,false,{1,0});h.renderer.step()
	end)
end
