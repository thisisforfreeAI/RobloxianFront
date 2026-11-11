--!strict
-- Original fQt pedestrian walks and oQt fleeing waves. No damageable or selectable entities.
local People={}
local function inside(view:any,x:number,y:number,margin:number):boolean
	return x>=view.x0-margin and x<=view.x1+margin and y>=view.y0-margin and y<=view.y1+margin
end
function People.walker(w:any,line:any,config:any,sample:any,time:number,dt:number,snap:boolean,enabled:boolean):any
	local target=if enabled then 1 else 0
	if snap then w.alpha=target elseif w.alpha<target then w.alpha=math.min(target,w.alpha+dt/config.fadeSec) else w.alpha=math.max(target,w.alpha-dt/config.fadeSec) end
	if w.alpha<=0 then return nil end
	local x,y,heading,frame=w.x,w.y,w.seed*math.pi*2,0
	if w.line>=0 then
		local cycle=time*config.speed/(2*w.reach)+w.seed*7
		local phase=cycle-math.floor(cycle)
		local returning=phase>=.5
		local distance=(if returning then 2-2*phase else 2*phase)*w.reach
		local p=sample(line,w.s0+distance);local dir=if returning then -1 else 1
		x=p.x-p.dy*w.side;y=p.y+p.dx*w.side
		heading=math.atan2(p.dy*dir,p.dx*dir)
		frame=if w.reach<.1 then 0 elseif math.floor(distance*config.stride)%2==1 then 1 else 2
	end
	return {group="people",x=x,y=y,heading=heading,alpha=w.alpha,cells=config.cells,model="person"..w.look..frame}
end
function People.new(trafficState:any,helpers:any,hash:any):any
	local state={world=trafficState,helpers=helpers,hash=hash,places={},lookedAt=-math.huge,lastTime=nil}
	for _,source in trafficState.data.towns do
		local walkers={}
		for _,w in source.walkers or {} do table.insert(walkers,table.clone(w)) end
		table.insert(state.places,{town=trafficState.towns[source.id],seedId=source.seedId or source.id-1,kind=source.kind,
			walkers=walkers,exits=source.exits or {},onset=-math.huge,finish=-math.huge,fightAt=-math.huge,known=false})
	end
	return state
end
function People.look(state:any,time:number,fighters:{any},age:number,view:any,visible:any)
	local rules=state.world.data.config.fleeing
	for _,u in fighters do
		if math.min(u.shotAge or math.huge,u.hitAge or math.huge)+math.max(0,age)>rules.fightSec then continue end
		if not inside(view,u.x,u.y,8) or not visible(u.x,u.y) then continue end
		for _,place in state.places do
			local town=place.town
			if town.known and (town.x-u.x)^2+(town.y-u.y)^2<=town.radius^2 then place.fightAt=time end
		end
	end
end
function People.wave(place:any,state:any,time:number,snap:boolean,view:any,visible:any):{any}
	local out={};local town=place.town
	local config=state.world.data.config;local rules=config.fleeing
	if not town.known or town.destroyed or town.integrity<=0 or #place.exits==0 then return out end
	local distance=(1-rules.startShare)*town.radius+rules.outCells
	if not inside(view,town.x,town.y,distance+1) then return out end
	if time<place.onset then place.onset=-math.huge;place.finish=-math.huge end
	local count=rules.count[place.kind];if not count then return out end
	local hit=time-town.hitAt<rules.hitSec
	if (hit or time-place.fightAt<rules.fightSec) and time>place.finish then
		place.onset=if snap and hit then town.hitAt else time
		place.finish=place.onset+(count-1)*rules.gapSec+rules.jitterSec+distance/rules.speed
	end
	if time<place.onset or time>place.finish then return out end
	local seed=math.floor(place.onset*7);local hash=state.hash
	for i=0,count-1 do
		local elapsed=time-(place.onset+i*rules.gapSec+hash(place.seedId*31+seed,i)*rules.jitterSec)
		if elapsed<=0 then continue end
		local travelled=elapsed*rules.speed;if travelled>=distance then continue end
		local exit=place.exits[math.floor(hash(place.seedId+seed,i+40)*#place.exits)+1]
		local p=state.helpers.sample(state.world.data.lines[exit.line],exit.s0+exit.dir*(rules.startShare*town.radius+travelled))
		local spread=(hash(place.seedId,i+80)-.5)*2*rules.spread
		local x,y=p.x-p.dy*spread,p.y+p.dx*spread
		if not inside(view,x,y,1) or not visible(x,y) then continue end
		local alpha=math.min(1,travelled/rules.fadeInCells,(distance-travelled)/rules.fadeOutCells)
		if alpha<=0 then continue end
		local frame=if math.floor((travelled+hash(place.seedId,i+120))*config.people.stride)%2==1 then 1 else 2
		local look=string.char(65+math.floor(hash(place.seedId,i+160)*3))
		table.insert(out,{id="f"..town.id..":"..seed..":"..i,group="people",x=x,y=y,
			heading=math.atan2(p.dy*exit.dir,p.dx*exit.dir),cells=config.people.cells,alpha=alpha,model="person"..look..frame})
	end
	return out
end
function People.step(state:any,time:number,dt:number,share:number,night:number,fighters:{any},age:number,view:any,visible:any,snap:boolean?):{any}
	local config=state.world.data.config
	if not config.people or not config.fleeing then return {} end
	local reset=snap==true or state.lastTime==nil or time<(state.lastTime or time) or time-(state.lastTime or time)>config.jumpSec
	if time<(state.lastTime or time) then
		state.lookedAt=-math.huge
		for _,p in state.places do p.onset=-math.huge;p.finish=-math.huge;p.fightAt=-math.huge end
	end
	state.lastTime=time
	if time<state.lookedAt or time-state.lookedAt>=config.fleeing.lookSec then
		state.lookedAt=time;People.look(state,time,fighters,age,view,visible)
	end
	local out={}
	for _,place in state.places do
		local town=place.town
		if not town.known or town.destroyed or town.integrity<=0 then place.known=false;continue end
		local _,density=state.helpers.activity(town,config,time,share,night)
		local walking=if night>.6 then 0 else density*(1-(1-config.towns.nightPeople)*night)
		if inside(view,town.x,town.y,town.radius+6) then
			for i,w in place.walkers do
				local p=People.walker(w,state.world.data.lines[w.line],config.people,state.helpers.sample,time,dt,reset or not place.known,(i-.5)/#place.walkers<=walking)
				if p and inside(view,p.x,p.y,1) and visible(p.x,p.y) then p.id="w"..town.id..":"..i;table.insert(out,p) end
			end
		end
		place.known=true
	end
	local fleeing=0
	for _,place in state.places do
		for _,p in People.wave(place,state,time,reset,view,visible) do
			table.insert(out,p);fleeing+=1
			if fleeing>=config.fleeing.maxShown then return out end
		end
	end
	return out
end
return People
