--!strict
-- Tank/IFV muzzle primitives from the source effects. Uses existing observed recoil and shared pool.
-- Ground dust/scorch, dynamic lights, shake and projectiles are separate presentation work.
local Muzzle={}
local TAU=math.pi*2
local function finite(n:any):boolean return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function range(rng:()->number,a:number,b:number):number return a+rng()*(b-a) end
local function pick(rng:()->number,r:any):number return range(rng,r[1],r[2]) end
local function texture(rng:()->number,blob:boolean?):string
	return (if blob then {"blobA","blobB","blobC"} else {"puffA","puffB","puffC"})[math.min(3,math.floor(rng()*3)+1)]
end
local function mix(a:number,b:number,k:number):number
	local result=0
	for shift=0,16,8 do local x,y=bit32.extract(a,shift,8),bit32.extract(b,shift,8);result+=math.floor(x+(y-x)*k+.5)*2^shift end
	return result
end
local function puff(cfg:any,x:number,y:number,h:number,size:number,life:number,vx:number,vy:number,rise:number,emit:(any)->boolean,rng:()->number):boolean
	local color=cfg.colors.smokeLight
	return emit({tex=texture(rng),x=x,y=y,h=h,vx=vx,vy=vy,vh=cfg.motion.rise*rise*range(rng,.7,1.3),size=size,life=life,rot=rng()*TAU,grow=size*cfg.motion.grow/life,drag=1.2,wind=true,lean=0,ground=false,color=color,color1=mix(color,cfg.colors.smokeLight,.4),a0=1,a1=0,small=true,erode=true,swell=true})
end
function Muzzle.supports(kind:string):boolean return kind=="tank" or kind=="ifv" end
function Muzzle.new():any return {sequence=nil,pose={}} end
function Muzzle.cancel(s:any) s.pending=nil;s.events=nil;s.fired=false;s.distance=nil end
function Muzzle.receive(s:any,ride:any,tx:number?,ty:number?)
	if not ride or ride.warAt==nil or ride.sequence==nil then Muzzle.cancel(s);s.sequence=nil;return end
	if s.sequence~=nil and ride.sequence>s.sequence then
		Muzzle.cancel(s)
		if finite(ride.shotAt) then s.pending={at=ride.shotAt,army=ride.army or "coalition",tx=tx,ty=ty} end
	elseif s.sequence~=nil and ride.sequence<s.sequence then Muzzle.cancel(s) end
	s.sequence=ride.sequence
end
-- Written once per frame into the view's reused record; geometry comes from the actual drawn turret.
function Muzzle.place(s:any,x:number,y:number,barrelX:number,barrelY:number,heading:number)
	local p=s.pose;p.x=x;p.y=y;p.barrelX=barrelX;p.barrelY=barrelY;p.heading=heading
end
function Muzzle.tip(cfg:any,kind:string,pose:any,distance:number?):any
	local reach=math.min(cfg.gun[kind],(distance or math.huge)*.5)
	local ux,uy=math.cos(pose.heading),math.sin(pose.heading)
	return {x=pose.barrelX+ux*reach,y=pose.barrelY+uy*reach,h=cfg.gunHeight,ux=ux,uy=uy}
