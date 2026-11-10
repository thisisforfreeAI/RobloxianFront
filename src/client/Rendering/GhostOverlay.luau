--!strict
--[[
	GhostOverlay: enemy units you saw recently but can't see now, at the spot you last saw them (the
	game's unit intel markers, kept up to intel.unitIntelSec). A faint disc in the owner's colour with
	the unit's name, fading with age. PLACEHOLDER look (TEMP-003).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)

local GhostOverlay = {}

local S = World.STUDS_PER_CELL
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }
local folder: Folder
local views: { [number]: { part: Part, text: TextLabel } } = {}
local keep = 45

function GhostOverlay.start(unitIntelSec: number?)
	keep = unitIntelSec or 45
	folder = Instance.new("Folder")
	folder.Name = "WarFrontGhosts"
	folder.Parent = workspace
end

-- rows: { id, kind, side, x, y, age }
function GhostOverlay.apply(rows: { { any } })
	local seen = {}
	for _, row in rows do
		local id, kind, side, x, y, age = row[1], row[2], row[3], row[4], row[5], row[6]
		seen[id] = true
		local v = views[id]
		if not v then
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Shape = Enum.PartType.Cylinder
			p.Material = Enum.Material.SmoothPlastic
			p.Size = Vector3.new(0.1, 1.2 * S, 1.2 * S)
			p.Parent = folder
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(70, 12)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
			gui.Adornee = p
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextColor3 = Color3.new(1, 1, 1)
			text.TextStrokeTransparency = 0.6
			text.Font = Enum.Font.Gotham
			text.TextSize = 9
			text.Parent = gui
			gui.Parent = p
			v = { part = p, text = text }
			views[id] = v
		end
		v.part.Color = SIDE_COLOR[side :: number] or Color3.new(0.6, 0.6, 0.6)
		v.part.CFrame = CFrame.new(World.toWorld(x :: number, y :: number, 0.3)) * CFrame.Angles(0, 0, math.rad(90))
		local fade = math.clamp((age :: number) / keep, 0, 1)
		v.part.Transparency = 0.55 + 0.4 * fade
		v.text.Text = `{kind}?`
		v.text.TextTransparency = 0.3 + 0.6 * fade
	end
	for id, v in views do
		if not seen[id] then
			v.part:Destroy()
			views[id] = nil
		end
	end
end

return GhostOverlay
