--!strict
-- Cosmetic crew action samples. Simulation reload/setup/packing rules stay authoritative.
local Motion={}
local PHASE={[0]='travel',[1]='setting',[2]='packing',[3]='set'}
function Motion.snapshot(e:any,time:number,running:boolean,setup:number,pack:number):any
 if not e.alive or e.kind~='at' and e.kind~='mortar' then return nil end
 local phase,progress=0,0
 if e.kind=='mortar' then
  if e.packAt and e.packAt>=0 and time<e.packAt then phase=2;progress=math.clamp(1-(e.packAt-time)/math.max(1e-6,pack),0,1)
  elseif e.path then phase=0
  else progress=math.clamp((e.still or 0)/math.max(1e-6,setup),0,1);phase=if progress>=1 then 3 else 1 end
 end
 return {math.max(0,e.shotTimer or 0),phase,progress,time,if running then 1 else 0}
end
function Motion.receive(state:any,packet:any,clock:number)
 if type(packet)~='table' or type(packet[1])~='number' or PHASE[packet[2]]==nil or type(packet[3])~='number' or type(packet[4])~='number' then
  state.packet=nil;state.war=nil;state.running=nil;return
 end
 local running=packet[5]==1
 if state.war~=packet[4] or state.running~=running then state.war=packet[4];state.running=running;state.received=clock end
 state.packet=packet
end
function Motion.sample(state:any,clock:number,since:number,setup:number,pack:number):(number?,string?,number?,number)
 local p=state and state.packet;if not p then return nil,nil,nil,since end
 -- APPROX client prediction bound, shared with other weapon presentation clocks.
 local dt=if state.running then math.clamp(clock-state.received,0,.2) else 0
 local duration=if p[2]==1 then setup elseif p[2]==2 then pack else math.huge
 return math.max(0,p[1]-dt),PHASE[p[2]],math.clamp(p[3]+dt/math.max(1e-6,duration),0,1),since+dt
end
return Motion
