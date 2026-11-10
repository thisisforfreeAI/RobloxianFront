--!strict
--[[
	ControlGroups: the game's control groups (QV / xxe / b5t / k5t / Cxe / $ee / eF), kept on the client.
	A group holds either units or buildings. Ctrl + number makes the group from what is selected (units
	first, else the one picked building; nothing selected clears it), Shift + number adds the selection
	to it (units replace a building group and the other way round), the number alone selects it, and
	pressing it twice within 400 ms (the game's doubleMs) also moves the camera there.
	Dead units and lost buildings drop out when read. No Roblox services, so the tests can run it.
]]

local ControlGroups = {}

ControlGroups.COUNT = 9 -- the game's MY
ControlGroups.DOUBLE_MS = 400

export type Group = { units: { number }, structures: { number } }
export type Groups = { list: { Group }, lastN: number, lastAt: number }

function ControlGroups.new(): Groups
	local list = {}
	for i = 1, ControlGroups.COUNT do
		list[i] = { units = {}, structures = {} }
	end
	return { list = list, lastN = -1, lastAt = 0 }
end

local function union(a: { number }, b: { number }): { number }
	local seen, out = {}, {}
	for _, list in { a, b } do
		for _, id in list do
			if not seen[id] then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	return out
end

local function alive(ids: { number }, ok: (number) -> boolean): { number }
	local out = {}
	for _, id in ids do
		if ok(id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Ctrl + n: returns how many the group now holds (0 = cleared)
function ControlGroups.set(g: Groups, n: number, units: { number }, structure: number?): number
	local grp = g.list[n]
	if not grp then
		return 0
	end
	if #units > 0 then
		g.list[n] = { units = table.clone(units), structures = {} }
	elseif structure then
		g.list[n] = { units = {}, structures = { structure } }
	else
		g.list[n] = { units = {}, structures = {} }
	end
	return #g.list[n].units + #g.list[n].structures
end

-- Shift + n: returns the new size, or nil when nothing was selected
function ControlGroups.add(g: Groups, n: number, units: { number }, structure: number?, unitOk: (number) -> boolean, structureOk: (number) -> boolean): number?
	local grp = g.list[n]
	if not grp then
		return nil
	end
	if #units > 0 then
		g.list[n] = { units = union(alive(grp.units, unitOk), units), structures = {} }
	elseif structure then
		g.list[n] = { units = {}, structures = union(alive(grp.structures, structureOk), { structure }) }
	else
		return nil
	end
	return #g.list[n].units + #g.list[n].structures
end

-- n alone: what to select (units, else the first building) and whether this was the second press
function ControlGroups.recall(g: Groups, n: number, nowMs: number, unitOk: (number) -> boolean, structureOk: (number) -> boolean): ({ number }, number?, boolean)
	local double = g.lastN == n and nowMs - g.lastAt <= ControlGroups.DOUBLE_MS
	g.lastN = n
	g.lastAt = if double then 0 else nowMs
	local grp = g.list[n]
	if not grp then
		return {}, nil, false
	end
	local units = alive(grp.units, unitOk)
	if #units > 0 then
		return units, nil, double
	end
	local sts = alive(grp.structures, structureOk)
	return {}, sts[1], double
end

return ControlGroups
