--!strict
return function(test:any,eq:any)
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	local function fixture()
		local h:any={instances={},contents=0}
		local function instance(class)
			local o:any={ClassName=class,Visible=true,Destroying={listeners={}}}
			function o.Destroying:Connect(fn) table.insert(self.listeners,fn) end
			function o:Destroy() if self.dead then return end;self.dead=true;for _,fn in self.Destroying.listeners do fn() end;for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local style={preview={from=7,fadePx=4},coverage={detail={from=7,fadePx=4},token={detailFrom=2,tokenFarPx=12,tokenMinPx=18,tokenMaxPx=40,tokenPerCell=2,tokenFloorPx=10,hqShare=1.4,facilityShare=1.1,farScale=2}},tokens={buildingAlpha=.4,stale={iconAlpha=.2,reach=.6,arm=.3,rimPx=4,linePx=2,rim='rgba(11, 16, 24, 0.75)',color='#eeeeee',alpha=.7},bar={max=70,widthShare=.75,buildGap=3,hpGap=6,height=3,back='rgba(8, 11, 15, 0.8)'},accent='#123456',secured='#abcdef',contested='#dd0000'}}
		h.sheet={image={},meta={rects={}}};for i=1,5 do h.sheet.meta.rects[tostring(i)]={i*10,2,8,8,0,0} end
		h.resource={style=style,sheet=h.sheet,tint={.2,.5,.8},meta={frame=8,back=1,fill=2,face=3,ghost=4}}
		local modules={motion=require('../src/shared/Presentation/StructureTokens'),art={token=function() return h.resource end}}
		h.playerGui=instance('PlayerGui');local env=setmetatable({game={GetService=function(_,name) return if name=='Players' then {LocalPlayer={FindFirstChild=function() return if h.noParent then nil else h.playerGui end}} else {WaitForChild=function() return {Presentation={StructureTokens='motion'}} end} end},require=function(k) return modules[k] end,script={Parent={StructureArt='art'}},Instance={new=instance},Color3=rb.Color3,Vector2=rb.Vector2,UDim2=rb.UDim2,UDim=rb.UDim,Content={fromObject=function(v) h.contents+=1;return v end}},{__index=getfenv()})
		h.tokens=luau.load(fs.readFile('src/client/Rendering/StructureTokens.luau'),{environment=env})();h.v={id=1,kind='factory',army='coalition',side=1,built=1,hp=100,maxHp=100}
		h.rules={}
		function h:draw(px,x,y,z) return self.tokens.draw(self.v,rb.Vector3.new(x or 100,y or 100,z or 1),px or 3,self.rules,1,800,600) end
		return h
	end
	test('placed token UI shares one atlas, reuses native labels and follows fractional camera positions',function()
		local h=fixture();h:draw();eq(h.tokens.count(),1);eq(h.contents,1);local count=#h.instances
		for i=1,20 do h.tokens.begin();h:draw(3,100+i*.1);h.tokens.finish({[1]=h.v}) end;eq(#h.instances,count);eq(h.contents,1)
		local images=0;for _,o in h.instances do assert(o.ClassName~='EditableImage');if o.ClassName=='ImageLabel' and o.ImageContent then eq(o.ImageContent,h.sheet.image);images+=1 end end;eq(images,4)
	end)
	test('fog clears live fill and status, out of view hides owners and removal destroys their UI',function()
		local h=fixture();h.v.hp=20;h.v.built=.5;h:draw(4);h.v.stale=true;h.tokens.begin();h:draw(30)
		local visible={};for _,o in h.instances do if o.ClassName=='ImageLabel' and o.Visible then table.insert(visible,o) end end;eq(#visible,1);eq(visible[1].ImageColor3,rb.Color3.fromRGB(238,238,238))
		for _,o in h.instances do if o.ClassName=='Frame' and o.Size and o.Size.Y.Offset==3 then eq(o.Visible,false) end end
		h.tokens.begin();h:draw(3,-1000);h.tokens.finish({[1]=h.v});for _,o in h.instances do if o.Name=='Building1' then eq(o.Visible,false) end end
		h.tokens.finish({});eq(h.tokens.count(),0);h:draw();h.tokens.reset();eq(h.tokens.count(),0)
	end)
	test('panning reuses the pose and atlas content while status changes and owner replacement invalidate it',function()
		local h=fixture();h.tokens.begin();local p=h:draw();h.tokens.finish({[1]=h.v})
		eq(h:draw(3,102),p);h.v.hp=20;local damaged=h:draw();assert(damaged~=p);eq(#damaged.bars,1)
		h.v.id=2;h:draw();eq(h.tokens.count(),2);eq(h.contents,1)
		h.tokens.begin();h.tokens.finish({[2]=h.v});eq(h.tokens.count(),1)
		for _,o in h.instances do if o.Name=='Building2' and not o.dead then eq(o.Visible,false) end end
		h.v.kind='rig';h.tokens.finish({[2]=h.v});eq(h.tokens.count(),0)
	end)
	test('warning icons share the atlas and clear on demolition ownership changes and fog',function()
		local h=fixture();h.resource.style.tokens.status={minPx=11,sizeShare=.4,offsetShare=.45,discShare=.6,ink='#ffff00',plate='rgba(11, 16, 24, 0.88)'};h.resource.status={damaged={frame=8,tile=5}}
		h.v.markerFlags=1;h.v.hp=20;h:draw(8);local root;for _,o in h.instances do if o.Name=='DamagedStatus' then root=o end end;assert(root);eq(root.Visible,true);eq(h.contents,1)
		local count=#h.instances;for _=1,20 do h:draw(8) end;eq(#h.instances,count)
		h.v.markerFlags=2;h:draw(8);eq(root.Visible,false);h.v.markerFlags=1;h.v.side=2;h:draw(8);eq(root.Visible,false)
		h.v.side=1;h.v.stale=true;h:draw(8);eq(root.Visible,false)
	end)
	test('pending and legacy art preserve the ordinary renderer and external GUI destruction can restart',function()
		local h=fixture();h.resource.sheet=nil;eq(h:draw(),nil);eq(h.tokens.count(),0);h.resource.sheet=h.sheet;h.resource.meta.ghost=nil;eq(h:draw(),nil)
		h.resource.meta.ghost=4;h.noParent=true;eq(h:draw(),nil);h.noParent=false;assert(h:draw())
		for _,o in h.instances do if o.Name=='StructureTokens' then o:Destroy() end end;eq(h.tokens.count(),0);assert(h:draw());eq(h.tokens.count(),1)
	end)
end
