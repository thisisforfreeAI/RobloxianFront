--!strict
-- Local particle atlas + shared death presentation state. Atlas loads on the first visible death,
-- using one 96px EditableImage; vehicle art stays lazy. DeathFx/OrigDeathFx are generated privately.
-- APPROX: flat projected quads replace Pixi's additive/dithered passes. See PROJECT_STATUS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ImageMemory = require(script.Parent.ImageMemory)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathEffects = require(Shared.Presentation.DeathEffects)
local ImpactEffects=require(Shared.Presentation.ImpactEffects)
local TracerFlight=require(Shared.Presentation.TracerFlight)
local BallisticFlight=require(Shared.Presentation.BallisticFlight)
local ballisticConfig:any=nil
local ballisticChecked=false
local tracerClock=TracerFlight.clock()
local tracerConfig:any=nil
local tracerChecked=false
local impacts=ImpactEffects.new()
local impactConfig:any=nil
local impactChecked=false
local MapCodec = require(Shared.Maps.MapCodec)
local PixelCodec = require(Shared.Assets.PixelCodec)
local World = require(Shared.Config.World)
local Fog = require(script.Parent.FogOverlay)
local Static=if script.Parent.StaticImages then require(script.Parent.StaticImages)else nil
local staticMeta:any=nil
local DeathRenderer = {}
local engine: any = nil
local content: Content? = nil
local atlasImage: EditableImage? = nil -- keep the image alive alongside its Content
local frame = 24
local retryAt,disabled,warnedFailure = 0,false,false
local slots: { any } = {}
local root: Folder? = nil
local FRAMES = { disc = { 1, 0 }, ring = { 2, 0 }, star = { 3, 0 }, spark = { 0, 1 }, chunk = { 1, 1 }, shard = { 2, 1 },
	puffA = { 3, 1 }, puffB = { 0, 2 }, puffC = { 1, 2 }, blobA = { 2, 2 }, blobB = { 3, 2 }, blobC = { 0, 3 },streak={1,3}, glint = { 2, 3 } }
-- Convoys and demolition trucks have separate effect routines in the game, pending their own port.
-- Do not give either the generic light-vehicle variants just because both leave a death snapshot.
local SUPPORTED = { tank = true, ifv = true, artillery = true, rocket = true, scout = true, engineer = true, command = true }

local function load(): boolean
	if engine then return true end
	if disabled or os.clock()<retryAt then return false end
	retryAt=os.clock()+5
	local data = Shared:FindFirstChild("GameData")
	local config = data and data:FindFirstChild("DeathFx")
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local pixels = assets and assets:FindFirstChild("OrigDeathFx")
	if not config or not pixels then
		disabled=true
		warn("[DeathRenderer] Generate local death effects with tools/conversion/export_death_fx.cjs; wrecks still draw")
		return false
	end
	local ok, err = pcall(function()
		local meta = require(pixels :: ModuleScript) :: any
		staticMeta=meta
		local asset=Static and Static.get("OrigDeathFx",meta)
		if asset then content=asset.content;frame=meta.frame;engine=DeathEffects.new(require(config :: ModuleScript));return end
		local image = ImageMemory.create(Vector2.new(meta.width, meta.height),"detail","DeathRenderer")
		assert(image, "EditableImage budget refused particle atlas")
		atlasImage = image
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(meta.width, meta.height), PixelCodec.decode(MapCodec.base64Decode(meta.rle), meta.width, meta.height))
		content, frame = Content.fromObject(image), meta.frame
		engine = DeathEffects.new(require(config :: ModuleScript))
	end)
	if not ok then
		if atlasImage then ImageMemory.release(atlasImage); atlasImage = nil end
		content, engine = nil, nil
		if not warnedFailure then warnedFailure=true;warn("[DeathRenderer] Death effects unavailable; wrecks still draw:", err) end
	else warnedFailure=false
	end
	return engine ~= nil
end

function DeathRenderer.kill(kind: string, x: number, y: number): any
	if not SUPPORTED[kind] or Fog.hidden(x, y) or not load() then return nil end
	return engine:kill(kind, x, y)
end

-- Prepared world-fire bridge: the caller supplies a local map/session tag for cleanup.
function DeathRenderer.request(kind:string,p:any,tag:any?):boolean
	if kind~="spawn" and kind~="puff" and kind~="embers" and kind~="tracer" and kind~="ballistic"then return false end
	if Fog.hidden(p.x,p.y) or not load() then return false end
	return engine:request(kind,p,tag)
end
function DeathRenderer.ballistic(event:any,budget:any,tag:any?):boolean
	local now=TracerFlight.time(tracerClock,os.clock());if not now or event.weapon=="tbm"then return false end
	if not ballisticChecked then
		ballisticChecked=true;local data=Shared:FindFirstChild("GameData");local source=data and data:FindFirstChild("BallisticFx")
		if source then local ok,result=pcall(require,source);if ok then ballisticConfig=result end end
	end
	if not ballisticConfig then return false end
	local p=BallisticFlight.shot(ballisticConfig,event,now);if not p then return false end
	local flight=BallisticFlight.plan(p);if not flight then return false end;local slots=BallisticFlight.slots(flight)
	if budget.particles<slots then return false end;budget.particles-=slots
	return DeathRenderer.request("ballistic",p,tag)
