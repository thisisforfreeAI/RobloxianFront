--!strict
--[[
	RoadOverlay: road cuts and worn road from the server's state (2 Hz).
	Own sabotage charges show a small tag ("Planting N%", "Charge armed").
	A cut is a dark crater disc over the cut cells with a tag ("Road cut", "Bridge down", and the
	repair progress once engineers work on it). Worn road cells get a dusty tint (three bands from the
	35% wear where traffic starts to slow). PLACEHOLDER look (TEMP-003).
]]
local World = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.World)

local RoadOverlay = {}

local S = World.STUDS_PER_CELL
local folder: Folder
local mapW = 0
type Cut = { part: Part, text: TextLabel, x: number, y: number, r: number }
local cuts: { [number]: Cut } = {}
local wornParts: { [number]: Part } = {}
local wornBand: { [number]: number } = {}
local WORN_ALPHA = { [1] = 0.75, [2] = 0.6, [3] = 0.45 }
local MAX_WORN = 1500 -- keep the part count bounded

function RoadOverlay.start(width: number)
	mapW = width
	folder = Instance.new("Folder")
	folder.Name = "WarFrontRoads"
	folder.Parent = workspace
end

local function flat(): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	return p
end

-- rows: { id, x, y, radius, repair%, bridge(1/0) }
function RoadOverlay.applyCuts(rows: { { number } })
	local seen = {}
	for _, row in rows do
		local id, x, y, r, repair, bridge = row[1], row[2], row[3], row[4], row[5], row[6]
		seen[id] = true
		local c = cuts[id]
		if not c then
			local part = flat()
			part.Shape = Enum.PartType.Cylinder
			part.Color = Color3.fromRGB(45, 35, 28)
			part.Size = Vector3.new(0.12, r * 2 * S, r * 2 * S)
			part.CFrame = CFrame.new(World.toWorld(x, y, 0.2)) * CFrame.Angles(0, 0, math.rad(90))
			part.Parent = folder
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(110, 14)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
			gui.AlwaysOnTop = true
			gui.Adornee = part
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextColor3 = Color3.fromRGB(255, 200, 120)
			text.TextStrokeTransparency = 0.4
			text.Font = Enum.Font.GothamBold
			text.TextSize = 10
			text.Parent = gui
			gui.Parent = part
			c = { part = part, text = text, x = x, y = y, r = r }
			cuts[id] = c
		end
		local name = if bridge == 1 then "Bridge down" else "Road cut"
		c.text.Text = if repair > 0 then `{name} · repair {repair}%` else name
	end
	for id, c in cuts do
		if not seen[id] then
			c.part:Destroy()
			cuts[id] = nil
		end
	end
end

-- own charges: rows { id, x, y, progress%, armed(1/0) }, shown as a small tag on the road
local charges: { [number]: { part: Part, text: TextLabel } } = {}
function RoadOverlay.applyCharges(rows: { { number } })
	local seen = {}
	for _, row in rows do
		local id = row[1]
		seen[id] = true
		local c = charges[id]
		if not c then
			local part = flat()
			part.Transparency = 1
			part.Size = Vector3.new(1, 0.1, 1)
			part.CFrame = CFrame.new(World.toWorld(row[2], row[3], 0.3))
			part.Parent = folder
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(100, 14)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
			gui.AlwaysOnTop = true
			gui.Adornee = part
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextColor3 = Color3.fromRGB(255, 120, 90)
			text.TextStrokeTransparency = 0.4
			text.Font = Enum.Font.GothamBold
			text.TextSize = 10
			text.Parent = gui
			gui.Parent = part
			c = { part = part, text = text }
			charges[id] = c
		end
		c.text.Text = if row[5] == 1 then "Charge armed" else `Planting {row[4]}%`
	end
	for id, c in charges do
		if not seen[id] then
			c.part:Destroy()
			charges[id] = nil
		end
	end
end

-- flat list: cell, band, cell, band, ...
function RoadOverlay.applyWorn(list: { number })
	local now: { [number]: number } = {}
	local count = 0
	for i = 1, #list - 1, 2 do
		if count >= MAX_WORN then
			break
		end
		now[list[i]] = list[i + 1]
		count += 1
	end
	for cell, p in wornParts do
		if not now[cell] then
			p:Destroy()
			wornParts[cell], wornBand[cell] = nil, nil
		end
	end
	for cell, band in now do
		local p = wornParts[cell]
		if not p then
			p = flat()
			p.Color = Color3.fromRGB(150, 130, 95)
			p.Size = Vector3.new(S, 0.06, S)
			p.CFrame = CFrame.new(World.toWorld(cell % mapW + 0.5, cell // mapW + 0.5, 0.12))
			p.Parent = folder
			wornParts[cell] = p
		end
		if wornBand[cell] ~= band then
			wornBand[cell] = band
			p.Transparency = WORN_ALPHA[band] or 0.75
		end
	end
end

-- true when (x, y) lies on a cut (within its radius plus a little) or a worn road cell
function RoadOverlay.repairableAt(x: number, y: number): boolean
	for _, c in cuts do
		if (c.x - x) ^ 2 + (c.y - y) ^ 2 <= (c.r + 1) ^ 2 then
			return true
		end
	end
	local cx, cy = math.floor(x), math.floor(y)
	for dy = -1, 1 do
		for dx = -1, 1 do
			if wornParts[(cy + dy) * mapW + cx + dx] then
				return true
			end
		end
	end
	return false
end

return RoadOverlay
