--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local function make():any
		local h:any={now=0,writes={},warnings=0,images={}}
		local signal:any={items={}}
		function signal:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
		function signal:fire() h.now+=1/60;for _,c in table.clone(self.items) do if not c.dead then c.fn() end end end
		local asset={CreateEditableImage=function()
			local image:any={};function image:Destroy() self.dead=true end
			function image:WritePixelsBuffer(_pos,_size,pixels) assert(not self.dead);if self.fail then error("synthetic failed upload") end;table.insert(h.writes,{self,buffer.readu32(pixels,0)}) end
			table.insert(h.images,image);return image
		end}
		local shared={Presentation={ImageBudget="budget",ImageUploads="uploads"}}
		local modules={budget=require("../src/shared/Presentation/ImageBudget"),uploads=require("../src/shared/Presentation/ImageUploads")}
		local env=setmetatable({game={GetService=function(_,name)
			if name=="AssetService" then return asset elseif name=="RunService" then return {RenderStepped=signal} end
			return {WaitForChild=function() return shared end}
		end},require=function(key) return modules[key] end,Vector2={new=function(x,y) return {X=x,Y=y} end},os={clock=function() return h.now end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.memory=luau.load(fs.readFile("src/client/Rendering/ImageMemory.luau"),{environment=env})();h.signal=signal
		function h.image() return h.memory.create({X=1,Y=1}) end
		function h.upload(image,value,options) local p=buffer.create(4);buffer.writeu32(p,0,value);return h.memory.upload(image,{X=0,Y=0},{X=1,Y=1},p,options) end
		return h
	end
	test("actual image-memory adapter shares one render lane and disconnects when idle",function()
		local h=make();local a,b=h.image(),h.image();h.upload(a,10,{priority=1});h.upload(b,20,{priority=3});eq(#h.writes,0);eq(#h.signal.items,1)
		h.signal:fire();eq(#h.writes,1);eq(h.writes[1][1],a);h.signal:fire();eq(#h.writes,2);eq(h.memory.uploadStats().images,0);assert(h.signal.items[1].dead)
		h.upload(a,30);h.memory.release(a);h.signal:fire();eq(#h.writes,2);eq(h.upload(a,40),false)
	end)
	test("actual adapter cancels pooled reuse snapshots and reports write failure once per live image",function()
		local h=make();local a=h.image();h.upload(a,10);h.memory.cancelUploads(a);h.upload(a,20);h.signal:fire();eq(#h.writes,1);eq(h.writes[1][2],20)
		a.fail=true;local failures=0
		for i=1,2 do h.upload(a,30,{done=function(ok) if not ok then failures+=1 end end});h.signal:fire() end
		eq(h.warnings,1);eq(failures,2);eq(h.memory.uploadStats().bytes,0)
		h.memory.release(a);h.signal:fire();eq(h.memory.stats(),0)
	end)
	test("actual terrain recovery throttles releases, cancels old uploads and performs no native allocation",function()
		local h=make();local terrain=h.memory.create({X=1,Y=1},"terrain");local idle={}
		for _=1,3 do table.insert(idle,h.memory.create({X=1024,Y=1024},"detail")) end
		local calls=0;h.memory.register(20,function() calls+=1;h.memory.release(idle[calls]) end)
		h.upload(idle[1],10);eq(h.memory.uploadStats().images,1)
		eq(h.memory.recoverTerrain(8*1024*1024,4),8*1024*1024);eq(calls,1);eq(h.memory.uploadStats().images,0)
		eq(h.memory.recoverTerrain(12*1024*1024,4),8*1024*1024);eq(calls,1)
		h.now=1.1;eq(h.memory.recoverTerrain(12*1024*1024,4),12*1024*1024);eq(calls,2);eq(#h.images,4);eq(terrain.dead,nil)
		local stats=h.memory.pressureStats();eq(stats.recoveryPasses,2);eq(stats.recoveryReleased,8*1024*1024)
	end)
end
