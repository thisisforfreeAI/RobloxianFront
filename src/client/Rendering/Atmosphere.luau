--!strict
--[[
	Atmosphere: night and weather drawn over the battlefield.

	Night: the server sends the sim's night amount (0 day .. 1 full night, the game's 480 s day); a
	ColorCorrectionEffect in Lighting darkens and cools the 3D view by it. APPROX: the game dims its
	own canvas by its nightDim settings; these strengths are picked by eye, not traced.
	Weather: the server's weather ("clear", "fog", "downpour", "storm", "sandstorm") adds a haze and,
	for rain or sand, moving streaks on a ScreenGui under the HUD; storms flash now and then. Visual
	only: the port has no weather rules yet.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Atmosphere = {}

local NIGHT = { brightness = -0.22, contrast = 0.08, saturation = -0.4, tint = Color3.fromRGB(150, 168, 225) }
type Look = { haze: Color3, hazeAlpha: number, streaks: number, streakColor: Color3, fall: Vector2, saturation: number, brightness: number, flash: boolean }
local WEATHER: { [string]: Look } = {
	clear = { haze = Color3.new(1, 1, 1), hazeAlpha = 0, streaks = 0, streakColor = Color3.new(1, 1, 1), fall = Vector2.zero, saturation = 0, brightness = 0, flash = false },
	fog = { haze = Color3.fromRGB(215, 220, 225), hazeAlpha = 0.45, streaks = 0, streakColor = Color3.new(1, 1, 1), fall = Vector2.zero, saturation = -0.25, brightness = 0.02, flash = false },
	downpour = { haze = Color3.fromRGB(120, 135, 155), hazeAlpha = 0.2, streaks = 70, streakColor = Color3.fromRGB(200, 215, 235), fall = Vector2.new(120, 900), saturation = -0.2, brightness = -0.06, flash = false },
	storm = { haze = Color3.fromRGB(70, 80, 100), hazeAlpha = 0.3, streaks = 110, streakColor = Color3.fromRGB(200, 215, 235), fall = Vector2.new(260, 1100), saturation = -0.3, brightness = -0.12, flash = true },
	sandstorm = { haze = Color3.fromRGB(196, 160, 105), hazeAlpha = 0.45, streaks = 80, streakColor = Color3.fromRGB(230, 200, 150), fall = Vector2.new(900, 120), saturation = -0.15, brightness = 0, flash = false },
}

local cc: ColorCorrectionEffect
local haze: Frame
local flashFrame: Frame
local streakHolder: Frame
local streaks: { { frame: Frame, x: number, y: number } } = {}
local look: Look = WEATHER.clear
local night = 0
local nextFlash = 0

local function setStreaks(n: number)
	while #streaks < n do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Parent = streakHolder
		table.insert(streaks, { frame = f, x = math.random(), y = math.random() })
	end
	for i, s in streaks do
		s.frame.Visible = i <= n
	end
end

local function refresh()
	cc.Brightness = NIGHT.brightness * night + look.brightness
	cc.Contrast = NIGHT.contrast * night
	cc.Saturation = NIGHT.saturation * night + look.saturation
	cc.TintColor = Color3.new(1, 1, 1):Lerp(NIGHT.tint, night)
	haze.BackgroundColor3 = look.haze
	haze.BackgroundTransparency = 1 - look.hazeAlpha * (1 - 0.4 * night)
	setStreaks(look.streaks)
	local angle = math.deg(math.atan2(look.fall.X, look.fall.Y))
	local long = look.fall.Magnitude > 0 and math.abs(look.fall.Y) > math.abs(look.fall.X)
	for _, s in streaks do
		s.frame.BackgroundColor3 = look.streakColor
		s.frame.BackgroundTransparency = if long then 0.55 else 0.7
		s.frame.Size = if long then UDim2.fromOffset(1, 16) else UDim2.fromOffset(14, 1)
		s.frame.Rotation = if long then -angle else 0
	end
end

function Atmosphere.start()
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WarFrontAtmosphere"
	cc.Parent = Lighting
	local gui = Instance.new("ScreenGui")
	gui.Name = "Weather"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10 -- under the HUD
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	haze = Instance.new("Frame")
	haze.Size = UDim2.fromScale(1, 1)
	haze.BorderSizePixel = 0
	haze.BackgroundTransparency = 1
	haze.Active = false
	haze.Parent = gui
	streakHolder = Instance.new("Frame")
	streakHolder.Size = UDim2.fromScale(1, 1)
	streakHolder.BackgroundTransparency = 1
	streakHolder.ClipsDescendants = true
	streakHolder.Parent = gui
	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BorderSizePixel = 0
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.Parent = gui
	refresh()
	RunService.RenderStepped:Connect(function(dt)
		if look.streaks > 0 then
			local size = gui.AbsoluteSize
			local vx, vy = look.fall.X / math.max(1, size.X), look.fall.Y / math.max(1, size.Y)
			for i = 1, look.streaks do
				local s = streaks[i]
				s.x = (s.x + vx * dt * (0.8 + (i % 5) * 0.1)) % 1
				s.y = (s.y + vy * dt * (0.8 + (i % 7) * 0.06)) % 1
				s.frame.Position = UDim2.fromScale(s.x, s.y)
			end
		end
		if look.flash then
			local now = os.clock()
			if now >= nextFlash then
				nextFlash = now + 6 + math.random() * 10
				flashFrame.BackgroundTransparency = 0.45
			end
			flashFrame.BackgroundTransparency = math.min(1, flashFrame.BackgroundTransparency + dt * 3)
		elseif flashFrame.BackgroundTransparency < 1 then
			flashFrame.BackgroundTransparency = 1
		end
	end)
end

-- day: { phase, night } from the server; weather: its weather name
function Atmosphere.apply(day: { number }?, weather: string?)
	if not cc then
		return
	end
	local n = if day then day[2] or 0 else night
	local l = if weather and WEATHER[weather] then WEATHER[weather] else look
	if math.abs(n - night) < 0.005 and l == look then
		return
	end
	night, look = n, l
	refresh()
end

return Atmosphere