end
function Muzzle.tank(cfg:any,tip:any,army:string,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.tank;local nation=cfg.factions[army] or cfg.factions.coalition
	local flash,ball=c.flash*nation.flash,c.ball*nation.ball
	local rot=math.atan2(tip.uy,tip.ux)
	local x,y=tip.x+tip.ux*flash*.2,tip.y+tip.uy*flash*.2
	if not emit({tex="star",x=x,y=y,h=tip.h,size=flash,len=1.3,rot=rot,life=c.flashSec,color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true}) then return false end
	if not emit({tex="disc",x=x,y=y,h=tip.h,size=flash*.42,life=c.flashSec*.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true}) then return true end
	if not emit({tex=texture(rng,true),x=tip.x+tip.ux*ball*.5,y=tip.y+tip.uy*ball*.5,h=tip.h,size=ball,life=c.ballSec,rot=rng()*TAU,color=cfg.colors.fire,color1=cfg.colors.ember,a0=1,a1=1,step=true,pop=true,emit=true}) then return true end
	if not emit({tex="disc",x=tip.x+tip.ux*c.dome*.25,y=tip.y+tip.uy*c.dome*.25,h=tip.h,size=c.dome*.3,grow=c.dome*.7/c.domeSec,life=c.domeSec,color=cfg.colors.dustLight,a0=c.domeAlpha,a1=0,step=true}) then return true end
	for _=1,cfg.sparks.muzzle do
		local a=rot+range(rng,-.5,.5);local speed=pick(rng,cfg.sparks.speed)
		if not emit({tex="spark",x=x,y=y,h=tip.h,vx=math.cos(a)*speed,vy=math.sin(a)*speed,vh=range(rng,.5,2),falls=true,drag=.6,size=pick(rng,cfg.sparks.size),life=pick(rng,cfg.sparks.life),color=cfg.colors.hot,color1=cfg.colors.ember,a0=1,a1=1,glow=true,emit=true,small=true,fine=true,align=true,flicker=true}) then return true end
	end
	for i=0,c.smoke-1 do
		local k=i/c.smoke
		local px,py=tip.x+tip.ux*(.2+k*.8)+range(rng,-.15,.15),tip.y+tip.uy*(.2+k*.8)+range(rng,-.15,.15)
		local life=c.smokeLife*range(rng,.85,1.15)
		if not puff(cfg,px,py,tip.h,c.smokeSize*(1+k*.6),life,tip.ux*c.smokeKick*(1-k*.5),tip.uy*c.smokeKick*(1-k*.5),1,emit,rng) then break end
	end
	return true
end
function Muzzle.ifv(cfg:any,tip:any,round:number,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.ifv
	local flash=c.flash*(if round==0 then 1 else c.follow)
	local x,y=tip.x+tip.ux*flash*.25,tip.y+tip.uy*flash*.25
	if not emit({tex="star",x=x,y=y,h=tip.h,size=flash,len=c.flashLen,life=c.flashSec,rot=math.atan2(tip.uy,tip.ux),color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true,small=true}) then return false end
	if not emit({tex="disc",x=x,y=y,h=tip.h,size=flash*.4,life=c.flashSec*.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true,small=true}) then return true end
	if not puff(cfg,tip.x+tip.ux*.3,tip.y+tip.uy*.3,tip.h,flash*.3,.6,tip.ux*1.5,tip.uy*1.5,1,emit,rng) then return true end
	local px,py=tip.x+tip.ux*.4+range(rng,-.1,.1),tip.y+tip.uy*.4+range(rng,-.1,.1)
	if not puff(cfg,px,py,tip.h,c.smoke*range(rng,.8,1.2),.8,tip.ux*1.6,tip.uy*1.6,1,emit,rng) then return true end
	local cases=c.cases;local rightX,rightY=-tip.uy,tip.ux
	for _=1,cases.n do
		local angle=math.atan2(rightY,rightX)+range(rng,-.35,.35);local speed=pick(rng,cases.speed)
		if not emit({tex="shard",x=tip.x-tip.ux*cases.at+rightX*cases.out,y=tip.y-tip.uy*cases.at+rightY*cases.out,h=tip.h,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=pick(rng,cases.rise),falls=true,drag=1.5,size=cases.size,len=cases.len,rot=rng()*TAU,spin=range(rng,-14,14),life=cases.life,color=cases.color,color1=cases.shade,a0=1,a1=1,small=true,fine=true}) then break end
	end
	return true
end
function Muzzle.breath(cfg:any,tip:any,kind:string,emit:(any)->boolean,rng:()->number)
	local c=if kind=="tank" then cfg.tank.evacuator else cfg.ifv.breath
	for i=0,c.puffs-1 do
		local x,y,size,life,kick,rise
		if kind=="tank" then
			x=tip.x+tip.ux*(.15+i*.12)+range(rng,-.06,.06);y=tip.y+tip.uy*(.15+i*.12)+range(rng,-.06,.06)
			size=c.size*range(rng,.8,1.3);life=c.life*range(rng,.85,1.15);kick=c.kick*(1-i*.2);rise=1
		else
			x=tip.x+tip.ux*(.1+i*.1)+range(rng,-.04,.04);y=tip.y+tip.uy*(.1+i*.1)+range(rng,-.04,.04)
			size=c.size*range(rng,.8,1.3);life=c.life*range(rng,.85,1.15);kick=c.kick*(1-i*.3);rise=.6
		end
		if not puff(cfg,x,y,tip.h,size,life,tip.ux*kick,tip.uy*kick,rise,emit,rng) then break end
	end
end
function Muzzle.step(s:any,ride:any,cfg:any,kind:string,now:number,hidden:(number,number)->boolean,emit:(any)->boolean,budget:any,rng:(()->number)?)
	if not Muzzle.supports(kind) or not ride or ride.warAt==nil or not finite(now) then Muzzle.cancel(s);return end
	local pose=s.pose
	if pose.x==nil then return end
	if hidden(pose.x,pose.y) then Muzzle.cancel(s);return end
	local random=rng or math.random
	if s.pending then
		local pending=s.pending;s.pending=nil
		if now<pending.at or now-pending.at>.25 or budget.prepares<=0 then Muzzle.cancel(s);return end
		budget.prepares-=1;s.army=pending.army
		if finite(pending.tx) and finite(pending.ty) then s.distance=math.sqrt((pending.tx-pose.x)^2+(pending.ty-pose.y)^2) end
		local events={}
		if kind=="tank" then
			table.insert(events,{at=pending.at,round=0,first=true});table.insert(events,{at=pending.at+cfg.tank.evacuator.delay,gas=true})
		else
			for i=0,cfg.ifv.rounds-1 do table.insert(events,{at=pending.at+i*cfg.ifv.gap,round=i,first=i==0}) end
			table.insert(events,{at=pending.at+(cfg.ifv.rounds-1)*cfg.ifv.gap+cfg.ifv.breath.delay,gas=true})
		end
		s.events=events
	end
	if not s.events then return end
	local tip:any=nil
	local remaining=0
	for i=1,#s.events do
		local event=s.events[i]
		if event.at>now+1e-6 then remaining+=1;s.events[remaining]=event;continue end
		if now-event.at>(if event.first then .25 else .1) or budget.pulses<=0 or (event.gas and not s.fired) then continue end
		tip=tip or Muzzle.tip(cfg,kind,pose,s.distance)
		if hidden(tip.x,tip.y) then continue end
		budget.pulses-=1
		if event.gas then Muzzle.breath(cfg,tip,kind,emit,random)
		else local accepted=if kind=="tank" then Muzzle.tank(cfg,tip,s.army,emit,random) else Muzzle.ifv(cfg,tip,event.round,emit,random);s.fired=s.fired or accepted end
	end
	for i=#s.events,remaining+1,-1 do s.events[i]=nil end
	if remaining==0 then Muzzle.cancel(s) end
end
return Muzzle
