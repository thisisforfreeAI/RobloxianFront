--!strict
--[[
	AirOverlay: transport planes for airfield drops and the capital's paratroopers, from the server's
	state (2 Hz). Each flight comes with its start point, heading, speed and stick times, so the client
	flies it on every frame from its own clock. A plane is a flat wedge at drop.planeHeight (4.5
	cells, the game's value); each stick is a small canopy falling from the plane to the ground over
	the chute time. Own planes are blue, enemy planes red. Recon drones are small crosses at 3 cells up, own artillery-base flares glowing balls,
	SAM missiles short white darts, both placed where the server last saw them. PLACEHOLDER look (TEMP-003).
]]
local RunService = game:GetService("RunService")
local World = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.World)

local AirOverlay = {}

local S = World.STUDS_PER_CELL
local PLANE_HEIGHT = 4.5 * S
local folder: Folder
local mySide = 0
local flights: { any } = {}
local serverTime, receivedAt = 0, 0
local planes: { [number]: Part } = {}
local chutes: { [string]: Part } = {}

local function part(color: Color3, size: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.Parent = folder
	return p
end

function AirOverlay.start(side: number)
	mySide = side
	folder = Instance.new("Folder")
	folder.Name = "WarFrontAir"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(function()
		local t = serverTime + (os.clock() - receivedAt)
		local livePlanes, liveChutes = {}, {}
		for _, f in flights do
			local own = f.side == mySide
			if t <= f.goneT then
				local p = planes[f.id]
				if not p then
					p = part(if own then Color3.fromRGB(120, 170, 255) else Color3.fromRGB(255, 110, 100), Vector3.new(2.4 * S, 0.3 * S, 1.6 * S))
					planes[f.id] = p
				end
				local d = math.max(0, t - f.startT) * f.speed
				local x, y = f.fromX + math.cos(f.heading) * d, f.fromY + math.sin(f.heading) * d
				local pos = World.toWorld(x, y, PLANE_HEIGHT)
				local ahead = World.toWorld(x + math.cos(f.heading), y + math.sin(f.heading), PLANE_HEIGHT)
				p.CFrame = CFrame.lookAt(pos, ahead) * CFrame.Angles(0, math.pi / 2, 0)
				livePlanes[f.id] = true
			end
			for i, st in f.sticks do
				local x, y, outT, landT = st[1], st[2], st[3], st[4]
				if t >= outT and t < landT then
					local key = `{f.id}:{i}`
					local c = chutes[key]
					if not c then
						c = part(if own then Color3.fromRGB(235, 235, 220) else Color3.fromRGB(230, 190, 180), Vector3.new(0.9 * S, 0.25 * S, 0.9 * S))
						chutes[key] = c
					end
					local k = (t - outT) / math.max(0.01, landT - outT)
					c.CFrame = CFrame.new(World.toWorld(x, y, PLANE_HEIGHT * (1 - k) + 0.6 * S))
					liveChutes[key] = true
				end
			end
		end
		for id, p in planes do
			if not livePlanes[id] then
				p:Destroy()
				planes[id] = nil
			end
		end
		for key, c in chutes do
			if not liveChutes[key] then
				c:Destroy()
				chutes[key] = nil
			end
		end
	end)
end

local dronePool: { Part } = {}
local missilePool: { Part } = {}
local function pooled(pool: { Part }, n: number, color: Color3, size: Vector3): Part
	local p = pool[n]
	if not p then
		p = part(color, size)
		pool[n] = p
	end
	p.Color = color
	p.Transparency = 0
	return p
end

-- drones: { x, y, side, phase }; missiles: { x, y, heading, side }
function AirOverlay.applyDrones(drones: { any }, missiles: { any })
	for i, d in drones do
		local p = pooled(dronePool, i, if d[3] == mySide then Color3.fromRGB(140, 200, 255) else Color3.fromRGB(255, 140, 120), Vector3.new(1.1 * S, 0.15 * S, 1.1 * S))
		p.CFrame = CFrame.new(World.toWorld(d[1], d[2], 3 * S)) * CFrame.Angles(0, math.rad(45), 0)
	end
	for i = #drones + 1, #dronePool do
		dronePool[i].Transparency = 1
	end
	for i, m in missiles do
		local p = pooled(missilePool, i, Color3.fromRGB(245, 245, 245), Vector3.new(0.8 * S, 0.12 * S, 0.12 * S))
		p.Material = Enum.Material.Neon
		p.CFrame = CFrame.new(World.toWorld(m[1], m[2], 2.5 * S)) * CFrame.Angles(0, -m[3], 0)
	end
	for i = #missiles + 1, #missilePool do
		missilePool[i].Transparency = 1
	end
end

local flarePool: { Part } = {}
-- own flares: { x, y, burstAt, until, radius }; a bright ball 4 cells up while it burns (before the
-- burst it is still a shell in the air and is not drawn)
function AirOverlay.applyFlares(list: { any }, time: number)
	local n = 0
	for _, f in list do
		if time >= f[3] and time < f[4] then
			n += 1
			local p = pooled(flarePool, n, Color3.fromRGB(255, 236, 160), Vector3.new(0.6 * S, 0.6 * S, 0.6 * S))
			p.Shape = Enum.PartType.Ball
			p.Material = Enum.Material.Neon
			p.CFrame = CFrame.new(World.toWorld(f[1], f[2], 4 * S))
			if not p:FindFirstChildOfClass("PointLight") then
				local l = Instance.new("PointLight")
				l.Range = 60
				l.Brightness = 2
				l.Color = Color3.fromRGB(255, 236, 160)
				l.Parent = p
			end
			p:FindFirstChildOfClass("PointLight").Enabled = true
		end
	end
	for i = n + 1, #flarePool do
		flarePool[i].Transparency = 1
		local l = flarePool[i]:FindFirstChildOfClass("PointLight")
		if l then
			l.Enabled = false
		end
	end
end

function AirOverlay.apply(list: { any }, time: number)
	flights = list
	serverTime, receivedAt = time, os.clock()
end

return AirOverlay
