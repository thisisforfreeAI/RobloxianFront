--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Wetness=require(Shared.Presentation.GroundWetness)
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Roads=require(Shared.Simulation.Roads)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local WeatherGround={}
local raining=false
function WeatherGround.setWeather(weather:string?)
	if weather then raining=weather=="storm" or weather=="downpour" end
end
function WeatherGround.start(map:any)
	local data=Shared:FindFirstChild("GameData")
	local module=data and data:FindFirstChild("WorldLook")
	if not module then return end
	local config=require(module :: ModuleScript) :: any
	local w,h=map.width*2,map.height*2
	if w>1024 or h>1024 then return end
	local blocked:buffer?=nil
	local mod=data:FindFirstChild("Visibility_"..map.data.id)
	if mod then local v=require(mod :: ModuleScript) :: any;blocked=Inflate.raw(Codec.base64Decode(v.deflate),map.width*map.height) end
	local road=buffer.create(map.width*map.height)
	for _,r in map.data.roads do
		for i=1,#r.pts-3,2 do
			for _,cell in Roads.line(map.width,map.height,r.pts[i],r.pts[i+1],r.pts[i+2],r.pts[i+3]) do buffer.writeu8(road,cell,1) end
		end
	end
	local eligible=buffer.create(w*h)
	for y=0,h-1 do for x=0,w-1 do
		local c=math.floor(y/2)*map.width+math.floor(x/2)
		local t=buffer.readu8(map.terrain,c)
		if t==0 or t==1 or t==10 or (blocked and buffer.readu8(blocked,c)~=0) then continue end
		local soil=t==2 or t==3 or t==5 or t==8 or t==9 or t==11
		buffer.writeu8(eligible,y*w+x,if soil and buffer.readu8(road,c)==0 and buffer.readu8(map.urban,c)==0 then 2 else 1)
	end end
	local field:buffer?=nil
	local state={wet=0,mud=0}
	local part:Part?=nil
	local image:EditableImage?=nil
	local retry=0
	local function clear()
		if part then part:Destroy();part=nil end
		Memory.release(image);image=nil
	end
	local acc=0
	local busy=false
	local connection:RBXScriptConnection?=nil
	connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.5 or busy then return end
		Wetness.advance(state,raining,acc,config.drying);acc=0
		if state.wet<=0 and state.mud<=0 then if image then clear() end;return end
		if not image then
			if os.clock()<retry then return end
			image=Memory.create(Vector2.new(w,h));if not image then retry=os.clock()+5;return end
			local p=Instance.new("Part");part=p
			p.Name="WeatherGround";p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Transparency=1
			p.Size=Vector3.new(map.height*World.STUDS_PER_CELL,.01,map.width*World.STUDS_PER_CELL)
			p.CFrame=CFrame.new(map.width*World.STUDS_PER_CELL/2,World.GROUND_Y+.13,map.height*World.STUDS_PER_CELL/2)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
			local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(w,h);gui.LightInfluence=0;gui.MaxDistance=0
			local label=Instance.new("ImageLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.ImageContent=Content.fromObject(image)
			label.Parent=gui;gui.Parent=p;p.Parent=workspace
		end
		if not field then field=Wetness.noise(w,h,2,config.weather) end
		busy=true
		local started=os.clock()
		local function checkpoint() if os.clock()-started>.003 then RunService.Heartbeat:Wait();started=os.clock() end end
		local pixels=Wetness.pixels(field :: buffer,eligible,w,h,state,config.weather,checkpoint)
		if image then upload(image,Vector2.zero,Vector2.new(w,h),pixels,{priority=3}) end
		busy=false
	end)
	-- Match client lives for one map. Release both connection and optional weather image at shutdown.
	script.Destroying:Connect(function() if connection then connection:Disconnect() end;clear() end)
end
return WeatherGround
