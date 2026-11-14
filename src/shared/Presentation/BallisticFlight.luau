--!strict
-- Cosmetic source projectile curves/trails. Never schedules a hit or changes simulation RNG.
local Hash=if script then require(script.Parent.Parent.Utilities.Hash)else require('../Utilities/Hash')
local Tracer=if script then require(script.Parent.TracerFlight)else require('./TracerFlight')
local Flight={MAX=32,TRAIL_ATTEMPTS=32,PER_FLIGHT=4}
local TAU=math.pi*2
local WEAPONS={at='rocket',mortar='mortar',artillery='shell',rocket='salvo'}
local function finite(n:any):boolean return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function range(rng:any,a:number,b:number):number return a+rng()*(b-a)end
local function texture(rng:any):string return ({'puffA','puffB','puffC'})[math.min(3,math.floor(rng()*3)+1)]end
local function flicker(n:number):number local v=math.sin(n*12.9898+78.233)*43758.5453;return v-math.floor(v)end
function Flight.target(cfg:any,id:number,at:number,round:number,tx:number,ty:number,spread:number?):(number,number)
 local state=bit32.bxor(Hash.imul(id+1,2654435761),Hash.imul(math.floor(at*1000+.5)+1,2246822507))
 local function nextRandom():number
  state=(state+1831565813)%4294967296;local value=Hash.imul(bit32.bxor(state,bit32.rshift(state,15)),bit32.bor(1,state))
  value=bit32.bxor((value+Hash.imul(bit32.bxor(value,bit32.rshift(value,7)),bit32.bor(61,value)))%4294967296,value)
  return bit32.bxor(value,bit32.rshift(value,14))/4294967296
 end
 local angle,radius=0,0
 for i=0,round do if i>0 then nextRandom()end;angle=nextRandom()*TAU;radius=math.sqrt(nextRandom())end
 local reach=spread or cfg.salvo.spread
 return tx+math.cos(angle)*radius*reach,ty+math.sin(angle)*radius*reach
end
function Flight.shot(cfg:any,event:any,now:number):any?
 if type(cfg)~='table'or type(cfg.profiles)~='table'then return nil end
 local weapon=WEAPONS[event.kind];if not weapon or event.weapon=='tbm'or not finite(event.tx)or not finite(event.ty)then return nil end
 local tx,ty=event.tx,event.ty
 if weapon=='salvo'then
  if not finite(event.id)or event.id<1 or event.id%1~=0 or not finite(event.salvoAt)or not finite(event.round)or event.round<0 or event.round>=64 or event.round%1~=0 or not finite(event.spread)or event.spread<0 or event.spread>64 then return nil end
  tx,ty=Flight.target(cfg,event.id,event.salvoAt,event.round,tx,ty,event.spread)
 end
 return {config=cfg,weapon=weapon,x=event.x,y=event.y,h=event.h,tx=tx,ty=ty,targetH=0,at=event.at,now=now,seed=(event.id or 0)*17+(event.round or 0)*31}
end
function Flight.plan(p:any):any?
 for _,key in {'x','y','h','tx','ty','targetH','at','now','seed'}do if not finite(p[key])then return nil end end
 local cfg=p.config;local c=cfg and cfg.profiles and cfg.profiles[p.weapon];if type(c)~='table'then return nil end
 for _,key in {'flame','colors','motion','contrail','thread'}do if type(cfg[key])~='table'then return nil end end
 if not finite(cfg.heightFactor)or not finite(cfg.tickHz)or p.at<0 or p.now<0 then return nil end
 for _,key in {'speed','length','width','arc','arcMax','trail','trailSize','trailLife'}do if not finite(c[key])then return nil end end
 if c.speed<=0 or c.speed>100 or c.width<=0 or c.width>4 or c.length<=0 or c.length>8 or c.arc<0 or c.arc>4 or c.arcMax<0 or c.arcMax>64 or c.trail<0 or c.trail>100 or p.h<0 or p.h>64 or p.targetH<0 or p.targetH>64 then return nil end
 if c.trailSize<0 or c.trailSize>8 or c.trailLife<0 or c.trailLife>12 or c.trail>0 and c.trailLife<=0 then return nil end
 local dx,dy=p.tx-p.x,p.ty-p.y;local distance=math.max(.01,math.sqrt(dx*dx+dy*dy));local life=distance/c.speed
 if distance>512 or life>24 or p.now<p.at or p.now-p.at>=life then return nil end
 local arc=if c.arc>0 then math.min(c.arcMax,c.arc*distance)elseif c.trail>0 then math.min(.8,distance*.04)else 0
 local f={config=cfg,profile=c,weapon=p.weapon,x=p.x,y=p.y,h=p.h,targetH=p.targetH,dx=dx,dy=dy,distance=distance,life=life,arc=arc,at=p.at,seed=p.seed,last=p.now,acc=0,motor=0,pose={}}
 local pose=Flight.pose(f,p.now);f.prevX=if p.now==p.at then p.x else pose.tailX;f.prevY=if p.now==p.at then p.y else pose.tailY;f.prevH=if p.now==p.at then p.h else pose.tailH
 return f
