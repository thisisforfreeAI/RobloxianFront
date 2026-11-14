--!strict
-- Ground-hit primitives. Private settings come from export_impact_fx.cjs.
-- APPROX: earth surface palette; no thrown clods, hot-fragment trails, lighting or shake.
local Impact={MAX_PENDING=16,MAX_SMOKE=64,MAX_BIRTHS=4,MAX_ATTEMPTS=128}
local TAU=math.pi*2
local function finite(n:any):boolean return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function round(n:number):number return math.floor(n+.5)end
local function pick(rng:()->number,a:number,b:number):number return a+rng()*(b-a)end
local function texture(rng:()->number,prefix:string):string return prefix..({"A","B","C"})[math.min(3,math.floor(rng()*3)+1)]end
local function dust(cfg:any,x:number,y:number,size:number,life:number,vx:number,vy:number,emit:(any)->boolean,rng:()->number):boolean
 return emit({tex=texture(rng,"puff"),x=x,y=y,h=.05,vx=vx,vy=vy,vh=cfg.motion.rise*.15,size=size,life=life,rot=rng()*TAU,grow=size*cfg.motion.grow/life,drag=1.3,wind=false,ground=true,color=cfg.earth.dust,color1=cfg.earth.dustPale,a0=1,a1=0,small=true,erode=true,swell=true})
end
function Impact.smoke(cfg:any,p:any,emit:(any)->boolean,rng:()->number):boolean
 local w=cfg.weapons[p.weapon];if not w then return false end
 local size= w.smokeSize*pick(rng,.75,1.1)
 local life= w.smokeLife*pick(rng,.8,1.25)
 local vx,vy=pick(rng,-.5,.5),pick(rng,-.5,.5)
 local tex=texture(rng,"puff");local rise=cfg.motion.rise*pick(rng,.7,1.3)
 return emit({tex=tex,x=p.x,y=p.y,h=cfg.blast.smokeFrom+p.index*.2,vx=vx,vy=vy,vh=rise,size=size,life=life,rot=rng()*TAU,grow=size*cfg.motion.grow/life,drag=1.2,wind=true,lean=cfg.lean,ground=false,color=cfg.colors.smoke,color1=cfg.colors.smokeLight,a0=1,a1=0,small=false,erode=true,swell=true})
