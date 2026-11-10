--!strict
--[[
	Hud: top bar, oil, the selected producer's training buttons and queue, build buttons, notices and
	the end-of-match banner. PLACEHOLDER visuals (TEMP-003).
	Producer: click one of your buildings (HQ, barracks, factory) to pick it; with none picked the HQ
	trains. Click one of your towns or cities to train infantry / AT there (forward training; it works
	while the town is secured). Q / E / Z / C train its first to fourth unit, B / F / K / G place a barracks / factory / bunker /
	AT gun, Y a radar (PROVISIONAL keys; K and G are the game's letters for the bunker and AT gun).
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
	barracks = { "infantry", "at", "mortar" },
	factory = { "tank", "ifv", "artillery", "scout", "rocket", "command" },
	town = { "infantry", "at" }, -- cities.forward.trains (a held, secured town or city)
}
-- PROVISIONAL keys for a producer's 1st..4th unit (WarFront's bindings are not confirmed yet)
local TRAIN_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Z, Enum.KeyCode.C, Enum.KeyCode.M, Enum.KeyCode.Six }
local PRODUCER_NAME = { hq = "HQ", barracks = "Barracks", factory = "War Factory", town = "Town" }

local rules: any
local oilLabel: TextLabel
local powersLabel: TextLabel
local dropLabel: TextLabel
local queueLabel: TextLabel
local trainButtons: { TextButton } = {}
local notice: TextLabel
local banner: TextLabel
local noticeUntil = 0
local alertLines: { TextLabel } = {}
local alertFeed: { { text: string, untilAt: number } } = {}
local mineButton: TextButton? = nil
local myArmy = "coalition"
local nvOn = false
local selected: { id: number?, kind: string } = { id = nil, kind = "hq" }
local lastProducers: { any } = {}
local lastForwards: { any } = {}
local actions: { produce: (string, number?) -> (), build: (string) -> (), forward: (string, number) -> () }

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
	local own = `armyUnits.{myArmy}.{item}.name`
	if rules:has(own) then
		return rules:text(own) -- the republic's missile launcher
	end
	return if rules:has(`units.{item}.name`) then rules:text(`units.{item}.name`) else item
end

local function refreshQueue()
	if selected.kind == "town" then
		local f = nil
		for _, p in lastForwards do
			if p.id == selected.id then
				f = p
			end
		end
		if not f then
			queueLabel.Text = "Only your towns and cities can train"
		elseif not f.active then
			queueLabel.Text = `Town queue {f.queue}/6 · needs a full garrison (secured)`
		elseif f.left then
			queueLabel.Text = `Town queue {f.queue}/6 · next {math.ceil(f.left)} s`
		else
			queueLabel.Text = `Town queue {f.queue}/6`
		end
		return
	end
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

local prices: { [string]: number } = {}

-- plain wording for the server's refusal codes (PLACEHOLDER wording; the game's own text is not used)
local NOTICE_TEXT: { [string]: string } = {
	requires = "Needs another finished building first (the War Factory needs a Barracks)",
	oil = "Not enough oil",
	queueFull = "Queue full",
	unitCap = "Unit cap reached",
	outsideBase = "Outside your territory",
	onRoad = "Too close to a road",
	onRig = "Too close to an oil rig",
	nearEnemy = "Too close to the enemy",
	terrain = "Can't build on that ground",
	sealsWay = "Would block the way",
	notSecured = "Needs a full garrison first",
	notHeld = "You don't hold this town",
	notDamaged = "Not damaged",
	noEngineers = "No engineers",
	notWorn = "Nothing to mend there",
	noCut = "That cut is already repaired",
	notRoad = "Not a road",
	alreadyCut = "That road is already cut",
	noSaboteurs = "Select engineers to sabotage",
	garrisonFull = "Garrison full",
	cooldown = "Still cooling down",
	noCapital = "You don't hold the capital",
	noHq = "Needs a finished HQ",
	noLaunchers = "Select rocket artillery",
	kills = "Not enough kills",
	startTaken = "Too close to the enemy's landing",
	notInMode = "Landing already chosen",
	noTruck = "Select a command truck",
	alreadyDeploying = "Already setting up",
	noRoom = "No room for an HQ here",
	notCarrier = "Pick an IFV",
	noRiders = "Only infantry and AT can ride",
	carrierFull = "That IFV is full",
	noCargo = "Nobody aboard",
	rebuildWait = "Not yet: wait after losing the last tower",
	noArtyBase = "You have no artillery base",
	notOperational = "The artillery base isn't working",
	notOwned = "Not yours",
	nothingQueued = "Nothing queued there",
	noNightOps = "You have no night operations tower",
	lineShort = "Too short: drag a longer line for the trench",
	badLine = "Engineers can't dig there",
	noTrench = "No trench there",
	cannotDemolish = "That can't be pulled down (the HQ, or already coming down)",
	tooClose = "Too close for rockets",
	droneOut = "The drone is already out",
	replaceCooldown = "No drone yet: wait for a new one",
	noAirfield = "You hold no airfield town",
	outOfRange = "Out of range",
	noDemo = "Select a bomb truck",
	blocked = "Not possible now",
	locked = "Your army doesn't have that",
	mineShort = "Too short: drag a longer line (at least 40 m of open ground)",
	mineGround = "Mines can't go there",
	minefieldSpent = "A minefield is used up",
}

