--!strict
-- Original local player-building art with shared images and screen-space label packing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local RunService=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Art=require(script.Parent.StructureArt)
local Daylight=require(script.Parent.DaylightController)
local Labels=require(ReplicatedStorage.Shared.Presentation.StructureLabels)
local SiteMotion=require(ReplicatedStorage.Shared.Presentation.SiteMotion)
local StructureRenderer = {}

export type View = { id: number, kind: string, side: number, x: number, y: number, anchor: Part, ring: Part?, block: Part?, bar: Frame, barBack: Frame, text: TextLabel, seen: number, built: number, hp: number?, maxHp: number?, art: any, army: string, stale: boolean, gui: BillboardGui, labelRoot: Frame, status: string, production: any, weapon: any, artillery: any, site: any }

local NAMES = { hq = "HQ", barracks = "Barracks", factory = "War Factory", bunker = "Bunker", atgun = "AT Gun", radar = "Radar", sam = "SAM Site", artybase = "Artillery Base", nightops = "Night Ops Tower" }
local DEFENCE = { bunker = true, atgun = true, radar = true, sam = true, nightops = true }
-- footprint radius in cells (production.footprint.facility and .defence = 1, so 3 x 3)
local FOOT = 1

local S = World.STUDS_PER_CELL
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }
local views: { [number]: View } = {}
local folder: Folder
local lastTick = 0
local focus: number?=nil
local connection: RBXScriptConnection?=nil

local function part(size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size, p.CFrame, p.Color, p.Transparency = size, cf, color, transparency
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = folder
	return p
end

local function create(id: number, kind: string, x: number, y: number): View
	local pos = World.toWorld(x, y, 0.3)
	local anchor = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), Color3.new(), 1)
	local ring: Part? = nil
	local block: Part? = nil
	if NAMES[kind] then
		local size = (if kind == "hq" then 5 else FOOT * 2 + 1) * S
		local tall = .02
		block = part(Vector3.new(size, tall, size), CFrame.new(World.toWorld(x, y, .35))*CFrame.Angles(0,World.TOP_GUI_YAW,0), Color3.new(0.7, 0.7, 0.7), 0)
		if DEFENCE[kind] then
			(block :: Part).Material = Enum.Material.Concrete
		end
	end
	if kind == "rig" then
		local r = 1.6 * S + 0.6
		ring = part(Vector3.new(0.12, r * 2, r * 2), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(1, 1, 1), 1)
		;(ring :: Part).Shape = Enum.PartType.Cylinder
		;(ring :: Part).Material = Enum.Material.Neon
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(144, 26)
	gui.StudsOffsetWorldSpace = Vector3.zero
	local root=Instance.new("Frame");root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);root.Parent=gui
	gui.AlwaysOnTop = true
	gui.Enabled=false
	gui.Adornee = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, 14)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Font = Enum.Font.GothamBold
	text.TextSize = 11
	text.Parent = root
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(0, 16)
	barBack.Size = UDim2.new(1, 0, 0, 6)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBack.BorderSizePixel = 0
	barBack.Parent = root
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	gui.Parent = anchor
	return { id = id, kind = kind, side = 0, x = x, y = y, anchor = anchor, ring = ring, block = block, bar = bar, barBack = barBack, text = text, seen = 0, built = 1, art=nil, army="coalition", stale=false, gui=gui, labelRoot=root, status="" }
end

local function present()
	local camera=workspace.CurrentCamera;if not camera then return end
	local size=camera.ViewportSize
	local pixels=S*size.Y/(2*math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)*math.tan(math.rad(camera.FieldOfView/2)))
	local inset=GuiService:GetGuiInset();local mouse=Input:GetMouseLocation()-inset
	local hover: number?=nil;local distance=40*40
	local projected={}
	for id,v in views do
		local point,on=camera:WorldToViewportPoint(v.anchor.Position)
		if on and point.X>=0 and point.Y>=0 and point.X<=size.X and point.Y<=size.Y then
			projected[id]=point
			local d=(Vector2.new(point.X,point.Y)-mouse).Magnitude^2
			if d<distance then hover=id;distance=d end
		end
	end
	local candidates={};local light=Daylight.get()
	for id,v in views do
		local point=projected[id];v.gui.Enabled=false
		if not point then continue end
		if v.block then
			if not v.art then v.art=Art.attach(v.block,v.kind,v.army) end
			if v.art then
				v.block.Transparency=1
				local importance=if focus==id then 1000 elseif hover==id then 900 else 1/(1+(Vector2.new(point.X,point.Y)-size/2).Magnitude/100)
				Art.update(v.art,v.side,v.stale,v.built,light,id,v.hp,v.maxHp,importance,v.production,v.weapon,v.artillery,v.site,(if v.kind=="hq" then 5 else 3)*pixels)
			end
		end
		local detail=Labels.detail(v,pixels,focus==id,hover==id)
		if v.kind=="rig" then detail.visible=v.status~="" and (pixels>=4 or focus==id or hover==id);detail.priority=if focus==id then 100 else 30 end
		if not detail.visible then continue end
		v.barBack.Visible=if v.kind=="rig" then v.barBack.Visible else detail.bar
		v.text.Text=if v.kind=="rig" or v.stale or v.built<1 or detail.numbers then v.status else NAMES[v.kind] or v.kind
		table.insert(candidates,{id=id,x=point.X,y=point.Y,w=144,h=26,priority=detail.priority})
	end
	local layout=Labels.layout(candidates,size.X,size.Y)
	for id,rect in layout do
		local v=views[id];local point=projected[id]
		v.gui.Size=UDim2.fromOffset(rect.w,rect.h)
		v.labelRoot.Position=UDim2.fromOffset(rect.x-point.X+rect.w/2,rect.y-point.Y+rect.h/2)
		v.gui.Enabled=true
	end
