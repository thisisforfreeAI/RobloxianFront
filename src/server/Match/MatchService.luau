--!strict
--[[
	MatchService: owns the authoritative match (Shared.Simulation.Sim) and the fixed 20 Hz loop.
	Clients only send intents (Protocol); everything here runs on the server.
	Sides: the first player gets side 1, the second side 2, later players spectate.
	PROVISIONAL: while side 2 has no player, a bot (Shared.Simulation.Bot) plays it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Config.Rules)
local MapCodec = require(Shared.Maps.MapCodec)
local Movement = require(Shared.Simulation.Movement)
local Sim = require(Shared.Simulation.Sim)
local Bot = require(Shared.Simulation.Bot)
local Protocol = require(Shared.Protocol.Protocol)
local Net = require(script.Parent.Parent.Networking.Net)
local GameData = Shared:WaitForChild("GameData", 10)
assert(GameData, "src/shared/GameData missing: run tools/conversion/generate_all.py (see README)")
local Locked = require(GameData.Locked)
local Units = require(GameData.UnitCatalog)

local MatchService = {}

local LOCOMOTION = { foot = "foot", tracks = "tracks", wheels = "wheels", sea = "sea" }
local SNAPSHOT_EVERY = 2 -- 20 Hz sim, 10 Hz snapshots
local STATE_EVERY = 10 -- 2 Hz private state

local rules: Rules.RuleSet
local map: MapCodec.DecodedMap
local sim: any
local sideOf: { [Player]: number } = {}
local bots: { [number]: any } = {}
local tick = 0

local function paceAt(kind: string, x: number, y: number): number
	local terrain = MapCodec.terrainName(map, x, y)
	if not terrain or not rules:flag(`terrain.{terrain}.passable`) then
		return 0
	end
	local loco = LOCOMOTION[Units[kind] and Units[kind].moves or "foot"]
	if loco == "foot" then
		-- Foot units: WarFront uses units.<kind>.rough off open ground (simplified, TEMP-002).
		return if terrain == "plains" or terrain == "beach" or terrain == "desert" then 1 else rules:number(`units.{kind}.rough`)
	end
	local key = `movement.terrainPace.{loco}.{terrain}`
	return if rules:has(key) then rules:number(key) else 1
end

local function updateBots()
	local taken = {}
	for _, s in sideOf do
		taken[s] = true
	end
	if not taken[2] and not bots[2] then
		bots[2] = Bot.new(sim, 2)
		print("[Match] side 2 is played by the bot (PROVISIONAL) until a second player joins")
	elseif taken[2] and bots[2] then
		bots[2] = nil
		print("[Match] side 2 handed from the bot to a player")
	end
end

local function onIntent(player: Player, raw: any)
	local side = sideOf[player]
	if not side or side == 0 then
		return
	end
	local intent, err = Protocol.parse(raw, map.width, map.height)
	if not intent then
		warn(`[Match] rejected intent from {player.Name}: {err}`)
		return
	end
	local i = intent :: any
	local refused: { number } = {}
	if i.kind == "move" then
		refused = sim.orderMove(side, i.unitIds, i.x, i.y)
	elseif i.kind == "stop" then
		refused = sim.orderStop(side, i.unitIds)
	elseif i.kind == "attack" then
		local why
		refused, why = sim.orderAttack(side, i.unitIds, i.targetId)
		if why then
			warn(`[Match] attack from {player.Name} refused: {why}`)
		end
	elseif i.kind == "produce" then
		local ok, why = sim.orderProduce(side, i.item)
		if not ok then
			Net.sendState(player, { notice = why })
		end
	end
	if #refused > 0 then
		warn(`[Match] refused order from {player.Name} (side {side}) for units it does not own: {table.concat(refused, ",")}`)
	end
end

local function assignSide(player: Player): { [string]: any }
	local existing = sideOf[player]
	if not existing then
		local taken = {}
		for _, s in sideOf do
			taken[s] = true
		end
		existing = if not taken[1] then 1 elseif not taken[2] then 2 else 0 -- 0 = spectator
		sideOf[player] = existing
		updateBots()
	end
	return { map = map.data.id, side = existing, width = map.width, height = map.height }
end

local function snapshot()
	-- TEMP-001: everyone receives every unit. Fog-filtered snapshots come with fog of war.
	local units, structures = table.create(64), table.create(24)
	for _, e in sim.entities do
		if e.cat == "unit" then
			table.insert(units, { e.id, e.kind, e.side, e.x, e.y, e.heading, e.hp, e.maxHp })
		else
			table.insert(structures, { e.id, e.kind, e.side, e.x, e.y, e.hp, e.maxHp, e.capSide or 0, e.capProgress or 0, e.store or 0 })
		end
	end
	Net.broadcastSnapshot(tick, units, structures)
end

local function privateState()
	for player, side in sideOf do
		local s = sim.sides[side]
		local payload: { [string]: any } = { winner = sim.winner }
		if s then
			local hq = sim.entities[s.hqId]
			local queue = hq and hq.queue or {}
			payload.oil = math.floor(s.oil)
			payload.queue = #queue
			payload.queueLeft = if queue[1] then queue[1].left else nil
			payload.lost = s.lost
		end
		Net.sendState(player, payload)
	end
end

function MatchService.start(mapModule: string)
	rules = Rules.new(require(GameData.RulesData) :: any)
	map = MapCodec.decode(require(GameData.Maps[mapModule]) :: any)

	-- Structures sit on the centre of their cell, matching MapRenderer.
	local starts, rigs = {}, {}
	for _, s in map.data.starts do
		table.insert(starts, { x = s.x + 0.5, y = s.y + 0.5 })
	end
	for _, r in map.data.rigs do
		table.insert(rigs, { x = r.x + 0.5, y = r.y + 0.5, name = r.name })
	end
	sim = Sim.new({
		rules = rules :: any,
		movement = Movement,
		paceAt = paceAt,
		unitClass = function(kind: string): string
			return if Units[kind] and Units[kind].armour == "armour" then "armour" else "soft"
		end,
		starts = starts,
		rigs = rigs,
		width = map.width,
		height = map.height,
	})
	for side = 1, 2 do
		local list = {}
		for id, e in sim.entities do
			if e.side == side and e.cat == "unit" then
				table.insert(list, id)
			end
		end
		table.sort(list)
		print(`[Match] side {side} unit ids: {table.concat(list, ",")}`)
	end

	Net.init(onIntent, assignSide) -- sides are assigned when the client asks to join
	updateBots()
	Players.PlayerRemoving:Connect(function(p)
		sideOf[p] = nil
		updateBots()
	end)

	local step = 1 / Locked["match.tickHz"]
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = math.min(acc + dt, step * 5) -- never spiral: drop time beyond 5 ticks
		while acc >= step do
			acc -= step
			tick += 1
			for _, bot in bots do
				bot.step(step)
			end
			sim.step(step)
			for _, ev in sim.takeEvents() do
				if ev.type == "rigCaptured" or ev.type == "rigLost" or ev.type == "victory" then
					print(`[Match] {ev.type} side {ev.side}{if ev.id then " rig " .. ev.id else ""}`)
				elseif ev.type == "destroyed" and ev.kind == "hq" then
					print(`[Match] HQ of side {ev.side} destroyed`)
				end
			end
			if tick % SNAPSHOT_EVERY == 0 then
				snapshot()
			end
			if tick % STATE_EVERY == 0 then
				privateState()
			end
		end
	end)
end

return MatchService
