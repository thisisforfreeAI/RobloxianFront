--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	local function fixture():any
		local h:any={time=0,created=0,released=0,instances={},blocked=false,warnings=0}
		local function signal():any
			local s:any={items={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire(dt) for _,c in table.clone(self.items) do if not c.dead then c.fn(dt) end end end;return s
		end
		local function instance(class):any
			local o:any={ClassName=class,Destroying=signal()}
			function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		h.parent=instance("Folder");h.heartbeat=signal()
		local memory={create=function() h.created+=1;return {WritePixelsBuffer=function() end} end,release=function(img) if img then h.released+=1 end end}
		local shared:any={Presentation={NightWindows="windows",NightLightPixels="pixels",GroundWetness="noise"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Config={World="world"}}
		local modules:any={windows=require("../src/shared/Presentation/NightWindows"),pixels={compensate=function() return {brightness=4,color={1,1,1}} end},
			noise={hash21=function() return .2 end},codec={base64Decode=function() return buffer.create(4) end},inflate={raw=function() return buffer.create(4) end},
			world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2},memory=memory,daylight={get=function() return {night=1} end,postEffect=function() return {} end}}
		local env:any=setmetatable({game={GetService=function(_,key) return if key=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",DaylightController="daylight"}},require=function(key) return assert(modules[key],key) end,
			Instance={new=instance},Vector2=roblox.Vector2,Vector3=roblox.Vector3,CFrame=roblox.CFrame,
			-- Lune Color3 supports arithmetic that Studio rejects; keep this boundary strict.
			Color3={new=function(r,g,b)
				if h.failColor then error("synthetic color creation failure") end
				return setmetatable({R=r,G=g,B=b},{__mul=function() error("Color3 multiplication is unavailable in Studio") end})
			end},warn=function() h.warnings+=1 end,
			UDim2={fromScale=function(x,y) return {x,y} end},Content={fromObject=function(img) return img end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Default=0}},
			workspace={CurrentCamera={CFrame=roblox.CFrame.new(28,100,28),FieldOfView=30,ViewportSize=roblox.Vector2.new(800,800)}},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/NightWindowRenderer.luau"),{environment=env})()
		function h.start()
			h.state=h.renderer.start({points={{95,95,21,21,0,1,1}},slot=12,pixelsPerCell=14,perRow=1,width=1,height=1,deflate=""},
				{windows=.5,flickerSec=10,fine=3,city={nearFrom=5,nearTo=9},color={1,1,1}},h.parent,0,{
					blocked=function() h.queries=(h.queries or 0)+1;return h.blocked end,any=function() return true end,version=function() return tostring(h.blocked) end})
		end
		function h.paint() h.time+=.1;h.heartbeat:fire(.1) end
		function h.parts() local count=0;for _,o in h.instances do if o.ClassName=="Part" and not o.dead then count+=1 end end;return count end
		return h
	end
	test("actual side-window renderer removes ruined facade/emission and restores using its existing atlas",function()
		local h=fixture();h.start();h.paint();eq(h.parts(),1);eq(h.created,1)
		local queries=h.queries;h.paint();eq(h.queries,queries)
		h.blocked=true;h.paint();eq(h.parts(),0);eq(h.created,1)
		h.blocked=false;h.paint();eq(h.parts(),1);eq(h.created,1)
		h.parent:Destroy();eq(h.released,1);for _,c in h.heartbeat.items do assert(c.dead) end
	end)
	test("actual side-window renderer never creates a facade for an already damaged roof",function()
		local h=fixture();h.blocked=true;h.start();h.paint();eq(h.parts(),0)
		h.parent:Destroy();eq(h.released,h.created)
	end)
	test("window colors avoid unsupported Color3 arithmetic and unexpected failures stop cleanly once",function()
		local h=fixture();h.start();h.paint();eq(h.parts(),1);eq(h.warnings,0)
		local broken=fixture();broken.failColor=true;broken.start();broken.paint();eq(broken.warnings,1);eq(broken.parts(),0);eq(broken.created,broken.released)
		broken.failColor=false;for _=1,5 do broken.paint() end;eq(broken.warnings,1);eq(broken.parts(),0)
		for _,c in broken.heartbeat.items do assert(c.dead) end
		h.parent:Destroy()
	end)
	test("actual city-light controller forwards the current damage mask through deferred preparation",function()
		local callbacks={};local heartbeat:any={Connect=function(_,fn) table.insert(callbacks,fn);return {Disconnect=function() end} end}
		local root={Destroying={Connect=function() end}};function root:Destroy() end
		local meta={mapWidth=1,mapHeight=1,width=1,height=1,scale=1,deflate="",windows={}}
		local modules:any
		modules={world={},codec={base64Decode=function() return buffer.create(4) end},inflate={raw=function() return buffer.create(4) end},
			pixels={prepare=function() return {} end},noise={hash21=function() return .2 end},memory={},
			daylight={get=function() return {night=1} end},config={nightLights={}},meta=meta,
			windows={start=function(_data,_profile,_parent,_born,damage) modules.check=damage.blocked;return {} end}}
		local shared:any={Presentation={NightLightPixels="pixels",GroundWetness="noise"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Config={World="world"},
			FindFirstChild=function() return {FindFirstChild=function() return "config" end} end}
		local env:any=setmetatable({game={GetService=function(_,key) return if key=="RunService" then {Heartbeat=heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={Parent={FindFirstChild=function() return {FindFirstChild=function() return "meta" end} end},ImageMemory="memory",DaylightController="daylight",NightWindowRenderer="windows"}},
			require=function(k) return assert(modules[k],k) end,Instance={new=function() return root end},task={spawn=function(fn) fn() end}},{__index=getfenv()})
		local renderer=luau.load(fs.readFile("src/client/Rendering/NightLightRenderer.luau"),{environment=env})()
		renderer.start({width=1,height=1,data={id="test"}},root);renderer.setFireMask({blocked=function(x,y) return x==4 and y==5 end})
		callbacks[1](.1);assert(modules.check(4,5));eq(modules.check(3,5),false)
		renderer.setFireMask(nil);eq(modules.check(4,5),false)
	end)
end
