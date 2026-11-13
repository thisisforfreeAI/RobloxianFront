--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local Motion=require("../src/shared/Presentation/SiteMotion")
	local function fixture():any
		local h:any={time=0,instances={}}
		local function signal() local s:any={callbacks={}};function s:Connect(fn) table.insert(self.callbacks,fn) end;function s:fire() for _,fn in self.callbacks do fn() end end;return s end
		local function instance(class)
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local modules={motion=Motion,pieces=require("../src/shared/Presentation/ConstructionPieces"),rng=require("../src/shared/Utilities/Rng")}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return {Presentation={SiteMotion="motion",ConstructionPieces="pieces"},Utilities={Rng="rng"}} end} end},require=function(k) return modules[k] end,
			Instance={new=instance},Vector2=rb.Vector2,UDim2=rb.UDim2,Color3=rb.Color3,NumberSequence=rb.NumberSequence,NumberSequenceKeypoint=rb.NumberSequenceKeypoint,ColorSequence=rb.ColorSequence,ColorSequenceKeypoint=rb.ColorSequenceKeypoint,
			Enum={ResamplerMode={Pixelated=1}},Content={fromObject=function(image) return image end},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/SiteRenderer.luau"),{environment=env})()
		h.cfg={yardShare=.25,accent="#112233",ok="#224455",hover={liftShare=.1,alpha=.8},site={blueprintAlpha=.2,gridAlpha=.1,pegPx=3,laserSec=4,laserAlpha=.5,laserInks={{10,20,30},{80,90,100},{10,20,30}}},survey={ink="#eeeedd",alpha=.4,dash={4,4},pegPx=2},drop={sec=.5,ringSec=1,ringGrow=1,flash=.6},done={sec=1,band=.2,glow=.8,ringGrow=1,inks={{40,50,60},{80,90,100},{40,50,60}}}}
		h.gui=instance("SurfaceGui");h.core={image={},meta={rects={["1"]={2,2,2,2,1,1}}}};h.meta={frame=8,siteMask={tile=1,frame=4}}
		h.view=h.renderer.attach(h.gui,h.meta,h.core,h.cfg,3)
		function h:sync(state,stale,side) self.renderer.sync(self.view,state,stale or false,side or 100,self.context) end
		function h:pieces()
			self.cfg.pieces={count=2,seed=33,shift=11,mul=123457,add=19,liftRate=1.25,fadeRate=2,scaffold={2,3}};self.cfg.site.dropShare=.6;self.cfg.site.pieceGlow=.5
			self.meta.base=2;self.meta.paint=3;self.core.meta.rects["2"]={6,2,8,8,0,0};self.core.meta.rects["3"]={16,2,8,8,0,0}
			self.context={id=11,base=rb.Color3.new(1,1,1),tint=rb.Color3.new(.2,.5,.8),score=1}
		end
		return h
	end
	test("site graphics allocate only while active, share core pixels and reuse their bounded native pool",function()
		local h=fixture();h:sync({built=1,placed=-math.huge,done=-math.huge});eq(#h.instances,1);eq(h.view.root,nil)
		h:sync({built=.1,placed=0,done=-math.huge});assert(h.view.root);eq(h.view.blueprint.label.ImageContent,h.core.image)
		eq(h.view.root.ZIndex,1);eq(h.view.overlay.ZIndex,8);eq(h.view.blueprint.label.Parent,h.view.root);eq(h.view.done.label.Parent,h.view.overlay)
		eq(h.view.drop.label.ImageContent,h.core.image);eq(h.view.done.label.ImageContent,h.core.image)
		local count=#h.instances;for i=1,10 do h.time=i*.01;h.renderer.step() end;eq(#h.instances,count)
		for _,o in h.instances do assert(o.ClassName~="EditableImage") end
		eq(h.renderer.attach(h.gui,h.meta,h.core,nil,3),nil)
	end)
	test("survey scan and silhouettes align to screen scale and disappear when raising begins",function()
		local h=fixture();h:sync({built=.1,placed=0,done=-math.huge},false,100)
		eq(h.view.laser.Size,rb.UDim2.fromScale(1,.02));eq(h.view.laser.Visible,true)
		assert(math.abs(h.view.drop.label.Position.Y.Scale-.15)<1e-6)
		h:sync({built=.4,placed=-math.huge,done=-math.huge},false,200)
		eq(h.view.laser.Visible,false);eq(h.view.blueprint.label.Visible,true);eq(h.view.drop.label.Visible,false)
		local first=h.view.pool[1];eq(first.Size,rb.UDim2.fromScale(1/200,1))
	end)
	test("completion effects expire, fog clears immediately and offscreen sites release UI objects",function()
		local h=fixture();h.time=1.1;h:sync({built=1,placed=-math.huge,done=1});eq(h.view.done.label.Visible,true)
		local root=h.view.root;h.time=2.1;h:sync({built=1,placed=-math.huge,done=1});eq(h.view.root,nil);eq(root.dead,true)
		h:sync({built=.1,placed=-math.huge,done=-math.huge});root=h.view.root;h:sync(nil,true);eq(h.view.root,nil);eq(root.dead,true)
		h:sync({built=.1,placed=-math.huge,done=-math.huge});root=h.view.root;h.time=3;h.renderer.step();eq(h.view.root,nil);eq(h.view.at,nil);eq(root.dead,true)
	end)
	test("site teardown drops all handles and leaves no frame callbacks or shared image ownership",function()
		local h=fixture();h:sync({built=.1,placed=-math.huge,done=-math.huge});eq(h.renderer.count(),1)
		h.gui:Destroy();eq(h.renderer.count(),0);eq(h.view.root,nil)
		h=fixture();h:sync({built=.1,placed=-math.huge,done=-math.huge});h.renderer.reset();eq(h.renderer.count(),0);eq(h.view.root,nil)
		h.time=.1;h.renderer.step();eq(h.view.root,nil)
	end)
	test("fallback pieces share core pixels, preserve team paint and reuse a stable native pool",function()
		local h=fixture();h:pieces();h:sync({built=.8,placed=-math.huge,done=-math.huge});assert(h.view.pieceRoot);eq(h.renderer.pieceCount(),1)
		local count=#h.instances;for _=1,20 do h.renderer.step() end;eq(#h.instances,count)
		local paint=0;for _,layers in h.view.pieceLayers do
			for kind,item in layers do eq(item.ImageContent,h.core.image);if kind=="paint" then eq(item.ImageColor3,h.context.tint);paint+=1 end end
		end;assert(paint>0);for _,o in h.instances do assert(o.ClassName~="EditableImage") end
	end)
	test("published height art atomically clears pieces and reclamation immediately restores the fallback",function()
		local h=fixture();h:pieces();h:sync({built=.8,placed=-math.huge,done=-math.huge});local root=h.view.pieceRoot
		h.renderer.covered(h.view,true);eq(root.dead,true);eq(h.renderer.pieceCount(),0);h.renderer.step();eq(h.view.pieceRoot,nil)
		h.renderer.covered(h.view,false);assert(h.view.pieceRoot);eq(h.renderer.pieceCount(),1)
		h:sync({built=.8,placed=-math.huge,done=-math.huge},true);eq(h.renderer.pieceCount(),0);eq(h.view.root,nil)
	end)
	test("fallback budgets admit eight sites, favor focus and release on fog offscreen completion and reset",function()
		local h=fixture();h:pieces();local handles={}
		for i=1,10 do local v=h.renderer.attach(h.gui,h.meta,h.core,h.cfg,3);handles[i]=v
			h.renderer.sync(v,{built=.8,placed=-math.huge,done=-math.huge},false,100,{id=i,base=h.context.base,tint=h.context.tint,score=0})
		end
		eq(h.renderer.pieceCount(),8);eq(handles[10].pieceRoot,nil)
		h.renderer.sync(handles[10],{built=.8,placed=-math.huge,done=-math.huge},false,100,{id=10,base=h.context.base,tint=h.context.tint,score=1000})
		assert(handles[10].pieceRoot);eq(h.renderer.pieceCount(),8)
		h.time=1;h.renderer.step();eq(h.renderer.pieceCount(),0)
		h:sync({built=.8,placed=-math.huge,done=-math.huge},false,2);eq(h.view.pieceRoot,nil)
		h:sync({built=.8,placed=-math.huge,done=-math.huge});assert(h.view.pieceRoot)
		h:sync({built=1,placed=-math.huge,done=-math.huge});eq(h.view.pieceRoot,nil);h.renderer.reset();eq(h.renderer.pieceCount(),0)
	end)
end
