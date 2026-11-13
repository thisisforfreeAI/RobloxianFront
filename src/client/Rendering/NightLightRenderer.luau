--!strict
-- A world-space HDR alpha layer approximates the original additive night emission, below fog,
-- forts and troops. Source-derived static fields hold windows, road lamps and dithered city glow.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Pixels=require(Shared.Presentation.NightLightPixels)
local Math=require(Shared.Presentation.GroundWetness)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local Daylight=require(script.Parent.DaylightController)
local WindowRenderer=require(script.Parent.NightWindowRenderer)
local Renderer={}
local current:any=nil
function Renderer.destroy()
	if current then current.folder:Destroy() end
end
function Renderer.setFireMask(mask:any?)
	if current then current.fireMask=mask;current.maskVersion=(current.maskVersion or 0)+1 end
end
function Renderer.start(map:any,parent:Instance?)
	Renderer.destroy()
	local assets=script.Parent.Parent:FindFirstChild("DevAssets")
	local module=assets and assets:FindFirstChild("NightLights_"..map.data.id)
	local dataFolder=Shared:FindFirstChild("GameData")
	local settings=dataFolder and dataFolder:FindFirstChild("WorldLook")
	if not module or not settings then
		warn("[NightLights] Generate local night settings/fields to enable city lighting")
		return
	end
	local profile=(require(settings :: ModuleScript) ::any).nightLights
	if not profile then warn("[NightLights] Regenerate WorldLook with export_world_look.cjs");return end
	local folder=Instance.new("Folder");folder.Name="NightCityLights";folder.Parent=parent or workspace
	local session:any={folder=folder,pages={},alive=true,epoch=0,cache=nil,preparing=false,busy=false,disabled=false,preferHalf=false,retry=0,stamp="",born=os.clock()}
	current=session
	local function clearPages()
		for _,page in session.pages do
			if page.part then page.part:Destroy() end
			Memory.release(page.image)
		end
		table.clear(session.pages);session.epoch+=1;session.stamp=""
	end
	local function checkpointFactory():()->()
		local began=os.clock()
		return function() if os.clock()-began>.003 then RunService.Heartbeat:Wait();began=os.clock() end end
	end
	local function prepare()
		if session.cache or session.preparing or session.disabled then return end
		session.preparing=true
		task.spawn(function()
			local ok,result=pcall(function()
				local meta=require(module :: ModuleScript) ::any
				assert(meta.mapWidth==map.width and meta.mapHeight==map.height,"night field map dimensions differ")
				assert(meta.width==map.width*meta.scale and meta.height==map.height*meta.scale,"invalid night field resolution")
				local fields=Inflate.raw(Codec.base64Decode(meta.deflate),meta.width*meta.height*4)
				session.meta=meta
				return Pixels.prepare(fields,meta.width,meta.height,profile,Math.hash21,checkpointFactory())
			end)
			session.preparing=false
			if not session.alive then return end
			if ok then
				session.cache=result
				session.windows=WindowRenderer.start(session.meta.windows,profile,folder,session.born,{
					blocked=function(x,y) return session.fireMask~=nil and session.fireMask.blocked(x,y) end,
					any=function() return session.fireMask~=nil and session.fireMask.any() end,
					version=function() return (session.maskVersion or 0)..":"..(if session.fireMask then session.fireMask.revision else 0) end,
				})
			else session.disabled=true;warn("[NightLights] Local fields unavailable:",result) end
		end)
	end
	local function allocate(divisor:number):boolean
		local meta=session.meta
		local w,h=math.ceil(meta.width/divisor),math.ceil(meta.height/divisor)
		if h>1024 then return false end
		local pageWidth=if w>1024 then math.ceil(w/2) else w
		if pageWidth>1024 then return false end
		for x=0,w-1,pageWidth do
			local width=math.min(pageWidth,w-x)
			local image=Memory.create(Vector2.new(width,h),"detail","NightLightRenderer")
			if not image then clearPages();return false end
			table.insert(session.pages,{image=image,x=x,w=width,h=h})
		end
		local cellScale=meta.scale/divisor
		for _,page in session.pages do
			local cx,cw=page.x/cellScale,page.w/cellScale
			local part=Instance.new("Part");part.Name="CityLight_"..page.x
			part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;part.Transparency=1
			part.Size=Vector3.new(map.height*World.STUDS_PER_CELL,.01,cw*World.STUDS_PER_CELL)
			part.CFrame=CFrame.new((cx+cw/2)*World.STUDS_PER_CELL,World.GROUND_Y+.24,map.height*World.STUDS_PER_CELL/2)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
			local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize=Vector2.new(page.w,page.h);gui.LightInfluence=0;gui.MaxDistance=0
			local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
			label.ImageContent=Content.fromObject(page.image);label.ImageTransparency=1
			label.ResampleMode=Enum.ResamplerMode.Default -- Broad city/road glow should not form coarse squares.
			label.Parent=gui;gui.Parent=part;part.Parent=folder
			page.part,page.gui,page.label=part,gui,label
		end
		session.divisor=divisor;session.epoch+=1;session.stamp=""
		return true
	end
	local acc=0
	local connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.1 then return end;acc=0
		if session.disabled or not session.alive then return end
		local light=Daylight.get()
		if light.night<=0 then if #session.pages>0 then clearPages() end;return end
		if not session.cache then prepare();return end
		if #session.pages==0 then
			if os.clock()<session.retry then return end
			local ok=false
			if not session.preferHalf then ok=allocate(1) end
			if not ok then session.preferHalf=true;ok=allocate(2) end
			if not ok then session.retry=os.clock()+5;return end
		end
		local correction=Pixels.compensate(Daylight.postEffect(),profile.color)
		for _,page in session.pages do
			page.gui.Brightness=correction.brightness*1.5 -- APPROX owner-requested stronger local city/road glow.
			page.label.ImageColor3=Color3.new(correction.color[1],correction.color[2],correction.color[3])
			page.label.ImageTransparency=1-light.night
		end
		local camera=workspace.CurrentCamera;if not camera or session.busy then return end
		local dist=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local cellPixels=World.STUDS_PER_CELL*camera.ViewportSize.Y/(2*dist*math.tan(math.rad(camera.FieldOfView/2)))
		local near=math.clamp((cellPixels-profile.near.from)/(profile.near.to-profile.near.from),0,1)
		local clock=(os.clock()-session.born)
		local windows=session.windows
		local windowGain=if windows and windows.windowGain then windows.windowGain() else 1-(windows and windows.fade or 0)
		local stamp=math.floor(clock*2)..":"..math.floor(near*8+.5)..":"..math.floor((windows and windows.fade or 0)*8+.5)
		if stamp==session.stamp then return end
		session.stamp=stamp;session.busy=true
		local epoch,divisor=session.epoch,session.divisor
		task.spawn(function()
			local ok,err=pcall(function()
				local pixels=Pixels.paint(session.cache,profile,clock,near,divisor,Math.hash21,checkpointFactory(),windowGain)
				if not session.alive or session.epoch~=epoch then return end
				local width=math.ceil(session.meta.width/divisor)
				for _,page in session.pages do
					local partPixels=buffer.create(page.w*page.h*4)
					for y=0,page.h-1 do buffer.copy(partPixels,y*page.w*4,pixels,(y*width+page.x)*4,page.w*4) end
					if not upload(page.image,Vector2.zero,Vector2.new(page.w,page.h),partPixels,{priority=3,done=function(wrote)
						if not wrote and session.alive then session.disabled=true;clearPages() end
					end}) then session.stamp=nil end
				end
			end)
			session.busy=false
			if not ok and session.alive then session.disabled=true;clearPages();warn("[NightLights] Repaint failed:",err) end
		end)
	end)
	folder.Destroying:Connect(function()
		session.alive=false;connection:Disconnect();clearPages();session.cache=nil
		if current==session then current=nil end
	end)
end
return Renderer
