--!strict
-- Source artillery-base gun/pod presentation. Does not schedule or resolve gameplay damage.
local Motion={}
local TAU=math.pi*2
function Motion.snapshot(entity:any,visible:boolean,active:boolean,previous:any?,time:number,running:boolean):(any,any)
	if not visible or entity.kind~="artybase" then return nil,nil end
	local cache={};local packet={if active then 1 else 0,time,if running then 1 else 0}
	for i,key in {"gun","pod"} do
		local before=previous and previous[key];local record=entity.artilleryVisual and entity.artilleryVisual[key]
		local sequence=if before then before.sequence else 0
		local observed=before and before.observed
		if before and record and record~=before.record then sequence+=1;observed=record end
		cache[key]={sequence=sequence,record=record,observed=observed}
		packet[i+3]=if observed then {sequence,observed.x,observed.y,observed.last,observed.fires} else {sequence,0,0,0,{}}
	end
	return packet,cache
end
function Motion.new(config:any):any
	return {slots={{heading=config.rest,up=0,sequence=nil,fires={},untilT=-math.huge},{heading=config.rest,up=0,sequence=nil,fires={},untilT=-math.huge}}}
end
function Motion.time(state:any,wall:number):number
	if state.warAt==nil then return wall end
	return state.warAt+(if state.running then math.clamp(wall-state.received,0,.2) else 0)
end
function Motion.advance(state:any,config:any,sample:any,wall:number,dt:number,visible:boolean,id:number,origin:any)
	if not visible or not sample then
		local fresh=Motion.new(config);state.slots=fresh.slots;state.warAt=nil;state.running=nil
		return
	end
	local running=sample[3]==1
	if state.warAt~=sample[2] or state.running~=running then state.warAt=sample[2];state.running=running;state.received=wall end
	local war=Motion.time(state,wall);local step=math.clamp(dt,0,.1)
	for i,key in {"gun","pod"} do
		local s=state.slots[i];local row=sample[i+3];local sequence=row[1]
		if s.sequence~=nil and sequence>s.sequence then
			s.x=row[2];s.y=row[3];s.untilT=math.max(s.untilT,row[4]+config.holdSec)
			local retained={};for _,at in s.fires do if at>war-config.recoilSec then table.insert(retained,at) end end
			for _,at in row[5] do table.insert(retained,at) end;s.fires=retained
		elseif s.sequence~=nil and sequence<s.sequence then s.untilT=-math.huge;s.fires={} end
		s.sequence=sequence
		local working=sample[1]==1 and war<=s.untilT
		local offset=config[key];local scale=origin[3]/config.cells
		local goal=if working then math.atan2(s.y-origin[2]-offset[2]*scale,s.x-origin[1]-offset[1]*scale) else config.rest+(if i==2 then .25 else -.1)+(id*.7)%.3
		local delta=(goal-s.heading+math.pi)%TAU-math.pi
		s.heading+=math.clamp(delta,-config.turn*step,config.turn*step)
		local target=if working then 1 else 0;s.up+=math.clamp(target-s.up,-step/config.raiseSec,step/config.raiseSec)
	end
end
function Motion.pose(state:any,config:any,index:number,wall:number):any
	local s=state.slots[index];local key=if index==1 then "gun" else "pod";local age=math.huge
	for _,at in s.fires do if at<=Motion.time(state,wall) then age=math.min(age,Motion.time(state,wall)-at) end end
	local duration=config.recoilSec*(if index==1 then 1 else .4)
	local recoil=age<duration
	local kick=if recoil then config.kick*(if index==1 then 1 else .25)*(1-age/duration)^2 else 0
	local stage=if index==1 and recoil and age<config.recoilSec*config.recoilShare then 3 elseif s.up>=.5 then 2 else 1
	return {part=config.parts[key][stage],heading=s.heading,x=config[key][1]-math.cos(s.heading)*kick,y=config[key][2]-math.sin(s.heading)*kick,kick=kick,stage=stage}
end
return Motion