end
function Flight.slots(f:any):number return if f.profile.trail>0 then 3 else 2 end
function Flight.pose(f:any,now:number):any
 local p=f.pose;if p.now==now then return p end;p.now=now
 local c,S,H=f.profile,f.config.flame,f.config.heightFactor;local age=math.max(0,now-f.at);local t=math.min(1,age/f.life)
 p.x=f.x+f.dx*t;p.y=f.y+f.dy*t;p.h=f.h+(f.targetH-f.h)*t+f.arc*4*t*(1-t)
 local rise=f.targetH-f.h+f.arc*4*(1-2*t);local projected=math.max(.2,math.sqrt(f.dx*f.dx+(f.dy-rise*H)^2))
 p.ux=f.dx/projected;p.uy=f.dy/projected;p.uh=rise/projected;p.rot=math.atan2(f.dy-rise*H,f.dx)
 local half=c.length*.5;p.tailX=p.x-p.ux*half;p.tailY=p.y-p.uy*half;p.tailH=p.h-p.uh*half
 p.flameLen=S.flameLength*(1-S.flameFlicker+S.flameFlicker*flicker(math.floor(age*f.config.tickHz*2)+f.seed))
 local reach=half+c.width*S.flameWidth*p.flameLen/2
 p.flameX=p.x-p.ux*reach;p.flameY=p.y-p.uy*reach;p.flameH=p.h-p.uh*reach
 return p
end
function Flight.apply(p:any,now:number,shadowShare:number?):boolean
 local f=p.ballistic;p.age=math.max(0,now-f.at);if p.age>=f.life then return false end
 local pose=Flight.pose(f,now);local c=f.profile
 if p.ballisticRole=='flame'then p.x=pose.flameX;p.y=pose.flameY;p.h=pose.flameH;p.len=pose.flameLen;p.size=c.width*f.config.flame.flameWidth;p.rot=pose.rot;p.alpha=1
 else
  p.x=pose.x;p.y=pose.y
  if p.ballisticRole=='shadow'then p.h=0;p.rot=math.atan2(f.dy,f.dx);p.alpha=if pose.h>.2 then .35*(shadowShare or 1)else 0
  else p.h=pose.h;p.rot=pose.rot;p.alpha=1 end
 end
 p.drawSize=p.size;p.tint=p.color;return true
end
function Flight.particle(f:any,role:string,now:number):any
 local c=f.profile;local p={tex=if role=='flame'then 'streak'else 'shard',x=f.x,y=f.y,h=f.h,size=c.width*(if role=='shadow'then 1.2 elseif role=='flame'then f.config.flame.flameWidth else 1),len=if role=='flame'then f.config.flame.flameLength else c.length/c.width,life=f.life,color=if role=='shadow'then 0 elseif role=='flame'then f.config.colors.fire else f.config.colors.shell,a0=1,a1=1,ground=role=='shadow',glow=role=='flame',emit=role=='flame',ballistic=f,ballisticRole=role,ballisticBody=role=='body'}
 Flight.apply(p,now);return p
end
function Flight.visible(p:any,hidden:any):boolean
 local f=p.ballistic;if p.alpha<=0 or hidden(f.x,f.y)or hidden(p.x,p.y)then return false end
 local pose=f.pose;local half=p.size*p.len/2;local ux,uy=pose.ux,pose.uy
 if p.ballisticRole=='shadow'then ux=f.dx/f.distance;uy=f.dy/f.distance end
 return Tracer.segment(p.x-ux*half,p.y-uy*half,p.x+ux*half,p.y+uy*half,hidden)
end
local function send(f:any,p:any,hidden:any,emit:any,budget:any):boolean
 if budget.remaining<=0 or f.frameSent>=Flight.PER_FLIGHT then return false end
 budget.remaining-=1;f.frameSent+=1;if hidden(p.x,p.y)then return false end;return emit(p,f.tag)
