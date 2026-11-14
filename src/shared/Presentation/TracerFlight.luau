--!strict
-- Original normal-view round head/tail kinematics. No hit callbacks or gameplay authority.
local Flight={MAX=64}
local function finite(n:any):boolean return type(n)=='number'and n==n and math.abs(n)<math.huge end
function Flight.clock():any return {tick=0,received=0,running=false}end
function Flight.sync(s:any,tick:number,war:any,wall:number):boolean
 if not finite(tick)or tick<=s.tick then return false end;s.tick=tick
 if type(war)~='table'or not finite(war[1])or war[1]<0 or war[2]~=0 and war[2]~=1 then s.war=nil;s.running=false;return true end
 local reset=s.war~=nil and war[1]<s.war
 local running=war[2]==1
 if war[1]~=s.war or running~=s.running then s.war=war[1];s.running=running;s.received=wall end
 return reset
end
function Flight.time(s:any,wall:number):number?
 return if s.war then s.war+(if s.running then math.clamp(wall-s.received,0,.2)else 0)else nil
end
function Flight.plan(p:any):any?
 for _,key in {'x','y','h','tx','ty','targetH','at','now','speed','tail','width','tip','heightFactor','color','headColor'}do if not finite(p[key])then return nil end end
 if p.speed<=0 or p.speed>500 or p.width<=0 or p.width>4 or p.tail<0 or p.tail>32 or p.tip<=0 or p.tip>32 or p.h<0 or p.h>64 or p.targetH<0 or p.targetH>64 or p.color<0 or p.color>16777215 or p.headColor<0 or p.headColor>16777215 then return nil end
 local dx,dy=p.tx-p.x,p.ty-p.y;local distance=math.max(.01,math.sqrt(dx*dx+dy*dy))
 local life=(distance+p.tail)/p.speed
 if distance>512 or life>8 or p.now<p.at or p.now-p.at>=life then return nil end
 return {x=p.x,y=p.y,h=p.h,targetH=p.targetH,ux=dx/distance,uy=dy/distance,distance=distance,speed=p.speed,tail=p.tail,width=p.width,tip=p.tip,heightFactor=p.heightFactor,at=p.at,life=life,color=p.color,headColor=p.headColor}
end
function Flight.particle(f:any,head:boolean,now:number):any
 local p={tex='streak',x=f.x,y=f.y,h=f.h,size=f.width,len=if head then f.tip else .01,rot=math.atan2(f.uy*f.distance-(f.targetH-f.h)*f.heightFactor,f.ux*f.distance),life=f.life,color=if head then f.headColor else f.color,a0=1,a1=1,glow=true,emit=true,small=true,tracer=f,tracerHead=head}
 Flight.apply(p,now);return p
end
function Flight.apply(p:any,now:number):boolean
 local f=p.tracer;local age=math.max(0,now-f.at);p.age=age
 if age>=f.life then return false end
 local travelled=age*f.speed;local front=math.min(f.distance,travelled);local back=math.min(f.distance,math.max(0,travelled-f.tail))
 if p.tracerHead then
  local along=math.max(0,front-f.width*f.tip/2);p.x=f.x+f.ux*along;p.y=f.y+f.uy*along;p.h=f.h+(f.targetH-f.h)*(front/f.distance);p.alpha=if travelled>=f.distance then 0 else 1
 else
  local along=(front+back)/2;p.x=f.x+f.ux*along;p.y=f.y+f.uy*along;p.h=f.h+(f.targetH-f.h)*(along/f.distance);p.len=math.max(.01,(front-back)/f.width);p.alpha=1
 end
 p.drawSize=f.width;p.tint=p.color;return true
end
-- Conservative cell traversal along the tracer, including the drawn head length.
function Flight.visible(p:any,hidden:(number,number)->boolean):boolean
 local f=p.tracer;if p.alpha<=0 or hidden(f.x,f.y)or hidden(p.x,p.y)then return false end
 local front=math.min(f.distance,p.age*f.speed);local back=math.min(f.distance,math.max(0,p.age*f.speed-f.tail))
 if p.tracerHead then local center=math.max(0,front-f.width*f.tip/2);back=center-f.width*f.tip/2;front=center+f.width*f.tip/2 end
 local ax,ay=f.x+f.ux*back,f.y+f.uy*back;local bx,by=f.x+f.ux*front,f.y+f.uy*front
 return Flight.segment(ax,ay,bx,by,hidden)
end
function Flight.segment(ax:number,ay:number,bx:number,by:number,hidden:(number,number)->boolean):boolean
 local x,y,ex,ey=math.floor(ax),math.floor(ay),math.floor(bx),math.floor(by)
 local dx,dy=bx-ax,by-ay;local sx,sy=if dx>=0 then 1 else -1,if dy>=0 then 1 else -1
 local stepX,stepY=if dx==0 then math.huge else 1/math.abs(dx),if dy==0 then math.huge else 1/math.abs(dy)
 local nextX=if dx==0 then math.huge else ((if sx>0 then x+1 else x)-ax)/dx
 local nextY=if dy==0 then math.huge else ((if sy>0 then y+1 else y)-ay)/dy
 for _=1,1028 do
  if hidden(x+.5,y+.5)then return false end
  if x==ex and y==ey then return true end
  if nextX<nextY then x+=sx;nextX+=stepX
  elseif nextY<nextX then y+=sy;nextY+=stepY
  else
   if hidden(x+sx+.5,y+.5)or hidden(x+.5,y+sy+.5)then return false end
   x+=sx;y+=sy;nextX+=stepX;nextY+=stepY
  end
 end
 return false
end
function Flight.shot(cfg:any,event:any,now:number,rng:(()->number)?):any?
 local profile=cfg and cfg[event.kind];if type(profile)~='table'or not finite(event.tx)or not finite(event.ty)then return nil end
 local tx,ty=event.tx,event.ty
 if event.kind=='ifv'and event.round>0 then
  local random=rng or math.random;local ux,uy=math.cos(event.heading),math.sin(event.heading)
  tx+=ux*profile.walk*event.round-.6+random()*(profile.spread+.6)
  ty+=uy*profile.walk*event.round-.6+random()*(profile.spread+.6)
 end
 local faction=cfg.factions and cfg.factions[event.army];local color=if faction then faction[event.kind]else profile.color
 return {x=event.x,y=event.y,h=event.h,tx=tx,ty=ty,targetH=0,at=event.at,now=now,speed=profile.speed,tail=profile.tail,width=profile.width,tip=cfg.tip,heightFactor=cfg.heightFactor,color=color or profile.color,headColor=profile.headColor}
end
return Flight
