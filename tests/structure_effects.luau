--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	local Real=require("../src/shared/Presentation/StructurePixels")
	local function fixture():any
		local h:any={time=0,created=0,released=0,attempts=0,warnings=0,renders=0,decodes=0,pending={},instances={}}
		local function signal():any
			local event:any={listeners={}};function event:Connect(fn) table.insert(self.listeners,fn);return {Disconnect=function() end} end
			function event:fire() for _,fn in self.listeners do fn() end end;return event
		end
		local function instance(class:string):any
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() self.Destroying:fire() end;table.insert(h.instances,o);return o
		end
		local memory={create=function(_,kind) h.attempts+=1;if h.blocked then return nil end;h.created+=1;h.kind=kind;return {id=h.created} end,
			release=function(image) if image then h.released+=1;for i=#h.pending,1,-1 do if h.pending[i].image==image then table.remove(h.pending,i) end end end end,
			register=function(_,fn) h.reclaim=fn end,
			upload=function(image,position,size,pixels,options)
				if h.reject then return false end
				for i=#h.pending,1,-1 do if h.pending[i].image==image and h.pending[i].key==options.key then table.remove(h.pending,i) end end
				table.insert(h.pending,{image=image,key=options.key,done=options.done,position=position,size=size,pixels=pixels});return true
			end}
		local function raster(source:any,_,step:number,_,_,checkpoint:any):buffer
			h.renders+=1
			if h.slow then for _=1,8 do h.time+=.001;checkpoint() end end
			local out=buffer.create(source.frame*source.frame*4);buffer.writeu8(out,0,step);buffer.writeu8(out,3,255);return out
		end
		local pixels={prepare=Real.prepare,buildStep=Real.buildStep,damageStage=Real.damageStage,construction=raster,
			damage=function(source,cfg,step,id,cells,defence,helpers,checkpoint) return raster(source,cfg,step,id,nil,checkpoint) end}
		local shared={Presentation={StructurePixels="pixels"},Maps={MapCodec="codec"},Utilities={Inflate="inflate",Rng="rng"}}
		local modules:any={pixels=pixels,memory=memory,codec={base64Decode=function(raw) return raw end},inflate={raw=function(raw) h.decodes+=1;return raw end},rng={}}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},script={Parent={ImageMemory="memory"}},require=function(key) return assert(modules[key],key) end,
			Instance={new=instance},Vector2=roblox.Vector2,UDim2=roblox.UDim2,Enum={ResamplerMode={Pixelated=1}},Content={fromObject=function(image) return image end},
			os={clock=function() return h.time end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.effects=luau.load(fs.readFile("src/client/Rendering/StructureEffects.luau"),{environment=env})()
		h.effects.configure({construction={slabShare=.25,pourSteps=2,steps=4},damage={below={.8,.5,.2},back=.05}})
		function h:handle():any
			local gui=instance("SurfaceGui");local meta={frame=8,cells=3,effects={n=4,top=8,size=688,deflate=buffer.create(688)}}
			local handle=self.effects.attach(gui,meta,{{Visible=true},{Visible=true}});return handle
		end
		function h:request(handle,built,hp,id,stale,importance) return self.effects.request(handle,built,hp,100,stale or false,id or 1,{1,1,1},1,importance or 0) end
		function h:step() self.effects.step(self.time+.002) end
		function h:flush(ok) local queue=self.pending;self.pending={};for _,job in queue do job.done(ok~=false) end end
		return h
	end
	test("structure effects allocate lazily, share one optional image and bound slots and CPU source cache",function()
		local h=fixture();local healthy=h:handle();h:request(healthy,1,100);eq(h.created,0)
		local handles={};for i=1,12 do local handle=h:handle();h:request(handle,.4,100,i);handles[i]=handle end
		eq(h.created,1);eq(h.kind,"detail");eq(h.effects.stats().slots,9)
		for _=1,12 do h:step();h:flush() end;eq(h.effects.stats().sources,6)
		local focused=h:handle();h:request(focused,.4,100,99,false,1000);assert(focused.slot);eq(h.effects.stats().slots,9)
		local hidden=0;for _,handle in handles do if not handle.slot then hidden+=1 end end;eq(hidden,4)
	end)
	test("construction is published only after upload and advances without blanking the last valid stage",function()
		local h=fixture();local handle=h:handle();eq(h:request(handle,.1,100),nil);h:step();eq(#h.pending,1);eq(handle.label.Visible,false);eq(handle.static[1].Visible,true)
		h:request(handle,.7,100);h:flush();eq(handle.label.Visible,true);eq(handle.readyMode,"construction");eq(handle.static[1].Visible,false)
		h:step();eq(#h.pending,1);eq(handle.label.Visible,true);h:flush()
		eq(h:request(handle,.7,100),"construction");local renders=h.renders
		for _=1,10 do h:request(handle,.7,100);h:step();h:flush() end;eq(h.renders,renders)
	end)
	test("repair and fog invalidate queued damage; hidden or completed sites never resurrect pending pixels",function()
		local h=fixture();local handle=h:handle();h:request(handle,1,10);h:step();eq(#h.pending,1)
		h:request(handle,1,100);eq(handle.label.Visible,false);h:flush();eq(handle.label.Visible,false)
		h:request(handle,1,10);h:step();h:request(handle,1,10,1,true);h:flush();eq(handle.label.Visible,false)
		h:step();eq(h.effects.stats().images,0);eq(h.effects.stats().slots,0)
	end)
	test("damage hysteresis avoids redraws and a repair severity drop hides obsolete queued writes",function()
		local h=fixture();local handle=h:handle();h:request(handle,1,79);h:step();h:flush();eq(handle.stage,1)
		local rendered=h.renders;h:request(handle,1,82);h:step();eq(h.renders,rendered)
		h:request(handle,1,10);h:step();eq(#h.pending,1);h:request(handle,1,60);eq(handle.label.Visible,false)
		h:flush();eq(handle.label.Visible,false);h:step();h:flush();eq(handle.label.Visible,true);eq(handle.stage,1)
	end)
	test("native and queue refusals throttle work and a failed upload safely returns to static sprites",function()
		local h=fixture();local handle=h:handle();h.blocked=true
		for _=1,30 do h:request(handle,.5,100);h:step() end;eq(h.attempts,1)
		h.time=6;h.blocked=false;h.reject=true;h:request(handle,.5,100);h:step();eq(h.renders,1)
		for _=1,30 do h:request(handle,.5,100);h:step() end;eq(h.renders,1)
		h.time=6.3;h.reject=false;h:request(handle,.5,100);h:step();h:flush(false)
		eq(h.effects.stats().images,0);eq(handle.label.Visible,false);eq(h.released,1)
	end)
	test("cooperative pixel work cancels on destruction and optional image reclamation",function()
		local h=fixture();h.slow=true;local handle=h:handle();h:request(handle,.6,100);h:step()
		eq(#h.pending,0);assert(h.effects.stats().working);handle.gui:Destroy();h:step();eq(h.effects.stats().images,0);eq(h.warnings,0)
		h.slow=false;local another=h:handle();h:request(another,.6,100);h:step();h:flush();assert(another.label.Visible)
		h.reclaim();eq(another.label.Visible,false);eq(another.static[1].Visible,true);eq(h.effects.stats().images,0);h:flush();eq(another.label.Visible,false)
	end)
	test("offscreen expiry releases native canvas and reset clears cached source buffers",function()
		local h=fixture();local handle=h:handle();h:request(handle,.5,100);h:step();h:flush();assert(handle.label.Visible)
		h.time=1;h:step();eq(handle.label.Visible,false);eq(h.effects.stats().images,0)
		h.effects.reset();eq(h.effects.stats().sources,0)
	end)
end
