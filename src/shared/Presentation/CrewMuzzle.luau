--!strict
-- Source tubeFire/backblast and mortar firing particles; gameplay/projectiles/lights are separate.
local Clock=if script then require(script.Parent.RifleFire)else require("./RifleFire")
local Crew={}
local TAU=math.pi*2
local function range(rng:()->number,a:number,b:number):number return a+rng()*(b-a)end
local function pick(rng:()->number,r:any):number return range(rng,r[1],r[2])end
local function puff(rng:()->number):string return ({"puffA","puffB","puffC"})[math.min(3,math.floor(rng()*3)+1)]end
function Crew.new(id:number):any return Clock.new(id)end
function Crew.receive(s:any,since:any,flags:number,status:number,tx:number,ty:number,war:any,wall:number,army:string?)
	Clock.receive(s,since,flags,status,tx,ty,war,wall)
	if s.pending then s.pending.army=if army=="republic"then "republic"else "coalition"end
end
function Crew.cancel(s:any)Clock.cancel(s)end
function Crew.tip(cfg:any,kind:string,squad:any,x:number,y:number,tx:number,ty:number,scale:number):any
	if kind=="at"then
		local shooter:any=nil
		for _,m in squad.men do if m.up and m.pose~="fallen"then
			if m.kind=="gunner"then shooter=m;break end
			shooter=shooter or m
		end end
		if not shooter then return nil end
		local tip=Clock.muzzle(cfg,shooter,tx,ty,scale)
		local pose=cfg.muzzle[shooter.kind];local offset=pose and (pose[shooter.pose]or pose.stand)
		if not offset then return nil end
		local rear=scale*(offset[1]-(if shooter.pose=="prone"then cfg.tubeRearProne else cfg.tubeRear))
		tip.rearX=tip.x-tip.ux*rear;tip.rearY=tip.y-tip.uy*rear
		return tip
	end
	local tube=squad.tube
	if tube then
		local offset=cfg.muzzle.tube[tube.pose];if not offset then return nil end
		local ux,uy=math.cos(tube.heading),math.sin(tube.heading)
		return {x=tube.x+(offset[1]*ux-offset[2]*uy)*scale,y=tube.y+(offset[1]*uy+offset[2]*ux)*scale,h=cfg.mortar.muzzleH,ux=ux,uy=uy}
	end
	-- Same root fallback as the source mortarMuzzle when the tube is not present.
	local heading=math.atan2(ty-y,tx-x)
	return {x=x,y=y,h=cfg.mortar.muzzleH,ux=math.cos(heading),uy=math.sin(heading)}