end
function StructureRenderer.start()
	if connection then connection:Disconnect();connection=nil end
	if folder then folder:Destroy() end
	Art.reset();table.clear(views);lastTick=0;focus=nil
	folder = Instance.new("Folder");folder.Name = "WarFrontStructures";folder.Parent = workspace
	local elapsed=0
	connection=RunService.Heartbeat:Connect(function(dt) Art.step();elapsed+=dt;if elapsed<.1 then return end;elapsed=0;present() end)
	folder.Destroying:Connect(function() if connection then connection:Disconnect();connection=nil end;Art.reset() end)
end
function StructureRenderer.setFocus(id:number?) focus=id end

-- structures: { id, kind, side, x, y, hp, maxHp, capSide, capProgress, store, built, stale, army }
-- stale = 1: an enemy building remembered from an earlier sighting (fog): drawn faded, health unknown.
function StructureRenderer.apply(tick: number, structures: { any })
	if tick <= lastTick then
		return
	end
	local initial=lastTick==0;lastTick = tick
	for _, st in structures do
		local id, kind, side, x, y, hp, maxHp, capSide, capProgress, store, built, stale = table.unpack(st)
		-- Minefields have their own filtered cell overlay, not a building footprint or oil-rig ring.
		if not NAMES[kind] and kind~="rig" then continue end
		local v = views[id]
		if v and v.kind~=kind then
			v.anchor:Destroy();if v.block then v.block:Destroy() end;if v.ring then v.ring:Destroy() end
			views[id]=nil;v=nil
		end
		if not v then
			v = create(id, kind, x, y)
			views[id] = v
		end
		v.side, v.seen, v.built, v.hp, v.maxHp = side, tick, built or 1, hp, maxHp
		local army=if st[13]=="republic" then "republic" else "coalition"
		if v.army~=army and v.art then v.art.gui:Destroy();v.art=nil end
		v.army=army;v.stale=stale==1;v.production=st[14];v.weapon=st[15];v.artillery=st[16]
		v.site=SiteMotion.observe(v.site,v.built,not v.stale,os.clock(),initial)
		if v.art and v.stale then Art.update(v.art,side,true,v.built,Daylight.get(),id,hp,maxHp,nil,nil) end
		if v.block then
			local block = v.block :: Part
			local color = SIDE_COLOR[side] or Color3.new(0.7, 0.7, 0.7)
			local b = built or 1
			block.Color = if b < 1 then color:Lerp(Color3.new(1, 1, 1), 0.55) else color:Lerp(Color3.new(0, 0, 0), 0.15)
			block.Transparency = if v.art then 1 elseif b < 1 or stale == 1 then 0.35 else 0
			if stale == 1 then
				v.status = `{NAMES[kind]} (last seen)`
				v.bar.Size = UDim2.fromScale(0, 1)
			elseif b < 1 then
				v.status = `{NAMES[kind]} {math.floor(b * 100)}%`
				v.bar.Size = UDim2.fromScale(math.clamp(b, 0, 1), 1)
				v.bar.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
			else
				v.status = `{NAMES[kind]} {math.floor(hp)}/{maxHp}`
				v.bar.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
				v.bar.BackgroundColor3 = color
			end
		elseif kind == "hq" then
			local frac = math.clamp(hp / maxHp, 0, 1)
			v.status = `HQ {math.floor(hp)}/{maxHp}`
			v.bar.Size = UDim2.fromScale(frac, 1)
			v.bar.BackgroundColor3 = SIDE_COLOR[side] or Color3.new(1, 1, 1)
		else
			local ring = v.ring :: Part
			ring.Transparency = if side == 0 then 1 else 0.55
			ring.Color = SIDE_COLOR[side] or Color3.new(1, 1, 1)
			if capProgress > 0 and capSide ~= 0 then
				v.barBack.Visible = true
				v.bar.Size = UDim2.fromScale(math.clamp(capProgress, 0, 1), 1)
				v.bar.BackgroundColor3 = SIDE_COLOR[capSide] or Color3.new(1, 1, 1)
				v.status = "capturing"
			elseif hp and maxHp and hp <= 0 then
				-- wrecked: pumps nothing until engineers repair it
				v.barBack.Visible = false
				v.status = "DESTROYED"
			elseif hp and maxHp and hp < maxHp then
				v.barBack.Visible = true
				v.bar.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
				v.bar.BackgroundColor3 = Color3.fromRGB(220, 120, 60)
				v.status = if side == 0 then "DAMAGED" else `DAMAGED · oil {math.floor(store)}`
			else
				v.barBack.Visible = false
				v.status = if side == 0 then "" else `oil {math.floor(store)}`
			end
		end
	end
	for id, v in views do
		if v.seen ~= tick then
			if v.block then v.block:Destroy() end
			v.anchor:Destroy()
			if v.ring then v.ring:Destroy() end
			views[id] = nil
		end
	end
end

-- For right-click targeting: structures the given side could attack.
function StructureRenderer.each(): { [number]: View }
	return views
end

return StructureRenderer
