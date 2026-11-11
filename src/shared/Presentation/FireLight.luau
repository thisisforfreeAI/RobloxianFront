--!strict
-- Source Ihe/Ohe light grouping and effects burn-light envelope. Coefficients stay in GameData.
local Light={}
function Light.hash(config:any,seed:number):number
	local c=config.hash;local value=math.sin(seed*c[1]+c[2])*c[3];return value-math.floor(value)
end
function Light.groups(config:any,width:number,actors:{any},kind:string,visible:any):({any},{any})
	local c=config[kind];local across=math.ceil(width/c.blockCells);local byKey,groups={},{}
	for _,a in actors do
		if not visible(a.x,a.y,a.cell) then continue end
		local key=math.floor(a.y/c.blockCells)*across+math.floor(a.x/c.blockCells);local g=byKey[key]
		if not g then g={key=key,x=0,y=0,n=0,order=#groups+1};byKey[key]=g;table.insert(groups,g) end
		g.x+=a.x;g.y+=a.y;g.n+=1
	end
	table.sort(groups,function(a,b) return if a.n==b.n then a.order<b.order else a.n>b.n end)
	local selected={};for i=1,math.min(c.max,#groups) do
		local g=groups[i];table.insert(selected,{key=g.key,x=g.x/g.n,y=g.y/g.n,n=g.n})
	end;return selected,byKey
end
function Light.new(config:any,width:number,context:any):any
	local self:any={time=0,acc=0,lights={},due={forest={},houses={}}}
	function self.reset() self.time=0;self.acc=0;self.lights={};self.due={forest={},houses={}} end
	function self.refresh(actors:{any},kind:string)
		local c=config[kind];local selected,all=Light.groups(config,width,actors,kind,context.visible)
		local active=all
		if kind=="houses" then active={};for _,g in selected do active[g.key]=true end end
		local due=self.due[kind];for key in due do if not active[key] then due[key]=nil end end
		for _,g in selected do
			if (due[g.key] or -1)>self.time then continue end
			due[g.key]=self.time+c.sec-config.light.burn.dieSec
			local p={x=g.x,y=g.y,h=c.height,reach=math.min(c.reachMax,c.reach+(if kind=="forest" then c.perTree else c.perHouse)*g.n),
				power=c.power,color=config.light.fire,life=c.sec,curve="burn"}
			if context.emit then context.emit(p) end
			if context.enabled and not context.enabled() or not context.visible(p.x,p.y) then continue end
			local light
			if #self.lights>=config.light.max then
				local weakest=1;for i=2,#self.lights do if self.lights[i].now<self.lights[weakest].now then weakest=i end end
				if self.lights[weakest].now>=p.power then continue end;light=self.lights[weakest]
			else light={};table.insert(self.lights,light) end
			for key,value in p do light[key]=value end
			light.age=0;light.now=p.power;light.seed=(context.random or math.random)()*1000
		end
	end
	function self.step(dt:number)
		local kept={};local c=config.light
		for _,p in self.lights do
			p.age+=dt;if p.age>=p.life then continue end
			local burn=c.burn
			p.now=p.power*math.min(1,p.age/burn.riseSec)*math.min(1,(p.life-p.age)/burn.dieSec)
			p.now*=1-burn.flicker+burn.flicker*Light.hash(config,p.seed+math.floor(p.age*config.fps))
			p.now/=1+math.max(0,p.h)*c.heightFalloff;table.insert(kept,p)
		end;self.lights=kept
	end
	function self.advance(trees:{any},houses:{any},dt:number)
		assert(dt==dt and dt>=0 and dt<math.huge,"invalid fire light time step")
		self.time+=dt;self.acc+=dt
		if self.acc+1e-9>=config.tickSec then
			self.acc=self.acc%config.tickSec;self.refresh(trees,"forest");self.refresh(houses,"houses")
		end
		self.step(dt)
	end
	return self
end
return Light
