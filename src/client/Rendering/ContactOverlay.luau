--!strict
--[[
	ContactOverlay: radar contacts from the server's state (2 Hz): enemy units inside your radar
	sweeps (radar buildings, secured radio towns) that you can't see. Each is a small glowing dot,
	bigger and redder for a medium or heavy group. PLACEHOLDER look (TEMP-003).
]]
local World = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.World)

local ContactOverlay = {}

local S = World.STUDS_PER_CELL
local folder: Folder
local pool: { Part } = {}
local SIZE = { [1] = 0.9, [2] = 1.3, [3] = 1.8 }
local COLOR = { [1] = Color3.fromRGB(255, 210, 90), [2] = Color3.fromRGB(255, 150, 60), [3] = Color3.fromRGB(255, 70, 50) }

function ContactOverlay.start()
	folder = Instance.new("Folder")
	folder.Name = "WarFrontContacts"
	folder.Parent = workspace
end

-- flat list: x, y, strength, x, y, strength, ...
function ContactOverlay.apply(list: { number })
	local n = 0
	for i = 1, #list - 2, 3 do
		n += 1
		local p = pool[n]
		if not p then
			p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Shape = Enum.PartType.Cylinder
			p.Material = Enum.Material.Neon
			p.Parent = folder
			pool[n] = p
		end
		local band = list[i + 2]
		local d = (SIZE[band] or 0.9) * S
		p.Size = Vector3.new(0.1, d, d)
		p.Color = COLOR[band] or COLOR[1]
		p.Transparency = 0.25
		p.CFrame = CFrame.new(World.toWorld(list[i], list[i + 1], 0.35)) * CFrame.Angles(0, 0, math.rad(90))
	end
	for i = n + 1, #pool do
		pool[i].Transparency = 1
	end
end

return ContactOverlay
