--!strict
-- Original ambient cars share two small atlases. Routes and actors are presentation only;
-- current cell visibility and fog-filtered city health constrain every displayed car.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Traffic=require(Shared.Presentation.CivilianTraffic)
local Driving=require(Shared.Presentation.CivilianDriving)
local Roads=require(Shared.Simulation.Roads)
local Memory=require(script.Parent.ImageMemory)
local Fog=require(script.Parent.FogOverlay)
local Daylight=require(script.Parent.DaylightController)
local PeopleRenderer=require(script.Parent.CivilianPeopleRenderer)
local Renderer={}
local current:any=nil
function Renderer.destroy() if current then current.folder:Destroy() end end
function Renderer.start(map:any,parent:Instance)
	Renderer.destroy()
	local assets=script.Parent.Parent:FindFirstChild("DevAssets")
	local module=assets and assets:FindFirstChild("OrigCivilianTraffic_"..map.data.id)
	if not module then warn("[Civilians] Generate local ambient traffic assets to enable civilian cars");return end
	local ok,data=pcall(require,module :: ModuleScript)
	if not ok then warn("[Civilians] Local traffic data unavailable:",data);return end
	local folder=Instance.new("Folder");folder.Name="CivilianTraffic";folder.Parent=parent
	local state=Traffic.new(data)
	local settings=Shared:FindFirstChild("GameData")
	local roadLook=settings and settings:FindFirstChild("RoadLook")
	local flow=if roadLook then Driving.new(state,map.data.roads,require(roadLook :: ModuleScript),Traffic) else nil
	if not flow then warn("[Civilians] Generate RoadLook to enable road-width lanes and traffic queues") end
	local session:any={folder=folder,state=state,movers={},cuts={},clock=nil,at=os.clock()}
	current=session
	PeopleRenderer.start(state,session,assets :: Instance,folder,map.data.id)
	local road=buffer.create(map.width*map.height)
	for _,r in map.data.roads do if r.rank>=1 then
		for i=3,#r.pts-1,2 do for _,c in Roads.line(map.width,map.height,r.pts[i-2],r.pts[i-1],r.pts[i],r.pts[i+1]) do buffer.writeu8(road,c,1) end end
	end end
	local function onRoad(x:number,y:number):boolean
		local ix,iy=math.floor(x),math.floor(y)
		if ix<0 or iy<0 or ix>=map.width or iy>=map.height or buffer.readu8(road,iy*map.width+ix)==0 then return false end
		-- APPROX: the visible cut's displayed radius replaces its unavailable exact cut-cell list.
		for _,cut in session.cuts do if (x-cut[2])^2+(y-cut[3])^2<=cut[4]^2 then return false end end
		return true
	end
	local body:EditableImage?=nil
	local shade:EditableImage?=nil
	local bodyPixels:buffer?=nil
	local shadePixels:buffer?=nil
	local retry,idle=0,os.clock()
	local lastTime:number?=nil
	local disabled=false
	local views:{[string]:any}={}
	local function clear()
		for _,v in views do v.part:Destroy() end;table.clear(views)
		Memory.release(body);Memory.release(shade);body,shade=nil,nil
	end
	local function images():boolean
		if body and shade then return true end
		if os.clock()<retry then return false end
		local size=Vector2.new(data.width,data.height)
		body=Memory.create(size);if body then shade=Memory.create(size) end
		if not body or not shade then clear();retry=os.clock()+5;return false end
		local loaded,err=pcall(function()
			bodyPixels=bodyPixels or Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4)
			shadePixels=shadePixels or Inflate.raw(Codec.base64Decode(data.shade),data.width*data.height*4)
			local bodyImage=body :: EditableImage
			local shadeImage=shade :: EditableImage
			bodyImage:WritePixelsBuffer(Vector2.zero,size,bodyPixels :: buffer)
			shadeImage:WritePixelsBuffer(Vector2.zero,size,shadePixels :: buffer)
		end)
		if not loaded then clear();disabled=true;warn("[Civilians] Traffic atlas unavailable:",err);return false end
		return true
	end
	local function create():any
		local part=Instance.new("Part");part.Name="CivilianCar";part.Anchored=true;part.Transparency=1
		part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize=Vector2.new(data.frame,data.frame);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0;gui.ClipsDescendants=false
		local function label(image:EditableImage):ImageLabel
			local l=Instance.new("ImageLabel");l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1)
			l.ImageContent=Content.fromObject(image);l.ImageRectSize=Vector2.new(data.frame,data.frame)
			l.ResampleMode=Enum.ResamplerMode.Default;l.Parent=gui;return l
		end
		local shadow=label(shade :: EditableImage);shadow.ImageColor3=Color3.new(0,0,0)
		local color=label(body :: EditableImage)
		gui.Parent=part;part.Parent=folder
		return {part=part,gui=gui,shadow=shadow,color=color}
	end
	local connection=RunService.RenderStepped:Connect(function()
		if disabled or not session.clock then return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local time=session.clock+(if session.running then math.min(.5,os.clock()-session.at) else 0)
		local delta=if lastTime then time-lastTime else 0
		local snap=lastTime==nil or delta<0 or delta>data.config.jumpSec
		lastTime=time
		local distance=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local ry=distance*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
		local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
		local pixels=camera.ViewportSize.Y/(2*ry)
		if pixels<data.config.from then
			if body or next(views) then clear() end
			lastTime=nil;return
		end
		local light=Daylight.get()
		local share=math.clamp((pixels-data.config.from)/(data.config.full-data.config.from),0,1)
		if flow then Driving.plan(flow,time,if snap then 0 else delta,share,light.night,snap,session.movers) end
		local poses=Traffic.step(state,time,if snap then 0 else delta,share,light.night,session.movers,onRoad,snap)
		if flow then Driving.finish(flow) end
		local wanted={}
		local cx,cy=camera.CFrame.Position.X/World.STUDS_PER_CELL,camera.CFrame.Position.Z/World.STUDS_PER_CELL
		local sun=light.shadow;local length=math.sqrt(sun[1]^2+sun[2]^2)
		local factor=if length>2 then 2/length else 1
		for _,p in poses do
			if math.abs(p.x-cx)>rx+1 or math.abs(p.y-cy)>ry+1 or Fog.hidden(p.x,p.y) then continue end
			if not images() then break end
			wanted[p.id]=true
			local v=views[p.id];if not v then v=create();views[p.id]=v end
			local size=data.frame/data.px*p.cells
			v.part.Size=Vector3.new(size*World.STUDS_PER_CELL,.01,size*World.STUDS_PER_CELL)
			v.part.CFrame=CFrame.new(World.toWorld(p.x,p.y,.29))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
			local facing=math.floor(p.heading/(math.pi*2)*data.facings+.5)%data.facings
			local offset=Vector2.new(facing*data.frame,data.rects[p.model])
			v.color.ImageRectOffset=offset;v.shadow.ImageRectOffset=offset
			v.color.ImageTransparency=1-p.alpha
			local alpha=data.config.shadow.alpha*(light.shadowAlpha or 1)*p.alpha
			v.shadow.ImageTransparency=1-alpha
			v.shadow.Position=UDim2.fromScale(sun[1]*factor*data.config.shadow.car/size,sun[2]*factor*data.config.shadow.car/size)
		end
		for id,v in views do if not wanted[id] then v.part:Destroy();views[id]=nil end end
		if next(views) then idle=os.clock() elseif body and os.clock()-idle>3 then clear() end -- APPROX idle storage policy.
	end)
	folder.Destroying:Connect(function() connection:Disconnect();clear();if current==session then current=nil end end)
end
function Renderer.applyCities(rows:{any},time:number?)
	if current then Traffic.applyCities(current.state,rows,time or current.clock or 0) end
end
function Renderer.applyCuts(rows:{any}) if current then current.cuts=rows end end
function Renderer.syncClock(time:number,running:boolean)
	if current then current.clock=time;current.running=running;current.at=os.clock() end
end
function Renderer.snapshot(units:{any})
	if not current then return end
	local movers={}
	local fighters={}
	for _,u in units do
		-- Snapshots contain own/currently visible units. INSIDE (4) troops do not block traffic.
		if u[9]~=4 then table.insert(movers,{x=u[4],y=u[5]}) end
		table.insert(fighters,{x=u[4],y=u[5],shotAge=u[15] or 9,hitAge=u[18] or 9})
	end
	current.movers=movers
	current.fighters=fighters
	current.fightersAt=(current.clock or 0)+(if current.running then math.min(.5,os.clock()-current.at) else 0)
end
return Renderer
