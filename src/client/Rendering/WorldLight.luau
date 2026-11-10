--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Pixels=require(Shared.Presentation.ScreenLight)
local Memory=require(script.Parent.ImageMemory)
local Daylight=require(script.Parent.DaylightController)
local Wetness=require(Shared.Presentation.GroundWetness)
local World=require(Shared.Config.World)
local WorldLight={}
local image: EditableImage?=nil
local stamp=""
local nextUpdate=0
local born=os.clock()
local config: any=nil
function WorldLight.start()
	local data=Shared:FindFirstChild("GameData")
	local module=data and data:FindFirstChild("WorldLook")
	if not module then warn("[WorldLight] Generate source look with export_world_look.cjs");return end
	config=require(module :: ModuleScript)
	image=Memory.create(Vector2.new(192,128))
	if not image then return end
	local gui=Instance.new("ScreenGui")
	gui.Name="WorldLight";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=-20
	local label=Instance.new("ImageLabel")
	label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.ImageContent=Content.fromObject(image)
	label.Parent=gui;gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui")
	local connection=RunService.Heartbeat:Connect(function() WorldLight.update() end)
	gui.Destroying:Connect(function() connection:Disconnect();Memory.release(image);image=nil end)
	WorldLight.update()
end
function WorldLight.update()
	if not image or not config then return end
	if os.clock()<nextUpdate then return end;nextUpdate=os.clock()+.15
	local light=Daylight.get()
	if not light.toward or not light.color then return end
	local camera=workspace.CurrentCamera;if not camera then return end
	local height=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
	local ry=height*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
	local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
	local view={cx=camera.CFrame.Position.X/World.STUDS_PER_CELL,cy=camera.CFrame.Position.Z/World.STUDS_PER_CELL,rx=rx,ry=ry,time=os.clock()-born,cellPixels=camera.ViewportSize.Y/(ry*2)}
	local nextStamp=table.concat({math.floor(light.phase*512),math.floor(view.cx),math.floor(view.cy),math.floor(rx),math.floor(ry),if light.night<1 then math.floor(view.time*2) else 0},",")
	if nextStamp==stamp then return end
	stamp=nextStamp
	image:WritePixelsBuffer(Vector2.zero,Vector2.new(192,128),Pixels.pixels(config,light,192,128,view,Wetness.valueNoise))
end
return WorldLight
