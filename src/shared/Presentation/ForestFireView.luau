--!strict
local Packets=if script then require(script.Parent.Parent.Protocol.FirePackets) else require("../Protocol/FirePackets")
local View={}
function View.new(map:any,settings:any,context:any):any
	local self:any={epoch=nil,actors={}}
	function self.apply(packet:any):boolean
		if self.epoch and packet.epoch<self.epoch then return false end
		local reset=self.epoch~=packet.epoch or packet.reset==true
		local rows=Packets.readTrees(packet.fates,map.byKey,settings.charStages);local nextActors={}
		for _,row in packet.actors do
			local t=assert(map.byKey[row.key],"unknown forest actor");local old=if not reset then self.actors[row.key] else nil
			local a={key=t.key,x=t.x,y=t.y,cell=t.cell,size=t.size,age=row.age,life=row.life,rate=row.rate,at=packet.time}
			for _,key in {"flameAcc","smokeAcc","emberAcc"} do a[key]=if old then old[key] else context.random() end
			nextActors[t.key]=a
		end
		self.epoch=packet.epoch;self.actors=nextActors
		if reset then context.clear() end;context.fates(rows,reset);return true
	end
	function self.frame(time:number):{any}
		local actors={};for _,a in self.actors do
			a.drawAge=a.age+math.clamp(time-a.at,0,.5)*(a.rate or 1)
			if a.drawAge<a.life then table.insert(actors,a) end
		end;table.sort(actors,function(a,b) return a.key<b.key end);return actors
	end
	return self
end
return View
