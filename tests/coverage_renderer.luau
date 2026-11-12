--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local M=require("../src/shared/Presentation/CoverageMotion")
	local function fixture():any
		local h:any={time=0,instances={}}
		local function instance(class) local o:any={ClassName=class,Visible=true,Destroying={callbacks={}}};function o.Destroying:Connect(fn) table.insert(self.callbacks,fn) end;function o:Destroy() if self.dead then return end;self.dead=true;for _,fn in self.Destroying.callbacks do fn() end;for _,child in h.instances do if child.Parent==self then child:Destroy() end end end;table.insert(h.instances,o);return o end
		h.parent=instance("PlayerGui")
		h.config={token={detailFrom=3,tokenFarPx=18,tokenMaxPx=64,tokenMinPx=28,tokenPerCell=3.5,tokenFloorPx=16,hqShare=1.4,facilityShare=1.2,farScale=2},detail={from=8,fadePx=2},marker={ringShare=1.1,glowShare=1.7,pulseSec=2,spinSec=8,dash={9,7},backingPx=6,linePx=2.5,tickPx=6},same={fillAlpha=.06,lineAlpha=.7,linePx=1.5,dash={6,5}},own="#11aa44",other="#aabbcc",backing={rgb={8,10,12},alpha=.8},radar={rgb={90,220,190},fillAlpha=.06,lineAlpha=.75,linePx=1.8,dash={8,6}}}
		local shared={Config={World="world"},Presentation={CoverageMotion="motion"}}
		local modules={world={toWorld=function(x,y,z) return rb.Vector3.new(x*4,z,y*4) end},motion=M,art={coverageStyle=function() return h.config end}}
		local camera={ViewportSize=rb.Vector2.new(800,600),WorldToViewportPoint=function(_,p) return rb.Vector3.new(p.X*5+h.offset,p.Z*5,1) end};h.offset=0
		local env=setmetatable({game={GetService=function(_,name) return if name=="Players" then {LocalPlayer={FindFirstChild=function() return h.parent end}} else {WaitForChild=function() return shared end} end},script={Parent={StructureArt="art"}},workspace={CurrentCamera=camera},require=function(key) return modules[key] end,
			Instance={new=instance},Color3=rb.Color3,UDim2=rb.UDim2,UDim=rb.UDim,Vector2=rb.Vector2,os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/CoverageRenderer.luau"),{environment=env})();h.rules={["structures.radar.kind"]="defence",["structures.radar.radar"]=40,["structures.factory.kind"]="facility",["production.spacing"]=0};h.sites={{id=1,kind="radar",side=1,x=10,y=10,hp=10},{id=2,kind="radar",side=2,x=15,y=10,hp=1,stale=true}}
		function h:draw(kind) self.renderer.update(kind or "radar",8,8,1,self.rules,self.sites,5) end
		function h:gui() for _,o in self.instances do if o.Name=="PlacementCoverage" and not o.dead then return o end end end
		return h
	end
	test("coverage guides use one screen vector GUI below the cursor, with no native image allocations",function()
		local h=fixture();h:draw();eq(h:gui().ClassName,"ScreenGui");eq(h:gui().DisplayOrder,-2);eq(h:gui().IgnoreGuiInset,true)
		local count=#h.instances;for i=1,20 do h.time=i*.02;h:draw() end;eq(#h.instances,count)
		for _,o in h.instances do assert(o.ClassName~="EditableImage" and o.ClassName~="ImageLabel" and o.ClassName~="SurfaceGui") end
	end)
	test("camera motion reprojects guide centres and vanished or different-kind sites shed their UI",function()
		local h=fixture();h:draw();local root;for _,o in h.instances do if o.Parent==h:gui() and o.Position==rb.UDim2.fromOffset(200,200) then root=o;break end end;assert(root)
		h.offset=30;h:draw();eq(root.Position,rb.UDim2.fromOffset(230,200))
		h.sites={};h:draw();eq(root.dead,true)
		h:draw("factory");for _,o in h.instances do if o.Parent==h:gui() then eq(o.dead,true) end end
	end)
	test("coverage cancellation, missing legacy styles and external GUI teardown leave no retained owners",function()
		local h=fixture();h:draw();local gui=h:gui();h.renderer.hide();eq(gui.Enabled,false)
		h:draw();eq(h:gui(),gui);h.config=nil;h:draw();eq(gui.Enabled,false)
		h.renderer.destroy();eq(gui.dead,true);eq(h:gui(),nil)
	end)
end