end
function DeathRenderer.vehicleTracer(event:any,budget:any,tag:any?):boolean
	local now=TracerFlight.time(tracerClock,os.clock())
	if not now or budget.particles<2 then return false end
	if not tracerChecked then
		tracerChecked=true;local data=Shared:FindFirstChild("GameData");local source=data and data:FindFirstChild("VehicleTracerFx")
		if source then local ok,result=pcall(require,source);if ok then tracerConfig=result end end
	end
	if not tracerConfig then return false end
	local p=TracerFlight.shot(tracerConfig,event,now);if not p then return false end
	budget.particles-=2;return DeathRenderer.request("tracer",p,tag)
end
function DeathRenderer.clearTag(tag:any)
	if tag==nil or not engine then return end;engine:clearTag(tag)
	-- The next shared render step restores any remaining untagged vehicle particles.
	for _,v in slots do v.gui.Enabled=false end
	if #engine.particles==0 then
		for _,v in slots do v.part:Destroy() end;table.clear(slots)
		if root then root:Destroy();root=nil end
	end
end

-- Uses the existing visible blast tail; optional private settings never block normal units.
function DeathRenderer.impacts(tick:number,rows:{any},war:any)
	if TracerFlight.sync(tracerClock,tick,war,os.clock())and engine then engine:clearFlights()end
	if #rows>0 and not impactChecked then
		impactChecked=true;local data=Shared:FindFirstChild("GameData");local source=data and data:FindFirstChild("ImpactFx")
		if source then local ok,value=pcall(require,source);if ok then impactConfig=value end end
	end
	ImpactEffects.receive(impacts,tick,rows,war,os.clock(),Fog.hidden,Fog.water)
end
function DeathRenderer.resetImpacts()
	DeathRenderer.clearTag(impacts);impacts=ImpactEffects.new()
	if engine then engine:clearFlights()end;tracerClock=TracerFlight.clock()
end
local function emitImpactParticle(p:any):boolean return DeathRenderer.request("spawn",p,impacts)end

local function slot(i: number): any
	if slots[i] then return slots[i] end
	if not root then root = Instance.new("Folder"); root.Name = "WarFrontDeathEffects"; root.Parent = workspace end
	local p = Instance.new("Part")
	p.Name = "DeathParticle"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Parent = root
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(frame, frame)
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ImageContent = content :: Content
	label.ImageRectSize = Vector2.new(frame, frame)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.Parent = gui
	local s = { part = p, gui = gui, image = label }
	slots[i] = s
	return s
end

function DeathRenderer.step(dt: number,shadowShare:number?)
	-- Age existing effects before admitting this frame's hits: a slow frame must not
	-- consume an entire new flash before its first draw.
	if engine then engine:step(dt,TracerFlight.time(tracerClock,os.clock()),Fog.hidden,shadowShare)end
	if impactConfig then
		ImpactEffects.step(impacts,impactConfig,os.clock(),Fog.hidden,Fog.water,emitImpactParticle)
	end
	if not engine then return end
	if Static and staticMeta and atlasImage then
		local asset=Static.get("OrigDeathFx",staticMeta)
		if asset then
			for _,slot in slots do slot.image.ImageContent=asset.content end
			local old=atlasImage;atlasImage=nil;content=asset.content;ImageMemory.release(old)
		end
	end
	local used = 0
	local scale = World.STUDS_PER_CELL
	local camera = workspace.CurrentCamera
	for _, p in engine.particles do
		if p.ballistic and not BallisticFlight.visible(p,Fog.hidden)then continue end
		if p.tracer and not TracerFlight.visible(p,Fog.hidden)then continue end
		-- Test the source and current cell; a plume crossing the fog edge must not reveal a death.
		if Fog.hidden(p.x0, p.y0) or Fog.hidden(p.x, p.y) then continue end
		local pos = World.toWorld(p.x, p.y - p.h * math.cos(math.rad(62)), 0.55)
		local size = (p.drawSize or (if p.pop then 0.001 else p.size)) * scale
		if camera then
			local screen = camera:WorldToViewportPoint(pos)
			if screen.Z <= 0 then continue end
			local pad = size * p.len * camera.ViewportSize.Y / math.max(1, 2 * screen.Z * math.tan(math.rad(camera.FieldOfView) / 2))
			if screen.X < -pad or screen.Y < -pad or screen.X > camera.ViewportSize.X + pad or screen.Y > camera.ViewportSize.Y + pad then continue end
		end
		used += 1
		local s = slot(used)
		local cr = FRAMES[p.tex] or FRAMES.disc
		s.gui.Enabled = true
		-- Original px is the solid 4x4 crop inside the atlas corner, not a whole disc tile.
		s.image.ImageRectOffset = if p.tex=="px" then Vector2.new(1,1) else Vector2.new(cr[1]*frame,cr[2]*frame)
		s.image.ImageRectSize = if p.tex=="px" then Vector2.new(4,4) else Vector2.new(frame,frame)
		s.image.ImageTransparency = 1 - math.clamp(p.alpha or p.a0, 0, 1)
		local tint=p.tint or p.color
		s.image.ImageColor3 = Color3.fromRGB(bit32.extract(tint, 16, 8), bit32.extract(tint, 8, 8), bit32.extract(tint, 0, 8))
		s.part.Size = Vector3.new(size, 0.01, size * p.len) -- Top GUI x runs along local -Z
		s.part.CFrame = CFrame.new(pos + Vector3.new(0, used * 0.0001, 0)) * CFrame.Angles(0, World.TOP_GUI_YAW - p.rot, 0)
	end
	for i = used + 1, #slots do slots[i].gui.Enabled = false end
end

return DeathRenderer
