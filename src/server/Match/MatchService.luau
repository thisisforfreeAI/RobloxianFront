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

local OPENING_DROP = true -- the game's opening drop: pick a landing spot, the truck sets up the HQ
-- each side's army (the game's skirmish setting; its default is the coalition). The republic has no
-- mortars and lays minefields.
local ARMIES = { "coalition", "coalition" }

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
	elseif i.kind == "garrison" then
		-- the settlement whose centre is nearest the click, within twice its radius
		local best, bd = nil, math.huge
		for _, st in sim.settlements do
			local d = (st.x - i.x) ^ 2 + (st.y - i.y) ^ 2
			if d <= (st.radius * 2) ^ 2 and d < bd then
				best, bd = st, d
			end
		end
		local n, why = 0, "noSettlement"
		if best then
			n, why = sim.orderGarrison(side, best.id, i.unitIds)
		end
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "forward" then
		local ok, why = sim.queueForward(side, i.cityId, i.item)
		if not ok then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "repair" then
		local n, why = sim.orderRepair(side, i.targetId, i.unitIds)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "roadRepair" then
		-- a cut within its work reach of the point first, else the most worn road cell next to it
		local cut = sim.cutNear(i.x, i.y, rules:number("roads.cutRadius") + rules:number("roads.repairReach"))
		local n, why = 0, "notWorn"
		if cut then
			n, why = sim.orderRoadRepair(side, "cut", cut.id, i.unitIds)
		else
			local c = sim.wornCellNear(sim.roads.cellAt(i.x, i.y))
			if c >= 0 then
				n, why = sim.orderRoadRepair(side, "wear", c, i.unitIds)
			end
		end
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "sabotage" then
		-- the road cell nearest the point (within 1.5 cells; APPROX: the game takes the clicked cell)
		local best, bd = -1, 1.5 * 1.5
		for dy = -2, 2 do
			for dx = -2, 2 do
				local cx, cy = math.floor(i.x) + dx, math.floor(i.y) + dy
				local c = sim.roads.cellAt(cx + 0.5, cy + 0.5)
				local d = (cx + 0.5 - i.x) ^ 2 + (cy + 0.5 - i.y) ^ 2
				if c >= 0 and sim.roads.isRoad(c) and d <= bd then
					best, bd = c, d
				end
			end
		end
		local n, why = sim.orderSabotage(side, if best >= 0 then best else sim.roads.cellAt(i.x, i.y), i.unitIds)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "power" then
		local ok, why
		if i.power == "para" then
			ok, why = sim.callParatroopers(side, i.x, i.y)
		elseif i.power == "drone" then
			ok, why = sim.launchDrone(side, i.x, i.y)
		elseif i.power == "demo" then
			ok, why = sim.deployDemo(side, i.x, i.y)
		elseif i.power == "barrage" or i.power == "flare" then
			-- the nearest own artillery base that can fire there now; else the first reason
			local best, bd, first = nil, math.huge, "noArtyBase"
			for _, b in sim.list do
				if b.alive and b.kind == "artybase" and b.side == side then
					local w = sim.artyProblem(side, b.id, i.power, i.x, i.y)
					local d = (b.x - i.x) ^ 2 + (b.y - i.y) ^ 2
					if not w and d < bd then
						best, bd = b, d
					elseif w and first == "noArtyBase" then
						first = w
					end
				end
			end
			if best then
				ok, why = sim.artyStrike(side, best.id, i.power, i.x, i.y)
			else
				ok, why = false, first
			end
		else
			-- the nearest own airfield town that could fly there now; else the first reason
			local best, bd, first = nil, math.huge, "noAirfield"
			for _, st in sim.settlements do
				if st.trait == "airfield" and st.owner == side then
					local w = sim.airfieldProblem(side, st, i.x, i.y)
					local d = (st.x - i.x) ^ 2 + (st.y - i.y) ^ 2
					if not w and d < bd then
						best, bd = st, d
					elseif w and first == "noAirfield" then
						first = w
					end
				end
			end
			if best then
				ok, why = sim.callAirfield(side, best.id, i.x, i.y)
			else
				ok, why = false, first
			end
		end
		if not ok then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "barrage" then
		local n, why = sim.orderBarrage(side, i.unitIds, i.x, i.y)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "dropPick" then
		local ok, why = sim.setDropPick(side, i.x, i.y)
		if not ok then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "dropReady" then
		sim.setDropReady(side)
	elseif i.kind == "cancelQueue" then
		local id = i.structureId or sim.sides[side].hqId
		local st = sim.entities[id]
		local index = if i.index == 0 and st and st.queue then #st.queue else i.index
		local ok = sim.cancelQueued(side, id, index)
		if not ok then
			Net.sendState(player, { notice = "nothingQueued" })
		end
	elseif i.kind == "dig" then
		local pts = {}
		for k = 1, #i.pts, 2 do
			table.insert(pts, { x = i.pts[k], y = i.pts[k + 1] })
		end
		local n, why = sim.orderDig(side, i.unitIds, pts)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "fill" then
		local n, why = sim.orderFill(side, i.unitIds, math.floor(i.y) * sim.roads.width + math.floor(i.x))
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "nightOps" then
		-- the game's nvOff switch, for every tower the side has
		local n = 0
		for _, e in sim.list do
			if e.alive and e.kind == "nightops" and e.side == side then
				sim.switchNightOps(side, e.id, i.on)
				n += 1
			end
		end
		if n == 0 then
			Net.sendState(player, { notice = "noNightOps" })
		end
	elseif i.kind == "layMines" then
		local pts = {}
		for k = 1, #i.pts, 2 do
			table.insert(pts, { x = i.pts[k], y = i.pts[k + 1] })
		end
		local id, why = sim.layMinefield(side, pts)
		if not id then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "demolish" then
		local st = sim.entities[i.structureId]
		local ok, why
		if st and st.alive and st.built and st.built < 1 then
			ok, why = sim.cancelBuilding(side, i.structureId)
		else
			ok, why = sim.demolish(side, i.structureId)
		end
		if not ok then
			Net.sendState(player, { notice = if why == "notOwned" then "notOwned" else "cannotDemolish" })
		end
	elseif i.kind == "board" then
		local n, why = sim.orderBoard(side, i.carrierId, i.unitIds)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "unload" then
		local n, why = sim.orderUnload(side, i.unitIds)
		if n == 0 then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "detonate" then
		local ok, why = sim.detonate(side, i.unitIds)
		if not ok then
			Net.sendState(player, { notice = why })
		end
	elseif i.kind == "recon" then
		-- command trucks among them set up an HQ; the rest are scouts
		local scouts, why = {}, nil
		local deployed = false
		for _, id in i.unitIds do
			local e = sim.entities[id]
			if e and e.kind == "command" then
				local ok, w = sim.deployHq(side, id)
				deployed = deployed or ok
				why = why or w
			else
				table.insert(scouts, id)
			end
		end
		if #scouts > 0 then
			local n, w = sim.deployRecon(side, scouts)
			if n == 0 and not deployed then
				Net.sendState(player, { notice = w })
			end
		elseif not deployed and why then
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

