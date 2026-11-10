--!strict
--[[
	AdminPanel: the owner's test panel (time of day, weather, oil). Not part of WarFront; a development
	tool for this port. Shown only when the server says this player is an admin (in Studio, or the
	place's owner); the server checks every command again (server/Match/Admin.luau).

	Open and close it with the Admin button on the right or the F2 key.
	Clock: the game's 480 s day shown on a 24 h clock with 06:00 at phase 0 (the end of dawn), so night
	falls from about 20:50, is full from about 22:50, and dawn breaks from about 04:50. The clock face is
	this port's choice; the phases are the game's.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local AdminPanel = {}

local PRESETS = { { "Dawn", 5 }, { "Morning", 8 }, { "Noon", 12 }, { "Evening", 18 }, { "Dusk", 21 }, { "Midnight", 0 } }
local WEATHERS = { { "Clear", "clear" }, { "Fog", "fog" }, { "Rain", "downpour" }, { "Storm", "storm" }, { "Sandstorm", "sandstorm" } }

local send: (any) -> ()
local root: ScreenGui
local panel: Frame
local toggle: TextButton
local clockLabel: TextLabel
local weatherLabel: TextLabel
local freezeButton: TextButton
local oilBox: TextBox
local isAdmin = false
local phase = 0.25
local frozen = false

local function phaseOfHour(h: number): number
	return ((h - 6) / 24) % 1
end

local function hourOfPhase(p: number): number
	return (6 + p * 24) % 24
end

local function button(parent: Instance, text: string, x: number, y: number, w: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 22)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = Color3.fromRGB(52, 58, 66)
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(235, 235, 235)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = b
	b.Activated:Connect(onClick)
	return b
end

local function label(parent: Instance, text: string, y: number, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, 18)
	l.Position = UDim2.fromOffset(8, y)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = if bold then Color3.fromRGB(255, 225, 140) else Color3.fromRGB(220, 220, 220)
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = 12
	l.Text = text
	l.Parent = parent
	return l
end

local function setTime(p: number)
	send({ kind = "admin", op = "time", phase = p % 1, freeze = frozen })
end

local function setOil(add: boolean, amount: number?)
	local n = amount or tonumber(oilBox.Text)
	if not n then
		oilBox.Text = ""
		oilBox.PlaceholderText = "type a number"
		return
	end
	send({ kind = "admin", op = "oil", amount = n, add = add })
end

function AdminPanel.start(sendIntent: (any) -> ())
	send = sendIntent
	root = Instance.new("ScreenGui")
	root.Name = "AdminPanel"
	root.ResetOnSpawn = false
	root.DisplayOrder = 20
	root.Enabled = false
	root.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	toggle = Instance.new("TextButton")
	toggle.Size = UDim2.fromOffset(60, 24)
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -8, 0.32, 0)
	toggle.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
	toggle.BorderSizePixel = 0
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 12
	toggle.Text = "Admin"
	toggle.Parent = root

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(300, 262)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -8, 0.32, 30)
	panel.BackgroundColor3 = Color3.fromRGB(24, 27, 32)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = panel

	label(panel, "Admin panel (testing)", 6, true)
	clockLabel = label(panel, "Time --:--", 28)
	for i, p in PRESETS do
		local col, row = (i - 1) % 3, (i - 1) // 3
		button(panel, p[1], 8 + col * 96, 48 + row * 26, 90, function()
			setTime(phaseOfHour(p[2]))
		end)
	end
	button(panel, "-1 h", 8, 102, 60, function()
		setTime(phase - 1 / 24)
	end)
	button(panel, "+1 h", 72, 102, 60, function()
		setTime(phase + 1 / 24)
	end)
	freezeButton = button(panel, "Freeze time: off", 136, 102, 156, function()
		frozen = not frozen
		freezeButton.Text = if frozen then "Freeze time: on" else "Freeze time: off"
		setTime(phase)
	end)

	weatherLabel = label(panel, "Weather: clear", 132)
	for i, w in WEATHERS do
		local col, row = (i - 1) % 3, (i - 1) // 3
		button(panel, w[1], 8 + col * 96, 152 + row * 26, 90, function()
			send({ kind = "admin", op = "weather", weather = w[2] })
		end)
	end

	label(panel, "Oil", 206)
	oilBox = Instance.new("TextBox")
	oilBox.Size = UDim2.fromOffset(80, 22)
	oilBox.Position = UDim2.fromOffset(8, 228)
	oilBox.BackgroundColor3 = Color3.fromRGB(40, 44, 50)
	oilBox.BorderSizePixel = 0
	oilBox.TextColor3 = Color3.new(1, 1, 1)
	oilBox.PlaceholderText = "amount"
	oilBox.Font = Enum.Font.Gotham
	oilBox.TextSize = 12
	oilBox.Text = ""
	oilBox.ClearTextOnFocus = false
	oilBox.Parent = panel
	button(panel, "Set", 92, 228, 44, function()
		setOil(false)
	end)
	button(panel, "+1000", 140, 228, 72, function()
		setOil(true, 1000)
	end)
	button(panel, "+10000", 216, 228, 76, function()
		setOil(true, 10000)
	end)

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and isAdmin and input.KeyCode == Enum.KeyCode.F2 then
			panel.Visible = not panel.Visible
		end
	end)
end

-- state from the server: admin (show the panel at all), day { phase, night }, weather
function AdminPanel.update(state: { [string]: any })
	if not root then
		return
	end
	if state.admin ~= nil and state.admin ~= isAdmin then
		isAdmin = state.admin == true
		root.Enabled = isAdmin
	end
	if not isAdmin then
		return
	end
	if state.day then
		phase = state.day[1] or phase
		local h = hourOfPhase(phase)
		local hh, mm = math.floor(h), math.floor((h % 1) * 60)
		clockLabel.Text = string.format("Time %02d:%02d   night %d%%%s", hh, mm, math.floor((state.day[2] or 0) * 100 + 0.5), if frozen then "   (frozen)" else "")
	end
	if state.weather then
		weatherLabel.Text = `Weather: {state.weather} (looks only for now)`
	end
end

return AdminPanel
