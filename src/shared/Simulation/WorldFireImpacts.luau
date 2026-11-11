--!strict
-- Source effect onBlast adapter: mines/minefield losses use shell hits; demolition's primary
-- impact uses its original visual weapon/size; razed structures use the source collapse scale.
-- Optional config absence leaves existing direct impacts available. This adds no combat damage.
local Impacts={}
function Impacts.valid(config:any):boolean
	if type(config)~="table" or type(config.demoWeapon)~="string" or #config.demoWeapon==0 or type(config.mineWeapon)~="string" or #config.mineWeapon==0 then return false end
	for _,key in {"razedSize","hqScale","demoSize"} do local v=config[key];if type(v)~="number" or not (v>0 and v<math.huge) then return false end end
	local p=config.pops
	if p~=nil then
		if type(p)~="table" or type(p.weapon)~="string" or #p.weapon==0 or type(p.radius)~="table" then return false end
		for _,key in {"count","reach","from","to"} do local v=p[key];if type(v)~="number" or not (v>=0 and v<math.huge) then return false end end
		for i=1,2 do local v=p.radius[i];if type(v)~="number" or not (v>=0 and v<math.huge) then return false end end
		if p.count%1~=0 or p.to<p.from or p.radius[2]<p.radius[1] then return false end
	end
	return true
end
function Impacts.new(config:any?,width:number,height:number,context:any):any
	config=if Impacts.valid(config) then config else nil
	local self:any={hasEvents=config~=nil,pending={},time=if context.time then context.time() else 0}
	local function point(x,y) return type(x)=="number" and type(y)=="number" and x==x and y==y and x>=0 and y>=0 and x<width and y<height end
	function self.fire(x:any,y:any,weapon:string,size:number?,preset:string?):boolean
		if not point(x,y) then return false end
		if type(weapon)~="string" or #weapon==0 or (size~=nil and (type(size)~="number" or not (size>=0 and size<math.huge))) then return false end
		if context.water and context.water(x,y) then return false end
		context.emit(x,y,weapon,size,preset);return true
	end
	function self.event(ev:any):boolean
		if not config then return false end
		if ev.type=="mineBlast" then return self.fire(ev.x,ev.y,config.mineWeapon)
		elseif ev.type=="demoBlast" then
			if not point(ev.x,ev.y) then return false end
			local emitted=self.fire(ev.x,ev.y,config.demoWeapon,config.demoSize,"demo")
			local pops=config.pops
			if pops then
				local random=context.random or math.random
				for _=1,pops.count do
					local angle=random()*math.pi*2
					local radius=(pops.radius[1]+(pops.radius[2]-pops.radius[1])*random())*pops.reach
					local wait=pops.from+(pops.to-pops.from)*random()
					table.insert(self.pending,{at=self.time+wait,x=ev.x+math.cos(angle)*radius,y=ev.y+math.sin(angle)*radius,weapon=pops.weapon})
				end
			end
			return emitted
		elseif ev.type=="destroyed" and ev.cat=="structure" and type(ev.kind)=="string" and ev.kind~="rig" then
			if ev.kind=="minefield" then return self.fire(ev.x,ev.y,config.mineWeapon) end
			return self.fire(ev.x,ev.y,"razed",config.razedSize*(if ev.kind=="hq" then config.hqScale else 1))
		end;return false
	end
	-- APPROX: authoritative war time and an independent cosmetic RNG replace the visual timer/RNG.
	function self.advance(time:number)
		assert(time==time and time>=self.time-1e-8 and time<math.huge,"invalid fire-impact clock")
		self.time=time;local kept={}
		for _,p in self.pending do if p.at<=time then self.fire(p.x,p.y,p.weapon) else table.insert(kept,p) end end
		self.pending=kept
	end
	function self.reset() self.pending={};self.time=if context.time then context.time() else self.time end
	return self
end
return Impacts
