--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	local function fixture(bad:boolean?,legacy:boolean?,weapons:boolean?):any
		local h:any={created=0,released=0,attempts=0,time=0,fail=false,pending={},instances={},warnings=0,kinds={}}
		local function instance(class:string):any
			local object:any={ClassName=class};function object:Destroy() self.dead=true end;table.insert(h.instances,object);return object
		end
		local memory={register=function(_,fn) h.weaponReclaim=fn end,create=function(_,kind) table.insert(h.kinds,kind or "core");h.attempts+=1;if h.fail then return nil end;h.created+=1;return {} end,
			release=function(image) if image then h.released+=1 end end,
			upload=function(_,_,_,_,options) table.insert(h.pending,options.done);return true end}
		local meta={width=4,height=4,deflate="synthetic",rects={["1"]={0,0,1,1,0,0},["2"]={1,0,1,1,1,0},["3"]={2,0,1,1,0,0},["4"]={3,0,1,1,2,1}},
			looks={hq={frame=2,cells=5,base=1,paint=2,night=3,dish={frame=2,cells=2,x=0,y=0,speed=1,frames={{base=1},{base=2,paint=3}}}}}}
		if not legacy then (meta.looks.hq :: any).shadow={tile=4,frame=4} end
		local data={nightAlpha=.9,armies={coalition=meta,republic=meta}};h.data=data
		if weapons then (meta.looks.hq :: any).gun={part="synthetic"};(data :: any).weapons={width=4,height=4,deflate="synthetic",parts={},rects=meta.rects} end
		local shared:any={Config={World="world"},Maps={MapCodec="codec"},Utilities={Inflate="inflate"}}
		function shared:FindFirstChild() return nil end
		local assets={FindFirstChild=function() return "art" end}
		local modules:any={world={},codec={base64Decode=function() return buffer.create(0) end},inflate={raw=function(_,_,checkpoint)
			if h.slow then for _=1,8 do h.time+=.001;checkpoint() end end
			return buffer.create(64)
		end},memory=memory,art=data,gun={attach=function(_,m) return if m.gun then {} else nil end,sync=function(_,_,_,_,_,_,_,_,_,bank) h.gunBank=bank end,step=function() end,reset=function() end,forgetSheet=function() h.forgotWeapon=(h.forgotWeapon or 0)+1 end},factory={attach=function() return {} end,step=function() end,reset=function() end,sync=function(_,_,_,sample) h.factorySample=sample end},effects={configure=function() end,step=function() end,attach=function() return {} end,request=function(_,_,hp,maxHp,stale) h.effectHp=hp;h.effectMax=maxHp;return if stale then nil else h.effectMode end}}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",StructureEffects="effects",FactoryRenderer="factory",GunRenderer="gun",Parent={FindFirstChild=function() return assets end}}},require=function(key) if bad and key=="art" then error("bad local art") end;return assert(modules[key],key) end,
			Instance={new=instance},Vector2=roblox.Vector2,UDim2=roblox.UDim2,Color3=roblox.Color3,
			Enum={NormalId={Top=1},SurfaceGuiSizingMode={FixedSize=1},ResamplerMode={Pixelated=1}},Content={fromObject=function(image) return image end},
			os={clock=function() return h.time end},warn=function() h.warnings+=1 end},{__index=getfenv()})
		h.art=luau.load(fs.readFile("src/client/Rendering/StructureArt.luau"),{environment=env})()
		function h:flush(success) self.art.step();local pending=self.pending;self.pending={};for _,done in pending do done(success) end end
		return h
	end
	test("building instances share one atlas per faction and bind only after upload succeeds",function()
		local h=fixture();eq(h.art.attach({},"hq","coalition"),nil);eq(h.created,1)
		eq(h.art.attach({},"hq","coalition"),nil);eq(h.created,1);h:flush(true)
		for _=1,100 do assert(h.art.attach({},"hq","coalition")) end;eq(h.created,1)
		eq(h.art.attach({},"hq","republic"),nil);eq(h.created,2);h:flush(true)
		assert(h.art.attach({},"hq","republic"));h.art.reset();eq(h.released,2)
	end)
	test("a broken optional pixel module preserves the fallback without repeated warnings",function()
		local h=fixture(true)
		for _=1,100 do eq(h.art.attach({},"hq","coalition"),nil);h.art.step() end
		eq(h.created,0);eq(h.warnings,1)
	end)
	test("building shadows use the separate raised-object mask and its own crop scale",function()
		local h=fixture();h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		eq(art.body.ImageRectOffset,roblox.Vector2.new(0,0));eq(art.shadow.ImageRectOffset,roblox.Vector2.new(3,0))
		eq(art.shadow.Size,roblox.UDim2.fromScale(.25,.25))
		h.art.update(art,1,false,1,{night=0,shadow={1,-1},shadowAlpha=1},0)
		assert(math.abs(art.shadow.Position.X.Scale-.68)<1e-6);assert(math.abs(art.shadow.Position.Y.Scale-.07)<1e-6)
		eq(art.body.Position,roblox.UDim2.fromScale(0,0))
		h.art.update(art,1,false,1,{night=1,shadow={0,1},shadowAlpha=0},0);eq(art.shadow.ImageTransparency,1)
	end)
	test("old local atlases without caster masks never reuse dirt-bearing colour art as a shadow",function()
		local h=fixture(false,true);h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		assert(art.body);eq(art.shadow,nil);h.art.update(art,1,false,1,{night=0,shadow={1,0},shadowAlpha=1},0)
	end)
	test("budget and upload failures throttle retries and release failed images",function()
		local h=fixture();h.fail=true
		for _=1,100 do eq(h.art.attach({},"hq","coalition"),nil) end;eq(h.attempts,1)
		h.time=6;h.fail=false;eq(h.art.attach({},"hq","coalition"),nil);h:flush(false);eq(h.released,1)
		for _=1,100 do eq(h.art.attach({},"hq","coalition"),nil) end;eq(h.attempts,2)
		h.time=12;h.art.attach({},"hq","coalition");h:flush(true);assert(h.art.attach({},"hq","coalition"))
	end)
	test("fog memory freezes dishes, hides lights and never retains live faction tint",function()
		local h=fixture();h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=1,shadow={1,0},shadowAlpha=1}
		h.time=.6;h.art.update(art,1,false,1,light,0);eq(art.dish.index,2);eq(art.dish.paint.Visible,true)
		assert(art.night.ImageTransparency<1)
		h.art.update(art,1,true,1,light,0);eq(art.dish.index,1);eq(art.dish.paint.Visible,false);eq(art.night.ImageTransparency,1)
		eq(art.body.ImageColor3,art.paint.ImageColor3)
		h.art.update(art,1,false,.4,light,0);eq(art.dish.index,1);eq(art.night.ImageTransparency,1)
		h.art.reset();h:flush(true)
	end)
	test("reset cancels visibility of an old pending atlas and accepts a fresh upload",function()
		local h=fixture();h.art.attach({},"hq","coalition");h.art.reset();eq(h.released,1);h:flush(true)
		eq(h.art.attach({},"hq","coalition"),nil);eq(h.created,2);h:flush(true);assert(h.art.attach({},"hq","coalition"))
	end)
	test("atlas decoding yields across frame slices and reset abandons unfinished pixels",function()
		local h=fixture();h.slow=true;h.art.attach({},"hq","coalition")
		h.art.step();eq(#h.pending,0);assert(h.time<.004)
		h.art.reset();h.art.step();eq(#h.pending,0);eq(h.released,1)
		h.slow=false;h.art.attach({},"hq","coalition");h:flush(true);assert(h.art.attach({},"hq","coalition"))
	end)
	local function renderer():any
		local h:any={instances={},resets=0,mouse=roblox.Vector2.new(700,500)}
		local function signal():any
			local s:any={connections={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.connections,c);return c end
			function s:fire(dt) for _,c in table.clone(self.connections) do if not c.dead then c.fn(dt) end end end;return s
		end
		local function instance(class):any
			local o:any=setmetatable({ClassName=class,Destroying=signal()},{__index=function(self,key) if key=="Position" and rawget(self,"CFrame") then return self.CFrame.Position end;return nil end})
			function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		h.heartbeat=signal()
		h.camera={CFrame=roblox.CFrame.new(0,1000,0),ViewportSize=roblox.Vector2.new(800,600),FieldOfView=30}
		function h.camera:WorldToViewportPoint(pos) return roblox.Vector3.new(200+pos.X*2,150+pos.Z*2,1),true end
		local world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return roblox.Vector3.new(x*4,z or 0,y*4) end}
		local shared:any={Config={World="world"},Presentation={StructureLabels="labels"}}
		local rep={Shared=shared,WaitForChild=function() return shared end}
		local modules:any={world=world,labels=require("../src/shared/Presentation/StructureLabels"),daylight={get=function() return {} end},
			art={reset=function() h.resets+=1 end,step=function() end,attach=function() return {gui=instance("SurfaceGui")} end,update=function() end}}
		local services={ReplicatedStorage=rep,RunService={Heartbeat=h.heartbeat},UserInputService={GetMouseLocation=function() return h.mouse end},GuiService={GetGuiInset=function() return roblox.Vector2.zero end}}
		local env:any=setmetatable({game={GetService=function(_,name) return services[name] end},script={Parent={StructureArt="art",DaylightController="daylight"}},
			require=function(name) return assert(modules[name],name) end,workspace={CurrentCamera=h.camera},Instance={new=instance},
			Vector2=roblox.Vector2,Vector3=roblox.Vector3,CFrame=roblox.CFrame,UDim2=roblox.UDim2,Color3=roblox.Color3,
			Enum={Material={SmoothPlastic=1,Concrete=2,Neon=3},PartType={Cylinder=1},Font={GothamBold=1}}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/StructureRenderer.luau"),{environment=env})();h.renderer.start()
		return h
	end
	test("live structure focus exposes health while stale memories hide it and removal clears every part",function()
		local h=renderer();local r=h.renderer
		r.apply(1,{{1,"barracks",1,5,5,100,100,0,0,0,1,0,"republic"}});h.heartbeat:fire(.1)
		local v=r.each()[1];eq(v.army,"republic");eq(v.gui.Enabled,false);eq(v.block.Transparency,1)
		r.setFocus(1);h.heartbeat:fire(.1);eq(v.gui.Enabled,true);eq(v.text.Text,"Barracks 100/100");eq(v.barBack.Visible,true)
		r.apply(2,{{1,"barracks",1,5,5,1,1,0,0,0,1,1,"republic"}});h.heartbeat:fire(.1)
		eq(v.text.Text,"Barracks (last seen)");eq(v.barBack.Visible,false)
		r.apply(3,{});eq(next(r.each()),nil)
		for _,object in h.instances do if object.ClassName=="Part" then eq(object.dead,true) end end
	end)
	test("restarting presentation clears old HQs and connections without retaining destroyed HQ slabs",function()
		local h=renderer();local r=h.renderer
		r.apply(1,{{1,"hq",1,2,2,100,100,0,0,0,1,0}});r.apply(2,{})
		for _,object in h.instances do if object.ClassName=="Part" then eq(object.dead,true) end end
		r.start();r.apply(1,{{1,"hq",1,2,2,100,100,0,0,0,1,0}});assert(r.each()[1])
		local active=0;for _,connection in h.heartbeat.connections do if not connection.dead then active+=1 end end;eq(active,1)
	end)
	test("minefield snapshots stay in their dedicated overlay without creating structure or rig artifacts",function()
		local h=renderer();h.renderer.apply(1,{{1,"minefield",1,2,2,100,100,0,0,0,1,0,"republic"}})
		eq(next(h.renderer.each()),nil);for _,object in h.instances do assert(object.ClassName~="Part") end
	end)
	test("ready construction replaces the full sprite while damage keeps it and receives authoritative health",function()
		local h=fixture();h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=1,shadow={1,0},shadowAlpha=1}
		h.effectMode="construction";h.art.update(art,1,false,.5,light,5,40,100)
		eq(art.body.Visible,false);eq(art.paint.Visible,false);eq(art.shadow.ImageTransparency,1);eq(art.dish.base.ImageTransparency,1)
		eq(h.effectHp,40);eq(h.effectMax,100)
		h.effectMode="damage";h.art.update(art,1,false,1,light,5,20,100);eq(art.body.ImageTransparency,0)
		eq(art.night.ZIndex,3);eq(art.dish.base.ZIndex,4)
		h.art.update(art,1,true,1,light,5,1,1);assert(art.body.ImageTransparency<1)
	end)

	test("factory production samples reach animation without exposing them on remembered structures",function()
		local h=fixture();h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local sample={1,2};h.art.update(art,1,false,1,{night=0,shadow={0,1},shadowAlpha=1},1,100,100,0,sample)
		eq(h.factorySample,sample)
		local r=renderer();r.renderer.apply(1,{{1,"factory",1,5,5,100,100,0,0,0,1,0,"coalition",sample}})
		eq(r.renderer.each()[1].production,sample)
		r.renderer.apply(2,{{1,"factory",1,5,5,1,1,0,0,0,1,1,"coalition"}});eq(r.renderer.each()[1].production,nil)
	end)

	test("weapon frames use one optional shared atlas and reclaim without reallocation churn",function()
		local h=fixture(false,false,true);h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=0,shadow={0,1},shadowAlpha=1}
		h.art.update(art,1,false,1,light,1,100,100);eq(h.created,2);eq(h.kinds[2],"detail");eq(h.gunBank,nil)
		h:flush(true);h.art.update(art,1,false,1,light,1,100,100);assert(h.gunBank)
		for _=1,30 do h.art.update(art,1,false,1,light,1,100,100) end;eq(h.created,2)
		h.weaponReclaim();eq(h.forgotWeapon,1);eq(h.released,1)
		h.art.update(art,1,false,1,light,1,100,100);eq(h.created,2);eq(h.gunBank,nil)
	end)

	test("SAM pages load on demand by faction and all optional weapon pages reclaim with cooldown",function()
		local h=fixture(false,false,true);h.data.launchers={coalition=h.data.weapons,republic=h.data.weapons}
		h.data.armies.coalition.looks.hq.gun.bank="$sam:coalition"
		h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=0,shadow={0,1},shadowAlpha=1}
		h.art.update(art,1,false,1,light,1,100,100);eq(h.created,2);eq(h.kinds[2],"detail");h:flush(true)
		h.art.update(art,1,false,1,light,1,100,100);local coalition=h.gunBank;assert(coalition)
		art.meta.gun.bank="$sam:republic";h.art.update(art,1,false,1,light,1,100,100);eq(h.created,3);h:flush(true)
		h.art.update(art,1,false,1,light,1,100,100);assert(h.gunBank~=coalition)
		h.weaponReclaim();eq(h.forgotWeapon,2);eq(h.released,2)
		for _,bank in {"$sam:coalition","$sam:republic"} do art.meta.gun.bank=bank;h.art.update(art,1,false,1,light,1,100,100);eq(h.gunBank,nil) end
		eq(h.created,3)
	end)
	test("weapon snapshot tails preserve the factory slot and are discarded for fog memories",function()
		local h=renderer();local packet={1,1,.5,2,.02,.5}
		local row={4,"atgun",1,5,5,100,100,0,0,0,1,0,"coalition",false,packet}
		eq(#row,15);h.renderer.apply(1,{row});eq(h.renderer.each()[4].weapon,packet)
		h.renderer.apply(2,{{4,"atgun",1,5,5,1,1,0,0,0,1,1,"coalition"}})
		eq(h.renderer.each()[4].weapon,nil);eq(h.renderer.each()[4].production,nil)
	end)

end
