--!strict
return function(test:any,eq:any)
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox');local P=require('../src/shared/Presentation/StructureShadows')
	local function fixture()
		local h:any={time=0,created=0,released=0,attempts=0,renders=0,decodes=0,pending={},instances={},warnings=0}
		local function instance(class)
			local o:any={ClassName=class,ResampleMode=0,Destroying={listeners={}}};function o.Destroying:Connect(fn) table.insert(self.listeners,fn) end
			function o:Destroy() self.dead=true;for _,fn in self.Destroying.listeners do fn() end end;table.insert(h.instances,o);return o
		end
		local memory={register=function(priority,fn) h.priority=priority;h.reclaim=fn end,create=function(_,kind) h.attempts+=1;if h.blocked then return nil end;h.kind=kind;h.created+=1;return {} end,
			release=function(image) if image then h.released+=1;table.clear(h.pending) end end,
			upload=function(_,_,_,_,options) if h.reject then return false end;table.insert(h.pending,options.done);return true end}
		local pixels={plan=P.plan,prepare=P.prepare,raster=function(...)
			h.renders+=1;local args={...};if h.slow then for _=1,8 do h.time+=.001;args[4]() end end;return P.raster(...)
		end}
		local modules={pixels=pixels,codec={base64Decode=function(v) return v end},inflate={raw=function(v) h.decodes+=1;return v end},memory=memory,fade={restore=function() end,apply=function() end}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return {Presentation={StructureShadows='pixels'},Maps={MapCodec='codec'},Utilities={Inflate='inflate'}} end} end},script={Parent={ImageMemory='memory',StructureFade='fade'}},require=function(k) return assert(modules[k],k) end,Instance={new=instance},Vector2=rb.Vector2,UDim2=rb.UDim2,Enum={ResamplerMode={Pixelated=1}},Content={fromObject=function(v) return v end},os={clock=function() return h.time end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.shadows=luau.load(fs.readFile('src/client/Rendering/StructureShadows.luau'),{environment=env})();h.cfg={angleSteps=8,reachStep=.25,shadowPerHeight=1,stepPx=1,ink='#05080b',alpha=.4,nightFade=.5}
		function h:source() local raw=buffer.create(128);buffer.writeu8(raw,27,255);buffer.writeu8(raw,64+28,255);return {frame=8,reach={2,4},bands={1,3},size=128,deflate=raw} end
		function h:handle(source,name)
			local gui=instance('SurfaceGui');local fallback={Visible=true};local v=self.shadows.attach(gui,{sourceName=name,shadow={source=source or self:source()}},fallback,self.cfg,{writing=true,mix=1});return v
		end
		function h:request(v,x,score,built,stale) self.shadows.sync(v,built or 1,stale or false,{shadow={x or 1,0},night=.5},score or 0,1) end
		function h:step() self.shadows.step(self.time+.002) end
		function h:flush(ok) local pending=self.pending;self.pending={};for _,done in pending do done(ok~=false) end end
		return h
	end
	test('many matching buildings share one optional shadow variant and publish only after native upload',function()
		local h=fixture();local source=h:source();local handles={}
		eq(h.shadows.attach({}, {shadow={source=source}}, {}, {shadowPerHeight=1}, {}),nil)
		for _=1,40 do local v=h:handle(source);h:request(v);table.insert(handles,v) end
		eq(h.created,1);eq(h.kind,'detail');eq(h.priority,5);eq(h.shadows.stats().variants,1)
		h:step();eq(#h.pending,1);eq(handles[1].label,nil);h:flush();eq(h.renders,1);eq(h.decodes,1)
		for _,v in handles do eq(v.fallback.Visible,false);eq(v.label.Visible,true);assert(math.abs(v.label.ImageTransparency-.7)<1e-9) end
		h.shadows.sync(handles[1],1,false,{shadow={1,0},night=0},0,1,4);eq(handles[1].label.ResampleMode,0)
		h.shadows.sync(handles[1],1,false,{shadow={1,0},night=0},0,1,16);eq(handles[1].label.ResampleMode,1)
		h.reclaim();eq(h.shadows.stats().images,0);for _,v in handles do eq(v.fallback.Visible,true);eq(v.label.Visible,false) end
	end)
	test('matching source art across faction tables shares a variant and hiding the last owner cancels work',function()
		local h=fixture();local a=h:handle(h:source(),'shared-source');local b=h:handle(h:source(),'shared-source')
		h:request(a);h:request(b);eq(a.entry,b.entry);h:step();h:flush();eq(h.decodes,1)
		h.shadows.hide(a);eq(a.label.Visible,false);eq(h.shadows.stats().variants,1)
		h.shadows.hide(b);eq(h.shadows.stats().variants,0);h:step();eq(h.shadows.stats().images,1)
		h:request(a);h:step();h:flush();eq(h.created,1);eq(a.label.Visible,true)
		h.shadows.hide(a);h.time=1;h:step();eq(h.shadows.stats().images,0)
	end)
	test('sun updates keep the last published shadow until a complete next pose replaces it',function()
		local h=fixture();local v=h:handle();h:request(v);h:step();h:flush();local old=v.entry.current.key
		h:request(v,2);h:step();eq(v.entry.current.key,old);eq(v.label.Visible,true)
		h:request(v,3);h:flush();assert(v.entry.current.key~=old);assert(v.entry.current.key~=v.entry.want.key)
		h:step();h:flush();eq(v.entry.current.key,v.entry.want.key);eq(h.decodes,1)
	end)
	test('shadow slots and decoded source cache stay bounded and focus replaces lower priority variants',function()
		local h=fixture();local handles={};for i=1,10 do local v=h:handle();handles[i]=v;h:request(v) end
		eq(h.shadows.stats().variants,9);eq(handles[10].entry,nil)
		for _=1,10 do h:step();h:flush() end;eq(h.shadows.stats().sources,6)
		h:request(handles[10],1,1000);assert(handles[10].entry);eq(h.shadows.stats().variants,9)
	end)
	test('native and upload refusal throttle retries, preserve the simple mask and release a failed image',function()
		local h=fixture();local v=h:handle();h.blocked=true
		for _=1,30 do h:request(v);h:step() end;eq(h.attempts,1);eq(v.fallback.Visible,true)
		h.time=6;h.blocked=false;h.reject=true;h:request(v);h:step();eq(h.renders,1)
		for _=1,30 do h:request(v);h:step() end;eq(h.renders,1)
		h.time=6.3;h.reject=false;h:request(v);h:step();h:flush(false);eq(h.shadows.stats().images,0);eq(v.fallback.Visible,true);eq(h.released,1)
	end)
	test('fog construction offscreen expiry and teardown prevent stale shadows from returning',function()
		local h=fixture();local v=h:handle();h:request(v);h:step();local late=h.pending[1]
		h:request(v,1,0,1,true);late(true);eq(v.label,nil);eq(v.fallback.Visible,false)
		h:request(v,1,0,.5);eq(v.fallback.Visible,false)
		h:request(v);h:step();h:flush();assert(v.label.Visible)
		h.time=1;h:step();eq(v.label.Visible,false);eq(h.shadows.stats().images,0)
		h:request(v);h:step();local done=h.pending[1];h.shadows.reset();if done then done(true) end;eq(h.shadows.stats().variants,0);eq(h.shadows.stats().sources,0)
	end)
	test('cooperative raster work cancels on destruction without warning or publishing partial pixels',function()
		local h=fixture();h.slow=true;local v=h:handle();h:request(v);h:step();assert(h.shadows.stats().working);eq(#h.pending,0)
		v.gui:Destroy();h:step();eq(h.shadows.stats().working,false);eq(h.warnings,0)
		h.time=1;h:step();eq(h.shadows.stats().images,0)
	end)
end
