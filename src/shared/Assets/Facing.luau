--!strict
--[[
	Facing: WarFront's sprite-direction convention (recovered from the game's renderer).
	  angle  = atan2(dy, dx) in map cells, y pointing down (south). Same as unit.heading.
	  index  = round(angle / step) mod facings  -> 0 faces east (+x), indices go clockwise on screen.
	  residual = angle - index * step, wrapped to [-pi, pi): rotation applied on top of the frame.
	Roblox mapping: cell (x, y) -> world (X, Z), so a yaw of CFrame.Angles(0, -angle, 0) turns +X towards
	the heading. The camera keeps north (-Z) at the top of the screen.
]]
local Facing = {}

local TAU = 2 * math.pi

function Facing.index(angle: number, facings: number): number
	local step = TAU / facings
	return math.floor(angle / step + 0.5) % facings -- JS Math.round, Luau % is floored (never negative)
end

function Facing.residual(angle: number, index: number, facings: number): number
	local r = angle - index * (TAU / facings)
	return (r + math.pi) % TAU - math.pi
end

-- Atlas rectangle for one frame. meta is a generated Shared.Assets.Atlases module.
function Facing.rect(meta: any, animation: string, frame: number, direction: number): (number, number, number)
	local cell = meta.frames[animation][frame + 1][direction + 1]
	return cell[1], cell[2], cell[3] -- page (1-based), x, y in pixels
end

return Facing
