--!strict
-- Source structure gun turning, slit restriction, recoil and facing residuals. Cosmetic only.
local Motion={}
local TAU=math.pi*2
function Motion.supports(kind:string):boolean return kind=="atgun" or kind=="bunker" or kind=="sam" end
function Motion.snapshot(entity:any,visible:boolean,active:boolean,previous:any?,time:number,reload:number?,running:boolean?):(any,any)
	if not visible or not Motion.supports(entity.kind) then return nil,nil end
	local sequence=if previous then previous.sequence else 0
	local fresh=previous~=nil and entity.weaponShotAt~=nil and entity.weaponShotAt~=previous.shot
	if fresh then sequence+=1 end
	local observedAt=if fresh then entity.weaponShotAt elseif previous then previous.observedAt else nil
	local observedAim=if fresh then entity.weaponShotAim or entity.weaponAim or 0 elseif previous then previous.observedAim else nil
	local aim=entity.weaponAim
	return {if active then 1 else 0,if aim~=nil then 1 else 0,aim or 0,sequence,
		if observedAt~=nil then math.clamp(time-observedAt,0,3600) else 3600,observedAim or 0,
		if entity.kind=="sam" or running~=nil then reload or 0 else nil,
		if running~=nil then time else nil,if running~=nil then (if running then 1 else 0) else nil},
		{sequence=sequence,shot=entity.weaponShotAt,observedAt=observedAt,observedAim=observedAim}
end
function Motion.wrap(angle:number):number return (angle+math.pi)%TAU-math.pi end
function Motion.slit(angle:number,slits:{any}):number
	local best,distance=angle,math.huge
	for _,slit in slits do
		local delta=Motion.wrap(angle-slit[1]);local gap=math.abs(delta)-slit[2]
		if gap<=0 then return angle end
		if gap<distance then distance=gap;best=slit[1]+(if delta>=0 then 1 else -1)*slit[2] end
	end;return best
end
function Motion.new(config:any,id:number):any
	return {heading=id*config.initialStep%TAU,sequence=nil,shotAt=-math.huge,aim=0}
end
function Motion.samStage(config:any,age:number,reload:number):number
	local sam=config.sam
	if age>=sam.stay and age<reload-sam.up then
		return if age<sam.half or age>reload-sam.rise then 1 else 0
	end
	return 2
end
-- Shot/reload age uses war time; source idle scan and turn integration use wall time.
-- Bound prediction to two snapshot periods if the network stops delivering state.
function Motion.time(state:any,wall:number):number
	if state.warAt==nil then return wall end
	return state.warAt+(if state.running then math.clamp(wall-state.received,0,.2) else 0)
end
function Motion.advance(state:any,config:any,sample:any,clock:number,dt:number,visible:boolean,id:number)
	if not visible or not sample then
		state.heading=id*config.initialStep%TAU;state.sequence=nil;state.shotAt=-math.huge;state.aim=0;state.warAt=nil;state.running=nil
		return
	end
	if sample[8]~=nil then
		local running=sample[9]==1
		if state.warAt~=sample[8] or state.running~=running then state.warAt=sample[8];state.received=clock;state.running=running end
	else state.warAt=nil;state.running=nil end
	local war=Motion.time(state,clock)
	local sequence=sample[4] or 0
	if state.sequence~=nil and sequence>state.sequence then state.shotAt=war-(sample[5] or 0);state.aim=sample[6] or sample[3] or 0 end
	if state.sequence~=nil and sequence<state.sequence then state.shotAt=-math.huge end
	state.sequence=sequence
	state.reload=sample[7] or 0
	local goal=state.heading
	if sample[1]==1 then
		if config.kind=="sam" and Motion.samStage(config,war-state.shotAt,state.reload)<2 then goal=0
		elseif war-state.shotAt<config.holdSec then goal=state.aim
		elseif sample[2]==1 then goal=sample[3]
		else goal=id*config.initialStep%TAU+math.sin(clock/config.sweepSec*TAU+id)*config.sweep end
	end
	if config.kind=="bunker" then goal=Motion.slit(goal,config.slits) end
	local delta=Motion.wrap(goal-state.heading);local reach=config.turn*math.clamp(dt,0,.1)
	state.heading+=math.clamp(delta,-reach,reach)
end
function Motion.pose(state:any,config:any,clock:number,headings:number):any
	local age=Motion.time(state,clock)-state.shotAt
	local kick=if age>=0 and age<config.kickSec then config.kick*(1-age/config.kickSec)^2 else 0
	local fraction=(state.heading/TAU)%1;local index=math.floor(fraction*headings+.5)
	return {index=index%headings+1,residual=if headings>1 then (fraction-index/headings)*TAU else 0,
		x=config.x-math.cos(state.heading)*kick,y=config.y-math.sin(state.heading)*kick,kick=kick}
end
return Motion
