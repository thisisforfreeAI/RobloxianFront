--!strict
local Fire=if script then require(script.Parent.ForestFire) else require("./ForestFire")
local Packets=if script then require(script.Parent.Parent.Protocol.FirePackets) else require("../Protocol/FirePackets")
local World={}
function World.new(settings:any,map:any,context:any):any
	local self:any={epoch=1,seq=0,versions={},acc=0,lastTime=context.time(),sampleTime=context.time()}
	local ctx={width=map.width,trees=map.trees,forNear=map.forNear,fuelAt=map.fuelAt,random=context.random,
		waterAt=context.waterAt,firebreakAt=context.firebreakAt}
	ctx.rain=function(_x,_y)
		-- APPROX: owner-selected map-wide weather replaces original spatial weather fronts.
		local weather=context.weather();return if weather=="downpour" or weather=="storm" then 1 else 0
	end
	ctx.onFate=function(t,_fate) self.seq+=1;self.versions[t.key]=self.seq end
	self.model=Fire.new(settings,ctx)
	function self.advance(time:number)
		local delta=time-self.lastTime;assert(delta>=-1e-8 and delta<math.huge,"forest clock moved backwards");self.lastTime=time;self.acc+=math.max(0,delta)
		while self.acc+1e-9>=settings.forest.tickSec do
			self.acc=math.max(0,self.acc-settings.forest.tickSec);self.sampleTime+=settings.forest.tickSec;self.model.tick(settings.forest.tickSec)
		end
	end
	function self.blast(x:number,y:number,weapon:string,size:number?):number
		return self.model.blast(x,y,size or settings.weaponBlast[weapon] or settings.forest.blastSize,weapon)
	end
	function self.igniteAt(x:number,y:number):number return self.model.igniteAt(x,y) end
	function self.reset()
		self.model.reset();self.epoch+=1;self.seq=0;table.clear(self.versions);self.acc=0;self.lastTime=context.time();self.sampleTime=self.lastTime
	end
	function self.view(previous:any?,visible:any):(any,any)
		local reset=not previous or previous.epoch~=self.epoch;local cache={epoch=self.epoch,known=if reset then {} else table.clone(previous.known)}
		local keys={}
		for key,version in self.versions do
			local t=map.byKey[key];if version~=cache.known[key] and visible(t.x,t.y,t.cell) then table.insert(keys,key) end
		end;table.sort(keys)
		local rows={};for i=1,math.min(#keys,Packets.TREES_PER_PACKET) do
			local key=keys[i];table.insert(rows,{key,self.model.fates[key]});cache.known[key]=self.versions[key]
		end
		local actors={}
		for _,b in self.model.burns do if visible(b.x,b.y,b.cell) then table.insert(actors,{key=b.key,age=b.age,life=b.life,rate=b.ageRate or 1}) end end
		return {epoch=self.epoch,reset=reset,time=self.sampleTime,fates=Packets.trees(rows),actors=actors},cache
	end
	return self
end
return World
