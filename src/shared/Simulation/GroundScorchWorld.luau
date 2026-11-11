--!strict
-- Shared authoritative fire scars, fog-filtered deltas and source settlement recovery.
-- APPROX: fixed one-second war-clock ticks replace the original wall-clock scheduler/hitch cap.
local Scorch=if script then require(script.Parent.GroundScorch) else require("./GroundScorch")
local Packets=if script then require(script.Parent.Parent.Protocol.GroundScorchPackets) else require("../Protocol/GroundScorchPackets")
local World={}
function World.new(config:any,map:any,context:any):any
	local self:any={epoch=1,time=context.time(),lastTime=context.time(),acc=0}
	local townAt=Scorch.towns(config.towns,map.width,map.height,context.towns or {})
	self.model=Scorch.new(config,map.width,map.height,{townAt=townAt,quiet=function(town) return self.time-town.lastHitAt>=context.quietSec end})
	function self.scar(x,y,radius,power,kind) self.model.scar(x,y,radius,power,kind) end
	function self.advance(time:number)
		local dt=time-self.lastTime;assert(dt>=-1e-8 and dt<math.huge,"scorch clock moved backwards");self.lastTime=time;self.acc+=math.max(0,dt)
		while self.acc+1e-9>=1 do self.acc=math.max(0,self.acc-1);self.time+=1;self.model.fade(1);self.model.heal(1) end
	end
	function self.reset() self.model.reset();self.epoch+=1;self.time=context.time();self.lastTime=self.time;self.acc=0 end
	function self.view(previous:any?,visible:any):(any,any)
		local reset=not previous or previous.epoch~=self.epoch
		local known=if reset then {} else table.clone(previous.known);local changes={};local values={}
		for cell in self.model.cells do values[cell]=math.floor(buffer.readf32(self.model.amount,cell*4)*255+.5) end
		for cell in known do if not values[cell] then values[cell]=0 end end
		for cell,value in values do
			if value~=(known[cell] or 0) and visible(cell%map.width+.5,math.floor(cell/map.width)+.5) then table.insert(changes,cell) end
		end;table.sort(changes)
		local rows={};for i=1,math.min(Packets.LIMIT,#changes) do
			local cell=changes[i];local value=values[cell];table.insert(rows,{cell,value});known[cell]=if value>0 then value else nil
		end
		return {epoch=self.epoch,reset=reset,rows=Packets.encode(rows)},{epoch=self.epoch,known=known}
	end
	return self
end
return World
