--!strict
-- Hud: top bar, oil and HQ production, notices and the end-of-match banner. PLACEHOLDER visuals (TEMP-003).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Hud = {}

local oilLabel: TextLabel
local queueLabel: TextLabel
local notice: TextLabel
local banner: TextLabel
local noticeUntil = 0

local function label(parent: Instance, size: UDim2, pos: UDim2, textSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Size, t.Position = size, pos
	t.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
	t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.fromRGB(235, 235, 235)
	t.Font = Enum.Font.GothamMedium
	t.TextSize = textSize
	t.BorderSizePixel = 0
	t.Parent = parent
	return t
end

-- produce(): asks the server to train one infantry (the server checks oil and queue).
function Hud.start(info: { [string]: any }, produce: () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontHud"
	gui.ResetOnSpawn = false
	local sideText = if info.side == 1 then "Side 1 (blue)" elseif info.side == 2 then "Side 2 (red)" else "Spectator"
	local bar = label(gui, UDim2.new(1, 0, 0, 28), UDim2.new(), 14)
	bar.Text = `RobloxianFront · {info.map} · {sideText} · WASD pan · wheel zoom · click/drag select · right-click move or attack · X stop · Q train infantry · PLACEHOLDER ART`

	oilLabel = label(gui, UDim2.fromOffset(230, 34), UDim2.fromOffset(10, 38), 18)
	oilLabel.Text = "Oil —"
	oilLabel.TextColor3 = Color3.fromRGB(250, 210, 90)
	queueLabel = label(gui, UDim2.fromOffset(150, 22), UDim2.fromOffset(10, 74), 13)
	queueLabel.Text = "HQ queue 0/6"
	local button = Instance.new("TextButton")
	button.Size, button.Position = UDim2.fromOffset(150, 34), UDim2.fromOffset(10, 100)
	button.BackgroundColor3 = Color3.fromRGB(50, 90, 60)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = "Train infantry (36) [Q]"
	button.Parent = gui
	button.Activated:Connect(produce)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Q then
			produce()
		end
	end)
	notice = label(gui, UDim2.fromOffset(260, 26), UDim2.new(0.5, -130, 0, 40), 14)
	notice.Visible = false
	banner = label(gui, UDim2.fromOffset(420, 70), UDim2.new(0.5, -210, 0.4, -35), 30)
	banner.Visible = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- state from the server (2 Hz): { oil, trucksIdle, queue, queueLeft, lost, winner, notice }
function Hud.update(state: { [string]: any }, mySide: number)
	if state.oil then
		oilLabel.Text = if state.trucksIdle then `Oil {state.oil} · trucks idle {state.trucksIdle}` else `Oil {state.oil}`
	end
	if state.queue then
		queueLabel.Text = if state.queueLeft
			then `HQ queue {state.queue}/6 · next {math.ceil(state.queueLeft)} s`
			else `HQ queue {state.queue}/6`
	end
	if state.notice then
		notice.Text = state.notice
		notice.Visible = true
		noticeUntil = os.clock() + 2.5
		task.delay(2.6, function()
			if os.clock() >= noticeUntil then
				notice.Visible = false
			end
		end)
	end
	if state.winner ~= nil then
		banner.Visible = true
		banner.Text = if state.winner == mySide then "VICTORY" elseif state.winner == 0 then "DRAW" else "DEFEAT"
		banner.TextColor3 = if state.winner == mySide then Color3.fromRGB(120, 230, 120) else Color3.fromRGB(240, 110, 100)
	end
end

return Hud