local function refreshButtons()
	local list = TRAINS[selected.kind] or {}
	for i, b in trainButtons do
		local item = list[i]
		b.Visible = item ~= nil
		if item then
			b.Text = `{unitName(item)} ({prices[item] or rules:number(`units.{item}.cost`)}) [{TRAIN_KEYS[i].Name}]`
		end
	end
	refreshQueue()
end

local function train(i: number)
	local item = (TRAINS[selected.kind] or {})[i]
	if item and selected.kind == "town" and selected.id then
		actions.forward(item, selected.id)
	elseif item then
		actions.produce(item, selected.id)
	end
end

function Hud.start(info: { [string]: any }, acts: { produce: (string, number?) -> (), build: (string) -> (), forward: (string, number) -> () })
	actions = acts
	rules = Rules.new(require(Shared:WaitForChild("GameData").RulesMatch) :: any)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontHud"
	gui.ResetOnSpawn = false
	local sideText = if info.side == 1 then "Side 1 (blue)" elseif info.side == 2 then "Side 2 (red)" else "Spectator"
	local bar = label(gui, UDim2.new(1, 0, 0, 28), UDim2.new(), 14)
	bar.Text = `RobloxianFront · {info.map} · {sideText} · WASD pan · wheel zoom · click/drag select · right-click move or attack · X stop · click a building to train there · Q/E/Z/C/M/6 train · B/F/K/G build · R scouts recon or command truck deploys HQ · H garrison a town · right-click a damaged building with engineers to repair · PLACEHOLDER ART`

	oilLabel = label(gui, UDim2.fromOffset(230, 34), UDim2.fromOffset(10, 38), 18)
	oilLabel.Text = "Oil —"
	oilLabel.TextColor3 = Color3.fromRGB(250, 210, 90)
	queueLabel = label(gui, UDim2.fromOffset(230, 22), UDim2.fromOffset(10, 74), 13)
	queueLabel.Text = "HQ queue 0/6"
	for i = 1, #TRAIN_KEYS do
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
	buildButton("barracks", "B", 318)
	buildButton("factory", "F", 352)
	buildButton("bunker", "K", 386)
	buildButton("atgun", "G", 420)
	buildButton("radar", "Y", 454)
	buildButton("sam", "U", 488)
	do
		local b = button(gui, UDim2.fromOffset(10, 522), Color3.fromRGB(80, 70, 45))
		b.Text = `{rules:text("structures.artybase.name")} ({rules:number("structures.artybase.killCost")} kills) [;]`
		b.Activated:Connect(function()
			actions.build("artybase")
		end)
	end
	buildButton("nightops", "'", 556)
	mineButton = button(gui, UDim2.fromOffset(10, 590), Color3.fromRGB(80, 70, 45))
	mineButton.Text = `{rules:text("structures.minefield.name")} ({rules:number("minefield.oilPerMetre")} oil a metre, drag) [-]`
	mineButton.Visible = false
	mineButton.Activated:Connect(function()
		actions.build("minefield")
	end)
	powersLabel = label(gui, UDim2.fromOffset(300, 70), UDim2.fromOffset(10, 624), 12)
	powersLabel.Text = ""
	dropLabel = label(gui, UDim2.fromOffset(520, 34), UDim2.new(0.5, -260, 0, 40), 16)
	dropLabel.Visible = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local i = table.find(TRAIN_KEYS, input.KeyCode)
		if i then
			train(i)
		end
	end)
	notice = label(gui, UDim2.fromOffset(260, 26), UDim2.new(0.5, -130, 0, 40), 14)
	-- match alerts, newest on top, top right under the bar
	for i = 1, 4 do
		local l = label(gui, UDim2.fromOffset(280, 22), UDim2.new(1, -290, 0, 34 + (i - 1) * 24), 13)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Visible = false
		alertLines[i] = l
	end
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