end
function Impact.burst(cfg:any,x:number,y:number,size:number,weapon:string,emit:(any)->boolean,after:(number,any)->(),rng:()->number):boolean
 local w=cfg.weapons[weapon];if not w then return false end
 local B,F,C,N,M,U=cfg.blast,cfg.flash,cfg.colors,cfg.sparks,cfg.motion,cfg.earth
 if not emit({tex="disc",x=x,y=y,h=.1,size=size*F.share,life=F.sec,color=C.fire,a0=.6,a1=0,glow=true,emit=true})then return false end
 if not emit({tex="disc",x=x,y=y,h=.1,size=size*F.share*F.core,life=F.sec,color=C.hot,a0=1,a1=0,glow=true,emit=true})then return true end
 for _,b in B.bands do
  if not emit({tex=texture(rng,"blob"),x=x,y=y,h=size*.12,size=size*b.share,life=b.sec,rot=rng()*TAU,color=C[b.color],color1=if b.color=="ember"then C.coal else nil,a0=1,a1=1,step=true,pop=true,emit=true})then return true end
 end
 if not emit({tex="disc",x=x,y=y,h=size*.15,size=size*B.coreShare,life=B.coreSec,color=C.hot,a0=1,a1=1,glow=true,step=true,pop=true,emit=true})then return true end
 for _=1,round(N.blast*(size/4)*U.sparks)do
  local a,v=pick(rng,-math.pi,math.pi),pick(rng,N.blastSpeed[1],N.blastSpeed[2]*math.sqrt(size/4))
  local rise=pick(rng,N.blastRise[1],N.blastRise[2]);local s=pick(rng,N.size[1],N.size[2]);local life=pick(rng,N.blastLife[1],N.blastLife[2])
  if not emit({tex="spark",x=x,y=y,h=size*.15,vx=math.cos(a)*v,vy=math.sin(a)*v,vh=rise,falls=true,drag=.6,size=s,life=life,color=C.hot,color1=C.ember,a0=1,a1=1,glow=true,emit=true,small=true,fine=true,align=true,flicker=true})then return true end
 end
 if not emit({tex="ring",x=x,y=y,h=0,size=size*F.ringShare,life=F.ringSec,grow=size*F.ringGrow/F.ringSec,color=U.dustPale,a0=.9,a1=0,ground=true,step=true})then return true end
 local n=math.min(F.maxPuffs,math.max(F.minPuffs,round(F.puffs*(size/4)*U.dustAmount)))
 for i=0,n-1 do
  local a=(i+pick(rng,-.3,.3))/n*TAU;local v=F.kick*math.sqrt(size/4)*pick(rng,.8,1.1)
  local s=size*F.puffShare*pick(rng,.8,1.2);local life=F.puffSec*U.dustHang*pick(rng,.85,1.15)
  if not dust(cfg,x+math.cos(a)*size*.15,y+math.sin(a)*size*.15,s,life,math.cos(a)*v,math.sin(a)*v,emit,rng)then return true end
 end
 n=math.min(B.dust*3,math.max(3,round(B.dust*(size/4)*U.dustAmount)))
 for i=0,n-1 do
  local a=i/n*TAU+pick(rng,-.4,.4);local v=B.dustKick*(size/4)
  if not dust(cfg,x+math.cos(a)*size*.2,y+math.sin(a)*size*.2,size*B.dustShare,B.dustSec*U.dustHang,math.cos(a)*v,math.sin(a)*v,emit,rng)then return true end
 end
 for i=0,w.debris-1 do
  local a,v=rng()*TAU,pick(rng,.2,1)*M.debrisSpeed*(size/3.5);local hot=i%4==0
  local rise=pick(rng,3,10)*(size/3.5);local s=pick(rng,.3,.55);local len=pick(rng,1,1.6);local life=pick(rng,.5,1.3)
  if not emit({tex=if i%2==1 then "chunk"else "shard",x=x,y=y,h=.2,vx=math.cos(a)*v,vy=math.sin(a)*v,vh=rise,falls=true,size=s,len=len,life=life,color=if hot then C.ember else U.debris[i%#U.debris+1],a0=1,a1=1,spin=pick(rng,-8,8),small=true,emit=hot})then return true end
 end
 for i=0,(if w.smoke>0 then math.max(1,round(w.smoke*U.smoke))else 0)-1 do
  local dx,dy=pick(rng,-.35,B.smokeSpread)*size*.4,pick(rng,-.35,B.smokeSpread)*size*.4
  after(B.smokeDelay+i*.05,{x=x+dx,y=y+dy,index=i,weapon=weapon})
 end
 return true
end
function Impact.new():any return {tick=0,sequence=0,pending={},smokes={},received=0,running=false,stats={births=0,attempts=0,smoke=0}}end
function Impact.time(s:any,wall:number):number return (s.war or 0)+(if s.running then math.clamp(wall-s.received,0,.2)else 0)end
function Impact.clear(s:any) table.clear(s.pending);table.clear(s.smokes)end
-- Rows have already passed BlastEvents.read. No queues retain unit or target owners.
function Impact.receive(s:any,tick:number,rows:{any},war:any,wall:number,hidden:(number,number)->boolean,wet:(number,number)->boolean)
 if not finite(tick)or tick%1~=0 or tick<=s.tick then return end;s.tick=tick
 if type(war)~="table"or not finite(war[1])or war[1]<0 or (war[2]~=0 and war[2]~=1)then Impact.clear(s);s.war=nil;s.running=false;return end
 if s.war and war[1]<s.war then Impact.clear(s);s.sequence=0 end
 local running=war[2]==1
 if s.war~=war[1]or s.running~=running then s.war=war[1];s.running=running;s.received=wall end
 local now=Impact.time(s,wall);local sequence=s.sequence
 for _,row in rows do
  if row[1]<=sequence then continue end;sequence=row[1]
  if not row[6]or now-row[5]>.25 or row[5]>now+.05 or hidden(row[2],row[3])or wet(row[2],row[3])then continue end
  if #s.pending<Impact.MAX_PENDING then table.insert(s.pending,{x=row[2],y=row[3],size=row[4],at=row[5],weapon=row[6]})end
 end
 s.sequence=sequence
end
function Impact.step(s:any,cfg:any,wall:number,hidden:(number,number)->boolean,wet:(number,number)->boolean,emit:(any)->boolean,rng:(()->number)?):any
 local stats=s.stats;stats.births=0;stats.attempts=0;stats.smoke=0
 if not s.war or not s.running or not cfg or (#s.pending==0 and #s.smokes==0)then return stats end
 local now=Impact.time(s,wall);local random=rng or math.random
 local function send(p:any):boolean
  if stats.attempts>=Impact.MAX_ATTEMPTS then return false end
  stats.attempts+=1;if hidden(p.x,p.y)then return false end
  return emit(p)
 end
 -- Older smoke gets a bounded share of work before new flashes; missed puffs never catch up.
 local keep=0
 for _,p in s.smokes do
  if hidden(p.rootX,p.rootY)or wet(p.rootX,p.rootY)then continue end
  if p.at>now then keep+=1;s.smokes[keep]=p
  elseif now-p.at<=.1 and stats.smoke<32 then stats.smoke+=1;Impact.smoke(cfg,p,send,random)end
 end
 for i=#s.smokes,keep+1,-1 do s.smokes[i]=nil end
 keep=0
 for _,p in s.pending do
  if hidden(p.x,p.y)or wet(p.x,p.y)or now-p.at>.25 then continue end
  if p.at>now or stats.births>=Impact.MAX_BIRTHS then keep+=1;s.pending[keep]=p;continue end
  stats.births+=1
  Impact.burst(cfg,p.x,p.y,p.size,p.weapon,send,function(delay,smoke)
   if #s.smokes>=Impact.MAX_SMOKE then return end
   smoke.at=p.at+delay;smoke.rootX=p.x;smoke.rootY=p.y;table.insert(s.smokes,smoke)
  end,random)
 end
 for i=#s.pending,keep+1,-1 do s.pending[i]=nil end
 return stats
end
return Impact
