--!strict
--[[
	StructureRenderer: live state of HQs and oil rigs from server snapshots, drawn over the static map.
	  HQ: health bar; a dark slab when destroyed.
	  Rig: ring in the owner's colour (none while neutral), capture progress bar, stored oil.
	PLACEHOLDER visuals (TEMP-003).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local StructureRenderer = {}

export type View = { id: number, kind: string, side: number, x: number, y: number, anchor: Part, ring: Part?, bar: Frame, barBack: Frame, text: TextLabel, seen: number }

local S = World.STUDS_PER_CELL
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }
local views: { [number]: View } = {}
local folder: Folder
local lastTick = 0

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
	if kind == "rig" then
		local r = 1.6 * S + 0.6
		ring = part(Vector3.new(0.12, r * 2, r * 2), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(1, 1, 1), 1)
		;(ring :: Part).Shape = Enum.PartType.Cylinder
		;(ring :: Part).Material = Enum.Material.Neon
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if kind == "hq" then 90 else 64, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, if kind == "hq" then -3.2 * S else -2.2 * S)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, 14)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Font = Enum.Font.GothamBold
	text.TextSize = 11
	text.Parent = gui
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(0, 16)
	barBack.Size = UDim2.new(1, 0, 0, 6)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = barBack
	gui.Parent = anchor
	return { id = id, kind = kind, side = 0, x = x, y = y, anchor = anchor, ring = ring, bar = bar, barBack = barBack, text = text, seen = 0 }
end

function StructureRenderer.start()
	folder = Instance.new("Folder")
	folder.Name = "WarFrontStructures"
	folder.Parent = workspace
end

-- structures: { id, kind, side, x, y, hp, maxHp, capSide, capProgress, store }
function StructureRenderer.apply(tick: number, structures: { any })
	if tick <= lastTick then
		return
	end
	lastTick = tick
	for _, st in structures do
		local id, kind, side, x, y, hp, maxHp, capSide, capProgress, store = table.unpack(st)
		local v = views[id]
		if not v then
			v = create(id, kind, x, y)
			views[id] = v
		end
		v.side, v.seen = side, tick
		if kind == "hq" then
			local frac = math.clamp(hp / maxHp, 0, 1)
			v.text.Text = `HQ {math.floor(hp)}/{maxHp}`
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
				v.text.Text = if side == 0 then "capturing" else "taking over"
			else
				v.barBack.Visible = false
				v.text.Text = if side == 0 then "" else `oil {math.floor(store)}`
			end
		end
	end
	for id, v in views do
		if v.seen ~= tick then
			if v.kind == "hq" then
				v.text.Text = "HQ DESTROYED"
				v.bar.Size = UDim2.fromScale(0, 1)
				part(Vector3.new(5 * S, 2.4, 5 * S), CFrame.new(World.toWorld(v.x, v.y, 1.1)), Color3.fromRGB(30, 30, 30), 0)
			end
			views[id] = nil
		end
	end
end

-- For right-click targeting: structures the given side could attack.
function StructureRenderer.each(): { [number]: View }
	return views
end

return StructureRenderer
