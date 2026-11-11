--!strict
-- Source razed/burner requests; the adapter uses the existing death/fire atlas and particle pool.
-- APPROX: independent cosmetic RNG, real-time clock, native alpha/physics and screen culling.
-- Port budgets: eight active collapses, 128 deferred dust requests, 96 requests/check; no catch-up burst.
local Effects={}
function Effects.valid(config:any):boolean
	if type(config)~="table" or type(config.collapse)~="table" or type(config.colors)~="table" then return false end
	local s=config.collapse
	for _,key in {"hqScale","thump","thumpSize","thumpLife","ringSec","ringReach","dustWall","dustSize","dustLife","dustKick","rubble","rubbleSize","rubbleLife","smokeSec","smokePerSec","smokeSize","smokeLife","smokeRise","fireSec","firePerSec","fireSize","fireLife","fireSpread"} do
		local v=s[key];if type(v)~="number" or not (v>=0 and v<math.huge) then return false end
	end
	if s.hqScale<=0 or s.ringSec<=0 or s.fireLife<=0 or s.smokeSec<=0 or s.fireSec>s.smokeSec then return false end
	for _,key in {"thumpLife","dustLife","rubbleLife","smokeLife"} do if s[key]<=0 then return false end end
	for _,key in {"thump","dustWall","rubble"} do if s[key]*math.max(1,s.hqScale)>64 then return false end end
	for _,key in {"smokePerSec","firePerSec"} do if s[key]*math.max(1,s.hqScale)>1024 then return false end end
	if type(config.embersPerSec)~="number" or not (config.embersPerSec>=0 and config.embersPerSec<=1024) then return false end
	for _,key in {"smoke","dust","dustLight","rubble"} do local v=config.colors[key];if type(v)~="number" or not (v>=0 and v<=0xffffff and v%1==0) then return false end end
	for _,key in {"textures","fireColors"} do if type(config[key])~="table" or #config[key]==0 or #config[key]>16 then return false end end
	for _,v in config.textures do if v~="blobA" and v~="blobB" and v~="blobC" then return false end end
	for _,v in config.fireColors do if type(v)~="number" or not (v>=0 and v<=0xffffff and v%1==0) then return false end end
	return true
end
function Effects.new(config:any,context:any):any
	assert(Effects.valid(config),"invalid collapse settings")
	local s,C=config.collapse,config.colors
	local random=context.random or math.random
	local self:any={time=0,active={},later={},used=0,maxActive=8,maxLater=128,maxCommands=96}
	local function range(a:number,b:number):number return a+(b-a)*random() end
	local function pick(list:{any}):any return list[math.min(#list,math.floor(random()*#list)+1)] end
	local function request(kind:string,p:any)
		if self.used>=self.maxCommands then return end
		self.used+=1;context.emit(kind,p)
	end
	local function puff(x,y,h,size,life,vx,vy,color,small,ground,rise)
		request("puff",{x=x,y=y,h=h,size=size,life=life,vx=vx or 0,vy=vy or 0,color=color or C.smoke,small=small==true,ground=ground==true,rise=rise or 1})
	end
	function self.raze(kind:string,x:number,y:number):boolean
		if #self.active>=self.maxActive or not context.visible(x,y) then return false end
		local scale=if kind=="hq" then s.hqScale else 1
		local a={x=x,y=y,scale=scale,age=0,life=s.smokeSec*scale,fire=0,smoke=0,embers=0}
		table.insert(self.active,a)
		for i=0,math.ceil(s.thump*scale)-1 do
			puff(x+range(-.5,.5)*scale,y+range(-.5,.5)*scale,.3+i*.3,s.thumpSize*scale,s.thumpLife,range(-.4,.4),range(-.4,.4))
		end
		request("spawn",{tex="ring",x=x,y=y,h=0,size=1.2*scale,life=s.ringSec,grow=s.ringReach*scale/s.ringSec,color=C.dustLight,a0=1,a1=.1,ground=true,step=true})
		local count=math.floor(s.dustWall*scale+.5)
		for i=0,count-1 do
			local angle=i/count*math.pi*2+range(-.2,.2);local speed=s.dustKick*scale*range(.7,1)
			local at=self.time+range(0,.15)
			if #self.later<self.maxLater then table.insert(self.later,{at=at,x=x,y=y,scale=scale,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed}) end
		end
		for i=0,math.ceil(s.rubble*scale)-1 do
			local angle=range(0,math.pi*2);local speed=range(.5,3)*scale
			request("spawn",{tex=if i%2==1 then "chunk" else "shard",x=x,y=y,h=.5,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=range(2,6),falls=true,
				size=s.rubbleSize*range(.6,1.2),len=range(1,1.6),life=s.rubbleLife,color=C.rubble,a0=1,a1=0,ground=true,spin=range(-4,4),erode=true})
		end;return true
	end
	function self.step(dt:number)
		if not (dt>0 and dt<math.huge) then return end
		local delta=math.min(.1,dt);self.time+=delta;self.used=0
		local later=self.later;self.later={}
		for _,d in later do
			if d.at>self.time+1e-9 then table.insert(self.later,d)
			elseif context.visible(d.x,d.y) then puff(d.x,d.y,.1,s.dustSize*d.scale,s.dustLife,d.vx,d.vy,C.dust,false,true) end
		end
		local keep={}
		for _,a in self.active do
			local dt=delta;a.age+=dt
			local shown=context.visible(a.x,a.y);local scale=a.scale
			a.smoke+=dt*s.smokePerSec*scale
			while a.smoke>=1 do
				a.smoke-=1
				if shown then puff(a.x+range(-.6*scale,.6*scale),a.y+range(-.6*scale,.6*scale),.4,s.smokeSize*scale*range(.85,1.1),s.smokeLife*range(.9,1.15),0,0,C.smoke,true,false,s.smokeRise) end
			end
			if a.age<=s.fireSec*scale then
				a.fire+=dt*s.firePerSec*scale
				while a.fire>=1 do
					a.fire-=1
					if shown then
						local size=s.fireSize*math.sqrt(scale);local spread=s.fireSpread*scale
						local tex=pick(config.textures);local x,y=a.x+range(-spread,spread),a.y+range(-spread,spread)
						local drawSize=size*range(.7,1.2);local rot=range(0,math.pi*2);local color=pick(config.fireColors)
						request("spawn",{tex=tex,x=x,y=y,h=.2,vh=2.4,size=drawSize,rot=rot,life=s.fireLife,grow=-size/s.fireLife,color=color,a0=1,a1=1,step=true,small=true,emit=true})
					end
				end
				a.embers+=dt*config.embersPerSec*scale
				while a.embers>=1 do a.embers-=1;if shown then request("embers",{x=a.x,y=a.y,h=.4,count=1,spread=s.fireSpread*scale}) end end
			end
			if a.age<a.life-1e-9 then table.insert(keep,a) end
		end;self.active=keep
	end
	function self.clear() table.clear(self.active);table.clear(self.later);self.used=0 end
	return self
end
return Effects
