--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local Motion=require("../src/shared/Presentation/PlacementMotion");local Site=require("../src/shared/Presentation/SiteMotion")
	local function fixture():any
		local h:any={time=0,instances={},contents=0}
		local function instance(class)
			local o:any={ClassName=class,Destroying={callbacks={}}};function o.Destroying:Connect(fn) local c={};function c:Disconnect() self.dead=true end;table.insert(self.callbacks,function() if not c.dead then fn() end end);return c end
			function o:Destroy() if self.dead then return end;self.dead=true;for _,fn in self.Destroying.callbacks do fn() end;for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local style={ok="#11aa44",bad="#aa2244",preview={from=2,fadePx=2,defenceShare=.75},hover={pulseSec=2,liftShare=.1,bobSec=4,bobPx=2,jitterHz=1,jitterPx=1.5,alpha=.8,refusedAlpha=.4,scanSec=2,wash=.1,gridAlpha=.2,edgeDash={4,4},marchPxPerSec=8,bracketShare=.2,tint=.3,shadowAlpha=.3,scanShare=.2,scanlinePx=4},refused={cellAlpha=.4,hatchPx=4,clashSec=2,clashAlpha={.1,.3}}}
		h.sheet={image={},meta={rects={["1"]={2,2,8,8,0,0},["2"]={12,2,8,8,0,0},["3"]={2,12,8,8,0,0}}}}
		h.resource={style=style,sheet=h.sheet,tint={.4,.6,.8},meta={frame=8,defence=true,base=1,paint=2,siteMask={tile=3,frame=8}}}
		local modules={motion=Motion,site=Site,coverage=require("../src/shared/Presentation/CoverageMotion"),art={preview=function(kind,army,side) h.requested={kind,army,side};return h.resource end}}
		local shared={Presentation={PlacementMotion="motion",SiteMotion="site",CoverageMotion="coverage"}};h.ui=instance("PlayerGui");h.center=rb.Vector3.new(350,250,1)
		local env=setmetatable({game={GetService=function(_,name) if name=="Players" then return {LocalPlayer=if h.noPlayer then nil else {FindFirstChild=function() return h.ui end}} end;return {WaitForChild=function() return shared end} end},workspace={CurrentCamera={WorldToViewportPoint=function() return h.center end}},script={Parent={StructureArt="art"}},require=function(key) return modules[key] end,
			Instance={new=instance},Vector2=rb.Vector2,UDim2=rb.UDim2,Color3=rb.Color3,NumberSequence=rb.NumberSequence,NumberSequenceKeypoint=rb.NumberSequenceKeypoint,Enum={NormalId={Top=1},SurfaceGuiSizingMode={FixedSize=1},ResamplerMode={Pixelated=1}},Content={fromObject=function(image) h.contents+=1;return image end},os={clock=function() return h.time end}},{__index=getfenv()})
		h.preview=luau.load(fs.readFile("src/client/Rendering/BuildPreview.luau"),{environment=env})();h.part=instance("Part")
		function h:draw(pixels,ok) return self.preview.update(self.part,"bunker","republic",2,{ok=ok~=false,blocked={},clashes={}},pixels or 120,self.rules) end
		function h:gui() for _,o in self.instances do if o.Name=="PlacementPreview" and not o.dead then return o end end end
		function h:badges()
			self.resource.meta.badge={frame=8,back=1,ink=2}
			self.resource.style.coverage={detail={from=2,fadePx=2},token={detailFrom=3,tokenFarPx=18,tokenMinPx=28,tokenMaxPx=64,tokenPerCell=3.6,tokenFloorPx=16,hqShare=1.45,facilityShare=1.2,farScale=2}}
			self.rules={["structures.bunker.kind"]="defence",["production.spacing"]=0}
		end
		function h:badge(name) for _,o in self.instances do if o.Name==name and not o.dead then return o end end end
		return h
	end
	test("placement cursor shares body/paint/mask images and reuses one GUI across kinds and frames",function()
		local h=fixture();eq(h:draw(),true);eq(h.requested[2],"republic");local gui=h:gui();assert(gui)
		eq(gui.ClassName,"ScreenGui");eq(gui.DisplayOrder,-1);eq(gui.IgnoreGuiInset,true)
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
	test("screen-space ghost reprojects without a world canvas and hides behind the camera",function()
		local h=fixture();h:draw(120);local root
		for _,item in h.instances do if item.Parent==h:gui() and item.ClassName=="Frame" then root=item;break end end
		assert(root);eq(root.Position,rb.UDim2.fromOffset(290,190));eq(root.Size,rb.UDim2.fromOffset(120,120))
		h.center=rb.Vector3.new(500,300,1);h:draw(180);eq(root.Position,rb.UDim2.fromOffset(410,210));eq(root.Size,rb.UDim2.fromOffset(180,180))
		h.center=rb.Vector3.new(500,300,-1);h:draw();eq(h:gui().Enabled,false)
	end)
	test("far building tokens share the faction page, use source sizing and stay on the ground pivot",function()
		local h=fixture();h:badges();h:draw(9)
		local back,tone=h:badge("BadgeBacking"),h:badge("BadgeInk");eq(back.Visible,true);eq(tone.Visible,true)
		eq(back.ImageContent,h.sheet.image);eq(tone.ImageContent,h.sheet.image);eq(back.Parent.ZIndex,5)
		eq(back.ResampleMode,nil);eq(tone.ResampleMode,nil) -- Keep native default smoothing for vector-derived icons.
		eq(back.Size,rb.UDim2.fromScale(29/9,29/9));eq(back.Position,rb.UDim2.fromScale((1-29/9)/2,(1-29/9)/2))
		eq(tone.ImageColor3,rb.Color3.fromRGB(17,170,68));eq(tone.ImageTransparency,0)
		eq(back.Parent.Size,rb.UDim2.fromScale(1,1));eq(h.contents,1)
	end)
	test("token refusal tint and zoom handoff reuse labels without retaining an old body or token",function()
		local h=fixture();h:badges();h:draw(9);local badge=h:badge("BadgeInk")
		for _=1,20 do h:draw(9,false);eq(badge.Visible,true);eq(badge.ImageColor3,rb.Color3.fromRGB(170,34,68));h:draw(12);eq(badge.Visible,false) end
		eq(h:badge("BadgeInk"),badge);eq(h.contents,1)
		local newImage={};h.sheet.image=newImage;h:draw(6);eq(badge.Visible,true);eq(badge.ImageContent,newImage);eq(h.contents,2)
		for _,o in h.instances do if o.ClassName=="ImageLabel" and o.Visible then assert(o.Name=="BadgeBacking" or o.Name=="BadgeInk") end end
	end)
	test("pending tokens and legacy metadata keep the advisory footprint without a new image",function()
		local h=fixture();h:badges();h.resource.sheet=nil;eq(h:draw(6),true);eq(h:badge("BadgeInk").Visible,false)
		h.resource.sheet=h.sheet;h.resource.meta.badge=nil;h:draw(6);eq(h:badge("BadgeInk").Visible,false)
		h:badges();h.resource.style.coverage=nil;h:draw(6);eq(h:badge("BadgeInk").Visible,false)
		for _,o in h.instances do assert(o.ClassName~="EditableImage") end
	end)
	test("HQ token share and current spacing rules survive missing or partial advisory rules",function()
		local h=fixture();h:badges()
		h.preview.update(h.part,"hq","coalition",1,{ok=true},6,nil)
		eq(h:badge("BadgeInk").Size,rb.UDim2.fromScale(52/6,52/6))
		h.preview.update(h.part,"hq","coalition",1,{ok=true},9,{["structures.hq.kind"]="hq",["production.spacing"]=0})
		eq(h:badge("BadgeInk").Size,rb.UDim2.fromScale(35/9,35/9))
		h.preview.update(h.part,"hq","coalition",1,{ok=true},9,{["production.spacing"]=4})
		eq(h:badge("BadgeInk").Size,rb.UDim2.fromScale(42/9,42/9))
	end)
	test("modern placement badges use their shared bank while body art is pending and switch back correctly",function()
		local h=fixture();h:badges();local bank={image={},meta=h.sheet.meta};h.resource.badgeSheet=bank;h.resource.sheet=nil
		h:draw(6);eq(h:badge("BadgeInk").Visible,true);eq(h:badge("BadgeInk").ImageContent,bank.image)
		h.resource.sheet=h.sheet;h:draw(12);eq(h:badge("BadgeInk").Visible,false)
		for _,o in h.instances do if o.ClassName=="ImageLabel" and o.Visible then eq(o.ImageContent,h.sheet.image) end end
		h:draw(6);eq(h:badge("BadgeInk").ImageContent,bank.image);eq(h.contents,2)
	end)
	test("cursor cancellation, ghost replacement and teardown hide or destroy all native preview owners",function()
		local h=fixture();h:draw();local gui=h:gui();h.preview.hide();eq(gui.Enabled,false)
		h:draw();h.part={};h:draw();eq(gui.dead,true);h.preview.destroy();eq(h:gui(),nil)
		h:draw();h:gui():Destroy();h.preview.destroy();eq(h:gui(),nil)
	end)
end
