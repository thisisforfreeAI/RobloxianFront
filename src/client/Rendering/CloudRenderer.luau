--!strict
-- Original sky field, sampled on the CPU. APPROX: small, throttled image replaces the GPU pass.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Clouds=require(Shared.Presentation.CloudField)
local Wetness=require(Shared.Presentation.GroundWetness)
local Memory=require(script.Parent.ImageMemory)
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
	local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
	label.Active=false;label.Visible=false;label.ResampleMode=Enum.ResamplerMode.Default;label.Parent=gui
	gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui");current=gui
	local image:EditableImage?=nil
	local full=false
	local retry,nextUpdate,idle=0,0,os.clock()
	local disabled=false
	local function clear()
		label.Visible=false;Memory.release(image);image=nil
	end
	local unregister=Memory.register(10,function() clear();retry=os.clock()+5 end)
	local connection=RunService.Heartbeat:Connect(function()
		if disabled or os.clock()<nextUpdate then return end
		nextUpdate=os.clock()+.15 -- APPROX cadence; the source paints every frame.
		local camera=workspace.CurrentCamera;if not camera then return end
		local view=WorldLight.view(camera)
		if Clouds.share(config,view.cellPixels)<=0 then clear();return end
		-- APPROX: half-resolution at wider zoom keeps expensive unique noise samples bounded.
		-- Two pixels/cell of hysteresis prevent repeated native allocations at the boundary.
		local detail=if view.cellPixels>=config.showPx+2 then true elseif view.cellPixels<=config.showPx then false else full
		if detail~=full then clear();full=detail end
		local width,height=if full then WIDTH else WIDTH/2,if full then HEIGHT else HEIGHT/2
		if not image and os.clock()<retry then return end
		local light=Daylight.get()
		if not light.mul or not light.add or not light.color then clear();return end
		local pixels,count=Clouds.pixels(config,light,width,height,view,Wetness.valueNoise)
		if count==0 then
			label.Visible=false
			if image and os.clock()-idle>3 then clear() end
			return
		end
		if not image then
			image=Memory.create(Vector2.new(width,height),"detail")
			if not image then retry=os.clock()+5;return end
			label.ImageContent=Content.fromObject(image)
		end
		local target=image :: EditableImage
		local painted,err=pcall(function() target:WritePixelsBuffer(Vector2.zero,Vector2.new(width,height),pixels) end)
		if not painted then clear();disabled=true;warn("[Clouds] Sky image unavailable:",err);return end
		idle=os.clock();label.Visible=true
	end)
	local parentConnection=parent.Destroying:Connect(function() gui:Destroy() end)
	gui.Destroying:Connect(function()
		connection:Disconnect();parentConnection:Disconnect();unregister();clear()
		if current==gui then current=nil end
	end)
end
return Renderer
