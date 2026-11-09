--!strict
--[[
	UnitRenderer: draws units from server snapshots and interpolates between them.
	PLACEHOLDER shapes (TEMP-003): a flat body in the side colour plus a nose showing heading.
	Sizes follow WarFront's sprite footprints in cells (units-top atlas "cells" values).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local UnitRenderer = {}

local S = World.STUDS_PER_CELL
local SNAPSHOT_SEC = 0.1 -- server sends 10 snapshots/s
local FOOTPRINT = { infantry = 0.78, at = 0.78, mortar = 0.78, para = 0.78, tank = 1, ifv = 0.95, artillery = 1.4, rocket = 1.3, scout = 0.62, engineer = 0.8, command = 1, demo = 1.2, truck = 0.7 }
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }

export type View = {
	id: number,
	kind: string,
	side: number,
	model: Model,
	body: Part,
	ring: Part,
	bar: Frame,
	barGui: BillboardGui,
	status: TextLabel,
	from: Vector3,
	to: Vector3,
	fromYaw: number,
	toYaw: number,
	t: number,
	seen: number,
}

local views: { [number]: View } = {}
local folder: Folder
local lastTick = 0

local function part(parent: Instance, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function create(id: number, kind: string, side: number): View
	local cells = FOOTPRINT[kind] or 0.8
	local model = Instance.new("Model")
	model.Name = `Unit{id}`
	local color = SIDE_COLOR[side] or Color3.new(0.7, 0.7, 0.7)
	local body = part(model, Vector3.new(cells * S, 0.6, cells * S * 0.6), color)
	local nose = part(model, Vector3.new(cells * S * 0.3, 0.7, cells * S * 0.25), color:Lerp(Color3.new(1, 1, 1), 0.5))
	nose.Name = "Nose"
	local ring = part(model, Vector3.new(0.1, cells * S * 1.5, cells * S * 1.5), Color3.fromRGB(120, 255, 120))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	if kind == "truck" then
		body.Material = Enum.Material.Metal -- trucks: darker, so they read apart from combat units
		body.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	-- health bar, shown only when damaged
	local barGui = Instance.new("BillboardGui")
	barGui.Size = UDim2.fromOffset(28, 4)
	barGui.StudsOffsetWorldSpace = Vector3.new(0, 2, -cells * S * 0.6)
	barGui.AlwaysOnTop = true
	barGui.Enabled = false
	barGui.Adornee = body
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = barGui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(110, 220, 90)
	bar.BorderSizePixel = 0
	bar.Parent = back
	barGui.Parent = body
	-- status tag: RECON (scout deployed), PACKING / SETTING UP (artillery and mortars)
	local tagGui = Instance.new("BillboardGui")
	tagGui.Size = UDim2.fromOffset(70, 12)
	tagGui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, cells * S * 0.7)
	tagGui.AlwaysOnTop = true
	tagGui.Adornee = body
	local status = Instance.new("TextLabel")
	status.Size = UDim2.fromScale(1, 1)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.fromRGB(255, 240, 170)
	status.TextStrokeTransparency = 0.3
	status.Font = Enum.Font.GothamBold
	status.TextSize = 9
	status.Text = ""
	status.Parent = tagGui
	tagGui.Parent = body
	model.PrimaryPart = body
	model.Parent = folder
	return {
		id = id, kind = kind, side = side, model = model, body = body, ring = ring, bar = bar, barGui = barGui, status = status,
		from = Vector3.zero, to = Vector3.zero, fromYaw = 0, toYaw = 0, t = 1, seen = 0,
	}
end

local function place(v: View, pos: Vector3, yaw: number)
	-- Rotating about Y by -heading turns local +X towards (cos h, 0, sin h): east = +X, south = +Z.
	local cf = CFrame.new(pos) * CFrame.Angles(0, -yaw, 0)
	v.body.CFrame = cf
	local nose = v.model:FindFirstChild("Nose") :: Part
	nose.CFrame = cf * CFrame.new(v.body.Size.X / 2, 0.05, 0)
	v.ring.CFrame = CFrame.new(pos - Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

function UnitRenderer.start()
	folder = Instance.new("Folder")
	folder.Name = "WarFrontUnits"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(function(dt)
		for _, v in views do
			v.t = math.min(1, v.t + dt / SNAPSHOT_SEC)
			place(v, v.from:Lerp(v.to, v.t), lerpAngle(v.fromYaw, v.toYaw, v.t))
		end
	end)
end

local STATUS = { [1] = "RECON", [2] = "PACKING", [3] = "SETTING UP", [4] = "INSIDE" }

-- units: { {id, kind, side, x, y, heading, hp, maxHp, status}, ... }
function UnitRenderer.apply(tick: number, units: { any })
	if tick <= lastTick then
		return -- stale or duplicate snapshot
	end
	lastTick = tick
	for _, u in units do
		local id, kind, side, x, y, heading = u[1], u[2], u[3], u[4], u[5], u[6]
		local v = views[id]
		local target = World.toWorld(x, y, 0.4)
		if not v then
			v = create(id, kind, side)
			views[id] = v
			v.from, v.fromYaw = target, heading
		else
			local t = v.t
			v.from = v.from:Lerp(v.to, t)
			v.fromYaw = lerpAngle(v.fromYaw, v.toYaw, t)
		end
		v.to, v.toYaw, v.t, v.seen = target, heading, 0, tick
		local frac = math.clamp((u[7] or 1) / math.max(1, u[8] or u[7] or 1), 0, 1)
		v.barGui.Enabled = frac < 0.999
		v.status.Text = STATUS[u[9] or 0] or ""
		v.bar.Size = UDim2.fromScale(frac, 1)
		v.bar.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(110, 220, 90) elseif frac > 0.25 then Color3.fromRGB(240, 200, 60) else Color3.fromRGB(230, 70, 60)
	end
	for id, v in views do
		if v.seen ~= tick then -- gone from the snapshot (dead, or later hidden by fog)
			v.model:Destroy()
			views[id] = nil
		end
	end
end

function UnitRenderer.each(): { [number]: View }
	return views
end

function UnitRenderer.setSelected(selected: { [number]: boolean })
	for id, v in views do
		v.ring.Transparency = if selected[id] then 0.3 else 1
	end
end

return UnitRenderer
