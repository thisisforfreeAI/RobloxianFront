--!strict
-- Client transport/clock adapter; presentation RNG never feeds the authoritative fire model.
local Packets=if script then require(script.Parent.Parent.Protocol.FirePackets) else require("../Protocol/FirePackets")
local View={}
function View.new(width:number,height:number,tile:number,maxPixels:number,context:any):any
	local self:any={epoch=nil,actors={},lastTime=nil}
	local fineWidth=width*tile;local total=fineWidth*height*tile
	function self.apply(packet:any):boolean
		if self.epoch and packet.epoch<self.epoch then return false end
		local reset=self.epoch~=packet.epoch or packet.reset==true
		local rows=Packets.readPixels(packet.pixels,total)
		local nextActors={}
		for _,row in packet.actors do
			local old=if not reset then self.actors[row.id] else nil
			local points=if row.points then Packets.readPoints(row.points,total,maxPixels) elseif old then old.px else nil
			if not points then continue end
			local a=table.clone(row);a.px=points;a.points=nil;a.at=packet.time
			for _,key in {"flameAcc","smokeAcc","emberAcc"} do a[key]=if old then old[key] else context.random() end
			nextActors[a.id]=a
		end
		if reset then context.clear();self.lastTime=nil end
		self.epoch=packet.epoch;self.actors=nextActors;context.pixels(rows)
		return true
	end
	function self.frame(time:number):(any,number)
		local dt=if self.lastTime then math.clamp(time-self.lastTime,0,.5) else 0;self.lastTime=time
		local list={}
		for _,a in self.actors do
			local age=a.age+math.clamp(time-a.at,0,.5)*(a.rate or 1)
			if age<a.life then
				-- Keep source accumulators on the cached actor, without cumulatively advancing its base age.
				a.drawAge=age;table.insert(list,a)
			end
		end
		table.sort(list,function(a,b) return a.id<b.id end)
		return list,dt
	end
	function self.point(p:number):(number,number) return p%fineWidth,math.floor(p/fineWidth) end
	return self
end
return View
