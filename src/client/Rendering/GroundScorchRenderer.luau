--!strict
-- Source burn tint on the ground plane, beneath city/roof/tree art, roads, weather and fog.
-- APPROX: native alpha and 8-bit strength; opaque baked city paving can cover ground stains.
-- Detail tiles use cooperative image admission and retry. Missing local data skips this layer only.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local View=require(Shared.Presentation.GroundScorchView)
local World=require(Shared.Config.World)
local Memory=require(script.Parent.ImageMemory)
local Fog=require(script.Parent.FogOverlay)
local WorldLight=require(script.Parent.WorldLight)
local Town=require(script.Parent.TownRenderer)
local Roof=require(script.Parent.FireScorchRenderer)
local Renderer={}
local current:any=nil
function Renderer.destroy() if current then current.folder:Destroy() end end
function Renderer.start(map:any,parent:Instance):boolean
	Renderer.destroy()
	local data=Shared:FindFirstChild("GameData");local module=data and data:FindFirstChild("GroundScorchRules")
	if not module then return false end
	local ok,config=pcall(require,module);if not ok then warn("[GroundScorch] Settings unavailable:",config);return false end
	local folder=Instance.new("Folder");folder.Name="GroundBurnScars";folder.Parent=parent
	local st:any={folder=folder,view=View.new(map.width,map.height,config),tiles={},retry=0,dead=false,cursor=1,townSerial=-1};current=st
	st.config=config
	local function unload(key)
		local t=st.tiles[key];if t then t.part:Destroy();Memory.release(t.image);st.tiles[key]=nil end
	end
	local function clear() for key in st.tiles do unload(key) end end
	st.clear=clear
	local unregister=Memory.register(10,function() clear();st.retry=os.clock()+5 end)
	local elapsed=0
	local connection=RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.2 then return end;elapsed=0
		if st.townSerial~=st.view.serial then
			if next(st.view.buckets)==nil then Town.setGroundScorch({},config,nil);st.townSerial=st.view.serial
			else
				local source=Roof.source()
				if source then Town.setGroundScorch(st.view.buckets,config,source);st.townSerial=st.view.serial end
			end
		end
		local camera=workspace.CurrentCamera;if not camera then clear();return end
		local bounds=WorldLight.view(camera);local order={};local wanted={}
		for key,b in st.view.buckets do
			local x,y=b.x+b.cw/2,b.y+b.ch/2
			if math.abs(x-bounds.cx)<=bounds.rx+b.cw/2 and math.abs(y-bounds.cy)<=bounds.ry+b.ch/2 then table.insert(order,{key=key,b=b,d=(x-bounds.cx)^2+(y-bounds.cy)^2}) end
		end
		table.sort(order,function(a,b) return if a.d==b.d then a.key<b.key else a.d<b.d end)
		for _,item in order do wanted[item.key]=true end
		local added=0;local began=os.clock()
		-- APPROX: rotating eight-tile/3ms checks bound wide-view work without starving distant scars.
		for _=1,math.min(8,#order) do
			if st.cursor>#order then st.cursor=1 end
			local item=order[st.cursor];st.cursor+=1
			local b=item.b;local pixels,count=st.view.pixels(b,function(x,y) return not Fog.hidden(x,y) end)
			if count==0 then unload(item.key);continue end
			local t=st.tiles[item.key]
			if not t then
				if added>=2 or os.clock()<st.retry then continue end
				local size=Vector2.new(b.cw,b.ch);local image=Memory.create(size,"detail")
				if not image then st.retry=os.clock()+5;continue end
				local part=Instance.new("Part");part.Name="BurnStain_"..item.key
				part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;part.Transparency=1
				part.Size=Vector3.new(b.ch*World.STUDS_PER_CELL,.01,b.cw*World.STUDS_PER_CELL)
				part.CFrame=CFrame.new((b.x+b.cw/2)*World.STUDS_PER_CELL,World.GROUND_Y+.04,(b.y+b.ch/2)*World.STUDS_PER_CELL)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
				local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
				gui.CanvasSize=size;gui.LightInfluence=0;gui.MaxDistance=0
				local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
				label.ResampleMode=Enum.ResamplerMode.Pixelated;label.ImageContent=Content.fromObject(image)
				label.Parent=gui;gui.Parent=part;part.Parent=folder
				t={part=part,image=image,size=size};st.tiles[item.key]=t;added+=1
			end
			local stamp=buffer.tostring(pixels)
			if stamp~=t.stamp then t.image:WritePixelsBuffer(Vector2.zero,t.size,pixels);t.stamp=stamp end
			if os.clock()-began>=.003 then break end
		end
		for key in st.tiles do if not wanted[key] then unload(key) end end
	end)
	folder.Destroying:Connect(function()
		st.dead=true;connection:Disconnect();unregister();clear();Town.setGroundScorch({},config,nil)
		if current==st then current=nil end
	end)
	return true
end
function Renderer.apply(packet:any)
	if current and not current.dead then
		local before=current.view.epoch
		if current.view.apply(packet) and (before~=packet.epoch or packet.reset==true) then
			current.clear();Town.setGroundScorch({},current.config,nil)
		end
	end
end
return Renderer
