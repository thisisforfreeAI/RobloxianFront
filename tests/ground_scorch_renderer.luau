--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	if not fs.isFile("src/shared/GameData/GroundScorchRules.luau") then return end
	local Packets=require("../src/shared/Protocol/GroundScorchPackets")
	local function fixture():any
		local h:any={time=0,instances={},attempts=0,created=0,released=0,writes=0,view={cx=16,cy=16,rx=40,ry=40}}
		local function signal():any
			local s:any={items={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire(dt) for _,c in table.clone(self.items) do if not c.dead then c.fn(dt) end end end;return s
		end
		local function instance(class):any
			local o:any={ClassName=class,Destroying=signal()}
			function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,c in h.instances do if c.Parent==self then c:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		h.heartbeat=signal();h.parent=instance("Folder")
		local memory={create=function(size,kind)
			h.attempts+=1;eq(kind,"detail");assert(size.X<=32 and size.Y<=32);if h.deny then return nil end
			h.created+=1;local img:any={}
			function img:WritePixelsBuffer(_from,size,px) assert(not self.dead);eq(buffer.len(px),size.X*size.Y*4);h.writes+=1;self.pixels=px end;return img
		end,release=function(img) if img then assert(not img.dead);img.dead=true;h.released+=1 end end,
		register=function(_priority,fn) h.reclaim=fn;return function() h.reclaim=nil end end}
		local data={FindFirstChild=function() return if h.missing then nil else "config" end}
		local shared:any={Presentation={GroundScorchView="view"},Config={World="world"},FindFirstChild=function() return data end}
		local modules:any={view=require("../src/shared/Presentation/GroundScorchView"),world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2},
			town={setGroundScorch=function(buckets,_config,source) h.townBuckets=buckets;h.townSource=source;h.townUpdates=(h.townUpdates or 0)+1 end},
			roof={source=function() h.sourceRequests=(h.sourceRequests or 0)+1;return if h.pendingRoof then nil else {width=64,height=64,tileSize=14} end},
			config=require("../src/shared/GameData/GroundScorchRules"),memory=memory,fog={hidden=function(x) return h.hidden or h.fogFrom and x>=h.fogFrom end},worldlight={view=function() return h.view end}}
		local env:any=setmetatable({game={GetService=function(_,key) return if key=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",FogOverlay="fog",WorldLight="worldlight",TownRenderer="town",FireScorchRenderer="roof"}},require=function(k) return assert(modules[k],k) end,
			workspace={CurrentCamera={}},Instance={new=instance},Vector2=roblox.Vector2,Vector3=roblox.Vector3,CFrame=roblox.CFrame,
			UDim2={fromScale=function(x,y) return {x,y} end},Content={fromObject=function(img) assert(img and not img.dead);return img end},
			Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/GroundScorchRenderer.luau"),{environment=env})()
		function h.start() return h.renderer.start({width=64,height=64},h.parent) end
		function h.apply(rows,epoch,reset) h.renderer.apply({epoch=epoch or 1,reset=reset,rows=Packets.encode(rows),tones=Packets.tones(rows)}) end
		function h.paint(dt) dt=dt or .2;h.time+=dt;h.heartbeat:fire(dt) end
		function h.active(class) local out={};for _,o in h.instances do if o.ClassName==class and not o.dead then table.insert(out,o) end end;return out end
		return h
	end
	test("actual ground-scar tiles stay on the map beneath town art and reuse images while fading",function()
		local h=fixture();assert(h.start());h.apply({{10*64+10,255},{10*64+11,180}});h.paint();eq(h.created,1)
		local part=h.active("Part")[1];assert(math.abs(part.CFrame.Position.Y-.04)<1e-7)
		local anchored=part.CFrame;h.view.cx+=1;h.view.cy-=1;h.paint();eq(h.active("Part")[1].CFrame,anchored)
		local writes=h.writes;h.paint();eq(h.writes,writes)
		h.apply({{10*64+10,100}});h.paint();eq(h.created,1);assert(h.writes>writes)
		h.parent:Destroy();eq(h.released,1);eq(h.reclaim,nil)
	end)
	test("actual ground-scar renderer filters individual fog cells and culls hidden/offscreen tiles",function()
		local h=fixture();h.start();h.fogFrom=11;h.apply({{10*64+10,255},{10*64+11,255}});h.paint()
		local px=h.active("ImageLabel")[1].ImageContent.pixels
		assert(buffer.readu8(px,(10*32+10)*4+3)>0);eq(buffer.readu32(px,(10*32+11)*4),0)
		h.hidden=true;h.paint();eq(#h.active("Part"),0)
		h.hidden=false;h.view.cx=1000;h.paint();eq(#h.active("Part"),0)
		h.view.cx=16;h.paint();assert(#h.active("Part")>0);h.parent:Destroy()
	end)
	test("actual ground-scar renderer retries refusal/reclaim and rejects stale reset epochs",function()
		local h=fixture();h.start();h.deny=true;h.apply({{10*64+10,255}});h.paint();eq(h.attempts,1)
		h.deny=false;for _=1,10 do h.paint() end;eq(h.attempts,1)
		h.paint(5);eq(h.created,1);h.reclaim();eq(h.released,1);h.paint();eq(#h.active("Part"),0)
		h.paint(5);eq(h.created,2);h.apply({},2,true);eq(#h.active("Part"),0)
		h.apply({{10*64+10,255}},1,true);h.paint();eq(#h.active("Part"),0)
		h.renderer.destroy();local writes=h.writes;h.paint(6);eq(h.writes,writes);eq(h.created,h.released)
		for _,c in h.heartbeat.items do assert(c.dead) end;eq(h.reclaim,nil)
	end)
	test("actual ground-scar startup tolerates missing data and replaces old sessions",function()
		local h=fixture();h.missing=true;eq(h.start(),false);eq(h.reclaim,nil)
		h.missing=false;h.start();h.apply({{10*64+10,200}});h.paint();eq(h.created,1)
		h.start();eq(h.released,1);h.paint();eq(#h.active("Part"),0)
		local live=0;for _,c in h.heartbeat.items do if not c.dead then live+=1 end end;eq(live,1)
		h.parent:Destroy();eq(h.reclaim,nil)
	end)
	test("actual ground scars retry lazy roof exclusion and synchronize town restoration epochs",function()
		local h=fixture();h.pendingRoof=true;h.start();h.apply({{10*64+10,255}});h.paint();eq(h.townSource,nil);assert(h.sourceRequests>0)
		h.pendingRoof=false;h.paint();assert(h.townSource);assert(next(h.townBuckets));local updates=h.townUpdates
		h.paint();eq(h.townUpdates,updates)
		h.apply({},2,true);eq(next(h.townBuckets),nil);h.paint();eq(h.townSource,nil)
		h.parent:Destroy();eq(next(h.townBuckets),nil)
	end)
	test("actual native ground tiles update earth and ash tones in place and clear them on reset",function()
		local h=fixture();assert(h.start());local cell=10*64+10
		h.apply({{cell,255,1}});h.paint();eq(h.created,1)
		local image=h.active("ImageLabel")[1].ImageContent;local at=(10*32+10)*4;local earth=buffer.readu32(image.pixels,at)
		h.apply({{cell,255,2}});h.paint();eq(h.created,1);assert(buffer.readu32(image.pixels,at)~=earth)
		eq(h.townBuckets["0:0"].tones[cell],2)
		h.apply({},2,true);eq(#h.active("Part"),0);eq(next(h.townBuckets),nil);h.parent:Destroy();eq(h.created,h.released)
	end)
end
