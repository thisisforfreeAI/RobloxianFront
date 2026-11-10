--!strict
-- APPROX rendering policy, not game rules: screen-space resolution with hysteresis.
local TownDetail = {}
function TownDetail.stride(cellPixels: number, previous: number): number
	if previous == 1 and cellPixels >= 7 then return 1 end
	if cellPixels >= 8 then return 1 end
	if previous == 2 and cellPixels >= 3.6 then return 2 end
	if cellPixels >= 4.2 then return 2 end
	if previous == 4 and cellPixels >= 2.2 then return 4 end
	if cellPixels >= 2.8 then return 4 end
	return 0
end
function TownDetail.frame(phase: number, sunUp: number, steps: number): number
	local p = phase % 1
	local progress = if p < sunUp then p / sunUp else (p - sunUp) / (1 - sunUp)
	return math.clamp(math.floor(progress * steps + 0.5), 0, steps) + 1
end
return TownDetail
