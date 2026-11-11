--!strict
-- Execute actual native renderer with mocked service/image boundaries.
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	if not fs.isFile("src/shared/GameData/FireLightRules.luau") then return end
	local config=require("../src/shared/GameData/FireLightRules")
	local function fixture():any
		local h:any={time=0,instances={},created=0,released=0,writes=0,attempts=0,night=1,hidden=false,nv=false,
			view={cx=16,cy=16,rx=12,ry=12,cellPixels=10}}
		local function signal():any
			local s:any={items={}}
			function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire() for _,c in table.clone(self.items) do if not c.dead then c.fn() end end end;return s
		end
		local function instance(class):any
			local o:any={ClassName=class,Destroying=signal()}
			function o:Destroy()
				if self.dead then return end;self.dead=true;self.Destroying:fire()
				for _,child in h.instances do if child.Parent==self then child:Destroy() end end
			end
			table.insert(h.instances,o);return o
		end
		h.heartbeat=signal();h.parent=instance("Folder")
		local memory={create=function(size,kind)
			h.attempts+=1;eq(kind,"detail");assert(size.X<=48 and size.Y<=48)
			if h.deny then return nil end;h.created+=1
			local image:any={}
			function image:WritePixelsBuffer(_origin,dimensions,px)
				assert(not self.dead);eq(buffer.len(px),dimensions.X*dimensions.Y*4);h.writes+=1;self.pixels=px
			end;return image
		end,release=function(image) if image then assert(not image.dead);image.dead=true;h.released+=1 end end,
		register=function(_priority,fn) h.reclaim=fn;return function() h.reclaim=nil end end}
		local data={FindFirstChild=function() return if h.missing then nil else "config" end}
		local shared:any={Presentation={FireLight="light",FireLightPixels="pixels",NightLightPixels="nightpixels"},Config={World="world"},FindFirstChild=function() return data end}
		local modules:any={light=require("../src/shared/Presentation/FireLight"),pixels=require("../src/shared/Presentation/FireLightPixels"),
			nightpixels=require("../src/shared/Presentation/NightLightPixels"),world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2},config=config,memory=memory,
			daylight={get=function() return {night=h.night} end,postEffect=function() return {tint={1,1,1},contrast=0} end},
			fog={hidden=function(x) return h.hidden or h.fogFrom and x>=h.fogFrom end},worldlight={view=function() return h.view end}}
		local env:any=setmetatable({game={GetService=function(_,key) return if key=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",DaylightController="daylight",FogOverlay="fog",WorldLight="worldlight"}},
			require=function(key) return assert(modules[key],key) end,workspace={CurrentCamera={}},
			Instance={new=instance},Vector2=roblox.Vector2,Vector3=roblox.Vector3,CFrame=roblox.CFrame,Color3=roblox.Color3,
			UDim2={fromScale=function(x,y) return {x,y} end},Content={fromObject=function(image) assert(image and not image.dead);return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}},
			Random={new=function() return {NextNumber=function() return .5 end} end},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/FireLightRenderer.luau"),{environment=env})()
		function h.start() h.session=h.renderer.start({width=64,height=64},h.parent);return h.session end
		function h.fire() h.session.advance({{x=15.8,y=15.8,cell=975}},{{x=15.6,y=15.6,cell=975}},.25) end
		function h.paint(dt) h.time+=dt or .1;h.heartbeat:fire() end
		function h.active(class)
			local out={};for _,o in h.instances do if o.ClassName==class and not o.dead then table.insert(out,o) end end;return out
		end
		return h
	end
	test("actual fire glow merges forest and house light pools on disjoint anchored tiles",function()
		local h=fixture();h.start();h.fire();h.paint();eq(h.created,2);h.paint();eq(h.created,4)
		for _,part in h.active("Part") do assert(math.abs(part.CFrame.Position.Y-.23)<1e-7);eq(part.Size.X,64);eq(part.Size.Z,64) end
		local original={};for _,part in h.active("Part") do original[part.Name]=part.CFrame end
		h.view.cx+=.2;h.view.cy-=.2;h.paint()
		for _,part in h.active("Part") do eq(part.CFrame,original[part.Name]) end
		for _,label in h.active("ImageLabel") do assert(label.Visible);assert(label.Parent.Brightness>1) end
		h.parent:Destroy();eq(h.released,h.created);eq(h.reclaim,nil)
	end)
	test("actual fire glow removes hidden sources and allocates nothing for hidden or distant fires",function()
		local h=fixture();h.hidden=true;h.start();h.fire();h.paint();eq(h.created,0)
		h.hidden=false;h.session.reset();h.fire();h.view.cellPixels=1;h.paint();eq(h.created,0)
		h.view.cellPixels=10;h.paint();assert(h.created>0)
		h.hidden=true;h.paint(.01);eq(#h.active("Part"),0);eq(h.released,h.created)
		h.parent:Destroy()
	end)
	test("actual fire glow backs off image refusal and reclamation then cleans every callback",function()
		local h=fixture();h.deny=true;h.start();h.fire();h.paint();eq(h.attempts,1)
		h.deny=false;for _=1,10 do h.paint() end;eq(h.attempts,1)
		h.paint(5);assert(h.created>0);h.reclaim();eq(h.released,h.created);h.paint();eq(#h.active("Part"),0)
		h.paint(5);assert(#h.active("Part")>0)
		h.session.destroy();local writes=h.writes;h.paint(6);eq(h.writes,writes);eq(h.released,h.created)
		for _,c in h.heartbeat.items do assert(c.dead) end;eq(h.reclaim,nil)
	end)
	test("actual fire glow handles night vision, zoom resolution, paused time and reset",function()
		local h=fixture();h.start();h.fire();h.paint();local first=h.active("ImageLabel")[1].ImageContent.pixels
		h.session.setNightVision(true);h.paint();local nv=h.active("ImageLabel")[1].ImageContent.pixels
		assert(buffer.tostring(first)~=buffer.tostring(nv));local created=h.created
		h.view.cellPixels=4;h.paint();assert(h.released>=created)
		for _,label in h.active("ImageLabel") do eq(buffer.len(label.ImageContent.pixels),32*32*4) end
		h.paint(20);assert(#h.active("Part")>0,"wall time must not age paused war lights")
		h.session.advance({}, {},8);h.paint();eq(#h.active("Part"),0)
		h.session.reset();h.fire();h.paint();assert(#h.active("Part")>0)
		h.session.reset();eq(#h.active("Part"),0);h.parent:Destroy()
	end)
	test("actual fire glow skips missing settings and returns to daylight without stale pools",function()
		local h=fixture();h.missing=true;eq(h.start(),nil);eq(h.reclaim,nil);eq(h.created,0)
		h.missing=false;h.night=0;h.start();h.fire();h.paint();eq(h.created,0)
		h.night=1;h.session.reset();h.fire();h.paint();assert(h.created>0)
		h.night=0;h.paint();eq(#h.active("Part"),0);eq(h.released,h.created);h.parent:Destroy()
	end)
end
