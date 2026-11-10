--!strict
--[[
	Protocol: names of remotes and validation of client intents.
	Clients send intents only; the server decides outcomes.
]]

local Protocol = {}

Protocol.FOLDER = "WarFrontNet"
Protocol.INTENT = "Intent" -- RemoteEvent, client -> server
Protocol.SNAPSHOT = "Snapshot" -- RemoteEvent, server -> client (10 Hz)
Protocol.JOIN = "Join" -- RemoteFunction, client -> server, returns { map, side, width, height }
Protocol.STATE = "State" -- RemoteEvent, server -> one client (2 Hz): own oil, HQ queue, match result

-- Units the slice can train (the server checks which producer may train what) and buildings it can place.
Protocol.PRODUCIBLE = { infantry = true, engineer = true, at = true, tank = true, ifv = true, mortar = true, artillery = true, scout = true, rocket = true, command = true }
Protocol.BUILDABLE = { barracks = true, factory = true, bunker = true, atgun = true, radar = true, sam = true, artybase = true, nightops = true }

Protocol.MAX_UNITS_PER_ORDER = 64

export type MoveIntent = { kind: "move", unitIds: { number }, x: number, y: number }
export type StopIntent = { kind: "stop", unitIds: { number } }
export type AttackIntent = { kind: "attack", unitIds: { number }, targetId: number }
export type ProduceIntent = { kind: "produce", item: string, structureId: number? } -- no id = the HQ
export type BuildIntent = { kind: "build", structure: string, x: number, y: number } -- footprint centre cell
export type ReconIntent = { kind: "recon", unitIds: { number } } -- deploy scouts for recon
export type GarrisonIntent = { kind: "garrison", unitIds: { number }, x: number, y: number } -- into the held settlement at (x, y)
export type ForwardIntent = { kind: "forward", cityId: number, item: string } -- train in a held, secured town
export type RepairIntent = { kind: "repair", unitIds: { number }, targetId: number } -- engineers mend an own building
export type RoadRepairIntent = { kind: "roadRepair", unitIds: { number }, x: number, y: number } -- engineers mend a road cut or worn road at a point
export type SabotageIntent = { kind: "sabotage", unitIds: { number }, x: number, y: number } -- engineers plant a charge on a road
export type TruckIntent = { kind: "truck", rigId: number } -- send an idle truck to a rig, or buy one
export type PowerIntent = { kind: "power", power: string, x: number, y: number } -- paratroopers, bomb truck, an airfield drop, the recon drone, or an artillery base barrage / flares at a point
export type BarrageIntent = { kind: "barrage", unitIds: { number }, x: number, y: number } -- rocket artillery fires on a point
export type DetonateIntent = { kind: "detonate", unitIds: { number } } -- blow up selected bomb trucks
export type BoardIntent = { kind: "board", unitIds: { number }, carrierId: number } -- riders get into an IFV
export type UnloadIntent = { kind: "unload", unitIds: { number } } -- IFVs set their riders down
export type DropPickIntent = { kind: "dropPick", x: number, y: number } -- where to land in the opening drop
export type DropReadyIntent = { kind: "dropReady" } -- done picking
export type CancelQueueIntent = { kind: "cancelQueue", structureId: number?, index: number } -- call off a queued unit (index 0 = the last; no id = the HQ)
export type DemolishIntent = { kind: "demolish", structureId: number } -- cancel a building going up, or pull a finished one down
export type NightOpsIntent = { kind: "nightOps", on: boolean } -- switch your night operations towers on or off
export type LayMinesIntent = { kind: "layMines", pts: { number } } -- a minefield along a stroke: x1, y1, x2, y2, ... in cells
export type Intent = MoveIntent | StopIntent | AttackIntent | ProduceIntent | TruckIntent | BuildIntent | ReconIntent | GarrisonIntent | RepairIntent | ForwardIntent | RoadRepairIntent | SabotageIntent | PowerIntent | DetonateIntent | BarrageIntent | BoardIntent | UnloadIntent | DropPickIntent | DropReadyIntent | CancelQueueIntent | DemolishIntent | LayMinesIntent | NightOpsIntent

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function readIds(raw: any): ({ number }?, string?)
	if type(raw) ~= "table" then
		return nil, "unitIds must be a list"
	end
	local ids, seen = {}, {}
	for i, v in raw do
		if type(i) ~= "number" or not finite(v) or v % 1 ~= 0 then
			return nil, "unitIds must be integers"
		end
		if #ids >= Protocol.MAX_UNITS_PER_ORDER then
			return nil, "too many units in one order"
		end
		if not seen[v] then
			seen[v] = true
			table.insert(ids, v)
		end
	end
	if #ids == 0 then
		return nil, "no units"
	end
	return ids, nil
end

