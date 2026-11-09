--!strict
-- How map cells map onto Roblox studs. Presentation scale only; rules stay in cells.
local World = {}
World.STUDS_PER_CELL = 4
World.GROUND_Y = 0

function World.toWorld(x: number, y: number, height: number?): Vector3
	return Vector3.new(x * World.STUDS_PER_CELL, World.GROUND_Y + (height or 0), y * World.STUDS_PER_CELL)
end

function World.toCell(pos: Vector3): (number, number)
	return pos.X / World.STUDS_PER_CELL, pos.Z / World.STUDS_PER_CELL
end

return World
