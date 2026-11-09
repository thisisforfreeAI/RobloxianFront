--!strict
--[[
	MatchService: owns the authoritative match (Shared.Simulation.Sim) and the fixed 20 Hz loop.
	Clients only send intents (Protocol); everything here runs on the server.
	Sides: the first player gets side 1, the second side 2, later players spectate.
	The simulation runs on WarFront's match rules (GameData/RulesMatch: runtime defaults at cell scale 3).
	While side 2 has no player, WarFront's bot (Shared.Simulation.Bot) plays it with BOT_PERSONA.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Config.Rules)
local MapCodec = require(Shared.Maps.MapCodec)
local Movement = require(Shared.Simulation.Movement)
local Pathing = require(Shared.Simulation.Pathing)
local Territory = require(Shared.Simulation.Territory)
local Fog = require(Shared.Simulation.Fog)
local ValueNoise = require(Shared.Utilities.ValueNoise)
local Rng = require(Shared.Utilities.Rng)
local Roads = require(Shared.Simulation.Roads)
local Sim = require(Shared.Simulation.Sim)
local Bot = require(Shared.Simulation.Bot)
local Protocol = require(Shared.Protocol.Protocol)
local Net = require(script.Parent.Parent.Networking.Net)
local GameData = Shared:WaitForChild("GameData", 10)
assert(GameData, "src/shared/GameData missing: run tools/conversion/generate_all.py (see README)")
local Locked = require(GameData.Locked)

local MatchService = {}

-- Bot persona: "balanced", "turtle" or "warlord"; level: "easy", "normal" or "hard".
-- UNCONFIRMED which persona WarFront's lobby gives a new bot slot; balanced is the game's fallback.
local BOT_PERSONA = "balanced"
local BOT_LEVEL = "normal"
local SNAPSHOT_EVERY = 2 -- 20 Hz sim, 10 Hz snapshots
local STATE_EVERY = 10 -- 2 Hz private state

local rules: Rules.RuleSet
local map: MapCodec.DecodedMap
local sim: any
local sideOf: { [Player]: number } = {}
local bots: { [number]: any } = {}
local tick = 0

local function updateBots()
	local taken = {}
	for _, s in sideOf do
		taken[s] = true
	end
	if not taken[2] and not bots[2] then
		bots[2] = Bot.new(sim, 2, BOT_PERSONA, BOT_LEVEL)
		print(`[Match] side 2 is played by the {BOT_PERSONA} bot ({BOT_LEVEL}) until a second player joins`)
	elseif taken[2] and bots[2] then
		bots[2] = nil
		sim.sides[2].oilMult = 1 -- a player's nation has no difficulty or persona oil edge
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
		local ok, why = sim.orderProduce(side, i.item, i.structureId)
		if not ok then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "build" then
		local id, why = sim.placeStructure(side, i.structure, i.y * map.width + i.x)
		if not id then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "recon" then
		local n, why = sim.deployRecon(side, i.unitIds)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "truck" then
		local ok, why = sim.orderTruck(side, i.rigId)
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

-- Fog of war: each player side gets its own viewer (Shared.Simulation.Fog) and only what it sees.
-- Spectators (side 0) see everything.
local viewers: { [number]: any } = {}
local sentVision: { [Player]: string } = {}

local function structureRow(e: any, owner: number, details: boolean): { any }
	return {
		e.id, e.kind, owner, e.x, e.y, e.hp, e.maxHp,
		if details then e.capSide or 0 else 0,
		if details then e.capProgress or 0 else 0,
		if details then e.store or 0 else 0,
		e.built or 1, 0,
	}
end

-- 0 none, 1 scout deployed (recon), 2 gun packing up, 3 gun setting up
local function unitStatus(e: any): number
	if (e.reconLeft or 0) > 0 then
		return 1
	end
	if e.packAt and e.packAt > sim.time then
		return 2
	end
	if not e.path and rules:text(`units.{e.kind}.nato`) == "artillery" then
		local setup = rules:number(if rules:text(`units.{e.kind}.weapon`) == "mortar" then "mortar.setupSec" else "artillery.setupSec")
		if (e.still or 0) < setup then
			return 3
		end
	end
	return 0
end

local function viewFor(side: number): ({ any }, { any }, { number }?)
	local viewer = if side > 0 then viewers[side] else nil
	if side > 0 and not viewer then
		viewer = Fog.newViewer(sim, side)
		viewers[side] = viewer
	end
	if viewer then
		viewer.update()
	end
	local units, structures = table.create(64), table.create(24)
	local listed = {}
	for _, e in sim.list do
		if e.cat == "unit" then
			if not viewer or viewer.unitVisible(e) then
				table.insert(units, { e.id, e.kind, e.side, e.x, e.y, e.heading, e.hp, e.maxHp, unitStatus(e) })
			end
		elseif e.kind == "rig" then
			local seen = not viewer or e.side == side or viewer.visibleAt(e.x, e.y)
			table.insert(structures, structureRow(e, if viewer then viewer.rigOwner(e) else e.side, seen))
		else
			local state = if viewer then viewer.structureState(e) else "seen"
			if state == "seen" then
				table.insert(structures, structureRow(e, e.side, true))
				listed[e.id] = true
			end
		end
	end
	if viewer then
		-- buildings remembered from earlier sightings (the last kind and owner seen; health unknown)
		for id, info in viewer.lastSeen do
			if not listed[id] then
				table.insert(structures, { id, info.kind, info.side, info.x, info.y, 1, 1, 0, 0, 0, 1, 1 })
			end
		end
	end
	return units, structures, if viewer then viewer.runs() else nil
end

local function snapshot()
	local bySide: { [number]: any } = {}
	for player, side in sideOf do
		local v = bySide[side]
		if not v then
			local units, structures, runs = viewFor(side)
			v = { units = units, structures = structures, runs = runs, key = if runs then table.concat(runs, ",") else "all" }
			bySide[side] = v
		end
		local vision = nil
		if sentVision[player] ~= v.key then
			sentVision[player] = v.key
			vision = v.runs or {}
		end
		Net.sendSnapshot(player, tick, v.units, v.structures, vision, side == 0 or not sim.fogOn())
	end
end

-- Own territory as row runs { y, x0, x1, ... } (sent only when it changes): the client tints the
-- placement ghost with it; the server still checks every placement.
local sentTerritory: { [Player]: string } = {}
local function territoryRuns(side: number): { number }
	local owners = sim.territoryOwners()
	local w, h = map.width, map.height
	local runs = {}
	for y = 0, h - 1 do
		local x = 0
		while x < w do
			if owners[y * w + x + 1] == side then
				local x0 = x
				while x + 1 < w and owners[y * w + x + 2] == side do
					x += 1
				end
				table.insert(runs, y)
				table.insert(runs, x0)
				table.insert(runs, x)
			end
			x += 1
		end
	end
	return runs
end

local sentCities: { [Player]: string } = {}
local citySeen: { [number]: { [number]: number } } = {} -- per side: settlement id -> owner last seen
local function privateState()
	for player, side in sideOf do
		local s = sim.sides[side]
		local payload: { [string]: any } = { winner = sim.winner }
		if s then
			local hq = sim.hqOf(side)
			payload.oil = math.floor(s.oil)
			payload.queue = if hq then #hq.queue else 0
			payload.queueLeft = sim.queueLeft(side)
			payload.trucksIdle = s.trucksIdle
			payload.lost = s.lost
			local producers = {}
			for _, e in sim.list do
				local makes = e.cat == "structure" and rules.data[`structures.{e.kind}.produces`] :: { string }?
				if e.alive and e.side == side and e.queue and makes and #makes > 0 then
					table.insert(producers, { id = e.id, kind = e.kind, queue = #e.queue, left = sim.queueLeft(side, e.id), built = e.built })
				end
			end
			payload.producers = producers
			local runs = territoryRuns(side)
			local key = table.concat(runs, ",")
			if sentTerritory[player] ~= key then
				sentTerritory[player] = key
				payload.territory = runs
			end
		end
		-- settlements: owner, capture side and progress, hold. With fog, like rigs: a settlement your
		-- side does not see now shows the owner last seen there (neutral until first seen) and no
		-- capture or hold progress; your own always show. (APPROX of the game's viewer intel.)
		local viewer = if side > 0 and sim.fogOn() then viewers[side] else nil
		local seenOwners = citySeen[side] or {}
		citySeen[side] = seenOwners
		local cities = {}
		for _, st in sim.settlements do
			local seen = not viewer or st.owner == side or viewer.visibleAt(st.x, st.y)
			if seen then
				seenOwners[st.id] = st.owner
				table.insert(cities, { st.id, st.owner, if st.capture then st.capture.by else 0, if st.capture then math.floor(st.capture.progress * 100) / 100 else 0, math.floor(st.hold * 100) / 100 })
			else
				table.insert(cities, { st.id, seenOwners[st.id] or 0, 0, 0, 1 })
			end
		end
		local ck = HttpService:JSONEncode(cities)
		if sentCities[player] ~= ck then
			sentCities[player] = ck
			payload.cities = cities
		end
		Net.sendState(player, payload)
	end
end

function MatchService.start(mapModule: string)
	assert(GameData:FindFirstChild("RulesMatch"), "GameData.RulesMatch missing: rerun tools/conversion/generate_all.py")
	rules = Rules.new(require(GameData.RulesMatch) :: any)
	map = MapCodec.decode(require(GameData.Maps[mapModule]) :: any)

	-- Structures and rigs sit on the centre of their cell, as in WarFront.
	local starts, rigs = {}, {}
	for _, s in map.data.starts do
		table.insert(starts, { x = math.floor(s.x) + 0.5, y = math.floor(s.y) + 0.5 })
	end
	for _, r in map.data.rigs do
		table.insert(rigs, { x = r.x, y = r.y, name = r.name })
	end
	local w = map.width
	sim = Sim.new({
		rules = rules :: any,
		movement = Movement,
		roadsLib = Roads,
		pathingLib = Pathing,
		territoryLib = Territory,
		valueNoise = ValueNoise,
		rng = Rng,
		map = {
			width = map.width,
			height = map.height,
			terrainAt = function(cell: number): string?
				return MapCodec.terrainName(map, cell % w, cell // w)
			end,
			urbanAt = function(cell: number): boolean
				return buffer.readu8(map.urban, cell) ~= 0
			end,
			roads = (map.data :: any).roads or {},
		},
		starts = starts,
		rigs = rigs,
		settlements = (map.data :: any).settlements or {},
		seed = map.data.seed,
	})
	for _, rig in sim.rigs do
		if rig.rich > 1 then
			print(`[Match] rich rig {rig.id} {rig.name or ""} at {rig.x},{rig.y}`)
		end
	end
	print(`[Match] roads: {sim.roads.pieces} road networks; rules cell scale {rules:number("match.cellScale")}`)
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
		sentTerritory[p] = nil
		sentCities[p] = nil
		sentVision[p] = nil
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
				if ev.type == "rigCaptured" or ev.type == "rigLost" or ev.type == "victory" or ev.type == "eliminated" or ev.type == "delivered" or ev.type == "convoyLost" then
					print(`[Match] {ev.type} side {ev.side}{if ev.id then " id " .. ev.id else ""}{if ev.oil then " oil " .. math.floor(ev.oil) else ""}`)
				elseif ev.type == "destroyed" and ev.kind == "hq" then
					print(`[Match] HQ of side {ev.side} destroyed`)
				elseif ev.type == "buildPlaced" or ev.type == "built" then
					print(`[Match] {ev.type} {ev.kind} side {ev.side} id {ev.id}`)
				elseif ev.type == "hqLostRebuild" then
					print(`[Match] side {ev.side} lost its HQ but keeps a factory: {ev.sec} s to rehouse (no command truck in the slice)`)
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
