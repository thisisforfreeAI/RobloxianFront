--!strict
return function(test:any,eq:any)
 local F=require('../src/shared/Presentation/BallisticFlight');local D=require('../src/shared/Presentation/DeathEffects');local cfg=require('./fixtures/ballistic_config');local fs=require('@lune/fs');local luau=require('@lune/luau')
 local function no()return false end;local function rng()return .5 end
 local function near(a,b)assert(math.abs(a-b)<1e-7,`{a} ~= {b}`)end
 local function packet(weapon,now)return {config=cfg,weapon=weapon or 'rocket',x=1,y=1,h=.4,tx=11,ty=1,targetH=0,at=0,now=now or 0,seed=7}end
 local function engine()return D.new({death={variants={}},colors={},sparks={},motion={gravity=8,windX=0,windY=0}},rng)end
 local function trails(f,now,hidden,budget)local out={};F.trails(f,now,hidden or no,function(p)table.insert(out,p);return true end,budget or {remaining=32},rng);return out end
 test('mortar follows the source capped parabolic arc and expires without landing callbacks',function()
  local f=assert(F.plan(packet('mortar')));near(f.life,2.5);near(f.arc,4);local p=F.particle(f,'body',0);near(p.x,1);near(p.h,.4);F.apply(p,1.25);near(p.x,6);near(p.h,4.2);eq(F.apply(p,2.5),false);eq(p.tick,nil);eq(p['end'],nil)
 end)
 test('rocket bump flame flicker back attachment and ground shadow use separate source transforms',function()
  local f=assert(F.plan(packet()));near(f.arc,.4);eq(F.slots(f),3);local body=F.particle(f,'body',.5);local flame=F.particle(f,'flame',.5);local shadow=F.particle(f,'shadow',.5);F.apply(shadow,.5,.5)
  assert(flame.x<body.x);assert(flame.len>=1.5 and flame.len<=2);near(flame.size,.16);near(shadow.alpha,.175);eq(shadow.h,0);near(shadow.size,.24);eq(shadow.color,0)
  local mortar=assert(F.plan(packet('mortar')));eq(F.slots(mortar),2)
 end)
 test('malformed oversized expired future and unsupported flights do not allocate',function()
  for _,c in {{'tx',0/0},{'tx',1000},{'h',-1},{'targetH',65},{'at',1},{'now',5},{'weapon','tbm'},{'at',-1}}do local p=packet();p[c[1]]=c[2];eq(F.plan(p),nil);local e=engine();eq(e:request('ballistic',p),false);eq(#e.particles,0)end
  local p=packet();p.config={profiles=cfg.profiles};eq(F.plan(p),nil)
 end)
 test('late admission positions the flight at observed age without painting an old trail',function()
  local f=assert(F.plan(packet('rocket',.2)));near(f.pose.x,3);near(f.prevX,f.pose.tailX);eq(#trails(f,.2),0);eq(#trails(f,.5),0);eq(f.acc,0)
 end)
 test('salvo scatter agrees with the actual authoritative seed and pattern helpers',function()
  local src=fs.readFile('src/shared/Simulation/Sim.luau');local start=assert(src:find('function R.imul(',src:find('-- Rocket artillery',1,true),true));local finish=assert(src:find('\n\t\tfunction rocketLands(',start,true));local env=setmetatable({self={}},{__index=getfenv()})
  luau.load('local R={}\n'..src:sub(start,finish-1),{environment=env})();local sim=env.self
  for _,id in {1,19,321}do for _,time in {0,7.123,90.5}do local rounds=sim.salvoPattern(sim.salvoSeed(id,time),8,.75)
   for i,r in rounds do local x,y=F.target(cfg,id,time,i-1,20,30);near(x,20+math.cos(r.a)*r.r*cfg.salvo.spread);near(y,30+math.sin(r.a)*r.r*cfg.salvo.spread)end
  end end
 end)
 test('missing salvo identity and special TBM cannot fabricate generic rocket flights',function()
  local event={kind='rocket',at=10,salvoAt=10,round=0,spread=cfg.salvo.spread,x=5,y=5,h=.4,tx=30,ty=30};eq(F.shot(cfg,event,10),nil);event.id=7;assert(F.shot(cfg,event,10));event.weapon='tbm';eq(F.shot(cfg,event,10),nil);event.weapon=nil;event.round=64;eq(F.shot(cfg,event,10),nil);eq(F.shot(nil,event,10),nil)
 end)
 test('resolved server spread overrides the visual default and legacy metadata clears safely',function()
  local V=require('../src/shared/Presentation/VehicleRecoil');local sim={time=10,rules={number=function(_,key)eq(key,'artillery.rocketSpread');return 3.3 end}};local p=V.snapshot({kind='rocket',id=99,x=5,y=5,side=1,alive=true},nil,sim);eq(p[6],false);eq(p[7],3.3)
  local ride=V.new();V.receive(ride,p,{10,1},0);eq(ride.spread,3.3);local event={kind='rocket',id=99,salvoAt=10,at=10,round=2,spread=ride.spread,x=5,y=5,h=.4,tx=30,ty=20};local shot=assert(F.shot(cfg,event,10));local x,y=F.target(cfg,99,10,2,30,20,3.3);near(shot.tx,x);near(shot.ty,y)
  V.receive(ride,{0,false,0,{},'coalition'},{10,1},0);eq(ride.spread,nil);event.spread=ride.spread;eq(F.shot(cfg,event,10),nil);V.receive(ride,{0,false,0,{},'coalition',false,0/0},{10,1},0);eq(ride.spread,nil)
 end)
 test('authoritative spread metadata is sampled only after the existing unit visibility guard',function()
  local V=require('../src/shared/Presentation/VehicleRecoil');local code=fs.readFile('src/server/Match/MatchService.luau');local a=assert(code:find('local function viewFor(',1,true));local b=assert(code:find('-- vehicles destroyed',a,true));local shown=false;local reads=0
  local e={id=99,kind='rocket',cat='unit',side=2,alive=true,x=5,y=5,heading=0,hp=100,maxHp=100};local sim={time=10,list={e},rules={number=function(_,key)eq(key,'artillery.rocketSpread');reads+=1;return 3.3 end}};local viewer={update=function()end,unitVisible=function()return shown end,lastSeen={},runs=function()return{}end}
  local env=setmetatable({sim=sim,viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},CrewMotion={snapshot=function()return nil end},VehicleRecoil=V,rules={data={}},unitLook=function()return 1,30,20,9 end,unitStatus=function()return 0 end,unitStage=function()return 0 end},{__index=getfenv()});local view=luau.load(code:sub(a,b-1)..'\nreturn viewFor',{environment=env})();eq(#view(1),0);eq(reads,0);shown=true;local rows=view(1);eq(reads,1);eq(rows[1][20][7],3.3)
 end)
 test('AT smoke motors shell threads and salvo wisps remain distinct',function()
  local rocket=trails(assert(F.plan(packet())),.05);eq(rocket[1].tex,'puffB');eq(rocket[1].small,true);eq(rocket[#rocket].tex,'spark')
  local shell=trails(assert(F.plan(packet('shell'))),.1);eq(shell[1].tex,'puffB');eq(shell[1].color,7);eq(shell[1].fine,true)
  local f=assert(F.plan(packet('salvo')));trails(f,.05);trails(f,.1);local salvo=trails(f,.15);eq(salvo[1].tex,'px');eq(salvo[1].wind,true);eq(#trails(assert(F.plan(packet('mortar'))),.1),0)
 end)
 test('paused stalled hidden and over-budget trail work leaves no catch-up backlog',function()
  local f=assert(F.plan(packet()));eq(#trails(f,0),0);eq(#trails(f,.3),0);eq(f.acc,0);eq(#trails(f,.35,function()return true end),0);eq(f.acc,0)
  eq(#trails(f,.4,no,{remaining=0}),0);eq(f.acc,0);local out=trails(f,.451);assert(#out<=4);assert(#out>0);eq(#trails(f,.451),0)
 end)
 test('per-owner and shared trail attempts bound dense emission before creating a backlog',function()
  local budget={remaining=3};local f=assert(F.plan(packet()));local out=trails(f,.1,no,budget);assert(#out<=3);eq(budget.remaining,0)
  local next=trails(f,.15,no,{remaining=32});assert(#next<=4)
 end)
 test('normal tenth-second clock steps tolerate floating-point subtraction error',function()
  local p=packet();p.at=.3;p.now=.3;local f=assert(F.plan(p));assert(#trails(f,.4)>0)
 end)
 test('thin contrails do not connect across hidden cells and body checks include the full segment',function()
  local f=assert(F.plan(packet()));local p=F.particle(f,'body',.5);eq(F.visible(p,function(x)return x>=5 and x<6 end),false);eq(F.visible(p,no),true)
  local input=packet('salvo');input.tx=20;f=assert(F.plan(input));f.last=1.25;f.prevX=5;f.prevY=1;f.prevH=0;local out=trails(f,1.3,function(x)return x>=7 and x<8 end)
  for _,part in out do assert(part.tex~='px','no thin bridge through hidden terrain')end
 end)
 test('body shadow flame admission is atomic and shares the existing 512 particle pool',function()
  local e=engine();e.maxParticles=2;eq(e:request('ballistic',packet()),false);eq(#e.particles,0);assert(e:request('ballistic',packet('mortar')));eq(#e.particles,2);eq(e.ballisticCount,1)
  e:clearTag(nil);eq(e.ballisticCount,1);e:clearFlights();eq(e.ballisticCount,0);eq(#e.particles,0)
 end)
 test('32 active flights and one 32-request trail pass bound dense mixed fire',function()
  local e=engine();local accepted=0;for _=1,3000 do if e:request('ballistic',packet(),'a')then accepted+=1 end end;eq(accepted,32);eq(#e.particles,96);eq(e.ballisticCount,32)
  e:step(.05,.05,no);assert(#e.particles<=128);eq(e.flightBudget.remaining,0);eq(#e.later,0);eq(#e.emitters,0);local count=#e.particles;e:step(.05,.05,no);eq(#e.particles,count);eq(e.ballisticCount,32)
  e:step(.05,2,no);eq(e.ballisticCount,0)
 end)
 test('flight pose freezes on war time while emitted smoke continues aging normally',function()
  local e=engine();assert(e:request('ballistic',packet(),'a'));e:step(.05,.05,no);local x=e.particles[1].x;e:step(2,.05,no);eq(e.particles[1].x,x);eq(e.ballisticCount,1);eq(#e.particles,3)
 end)
 test('cleanup counts both flight types correctly and preserves unrelated fire',function()
  local e=engine();e:request('spawn',{x=1,y=1,h=0,size=1,life=10,color=0},'fire');e:request('ballistic',packet(),'a');e:request('ballistic',packet('mortar'),'b');e:clearTag('a');eq(e.ballisticCount,1);eq(#e.particles,3);e:clearFlights();eq(e.ballisticCount,0);eq(#e.particles,1);eq(e.particles[1].worldTag,'fire')
 end)
 test('native engine shadow strength follows the supplied daylight opacity and no trail ages through birth',function()
  local e=engine();e:request('ballistic',packet(),'a');e:step(.05,.05,no,.5);near(e.particles[2].alpha,.175);for i=4,#e.particles do eq(e.particles[i].age,0)end
 end)
 test('actual rocket muzzle preserves salvo identity launch time offsets and independent endpoints',function()
  local code=fs.readFile('src/shared/Presentation/VehicleMuzzle.luau');local env=setmetatable({require=function()return {rocketTip=function()return {x=5,y=5,h=.4}end,rocket=function()return true end}end},{__index=getfenv()});local M=luau.load(code,{environment=env})();local s=M.new(99);local ride={warAt=10,sequence=0,army='coalition',aim=0,spread=3.3};M.receive(s,ride,30,20);ride.sequence=1;ride.shotAt=10;ride.offsets={0,.6,.9};M.receive(s,ride,30,20);M.place(s,5,5,5,5,0)
  local events={};for _,t in {10,10.6,10.9}do M.step(s,ride,{rocket={}},'rocket',t,no,function()return true end,{prepares=32,pulses=32},rng,nil,function(e)table.insert(events,e)end)end
  eq(#events,3);for i,e in events do eq(e.id,99);eq(e.salvoAt,10);eq(e.spread,3.3);eq(e.round,i-1);near(e.at,10+ride.offsets[i]);eq(e.tx,30)end
 end)
 test('crew bridge emits one accepted tube flight and skips a refused first flash',function()
  local C=require('../src/shared/Presentation/CrewMuzzle');local originalTip,originalMortar=C.tip,C.mortar;C.tip=function()return {x=5,y=5,h=.4,ux=1,uy=0}end;C.mortar=function()return true end
  local shots={};local s={id=33,war=10,running=false,received=0,pending={at=10,tx=30,ty=20,army='coalition'}};C.step(s,{},'mortar',{},5,5,1,0,no,function()return true end,{prepares=1,pulses=1},rng,function(e)table.insert(shots,e)end);eq(#shots,1);eq(shots[1].id,33);eq(shots[1].kind,'mortar')
  C.mortar=function()return false end;s.pending={at=10,tx=30,ty=20};C.step(s,{},'mortar',{},5,5,1,0,no,function()return false end,{prepares=1,pulses=1},rng,function()error('refused flash must not launch')end);C.tip=originalTip;C.mortar=originalMortar
 end)
 test('actual unit bridge routes tracers and ballistic flights through their shared slot budget',function()
  local code=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(code:find('local function emitVehicleTracer(',1,true));local b=assert(code:find('\nlocal UnitRenderer',a,true));local kinds={};local budget={}
  local env=setmetatable({rifleBudget=budget,DeathRenderer={vehicleTracer=function(e,b)eq(b,budget);table.insert(kinds,e.kind)end,ballistic=function(e,b)eq(b,budget);table.insert(kinds,e.kind)end}},{__index=getfenv()});local emit=luau.load(code:sub(a,b-1)..'\nreturn emitVehicleTracer',{environment=env})();for _,kind in {'tank','ifv','rocket','mortar','artillery'}do emit({kind=kind})end;eq(table.concat(kinds,','),'tank,ifv,rocket,mortar,artillery')
 end)
 test('actual ballistic renderer bridge charges two or three slots and skips missing clocks or special missiles',function()
  local code=fs.readFile('src/client/Rendering/DeathRenderer.luau');local a=assert(code:find('function DeathRenderer.ballistic(',1,true));local b=assert(code:find('function DeathRenderer.vehicleTracer(',a,true));local calls=0
  local env=setmetatable({DeathRenderer={request=function(kind,p)eq(kind,'ballistic');eq(p.weapon,'mortar');calls+=1;return true end},TracerFlight=require('../src/shared/Presentation/TracerFlight'),tracerClock={war=10,running=false},BallisticFlight=F,ballisticConfig=cfg,ballisticChecked=true},{__index=getfenv()});luau.load(code:sub(a,b-1),{environment=env})();local budget={particles=3};local event={kind='mortar',id=3,x=1,y=1,h=.4,tx=11,ty=1,at=10};assert(env.DeathRenderer.ballistic(event,budget));eq(budget.particles,1);eq(env.DeathRenderer.ballistic(event,budget),false);event.weapon='tbm';eq(env.DeathRenderer.ballistic(event,{particles=10}),false);eq(calls,1)
 end)
end
