--!strict
-- Original sky field, sampled on the CPU. APPROX: small, throttled image replaces the GPU pass.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Clouds=require(Shared.Presentation.CloudField)
local Wetness=require(Shared.Presentation.GroundWetness)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local Daylight=require(script.Parent.DaylightController)
local WorldLight=require(script.Parent.WorldLight)
local Renderer={}
local current:ScreenGui?=nil
local WIDTH,HEIGHT=256,160 -- APPROX resolution policy: 160 KiB, shared by the entire sky.
function Renderer.destroy() if current then current:Destroy() end end
function Renderer.start(parent:Instance)
	Renderer.destroy()
	local settings=Shared:FindFirstChild("GameData")
	local module=settings and settings:FindFirstChild("CloudLook")
	if not module then warn("[Clouds] Generate local cloud settings with export_clouds.cjs");return end
	local ok,config=pcall(require,module :: ModuleScript)
	if not ok then warn("[Clouds] Local cloud settings unavailable:",config);return end
	local gui=Instance.new("ScreenGui");gui.Name="Clouds";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=-15
	local shadowGui=Instance.new("ScreenGui");shadowGui.Name="CloudShadows";shadowGui.IgnoreGuiInset=true;shadowGui.ResetOnSpawn=false;shadowGui.DisplayOrder=-21
	local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
	label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5)
	label.Active=false;label.Visible=false;label.ResampleMode=Enum.ResamplerMode.Default;label.Parent=gui
	local shadow=Instance.new("ImageLabel");shadow.BackgroundTransparency=1;shadow.AnchorPoint=Vector2.new(.5,.5)
	shadow.Active=false;shadow.Visible=false;shadow.ResampleMode=Enum.ResamplerMode.Default
	shadow.ImageColor3=Color3.new(0,0,0);shadow.Parent=shadowGui
	local playerGui=Players.LocalPlayer:WaitForChild("PlayerGui")
	shadowGui.Parent=playerGui;gui.Parent=playerGui;current=gui
	local image:EditableImage?=nil
	local painted:any=nil
	local full=false
	local retry,nextUpdate,idle=0,0,os.clock()
	local disabled=false
	local function clear()
		label.Visible=false;shadow.Visible=false;Memory.release(image);image=nil;painted=nil
	end
	local function place(target:any,p:any,alpha:number)
		target.Position=UDim2.fromScale(p.x,p.y);target.Size=UDim2.fromScale(p.width,p.height)
		target.ImageTransparency=1-alpha;target.Visible=p.covered and alpha>0
	end
	local function project(view:any)
		if not painted or not image then label.Visible=false;shadow.Visible=false;return end
		local light=Daylight.get()
		if not light.mul or not light.add or not light.color then label.Visible=false;shadow.Visible=false;return end
		local color,alpha=Clouds.tone(config,light,view.cellPixels)
		label.ImageColor3=Color3.new(color[1],color[2],color[3])
		place(label,Clouds.project(painted,view,config),alpha)
		local sx,sy=Clouds.offset(config,light)
		place(shadow,Clouds.project(painted,view,config,sx,sy),config.shadow*(1-light.night)*Clouds.share(config,view.cellPixels))
	end
	-- CameraController runs at Camera+1. Reproject AFTER it, without re-evaluating noise each frame.
	RunService:BindToRenderStep("WarFrontClouds",Enum.RenderPriority.Camera.Value+2,function()
		local camera=workspace.CurrentCamera
		if camera then project(WorldLight.view(camera)) end
	end)
	local unregister=Memory.register(10,function() clear();retry=os.clock()+5 end)
	local connection=RunService.Heartbeat:Connect(function()
		if disabled or os.clock()<nextUpdate then return end
		nextUpdate=os.clock()+.15 -- APPROX cadence; the source paints every frame.
		local camera=workspace.CurrentCamera;if not camera then return end
		local view=WorldLight.view(camera)
		if Clouds.share(config,view.cellPixels)<=0 then clear();return end
		-- APPROX: half-resolution at wider zoom keeps expensive unique noise samples bounded.
		-- The larger world cache needs the small image until close zoom; four pixels/cell of
		-- hysteresis prevent repeated native allocations at the boundary (port performance policy).
		local detail=if view.cellPixels>=config.showPx+12 then true elseif view.cellPixels<=config.showPx+8 then false else full
		if detail~=full then clear();full=detail end
		local width,height=if full then WIDTH else WIDTH/2,if full then HEIGHT else HEIGHT/2
		if not image and os.clock()<retry then return end
		local light=Daylight.get()
		if not light.mul or not light.add or not light.color then clear();return end
		-- APPROX cache padding covers ordinary panning between 0.15 s noise repaints.
		-- Cover both the sky view and the ground view displaced by the sun's shadow offset.
		local sx,sy=Clouds.offset(config,light)
		local field=Clouds.bounds(config,view,width,height,sx,sy)
		local pixels,count=Clouds.mask(config,width,height,field,Wetness.valueNoise)
		if count==0 then
			label.Visible=false;shadow.Visible=false;painted=nil
			if image and os.clock()-idle>3 then clear() end
			return
		end
		if not image then
			image=Memory.create(Vector2.new(width,height),"detail")
			if not image then retry=os.clock()+5;return end
			label.ImageContent=Content.fromObject(image);shadow.ImageContent=Content.fromObject(image)
		end
		local target=image :: EditableImage
		local success,err=pcall(function()
			return upload(target,Vector2.zero,Vector2.new(width,height),pixels,{priority=3,done=function(ok)
				if image~=target or disabled then return end
				if not ok then clear();disabled=true;return end
				idle=os.clock();painted=field;project(WorldLight.view(workspace.CurrentCamera or camera))
			end})
		end)
		if not success then clear();disabled=true;warn("[Clouds] Sky image unavailable:",err);return end
	end)
	local parentConnection=parent.Destroying:Connect(function() gui:Destroy() end)
	gui.Destroying:Connect(function()
		connection:Disconnect();RunService:UnbindFromRenderStep("WarFrontClouds");parentConnection:Disconnect();unregister();clear()
		shadowGui:Destroy()
		if current==gui then current=nil end
	end)
end
return Renderer
