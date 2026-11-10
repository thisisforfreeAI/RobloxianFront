--!strict
-- Original gJt layouts and building-sheet fort art. Partial garrisons show source gate sandbags;
-- full ones raise walls/gates/towers/nests. Layouts are visual: existing secured combat rules apply.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local State=require(Shared.Presentation.FortificationState)
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Memory=require(script.Parent.ImageMemory)
local Daylight=require(script.Parent.DaylightController)
local FortRenderer={}
local data:any=nil
local palette:any=nil
local body:EditableImage?=nil
local paint:EditableImage?=nil
local folder:Folder?=nil
local views:{[number]:any}={}
local retry=0
local function release()
	Memory.release(body);Memory.release(paint);body,paint=nil,nil
end
local function sheets():boolean
	if body and paint then return true end
	if os.clock()<retry then return false end
	local size=Vector2.new(data.width,data.height)
	body=Memory.create(size);paint=Memory.create(size)
	if not body or not paint then release();retry=os.clock()+5;return false end
	local ok=pcall(function()
		body:WritePixelsBuffer(Vector2.zero,size,Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4))
		paint:WritePixelsBuffer(Vector2.zero,size,Inflate.raw(Codec.base64Decode(data.paint),data.width*data.height*4))
	end)
	if not ok then release();retry=os.clock()+5;return false end
	return true
end
function FortRenderer.start(mapId:string)
	local assets=script.Parent.Parent:FindFirstChild("DevAssets")
	local module=assets and assets:FindFirstChild("OrigForts_"..mapId)
	if not module then warn("[Forts] Generate local original fort art/layouts to enable city fortifications");return end
	data=require(module :: ModuleScript)
	local settings=Shared:FindFirstChild("GameData")
	local look=settings and settings:FindFirstChild("WorldLook")
	if look then palette=(require(look :: ModuleScript) :: any).palette end
	folder=Instance.new("Folder");folder.Name="SettlementForts";folder.Parent=workspace
	local acc=0
	local connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.1 then return end;acc=0
		local camera=workspace.CurrentCamera;if not camera then return end
		local pixels=World.STUDS_PER_CELL*camera.ViewportSize.Y/(2*math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)*math.tan(math.rad(camera.FieldOfView/2)))
		local night=Daylight.get().night
		local sun=Daylight.get().shadow
		for _,view in views do for i,piece in view.pieces do
			piece.gui.Enabled=pixels>=data.config.fromPx
			local age=os.clock()-view.born-(i-1)*data.config.staggerSec
			local alpha=math.clamp(age/data.config.riseSec,0,1)
			piece.base.ImageTransparency=1-alpha;piece.tint.ImageTransparency=1-alpha
			piece.shadow.ImageTransparency=1-data.config.shadowAlpha*(1-data.config.nightFade*night)*alpha
			piece.shadow.Position=UDim2.fromScale(sun[1]*7/96,sun[2]*7/96)
		end end
	end)
	folder.Destroying:Connect(function() connection:Disconnect();release();table.clear(views) end)
end
function FortRenderer.apply(rows:{any})
	if not folder or not data then return end
	local wanted={}
	for _,row in rows do
		local id,owner=row[1],row[2]
		local mode=State.mode(row)
		if mode=="none" then continue end
		wanted[id]=true
		local old=views[id]
		if old and old.owner==owner and old.mode==mode then continue end
		if old then for _,piece in old.pieces do piece.part:Destroy() end;views[id]=nil end
		if not sheets() then continue end
		local view={owner=owner,mode=mode,born=os.clock(),pieces={}}
		local rgb=palette and palette[owner] or {1,1,1}
		for _,point in data.layouts[id] or {} do
			local sprite=State.sprite(point.id,mode)
			local rect=sprite and data.rects[sprite]
			if not rect then continue end
			local part=Instance.new("Part")
			part.Name=sprite;part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;part.Transparency=1
			part.Size=Vector3.new(World.STUDS_PER_CELL,.01,World.STUDS_PER_CELL)
			part.CFrame=CFrame.new(World.toWorld(point.x,point.y,.26))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
			local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(48,48);gui.LightInfluence=0;gui.MaxDistance=0;gui.ClipsDescendants=false
			local function label(content:Content):ImageLabel
				local image=Instance.new("ImageLabel");image.BackgroundTransparency=1;image.Size=UDim2.fromScale(1,1);image.ImageContent=content;image.ImageRectOffset=Vector2.new(rect[1],rect[2]);image.ImageRectSize=Vector2.new(rect[3],rect[4]);image.ImageTransparency=1;image.Parent=gui;return image
			end
			local shadow=label(Content.fromObject(body));shadow.ImageColor3=Color3.new(0,0,0)
			-- APPROX source reach-band offset; full original projected sprite extrusion is pending.
			local sun=Daylight.get().shadow;shadow.Position=UDim2.fromScale(sun[1]*7/96,sun[2]*7/96)
			local base=label(Content.fromObject(body))
			local tint=label(Content.fromObject(paint));tint.ImageColor3=Color3.new(rgb[1],rgb[2],rgb[3])
			gui.Parent=part;part.Parent=folder
			table.insert(view.pieces,{part=part,gui=gui,base=base,tint=tint,shadow=shadow})
		end
		views[id]=view
	end
	for id,view in views do if not wanted[id] then for _,piece in view.pieces do piece.part:Destroy() end;views[id]=nil end end
	if next(views)==nil then release() end
end
return FortRenderer