end
function Crew.at(cfg:any,t:any,army:string,emit:(any)->boolean,rng:()->number)
	local r=cfg.backblast;local override=cfg.backblastOverrides[army]
	if override then r=table.clone(r);for key,value in override do r[key]=value end end
	local x,y=t.x+t.ux*r.tipFlash*.25,t.y+t.uy*r.tipFlash*.25
	if not emit({tex="star",x=x,y=y,h=t.h,size=r.tipFlash,life=.1,rot=math.atan2(t.uy,t.ux),color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true})then return end
	if not emit({tex="disc",x=x,y=y,h=t.h,size=r.tipFlash*.45,life=.08,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return end
	for _=1,cfg.rocketSmoke do
		local life,size=.7,.45
		local texture=puff(rng)
		local rise=cfg.motion.rise*range(rng,.7,1.3)
		if not emit({tex=texture,x=t.x+t.ux*.3,y=t.y+t.uy*.3,h=t.h+.1,size=size,life=life,vx=t.ux*1.5,vy=t.uy*1.5,vh=rise,rot=rng()*TAU,grow=size*cfg.motion.grow/life,drag=1.2,wind=true,lean=0,ground=false,color=cfg.colors.smokeLight,color1=cfg.colors.smokeLight,a0=1,a1=0,small=true,erode=true,swell=true})then return end
	end
	x,y=t.rearX,t.rearY;local ux,uy=-t.ux,-t.uy;local heading=math.atan2(uy,ux)
	if not emit({tex="star",x=x,y=y,h=t.h,size=r.rearFlash,life=r.rearSec,rot=heading,color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true})then return end
	if not emit({tex="disc",x=x,y=y,h=t.h,size=r.rearFlash*.4,life=r.rearSec*.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return end
	for i=0,r.puffs-1 do
		local k=if r.puffs>1 then i/(r.puffs-1)else 1
		local angle=heading+(i*.618%1*2-1)*r.cone*(.35+.65*k)
		local dist=r.reach*k*.5;local speed=r.speed[1]+(r.speed[2]-r.speed[1])*k*range(rng,.8,1.1)
		local smoke=i%r.smokeEvery==r.smokeEvery-1;local size=r.size[1]+(r.size[2]-r.size[1])*k;local life=pick(rng,r.life)
		if not emit({tex=puff(rng),x=x+math.cos(angle)*dist,y=y+math.sin(angle)*dist,h=if smoke then t.h+.1 else .05,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=cfg.motion.rise*(if smoke then .4 else .1),drag=2.5,size=size,grow=size*cfg.motion.grow/life,rot=rng()*TAU,life=life,color=if smoke then r.smoke else r.dust,color1=r.pale,a0=1,a1=0,erode=true,swell=true,ground=not smoke,wind=smoke})then return end
	end
	for _=1,r.grit do
		local angle=heading+range(rng,-r.cone,r.cone);local speed=pick(rng,r.gritSpeed)
		if not emit({tex="px",x=x,y=y,h=.1,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=range(rng,1,3),falls=true,drag=1,size=range(rng,.08,.14),life=range(rng,.25,.45),color=cfg.colors.debris,a0=1,a1=1,small=true,fine=true})then return end
	end
	emit({tex="ring",x=x+ux*.2,y=y+uy*.2,h=0,size=r.ring,life=r.ringSec,grow=(r.ringTo-r.ring)/r.ringSec,color=cfg.colors.dustLight,a0=.9,a1=0,ground=true,step=true})
end
function Crew.mortar(cfg:any,t:any,emit:(any)->boolean,rng:()->number)
	local s=cfg.mortar;local ground=cfg.ground -- APPROX: source earth palette until detailed surface classes are available here.
	if not emit({tex="star",x=t.x,y=t.y,h=t.h,size=s.flash,life=s.flashSec,rot=math.atan2(t.uy,t.ux),color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true})then return end
	if not emit({tex="disc",x=t.x,y=t.y,h=t.h,size=s.flash*.45,life=s.flashSec*.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return end
	local x,y=t.x-t.ux*.12,t.y-t.uy*.12
	if not emit({tex="ring",x=x,y=y,h=0,size=s.ring,life=s.ringSec,grow=(s.ringTo-s.ring)/s.ringSec,color=ground.dustPale,a0=.9,a1=0,ground=true,step=true})then return end
	for i=0,s.dust-1 do
		local angle=i/s.dust*TAU+range(rng,-.3,.3);local speed=s.kick*range(rng,.7,1.1)
		local texture=puff(rng);local size=s.dustSize*range(rng,.8,1.2);local rot=rng()*TAU;local life=s.dustLife*ground.dustHang*range(rng,.85,1.15)
		if not emit({tex=texture,x=x+math.cos(angle)*.15,y=y+math.sin(angle)*.15,h=.05,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=.2,drag=2.4,size=size,grow=s.dustSize*cfg.motion.grow/s.dustLife,rot=rot,life=life,color=ground.dust,color1=ground.dustPale,a0=1,a1=0,ground=true,erode=true,swell=true,small=true})then return end
	end
	for i=0,s.smoke-1 do
		local life=s.smokeLife*range(rng,.85,1.2);local size=s.smokeSize*(.8+i*.25)
		local texture=puff(rng);local x,y=t.x+range(rng,-.05,.05),t.y+range(rng,-.05,.05)
		if not emit({tex=texture,x=x,y=y,h=t.h+i*.15,vh=s.rise*(1-i*.18),drag=.6,size=size,grow=size*cfg.motion.grow/life,rot=rng()*TAU,life=life,color=s.smokeColor,color1=s.smokePale,a0=1,a1=0,wind=true,erode=true,swell=true})then return end
	end
end
function Crew.step(s:any,cfg:any,kind:string,squad:any,x:number,y:number,scale:number,wall:number,hidden:(number,number)->boolean,emit:(any)->boolean,budget:any,rng:(()->number)?)
	local pending=s.pending;s.pending=nil
	if not pending or (kind~="at"and kind~="mortar") or not squad then return end
	local now=Clock.time(s,wall)
	-- APPROX network admission, matching the existing shared shot clocks: no catch-up backlog.
	if now<pending.at or now-pending.at>.25 or budget.prepares<=0 or budget.pulses<=0 or hidden(x,y)then return end
	budget.prepares-=1
	local tip=Crew.tip(cfg,kind,squad,x,y,pending.tx,pending.ty,scale)
	if not tip or hidden(tip.x,tip.y)then return end
	budget.pulses-=1
	if kind=="at"then Crew.at(cfg,tip,pending.army,emit,rng or math.random)else Crew.mortar(cfg,tip,emit,rng or math.random)end
end
return Crew
