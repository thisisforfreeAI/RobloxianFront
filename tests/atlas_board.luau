--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local function fixture():any
		local h:any={created=0,released=0,decodes=0,instances={},reclaimers={},warnings=0,logs=0}
		local function signal():any
			local s:any={items={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire(...) for _,c in table.clone(self.items) do if not c.dead then c.fn(...) end end end
			function s:alive() local n=0;for _,c in self.items do if not c.dead then n+=1 end end;return n end;return s
		end
		local function instance(class):any
			local o:any={ClassName=class,Destroying=signal()}
			function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local memory={create=function(_,kind)
			h.kind=kind;if h.blocked then return nil end;h.created+=1
			local image:any={};function image:WritePixelsBuffer(_,_,pixels) if h.failWrite then error("synthetic upload failure") end;self.pixels=pixels end
			function image:ReadPixelsBuffer() return self.pixels end;return image
		end,release=function(image) if image then assert(not image.dead);image.dead=true;h.released+=1 end end,
			register=function(priority,fn) eq(priority,5);local r={fn=fn};table.insert(h.reclaimers,r);return function() r.dead=true end end}
		local module={pages={{devPixels="pixels"}},directions=4,frameWidth=1,frameHeight=1}
		local data={width=4,height=1,rle="synthetic"}
		local shared={Config={World="world"},Maps={MapCodec="codec"},Assets={Facing="facing",PixelCodec="pixels",AtlasCheck="check",Atlases={FindFirstChild=function() return module end}}}
		local modules:any={memory=memory,world={STUDS_PER_CELL=4,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return rb.Vector3.new(x*4,z or 0,y*4) end},
			codec={base64Decode=function() return buffer.create(0) end},pixels={decode=function() h.decodes+=1;return buffer.create(16) end},
			facing={index=function() return 0 end,rect=function() return 1,0,0 end,residual=function() return 0 end},check={run=function() return {ok=true,worstDegrees=0,partialAlpha=0,failures={}} end}}
		h.input,h.frame=signal(),signal()
		local services={ReplicatedStorage={WaitForChild=function() return shared end},RunService={IsStudio=function() return true end,RenderStepped=h.frame},UserInputService={InputBegan=h.input}}
		local env:any=setmetatable({game={GetService=function(_,name) return assert(services[name],name) end},
			script={Parent={Parent={Rendering={ImageMemory="memory"},DevAssets={FindFirstChild=function() return data end}}}},
			require=function(key) return if type(key)=="table" then key else assert(modules[key],key) end,
			Instance={new=instance},workspace={},Vector2=rb.Vector2,Vector3=rb.Vector3,CFrame=rb.CFrame,Color3=rb.Color3,UDim2=rb.UDim2,Content={fromObject=function(image) return image end},
			Enum={Material={Neon=1},PartType={Cylinder=1},NormalId={Top=1},SurfaceGuiSizingMode={FixedSize=1},ResamplerMode={Pixelated=1},KeyCode={R="R",G="G"}},
			warn=function() h.warnings+=1 end,print=function() h.logs+=1 end},{__index=getfenv()})
		h.board=luau.load(fs.readFile("src/client/Dev/AtlasTestBoard.luau"),{environment=env})()
		function h:start() return self.board.start(rb.Vector2.new(30,30),"synthetic",true) end
		return h
	end
	test("debug atlas admission uses optional shared storage before any decode or GUI work",function()
		local h=fixture();h.blocked=true;eq(h:start(),nil);eq(h.kind,"detail");eq(h.created,0);eq(h.decodes,0);eq(#h.instances,0)
	end)
	test("a failed atlas readback/upload releases storage without leaving debug callbacks alive",function()
		local h=fixture();h.failWrite=true;eq(h:start(),nil);eq(h.created,1);eq(h.released,1);eq(h.warnings,1)
		eq(h.input:alive(),0);eq(h.frame:alive(),0)
	end)
	test("restarting or destroying an atlas board disconnects old gameplay-key hooks and images",function()
		local h=fixture();local old=h:start();local current=h:start();eq(old.folder.dead,true)
		eq(h.created,2);eq(h.released,1);eq(h.input:alive(),1);eq(h.frame:alive(),1)
		local before=h.logs;h.input:fire({KeyCode="G"},false);eq(h.logs,before+1)
		current.destroy();current.destroy();eq(h.released,2);eq(h.input:alive(),0);eq(h.frame:alive(),0)
	end)
	test("debug boards yield their whole image and callbacks first when the shared budget reclaims them",function()
		local h=fixture();h:start();h.reclaimers[1].fn();eq(h.released,1);eq(h.input:alive(),0);eq(h.frame:alive(),0)
		eq(h.reclaimers[1].dead,true);h.board.destroyAll();eq(h.released,1)
	end)
end
