--!strict
-- Ambient traffic presentation, traced from the original fQt.cars/parked and line helpers.
-- No selectable units, combat targets, collisions, oil or authoritative simulation changes.
local Traffic={}
local function approach(a:number,b:number,amount:number):number
	return if a<b then math.min(b,a+amount) else math.max(b,a-amount)
end
function Traffic.sample(line:any,at:number):any
	local cum,pts=line.cum,line.pts
	local distance=math.clamp(at,0,line.len)
	local lo,hi=1,#cum
	while hi-lo>1 do local mid=math.floor((lo+hi)/2);if cum[mid]<=distance then lo=mid else hi=mid end end
	local length=cum[hi]-cum[lo];if length==0 then length=1 end
	local fraction=(distance-cum[lo])/length
	local x,y=pts[lo*2-1],pts[lo*2]
	local dx,dy=pts[hi*2-1]-x,pts[hi*2]-y
	return {x=x+dx*fraction,y=y+dy*fraction,dx=dx/length,dy=dy/length}
end
function Traffic.cycle(car:any,config:any,time:number):(number,boolean)
	local duration=math.abs(car.b-car.a)/config.speed
	local cycle=2*duration+car.parkA+car.parkB
	local phase=(time+car.seed*cycle)%cycle
	local away=phase>=car.parkA and phase<car.parkA+duration+car.parkB
	local p=if phase<car.parkA then 0 elseif phase<car.parkA+duration then (phase-car.parkA)/duration elseif away then 1 else 1-(phase-car.parkA-duration-car.parkB)/duration
	return car.a+(car.b-car.a)*p,away
end
function Traffic.advance(car:any,line:any,config:any,time:number,dt:number,snap:boolean,active:boolean,flee:boolean,movers:{any},onRoad:((number,number)->boolean)?,drive:any?):any
	local scheduled,away=Traffic.cycle(car,config,time)
	if snap then
		car.s=scheduled;car.alpha=if active and not flee then 1 else 0
	end
	local target=if flee or (active and away) then car.b else car.a
	-- The upgraded driver can merge into its departure lane while stationary in a curb bay.
	-- Waiting for forward motion before changing sides otherwise locks returning cars in place.
	if drive and target~=car.s then car.dir=math.sign(target-car.s) end
	local before=car.s
	local movement=(if drive then drive.speed elseif flee then config.flee else config.speed)*dt
	if drive then movement=math.min(movement,drive.limit) end
	if movement>0 and car.s~=target then
		local direction=math.sign(target-car.s)
		local look=Traffic.sample(line,car.s+direction*config.waitCells)
		local collisionLook=if drive then drive.pose(line,car.s+direction*config.waitCells,drive.lane*direction,direction) else look
		if onRoad and not onRoad(look.x,look.y) then movement=0 else
			for _,mover in movers do if (mover.x-collisionLook.x)^2+(mover.y-collisionLook.y)^2<(config.waitCells*.7)^2 then movement=0;break end end
		end
	end
	car.s=approach(car.s,target,movement)
	if car.s~=before then car.dir=math.sign(car.s-before) end
	local visible=if car.s==target and (flee or not active) then 0 else 1
	car.alpha=approach(car.alpha,visible,dt/config.fadeSec)
	if drive and drive.hide then car.alpha=0 end
	if car.alpha<=0 then return {alpha=0} end
	local p=Traffic.sample(line,car.s)
	local pull=math.max(if car.pullA then 1-math.abs(car.s-car.a)/.9 else 0,if car.pullB then 1-math.abs(car.s-car.b)/.9 else 0,0)
	local offset=((if drive then drive.lane else config.lane)+(if drive then drive.parked else config.parked)*pull)*car.dir
	car.off=if snap then offset else approach(car.off,offset,config.cross*dt)
	local pose=if drive then drive.pose(line,car.s,car.off,car.dir) else {x=p.x-p.dy*car.off,y=p.y+p.dx*car.off,heading=math.atan2(p.dy*car.dir,p.dx*car.dir)}
	pose.alpha=car.alpha;pose.model=car.model;pose.cells=if drive then drive.cells else config.cells
	return pose
end
function Traffic.new(data:any):any
	local state={data=data,towns={}}
	for _,source in data.towns do
		local town=table.clone(source);town.cars={};town.parked={}
		for _,car in source.cars do table.insert(town.cars,table.clone(car)) end
		for _,car in source.parked do table.insert(town.parked,table.clone(car)) end
		town.known=false;town.snap=true;town.integrity=100;town.garrison=0;town.hitAt=-99
		state.towns[town.id]=town
	end
	return state
end
function Traffic.applyCities(state:any,rows:{any},time:number)
	for _,row in rows do
		local town=state.towns[row[1]];if not town then continue end
		local known=type(row[10])=="number" and row[10]>=0
		if known and not town.known then town.snap=true end
		if known then
			-- Current server supplies visible/own lastHitAt. APPROX legacy-server fallback: observed
			-- integrity loss stands in for the hit timestamp, with no hidden state inferred.
			if type(row[12])=="number" then town.hitAt=row[12]
			elseif town.known and row[10]<town.integrity then town.hitAt=time end
			town.integrity=row[10];town.garrison=row[6] or 0;town.destroyed=row[11]==1
		end
		town.known=known
	end
end
function Traffic.activity(town:any,config:any,time:number,share:number,night:number):(number,number,boolean)
	if not town.known or town.destroyed or town.integrity<=0 then return 0,0,false end
	local rules=config.towns
	local strength=if town.integrity/100<config.criticalBelow then rules.critical elseif town.integrity/100<config.damagedBelow then rules.damaged else 1
	if town.garrison>0 then strength*=rules.garrisoned end
	local elapsed=time-town.hitAt
	local flee=elapsed<rules.calmSec
	local calm=if flee then 0 else math.min(1,(elapsed-rules.calmSec)/rules.returnSec)
	local density=strength*share*calm
	return density*(1-(1-rules.nightCars)*night),density,flee
end
function Traffic.step(state:any,time:number,dt:number,share:number,night:number,movers:{any},onRoad:((number,number)->boolean)?,snap:boolean?):{any}
	local out={};local config=state.data.config
	for _,town in state.towns do
		if not town.known or town.destroyed or town.integrity<=0 then continue end
		local moving,parked,flee=Traffic.activity(town,config,time,share,night)
		local reset=snap==true or town.snap
		for i,car in town.cars do
			local pose=Traffic.advance(car,state.data.lines[car.line],config.cars,time,dt,reset,(i-.5)/#town.cars<=moving,flee,movers,onRoad,if state.driving then state.driving[car] else nil)
			if pose.alpha>0 then pose.id="m"..town.id..":"..i;table.insert(out,pose) end
		end
		for i,car in town.parked do
			local target=if (i-.5)/#town.parked<=parked then 1 else 0
			car.alpha=if reset then target else approach(car.alpha,target,dt/config.cars.fadeSec)
			if car.alpha>0 then table.insert(out,{id="p"..town.id..":"..i,x=car.x,y=car.y,heading=car.heading,model=car.model,alpha=car.alpha,cells=config.cars.streetCells}) end
		end
		town.snap=false
	end
	return out
end
return Traffic
