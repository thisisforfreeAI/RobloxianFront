--!strict
-- Source factory door/crane/weld motion. Original parameters live in the private art metadata.
local Motion={}
-- Only a visible-work flag and per-view completion pulse cross the wire, never queue contents/counts.
function Motion.snapshot(entity:any,visible:boolean,active:boolean,previous:any?):(any,any)
	if not visible or entity.kind~="factory" then return nil,nil end
	local made=entity.made or 0;local sequence=if previous then previous.sequence else 0
	if previous and made~=previous.made then sequence+=1 end
	return {if active and (entity.built or 1)>=1 and entity.queue and #entity.queue>0 then 1 else 0,sequence},{made=made,sequence=sequence}
end
function Motion.new():any return {open=0,hold=0,sequence=nil,busy=false} end
function Motion.advance(state:any,config:any,sample:any,clock:number,dt:number,visible:boolean):any
	if not visible or not sample then
		state.open=0;state.hold=0;state.sequence=nil;state.busy=false
		return state
	end
	local sequence=sample[2] or 0
	if state.sequence~=nil and sequence>state.sequence then state.hold=clock+config.doorHoldSec end
	if state.sequence~=nil and sequence<state.sequence then state.hold=0 end
	state.sequence=sequence;state.busy=sample[1]==1
	local target=if state.busy or clock<state.hold then 1 else 0
	local distance=math.min(math.abs(target-state.open),math.clamp(dt,0,.1)/config.doorSec)
	state.open+=if target>state.open then distance else -distance
	return state
end
function Motion.crane(config:any,state:any,clock:number,id:number):any
	local c=config.crane
	local wave=math.sin(if state.busy then clock/c.sec*math.pi*2+id else id*1.7)
	return {x=c.x,y=c.y+wave*c.run}
end
function Motion.door(config:any,open:number,index:number):any
	local d=config.doors[index];local part=config.door;local width=.72*(part.frame/part.cells);local height=.32*(part.frame/part.cells)
	local crop=height*(1-open)
	return {visible=open<.98,x=d[1]-d[3]/2,y=d[2]-d[4]/2,w=d[3],h=d[4]*(1-open),
		sx=(part.frame-width)/2,sy=(part.frame-height)/2+height-crop,sw=width,sh=crop}
end
function Motion.weld(config:any,clock:number,id:number,imul:any):{any}
	local c=config.weld;local frame=math.floor(clock*config.fps);local points={}
	for i=0,c.count-1 do
		local bits=imul(frame*7919+i*104729+id*31,2654435761)
		if bit32.band(bits,3)==0 then continue end
		table.insert(points,{x=c.x0+bit32.band(bit32.rshift(bits,4),255)/255*(c.x1-c.x0),y=c.y0+bit32.band(bit32.rshift(bits,12),255)/255*(c.y1-c.y0),
			size=math.max(1,c.px*(config.frame/config.cells/16))*(1+bit32.band(bit32.rshift(bits,20),1)),ink=c.inks[bit32.rshift(bits,22)%#c.inks+1]})
	end
	return points
end
return Motion