-- Shape check only. Ownership/passability are checked by the server against match state.
function Protocol.parse(raw: any, mapWidth: number, mapHeight: number): (Intent?, string?)
	if type(raw) ~= "table" then
		return nil, "intent must be a table"
	end
	if raw.kind == "produce" then
		if type(raw.item) ~= "string" or not Protocol.PRODUCIBLE[raw.item] then
			return nil, "cannot produce that"
		end
		if raw.structureId ~= nil and (not finite(raw.structureId) or raw.structureId % 1 ~= 0) then
			return nil, "structureId must be an integer"
		end
		return { kind = "produce", item = raw.item, structureId = raw.structureId }, nil
	end
	if raw.kind == "build" then
		if type(raw.structure) ~= "string" or not Protocol.BUILDABLE[raw.structure] then
			return nil, "cannot build that"
		end
		if not finite(raw.x) or not finite(raw.y) or raw.x % 1 ~= 0 or raw.y % 1 ~= 0 then
			return nil, "cell must be integers"
		end
		if raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "cell outside the map"
		end
		return { kind = "build", structure = raw.structure, x = raw.x, y = raw.y }, nil
	end
	if raw.kind == "forward" then
		if type(raw.item) ~= "string" or not Protocol.PRODUCIBLE[raw.item] then
			return nil, "cannot produce that"
		end
		if not finite(raw.cityId) or raw.cityId % 1 ~= 0 then
			return nil, "cityId must be an integer"
		end
		return { kind = "forward", cityId = raw.cityId, item = raw.item }, nil
	end
	if raw.kind == "power" then
		if raw.power ~= "para" and raw.power ~= "demo" and raw.power ~= "airfield" and raw.power ~= "drone"
			and raw.power ~= "barrage" and raw.power ~= "flare" then
			return nil, "unknown power"
		end
		if not finite(raw.x) or not finite(raw.y) then
			return nil, "target must be numbers"
		end
		if raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "target outside the map"
		end
		return { kind = "power", power = raw.power, x = raw.x, y = raw.y } :: any, nil
	end
	if raw.kind == "nightOps" then
		if type(raw.on) ~= "boolean" then
			return nil, "on must be true or false"
		end
		return { kind = "nightOps", on = raw.on } :: any, nil
	end
	if raw.kind == "dropReady" then
		return { kind = "dropReady" } :: any, nil
	end
	if raw.kind == "dropPick" then
		if not finite(raw.x) or not finite(raw.y) or raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "landing outside the map"
		end
		return { kind = "dropPick", x = raw.x, y = raw.y } :: any, nil
	end
	if raw.kind == "cancelQueue" then
		if not finite(raw.index) or raw.index % 1 ~= 0 or raw.index < 0 then
			return nil, "index must be a whole number"
		end
		if raw.structureId ~= nil and (not finite(raw.structureId) or raw.structureId % 1 ~= 0) then
			return nil, "structureId must be an integer"
		end
		return { kind = "cancelQueue", structureId = raw.structureId, index = raw.index } :: any, nil
	end
	if raw.kind == "layMines" then
		local pts = raw.pts
		if type(pts) ~= "table" or #pts < 2 or #pts > 1200 or #pts % 2 ~= 0 then
			return nil, "pts must be 1 to 600 x, y pairs"
		end
		local out = table.create(#pts)
		for i = 1, #pts do
			local v = pts[i]
			if not finite(v) or v < 0 or v >= (if i % 2 == 1 then mapWidth else mapHeight) then
				return nil, "stroke outside the map"
			end
			out[i] = v
		end
		return { kind = "layMines", pts = out } :: any, nil
	end
	if raw.kind == "demolish" then
		if not finite(raw.structureId) or raw.structureId % 1 ~= 0 then
			return nil, "structureId must be an integer"
		end
		return { kind = "demolish", structureId = raw.structureId } :: any, nil
	end
	if raw.kind == "truck" then
		if not finite(raw.rigId) or raw.rigId % 1 ~= 0 then
			return nil, "rigId must be an integer"
		end
		return { kind = "truck", rigId = raw.rigId }, nil
	end
	local ids, err = readIds(raw.unitIds)
	if not ids then
		return nil, err
	end
	if raw.kind == "move" then
		if not finite(raw.x) or not finite(raw.y) then
			return nil, "target must be numbers"
		end
		if raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "target outside the map"
		end
		return { kind = "move", unitIds = ids, x = raw.x, y = raw.y }, nil
	elseif raw.kind == "stop" then
		return { kind = "stop", unitIds = ids }, nil
	elseif raw.kind == "recon" then
		return { kind = "recon", unitIds = ids }, nil
	elseif raw.kind == "detonate" then
		return { kind = "detonate", unitIds = ids } :: any, nil
	elseif raw.kind == "unload" then
		return { kind = "unload", unitIds = ids } :: any, nil
	elseif raw.kind == "board" then
		if not finite(raw.carrierId) or raw.carrierId % 1 ~= 0 then
			return nil, "carrierId must be an integer"
		end
		return { kind = "board", unitIds = ids, carrierId = raw.carrierId } :: any, nil
	elseif raw.kind == "repair" then
		if not finite(raw.targetId) or raw.targetId % 1 ~= 0 then
			return nil, "targetId must be an integer"
		end
		return { kind = "repair", unitIds = ids, targetId = raw.targetId }, nil
	elseif raw.kind == "roadRepair" or raw.kind == "sabotage" or raw.kind == "barrage" then
		if not finite(raw.x) or not finite(raw.y) then
			return nil, "target must be numbers"
		end
		if raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "target outside the map"
		end
		return { kind = raw.kind, unitIds = ids, x = raw.x, y = raw.y } :: any, nil
	elseif raw.kind == "garrison" then
		if not finite(raw.x) or not finite(raw.y) then
			return nil, "target must be numbers"
		end
		if raw.x < 0 or raw.y < 0 or raw.x >= mapWidth or raw.y >= mapHeight then
			return nil, "target outside the map"
		end
		return { kind = "garrison", unitIds = ids, x = raw.x, y = raw.y }, nil
	elseif raw.kind == "attack" then
		if not finite(raw.targetId) or raw.targetId % 1 ~= 0 then
			return nil, "targetId must be an integer"
		end
		return { kind = "attack", unitIds = ids, targetId = raw.targetId }, nil
	end
	return nil, "unknown intent kind"
end

return Protocol
