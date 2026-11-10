--!strict
--[[
	CityOverlay: who holds each settlement, from the server's state (2 Hz, sent when it changes).
	A ring in the owner's colour round each settlement (none while neutral), and a tag with its name and
	capture progress or, when enemies are wearing a held one down, its hold, its garrison and its trait
	(rail, hospital, factory, radio, airfield; "ON" while held and secured). A held town, city or
	capital paints territory you can build in (shown by the build ghost). PLACEHOLDER look (TEMP-003).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Rules = require(Shared.Config.Rules)

local CityOverlay = {}

local S = World.STUDS_PER_CELL
local SIDE_COLOR = { [1] = Color3.fromRGB(70, 130, 230), [2] = Color3.fromRGB(220, 80, 70) }

type View = { ring: Part, text: TextLabel, name: string, owner: number, x: number, y: number, r: number }
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
		views[i] = { ring = ring, text = text, name = s.name or "", owner = 0, x = x, y = y, r = r }
	end
end

-- trait names as the tag shows them (PLACEHOLDER wording)
local TRAIT_NAME = { rail = "Rail", hospital = "Hospital", factory = "Factory", radio = "Radio", airfield = "Airfield" }

-- cities: { { id, owner, captureSide, captureProgress, hold, garrison, garrisonFull, trait, traitWorks,
--             integrity %, ruined }, ... }
function CityOverlay.apply(cities: { any })
	for _, c in cities do
		local id, owner, capSide, capProgress, hold, men, full = c[1], c[2], c[3], c[4], c[5], c[6], c[7]
		local trait, works = c[8], c[9]
		local integrity, ruined = c[10], c[11]
		local v = views[id]
		if v then
			v.owner = owner
			v.ring.Transparency = 1 -- territory wash and original fort sprites replace the placeholder blue disc
			v.ring.Color = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			if owner <= 0 and capSide > 0 and capProgress > 0 then
				v.text.Text = `capturing {math.floor(capProgress * 100)}%`
				v.text.TextColor3 = SIDE_COLOR[capSide] or Color3.new(1, 1, 1)
			elseif owner > 0 and hold < 1 then
				v.text.Text = `hold {math.floor(hold * 100)}%`
				v.text.TextColor3 = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			elseif owner > 0 and men and full and full > 0 then
				-- garrison: occupied (0), fortified, secured (full)
				v.text.Text = if men >= full then `secured {men}/{full}` elseif men > 0 then `fortified {men}/{full}` else `occupied 0/{full}`
				v.text.TextColor3 = SIDE_COLOR[owner] or Color3.new(1, 1, 1)
			else
				v.text.Text = ""
			end
			-- integrity: damaged (< 70%) / critical (< 30%) / in ruins (-1 = not seen now)
			local band = if ruined == 1 then "In ruins"
				elseif integrity and integrity >= 0 and integrity < 30 then `Critical {integrity}%`
				elseif integrity and integrity >= 0 and integrity < 70 then `Damaged {integrity}%`
				else nil
			if band then
				v.text.Text = if v.text.Text == "" then band else `{v.text.Text} · {band}`
			end
			v.ring.Material = if ruined == 1 then Enum.Material.Slate else Enum.Material.Neon
			-- the trait, marked on when it works (held and secured)
			local tn = trait and TRAIT_NAME[trait]
			if tn then
				local tag = if works == 1 then `{tn} ON` else tn
				v.text.Text = if v.text.Text == "" then tag else `{v.text.Text} · {tag}`
			end
		end
	end
end

-- the settlement of `side` whose ring is under the screen point (nil if none)
function CityOverlay.pick(mouse: Vector2, side: number): number?
	local best, bestDist = nil, math.huge
	for id, v in views do
		if v.owner == side then
			local p, on = workspace.CurrentCamera:WorldToViewportPoint(World.toWorld(v.x, v.y, 0.25))
			local edge = workspace.CurrentCamera:WorldToViewportPoint(World.toWorld(v.x + v.r, v.y, 0.25))
			local rad = math.max(24, (Vector2.new(edge.X, edge.Y) - Vector2.new(p.X, p.Y)).Magnitude)
			local d = (Vector2.new(p.X, p.Y) - mouse).Magnitude
			if on and d <= rad and d < bestDist then
				best, bestDist = id, d
			end
		end
	end
	return best
end

return CityOverlay