-- 0 none, 1 scout deployed (recon), 2 gun packing up, 3 gun setting up, 4 inside a settlement,
-- 5 repairing, 6 sabotage
local function unitStatus(e: any): number
	if e.inside then
		return 4
	end
	if e.deployAt then
		return 9
	end
	if e.trenchJob then
		return if e.trenchJob.kind == "dig" then 10 else 11
	end
	if e.repairId or e.roadJob then
		return 5
	end
	if e.sabotageCell then
		return 6
	end
	if e.stopped == "enemy" then
		return 7
	end
	if e.stopped == "cut" then
		return 8
	end
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
				table.insert(units, { e.id, e.kind, e.side, e.x, e.y, e.heading, e.hp, e.maxHp, unitStatus(e), e.rank or 0, if e.cargo then #e.cargo else 0 })
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
local sentWear: { [Player]: number } = {}
local wearSentAt: { [Player]: number } = {}
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

-- On-screen alerts for match events, sent to the sides the game alerts (PLACEHOLDER wording; the
-- game's own text is not used). Each side's alerts go out with its next private state.
local pendingAlerts: { [number]: { string } } = {}
local convoyNoticeAt: { [string]: number } = {}
local function alertSide(side: number?, text: string)
	if side and side > 0 then
		local list = pendingAlerts[side] or {}
		if #list < 6 then
			table.insert(list, text)
		end
		pendingAlerts[side] = list
	end
end
local function nameOf(kind: string?): string
	if not kind then
		return "?"
	end
	if rules:has(`units.{kind}.name`) then
		return rules:text(`units.{kind}.name`)
	end
	if rules:has(`structures.{kind}.name`) then
		return rules:text(`structures.{kind}.name`)
	end
	return kind
end
local function townOf(id: number?): string
	local st = if id then sim.settlements[id] else nil
	return if st and st.name ~= "" then st.name else "A town"
end
local function rigName(id: number?): string
	local rig = if id then sim.entities[id] else nil
	return if rig and rig.name then `Oil rig {rig.name}` else "An oil rig"
end
local function alertsFor(ev: any)
	local t = ev.type
	-- the game's Cje: by night a side without night vision misses these alerts
	if ev.side and sim.quietAtNight(t, ev.side) then
		return
	end
	if t == "rigUnderAttack" then
		alertSide(ev.side, `{rigName(ev.id)} is under attack`)
	elseif t == "rigCaptureStarted" then
		alertSide(ev.side, `{rigName(ev.id)} is being captured`)
	elseif t == "rigCaptured" then
		alertSide(ev.side, `{rigName(ev.id)} captured`)
	elseif t == "rigLost" then
		alertSide(ev.side, `{rigName(ev.id)} lost`)
	elseif t == "rigNoTrucks" then
		alertSide(ev.side, `{rigName(ev.id)} has no trucks left`)
	elseif t == "convoyLost" then
		alertSide(ev.side, "Oil truck destroyed")
	elseif t == "droneScanned" then
		alertSide(ev.side, "The drone is over the area")
	elseif t == "droneLost" and ev.shot then
		alertSide(ev.side, "Recon drone shot down")
	elseif t == "unitPromoted" then
		alertSide(ev.side, `{rules:text(`units.{ev.kind}.name`)} promoted: {ev.rank}`)
	elseif t == "hqDeploying" then
		alertSide(ev.side, `Command truck setting up the HQ: {ev.sec} s, keep it still`)
	elseif t == "hqDeployed" or t == "hqSetUp" then
		alertSide(ev.side, "The new HQ is up")
	elseif t == "mineBlast" then
		alertSide(ev.side, `{rules:text(`units.{ev.kind}.name`)} hit a mine`)
		if ev.owner ~= ev.side then
			alertSide(ev.owner, `A mine took out part of an enemy {rules:text(`units.{ev.kind}.name`)}`)
		end
	elseif t == "dropNoRoad" then
		alertSide(ev.side, "Your command truck landed away from the roads: select it and press R to set up the HQ")
	elseif t == "trenchDug" then
		alertSide(ev.side, `Trench dug: {ev.n} cells`)
	elseif t == "trenchStalled" then
		alertSide(ev.side, "Trench work stopped: not enough oil")
	elseif t == "trenchClosed" then
		alertSide(ev.side, "Gap filled in the trench")
	elseif t == "trenchGapped" then
		alertSide(ev.side, "Engineers cut a gap in a trench")
		if ev.owner ~= ev.side then
			alertSide(ev.owner, "The enemy cut a gap in your trench")
		end
	elseif t == "minefieldSpent" then
		alertSide(ev.side, "A minefield is used up")
	elseif t == "demolished" then
		alertSide(ev.side, `{rules:text(`structures.{ev.kind}.name`)} pulled down: {ev.oil} oil back`)
	elseif t == "buildCancelled" then
		alertSide(ev.side, `{rules:text(`structures.{ev.kind}.name`)} cancelled`)
	elseif t == "nightOpsLost" then
		alertSide(ev.side, `Night operations tower destroyed: a new one can go up in {ev.sec} s`)
	elseif t == "barrageIntercepted" then
		alertSide(ev.side, `SAM sites stopped {ev.n} of {ev.total} shells`)
	elseif t == "barrageStopped" then
		alertSide(ev.side, `Our SAM sites stopped {ev.n} enemy shells`)
	elseif t == "droneHome" then
		alertSide(ev.side, "The drone is back: refuelling")
	elseif t == "paraAway" then
		alertSide(ev.side, `Paratroopers away: down in about {ev.sec} s`)
	elseif t == "airfieldAway" then
		alertSide(ev.side, `Transport away from {townOf(ev.city)}: down in about {ev.sec} s`)
	elseif t == "paraLanded" or t == "airfieldLanded" then
		alertSide(ev.side, `{ev.n} squads are on the ground`)
	elseif t == "airfieldReady" then
		alertSide(ev.side, `The airfield at {townOf(ev.city)} is ready`)
	elseif t == "capitalPowerReady" then
		alertSide(ev.side, if ev.power == "para" then "Paratroopers ready" else "Bomb truck ready")
	elseif t == "demoOut" then
		alertSide(ev.side, "Bomb truck on its way")
	elseif t == "demoBlast" then
		alertSide(ev.side, if ev.target then `Bomb truck hit the {nameOf(ev.target)}` else "Bomb truck blew up")
	elseif t == "convoyHeld" or t == "convoyStranded" then
		-- the game's notice keys: one per rig, held every 45 s, stranded every 30 s at most
		local key = `{t}{ev.side}:{ev.rig or -1}`
		local gap = if t == "convoyHeld" then 45 else 30
		local now = sim.time
		if now - (convoyNoticeAt[key] or -math.huge) >= gap then
			convoyNoticeAt[key] = now
			local from = if ev.rig and ev.rig > 0 then ` from {rigName(ev.rig)}` else ""
			alertSide(ev.side, if t == "convoyHeld" then `Oil trucks{from} held up by enemies ahead` else `Oil trucks{from} stranded: the road is cut`)
		end
	elseif t == "cityUnderAttack" then
		alertSide(ev.side, `{townOf(ev.id)} is under attack`)
	elseif t == "cityTaken" then
		alertSide(ev.side, `{townOf(ev.id)} taken`)
	elseif t == "cityLost" then
		alertSide(ev.side, `{townOf(ev.id)} lost`)
	elseif t == "settlementDestroyed" then
		alertSide(ev.side, `{townOf(ev.id)} lies in ruins`)
	elseif t == "built" then
		alertSide(ev.side, `{nameOf(ev.kind)} ready`)
	elseif t == "unitReady" then
		alertSide(ev.side, `{nameOf(ev.kind)} ready`)
	elseif t == "forwardReady" then
		alertSide(ev.side, `{nameOf(ev.kind)} ready at {townOf(ev.city)}`)
	elseif t == "destroyed" and ev.kind ~= "truck" and rules:has(`structures.{ev.kind}.name`) then
		alertSide(ev.side, `{nameOf(ev.kind)} destroyed`)
	elseif t == "repaired" then
		alertSide(ev.side, `{nameOf(ev.kind)} repaired`)
	elseif t == "roadCut" or t == "bridgeDown" then
		local text = if t == "bridgeDown" then "A bridge is down" else "A road was cut"
		alertSide(ev.side, text)
		for _, sd in ev.users or {} do
			if sd ~= ev.side then
				alertSide(sd, if t == "bridgeDown" then "A bridge on your supply route is down" else "Your supply road was cut")
			end
		end
	elseif t == "roadSabotaged" then
		alertSide(ev.side, "Your supply road was sabotaged")
	elseif t == "roadRepaired" then
		alertSide(ev.side, "Road repaired")
	elseif t == "roadMended" then
		alertSide(ev.side, "Road surface mended")
	elseif t == "sabotageArmed" then
		alertSide(ev.side, "Charge armed: get clear")
	elseif t == "sabotageDone" then
		alertSide(ev.side, "Sabotage done: road cut")
	elseif t == "sabotageFailed" then
		alertSide(ev.side, "Sabotage failed")
	elseif t == "hqLostRebuild" then
		alertSide(ev.side, "HQ lost")
	end
end

local function privateState()
	for player, side in sideOf do
		local s = sim.sides[side]
		local payload: { [string]: any } = { winner = sim.winner }
		payload.alerts = pendingAlerts[side]
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
			-- unit prices after settlement and factory-town discounts
			local prices = {}
			for item in Protocol.PRODUCIBLE do
				prices[item] = sim.unitCost(side, item)
			end
			payload.prices = prices
			-- own towns and cities that can train (forward training): queue, time left, working now
			local forwards = {}
			for _, st in sim.settlements do
				if st.owner == side and table.find((rules.data["cities.forward.kinds"] :: { string }?) or {}, st.kind) then
					local f = st.forward
					table.insert(forwards, { id = st.id, queue = if f then #f.queue else 0, left = sim.forwardLeft(st.id),
						active = sim.forwardActive(st) })
				end
			end
			payload.forwards = forwards
			-- the capital's powers and own airfield towns: state and seconds left
			local paraState, paraLeft = sim.capitalPower(side, "para")
			local demoState, demoLeft = sim.capitalPower(side, "demo")
			local droneState, droneLeft = sim.droneState(side)
			payload.powers = { para = { paraState, math.ceil(paraLeft) }, demo = { demoState, math.ceil(demoLeft) }, drone = { droneState, math.ceil(droneLeft) } }
			-- kills to spend, and the soonest own working artillery base's barrage / flare wait (-1: no base)
			payload.kills = sim.killsOf(side)
			local towerOff = 0
			for _, e in sim.list do
				if e.alive and e.kind == "nightops" and e.side == side and e.built >= 1 and e.nvOff then
					towerOff = 1
				end
			end
			payload.nv = { if sim.nightVisionFor(side) then 1 else 0, math.ceil(sim.nightOpsRebuildIn(side)), towerOff }
			local artyB, artyF = -1, -1
			for _, b in sim.list do
				if b.alive and b.kind == "artybase" and b.side == side and not sim.inactiveReason(b) then
					local r = b.strikeReady or {}
					local wb, wf = math.ceil(math.max(0, (r.barrage or 0) - sim.time)), math.ceil(math.max(0, (r.flare or 0) - sim.time))
					artyB = if artyB < 0 then wb else math.min(artyB, wb)
					artyF = if artyF < 0 then wf else math.min(artyF, wf)
				end
			end
			payload.arty = { artyB, artyF }
			local airfields = {}
			for _, st in sim.settlements do
				if st.trait == "airfield" and st.owner == side then
					table.insert(airfields, { st.id, math.ceil(math.max(0, (st.airfieldReady or 0) - sim.time)), if sim.traitActive(st) then 1 else 0 })
				end
			end
			payload.airfields = airfields
			-- transport flights in the air (APPROX: every side sees every plane): the client flies
			-- them on from these numbers and its own clock
			local flights = {}
			for _, d in sim.paradrops do
				local pl = d.plane
				local sticks = {}
				for _, l in pl.loads do
					table.insert(sticks, { l.x, l.y, l.outT, l.landT })
				end
				table.insert(flights, { id = d.id, side = d.side, fromX = pl.fromX, fromY = pl.fromY, heading = pl.heading,
					speed = pl.speed, startT = pl.startT, goneT = pl.goneT, sticks = sticks })
			end
			payload.flights = flights
			-- recon drones and SAM missiles (APPROX: every side sees them all): x, y, side, phase
			local drones = {}
			for _, d in sim.drones do
				table.insert(drones, { d.x, d.y, d.side, d.phase })
			end
			payload.drones = drones
			local missiles = {}
			for _, m in sim.samMissiles do
				table.insert(missiles, { m.x, m.y, m.heading, m.side })
			end
			payload.missiles = missiles
			-- own flares (others only see what they light): x, y, burstAt, until, radius
			local flares = {}
			for _, f in sim.flares do
				if f.side == side then
					table.insert(flares, { f.x, f.y, f.burstAt, f.untilT, f.r })
				end
			end
			payload.flares = flares
			-- minefields this side can see: id, side, charges left (own only), laid cells
			payload.army = sim.armyOf(side)
			local mines = {}
			local viewer = viewers[side]
			for _, e in sim.list do
				if e.alive and e.kind == "minefield" and (e.side == side or (viewer and viewer.structureState(e) == "seen")) then
					table.insert(mines, { e.id, e.side, if e.side == side then e.mines else 0, (sim.laidMines(e)) })
				end
			end
			payload.mines = mines
			-- no HQ yet but a command truck: the HUD reminds you how to set it up
			if not sim.hqOf(side) then
				for _, e in sim.list do
					if e.alive and e.kind == "command" and e.side == side then
						payload.needHq = if e.deployAt then "deploying" else "truck"
						break
					end
				end
			end
			-- trenches this side can see: owner, then cell, state pairs (dug / wire / planned, own planned only)
			local trenches = {}
			for _, t in sim.trenches do
				local row = { t.owner }
				for k, c in t.cells do
					local st = t.state[k]
					local shown = st == sim.TRENCH.dug or st == sim.TRENCH.wire or (st == sim.TRENCH.plan and t.owner == side)
					if shown and (t.owner == side or not viewer or viewer.grid[c + 1] == 2 or (viewer.trenchSeen and viewer.trenchSeen[c])) then
						if t.owner ~= side and viewer then
							viewer.trenchSeen = viewer.trenchSeen or {}
							viewer.trenchSeen[c] = true
						end
						table.insert(row, c)
						table.insert(row, st)
					end
				end
				if #row > 1 then
					table.insert(trenches, row)
				end
			end
			payload.trenches = trenches
			payload.time = sim.time
			-- the opening drop: phase, seconds left, own pick (and whether a road there reaches the rigs);
			-- while it runs the planes fly on the drop clock
			local d = sim.drop
			if d and d.phase ~= "done" then
				local p = d.picks[side]
				payload.drop = { phase = d.phase, left = math.ceil(sim.dropLeft()), x = p.x, y = p.y,
					warn = sim.dropWarning(p.x, p.y) ~= nil, arrival = d.opening and d.opening.arrival or nil }
				payload.time = d.t
				local fl = {}
				for k, pl in d.planes do
					local sticks = {}
					for _, l in pl.loads do
						table.insert(sticks, { l.x, l.y, l.outT, l.landT })
					end
					table.insert(fl, { id = -k, side = pl.side, fromX = pl.fromX, fromY = pl.fromY, heading = pl.heading,
						speed = pl.speed, startT = pl.startT, goneT = pl.goneT, sticks = sticks })
				end
				payload.flights = fl
			end
			-- road cuts (APPROX: everyone sees every cut) and worn road cells, banded, when they change
			local cuts = {}
			for _, cut in sim.roadCuts do
				table.insert(cuts, { cut.id, cut.x, cut.y, rules:number("roads.cutRadius"), math.floor(cut.repair * 100), if cut.bridge then 1 else 0 })
			end
			payload.cuts = cuts
			-- own charges being planted or armed
			local charges = {}
			for _, sb in sim.sabotages do
				if sb.side == side then
					table.insert(charges, { sb.id, sb.x, sb.y, math.floor(sb.progress * 100), if sb.phase == "armed" then 1 else 0 })
				end
			end
			payload.charges = charges
			-- radar contacts out of sight: flat x, y, strength (1 light, 2 medium, 3 heavy)
			local blips = {}
			local viewer = viewers[side]
			if not sim.fogOn() then
				viewer = nil
			end
			if viewer or not sim.fogOn() then
				for _, ct in sim.contactsFor(side, if viewer then viewer.grid else nil) do
					if not ct.seen and sim.fogOn() then
						table.insert(blips, math.floor(ct.x * 10 + 0.5) / 10)
						table.insert(blips, math.floor(ct.y * 10 + 0.5) / 10)
						table.insert(blips, if ct.strength == "heavy" then 3 elseif ct.strength == "medium" then 2 else 1)
					end
				end
			end
			payload.contacts = blips
			-- enemy units last seen a moment ago (the game's unit intel markers)
			payload.ghosts = if viewers[side] then viewers[side].ghosts() else {}
			if sentWear[player] ~= sim.roads.wearEpoch and sim.time - (wearSentAt[player] or -math.huge) >= 5 then -- at most every 5 s
				sentWear[player], wearSentAt[player] = sim.roads.wearEpoch, sim.time
				local worn = {}
				local from = rules:number("roads.wear.from")
				for c = 0, sim.roads.width * sim.roads.height - 1 do
					local v = sim.roads.wearAt(c)
					if v >= from and sim.roads.isRoad(c) then
						table.insert(worn, c)
						table.insert(worn, if v >= 0.8 then 3 elseif v >= 0.55 then 2 else 1)
					end
				end
				payload.worn = worn
			end
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
				table.insert(cities, { st.id, st.owner, if st.capture then st.capture.by else 0, if st.capture then math.floor(st.capture.progress * 100) / 100 else 0, math.floor(st.hold * 100) / 100, #st.garrison, rules:number(`cities.garrisonFull.{st.kind}`), st.trait or "", if sim.traitActive(st) then 1 else 0,
					math.floor(st.integrity / math.max(1, st.maxIntegrity) * 100), if st.destroyed then 1 else 0 })
			else
				-- the trait is known from the map; garrison and whether it works are not
				table.insert(cities, { st.id, seenOwners[st.id] or 0, 0, 0, 1, 0, 0, st.trait or "", 0, -1, 0 })
			end
		end
		local ck = HttpService:JSONEncode(cities)
		if sentCities[player] ~= ck then
			sentCities[player] = ck
			payload.cities = cities
		end
		Net.sendState(player, payload)
	end
	table.clear(pendingAlerts)
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
		drop = OPENING_DROP,
		armies = ARMIES,
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
		-- the game starts each match with a fresh seed (0 to 999999); here it only draws the opening deck
		deckSeed = Random.new():NextInteger(0, 999999),
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
		sentWear[p], wearSentAt[p] = nil, nil
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
				alertsFor(ev)
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
