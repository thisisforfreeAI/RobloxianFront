--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local roblox=require("@lune/roblox")
	local function fixture(bad:boolean?,legacy:boolean?,weapons:boolean?):any
		local h:any={created=0,released=0,attempts=0,time=0,fail=false,pending={},instances={},warnings=0,kinds={}}
		local function instance(class:string):any
			local object:any={ClassName=class,BackgroundTransparency=0,ImageTransparency=0,Destroying={listeners={}}}
			function object.Destroying:Connect(fn) table.insert(self.listeners,fn);return {Disconnect=function() end} end
			function object:IsA(kind) return self.ClassName==kind end
			function object:GetDescendants() local out={};for _,o in h.instances do local p=o.Parent;while p do if p==self then table.insert(out,o);break end;p=p.Parent end end;return out end
			function object:Destroy() self.dead=true;for _,fn in self.Destroying.listeners do fn() end end;table.insert(h.instances,object);return object
		end
		local memory={register=function(_,fn) h.weaponReclaim=fn end,create=function(_,kind) table.insert(h.kinds,kind or "core");h.attempts+=1;if h.fail then return nil end;h.created+=1;return {} end,
			release=function(image) if image then h.released+=1 end end,
			upload=function(_,_,_,_,options) table.insert(h.pending,options.done);return true end}
		local meta={width=4,height=4,deflate="synthetic",rects={["1"]={0,0,1,1,0,0},["2"]={1,0,1,1,1,0},["3"]={2,0,1,1,0,0},["4"]={3,0,1,1,2,1}},
			looks={hq={frame=2,cells=5,base=1,paint=2,night=3,dish={frame=2,cells=2,x=0,y=0,speed=1,frames={{base=1},{base=2,paint=3}}}}}}
		if not legacy then (meta.looks.hq :: any).shadow={tile=4,frame=4} end
		local data={nightAlpha=.9,armies={coalition=meta,republic=meta}};h.data=data
		if weapons then (meta.looks.hq :: any).gun={part="synthetic"};(data :: any).weapons={width=4,height=4,deflate="synthetic",parts={},rects=meta.rects} end
		local shared:any={Config={World="world"},Maps={MapCodec="codec"},Presentation={StructureTokens="tokens"},Utilities={Inflate="inflate"}}
		function shared:FindFirstChild() return nil end
		local assets={FindFirstChild=function() return "art" end}
		local modules:any={world={STUDS_PER_CELL=4},codec={base64Decode=function() return buffer.create(0) end},inflate={raw=function(_,_,checkpoint)
			if h.slow then for _=1,8 do h.time+=.001;checkpoint() end end
			return buffer.create(64)
		end},memory=memory,art=data,tokens=require("../src/shared/Presentation/StructureTokens"),shadows={hide=function() end,attach=function(_,meta,_,config,fade) h.shadowConfig=config;return if config and meta.shadow and meta.shadow.source then {fade=fade} else nil end,sync=function(handle,built,stale,light,score,mix) h.shadowSample={handle=handle,built=built,stale=stale,light=light,score=score,mix=mix} end,step=function() end,reset=function() end},fade=require("../src/client/Rendering/StructureFade"),site={attach=function(_,_,_,config) return if config then {} else nil end,covered=function(site,covered) h.coveredSite=site;h.siteCovered=covered end,sync=function(site,state,stale,side,context) if site then site.state=state;site.stale=stale end;h.siteContext=context;h.siteState=state;h.siteStale=stale;h.siteSide=side end,step=function() end,reset=function() end},artillery={attach=function(_,meta) return if meta.artillery then {} else nil end,sync=function(_,_,_,sample,_,_,_,_,_,bank) h.artillerySample=sample;h.artilleryBank=bank end,step=function() end,reset=function() end,forgetSheet=function() end},gun={attach=function(_,m) return if m.gun then {} else nil end,sync=function(_,_,_,_,_,_,_,_,_,bank) h.gunBank=bank end,step=function() end,reset=function() end,forgetSheet=function() h.forgotWeapon=(h.forgotWeapon or 0)+1 end},factory={attach=function() return {} end,step=function() end,reset=function() end,sync=function(_,_,_,sample) h.factorySample=sample end},effects={configure=function() end,step=function() end,attach=function(_,_,_,onDisplay) h.onDisplay=onDisplay;return {} end,request=function(_,_,hp,maxHp,stale) h.effectHp=hp;h.effectMax=maxHp;return if stale then nil else h.effectMode end}}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",StructureFade="fade",StructureShadows="shadows",StructureEffects="effects",FactoryRenderer="factory",GunRenderer="gun",ArtilleryRenderer="artillery",SiteRenderer="site",Parent={FindFirstChild=function() return assets end}}},require=function(key) if bad and key=="art" then error("bad local art") end;return assert(modules[key],key) end,
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
		local h:any={instances={},resets=0,time=0,mouse=roblox.Vector2.new(700,500)}
		local function signal():any
			local s:any={connections={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.connections,c);return c end
			function s:fire(dt) for _,c in table.clone(self.connections) do if not c.dead then c.fn(dt) end end end;return s
		end
		local function instance(class):any
			local o:any=setmetatable({ClassName=class,Destroying=signal()},{__index=function(self,key) if key=="Position" and rawget(self,"CFrame") then return self.CFrame.Position end;return nil end})
			function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		h.heartbeat=signal();h.render=signal()
		h.camera={CFrame=roblox.CFrame.new(0,1000,0),ViewportSize=roblox.Vector2.new(800,600),FieldOfView=30}
		function h.camera:WorldToViewportPoint(pos) return roblox.Vector3.new(200+pos.X*2,150+pos.Z*2,1),true end
		local world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return roblox.Vector3.new(x*4,z or 0,y*4) end}
		local shared:any={Config={World="world"},Presentation={StructureLabels="labels",SiteMotion="siteMotion"}}
		local rep={Shared=shared,WaitForChild=function() return shared end}
		local modules:any={world=world,labels=require("../src/shared/Presentation/StructureLabels"),siteMotion=require("../src/shared/Presentation/SiteMotion"),daylight={get=function() return {} end},
			tokens={begin=function() end,draw=function() return h.lod end,finish=function() end,reset=function() end},art={setMix=function(art,mix) if art then art.mix=mix end end,reset=function() h.resets+=1 end,step=function() end,scale=function(kind) return if kind=="bunker" then h.scale or 1 else 1 end,attach=function() h.attached=(h.attached or 0)+1;return {gui=instance("SurfaceGui")} end,update=function() end}}
		local services={ReplicatedStorage=rep,RunService={Heartbeat=h.heartbeat,RenderStepped=h.render},UserInputService={GetMouseLocation=function() return h.mouse end},GuiService={GetGuiInset=function() return roblox.Vector2.zero end}}
		local env:any=setmetatable({game={GetService=function(_,name) return services[name] end},script={Parent={StructureArt="art",StructureTokens="tokens",DaylightController="daylight"}},
			require=function(name) return assert(modules[name],name) end,workspace={CurrentCamera=h.camera},Instance={new=instance},
			Vector2=roblox.Vector2,Vector3=roblox.Vector3,CFrame=roblox.CFrame,UDim2=roblox.UDim2,Color3=roblox.Color3,
			Enum={Material={SmoothPlastic=1,Concrete=2,Neon=3},PartType={Cylinder=1},Font={GothamBold=1}},os={clock=function() return h.time end}},{__index=getfenv()})
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
	test("artillery uses a separate optional page shared across structures and preserves its sample",function()
		local h=fixture();h.data.artillery={width=4,height=4,deflate="synthetic",parts={},rects={}}
		h.data.armies.coalition.looks.hq.artillery={}
		local part={Position=roblox.Vector3.new(20,0,40),Size=roblox.Vector3.new(12,.02,12)}
		h.art.attach(part,"hq","coalition");h:flush(true);local art=h.art.attach(part,"hq","coalition")
		local packet={1,2,1,{1,10,10,2,{2}},{0,0,0,0,{}}};local light={night=0,shadow={0,1},shadowAlpha=1}
		h.art.update(art,1,false,1,light,1,100,100,0,nil,nil,packet);eq(h.created,2);eq(h.kinds[2],"detail");eq(h.artillerySample,packet)
		h:flush(true);h.art.update(art,1,false,1,light,1,100,100,0,nil,nil,packet);assert(h.artilleryBank)
		for _=1,20 do local another=h.art.attach(part,"hq","coalition");h.art.update(another,1,false,1,light,1,100,100,0,nil,nil,packet) end
		eq(h.created,2);h.weaponReclaim();eq(h.released,1)
		h.art.update(art,1,false,1,light,1,100,100,0,nil,nil,packet);eq(h.artilleryBank,nil);eq(h.created,2)
	end)
	test("artillery snapshots preserve dense factory and gun placeholders and clear in fog",function()
		local h=renderer();local packet={1,2,1,{1,10,10,2,{2}},{0,0,0,0,{}}}
		local row={4,"artybase",1,5,5,100,100,0,0,0,1,0,"coalition",false,false,packet}
		eq(#row,16);h.renderer.apply(1,{row});eq(h.renderer.each()[4].artillery,packet)
		h.renderer.apply(2,{{4,"artybase",1,5,5,1,1,0,0,0,1,1,"coalition"}})
		eq(h.renderer.each()[4].artillery,nil);eq(h.renderer.each()[4].weapon,nil)
	end)
	test("site accents preserve a blueprint fallback while construction pixels are pending or refused",function()
		local h=fixture();h.data.site={yardShare=.3};h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local state={built=.1,placed=0,done=-math.huge};local light={night=0,shadow={0,1},shadowAlpha=1}
		h.art.update(art,1,false,.1,light,1,100,100,0,nil,nil,nil,state,80)
		eq(art.body.Visible,false);eq(art.paint.Visible,false);eq(h.siteState,state);eq(h.siteSide,80);eq(h.created,1)
		h.art.update(art,1,false,.8,light,1,100,100,0,nil,nil,nil,state,80);eq(art.body.Visible,false)
		h.art.update(art,1,false,1,light,1,100,100,0,nil,nil,nil,state,80);eq(art.body.Visible,true)
	end)
	test("site fallback receives current identity tint and focus and follows native publication callbacks",function()
		local h=fixture();h.data.site={yardShare=.3};h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=0,shadow={0,1},shadowAlpha=1};local state={built=.8,placed=-math.huge,done=-math.huge}
		h.art.update(art,1,false,.8,light,47,100,100,1000,nil,nil,nil,state,120)
		eq(h.siteContext.id,47);eq(h.siteContext.score,1000);eq(h.siteContext.base,art.body.ImageColor3);eq(h.siteContext.tint,art.paint.ImageColor3);eq(h.siteSide,120)
		h.onDisplay("construction");eq(h.coveredSite,art.site);eq(h.siteCovered,true)
		art.body.Visible=true;art.paint.Visible=true;h.onDisplay(nil);eq(art.body.Visible,false);eq(art.paint.Visible,false);eq(h.siteCovered,false);h.onDisplay("damage");eq(h.siteCovered,false);eq(h.created,1)
	end)
	test("site times follow snapshots before artwork loads and never replay on reveal or restart",function()
		local h=renderer();local function row(id,built,stale) return {id,"barracks",1,5,5,100,100,0,0,0,built,stale or 0,"coalition"} end
		h.renderer.apply(1,{row(1,.01)});eq(h.renderer.each()[1].site.placed,-math.huge)
		h.time=10;h.renderer.apply(2,{row(1,.8),row(2,.01)});eq(h.renderer.each()[2].site.placed,10)
		h.time=20;h.renderer.apply(3,{row(1,1),row(2,.9)});eq(h.renderer.each()[1].site.done,20)
		h.time=30;h.renderer.apply(4,{row(1,1),row(2,1,1)});eq(h.renderer.each()[2].site.hidden,true)
		h.time=40;h.renderer.apply(5,{row(1,1),row(2,1)});eq(h.renderer.each()[2].site.done,-math.huge)
		h.renderer.start();h.renderer.apply(1,{row(1,.01)});eq(h.renderer.each()[1].site.placed,-math.huge)
	end)
	test("cursor shares the faction core page and original defence scale without requesting weapon pages",function()
		local h=fixture();h.data.site={preview={defenceShare=.75}};h.data.armies.coalition.looks.hq.defence=true
		local coverage={marker={}};h.data.site.coverage=coverage;eq(h.art.coverageStyle(),coverage);eq(h.created,0)
		eq(h.art.scale("hq"),.75);eq(h.art.scale("missing"),1)
		local resource=h.art.preview("hq","coalition",1);eq(resource.sheet,nil);assert(resource.meta);eq(h.created,1)
		h:flush(true);resource=h.art.preview("hq","coalition",1);assert(resource.sheet)
		local art=h.art.attach({},"hq","coalition");eq(resource.sheet,art.sheet)
		for _=1,100 do h.art.preview("hq","coalition",1) end;eq(h.created,1)
	end)
	test("placed defence quads use the same visual scale while production structures keep their footprint art",function()
		local h=renderer();h.scale=.75;h.renderer.apply(1,{{1,"bunker",1,5,5,100,100,0,0,0,1,0,"coalition"},{2,"factory",1,10,10,100,100,0,0,0,1,0,"coalition"}})
		eq(h.renderer.each()[1].block.Size.X,9);eq(h.renderer.each()[2].block.Size.X,12)
	end)
	test("far token owners defer detailed art and full sprites appear when near data is admitted",function()
		local h=renderer();h.renderer.configure({},1);h.renderer.apply(1,{{1,"barracks",1,5,5,100,100,0,0,0,1,0,"coalition"}})
		h.lod={mix=0,detailMix=0};h.render:fire(.01);h.heartbeat:fire(.1);eq(h.attached,nil);eq(h.renderer.each()[1].block.Transparency,1)
		h.lod={mix=0,detailMix=1};h.render:fire(.01);h.heartbeat:fire(.1);eq(h.attached,1);eq(h.renderer.each()[1].art.mix,0)
		h.lod={mix=.5,detailMix=.5};h.render:fire(.01);eq(h.renderer.each()[1].art.mix,.5)
		h.renderer.start();h.render:fire(.01);eq(next(h.renderer.each()),nil)
	end)
	test("both armies and the cursor share one required badge bank without loading body or weapon pages",function()
		local h=fixture();h.data.badges={width=4,height=4,deflate="synthetic",rects={},looks={hq={frame=8}}}
		local r=h.art.token("hq","coalition",1);eq(r.sheet,nil);eq(h.created,1);h:flush(true)
		r=h.art.token("hq","republic",2);assert(r.sheet);eq(h.created,1);eq(h.kinds[1],"core")
		local original=r.sheet;h.weaponReclaim();eq(h.released,0);eq(h.art.token("hq","coalition",1).sheet,original)
		h.art.preview("hq","coalition",1);eq(h.created,2);h:flush(true);eq(h.art.preview("hq","coalition",1).badgeSheet,original)
	end)
	test("whole building alpha survives animation ticks and asynchronous construction display callbacks",function()
		local h=fixture();h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition")
		local light={night=0,shadow={0,1},shadowAlpha=1};h.art.update(art,1,false,1,light,1,100,100)
		h.art.setMix(art,.5);eq(art.body.ImageTransparency,.5)
		for _=1,20 do h.art.step();h.art.update(art,1,false,1,light,1,100,100);eq(art.body.ImageTransparency,.5) end
		h.onDisplay("construction");eq(art.body.ImageTransparency,.5);h.onDisplay(nil);eq(art.body.ImageTransparency,.5)
		h.art.setMix(art,1);eq(art.body.ImageTransparency,0);h.art.setMix(art,0);eq(art.gui.Enabled,false)
	end)
	test("height projection receives daylight, fog, construction and focus through the shared fade owner",function()
		local h=fixture();h.data.shadowProjection={alpha=.4};h.data.armies.coalition.looks.hq.shadow.source={}
		h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition");assert(art.projectedShadow)
		local light={night=.5,shadow={2,-1},shadowAlpha=.6};h.art.setMix(art,.5);h.art.update(art,1,false,1,light,9,100,100,1000)
		eq(h.shadowConfig,h.data.shadowProjection);eq(h.shadowSample.handle,art.projectedShadow);eq(h.shadowSample.mix,.5);eq(h.shadowSample.score,1000);eq(h.shadowSample.light,light)
		h.art.update(art,1,true,.4,light,9,100,100);eq(h.shadowSample.stale,true);eq(h.shadowSample.built,.4)
	end)
	test("close ground symbols share the badge bank, reuse labels and disappear in fog and demolition",function()
		local h=fixture();h.data.site={ground={from=4,fadePx=2,share=.4,symbolShare=.5,gapCells=.2,alpha=.8,nightFade=.5,shadePx=1,shadeRgb={5,8,11},shadeAlpha=.5,inkRgb={255,255,255}}}
		h.data.badges={width=4,height=4,deflate="synthetic",rects=h.data.armies.coalition.rects,looks={hq={frame=2,ghost=1}}}
		h.art.attach({},"hq","coalition");h:flush(true);local art=h.art.attach({},"hq","coalition");local light={night=.5,shadow={1,0},shadowAlpha=.5}
		local function draw(stale,flags,built) h.art.update(art,1,stale or false,built or 1,light,1,100,100,0,nil,nil,nil,nil,30,flags or 0) end
		draw();eq(art.ground,nil);h:flush(true);draw();assert(art.ground.ink.Visible);eq(h.created,2);eq(art.ground.ink.ImageContent,h.art.token("hq","coalition",1).sheet.image)
		local count=#h.instances;for _=1,20 do draw() end;eq(#h.instances,count);eq(h.created,2)
		draw(true);eq(art.ground.ink.Visible,false);draw(false,2);eq(art.ground.shade.Visible,false);draw(false,0,.5);eq(art.ground.ink.Visible,true)
	end)
	test("marker snapshot tails remain dense and clear on fog or older server rows",function()
		local h=renderer();h.renderer.apply(1,{{1,"factory",1,5,5,20,100,0,0,0,1,0,"coalition",false,false,false,1}});eq(h.renderer.each()[1].markerFlags,1)
		h.renderer.apply(2,{{1,"factory",1,5,5,1,1,0,0,0,1,1,"coalition"}});eq(h.renderer.each()[1].markerFlags,0)
		h.renderer.apply(3,{{1,"factory",1,5,5,20,100,0,0,0,1,0,"coalition"}});eq(h.renderer.each()[1].markerFlags,0)
	end)
	test("weapon snapshot tails preserve the factory slot and are discarded for fog memories",function()
		local h=renderer();local packet={1,1,.5,2,.02,.5}
		local row={4,"atgun",1,5,5,100,100,0,0,0,1,0,"coalition",false,packet}
		eq(#row,15);h.renderer.apply(1,{row});eq(h.renderer.each()[4].weapon,packet)
		h.renderer.apply(2,{{4,"atgun",1,5,5,1,1,0,0,0,1,1,"coalition"}})
		eq(h.renderer.each()[4].weapon,nil);eq(h.renderer.each()[4].production,nil)
	end)

end
