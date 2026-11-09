--!strict
--[[
	Hud: top bar, oil, the selected producer's training buttons and queue, build buttons, notices and
	the end-of-match banner. PLACEHOLDER visuals (TEMP-003).
	Producer: click one of your buildings (HQ, barracks, factory) to pick it; with none picked the HQ
	trains. Q / E train its first / second unit, B / F place a barracks / factory (PROVISIONAL keys).
	Costs and names come from the match rules; the server checks every order.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Config.Rules)

local Hud = {}

-- what each producer trains in the slice (the game's lists minus units not in the slice)
local TRAINS = {
	hq = { "infantry", "engineer" },
	barracks = { "infantry", "at" },
	factory = { "tank", "ifv" },
}
local PRODUCER_NAME = { hq = "HQ", barracks = "Barracks", factory = "War Factory" }

local rules: any
local oilLabel: TextLabel
local queueLabel: TextLabel
local trainButtons: { TextButton } = {}
local notice: TextLabel
local banner: TextLabel
local noticeUntil = 0
local selected: { id: number?, kind: string } = { id = nil, kind = "hq" }
local lastProducers: { any } = {}
local actions: { produce: (string, number?) -> (), build: (string) -> () }

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

local function button(parent: Instance, pos: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size, b.Position = UDim2.fromOffset(190, 30), pos
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.Parent = parent
	return b
end

local function unitName(item: string): string
	return if rules:has(`units.{item}.name`) then rules:text(`units.{item}.name`) else item
end

local function refreshQueue()
	local entry = nil
	for _, p in lastProducers do
		if (selected.id and p.id == selected.id) or (not selected.id and p.kind == "hq") then
			entry = p
		end
	end
	local name = PRODUCER_NAME[selected.kind] or selected.kind
	if not entry then
		queueLabel.Text = `{name}: gone`
	elseif (entry.built or 1) < 1 then
		queueLabel.Text = `{name}: building {math.floor((entry.built or 0) * 100)}%`
	elseif entry.left then
		queueLabel.Text = `{name} queue {entry.queue}/6 · next {math.ceil(entry.left)} s`
	else
		queueLabel.Text = `{name} queue {entry.queue}/6`
	end
end

local function refreshButtons()
	local list = TRAINS[selected.kind] or {}
	for i, b in trainButtons do
		local item = list[i]
		b.Visible = item ~= nil
		if item then
			b.Text = `{unitName(item)} ({rules:number(`units.{item}.cost`)}) [{if i == 1 then "Q" else "E"}]`
		end
	end
	refreshQueue()
end

local function train(i: number)
	local item = (TRAINS[selected.kind] or {})[i]
	if item then
		actions.produce(item, selected.id)
	end
end

function Hud.start(info: { [string]: any }, acts: { produce: (string, number?) -> (), build: (string) -> () })
	actions = acts
	rules = Rules.new(require(Shared:WaitForChild("GameData").RulesMatch) :: any)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontHud"
	gui.ResetOnSpawn = false
	local sideText = if info.side == 1 then "Side 1 (blue)" elseif info.side == 2 then "Side 2 (red)" else "Spectator"
	local bar = label(gui, UDim2.new(1, 0, 0, 28), UDim2.new(), 14)
	bar.Text = `RobloxianFront · {info.map} · {sideText} · WASD pan · wheel zoom · click/drag select · right-click move or attack · X stop · click a building to train there · Q/E train · B/F build · PLACEHOLDER ART`

	oilLabel = label(gui, UDim2.fromOffset(230, 34), UDim2.fromOffset(10, 38), 18)
	oilLabel.Text = "Oil —"
	oilLabel.TextColor3 = Color3.fromRGB(250, 210, 90)
	queueLabel = label(gui, UDim2.fromOffset(230, 22), UDim2.fromOffset(10, 74), 13)
	queueLabel.Text = "HQ queue 0/6"
	for i = 1, 2 do
		local b = button(gui, UDim2.fromOffset(10, 100 + (i - 1) * 34), Color3.fromRGB(50, 90, 60))
		b.Activated:Connect(function()
			train(i)
		end)
		trainButtons[i] = b
	end
	local function buildButton(kind: string, key: string, y: number)
		local b = button(gui, UDim2.fromOffset(10, y), Color3.fromRGB(80, 70, 45))
		b.Text = `{rules:text(`structures.{kind}.name`)} ({rules:number(`structures.{kind}.cost`)}) [{key}]`
		b.Activated:Connect(function()
			actions.build(kind)
		end)
	end
	buildButton("barracks", "B", 178)
	buildButton("factory", "F", 212)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			train(1)
		elseif input.KeyCode == Enum.KeyCode.E then
			train(2)
		end
	end)
	notice = label(gui, UDim2.fromOffset(260, 26), UDim2.new(0.5, -130, 0, 40), 14)
	notice.Visible = false
	banner = label(gui, UDim2.fromOffset(420, 70), UDim2.new(0.5, -210, 0.4, -35), 30)
	banner.Visible = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	refreshButtons()
end

-- Pick the producer the training buttons act on (nil = the HQ).
function Hud.selectProducer(id: number?, kind: string?)
	selected = { id = id, kind = if id then kind or "hq" else "hq" }
	refreshButtons()
end

-- state from the server (2 Hz): { oil, trucksIdle, queue, queueLeft, producers, territory, lost, winner, notice }
function Hud.update(state: { [string]: any }, mySide: number)
	if state.oil then
		oilLabel.Text = if state.trucksIdle then `Oil {state.oil} · trucks idle {state.trucksIdle}` else `Oil {state.oil}`
	end
	if state.producers then
		lastProducers = state.producers
		refreshQueue()
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