end
function Flight.trails(f:any,now:number,hidden:any,emit:any,budget:any,rng:any)
 local dt=now-f.last;f.last=now;local pose=Flight.pose(f,now)
 if dt<=0 then return end
 if budget.remaining<=0 or dt>.100001 or now<f.at or now>=f.at+f.life or hidden(f.x,f.y)or hidden(pose.x,pose.y)or hidden(pose.tailX,pose.tailY)then
  f.acc=0;f.motor=0;f.prevX=pose.tailX;f.prevY=pose.tailY;f.prevH=pose.tailH;return
 end
 f.frameSent=0
 local cfg,c=f.config,f.profile
 if f.weapon=='salvo'then
  local Z=cfg.contrail;local dx,dy,dh=pose.tailX-f.prevX,pose.tailY-f.prevY,pose.tailH-f.prevH
  if math.sqrt(dx*dx+dy*dy+dh*dh)>=Z.step then
   local projected=math.sqrt(dx*dx+(dy-dh*cfg.heightFactor)^2)
   if Tracer.segment(f.prevX,f.prevY,pose.tailX,pose.tailY,hidden)then send(f,{tex='px',x=f.prevX+dx/2,y=f.prevY+dy/2,h=f.prevH+dh/2,size=Z.width,grow=Z.grow,len=(projected*Z.overlap+Z.width)/Z.width,rot=math.atan2(dy-dh*cfg.heightFactor,dx),life=Z.life*range(rng,.9,1.1),wind=true,color=Z.color,color1=Z.pale,a0=Z.alpha,a1=0},hidden,emit,budget)end
   f.prevX=pose.tailX;f.prevY=pose.tailY;f.prevH=pose.tailH
  end
  f.acc+=dt*Z.wisps;local count=math.floor(f.acc);f.acc%=1
  for _=1,math.min(count,Flight.PER_FLIGHT)do
   if not send(f,{tex=texture(rng),x=pose.tailX+range(rng,-.08,.08),y=pose.tailY+range(rng,-.08,.08),h=pose.tailH,size=Z.wispSize*range(rng,.8,1.2),grow=Z.wispSize,rot=rng()*TAU,life=Z.wispLife*range(rng,.8,1.2),wind=true,drag=1,color=Z.color,color1=Z.pale,a0=1,a1=0,erode=true,step=true,small=true,fine=true},hidden,emit,budget)then break end
  end
 elseif c.trail>0 then
  f.acc+=dt*c.trail;local count=math.floor(f.acc);f.acc%=1
  for _=1,math.min(count,Flight.PER_FLIGHT)do
   local x,y=pose.tailX+range(rng,-.15,.15),pose.tailY+range(rng,-.15,.15);local tex=texture(rng);local rise=cfg.motion.rise*range(rng,.7,1.3)
   if not send(f,{tex=tex,x=x,y=y,h=pose.tailH,size=c.trailSize,life=c.trailLife,vx=0,vy=0,vh=rise,rot=rng()*TAU,grow=c.trailSize*cfg.motion.grow/c.trailLife,drag=1.2,wind=true,lean=0,ground=false,color=cfg.colors.smokeLight,color1=cfg.colors.smokeLight,a0=1,a1=0,small=true,erode=true,swell=true},hidden,emit,budget)then break end
  end
 elseif f.weapon=='shell'then
  local T=cfg.thread;f.acc+=dt*T.rate;local count=math.floor(f.acc);f.acc%=1
  for _=1,math.min(count,Flight.PER_FLIGHT)do
   if not send(f,{tex=texture(rng),x=pose.x,y=pose.y,h=pose.h,size=T.size,grow=T.size/T.life,rot=rng()*TAU,life=T.life,color=T.color,color1=cfg.colors.smokeLight,a0=1,a1=0,erode=true,wind=true,small=true,fine=true},hidden,emit,budget)then break end
  end
 end
 if c.trail>0 then
  f.motor+=dt
  if f.motor>=cfg.flame.motorSec then
   f.motor=0;local angle=math.atan2(-f.dy,-f.dx)+range(rng,-.6,.6);local speed=range(rng,2,5);local rise=range(rng,-1,2);local size=range(rng,cfg.flame.size[1],cfg.flame.size[2]);local life=range(rng,cfg.flame.impactLife[1],cfg.flame.impactLife[2])
   send(f,{tex='spark',x=pose.tailX,y=pose.tailY,h=pose.tailH,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,vh=rise,falls=true,drag=.6,size=size,life=life,color=cfg.colors.hot,color1=cfg.colors.ember,a0=1,a1=1,glow=true,emit=true,small=true,fine=true,align=true,flicker=true},hidden,emit,budget)
  end
 end
end
return Flight
