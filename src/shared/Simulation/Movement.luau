--!strict
--[[
	Movement: one fixed tick of unit movement.
	TEMP-002: straight-line movement, stopping at impassable cells. WarFront's
	pathfinding, formations and steering come later (see FEATURE_PARITY_MATRIX #31).
	Speed = units.<kind>.speed (cells/s) x movement.terrainPace.<loco>.<terrain>;
	foot units use units.<kind>.rough off plains (WarFront's foot model, simplified).
]]

local Movement = {}

export type Unit = {
	id: number,
	kind: string,
	side: number,
	x: number,
	y: number,
	heading: number,
	hp: number,
	target: { x: number, y: number }?,
}

export type Context = {
	speedOf: (kind: string) -> number,
	paceAt: (kind: string, x: number, y: number) -> number, -- 0 = impassable
}

-- Advances one unit by dt seconds. Returns true if it moved.
function Movement.step(unit: Unit, dt: number, ctx: Context): boolean
	local target = unit.target
	if not target then
		return false
	end
	local dx, dy = target.x - unit.x, target.y - unit.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 1e-3 then
		unit.target = nil
		return false
	end
	local pace = ctx.paceAt(unit.kind, unit.x, unit.y)
	local stepLen = ctx.speedOf(unit.kind) * pace * dt
	if stepLen <= 0 then
		unit.target = nil
		return false
	end
	local t = math.min(1, stepLen / dist)
	local nx, ny = unit.x + dx * t, unit.y + dy * t
	if ctx.paceAt(unit.kind, nx, ny) <= 0 then
		unit.target = nil -- blocked: stop at the edge (TEMP-002)
		return false
	end
	unit.x, unit.y = nx, ny
	unit.heading = math.atan2(dy, dx)
	if t >= 1 then
		unit.target = nil
	end
	return true
end

return Movement
