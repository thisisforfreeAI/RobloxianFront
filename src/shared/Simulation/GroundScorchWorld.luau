--!strict
-- Shared authoritative fire scars, fog-filtered deltas and source settlement recovery.
-- APPROX: fixed one-second war-clock ticks replace the original wall-clock scheduler/hitch cap.
local Scorch=if script then require(script.Parent.GroundScorch) else require("./GroundScorch")
local Packets=if script then require(script.Parent.Parent.Protocol.GroundScorchPackets) else require("../Protocol/GroundScorchPackets")
local World={}
function World.new(config:any,map:any,context:any):any
	local self:any={epoch=1,time=context.time(),lastTime=context.time(),acc=0}
	local townAt=Scorch.towns(config.towns,map.width,map.height,context.towns or {})
	-- Reuse this existing source settlement index for other cosmetic ground recovery.
	function self.quietAt(x:number,y:number):boolean
		local cx,cy=math.floor(x),math.floor(y)
		if cx<0 or cy<0 or cx>=map.width or cy>=map.height then return false end
		local town=townAt(cy*map.width+cx)
		return town~=nil and context.time()-town.lastHitAt>=context.quietSec
	end
	self.model=Scorch.new(config,map.width,map.height,{townAt=townAt,quiet=function(town) return self.time-town.lastHitAt>=context.quietSec end})
	function self.scar(x,y,radius,power,kind) self.model.scar(x,y,radius,power,kind) end
	-- Called only after the common impact adapter's map/water guard; no combat damage is applied.
	-- Legacy local profiles keep fire burns working until regenerated with impact/palette settings.
	function self.blast(x:number,y:number,weapon:string,size:number?,preset:string?):boolean
		local impacts=config.impacts
		if not impacts or not config.palette or not config.shapes then return false end
		local profile=if preset then impacts[preset] elseif weapon=="razed" then impacts.razed else impacts.weapons and impacts.weapons[weapon]
		if not profile or not config.shapes[profile.kind] then return false end
		local radius=if profile.fromBlastSize then size else profile.radius
		if type(radius)~="number" or not (radius>=0 and radius<math.huge) or type(profile.power)~="number" or not (profile.power>0 and profile.power<math.huge) then return false end
		if type(x)~="number" or type(y)~="number" or not (x>=0 and y>=0 and x<map.width and y<map.height) then return false end
		self.scar(x,y,radius,profile.power,profile.kind);return true
	end
	function self.advance(time:number)
		local dt=time-self.lastTime;assert(dt>=-1e-8 and dt<math.huge,"scorch clock moved backwards");self.lastTime=time;self.acc+=math.max(0,dt)
		while self.acc+1e-9>=1 do self.acc=math.max(0,self.acc-1);self.time+=1;self.model.fade(1);self.model.heal(1) end
	end
	function self.reset() self.model.reset();self.epoch+=1;self.time=context.time();self.lastTime=self.time;self.acc=0 end
	function self.view(previous:any?,visible:any):(any,any)
		local reset=not previous or previous.epoch~=self.epoch
		local known=if reset then {} else table.clone(previous.known);local changes={};local values={}
		for cell in self.model.cells do
			local amount=math.floor(buffer.readf32(self.model.amount,cell*4)*255+.5)
			values[cell]=if amount>0 then amount+buffer.readu8(self.model.tone,cell)*256 else 0
		end
		for cell in known do if not values[cell] then values[cell]=0 end end
		for cell,value in values do
			if value~=(known[cell] or 0) and visible(cell%map.width+.5,math.floor(cell/map.width)+.5) then table.insert(changes,cell) end
		end;table.sort(changes)
		local rows={};for i=1,math.min(Packets.LIMIT,#changes) do
			local cell=changes[i];local value=values[cell];table.insert(rows,{cell,value%256,math.floor(value/256)});known[cell]=if value>0 then value else nil
		end
		return {epoch=self.epoch,reset=reset,rows=Packets.encode(rows),tones=if config.palette then Packets.tones(rows) else nil},{epoch=self.epoch,known=known}
	end
	return self
end
return World
