--!strict
-- Observed rifle bursts and muzzle particles. Pure presentation; no simulation or gameplay RNG.
-- Private configuration comes from export_rifle_fx.cjs. Projectiles/impact rules are separate.
local Rifle = {}
local TAU = math.pi * 2
local LATE = 0.25
local function finite(n:any):boolean return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Rifle.supports(kind:string):boolean return kind=="infantry" or kind=="para" end
function Rifle.new(id:number):any return {id=id,observed=false,turn=0,received=0} end
local function clear(s:any)
	s.pending=nil;s.pulses=nil;s.haze=nil
end
function Rifle.time(s:any,wall:number):number
	return (s.war or 0)+(if s.running then math.clamp(wall-s.received,0,0.2) else 0)
end
function Rifle.receive(s:any,since:any,flags:number,status:number,aimX:number,aimY:number,war:any,wall:number)
	if type(war)~="table" or not finite(war[1]) or war[1]<0 or (war[2]~=0 and war[2]~=1) then
		clear(s);s.observed=false;s.war=nil;s.last=nil;return
	end
	local running=war[2]==1
	if s.war and war[1]<s.war then clear(s);s.observed=false;s.last=nil end
	if s.war~=war[1] or s.running~=running then s.war=war[1];s.running=running;s.received=wall end
	if status==4 then clear(s);s.observed=false;s.last=nil;return end
	-- Field 15 already supplies a capped public shot age. At the cap it is not a new shot.
	local shot=if finite(since) and since>=0 and since<9 then war[1]-since else nil
	if not s.observed then s.observed=true;s.last=shot;return end
	if shot and (not s.last or shot>s.last+1e-5) then
		s.last=shot
		if since<=LATE and bit32.btest(flags,1) and finite(aimX) and finite(aimY) then
			clear(s);s.pending={at=shot,tx=aimX,ty=aimY,turn=s.turn};s.turn+=1
		end
	end
end
-- A shared per-render-frame policy also bounds preparation work, not just stored particles.
function Rifle.newBudget():any return {prepares=0,pulses=0,particles=0,haze={}} end
function Rifle.begin(b:any,wall:number)
	b.prepares=32;b.pulses=32;b.particles=128
	local n=0
	for _,untilAt in b.haze do if untilAt>wall then n+=1;b.haze[n]=untilAt end end
	for i=#b.haze,n+1,-1 do b.haze[i]=nil end
end
function Rifle.muzzle(cfg:any,m:any,tx:number,ty:number,scale:number):any
	local aim=math.atan2(ty-m.y,tx-m.x)
	local delta=(aim-m.heading+math.pi)%TAU-math.pi
	local heading=if math.abs(delta)>cfg.men.aimSlack then aim else m.heading
	local ux,uy=math.cos(heading),math.sin(heading)
	local poses=cfg.muzzle[m.kind] or cfg.muzzle.rifle
	local at=poses[m.pose] or poses.stand
	local back=if m.pose=="prone" then cfg.proneBack*scale else 0
	return {x=m.x+(at[1]*ux-at[2]*uy)*scale-math.cos(m.heading)*back,
		y=m.y+(at[1]*uy+at[2]*ux)*scale-math.sin(m.heading)*back,
		h=cfg.men.muzzleH[m.pose] or cfg.men.muzzleH.stand,ux=ux,uy=uy}
