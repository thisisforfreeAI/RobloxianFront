--!strict
--[[
	Rules: read access to WarFront's rules table (RulesData.luau, generated).
	Keys keep WarFront's dotted names, e.g. "units.tank.cost".
	Pure module: pass the data table in, so it runs in Roblox and in Lune tests.
]]

local Rules = {}
Rules.__index = Rules

export type RuleValue = number | boolean
export type RuleSet = typeof(setmetatable({} :: { data: { [string]: RuleValue } }, Rules))

function Rules.new(data: { [string]: RuleValue }): RuleSet
	return setmetatable({ data = data }, Rules)
end

function Rules.count(self: RuleSet): number
	local n = 0
	for _ in self.data do
		n += 1
	end
	return n
end

function Rules.has(self: RuleSet, key: string): boolean
	return self.data[key] ~= nil
end

function Rules.number(self: RuleSet, key: string): number
	local v = self.data[key]
	if type(v) ~= "number" then
		error(`Rules: "{key}" is not a number rule (got {typeof(v)})`, 2)
	end
	return v
end

function Rules.flag(self: RuleSet, key: string): boolean
	local v = self.data[key]
	if type(v) ~= "boolean" then
		error(`Rules: "{key}" is not a switch rule (got {typeof(v)})`, 2)
	end
	return v
end

-- All rules under a prefix, with the prefix stripped: section("units.tank") -> { hp = 320, ["vs.soft"] = 1.1, ... }
function Rules.section(self: RuleSet, prefix: string): { [string]: RuleValue }
	local out = {}
	local p = prefix .. "."
	for k, v in self.data do
		if string.sub(k, 1, #p) == p then
			out[string.sub(k, #p + 1)] = v
		end
	end
	return out
end

return Rules
