--!strict
-- Pure geometry from the game's soldier pose height (iV) and ground-shadow projection (F7).
-- Source values/pose lengths live in the git-ignored MenFx module generated from the local install.
local MenShadows = {}

function MenShadows.height(config: any, pose: string): number
	if pose == "prone" or pose == "fallen" or pose == "base" then return config.shadow.low end
	if pose == "kneel" or pose == "plant" or pose == "set" or pose == "kick" then return config.shadow.kneel end
	return config.shadow.up
end

function MenShadows.project(config: any, kind: string, pose: string, heading: number, size: number, sunX: number, sunY: number): (number, number, number, number)
	local magnitude = math.sqrt(sunX * sunX + sunY * sunY)
	local height = size * MenShadows.height(config, pose)
	if magnitude < 1e-6 or height <= 0 then return 0, 0, 0, 1 end
	local reach = height * math.min(magnitude, config.maxReach)
	local axis = math.atan2(sunY, sunX)
	local poses = config.length[kind]
	local length = size * (if poses then poses[pose] or 1 else 1)
	local depth = size * config.art.h / config.art.w
	local along = math.max(0.001, math.abs(math.cos(heading - axis)) * length + math.abs(math.sin(heading - axis)) * depth)
	return sunX / magnitude * reach * 0.5, sunY / magnitude * reach * 0.5, axis, (along + reach) / along
end

return MenShadows
