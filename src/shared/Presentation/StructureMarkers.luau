--!strict
-- Port snapshot bits: 1 own damaged-facility warning, 2 visible demolition (omit ground symbol).
local Markers={}
function Markers.sample(entity:any,viewer:number,visible:boolean,inactiveReason:any):number
	if not visible or not entity.alive or entity.kind=="rig" then return 0 end
	if entity.demolishAt then return 2 end
	if viewer>0 and entity.side==viewer and inactiveReason(entity)=="damaged" then return 1 end
	return 0
end
function Markers.append(row:{any},flags:number?):{any}
	if flags and flags>0 then
		-- Preserve existing production/weapon/artillery positions and dense Roblox remote arrays.
		for i=14,16 do if row[i]==nil then row[i]=false end end
		row[17]=flags
	end
	return row
end
return Markers
