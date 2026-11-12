--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local function fixture():any
		local h:any={time=0,instances={}}
		local function signal():any local s:any={fns={}};function s:Connect(fn) table.insert(self.fns,fn) end;function s:fire() for _,fn in self.fns do fn() end end;return s end
		local function instance(class):any
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,c in h.instances do if c.Parent==self then c:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local shared={Presentation={GunMotion="motion"}}
		local env:any=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},require=function() return require("../src/shared/Presentation/GunMotion") end,
			Instance={new=instance},Color3=rb.Color3,Vector2=rb.Vector2,UDim2=rb.UDim2,Content={fromObject=function(image) return image end},Enum={ResamplerMode={Pixelated=1}},os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/GunRenderer.luau"),{environment=env})()
		h.meta={frame=12,gun={kind="atgun",part="cannon",frame=8,cells=2,footprint=3,tall=2,shadowScale=1.5,shadowInk="#05080b",
			x=0,y=0,initialStep=.4,holdSec=2,turn=2,sweep=.3,sweepSec=6,kick=.2,kickSec=.5,fallback={base=1},slits={{0,.1}},cap={base=2}}}
		h.core={image={},meta={rects={["1"]={2,2,4,4,3,2},["2"]={20,2,6,6,1,1}}}}
		h.bank={image={},meta={parts={cannon={tall=2,frames={{base=1},{base=2}}}},rects={["1"]={2,2,4,4,0,0},["2"]={10,2,3,4,2,1}}}}
		function h:attach() return self.renderer.attach(instance("SurfaceGui"),self.meta,self.core) end
		function h:sync(view,built,stale,sample,bank)
			local c=if stale then rb.Color3.new(.4,.4,.4) else rb.Color3.new(1,1,1)
			self.renderer.sync(view,built,stale,sample,1,c,c,if stale then .22 else 0,{shadow={1,0},shadowAlpha=1},bank)
		end
		return h
	end
	test("gun atlases switch from an existing core pose without per-gun image creation or pivot drift",function()
		local h=fixture();local view=h:attach();h:sync(view,1,false,{1,1,math.pi,0,9,0},nil)
		eq(view.base.ImageContent,h.core.image);eq(view.root.Rotation,0)
		local count=#h.instances;view.state.heading=math.pi;h:sync(view,1,false,{1,1,math.pi,0,9,0},h.bank)
		eq(view.base.ImageContent,h.bank.image);eq(view.base.ImageRectOffset,rb.Vector2.new(10,2))
		eq(view.root.AnchorPoint,rb.Vector2.new(.5,.5));eq(view.base.Position,rb.UDim2.fromScale(.25,.125));eq(#h.instances,count)
		eq(view.cap.base.ZIndex,5);eq(view.shadowRoot.ZIndex,3)
		for _,object in h.instances do assert(object.ClassName~="EditableImage") end
	end)
	test("optional weapon-image reclamation atomically restores an already-loaded resting pose",function()
		local h=fixture();local view=h:attach();h:sync(view,1,false,{1,1,0,0,9,0},h.bank)
		h.renderer.forgetSheet(h.bank.image);eq(view.base.ImageContent,h.core.image);eq(view.base.Visible,true);eq(view.root.Rotation,0)
		eq(view.cap.base.ImageContent,h.core.image)
	end)
	test("construction hides guns and caps, fog freezes grey poses, and bunkers omit the exterior gun shadow",function()
		local h=fixture();local view=h:attach();h:sync(view,.5,false,{1,1,1,0,9,0},h.bank)
		eq(view.base.Visible,false);eq(view.cap.base.Visible,false);eq(view.shadow.Visible,false)
		h:sync(view,1,true,{1,1,1,5,0,1},h.bank);eq(view.root.Rotation,0);eq(view.state.sequence,nil);eq(view.base.ImageTransparency,.22)
		local where=view.root.Position;h.time=.1;h.renderer.step();eq(view.root.Position,where)
		h.meta.gun.kind="bunker";local bunker=h:attach();eq(bunker.shadow,nil)
	end)
	test("SAM pose changes rebind the same image and use each stage height without rotating vertical launchers",function()
		local h=fixture();local cfg=h.meta.gun;cfg.kind="sam";cfg.parts={"down","half","up"};cfg.sam={stay=.5,half=1.1,rise=2.4,up=1.3};cfg.kick=0
		h.bank.meta.parts={down={tall=1,frames={{base=1}}},half={tall=2,frames={{base=2}}},up={tall=4,frames={{base=1}}}}
		local view=h:attach();h:sync(view,1,false,{1,0,0,0,3600,0,10},h.bank)
		eq(view.boundPart,"up");eq(view.root.Rotation,0);local high=view.shadowRoot.Position.X.Scale
		view.state.shotAt=0;h.time=.7;h:sync(view,1,false,{1,0,0,0,.7,1,10},h.bank)
		eq(view.boundPart,"half");eq(view.base.ImageRectOffset,rb.Vector2.new(10,2));eq(view.root.Rotation,0)
		assert(view.shadowRoot.Position.X.Scale<high)
		h.time=2;h:sync(view,1,false,{1,0,0,0,2,1,10},h.bank);eq(view.boundPart,"down");eq(view.base.ImageRectOffset,rb.Vector2.new(2,2))
		h.renderer.forgetSheet(h.bank.image);eq(view.base.ImageContent,h.core.image);eq(view.base.Visible,true)
		h:sync(view,1,true,nil,nil);eq(view.state.sequence,nil);eq(view.root.Rotation,0)
	end)
	test("externally driven artillery poses share gun drawing and reclaim to the core resting pose",function()
		local h=fixture();local view=h:attach();h.meta.gun.kind="artillery"
		local pose={part="cannon",heading=math.pi+.1,x=.2,y=-.1,kick=.1};local color=rb.Color3.new(1,1,1)
		h.renderer.sync(view,1,false,nil,1,color,color,0,{shadow={1,0},shadowAlpha=1},h.bank,pose)
		eq(view.boundPart,"cannon");eq(view.index,2);assert(math.abs(view.root.Rotation-math.deg(.1))<1e-5)
		local location=view.root.Position;h.time=.1;h.renderer.step();eq(view.root.Position,location)
		h.renderer.forgetSheet(h.bank.image);eq(view.base.ImageContent,h.core.image);eq(view.root.Rotation,0);eq(view.base.Visible,true)
	end)
	test("gun views expire offscreen, forget transient shots, and destroy all animation records",function()
		local h=fixture();local view=h:attach();h:sync(view,1,false,{1,1,0,0,9,0},h.bank)
		h.time=1;h.renderer.step();eq(view.at,nil);eq(view.state.sequence,nil)
		view.all[1].Parent:Destroy();eq(h.renderer.count(),0)
		local other=h:attach();h:sync(other,1,false,{1,1,0,0,9,0},h.bank);h.renderer.reset();eq(h.renderer.count(),0)
		for _,object in other.all do eq(object.dead,true) end
	end)
end
