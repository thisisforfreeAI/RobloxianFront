--!strict
-- Source howitzer/rocketLaunch and generic TBM muzzle particles. No gameplay/projectile scheduling.
local Heavy={}
local TAU=math.pi*2
local function range(rng:()->number,a:number,b:number):number return a+rng()*(b-a)end
local function pick(rng:()->number,r:any):number return range(rng,r[1],r[2])end
local function texture(rng:()->number,blob:boolean?):string return (if blob then {"blobA","blobB","blobC"}else {"puffA","puffB","puffC"})[math.min(3,math.floor(rng()*3)+1)]end
local function mix(a:number,b:number):number
	local result=0;for shift=0,16,8 do local x,y=bit32.extract(a,shift,8),bit32.extract(b,shift,8);result+=math.floor(x+(y-x)*.4+.5)*2^shift end;return result
end
function Heavy.puff(cfg:any,x:number,y:number,h:number,size:number,life:number,vx:number,vy:number,color:number,small:boolean,ground:boolean,rise:number,emit:(any)->boolean,rng:()->number):boolean
	local pale=if color==cfg.colors.smoke then cfg.colors.smokeLight elseif color==cfg.colors.dust then cfg.colors.dustLight else mix(color,cfg.colors.smokeLight)
	return emit({tex=texture(rng),x=x,y=y,h=h,vx=vx,vy=vy,vh=if ground then cfg.motion.rise*.15 else cfg.motion.rise*rise*range(rng,.7,1.3),size=size,life=life,rot=rng()*TAU,grow=size*cfg.motion.grow/life,drag=if ground then 1.3 else 1.2,wind=not ground,lean=0,ground=ground,color=color,color1=pale,a0=1,a1=0,small=small,erode=true,swell=true})
end
local function sparks(cfg:any,x:number,y:number,h:number,n:number,speed:any,rise:any,life:any,heading:number,cone:number,emit:(any)->boolean,rng:()->number):boolean
	for _=1,n do
		local angle=heading+range(rng,-cone,cone);local v=pick(rng,speed)
		if not emit({tex="spark",x=x,y=y,h=h,vx=math.cos(angle)*v,vy=math.sin(angle)*v,vh=pick(rng,rise),falls=true,drag=.6,size=pick(rng,cfg.sparks.size),life=pick(rng,life),color=cfg.colors.hot,color1=cfg.colors.ember,a0=1,a1=1,glow=true,emit=true,small=true,fine=true,align=true,flicker=true})then return false end
	end
	return true
