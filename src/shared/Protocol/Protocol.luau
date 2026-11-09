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
Protocol.PRODUCIBLE = { infantry = true, engineer = true, at = true, tank = true, ifv = true, mortar = true, artillery = true, scout = true }
Protocol.BUILDABLE = { barracks = true, factory = true, bunker = true, atgun = true }

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
export type TruckIntent = { kind: "truck", rigId: number } -- send an idle truck to a rig, or buy one
export type Intent = MoveIntent | StopIntent | AttackIntent | ProduceIntent | TruckIntent | BuildIntent | ReconIntent | GarrisonIntent | RepairIntent | ForwardIntent

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
	elseif raw.kind == "repair" then
		if not finite(raw.targetId) or raw.targetId % 1 ~= 0 then
			return nil, "targetId must be an integer"
		end
		return { kind = "repair", unitIds = ids, targetId = raw.targetId }, nil
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
