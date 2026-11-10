--!strict
-- Presentation codes in snapshot unit[17]. 0/1/2 keep the existing artillery base/set1/set2 codes.
-- The game's mte/gte puts its Republic empty look ahead of raised/packing looks whenever a missile
-- unit has fired before and its authoritative shot timer is still positive. No client reload clock.
local UnitStages = {}
UnitStages.MISSILE_LOADED = 3
UnitStages.MISSILE_SET1 = 4
UnitStages.MISSILE_SET2 = 5
UnitStages.MISSILE_EMPTY = 6

function UnitStages.artillery(missile: boolean, firedAt: number?, shotTimer: number?, raised: number?): number
	if missile and firedAt ~= nil and (shotTimer or 0) > 0 then return UnitStages.MISSILE_EMPTY end
	local stage = if (raised or 0) >= 0.999 then 2 elseif (raised or 0) >= 0.4 then 1 else 0
	return if missile then UnitStages.MISSILE_LOADED + stage else stage
end

return UnitStages
