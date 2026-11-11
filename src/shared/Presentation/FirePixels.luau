--!strict
-- Original Ohe.char colour/material sampling. IDs are ORIGINAL atlas pixel indices so
-- repacked map chunks can preserve the game's noise pattern through a source-index adapter.
local Hash=if script then require(script.Parent.Parent.Utilities.Hash) else require("../Utilities/Hash")
local FirePixels={}
function FirePixels.house(settings:any,id:number,original:{number},stage:number,edge:boolean):{number}
	assert(stage>=0 and stage<=3 and stage%1==0,"invalid house char stage")
	if stage==0 then return {original[1],original[2],original[3],bit32.bor(original[4],1)} end
	local c=settings.houses.colours;local burn=settings.houses.burn
	local lot=Hash.seed(id,settings.charSalts.char)
	local color
	if stage<3 then
		local ink=if Hash.seed(id,settings.charSalts.tone)<.5 then c.charA else c.charB
		if lot<burn.charShare[stage] then color=ink
		else color={math.floor(original[1]*burn.sooty[stage]),math.floor(original[2]*burn.sooty[stage]),math.floor(original[3]*burn.sooty[stage])} end
		return {color[1],color[2],color[3],bit32.bor(original[4],1)}
	end
	color=if edge then c.wall elseif lot<c.ashShare then c.ash elseif lot<c.ashShare+c.beamShare then c.beam else c.floor
	return {color[1],color[2],color[3],settings.roofFrom+(if edge then 2 else 0)+1}
end
return FirePixels
