--!strict
-- Original ambient pedestrian poses and town evacuation. Shared atlas pair; no per-person images.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Traffic=require(Shared.Presentation.CivilianTraffic)
local People=require(Shared.Presentation.CivilianPeople)
local RefugeeColumn=require(Shared.Presentation.RefugeeColumn)
local Hash=require(Shared.Utilities.Hash)
local Memory=require(script.Parent.ImageMemory)
local Fog=require(script.Parent.FogOverlay)
local Daylight=require(script.Parent.DaylightController)
local Renderer={}
function Renderer.start(world:any,clock:any,assets:Instance,parent:Instance,mapId:string)
	if not world.data.config.people then return end
	local module=assets:FindFirstChild("OrigCivilianPeople_"..mapId)
	if not module then warn("[Civilians] Regenerate civilian assets to enable pedestrians");return end
	local ok,data=pcall(require,module :: ModuleScript)
	if not ok then warn("[Civilians] Local pedestrian data unavailable:",data);return end
	local state=People.new(world,Traffic,Hash.ambient)
	local folder=Instance.new("Folder");folder.Name="TownPedestrians";folder.Parent=parent
	local body:EditableImage?=nil
	local shade:EditableImage?=nil
	local display:any=data
	local cached={}
	local preferHalf=false
	local retry,idle=0,os.clock()
	local disabled=false
	local views:{[string]:any}={}
	local function clear()
		for _,v in views do v.part:Destroy() end;table.clear(views)
		Memory.release(body);Memory.release(shade);body,shade=nil,nil
	end
	local function allocate(variant:any):boolean
		local size=Vector2.new(variant.width,variant.height)
		body=Memory.create(size);if body then shade=Memory.create(size) end
		if not body or not shade then clear();return false end
		display=variant
		return true
	end
	local function images():boolean
		if body and shade then return true end
		if os.clock()<retry or disabled then return false end
		local loaded=false
		if not preferHalf then loaded=allocate(data) end
		if not loaded and data.half then preferHalf=true;loaded=allocate(data.half) end
		if not loaded then retry=os.clock()+5;return false end
		local success,err=pcall(function()
			local bytes=cached[display.frame]
			if not bytes then
				bytes={Inflate.raw(Codec.base64Decode(display.deflate),display.width*display.height*4),Inflate.raw(Codec.base64Decode(display.shade),display.width*display.height*4)}
				cached[display.frame]=bytes
			end
			local image=body :: EditableImage
			local shadow=shade :: EditableImage
			image:WritePixelsBuffer(Vector2.zero,Vector2.new(display.width,display.height),bytes[1])
			shadow:WritePixelsBuffer(Vector2.zero,Vector2.new(display.width,display.height),bytes[2])
		end)
		if not success then disabled=true;clear();warn("[Civilians] Pedestrian atlas unavailable:",err);return false end
		return true
	end
	local function create():any
		local part=Instance.new("Part");part.Name="CivilianPerson";part.Anchored=true;part.Transparency=1
		part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize=Vector2.new(display.frame,display.frame);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0;gui.ClipsDescendants=false
		local function label(image:EditableImage):ImageLabel
			local l=Instance.new("ImageLabel");l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1)
			l.ImageContent=Content.fromObject(image);l.ImageRectSize=Vector2.new(display.frame,display.frame);l.ResampleMode=Enum.ResamplerMode.Default;l.Parent=gui
			return l
		end
		local shadow=label(shade :: EditableImage);shadow.ImageColor3=Color3.new(0,0,0)
		local color=label(body :: EditableImage)
		gui.Parent=part;part.Parent=folder
		return {part=part,shadow=shadow,color=color}
	end
	local function visible(x:number,y:number):boolean return not Fog.hidden(x,y) end
	local connection=RunService.RenderStepped:Connect(function()
		if disabled or not clock.clock then return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local distance=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local ry=distance*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
		local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
		local pixels=camera.ViewportSize.Y/(2*ry)
		if pixels<world.data.config.from then if body then clear() end;state.lastTime=nil;return end
		local time=clock.clock+(if clock.running then math.min(.5,os.clock()-clock.at) else 0)
		local delta=if state.lastTime then time-state.lastTime else 0
		local reset=state.lastTime==nil or delta<0 or delta>world.data.config.jumpSec
		local light=Daylight.get()
		local cx,cy=camera.CFrame.Position.X/World.STUDS_PER_CELL,camera.CFrame.Position.Z/World.STUDS_PER_CELL
		local share=math.clamp((pixels-world.data.config.from)/(world.data.config.full-world.data.config.from),0,1)
		local poses={}
		if pixels>=world.data.config.peopleFrom then
			poses=People.step(state,time,if reset then 0 else delta,share,light.night,clock.fighters or {},time-(clock.fightersAt or time),{x0=cx-rx-2,x1=cx+rx+2,y0=cy-ry-2,y1=cy+ry+2},visible,reset)
		else state.lastTime=nil end
		if os.clock()-(clock.refugeesAt or -math.huge)<2 then
			for _,row in clock.refugees or {} do
				if row.group=="people" and (row.coarse or pixels>=world.data.config.peopleFrom) then
					local p=RefugeeColumn.predict(row,time,world.data.config.people.stride);p.alpha*=share;table.insert(poses,p)
				end
			end
		end
		local wanted={}
		local sun=light.shadow;local length=math.sqrt(sun[1]^2+sun[2]^2);local factor=if length>2 then 2/length else 1
		for _,p in poses do
			if math.abs(p.x-cx)>rx+1 or math.abs(p.y-cy)>ry+1 or not visible(p.x,p.y) then continue end
			if not images() then break end
			wanted[p.id]=true
			local v=views[p.id];if not v then v=create();views[p.id]=v end
			local size=display.frame/display.px*p.cells
			v.part.Size=Vector3.new(size*World.STUDS_PER_CELL,.01,size*World.STUDS_PER_CELL)
			v.part.CFrame=CFrame.new(World.toWorld(p.x,p.y,.30))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
			local facing=math.floor(p.heading/(math.pi*2)*display.facings+.5)%display.facings
			local rect=Vector2.new(facing*display.frame,display.rects[p.model])
			v.color.ImageRectOffset=rect;v.shadow.ImageRectOffset=rect
			v.color.ImageTransparency=1-p.alpha
			v.shadow.ImageTransparency=1-world.data.config.shadow.alpha*(light.shadowAlpha or 1)*p.alpha
			v.shadow.Position=UDim2.fromScale(sun[1]*factor*world.data.config.shadow.person/size,sun[2]*factor*world.data.config.shadow.person/size)
		end
		for id,v in views do if not wanted[id] then v.part:Destroy();views[id]=nil end end
		if next(views) then idle=os.clock() elseif body and os.clock()-idle>3 then clear() end -- APPROX idle storage policy.
	end)
	folder.Destroying:Connect(function() connection:Disconnect();clear() end)
end
return Renderer
