--!strict
-- How map cells map onto Roblox studs. Presentation scale only; rules stay in cells.
local World = {}
World.STUDS_PER_CELL = 4
World.GROUND_Y = 0

-- Yaw that lines a Top-face SurfaceGui up with the map (GUI x -> +X/east, GUI y -> +Z/south).
-- Measured in Studio on 2026-11-09 (docs/STUDIO_TESTS.md test 6): on an unrotated part the Top-face
-- GUI x runs along -Z and GUI y along +X, so drawings came out a quarter turn anticlockwise.
-- A part turned by CFrame.Angles(0, TOP_GUI_YAW, 0) has local X along world +Z and local Z along world +X.
World.TOP_GUI_YAW = -math.pi / 2

function World.toWorld(x: number, y: number, height: number?): Vector3
	return Vector3.new(x * World.STUDS_PER_CELL, World.GROUND_Y + (height or 0), y * World.STUDS_PER_CELL)
end

function World.toCell(pos: Vector3): (number, number)
	return pos.X / World.STUDS_PER_CELL, pos.Z / World.STUDS_PER_CELL
end

return World
