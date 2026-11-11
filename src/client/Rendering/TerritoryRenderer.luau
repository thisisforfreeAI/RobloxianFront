--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Pixels=require(Shared.Presentation.TerritoryPixels)
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local TerritoryRenderer={}
local image: EditableImage?=nil
local width,height=0,0
local config: any=nil
local built: buffer?=nil
local pending:{number}?=nil
local busy=false
function TerritoryRenderer.start(w: number,h: number,mapId: string)
	width,height=w,h
	local data=Shared:FindFirstChild("GameData")
	local module=data and data:FindFirstChild("WorldLook")
	if not module then return end
	config=require(module :: ModuleScript)
	local visibility=data:FindFirstChild("Visibility_"..mapId)
	if visibility then
		local v=require(visibility :: ModuleScript) :: any
		if v.width==w and v.height==h then built=Inflate.raw(Codec.base64Decode(v.deflate),w*h) end
	end
	if w*2>1024 or h*2>1024 then warn("[Territory] map needs tiled ownership overlay");return end
	image=Memory.create(Vector2.new(w*2,h*2))
	if not image then return end
	local part=Instance.new("Part")
	part.Name="Territory";part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false;part.Transparency=1
	part.Size=Vector3.new(h*World.STUDS_PER_CELL,.02,w*World.STUDS_PER_CELL)
	part.CFrame=CFrame.new(w*World.STUDS_PER_CELL/2,World.GROUND_Y+.2,h*World.STUDS_PER_CELL/2)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
	local gui=Instance.new("SurfaceGui")
	gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=Vector2.new(w*2,h*2);gui.LightInfluence=0;gui.MaxDistance=0
	local label=Instance.new("ImageLabel")
	label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.ImageContent=Content.fromObject(image)
	label.Parent=gui;gui.Parent=part;part.Parent=workspace
	part.Destroying:Connect(function() Memory.release(image);image=nil end)
end
function TerritoryRenderer.apply(runs: {number})
	if not image then return end
	pending=runs
	if busy then return end
	busy=true
	task.spawn(function()
		while pending and image do
			local current=pending;pending=nil
			local started=os.clock()
			local function checkpoint()
				if os.clock()-started>.003 then RunService.Heartbeat:Wait();started=os.clock() end
			end
			local pixels=Pixels.render(current,width,height,config.territory,config.palette,built,checkpoint)
			if image and not upload(image,Vector2.zero,Vector2.new(width*2,height*2),pixels,{priority=2}) then
				pending=pending or current;RunService.Heartbeat:Wait()
			end
		end
		busy=false
	end)
end
return TerritoryRenderer
