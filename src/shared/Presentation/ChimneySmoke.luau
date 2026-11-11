--!strict
-- Ambient chimney puffs traced from the original fQt.draw/smoke. No fire or combat state.
local Smoke={}
function Smoke.poses(town:any,chimneys:{any},config:any,time:number,share:number,night:number,hash:(number,number)->number,view:any?,visible:((number,number)->boolean)?):{any}
	local out={}
	if not town.known or town.destroyed or town.integrity<=0 or share<=0 then return out end
	local daylight=1-math.min(1,night*1.6)
	if daylight<=0 then return out end
	local density=if town.integrity/100<config.criticalBelow then config.towns.critical elseif town.integrity/100<config.damagedBelow then config.towns.damaged else 1
	if town.garrison>0 then density*=config.towns.garrisoned end
	density*=share
	-- Unlike street activity, smoke is not suppressed for the post-shelling calm period.
	local smoke=config.smoke
	local wind=config.wind
	local length=math.sqrt(wind.x^2+wind.y^2);if length==0 then length=1 end
	local tick=math.floor(time*smoke.fps)/smoke.fps
	for i,site in chimneys do
		if (i-.5)/#chimneys>density then continue end
		if view and (site.x<view.x0-3 or site.x>view.x1+3 or site.y<view.y0-3 or site.y>view.y1+3) then continue end
		if visible and not visible(site.x,site.y) then continue end
		for puff=0,smoke.puffs-1 do
			local progress=tick/smoke.lifeSec+puff/smoke.puffs+site.seed
			local age=progress-math.floor(progress)
			local sequence=math.floor(progress)*smoke.puffs+puff
			local cross=(hash(sequence,i-1)-.5)*.5
			local x=site.x+(wind.x-wind.y*cross)/length*smoke.drift*age
			local y=site.y+(wind.y+wind.x*cross)/length*smoke.drift*age
			local remaining=if age<smoke.thinFrom then 1 else 1-(age-smoke.thinFrom)/(1-smoke.thinFrom)
			local cells=(smoke.size[1]+(smoke.size[2]-smoke.size[1])*age)*math.sqrt(remaining)
			local alpha=smoke.alpha*daylight*(.45+.55*remaining)
			-- The original sprite blitter skips alpha <= .02. Also avoid zero-size Roblox parts.
			if alpha<=.02 or cells<=0 then continue end
			-- APPROX fog adapter: check the drifting puff as well as its visible chimney origin.
			if visible and not visible(x,y) then continue end
			table.insert(out,{id=tostring(town.id)..":"..i..":"..puff,x=x,y=y,cells=cells,heading=hash(sequence,5)*math.pi*2,alpha=alpha})
		end
	end
	return out
end
return Smoke