end
local function hash(n:number):number local v=math.sin(n*12.9898+78.233)*43758.5453;return v-math.floor(v) end
function Rifle.plan(cfg:any,men:any,id:number,turn:number,tx:number,ty:number,scale:number,at:number,rng:()->number):(any,any)
	local eligible={}
	for _,m in men do if m.up and m.pose~="fallen" and m.kind~="gunner" and m.kind~="loader" then table.insert(eligible,m) end end
	local count=math.min(#eligible,cfg.men.shooters)
	if count==0 then return {},nil end
	local muzzles={}
	for i=0,count-1 do table.insert(muzzles,Rifle.muzzle(cfg,eligible[(turn+i)%#eligible+1],tx,ty,scale)) end
	local rounds=math.floor(cfg.rhythm.burst[1]+rng()*(cfg.rhythm.burst[2]+1-cfg.rhythm.burst[1]))
	rng() -- Original tracer-belt initialization consumes a cosmetic draw before scheduling.
	local pulses={}
	for i=0,rounds-1 do
		local shooter=i%count
		local delay=(shooter*cfg.men.stagger+math.floor(i/count)*cfg.rifle.gap)*(1+(rng()*2-1)*cfg.rhythm.jitter)
		if shooter>0 then delay+=hash(id*31+turn*7+shooter)*cfg.men.jitter end
		-- Preserve the source schedule's random order even though this batch draws no tracers.
		if i>0 then rng();rng() end
		table.insert(pulses,{at=at+delay,tip=muzzles[shooter+1],share=if i<count then 1 else cfg.men.follow,order=i})
	end
	-- Jitter can put a repeated round ahead of a later shooter's first round.
	table.sort(pulses,function(a,b)return if a.at==b.at then a.order<b.order else a.at<b.at end)
	return pulses,muzzles[math.min(count,math.floor(rng()*count)+1)]
end
local function range(rng:()->number,a:number,b:number):number return a+rng()*(b-a) end
local function puff(rng:()->number):string return ({"puffA","puffB","puffC"})[math.min(3,math.floor(rng()*3)+1)] end
function Rifle.flash(cfg:any,tip:any,share:number,scale:number,emit:(any)->boolean,rng:()->number):boolean
	local men,flash=cfg.men,cfg.flash
	local size=men.flash*share*flash.size
	local x,y=tip.x+tip.ux*size*0.3,tip.y+tip.uy*size*0.3
	if not emit({tex="star",x=x,y=y,h=tip.h,size=size,life=flash.sec,rot=math.atan2(tip.uy,tip.ux),color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true,small=true}) then return false end
	if not emit({tex="disc",x=x,y=y,h=tip.h,size=size*men.core,life=flash.sec*0.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true,small=true}) then return true end
	local w=men.wisp
	if not emit({tex=puff(rng),x=tip.x+tip.ux*0.1,y=tip.y+tip.uy*0.1,h=tip.h+0.05,vx=tip.ux*w.drift,vy=tip.uy*w.drift,vh=w.rise,drag=2,size=w.size,grow=w.size*cfg.grow/w.life,rot=rng()*TAU,life=w.life,color=w.color,color1=w.pale,a0=1,a1=0,wind=true,erode=true,swell=true,small=true,fine=true}) then return true end
	local brass=men.brass
	local speed=range(rng,brass.speed[1],brass.speed[2])
	emit({tex="px",x=tip.x-tip.ux*scale*0.5,y=tip.y-tip.uy*scale*0.5,h=tip.h+0.05,vx=-tip.uy*speed-tip.ux*speed*0.3,vy=tip.ux*speed-tip.uy*speed*0.3,vh=range(rng,brass.rise[1],brass.rise[2]),falls=true,size=brass.size,life=range(rng,brass.life[1],brass.life[2]),color=brass.color,a0=1,a1=1,spin=range(rng,-12,12),small=true,fine=true})
	return true
end
local function haze(cfg:any,tip:any,emit:(any)->boolean,rng:()->number):number?
	local h=cfg.haze
	local life,size=range(rng,h.life[1],h.life[2]),range(rng,h.size[1],h.size[2])
	if emit({tex=puff(rng),x=tip.x+tip.ux*0.35+range(rng,-0.2,0.2),y=tip.y+tip.uy*0.35+range(rng,-0.2,0.2),h=tip.h,vx=tip.ux*0.5,vy=tip.uy*0.5,vh=h.rise,drag=0.8,size=size,grow=size*(h.grow-1)/life,rot=rng()*TAU,life=life,color=h.color,color1=h.pale,a0=h.alpha,a1=0,wind=true,erode=true,swell=true}) then return life end
	return nil
end
function Rifle.step(s:any,cfg:any,men:any,scale:number,wall:number,hidden:(number,number)->boolean,emit:(any)->boolean,budget:any,rng:(()->number)?)
	local random=rng or math.random
	local now=Rifle.time(s,wall)
	if s.pending then
		local pending=s.pending;s.pending=nil
		if now-pending.at>LATE or now<pending.at or budget.prepares<=0 then clear(s);return end
		budget.prepares-=1
		s.pulses,s.haze=Rifle.plan(cfg,men,s.id,pending.turn,pending.tx,pending.ty,scale,now,random)
	end
	if not s.pulses then return end
	local remaining=0
	for i=1,#s.pulses do
		local pulse=s.pulses[i]
		if pulse.at>now+1e-6 then remaining+=1;s.pulses[remaining]=pulse;continue end
		-- Expired or over-budget flashes are dropped, never replayed as a later backlog.
		if now-pulse.at<=0.1 and budget.pulses>0 and not hidden(pulse.tip.x,pulse.tip.y) then
			budget.pulses-=1
			if Rifle.flash(cfg,pulse.tip,pulse.share,scale,emit,random) and s.haze then
				if #budget.haze<cfg.haze.max and not hidden(s.haze.x,s.haze.y) then local life=haze(cfg,s.haze,emit,random);if life then table.insert(budget.haze,wall+life) end end
				s.haze=nil
			end
		end
	end
	for i=#s.pulses,remaining+1,-1 do s.pulses[i]=nil end
	if remaining==0 then clear(s) end
end
function Rifle.cancel(s:any) clear(s) end
return Rifle
