--!strict
--[[
	RigCard: the panel that opens when you click one of your oil rigs, after the game's RigCard. It
	shows the rig's tank, its pump (most and now, oil a minute), its trucks and about how much oil
	they bring home a minute (the game's Yke; flagged when under 85% of what it pumps), where they haul
	to and the trip time, and damage. Buttons: send an idle truck (or buy one), release a truck, the
	second pump and the bigger tank (each once, "Done" after), and reroute (the next way on offer;
	waits out the reroute lock). Esc or the X closes it; clicking elsewhere on the map closes it too.
	The server re-checks every button. PLACEHOLDER look.

	RigCard.view(rig, oil, idle, prices) is plain data (no Roblox), so the tests can check it.
]]

local RigCard = {}

export type RigRow = { [string]: any }
export type Button = { key: string, label: string, off: boolean, tip: string }
export type View = { title: string, lines: { string }, warn: { [number]: boolean }, buttons: { Button } }

local function clock(sec: number): string
	local s = math.max(0, math.ceil(sec))
	return string.format("%02d:%02d", s // 60, s % 60)
end

-- prices: { truck, pump, tank, pumpMult, tankMult, baseTank }
function RigCard.view(r: RigRow, oil: number, idle: number, prices: { [string]: number }): View
	local lines, warn = {}, {}
	local function add(text: string, bad: boolean?)
		table.insert(lines, text)
		if bad then
			warn[#lines] = true
		end
	end
	local title = if r.name ~= "" then `OIL FIELD · {r.name}` else "OIL FIELD"
	if (r.rich or 1) > 1 then
		title ..= ` · Rich field x{r.rich}`
	end
	if r.wrecked then
		add("DESTROYED: it pumps nothing until engineers repair it.", true)
	elseif r.hp and r.maxHp and r.hp < r.maxHp then
		add(`DAMAGED {math.floor(r.hp / r.maxHp * 100 + 0.5)}%: bombs wreck it, engineers repair it.`, true)
	end
	if r.tank >= r.tankCap - 0.5 then
		add("Tank full, needs trucks", true)
	else
		add(`Tank {r.tank} / {r.tankCap}`)
	end
	add(`Pump {r.pumpMax} oil/min · now {r.pumpNow}`)
	add(`Trucks {r.trucks} / {r.perRig}`)
	if r.trucks == 0 then
		add("No truck: this rig earns nothing", true)
	elseif not r.connected or r.trip == nil then
		add("No road home: trucks can't reach the HQ", true)
	else
		add(`Hauls about {r.haul} of {r.pumpMax} oil/min`, r.haul < r.pumpMax * 0.85)
	end
	if r.cut then
		add("Route cut: no trucks leave. Reroute it.", true)
	end
	local dest = if r.refinery then `To the refinery in {r.refinery}` else "To the HQ"
	add(if r.trip then `{dest} · {clock(r.trip)} a way` else dest)
	if r.contested then
		add("Fought over: drive them off it.", true)
	end
	if idle > 0 then
		add(`Idle at HQ: {idle}`)
	end

	local buttons: { Button } = {}
	local full = r.trucks >= r.perRig
	if idle > 0 then
		table.insert(buttons, { key = "truck", label = "Send idle truck (free)", off = full or r.wrecked, tip = if full then "This rig has all the trucks it can work." else "Idle at the HQ, goes out free" })
	else
		local poor = oil < prices.truck
		table.insert(buttons, { key = "truck", label = `Buy oil truck ({prices.truck})`, off = full or poor or r.wrecked,
			tip = if full then "This rig has all the trucks it can work." elseif poor then "Not enough oil" else "Carries a load of oil a trip" })
	end
	table.insert(buttons, { key = "release", label = "Release truck", off = not r.canRelease, tip = if r.canRelease then "Sends one truck home to stand idle" else "This rig has no truck to release." })
	local function upgrade(key: string, done: boolean, name: string, cost: number, hint: string)
		if done then
			table.insert(buttons, { key = key, label = `{name}: Done`, off = true, tip = "Already bought for this rig." })
		else
			table.insert(buttons, { key = key, label = `{name} ({cost})`, off = oil < cost, tip = if oil < cost then "Not enough oil" else hint })
		end
	end
	upgrade("pump", r.pump, "Second pump", prices.pump, `Pumps {math.floor((prices.pumpMult - 1) * 100 + 0.5)}% faster`)
	upgrade("tank", r.bigTank, "Bigger tank", prices.tank, `Tank holds {math.floor(prices.baseTank * prices.tankMult + 0.5)}`)
	local waiting = (r.readyIn or 0) > 0
	table.insert(buttons, { key = "reroute", label = if waiting then `Reroute (ready in {clock(r.readyIn)})` else "Reroute: next way", off = waiting,
		tip = if waiting then "The route can't be changed yet" else "The trucks take the next way on offer: each route to the HQ, then each refinery" })
	return { title = title, lines = lines, warn = warn, buttons = buttons }
end

-- the panel (Roblox only). send(intent) goes to the server; prices as for view.
function RigCard.start(send: (any) -> (), prices: { [string]: number })
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontRigCard"
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(330, 360)
	frame.Position = UDim2.new(1, -340, 1, -370)
	frame.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	local function text(size: UDim2, pos: UDim2, ts: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Size, l.Position = size, pos
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(235, 235, 235)
		l.Font = Enum.Font.GothamMedium
		l.TextSize = ts
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = frame
		return l
	end
	local title = text(UDim2.new(1, -40, 0, 26), UDim2.fromOffset(10, 4), 15)
	local close = Instance.new("TextButton")
	close.Size, close.Position = UDim2.fromOffset(26, 26), UDim2.new(1, -30, 0, 4)
	close.Text = "X"
	close.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Parent = frame
	local lineLabels: { TextLabel } = {}
	for i = 1, 9 do
		lineLabels[i] = text(UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 32 + (i - 1) * 19), 13)
	end
	local tip = text(UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 1, -22), 12)
	tip.TextColor3 = Color3.fromRGB(180, 180, 180)
	local buttons: { TextButton } = {}
	local current: { Button } = {}
	local openId: number? = nil
	local function act(i: number)
		local b = current[i]
		if not b or not openId then
			return
		end
		if b.off then
			tip.Text = b.tip
			return
		end
		if b.key == "truck" then
			send({ kind = "truck", rigId = openId })
		elseif b.key == "release" then
			send({ kind = "truck", rigId = openId, release = true })
		elseif b.key == "reroute" then
			send({ kind = "truck", rigId = openId, reroute = true })
		else
			send({ kind = "upgradeRig", rigId = openId, upgrade = b.key })
		end
	end
	for i = 1, 5 do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -20, 0, 26)
		b.Position = UDim2.fromOffset(10, 32 + 9 * 19 + 6 + (i - 1) * 29)
		b.BackgroundColor3 = Color3.fromRGB(55, 80, 60)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 13
		b.Parent = frame
		b.Activated:Connect(function()
			act(i)
		end)
		b.MouseEnter:Connect(function()
			tip.Text = if current[i] then current[i].tip else ""
		end)
		buttons[i] = b
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local last: { rigs: { RigRow }, oil: number, idle: number } = { rigs = {}, oil = 0, idle = 0 }
	local function render()
		if not openId then
			frame.Visible = false
			return
		end
		local row = nil
		for _, r in last.rigs do
			if r.id == openId then
				row = r
			end
		end
		if not row then
			-- not ours any more
			openId = nil
			frame.Visible = false
			return
		end
		local v = RigCard.view(row, last.oil, last.idle, prices)
		title.Text = v.title
		for i, l in lineLabels do
			l.Text = v.lines[i] or ""
			l.TextColor3 = if v.warn[i] then Color3.fromRGB(255, 150, 110) else Color3.fromRGB(235, 235, 235)
		end
		current = v.buttons
		for i, b in buttons do
			local d = v.buttons[i]
			b.Visible = d ~= nil
			if d then
				b.Text = d.label
				b.AutoButtonColor = not d.off
				b.BackgroundColor3 = if d.off then Color3.fromRGB(60, 60, 60) else Color3.fromRGB(55, 80, 60)
			end
		end
		frame.Visible = true
	end
	close.Activated:Connect(function()
		openId = nil
		render()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then
			openId = nil
			render()
		end
	end)
	local api = {}
	function api.open(id: number?)
		openId = id
		tip.Text = ""
		render()
	end
	function api.isOpen(): boolean
		return openId ~= nil
	end
	function api.update(rigs: { RigRow }?, oil: number?, idle: number?)
		if rigs then
			last.rigs = rigs
		end
		if oil then
			last.oil = oil
		end
		if idle then
			last.idle = idle
		end
		render()
	end
	return api
end

return RigCard