end
local function groundDust(cfg:any,root:any,t:any,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.artillery;local g=cfg.groundMotion;local palette=cfg.ground -- APPROX source earth palette for land surfaces.
	for i=0,c.dust-1 do
		local angle=i/c.dust*TAU+range(rng,-.25,.25);local ux,uy=math.cos(angle),math.sin(angle)
		local front=math.max(0,ux*t.ux+uy*t.uy);local speed=c.kick*(.6+front*c.front)*range(rng,.8,1.1)
		local size=c.dustSize*(.8+front*.6)*range(rng,.8,1.2);local life=c.dustLife*range(rng,.8,1.2)
		if not emit({tex=texture(rng),x=root.x+ux*c.dustFrom,y=root.y+uy*c.dustFrom,h=g.dustHeight,vx=ux*speed,vy=uy*speed,vh=g.dustRise,drag=2.2,size=size,grow=size*g.grow/life,rot=rng()*TAU,life=life,color=palette.dust,color1=palette.dustPale,a0=1,a1=0,erode=true,swell=true,step=true,small=true,ground=true,trail=true})then return false end
	end
	return true
end
local function muzzleDust(cfg:any,t:any,emit:(any)->boolean,rng:()->number):boolean
	local c,g=cfg.muzzleDust,cfg.groundMotion;local scale=c.big;local n=math.floor(c.puffs*math.sqrt(scale)+.5)
	for i=0,n-1 do
		local angle=(i+range(rng,-.3,.3))/n*TAU;local ux,uy=math.cos(angle),math.sin(angle)
		local speed=c.kick*scale*range(rng,.75,1.1);local size=c.size*scale*range(rng,.8,1.2);local life=c.life*range(rng,.8,1.2)
		if not emit({tex=texture(rng),x=t.x+ux*c.from*scale,y=t.y+uy*c.from*scale,h=g.dustHeight,vx=ux*speed,vy=uy*speed,vh=g.dustRise,drag=2.2,size=size,grow=size*g.grow/life,rot=rng()*TAU,life=life,color=cfg.ground.dust,color1=cfg.ground.dustPale,a0=1,a1=0,erode=true,swell=true,step=true,small=true,ground=true,trail=true})then return false end
	end
	return true
end
function Heavy.howitzer(cfg:any,t:any,root:any,emit:(any)->boolean,rng:()->number,wet:((number,number)->boolean)?):boolean
	local c=cfg.artillery;local heading=math.atan2(t.uy,t.ux);local x,y=t.x+t.ux*c.flash*.2,t.y+t.uy*c.flash*.2
	if not emit({tex="star",x=x,y=y,h=t.h,size=c.flash,len=1.35,rot=heading,life=c.flashSec,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return false end
	if not emit({tex=texture(rng,true),x=t.x+t.ux*c.ball*.5,y=t.y+t.uy*c.ball*.5,h=t.h,size=c.ball,life=c.ballSec,rot=rng()*TAU,color=cfg.colors.fire,color1=cfg.colors.ember,a0=1,a1=1,step=true,pop=true,emit=true})then return true end
	if not emit({tex="disc",x=x,y=y,h=t.h,size=c.flash*.4,life=c.flashSec,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return true end
	for _,side in {1,-1}do
		local ux,uy=-t.uy*side,t.ux*side
		if not emit({tex="star",x=t.x+ux*c.brake*.35,y=t.y+uy*c.brake*.35,h=t.h,size=c.brake,len=1.6,rot=math.atan2(uy,ux),life=c.flashSec*.8,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return true end
	end
	if not sparks(cfg,x,y,t.h,cfg.sparks.muzzle*2,cfg.sparks.speed,{.5,2.5},cfg.sparks.life,heading,.45,emit,rng)then return true end
	for i=0,c.smoke-1 do
		local k=i/c.smoke;local px,py=t.x+t.ux*(.3+k*1.2)+range(rng,-.2,.2),t.y+t.uy*(.3+k*1.2)+range(rng,-.2,.2)
		if not Heavy.puff(cfg,px,py,t.h+.1,c.smokeSize*(1+k*.7),c.smokeLife*range(rng,.85,1.15),t.ux*c.smokeKick*(1-k*.6),t.uy*c.smokeKick*(1-k*.6),if i%3~=0 then cfg.colors.smokeLight else cfg.colors.smoke,false,false,1,emit,rng)then return true end
	end
	if not wet or not wet(root.x,root.y)then if not groundDust(cfg,root,t,emit,rng)then return true end end
	if not wet or not wet(t.x,t.y)then
		if not muzzleDust(cfg,t,emit,rng)then return true end
		emit({tex="ring",x=t.x,y=t.y,h=0,size=c.ringSize,grow=(c.ringTo-c.ringSize)/c.ringSec,life=c.ringSec,color=cfg.ground.dustPale,a0=1,a1=0,ground=true,step=true,trail=true})
	end
	return true
end
function Heavy.gas(cfg:any,t:any,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.artillery
	local x,y=t.x+range(rng,-.08,.08),t.y+range(rng,-.08,.08)
	return Heavy.puff(cfg,x,y,t.h+.05,c.lingerSize*range(rng,.8,1.2),c.lingerLife*range(rng,.85,1.15),t.ux*.25,t.uy*.25,cfg.colors.smokeLight,true,false,.6,emit,rng)
end
function Heavy.rocketTip(cfg:any,p:any,round:number,count:number):any
	local offset=(if round%2==0 then -1 else 1)*.4+(math.floor(round/2)-(count/2-1)/2)*.12
	local ux,uy=math.cos(p.heading),math.sin(p.heading)
	return {x=p.bodyX-uy*offset+ux*.3,y=p.bodyY+ux*offset+uy*.3,h=cfg.unitMuzzleHeight,ux=ux,uy=uy}
end
function Heavy.rocket(cfg:any,t:any,root:any,last:boolean,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.rocket;local heading=math.atan2(t.uy,t.ux)
	if not emit({tex="star",x=t.x,y=t.y,h=t.h,size=c.flash,life=.12,rot=heading,color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true})then return false end
	if not emit({tex="disc",x=t.x,y=t.y,h=t.h,size=c.flash*.5,life=.1,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return true end
	if not emit({tex="disc",x=t.x,y=t.y,h=t.h*.5,size=c.flash*1.6,life=.18,color=cfg.colors.fire,a0=.55,a1=0,glow=true,emit=true})then return true end
	for i=0,c.backblast-1 do
		local angle=math.atan2(-t.uy,-t.ux)+range(rng,-.35,.35);local speed=c.backblastSpeed*range(rng,.5,1.1)
		local x,y=t.x-t.ux*(.8+i*.25)+range(rng,-.15,.15),t.y-t.uy*(.8+i*.25)+range(rng,-.15,.15)
		if not Heavy.puff(cfg,x,y,t.h*.6,c.backblastSize*range(rng,.7,1.2),c.backblastLife*range(rng,.7,1.2),math.cos(angle)*speed,math.sin(angle)*speed,if i%3==0 then cfg.colors.smoke else cfg.colors.smokeLight,false,true,1,emit,rng)then return true end
	end
	if not sparks(cfg,t.x-t.ux*.6,t.y-t.uy*.6,t.h,c.embers,{2,6},{0,2.5},{.2,.5},math.atan2(-t.uy,-t.ux),.5,emit,rng)then return true end
	for i=0,c.cloud-1 do
		local x,y=root.x-t.ux*c.cloudBack*range(rng,.7,1.3)+range(rng,-.9,c.cloudSpread),root.y-t.uy*c.cloudBack*range(rng,.7,1.3)+range(rng,-.9,c.cloudSpread)
		if not Heavy.puff(cfg,x,y,t.h*.4,c.cloudSize*range(rng,.8,1.2),c.cloudLife*range(rng,.85,1.15),-t.ux*.35,-t.uy*.35,if i%2~=0 then cfg.colors.smokeLight else c.cloudColor,false,false,c.cloudRise,emit,rng)then return true end
	end
	if last then for _=1,c.haze do
		local x,y=root.x+range(rng,-.8,.8),root.y+range(rng,-.8,.8)
		if not Heavy.puff(cfg,x,y,t.h*.5,1.4*range(rng,.8,1.3),c.hazeLife*range(rng,.8,1.2),-t.ux*.4,-t.uy*.4,cfg.colors.smokeLight,false,false,.5,emit,rng)then break end
	end end
	return true
end
function Heavy.missile(cfg:any,root:any,heading:number,emit:(any)->boolean,rng:()->number):boolean
	local c=cfg.tbm;local ux,uy=math.cos(heading),math.sin(heading);local h=cfg.unitMuzzleHeight
	local angle=math.atan2(uy,ux)
	if c.flash>0 then
		if not emit({tex="star",x=root.x+ux*.6,y=root.y+uy*.6,h=h,size=c.flash,life=.1,rot=angle,color=cfg.colors.fire,a0=1,a1=1,step=true,emit=true})then return false end
		if not emit({tex="disc",x=root.x+ux*.6,y=root.y+uy*.6,h=h,size=c.flash*.45,life=.08,color=cfg.colors.hot,a0=1,a1=1,glow=true,step=true,emit=true})then return true end
	end
	for i=0,c.muzzleSmoke-1 do
		local x,y=root.x+ux*.8+range(rng,-.3,.3),root.y+uy*.8+range(rng,-.3,.3)
		if not Heavy.puff(cfg,x,y,h,.8+i*.15,.8,ux*3,uy*3,cfg.colors.smokeLight,true,false,1,emit,rng)then return i>0 or c.flash>0 end
	end
	return true
end
return Heavy
