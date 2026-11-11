--!strict
-- Live source house char/ruin layer, driven by HouseFireRenderer's visible pixel deltas.
-- APPROX: disjoint eight-cell image tiles, 24 near tiles, two allocations/update, shared detail
-- priority/retry policy. Existing town shade is preserved; collapsed-height shadows remain pending.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Map=require(Shared.Simulation.FireMap)
local Scorch=require(Shared.Presentation.FireScorch)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local Fog=require(script.Parent.FogOverlay)
local Town=require(script.Parent.TownRenderer)
local WorldLight=require(script.Parent.WorldLight)
local Renderer={}
local current:any=nil
local MAX_TILES=24
local HEIGHT=.12 -- Top face .125: above town detail's .105, below the road layer.
function Renderer.destroy() if current then current.folder:Destroy() end end
function Renderer.start(map:any,parent:Instance):boolean
	Renderer.destroy()
	local data=Shared:FindFirstChild("GameData")
	local source=data and data:FindFirstChild("FireMap_"..map.data.id)
	local rules=data and data:FindFirstChild("FireRules")
	if not source or not rules then return false end
	local ok,meta,settings=pcall(function() return require(source),require(rules) end)
	if not ok then warn("[FireScorch] Local data unavailable:",meta);return false end
	if type(meta)~="table" or type(settings)~="table" then return false end
	for _,key in {"width","height","tileSize"} do
		local value=meta[key]
		if type(value)~="number" or value<=0 or value==math.huge or value%1~=0 then return false end
	end
	local folder=Instance.new("Folder");folder.Name="HouseFireScorch";folder.Parent=parent
	local st:any={folder=folder,meta=meta,settings=settings,patches={},buckets={},views={},paintCache={},version=0,paintSeq=0,dead=false,loading=false,sampler=nil,retry=0,disabled=false}
	current=st
	local function unload(key:string)
		local v=st.views[key];if not v then return end
		v.part:Destroy();Memory.release(v.image);st.views[key]=nil
	end
	local function clear() for key in st.views do unload(key) end;table.clear(st.paintCache) end
	local unregister=Memory.register(10,function() clear();st.retry=os.clock()+5 end)
	local function load()
		if st.loading or st.sampler or st.disabled then return end;st.loading=true
		task.spawn(function()
			local loaded,value=pcall(function()
				return Map.new(meta,function(encoded:string,bytes:number):buffer
					assert(not st.dead,"cancelled fire map decode")
					return Inflate.raw(Codec.base64Decode(encoded),bytes)
				end,function(name:string):any
					assert(not st.dead,"cancelled fire map decode")
					local module=data:FindFirstChild(name);assert(module,"missing fire atlas page")
					local page=require(module);task.wait();return page
				end)
			end)
			st.loading=false
			if st.dead or current~=st then return end
			if loaded then st.sampler=value
			else st.disabled=true;warn("[FireScorch] Roof source unavailable:",value) end
		end)
	end
	st.load=load
	local function create(bucket:any):any?
		local side=meta.tileSize*Scorch.TILE;local image=Memory.create(Vector2.new(side,side),"detail")
		if not image then st.retry=os.clock()+5;return nil end
		local part=Instance.new("Part");part.Name="FireScorch_"..bucket.tx..":"..bucket.ty
		part.Anchored=true;part.Transparency=1;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
		part.Size=Vector3.new(Scorch.TILE*World.STUDS_PER_CELL,.01,Scorch.TILE*World.STUDS_PER_CELL)
		part.CFrame=CFrame.new(World.toWorld((bucket.tx+.5)*Scorch.TILE,(bucket.ty+.5)*Scorch.TILE,HEIGHT))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(side,side)
		gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0;gui.Parent=part
		local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.ResampleMode=Enum.ResamplerMode.Pixelated
		label.ImageContent=Content.fromObject(image);label.Parent=gui;part.Parent=folder
		return {part=part,image=image,stamp=nil}
	end
	local acc=0
	local connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.2 then return end;acc=0
		if st.dead or st.disabled then return end
		if next(st.buckets)==nil then clear();return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local view=WorldLight.view(camera);local wanted={};local order={}
		for key,b in st.buckets do
			local x,y=(b.tx+.5)*Scorch.TILE,(b.ty+.5)*Scorch.TILE
			if math.abs(x-view.cx)<=view.rx+Scorch.TILE and math.abs(y-view.cy)<=view.ry+Scorch.TILE then
				table.insert(order,{key=key,bucket=b,d=(x-view.cx)^2+(y-view.cy)^2})
			end
		end
		table.sort(order,function(a,b) return if a.d==b.d then a.key<b.key else a.d<b.d end)
		if #order==0 then clear();return end
		local anyVisible=false
		for i=1,math.min(MAX_TILES,#order) do
			for _,p in order[i].bucket.points do
				if not Fog.hidden((p.x+.5)/meta.tileSize,(p.y+.5)/meta.tileSize) then anyVisible=true;break end
			end
			if anyVisible then break end
		end
		if not anyVisible then clear();return end
		if not st.sampler then load();return end
		local made,paints=0,0;local began=os.clock();local considered={}
		local inputStamp=if Town.revision and Fog.revision then st.version..":"..Town.revision()..":"..Fog.revision() else nil
		local selected={};for i=1,math.min(MAX_TILES,#order) do table.insert(selected,order[i]) end
		-- Oldest invalid paint first: continuous fog/light changes must not starve farther tiles.
		table.sort(selected,function(a,b)
			local ac,bc=st.paintCache[a.key],st.paintCache[b.key]
			local av=if not ac then -1 elseif inputStamp and ac.inputStamp==inputStamp then math.huge else ac.sequence
			local bv=if not bc then -1 elseif inputStamp and bc.inputStamp==inputStamp then math.huge else bc.sequence
			return if av==bv then (if a.d==b.d then a.key<b.key else a.d<b.d) else av<bv
		end)
		for _,item in selected do
			considered[item.key]=true
			local cached=st.paintCache[item.key]
			if not cached or not inputStamp or cached.inputStamp~=inputStamp then
				-- Spread a burst of invalidated roof tiles across checks rather than blocking one frame.
				if paints>=2 or (paints>0 and os.clock()-began>=.003) then wanted[item.key]=st.views[item.key]~=nil;continue end
				local painted,pixels,count=pcall(function()
					local b=item.bucket
					local cover=if Town.forestCover then Town.forestCover(b.tx*Scorch.TILE,b.ty*Scorch.TILE,Scorch.TILE,Scorch.TILE) else nil
					return Scorch.paint(st.sampler,settings,b,function(x,y) return not Fog.hidden(x,y) end,Town.sample,cover)
				end)
				if not painted then st.disabled=true;clear();warn("[FireScorch] Char pixels unavailable:",pixels);return end
				st.paintSeq+=1
				cached={inputStamp=inputStamp,pixels=pixels,count=count,stamp=buffer.tostring(pixels),sequence=st.paintSeq};st.paintCache[item.key]=cached;paints+=1
			end
			local pixels,count=cached.pixels,cached.count
			if count==0 then unload(item.key);continue end
			wanted[item.key]=true
			local v=st.views[item.key]
			if not v then
				if os.clock()<st.retry or made>=2 then continue end
				v=create(item.bucket);if not v then break end;made+=1;st.views[item.key]=v
			end
			local stamp=cached.stamp
			if stamp~=v.stamp then
				local side=meta.tileSize*Scorch.TILE
				local wrote,err=pcall(function() return upload(v.image,Vector2.zero,Vector2.new(side,side),pixels,{priority=2,done=function(ok)
					if not ok and not st.dead and st.views[item.key]==v then st.disabled=true;clear() end
				end}) end)
				if wrote then if err then v.stamp=stamp end
				else unload(item.key);st.disabled=true;clear();warn("[FireScorch] Paint unavailable:",err);return end
			end
		end
		for key in st.views do if not wanted[key] then unload(key) end end
		for key in st.paintCache do if not considered[key] then st.paintCache[key]=nil end end
	end)
	folder.Destroying:Connect(function()
		st.dead=true;connection:Disconnect();unregister();clear();st.sampler=nil;table.clear(st.patches);table.clear(st.buckets)
		if current==st then current=nil end
	end)
	return true
end
-- Reuse the one lazy CPU roof map for ground-surface exclusion; no second atlas decode/image.
function Renderer.source():any
	local st=current;if not st or st.dead then return nil end
	if not st.sampler and not st.disabled then st.load() end
	return st.sampler
end
-- Changed world-pixel IDs and char stage. Stage zero restores the original underlying town art.
function Renderer.apply(rows:{any},replace:boolean?)
	local st=current;if not st or st.dead then return end
	local changed=replace==true and next(st.patches)~=nil
	if replace then table.clear(st.patches) end
	local total=st.meta.width*st.meta.height*st.meta.tileSize^2
	for _,row in rows do
		if type(row)~="table" then continue end
		local p,stage=row[1],row[2]
		if type(p)~="number" or p%1~=0 or p<0 or p>=total or type(stage)~="number" or stage%1~=0 or stage<0 or stage>3 then continue end
		local value=if stage==0 then nil else stage
		if st.patches[p]~=value then st.patches[p]=value;changed=true end
	end
	if not changed then return end
	st.version+=1
	st.buckets=Scorch.bucket(st.meta.width,st.meta.tileSize,st.patches)
end
return Renderer
