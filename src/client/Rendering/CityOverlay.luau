--!strict
--[[
	CityOverlay: who holds each settlement, from the server's state (2 Hz, sent when it changes).
	A ring in the owner's colour round each settlement (none while neutral), and a tag with its name and
	capture progress or, when enemies are wearing a held one down, its hold. A held town, city or
	capital paints territory you can build in (shown by the build ghost). PLACEHOLDER look (TEMP-003).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Rules = require(Shared.Config.Rules)

local CityOverlay = {}

local S = World.STUDS_PER_CELL
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }

type View = { ring: Part, text: TextLabel, name: string }
local views: { [number]: View } = {}

function CityOverlay.start(settlements: { any })
	local rules = Rules.new(require(Shared:WaitForChild("GameData").RulesMatch) :: any)
	local folder = Instance.new("Folder")
	folder.Name = "WarFrontCities"
	folder.Parent = workspace
	for i, s in settlements do
		local key = `settlements.{s.kind}Radius`
		local r = if rules:has(key) then rules:number(key) else 1.4
		local x, y = math.floor(s.x) + 0.5, math.floor(s.y) + 0.5
		local ring = Instance.new("Part")
		ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Size = Vector3.new(0.1, r * 2 * S + 0.8, r * 2 * S + 0.8)
		ring.CFrame = CFrame.new(World.toWorld(x, y, 0.25)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 1
		ring.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 14)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2, r * S * 0.4)
		gui.AlwaysOnTop = true
		gui.Adornee = ring
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.4
		text.Font = Enum.Font.GothamBold
		text.TextSize = 10
		text.Text = ""
		text.Parent = gui
		gui.Parent = ring
		views[i] = { ring = ring, text = text, name = s.name or "" }
	end
end

-- cities: { { id, owner, captureSide, captureProgress, hold, garrison?, garrisonFull? }, ... }
function CityOverlay.apply(cities: { any })
	for _, c in cities do
		local id, owner, capSide, capProgress, hold, men, full = c[1], c[2], c[3], c[4], c[5], c[6], c[7]
		local v = views[id]
		if v then
			v.ring.Transparency = if owner > 0 then 0.55 else 1
			v.ring.Color = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			if owner <= 0 and capSide > 0 and capProgress > 0 then
				v.text.Text = `capturing {math.floor(capProgress * 100)}%`
				v.text.TextColor3 = SIDE_COLOR[capSide] or Color3.new(1, 1, 1)
			elseif owner > 0 and hold < 1 then
				v.text.Text = `hold {math.floor(hold * 100)}%`
				v.text.TextColor3 = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			elseif owner > 0 and men and full then
				-- garrison: occupied (0), fortified, secured (full)
				v.text.Text = if men >= full then `secured {men}/{full}` elseif men > 0 then `fortified {men}/{full}` else `occupied 0/{full}`
				v.text.TextColor3 = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			else
				v.text.Text = ""
			end
		end
	end
end

return CityOverlay
