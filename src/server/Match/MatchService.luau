--!strict
--[[
	MatchService: owns the authoritative match state and the fixed 20 Hz loop.
	Clients only send intents (Protocol); everything here runs on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Config.Rules)
local MapCodec = require(Shared.Maps.MapCodec)
local Movement = require(Shared.Simulation.Movement)
local Protocol = require(Shared.Protocol.Protocol)
local Net = require(script.Parent.Parent.Networking.Net)
local GameData = Shared:WaitForChild("GameData", 10)
assert(GameData, "src/shared/GameData missing: run tools/conversion/generate_all.py (see README)")
local Locked = require(GameData.Locked)

local MatchService = {}

type Unit = Movement.Unit

local state = {
	rules = nil :: Rules.RuleSet?,
	map = nil :: MapCodec.DecodedMap?,
	units = {} :: { [number]: Unit },
	nextId = 1,
	sideOf = {} :: { [Player]: number },
	tick = 0,
}

local function rules(): Rules.RuleSet
	return assert(state.rules, "match not started")
end

local function map(): MapCodec.DecodedMap
	return assert(state.map, "match not started")
end

local LOCOMOTION = { foot = "foot", tracks = "tracks", wheels = "wheels", sea = "sea" }
local Units = require(GameData.UnitCatalog)

local movementCtx: Movement.Context = {
	speedOf = function(kind: string): number
		return rules():number(`units.{kind}.speed`)
	end,
	paceAt = function(kind: string, x: number, y: number): number
		local terrain = MapCodec.terrainName(map(), x, y)
		if not terrain then
			return 0
		end
		local r = rules()
		if not r:flag(`terrain.{terrain}.passable`) then
			return 0
		end
		local loco = LOCOMOTION[Units[kind].moves]
		if loco == "foot" then
			-- Foot units: WarFront uses units.<kind>.rough off open ground (simplified, TEMP-002).
			return if terrain == "plains" or terrain == "beach" or terrain == "desert"
				then 1
				else r:number(`units.{kind}.rough`)
		end
		local key = `movement.terrainPace.{loco}.{terrain}`
		return if r:has(key) then r:number(key) else 1
	end,
}

local function spawn(kind: string, side: number, x: number, y: number): Unit
	local unit: Unit = {
		id = state.nextId,
		kind = kind,
		side = side,
		x = x,
		y = y,
		heading = 0,
		hp = rules():number(`units.{kind}.hp`),
		target = nil,
	}
	state.units[unit.id] = unit
	state.nextId += 1
	return unit
end

local function onIntent(player: Player, raw: any)
	local side = state.sideOf[player]
	if not side then
		return
	end
	local m = map()
	local intent, err = Protocol.parse(raw, m.width, m.height)
	if not intent then
		warn(`[Match] rejected intent from {player.Name}: {err}`)
		return
	end
	local refused = {}
	for _, id in intent.unitIds do
		local unit = state.units[id]
		if unit and unit.side == side then -- ownership check: never order another side's unit
			if intent.kind == "move" then
				unit.target = { x = intent.x, y = intent.y }
			else
				unit.target = nil
			end
		elseif unit then
			table.insert(refused, id)
		end
	end
	if #refused > 0 then
		warn(`[Match] refused order from {player.Name} (side {side}) for units it does not own: {table.concat(refused, ",")}`)
	end
end

local function assignSide(player: Player): { [string]: any }
	local existing = state.sideOf[player]
	if existing then
		return { map = map().data.id, side = existing, width = map().width, height = map().height }
	end
	local taken = {}
	for _, s in state.sideOf do
		taken[s] = true
	end
	local side = if not taken[1] then 1 elseif not taken[2] then 2 else 0 -- 0 = spectator
	state.sideOf[player] = side
	return { map = map().data.id, side = side, width = map().width, height = map().height }
end

local SNAPSHOT_EVERY = 2 -- 20 Hz sim, 10 Hz snapshots

function MatchService.start(mapModule: string)
	state.rules = Rules.new(require(GameData.RulesData) :: any)
	state.map = MapCodec.decode(require(GameData.Maps[mapModule]) :: any)

	-- Start forces: match.startInfantry infantry per side at each start (WarFront value).
	-- The extra tank/scout per side are TEST UNITS for the renderer milestone only.
	local starts = map().data.starts
	local count = rules():number("match.startInfantry")
	for side, s in starts do
		for i = 1, count do
			spawn("infantry", side, s.x + (i - 2) * 1.2, s.y + 3)
		end
		spawn("tank", side, s.x - 2, s.y - 3)
		spawn("scout", side, s.x + 2, s.y - 3)
	end
	local bySide = { {}, {} } :: { { number } }
	for id, u in state.units do
		table.insert(bySide[u.side], id)
	end
	for side = 1, 2 do
		table.sort(bySide[side])
		print(`[Match] side {side} unit ids: {table.concat(bySide[side], ",")}`)
	end

	Net.init(onIntent, assignSide) -- sides are assigned when the client asks to join
	Players.PlayerRemoving:Connect(function(p)
		state.sideOf[p] = nil
	end)

	local step = 1 / Locked["match.tickHz"]
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = math.min(acc + dt, step * 5) -- never spiral: drop time beyond 5 ticks
		while acc >= step do
			acc -= step
			state.tick += 1
			for _, unit in state.units do
				Movement.step(unit, step, movementCtx)
			end
			if state.tick % SNAPSHOT_EVERY == 0 then
				-- TEMP-001: everyone receives every unit. Fog-filtered snapshots come with fog of war.
				local list = table.create(32)
				for _, u in state.units do
					table.insert(list, { u.id, u.kind, u.side, u.x, u.y, u.heading, u.hp })
				end
				Net.broadcastSnapshot(state.tick, list)
			end
		end
	end)
end

return MatchService
