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

Protocol.MAX_UNITS_PER_ORDER = 64

export type MoveIntent = { kind: "move", unitIds: { number }, x: number, y: number }
export type StopIntent = { kind: "stop", unitIds: { number } }
export type Intent = MoveIntent | StopIntent

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
	end
	return nil, "unknown intent kind"
end

return Protocol