-- state from the server (2 Hz): { oil, trucksIdle, queue, queueLeft, producers, territory, lost, winner, notice, alerts }
function Hud.update(state: { [string]: any }, mySide: number)
	if state.army then
		myArmy = state.army
	end
	if state.army and mineButton then
		mineButton.Visible = state.army == "republic"
	end
	if state.oil then
		oilLabel.Text = if state.trucksIdle then `Oil {state.oil} · trucks idle {state.trucksIdle}` else `Oil {state.oil}`
	end
	if state.oil then
		local d = state.drop
		dropLabel.Visible = d ~= nil or state.needHq ~= nil
		if not d and state.needHq then
			dropLabel.Text = if state.needHq == "deploying" then "Setting up the HQ: keep the truck still"
				else "No HQ yet: select your command truck and press R to set it up"
		end
		if d then
			dropLabel.Text = if d.phase == "pick"
				then `Pick where to land: click the map · Enter when ready · {d.left} s{if d.warn then " · no road to the rigs there" else ""}{if d.arrival then ` · arriving at {d.arrival}` else ""}`
				else `Planes inbound · down in {d.left} s`
		end
	end
	if state.powers then
		-- the capital's powers and own airfield towns (keys P / J / L; N blows up selected bomb trucks)
		local function show(p: any, name: string, key: string): string?
			if not p or p[1] == "none" or p[1] == "locked" then
				return nil
			end
			return if p[1] == "ready" then `{name} [{key}] ready` else `{name} [{key}] {p[2]} s`
		end
		local parts = {}
		local dr = state.powers.drone
		if dr then
			local text = if dr[1] == "buy" then "Recon drone [O] buy 120" elseif dr[1] == "ready" then "Recon drone [O] ready"
				elseif dr[1] == "out" then "Recon drone out" elseif dr[1] == "refuel" then `Recon drone refuelling {dr[2]} s`
				else `Recon drone: new one in {dr[2]} s`
			table.insert(parts, text)
		end
		table.insert(parts, show(state.powers.para, "Paratroopers", "P"))
		table.insert(parts, show(state.powers.demo, "Bomb truck", "J"))
		local best: number? = nil
		for _, a in state.airfields or {} do
			if a[3] == 1 then
				best = math.min(best or math.huge, a[2])
			end
		end
		if best then
			table.insert(parts, if best <= 0 then "Airfield drop [L] ready" else `Airfield drop [L] {best} s`)
		end
		if state.nv then
			nvOn = state.nv[1] == 1
			table.insert(parts, if state.nv[1] == 1 then "Night vision on [N off]"
				elseif state.nv[3] == 1 then "Night vision switched off [N on]"
				elseif state.nv[2] > 0 then `Night ops tower: new one in {state.nv[2]} s` else "No night vision")
		end
		if state.kills then
			table.insert(parts, `Kills {state.kills}`)
		end
		local ar = state.arty
		if ar and ar[1] >= 0 then
			table.insert(parts, (if ar[1] == 0 then "Barrage [.] ready" else `Barrage [.] {ar[1]} s`)
				.. " · " .. (if ar[2] == 0 then "Flares [,] ready" else `Flares [,] {ar[2]} s`))
		end
		powersLabel.Text = table.concat(parts, "\n")
	end
	if state.prices then
		local changed = false
		for k, v in state.prices do
			if prices[k] ~= v then
				prices[k], changed = v, true
			end
		end
		if changed then
			refreshButtons()
		end
	end
	if state.forwards then
		lastForwards = state.forwards
		if selected.kind == "town" then
			refreshQueue()
		end
	end
	if state.producers then
		lastProducers = state.producers
		refreshQueue()
	end
	if state.notice then
		notice.Text = NOTICE_TEXT[state.notice] or state.notice
		notice.Visible = true
		noticeUntil = os.clock() + 2.5
		task.delay(2.6, function()
			if os.clock() >= noticeUntil then
				notice.Visible = false
			end
		end)
	end
	if state.alerts then
		for _, text in state.alerts do
			table.insert(alertFeed, 1, { text = text, untilAt = os.clock() + 6 })
		end
	end
	local now = os.clock()
	for i = #alertFeed, 1, -1 do
		if alertFeed[i].untilAt < now or i > 4 then
			table.remove(alertFeed, i)
		end
	end
	for i, l in alertLines do
		local a = alertFeed[i]
		l.Visible = a ~= nil
		if a then
			l.Text = "  " .. a.text
		end
	end
	if state.winner ~= nil then
		banner.Visible = true
		banner.Text = if state.winner == mySide then "VICTORY" elseif state.winner == 0 then "DRAW" else "DEFEAT"
		banner.TextColor3 = if state.winner == mySide then Color3.fromRGB(120, 230, 120) else Color3.fromRGB(240, 110, 100)
	end
end

-- night vision is on now (the N key switches it)
function Hud.nightVisionOn(): boolean
	return nvOn
end

return Hud
