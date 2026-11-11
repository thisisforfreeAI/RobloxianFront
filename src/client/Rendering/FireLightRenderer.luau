--!strict
-- Original grouped fire lights on disjoint, world-anchored tiles below fog and units.
-- APPROX: HDR alpha replaces CSS color-dodge; 16-cell tiles, a 3ms repaint budget and
-- two image admissions per check replace the original full-canvas draw. Native appearance needs Studio.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Light=require(Shared.Presentation.FireLight)
local Pixels=require(Shared.Presentation.FireLightPixels)
local NightPixels=require(Shared.Presentation.NightLightPixels)
local World=require(Shared.Config.World)
local Memory=require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=Memory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local Daylight=require(script.Parent.DaylightController)
local Fog=require(script.Parent.FogOverlay)
local WorldLight=require(script.Parent.WorldLight)
local Renderer={}
function Renderer.start(map:any,parent:Instance):any
	local data=Shared:FindFirstChild("GameData")
	local module=data and data:FindFirstChild("FireLightRules")
	if not module then return nil end
	local ok,config=pcall(require,module)
	if not ok then warn("[FireLights] Local settings unavailable:",config);return nil end
	local folder=Instance.new("Folder");folder.Name="FireLightPools";folder.Parent=parent
	local state:any={tiles={},queue={},cursor=1,retry=0,check=0,nv=false,alive=true,scale=0}
	local rng=Random.new()
	local function visible(x,y,cell)
		if cell then x,y=cell%map.width+.5,math.floor(cell/map.width)+.5 end
		return not Fog.hidden(x,y)
	end
	local function strength() return math.max(config.light.day,Daylight.get().night) end
	local model=Light.new(config,map.width,{visible=visible,enabled=function() return strength()>0 end,random=function() return rng:NextNumber() end})
	local function release(tile)
		if tile.part then tile.part:Destroy() end
		Memory.release(tile.image);state.tiles[tile.key]=nil
	end
	local function clear()
		for _,tile in state.tiles do release(tile) end
		state.queue={};state.cursor=1
	end
	local function allocate(tile)
		local size=Vector2.new(tile.cw*state.scale,tile.ch*state.scale)
		local image=Memory.create(size,"detail");if not image then state.retry=os.clock()+5;return false end
		local part=Instance.new("Part");part.Name="FireGlow_"..tile.key
		part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false;part.Transparency=1
		part.Size=Vector3.new(tile.ch*World.STUDS_PER_CELL,.01,tile.cw*World.STUDS_PER_CELL)
		-- Keep fire pools below city emission (.24) and side windows (.245), never coplanar.
		part.CFrame=CFrame.new((tile.x+tile.cw/2)*World.STUDS_PER_CELL,World.GROUND_Y+.23,(tile.y+tile.ch/2)*World.STUDS_PER_CELL)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize=size;gui.LightInfluence=0;gui.MaxDistance=0
		local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
		label.ResampleMode=Enum.ResamplerMode.Pixelated;label.ImageContent=Content.fromObject(image);label.Visible=false
		label.Parent=gui;gui.Parent=part;part.Parent=folder
		tile.image,tile.part,tile.gui,tile.label,tile.size=image,part,gui,label,size
		state.tiles[tile.key]=tile;return true
	end
	local unregister=Memory.register(10,function()
		clear();state.retry=os.clock()+5
	end)
	local connection=RunService.Heartbeat:Connect(function()
		local now=os.clock();local level=strength();local camera=workspace.CurrentCamera
		if level<=0 then model.lights={};clear();return end
		if not camera then clear();return end
		local view=WorldLight.view(camera)
		if view.cellPixels<config.light.fromPx then clear();return end
		local scale=math.max(1,math.min(config.light.texelsPerCell,math.floor(view.cellPixels/config.light.minTexelPx)))
		if scale~=state.scale then clear();state.scale=scale;state.check=0 end
		local mix=if state.nv then 1 else 0
		local pools={}
		for _,p in model.lights do
			if p.now>.01 and visible(p.x,p.y) then table.insert(pools,{x=p.x,y=p.y,reach=p.reach,power=p.now*level,color=p.color}) end
		end
		if #pools==0 then clear();return end
		-- Re-evaluate fog/camera membership every frame; texture work is independently budgeted.
		local wanted={};local reachGain=1+(config.nv.reach-1)*mix
		for _,p in pools do
			local r=p.reach*reachGain
			local xmin=math.max(0,math.floor(math.max(p.x-r,view.cx-view.rx)/16))
			local xmax=math.min(math.ceil(map.width/16)-1,math.floor(math.min(p.x+r,view.cx+view.rx)/16))
			local ymin=math.max(0,math.floor(math.max(p.y-r,view.cy-view.ry)/16))
			local ymax=math.min(math.ceil(map.height/16)-1,math.floor(math.min(p.y+r,view.cy+view.ry)/16))
			for y=ymin,ymax do for x=xmin,xmax do
				local key=x..":"..y;local t=wanted[key]
				if not t then t={key=key,x=x*16,y=y*16,cw=math.min(16,map.width-x*16),ch=math.min(16,map.height-y*16),pools={}};wanted[key]=t end
				table.insert(t.pools,p)
			end end
		end
		for key,tile in state.tiles do
			if not wanted[key] then release(tile) end
		end
		if now>=state.check then
			state.check=now+.1;local added=0
			local ordered={};for _,tile in wanted do table.insert(ordered,tile) end
			table.sort(ordered,function(a,b)
				return (a.x+8-view.cx)^2+(a.y+8-view.cy)^2<(b.x+8-view.cx)^2+(b.y+8-view.cy)^2
			end)
			for _,tile in ordered do
				if not state.tiles[tile.key] and added<2 and now>=state.retry then if allocate(tile) then added+=1 end end
			end
			state.queue={};for _,tile in state.tiles do table.insert(state.queue,tile) end
			-- Oldest first keeps all admitted tiles progressing under dense-fire load.
			table.sort(state.queue,function(a,b) return (a.painted or -1)<(b.painted or -1) end);state.cursor=1
		end
		local correction=NightPixels.compensate(Daylight.postEffect(),{1,1,1})
		for _,tile in state.tiles do
			tile.gui.Brightness=correction.brightness
			tile.label.ImageColor3=Color3.new(correction.color[1],correction.color[2],correction.color[3])
			-- Hide cached pixels immediately if their contributing source set or NV mode changed.
			local signature="";for _,p in wanted[tile.key].pools do signature..=p.x..","..p.y..","..p.reach..";" end
			tile.signature=signature..tostring(mix);tile.label.Visible=tile.savedSignature==tile.signature
		end
		if state.lookupMix~=mix then state.lookup=Pixels.lookup(config,mix);state.lookupMix=mix end
		local began=os.clock()
		while state.cursor<=#state.queue do
			local tile=state.queue[state.cursor];state.cursor+=1
			if state.tiles[tile.key]~=tile then continue end
			local want=wanted[tile.key];if not want then continue end
			local rgba=Pixels.paint(config,want.pools,tile.x,tile.y,tile.cw,tile.ch,state.scale,mix,state.lookup,visible)
			local signature=tile.signature
			local accepted=upload(tile.image,Vector2.zero,tile.size,Pixels.native(rgba),{priority=3,done=function(ok)
				if not state.alive or state.tiles[tile.key]~=tile then return end
				tile.label.Visible=ok and tile.signature==signature
				if ok then tile.savedSignature=signature end
			end})
			if accepted then tile.painted=now end
			if os.clock()-began>=.003 then break end
		end
	end)
	folder.Destroying:Connect(function() state.alive=false;connection:Disconnect();unregister();clear();model.reset() end)
	return {
		advance=function(trees,houses,dt) if state.alive then model.advance(trees,houses,dt) end end,
		reset=function() if state.alive then model.reset();clear();state.check=0 end end,
		setNightVision=function(on) state.nv=on end,
		destroy=function() if state.alive then folder:Destroy() end end,
	}
end
return Renderer
