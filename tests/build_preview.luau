--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local Motion=require("../src/shared/Presentation/PlacementMotion");local Site=require("../src/shared/Presentation/SiteMotion")
	local function fixture():any
		local h:any={time=0,instances={},contents=0}
		local function instance(class)
			local o:any={ClassName=class,Destroying={callbacks={}}};function o.Destroying:Connect(fn) table.insert(self.callbacks,fn) end
			function o:Destroy() if self.dead then return end;self.dead=true;for _,fn in self.Destroying.callbacks do fn() end;for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local style={ok="#11aa44",bad="#aa2244",preview={from=2,fadePx=2,defenceShare=.75},hover={pulseSec=2,liftShare=.1,bobSec=4,bobPx=2,jitterHz=1,jitterPx=1.5,alpha=.8,refusedAlpha=.4,scanSec=2,wash=.1,gridAlpha=.2,edgeDash={4,4},marchPxPerSec=8,bracketShare=.2,tint=.3,shadowAlpha=.3,scanShare=.2,scanlinePx=4},refused={cellAlpha=.4,hatchPx=4,clashSec=2,clashAlpha={.1,.3}}}
		h.sheet={image={},meta={rects={["1"]={2,2,8,8,0,0},["2"]={12,2,8,8,0,0},["3"]={2,12,8,8,0,0}}}}
		h.resource={style=style,sheet=h.sheet,tint={.4,.6,.8},meta={frame=8,defence=true,base=1,paint=2,siteMask={tile=3,frame=8}}}
		local modules={motion=Motion,site=Site,art={preview=function(kind,army,side) h.requested={kind,army,side};return h.resource end}}
		local shared={Presentation={PlacementMotion="motion",SiteMotion="site"}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},script={Parent={StructureArt="art"}},require=function(key) return modules[key] end,
			Instance={new=instance},Vector2=rb.Vector2,UDim2=rb.UDim2,Color3=rb.Color3,NumberSequence=rb.NumberSequence,NumberSequenceKeypoint=rb.NumberSequenceKeypoint,Enum={NormalId={Top=1},SurfaceGuiSizingMode={FixedSize=1},ResamplerMode={Pixelated=1}},Content={fromObject=function(image) h.contents+=1;return image end},os={clock=function() return h.time end}},{__index=getfenv()})
		h.preview=luau.load(fs.readFile("src/client/Rendering/BuildPreview.luau"),{environment=env})();h.part=instance("Part")
		function h:draw(pixels,ok) return self.preview.update(self.part,"bunker","republic",2,{ok=ok~=false,blocked={},clashes={}},pixels or 120) end
		function h:gui() for _,o in self.instances do if o.Name=="PlacementPreview" and not o.dead then return o end end end
		return h
	end
	test("placement cursor shares body/paint/mask images and reuses one GUI across kinds and frames",function()
		local h=fixture();eq(h:draw(),true);eq(h.requested[2],"republic");local gui=h:gui();assert(gui)
		local count=#h.instances;for i=1,20 do h.time=i*.01;h:draw() end;assert(#h.instances<=count+4);eq(h:gui(),gui);eq(h.contents,1)
		for _,o in h.instances do
			assert(o.ClassName~="EditableImage")
			if o.ClassName=="ImageLabel" and o.ImageContent then eq(o.ImageContent,h.sheet.image) end
		end
		h.preview.update(h.part,"factory","coalition",1,{ok=true,blocked={},clashes={}},120);eq(h:gui(),gui);eq(h.requested[1],"factory")
	end)
	test("pending/refused art leaves the footprint while missing style keeps the legacy fallback",function()
		local h=fixture();h.resource.sheet=nil;eq(h:draw(),true)
		for _,o in h.instances do if o.ClassName=="ImageLabel" then eq(o.Visible,false) end end
		h.resource.sheet=h.sheet;eq(h:draw(),true);local visible=0;for _,o in h.instances do if o.ClassName=="ImageLabel" and o.Visible then visible+=1 end end;assert(visible>0)
		h.resource.style=nil;eq(h:draw(),false);eq(h:gui().Enabled,false)
	end)
	test("far zoom hides full art, stripes stay bounded and core replacement does not retain old pixels",function()
		local h=fixture();h:draw(3)
		for _,o in h.instances do if o.ClassName=="ImageLabel" then eq(o.Visible,false) end end
		h:draw(1000);local strips=0;for _,o in h.instances do if o.ClassName=="ImageLabel" and o.ImageRectSize and o.ImageRectSize.Y==1 then strips+=1 end end;assert(strips<=64,strips)
		local newImage={};h.sheet.image=newImage;h:draw(120,false)
		for _,o in h.instances do if o.ClassName=="ImageLabel" and o.Visible then eq(o.ImageContent,newImage) end end
	end)
	test("cursor cancellation, ghost replacement and teardown hide or destroy all native preview owners",function()
		local h=fixture();h:draw();local gui=h:gui();h.preview.hide();eq(gui.Enabled,false)
		h:draw();h.part={};h:draw();eq(gui.dead,true);h.preview.destroy();eq(h:gui(),nil)
		h:draw();h:gui():Destroy();h.preview.destroy();eq(h:gui(),nil)
	end)
end
