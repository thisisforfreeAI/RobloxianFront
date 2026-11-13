--!strict
-- Original 12 Hz vehicle recoil translation/slide. Does not alter simulation shots or movement.
local Motion={}
local EMPTY={}
local P={tank={sec=.42,shove=.16,slide=.09,swings=1.5,rounds=1,gap=0},ifv={sec=.1,shove=.05,slide=.03,swings=.5,rounds=4,gap=.2},artillery={sec=.85,shove=.3,slide=0,swings=1.5,rounds=1,gap=0},rocket={sec=.3,shove=.09,slide=0,swings=1,rounds=8,gap=.75},scout={sec=.1,shove=.03,slide=0,swings=.5,rounds=1,gap=0}}
local function finite(v:any):boolean return type(v)=='number'and v==v and math.abs(v)<math.huge end
function Motion.supports(kind:string):boolean return P[kind]~=nil end
function Motion.snapshot(e:any,previous:any?,sim:any):(any,any)
 if not Motion.supports(e.kind) or e.alive==false then return nil,nil end
 local shot=e.firedAt;local known
 if previous and shot==previous.shot then known=previous
 elseif previous and shot~=nil and(previous.shot==nil or shot>previous.shot)then
  local aim=if e.aimX and e.aimY and e.aimX>=0 and(math.abs(e.aimX-e.x)>.05 or math.abs(e.aimY-e.y)>.05)then math.atan2(e.aimY-e.y,e.aimX-e.x)else e.turret or e.heading or 0
  local offsets=EMPTY
  if e.kind=='rocket' and sim.salvoSeed and sim.salvoPattern then
   local count=math.clamp(math.floor(sim.rules:number('artillery.rockets')+.5),1,64)
   offsets={};for _,round in sim.salvoPattern(sim.salvoSeed(e.id,shot),count,.75)do table.insert(offsets,round.at)end
  end
  known={sequence=previous.sequence+1,shot=shot,at=shot,aim=aim,offsets=offsets}
 else known={sequence=0,shot=shot,at=nil,aim=0,offsets=EMPTY}end
 local offsets=known.offsets
 if known.at==nil or sim.time-known.at>((offsets[#offsets]or 0)+1)then offsets=EMPTY end
 local army=if e.kind=="tank"or e.kind=="ifv"then (if sim.armyOf then sim.armyOf(e.side)else "coalition")else nil
 return {known.sequence,known.at or false,known.aim,offsets,army},known
end
function Motion.new():any return{sequence=nil,shotAt=-math.huge,aim=0,offsets=EMPTY,warAt=nil,running=false,received=0}end
function Motion.time(state:any,wall:number):number
 return if state.warAt~=nil then state.warAt+(if state.running then math.clamp(wall-state.received,0,.2)else 0)else 0
end
function Motion.receive(state:any,packet:any,war:any,wall:number)
 if type(packet)~='table'or not finite(packet[1])or packet[1]<0 or packet[1]%1~=0 then
  state.sequence=nil;state.shotAt=-math.huge;state.offsets=EMPTY;state.warAt=nil;state.army="coalition";return
 end
 if type(war)=='table'and finite(war[1])and war[1]>=0 and(war[2]==0 or war[2]==1)then
  local running=war[2]==1
  if state.warAt~=war[1]or state.running~=running then state.warAt=war[1];state.running=running;state.received=wall end
 else state.warAt=nil end
 local sequence=packet[1]
 state.army=if packet[5]=="republic"then "republic"else "coalition"
 if state.sequence~=nil and sequence>state.sequence then
  state.shotAt=-math.huge;state.offsets=EMPTY
  if state.warAt~=nil and finite(packet[2])and finite(packet[3])then
   local age=state.warAt-packet[2]
   if age>=0 and age<=.25 then
    state.shotAt=packet[2];state.aim=packet[3];state.offsets={}
    if type(packet[4])=='table'then local last=-1;for i=1,math.min(#packet[4],64)do local at=packet[4][i];if finite(at)and at>=0 and at>=last then table.insert(state.offsets,at);last=at end end end
   end
  end
 elseif state.sequence~=nil and sequence<state.sequence then state.shotAt=-math.huge;state.offsets=EMPTY end
 state.sequence=sequence
end
function Motion.wave(kind:string,age:number,offsets:any?):number
 local config=P[kind];if not config or not(age>=0)then return 0 end
 local since=age
 if offsets and #offsets>1 then for _,at in offsets do if at<=age then since=age-at end end
 elseif config.rounds>1 and config.gap>0 then since=age-math.min(config.rounds-1,math.floor(age/config.gap))*config.gap end
 local phase=math.floor(since*12+1e-6)/12/config.sec
 return if phase>=1 then 0 else(1-phase)^2*math.cos(phase*math.pi*config.swings)
end
function Motion.pose(state:any,kind:string,size:number,baseSize:number,wall:number):(number,number,number)
 if not state or state.shotAt==-math.huge or not P[kind]then return 0,0,0 end
 local wave=Motion.wave(kind,Motion.time(state,wall)-state.shotAt,state.offsets);local config=P[kind]
 local shove=wave*config.shove*size/math.max(1e-6,baseSize)
 return -math.cos(state.aim)*shove,-math.sin(state.aim)*shove,wave*config.slide*size
end
return Motion
