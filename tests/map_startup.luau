--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local function fixture()
		local h:any={instances={},images={},released=0,writes=0,warnings=0,creates=0}
		local function signal() local s:any={items={}};function s:Connect(fn) table.insert(self.items,fn) end;function s:fire() for _,fn in self.items do fn() end end;return s end
		local function instance(class)
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,c in h.instances do if c.Parent==self then c:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		h.baked={width=2,height=2,pieces={{x=0,width=1,deflate="a"},{x=1,width=1,deflate="b"}}}
		local memory={create=function()
			h.creates+=1;if h.noImages then return nil end
			local image={};table.insert(h.images,image);return image
		end,release=function(image) if not image.dead then image.dead=true;h.released+=1 end end,
		write=function() h.writes+=1;if h.failWrites or h.writes==h.failAt then return false,"synthetic write denied" end;return true end}
		local module={IsA=function() return true end};local assets={FindFirstChild=function() return if h.noBaked then nil else module end}
		local shared={Maps={MapCodec="codec"},Definitions={Terrain="terrain"},Config={World="world",Rules="rules"},Utilities={Inflate="inflate"},WaitForChild=function() return {RulesData="rulesData"} end}
		local rules={number=function() return 1 end,has=function() return true end}
		local modules={memory=memory,codec={base64Decode=function(x) return x end},terrain={names={"plains"},placeholderColor={plains={70,80,60}}},world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2},rules={new=function() return rules end},flags={},town={build=function() return false end},road={paint=function() end,build=function() return true end},inflate={raw=function(_,n) if h.badDecode then error("bad pixels") end;return buffer.create(n) end}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},script={Parent={ImageMemory="memory",TownRenderer="town",RoadRenderer="road",Parent={Dev={DevFlags="flags"},FindFirstChild=function() return assets end}}},require=function(k) return if k==module then h.baked else modules[k] end,
			Instance={new=instance},Vector2=rb.Vector2,Vector3=rb.Vector3,CFrame=rb.CFrame,Color3=rb.Color3,UDim2=rb.UDim2,Content={fromObject=function(image) if h.badContent then error("bad content binding") end;return image end},workspace={},
			Enum={Material={SmoothPlastic=1},SurfaceType={Smooth=1},NormalId={Top=1},SurfaceGuiSizingMode={FixedSize=1},ResamplerMode={Pixelated=1}},warn=function() h.warnings+=1 end,print=function() end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/MapRenderer.luau"),{environment=env})();h.map={width=2,height=2,terrain=buffer.create(4),urban=buffer.create(4),elev=buffer.create(4),data={id="test",roads={},rigs={},settlements={}}}
		function h:build() self.folder=self.renderer.build(self.map);return self.folder end
		function h:live() local n=0;for _,image in self.images do if not image.dead then n+=1 end end;return n end
		return h
	end
	test("baked ground publishes only complete strips and releases its images on teardown",function()
		local h=fixture();assert(h:build());eq(h.writes,2);eq(h:live(),2);h.folder:Destroy();eq(h:live(),0)
	end)
	test("a failed baked strip releases earlier strips before a successful simple ground fallback",function()
		local h=fixture();h.failAt=2;assert(h:build());eq(h.released,2);eq(h:live(),1);eq(h.writes,3);h.folder:Destroy();eq(h:live(),0)
	end)
	test("denied image writes fall through to queryable Part terrain without aborting client initialization",function()
		local h=fixture();h.failWrites=true;assert(h:build());eq(h:live(),0);assert(h.released>0)
		local ground,parts=0,0;for _,o in h.instances do if not o.dead and o.ClassName=="Part" then parts+=1;if o.Name=="Ground" then ground+=1;eq(o.CanQuery,true) end end end
		eq(ground,1);assert(parts>1);h.folder:Destroy()
	end)
	test("allocation refusal and broken original data retain a complete fallback map",function()
		local h=fixture();h.noImages=true;assert(h:build());eq(h:live(),0)
		local broken=fixture();broken.badDecode=true;assert(broken:build());eq(broken:live(),1);broken.folder:Destroy();eq(broken:live(),0)
	end)
	test("failed Content publication destroys partial UI and releases native image owners",function()
		local h=fixture();h.noBaked=true;h.badContent=true;assert(h:build());eq(h:live(),0)
		for _,o in h.instances do if o.ClassName=="SurfaceGui" or o.ClassName=="ImageLabel" then eq(o.dead,true) end end
	end)
end
