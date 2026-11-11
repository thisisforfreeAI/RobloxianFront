--!strict
-- Actual renderer control flow under mocked Roblox boundaries, with locally generated source art.
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/client/DevAssets/OrigPowerLines_saddle.luau") then return end
	local luau=require("@lune/luau")
	local Power=require("../src/shared/Presentation/PowerLines")
	local data=require("../src/client/DevAssets/OrigPowerLines_saddle") ::any
	local function make(plan:any?):any
		plan=plan or data
		local h:any={time=0,hidden=false,fogChecks=0,failFull=false,created=0,released=0,writes=0,attempts=0,instances={},listeners={}}
		local function signal():any
			local s:any={items={}}
			function s:Connect(fn:any):any local item={fn=fn,on=true};table.insert(self.items,item);return{Disconnect=function() item.on=false end} end
			function s:fire(dt:number?) for _,item in self.items do if item.on then item.fn(dt) end end end
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
		h.parent=instance("Folder");h.heartbeat=signal();h.render=signal()
		local memory:any={}
		function memory.create(size:any):any
			h.attempts+=1;if h.failAll or (h.failFull and size.X==plan.width) then return nil end
			h.created+=1;local image:any={size=size}
			function image:WritePixelsBuffer() assert(not self.dead);h.writes+=1 end
			return image
		end
		function memory.release(image:any) if image then assert(not image.dead);image.dead=true;h.released+=1 end end
		function memory.register(_p:any,fn:any):any h.reclaim=fn;return function() h.reclaim=nil end end
		local function vec(x:number,y:number,z:number?):any return {X=x,Y=y,Z=z} end
		local function udim(x:number,y:number):any return {X={Scale=x},Y={Scale=y}} end
		local cf:any={};local mt={__mul=function(a:any,_b:any) return a end}
		cf.new=function(...:any) return setmetatable({...},mt) end;cf.Angles=cf.new
		local target=plan.nodes[3]
		h.view={cx=target.x,cy=target.y,rx=12,ry=10,cellPixels=10,time=0}
		local shared={Config={World="world"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"},Presentation={PowerLines="power"}}
		local modules:any={world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return vec(x*4,z,y*4) end},
			codec={base64Decode=function() return buffer.create(0) end},inflate={raw=function(_b:any,size:number) return buffer.create(size) end},power=Power,
			memory=memory,fog={hidden=function(x,y) h.fogChecks+=1;return h.hidden or (h.fog and h.fog(x,y)) or false end},light={get=function() return {shadow={0,1},shadowAlpha=1,night=0} end},
			worldlight={view=function() local v=table.clone(h.view);v.time=h.time;return v end},data=plan}
		local assets={FindFirstChild=function() return "data" end}
		h.camera={CFrame={Position=vec(target.x*4,60,target.y*4)}}
		local env:any=setmetatable({game={GetService=function(_s:any,name:string) return if name=="RunService" then {Heartbeat=h.heartbeat,RenderStepped=h.render} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",FogOverlay="fog",DaylightController="light",WorldLight="worldlight",Parent={FindFirstChild=function() return assets end}}},
			require=function(name:any) assert(modules[name],tostring(name));return modules[name] end,
			Instance={new=instance},Vector2={new=vec},Vector3={new=vec},UDim2={fromScale=udim,fromOffset=udim},CFrame=cf,
			Color3={new=vec,fromRGB=vec},Content={fromObject=function(image:any) assert(image and not image.dead);return image end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Default=0}},workspace={CurrentCamera=h.camera},os={clock=function() return h.time end}}, {__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/PowerLineRenderer.luau"),{environment=env,debugName="PowerLineRenderer_runtime_test"})()
		function h.paint() h.heartbeat:fire(.11);h.render:fire() end
		function h.parts():number local count=0;for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then count+=1;assert(obj.CanCollide==false and obj.CanQuery==false) end end;return count end
		function h.wires():{any}
			local out={}
			for _,obj in h.instances do
				if obj.ClassName=="Frame" and obj.Visible and not obj.dead and obj.ZIndex==2 and string.sub(obj.Parent.Parent.Name,1,14)=="PowerWireTile_" then
					table.insert(out,obj)
				end
			end
			return out
		end
		function h.signature():string
			local out={}
			for _,f in h.wires() do table.insert(out,string.format("%s:%.8f:%.8f:%.8f:%.8f",string.gsub(f.Parent.Parent.Name,"_Fog$",""),f.Position.X.Scale,f.Position.Y.Scale,f.Size.X.Scale,f.Rotation)) end
			table.sort(out);return table.concat(out,"|")
		end
		return h
	end
	test("actual power renderer preserves the network through fog and releases storage outside the camera view",function()
		local h=make();h.renderer.start({data={id="saddle"}},h.parent);h.paint()
		assert(h.parts()>0);eq(h.created,1);eq(h.writes,1)
		local contents={};for _,obj in h.instances do if obj.ImageContent then contents[obj.ImageContent]=true end end
		local count=0;for _ in contents do count+=1 end;eq(count,1)
		local parts,wires,signature=h.parts(),#h.wires(),h.signature();assert(wires>0)
		h.hidden=true;h.time=4;h.paint();eq(h.parts(),parts);eq(#h.wires(),wires);eq(h.signature(),signature);eq(h.released,0)
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then assert(obj.CFrame[1].Y>.4,"fogged power art must sit above the fog") end end
		h.hidden=false;h.paint();eq(h.parts(),parts);eq(h.signature(),signature)
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then assert(obj.CFrame[1].Y<.3,"revealed power art must return below unit sprites") end end
		h.view.cx=-10000;h.view.cy=-10000;h.time=8;h.paint();eq(h.parts(),0);eq(h.released,1)
		h.parent:Destroy();eq(h.reclaim,nil)
	end)
	test("actual power renderer uses half atlas after refusal and tears down reclaimed views",function()
		local h=make();h.failFull=true;h.view.rx=1000;h.view.ry=1000
		h.renderer.start({data={id="saddle"}},h.parent);h.paint()
		eq(h.attempts,2);eq(h.created,1);assert(h.parts()>#data.nodes)
		h.reclaim();eq(h.parts(),0);eq(h.released,1)
		h.time=6;h.paint();eq(h.created,2);assert(h.parts()>0)
		h.parent:Destroy();eq(h.parts(),0);eq(h.released,2);eq(h.reclaim,nil)
		local before=h.created;h.time=20;h.paint();eq(h.created,before)
	end)
	test("actual renderer includes every network anchor and covers every span without overlapping canvases",function()
		local h=make();h.view.rx=1000;h.view.ry=1000;h.renderer.start({data={id="saddle"}},h.parent);h.paint()
		local anchors=0;local tiles={};local lines={}
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then
			local height=obj.CFrame[1].Y;assert(height<.3,"revealed power art must retain its usual depth")
			local tx,ty=string.match(obj.Name,"^PowerWireTile_(-?%d+):(-?%d+)$")
			if tx then
				assert(not tiles[obj.Name]);tiles[obj.Name]=true
				local pos=obj.CFrame[1];eq(pos.X,(tonumber(tx)*8+4)*4);eq(pos.Z,(tonumber(ty)*8+4)*4)
			else anchors+=1 end
		end end
		eq(anchors,#data.nodes)
		for _,f in h.wires() do
			assert(f.Size.Y.Scale>=1)
			local tx,ty=string.match(f.Parent.Parent.Name,"^PowerWireTile_(-?%d+):(-?%d+)$")
			local key=tx..":"..ty;lines[key]=lines[key] or {}
			table.insert(lines[key],{x=tonumber(tx)*8+f.Position.X.Scale/h.view.cellPixels,y=tonumber(ty)*8+f.Position.Y.Scale/h.view.cellPixels,
				half=f.Size.X.Scale/h.view.cellPixels/2,angle=math.rad(f.Rotation)})
		end
		for _,link in data.links do for _,path in Power.curves(data,link,0,h.view.cellPixels,0,4) do
			for j=2,#path do for _,s in Power.sections(path[j-1],path[j],function() return true end,8) do
				local x,y=(s.a.x+s.b.x)/2,(s.a.y+s.b.y)/2;local covered=false
				for _,f in lines[s.tx..":"..s.ty] or {} do
					local dx,dy=x-f.x,y-f.y;local c,n=math.cos(f.angle),math.sin(f.angle)
					if math.abs(dx*c+dy*n)<=f.half+1e-8 and math.abs(-dx*n+dy*c)<1e-7 then covered=true;break end
				end
				assert(covered,"missing a wire section on span "..link.a..":"..link.b)
			end end
		end end
		h.view.cellPixels=3;h.paint();anchors=0
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead and not string.find(obj.Name,"PowerWireTile_",1,true) then anchors+=1 end end
		eq(anchors,#data.nodes);h.parent:Destroy()
	end)
	test("actual renderer freezes dry weather wires and preserves wet weather on partial snapshots",function()
		local h=make();h.renderer.start({data={id="saddle"}},h.parent)
		for _,weather in {"clear","fog","sandstorm"} do
			h.renderer.setWeather(weather);h.time=0;h.paint();local before=h.signature();assert(#before>0)
			h.time=1;h.paint();eq(h.signature(),before)
		end
		for _,weather in {"downpour","storm"} do
			h.renderer.setWeather(weather);h.time=0;h.paint();local before=h.signature()
			h.renderer.setWeather(nil);h.time=1;h.paint();assert(h.signature()~=before)
		end
		h.parent:Destroy()
	end)
	test("actual renderer retains anchor fallbacks when all image allocations are refused",function()
		local h=make();h.failAll=true;h.renderer.start({data={id="saddle"}},h.parent);h.paint()
		eq(h.created,0);eq(h.writes,0);assert(h.parts()>0);assert(#h.wires()>0)
		local visibleDots=0
		for _,obj in h.instances do if obj.ClassName=="ImageLabel" and not obj.dead then eq(obj.Visible,false)
		elseif obj.ClassName=="Frame" and obj.Visible and obj.Parent.ClassName=="SurfaceGui" and not string.find(obj.Parent.Parent.Name,"PowerWireTile_",1,true) then visibleDots+=1 end end
		assert(visibleDots>0);h.time=1;h.paint();eq(h.attempts,2);h.parent:Destroy();eq(h.parts(),0)
	end)
	test("actual renderer draws full spans and their anchors across mixed fog cells",function()
		local plan=table.clone(data)
		plan.nodes={{id=1,x=0,y=4.5,ax=1,ay=0,plant=true},{id=2,x=20,y=4.5,ax=1,ay=0,steel=true,phase=0},{id=3,x=25,y=4.5,ax=1,ay=0,steel=true,phase=0}}
		plan.links={{a=2,b=1}}
		local h=make(plan);h.view.cx=10;h.view.cy=4.5;h.view.rx=30
		h.fog=function(x) return x<8 or x>=16 end
		h.renderer.start({data={id="saddle"}},h.parent);h.paint();assert(#h.wires()>0)
		local tiles={};local anchors=0
		for _,f in h.wires() do
			local tx=tonumber(string.match(f.Parent.Parent.Name,"^PowerWireTile_(-?%d+):"));tiles[tx]=true
			eq(f.Parent.ClipsDescendants,true)
		end
		assert(tiles[0] and tiles[1] and tiles[2],"fog must not cut out the hidden ends")
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead and not string.find(obj.Name,"PowerWireTile_",1,true) then anchors+=1 end end
		eq(anchors,#plan.nodes)
		for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then
			local isWire=string.find(obj.Name,"PowerWireTile_",1,true)~=nil
			local fogged=not isWire or string.match(obj.Name,"_Fog$")~=nil
			if fogged then assert(obj.CFrame[1].Y>.4) else assert(obj.CFrame[1].Y<.3) end
		end end
		-- Alternating cells also put both layers inside the same tile, rather than only tile edges.
		h.fog=function(x) return math.floor(x)%2==0 end;h.paint()
		local segments={}
		for _,f in h.wires() do
			local tx,ty=string.match(f.Parent.Parent.Name,"^PowerWireTile_(-?%d+):(-?%d+)")
			table.insert(segments,{x=tonumber(tx)*8+f.Position.X.Scale/h.view.cellPixels,y=tonumber(ty)*8+f.Position.Y.Scale/h.view.cellPixels,
				half=f.Size.X.Scale/h.view.cellPixels/2,angle=math.rad(f.Rotation)})
		end
		for _,path in Power.curves(plan,plan.links[1],0,h.view.cellPixels,0,4) do for j=2,#path do
			local a,b=path[j-1],path[j];local steps=math.max(1,math.ceil(math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)*4))
			for n=0,steps-1 do
				local t=(n+.5)/steps;local x,y=a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t;local found=false
				for _,f in segments do
					local dx,dy=x-f.x,y-f.y;local c,s=math.cos(f.angle),math.sin(f.angle)
					if math.abs(dx*c+dy*s)<=f.half+1e-8 and math.abs(-dx*s+dy*c)<1e-7 then found=true;break end
				end
				assert(found,"wire gap at an internal fog boundary")
			end
		end end
		h.parent:Destroy()
	end)
	test("raised fog wire canvases stay on the same camera rays through pan and zoom and disconnect on teardown",function()
		local h=make();h.hidden=true;h.renderer.start({data={id="saddle"}},h.parent);h.paint()
		for _,camera in {{X=0,Y=16,Z=0},{X=300,Y=120,Z=150},{X=-25,Y=40,Z=900}} do
			h.camera.CFrame.Position=camera;h.render:fire()
			local count=0
			for _,obj in h.instances do if obj.ClassName=="Part" and not obj.dead then
				local tx,ty=string.match(obj.Name,"^PowerWireTile_(-?%d+):(-?%d+)_Fog$")
				if tx then
					count+=1;local pos=obj.CFrame[1];local ratio=(camera.Y-pos.Y-.005)/(camera.Y-.22-.005)
					local x=(tonumber(tx)*8+4)*4;local y=(tonumber(ty)*8+4)*4
					assert(math.abs((pos.X-camera.X)/(camera.Y-pos.Y-.005)-(x-camera.X)/(camera.Y-.22-.005))<1e-9)
					assert(math.abs((pos.Z-camera.Z)/(camera.Y-pos.Y-.005)-(y-camera.Z)/(camera.Y-.22-.005))<1e-9)
					assert(math.abs(obj.Size.X-32*ratio)<1e-9);assert(math.abs(obj.Size.Z-32*ratio)<1e-9)
				end
			end end
			assert(count>0)
		end
		h.parent:Destroy();for _,listener in h.render.items do eq(listener.on,false) end
		h.camera.CFrame.Position={X=0,Y=80,Z=0};h.render:fire();eq(h.parts(),0)
	end)
end
