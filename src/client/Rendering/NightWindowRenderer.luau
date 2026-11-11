--!strict
-- Source roof footprints with owner-requested projected side facades and roof-clipped windows.
-- APPROX: flat town art gets a thin wall rim; original roof-surface emitters are intentionally removed.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Windows=require(Shared.Presentation.NightWindows)
local Pixels=require(Shared.Presentation.NightLightPixels)
local Noise=require(Shared.Presentation.GroundWetness)
local Memory=require(script.Parent.ImageMemory)
local Daylight=require(script.Parent.DaylightController)
local Renderer={}
local EMISSION_GAIN=2.4 -- APPROX owner request: more noticeable window/lamp glow.
function Renderer.start(data:any,profile:any,parent:Instance,born:number,damage:any?):any
	local state:any={ready=false,fade=0}
	if not data or not profile.city then return state end
	local folder=Instance.new("Folder");folder.Name="BuildingWindows";folder.Parent=parent
	local items=Windows.prepare(data.points,profile,Noise.hash21)
	local views:{[number]:any}={}
	local damageCache:any={}
	local image:EditableImage?=nil
	local imageDivisor=1
	local preferHalf=false
	local retry=0
	local function release()
		for _,v in views do v.part:Destroy() end;table.clear(views)
		Memory.release(image);image=nil;state.ready=false;state.fade=0
	end
	local function create(item:any):any
		local p=item.point;local scale=data.pixelsPerCell
		local part=Instance.new("Part");part.Name="Window_"..item.id
		part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;part.Transparency=1
		part.Size=Vector3.new(data.slot/scale*World.STUDS_PER_CELL,.01,data.slot/scale*World.STUDS_PER_CELL)
		part.CFrame=CFrame.new((p[1]+data.slot/2)/scale*World.STUDS_PER_CELL,World.GROUND_Y+.245,(p[2]+data.slot/2)/scale*World.STUDS_PER_CELL)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize=Vector2.new(data.slot,data.slot);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0
		local function layer(index:number):ImageLabel
			local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
			label.ImageContent=Content.fromObject(image :: EditableImage)
			label.ImageRectOffset=Vector2.new((index%data.perRow)*data.slot/imageDivisor,math.floor(index/data.perRow)*data.slot/imageDivisor)
			label.ImageRectSize=Vector2.new(data.slot/imageDivisor,data.slot/imageDivisor);label.ResampleMode=Enum.ResamplerMode.Default
			label.ImageTransparency=1;label.Parent=gui;return label
		end
		local face=if p[6]~=nil and p[6]>=0 then layer(p[6]) else nil
		-- Preserve dark masonry while increasing the emission layer in the same SurfaceGui.
		if face then face.ImageColor3=Color3.new(.035,.032,.028)*(1.4/EMISSION_GAIN) end
		local label=layer(p[5])
		gui.Parent=part;part.Parent=folder
		return {part=part,gui=gui,label=label,face=face,item=item}
	end
	local acc=0
	local connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.1 then return end;acc=0
		local night=Daylight.get().night
		if night<=0 then if image then release() end;return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local dist=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local ry=dist*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
		local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
		local px=camera.ViewportSize.Y/(2*ry)
		local fade=Windows.fade(px,profile.city)
		if fade<=0 then
			state.fade=0
			for _,v in views do v.gui.Enabled=false end
			return
		end
		if not image then
			if os.clock()<retry then return end
			local variant=if preferHalf and data.half then data.half else data
			image=Memory.create(Vector2.new(variant.width,variant.height))
			if not image and not preferHalf and data.half then
				preferHalf=true;variant=data.half
				image=Memory.create(Vector2.new(variant.width,variant.height))
			end
			if not image then retry=os.clock()+5;return end
			imageDivisor=if preferHalf then 2 else 1
			local ok,err=pcall(function() (image :: EditableImage):WritePixelsBuffer(Vector2.zero,Vector2.new(variant.width,variant.height),Inflate.raw(Codec.base64Decode(variant.deflate),variant.width*variant.height*4)) end)
			if not ok then release();retry=math.huge;warn("[NightWindows] Local atlas unavailable:",err);return end
			state.ready=true
		end
		local wanted={}
		local eligible:any=nil
		if damage and damage.any() then
			local version=damage.version()
			eligible=function(item)
				local cached=damageCache[item.id]
				if not cached or cached.version~=version then
					cached={version=version,blocked=Windows.damaged(item,data.pixelsPerCell,profile.fine,damage.blocked)};damageCache[item.id]=cached
				end
				return not cached.blocked
			end
		end
		local selected=Windows.visible(items,data.pixelsPerCell,camera.CFrame.Position.X/World.STUDS_PER_CELL,camera.CFrame.Position.Z/World.STUDS_PER_CELL,rx,ry,eligible)
		local began=os.clock()
		for _,entry in selected do
			local item=entry.item;wanted[item.id]=true
			if not views[item.id] and os.clock()-began<.003 then views[item.id]=create(item) end
		end
		for id,v in views do if not wanted[id] then v.part:Destroy();views[id]=nil end end
		local clock=os.clock()-born
		local correction=Pixels.compensate(Daylight.postEffect(),profile.color)
		for _,v in views do
			v.gui.Enabled=true;v.gui.Brightness=correction.brightness*EMISSION_GAIN
			v.label.ImageColor3=Color3.new(correction.color[1],correction.color[2],correction.color[3])
			v.label.ImageTransparency=if Windows.on(v.item,profile,clock,Noise.hash21) then 1-night*fade else 1
			if v.face then v.face.ImageTransparency=1-night*fade end -- Wall stays visible when its window switches off.
		end
		-- Keep coarse coverage until all selected fragments exist; no empty camera-pan interval.
		local complete=true
		for _,entry in selected do if not views[entry.item.id] then complete=false;break end end
		state.fade=if complete then fade else 0
	end)
	folder.Destroying:Connect(function() connection:Disconnect();release();table.clear(damageCache) end)
	return state
end
return Renderer
