--!strict
-- Original ambient puff art in one shared, budgeted atlas; follows the civilian war clock.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Hash=require(Shared.Utilities.Hash)
local Smoke=require(Shared.Presentation.ChimneySmoke)
local Memory=require(script.Parent.ImageMemory)
local Fog=require(script.Parent.FogOverlay)
local Daylight=require(script.Parent.DaylightController)
local Renderer={}
function Renderer.start(world:any,clock:any,assets:Instance,parent:Instance,mapId:string)
	local module=assets:FindFirstChild("OrigChimneySmoke_"..mapId)
	if not module then warn("[Chimneys] Generate local chimney smoke assets to enable ambient smoke");return end
	local ok,data=pcall(require,module :: ModuleScript)
	if not ok then warn("[Chimneys] Local smoke data unavailable:",data);return end
	local folder=Instance.new("Folder");folder.Name="ChimneySmoke";folder.Parent=parent
	local image:EditableImage?=nil
	local pixels:buffer?=nil
	local views:{[string]:any}={}
	local retry,idle=0,os.clock()
	local disabled=false
	local function clear()
		for _,v in views do v.part:Destroy() end;table.clear(views)
		Memory.release(image);image=nil
	end
	local function atlas():boolean
		if image then return true end
		if os.clock()<retry or disabled then return false end
		image=Memory.create(Vector2.new(data.width,data.height))
		if not image then retry=os.clock()+5;return false end
		local loaded,err=pcall(function()
			pixels=pixels or Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4)
			local target=image :: EditableImage
			target:WritePixelsBuffer(Vector2.zero,Vector2.new(data.width,data.height),pixels :: buffer)
		end)
		if not loaded then disabled=true;clear();warn("[Chimneys] Puff atlas unavailable:",err);return false end
		return true
	end
	local function create():any
		local part=Instance.new("Part");part.Name="ChimneyPuff";part.Anchored=true;part.Transparency=1
		part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize=Vector2.new(data.frame,data.frame);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0
		local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
		label.ImageContent=Content.fromObject(image :: EditableImage);label.ImageRectSize=Vector2.new(data.frame,data.frame)
		label.ResampleMode=Enum.ResamplerMode.Default;label.Parent=gui;gui.Parent=part;part.Parent=folder
		return {part=part,label=label}
	end
	local function visible(x:number,y:number):boolean return not Fog.hidden(x,y) end
	local connection=RunService.RenderStepped:Connect(function()
		if disabled or not clock.clock then return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local distance=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local ry=distance*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
		local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
		local zoom=camera.ViewportSize.Y/(2*ry)
		local night=Daylight.get().night
		if zoom<data.config.from or night*1.6>=1 then if image or next(views) then clear() end;return end
		local cx,cy=camera.CFrame.Position.X/World.STUDS_PER_CELL,camera.CFrame.Position.Z/World.STUDS_PER_CELL
		local view={x0=cx-rx,x1=cx+rx,y0=cy-ry,y1=cy+ry}
		local share=math.clamp((zoom-data.config.from)/(data.config.full-data.config.from),0,1)
		local time=clock.clock+(if clock.running then math.min(.5,os.clock()-clock.at) else 0)
		local wanted={}
		for _,source in data.towns do
			local town=world.towns[source.id]
			if not town or math.abs(source.x-cx)>rx+source.radius+6 or math.abs(source.y-cy)>ry+source.radius+6 then continue end
			for _,p in Smoke.poses(town,source.chimneys,data.config,time,share,night,Hash.ambient,view,visible) do
				local size=data.frame/data.px*p.cells*World.STUDS_PER_CELL
				if size<.001 or math.abs(p.x-cx)>rx+p.cells or math.abs(p.y-cy)>ry+p.cells then continue end
				if not atlas() then break end
				wanted[p.id]=true
				local v=views[p.id];if not v then v=create();views[p.id]=v end
				v.part.Size=Vector3.new(size,.01,size)
				-- APPROX: flat puff layer above town art, below troops/fog; global grading replaces source tint sheets.
				v.part.CFrame=CFrame.new(World.toWorld(p.x,p.y,.32))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
				local facing=math.floor(p.heading/(math.pi*2)*data.facings+.5)%data.facings
				v.label.ImageRectOffset=Vector2.new(facing*data.frame,0)
				v.label.ImageTransparency=1-p.alpha
			end
		end
		for id,v in views do if not wanted[id] then v.part:Destroy();views[id]=nil end end
		-- APPROX storage policy, shared with other civilian detail: release after three idle seconds.
		if next(views) then idle=os.clock() elseif image and os.clock()-idle>3 then clear() end
	end)
	folder.Destroying:Connect(function() connection:Disconnect();clear() end)
end
return Renderer
