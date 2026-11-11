--!strict
-- Authoritative adaptation of the original visual house-fire controller. A separate RNG leaves
-- combat RNG unchanged. Only currently visible state crosses the per-view transport adapter.
local House=if script then require(script.Parent.HouseFire) else require("./HouseFire")
local Packets=if script then require(script.Parent.Parent.Protocol.FirePackets) else require("../Protocol/FirePackets")
local World={}
function World.new(settings:any,map:any,context:any):any
	local self:any={seq=0,epoch=1,paint={},acc=0,lastTime=context.time(),sampleTime=context.time()}
	local ctx=table.clone(map)
	ctx.random=context.random
	ctx.rain=function(_x,_y)
		-- APPROX: the admin weather covers the whole map; original spatial fronts remain unported.
		local weather=context.weather();return if weather=="downpour" or weather=="storm" then 1 else 0
	end
	ctx.worldTime=function() return self.sampleTime end;ctx.rebuildRules=context.rebuildRules
	ctx.townAt=function(cell)
		local index=map.townIndex(cell);return if index then context.towns[index] else nil
	end
	ctx.onStage=function(h,stage)
		if not h.id then self.seq+=1;h.id=self.seq end
		if stage>0 then for _,p in h.px do self.paint[p]=stage end end
	end
	ctx.onRestore=function(h) for _,p in h.px do self.paint[p]=nil end end
	ctx.onReset=function() table.clear(self.paint) end
	self.model=House.new(settings,ctx)
	function self.advance(time:number)
		local delta=time-self.lastTime
		assert(delta>=-1e-8 and delta<math.huge,"house world clock moved backwards")
		self.lastTime=time
		self.acc+=math.max(0,delta)
		while self.acc+1e-9>=settings.houses.tickSec do
			self.acc=math.max(0,self.acc-settings.houses.tickSec);self.sampleTime+=settings.houses.tickSec;self.model.tick(settings.houses.tickSec)
		end
	end
	function self.blast(x:number,y:number,weapon:string,size:number?):number
		return self.model.blast(x,y,size or settings.weaponBlast[weapon] or settings.houses.blastSize,weapon)
	end
	function self.igniteAt(x:number,y:number):number return self.model.igniteAt(x,y) end
	function self.reset()
		self.model.reset();self.epoch+=1;self.acc=0;self.lastTime=context.time();self.sampleTime=self.lastTime
	end
	function self.view(previous:any?,visible:(number,number)->boolean):(any,any)
		local reset=not previous or previous.epoch~=self.epoch
		local old=if reset then {known={},actors={}} else previous
		local nextView={epoch=self.epoch,known=table.clone(old.known),actors={}}
		local candidates={};local width=map.width*map.tileSize
		for p,stage in self.paint do
			if old.known[p]~=stage and visible((p%width+.5)/map.tileSize,(math.floor(p/width)+.5)/map.tileSize) then table.insert(candidates,p) end
		end
		for p in old.known do
			if not self.paint[p] and visible((p%width+.5)/map.tileSize,(math.floor(p/width)+.5)/map.tileSize) then table.insert(candidates,p) end
		end
		table.sort(candidates)
		local rows={}
		for i=1,math.min(#candidates,Packets.PIXELS_PER_PACKET) do
			local p=candidates[i];local stage=self.paint[p] or 0;table.insert(rows,{p,stage});nextView.known[p]=if stage==0 then nil else stage
		end
		local actors={};local bytes=0
		for _,h in self.model.houses do
			if not visible(h.x,h.y) then continue end
			local new=not old.actors[h.id]
			if new and bytes+#h.px*4>Packets.ROOF_BYTES_PER_PACKET then continue end
			local row={id=h.id,x=h.x,y=h.y,cell=h.cell,r=h.r,age=h.age,life=h.life,rate=h.ageRate or 1}
			if new then row.points=Packets.points(h.px);bytes+=buffer.len(row.points) end
			nextView.actors[h.id]=true;table.insert(actors,row)
		end
		return {epoch=self.epoch,reset=reset,time=self.sampleTime,actors=actors,pixels=Packets.pixels(rows)},nextView
	end
	return self
end
return World
