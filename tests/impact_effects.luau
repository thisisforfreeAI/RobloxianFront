--!strict
return function(test:any,eq:any)
 local I=require('../src/shared/Presentation/ImpactEffects');local E=require('../src/shared/Protocol/BlastEvents');local R=require('../src/shared/Presentation/SquadReaction')
 local fs=require('@lune/fs');local luau=require('@lune/luau')
 -- Synthetic values, deliberately unrelated to the extracted game configuration.
 local cfg={weapons={shell={debris=3,smoke=2,smokeSize=.8,smokeLife=1}},blast={bands={{share=.5,sec=.2,color='ember'}},coreShare=.2,coreSec=.1,smokeFrom=.3,smokeDelay=.4,smokeSpread=.2,dust=1,dustKick=2,dustShare=.3,dustSec=.6},
  flash={share=.7,core=.3,sec=.1,ringShare=.4,ringGrow=1.5,ringSec=.2,maxPuffs=3,minPuffs=2,puffs=2,kick=3,puffShare=.2,puffSec=.5},colors={hot=1,fire=2,ember=3,coal=4,smoke=5,smokeLight=6},motion={rise=2,grow=1.2,debrisSpeed=4},sparks={blast=2,blastSpeed={2,4},blastRise={1,3},blastLife={.2,.4},size={.1,.2}},earth={dust=7,dustPale=8,dustAmount=1,dustHang=1,sparks=1,smoke=1,debris={9,10}},lean=.6}
 local function no()return false end
 local function rng()return .5 end
 local function near(a,b)assert(math.abs(a-b)<1e-8,`{a} ~= {b}`)end
 local function row(id,at,weapon)return{id,5,6,4,at or 10,weapon or 'shell'}end
 local function receive(s,tick,rows,war,wall,hidden,wet)I.receive(s,tick,rows,war or{10,1},wall or 0,hidden or no,wet or no)end
 local function step(s,wall,out,hidden,wet,emit)return I.step(s,cfg,wall,hidden or no,wet or no,emit or function(p)table.insert(out,p);return true end,rng)end
 test('weapon tail preserves legacy blasts and accepts visual mortar below the reaction threshold',function()
  local q={};assert(E.push(q,1,5,5,1.8,10,20,20,'mortar'));assert(not E.push(q,2,5,5,1.8,10,20,20));assert(E.push(q,3,5,5,4,10,20,20))
  local v=E.visible(q,function()return true end,10);eq(v[1][6],'mortar');eq(v[2][6],nil);local read=E.read(v,20,20);eq(read[1][4],1.8);eq(#read[2],5)
  local r=R.new(function()return .5 end);r.sync({10,1},0);eq(r.apply({{id=1,men={{up=true,x=5,y=5}}}},read,0),1,'only the large legacy event causes flinch')
  eq(#E.read({{1,5,5,4,10,'unknown'},{2,5,5,4,10,{}},{3,5,5,0,10,'shell'}},20,20),0)
 end)
 test('land impact primitives include layered flash dust ring debris and source-relative smoke records',function()
  local out,delayed={},{};assert(I.burst(cfg,5,6,4,'shell',function(p)table.insert(out,p);return true end,function(at,p)table.insert(delayed,{at,p})end,rng))
  eq(out[1].tex,'disc');near(out[1].size,2.8);eq(out[3].tex,'blobB');eq(out[3].color1,4);eq(out[5].tex,'spark');eq(out[7].tex,'ring')
  eq(out[#out-2].tex,'shard');eq(out[#out-2].emit,true);eq(out[#out-1].tex,'chunk');eq(out[#out].color,9);eq(#delayed,2);near(delayed[2][1],.45);eq(delayed[2][2].index,1)
 end)
 test('unknown and legacy weapon data never invent a generic explosion',function()
  local s=I.new();receive(s,1,{{1,5,6,4,10}},nil);eq(#s.pending,0);receive(s,2,{row(2,10,'not-real')});local out={};step(s,0,out);eq(#out,0);eq(#s.smokes,0)
 end)
 test('duplicate snapshots and repeated blast ids cannot replay a flash',function()
  local s=I.new();receive(s,1,{row(1)});local out={};step(s,0,out);local n=#out;receive(s,1,{row(2)});receive(s,2,{row(1)});step(s,0,out);eq(#out,n)
 end)
 test('duplicate ids in one packet admit only one effect',function()
  local s=I.new();receive(s,1,{row(1),row(1)});eq(#s.pending,1)
 end)
 test('expired future hidden and wet impacts are rejected without a deferred queue',function()
  for _,scene in {{9.7,no,no},{10.1,no,no},{10,function()return true end,no},{10,no,function()return true end}}do
   local s=I.new();receive(s,1,{row(1,scene[1])},nil,0,scene[2],scene[3]);eq(#s.pending,0)
  end
 end)
 test('pending impacts and smoke are cancelled when their source enters fog before presentation',function()
  local s=I.new();receive(s,1,{row(1)});local out={};step(s,0,out,function()return true end);eq(#out,0);eq(#s.pending,0)
  receive(s,2,{row(2)});step(s,0,out);eq(#s.smokes,2);step(s,.1,out,function()return true end);eq(#s.smokes,0)
 end)
 test('pause freezes impact births and prediction stops after two tenths without fresh snapshots',function()
  local s=I.new();receive(s,1,{row(1)},{10,0});local out={};step(s,50,out);eq(#out,0);near(I.time(s,50),10)
  receive(s,2,{}, {10,1},50);step(s,50,out);assert(#out>0);near(I.time(s,500),10.2);local n=#out;step(s,500,out);eq(#out,n)
  receive(s,3,{}, {10.4,0},501);step(s,501,out);eq(#out,n);receive(s,4,{}, {10.4,1},502);step(s,502,out);assert(#out>n)
 end)
 test('delayed smoke uses original time height and current fog without callback owners',function()
  local s=I.new();receive(s,1,{row(1)});local out={};step(s,0,out);eq(#s.smokes,2);near(s.smokes[1].at,10.4);eq(type(s.smokes[1]),'table')
  receive(s,2,{}, {10.4,1},1);local n=#out;step(s,1,out);eq(#out,n+1);near(out[#out].h,.3);eq(out[#out].lean,.6);eq(out[#out].color1,6);eq(#s.smokes,1)
  receive(s,3,{}, {11,1},2);n=#out;step(s,2,out);eq(#out,n);eq(#s.smokes,0,'overdue smoke drops instead of catching up')
 end)
 test('clock rollback and invalid clock discard pending effects and delayed smoke',function()
  local s=I.new();receive(s,1,{row(1)});step(s,0,{});assert(#s.smokes>0);receive(s,2,{}, {1,1});eq(#s.smokes,0)
  receive(s,3,{row(3,1)},{1,1});eq(#s.pending,1);I.receive(s,4,{},nil,0,no,no);eq(#s.pending,0);eq(s.war,nil)
 end)
 test('dense packet work storage and particle attempts stay bounded',function()
  local s=I.new();local rows={};for i=1,64 do rows[i]=row(i)end;receive(s,1,rows);eq(#s.pending,I.MAX_PENDING)
  local calls=0;local stats=step(s,0,{},nil,nil,function()calls+=1;return true end);eq(stats.births,4);assert(calls<=128);eq(calls,stats.attempts);eq(#s.pending,12)
  for i=2,20 do receive(s,i,rows)end;eq(#s.pending,12,'observed dropped rows are not retried');I.clear(s);eq(#s.pending,0);eq(#s.smokes,0)
 end)
 test('allocation refusal stops a burst at its first request and cannot orphan delayed smoke',function()
  local s=I.new();receive(s,1,{row(1)});local calls=0;step(s,0,{},nil,nil,function()calls+=1;return false end);eq(calls,1);eq(#s.pending,0);eq(#s.smokes,0)
 end)
 test('shared particle engine admits impacts into the existing cap and cleans only their tag',function()
  local D=require('../src/shared/Presentation/DeathEffects');local engine=D.new({death={variants={}},colors={},sparks={},motion={gravity=8,windX=0,windY=0}},rng)
  engine:request('spawn',{x=1,y=1,size=1,life=10,color=1},'unrelated');local s=I.new();local emitted=0
  for tick=1,30 do local rows={};for j=1,16 do table.insert(rows,row(tick*64+j))end;receive(s,tick,rows);step(s,0,{},nil,nil,function(p)emitted+=1;return engine:request('spawn',p,s)end)end
  eq(#engine.particles,512);assert(emitted>=511);engine:clearTag(s);eq(#engine.particles,1);eq(engine.particles[1].worldTag,'unrelated');eq(#engine.later,0);eq(#engine.emitters,0)
 end)
 test('server bridge carries known weapon while keeping wreck reactions and smaller mortar visuals',function()
  local src=fs.readFile('src/server/Match/MatchService.luau');local a=assert(src:find('sim.presentBlast=function',1,true));local b=assert(src:find('\n\tdo',a,true));local sim={time=10};local q={}
  local env=setmetatable({sim=sim,blastSizes={shell=4,mortar=1.8,bullets=0},BlastEvents=E,blastSequence=0,blasts=q,map={width=100,height=100}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();sim.presentBlast(5,5,'mortar');sim.presentBlast(5,5,'shell');sim.presentBlast(5,5,'wreck',2);sim.presentBlast(5,5,'bullets');eq(#q,3);eq(q[1][6],'mortar');eq(q[2][6],'shell');eq(q[3][6],nil)
 end)
 test('actual unit receiver syncs impacts even on empty snapshots and rejects duplicates before dispatch',function()
  local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('function UnitRenderer.react(',1,true));local b=assert(src:find('function UnitRenderer.reactionStats(',a,true));local calls=0
  local env=setmetatable({UnitRenderer={},reactionTick=0,reactionWidth=100,reactionHeight=100,BlastEvents=E,reactions={sync=function()end,apply=function()end},views={},FogOverlay={hidden=no},DeathRenderer={impacts=function(_,events,war)calls+=1;eq(war[1],10);if calls==1 then eq(events[1][6],'shell')else eq(#events,0)end end}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();env.UnitRenderer.react(1,{row(1)},{10,1});env.UnitRenderer.react(1,{row(1)},{10,1});env.UnitRenderer.react(2,nil,{10,1});eq(calls,2)
 end)
 test('native renderer ages old effects before hit admission and draws newborn flash defaults on a slow frame',function()
  local rb=require('@lune/roblox');local src=fs.readFile('src/client/Rendering/DeathRenderer.luau');local a=assert(src:find('function DeathRenderer.step(',1,true));local b=assert(src:find('\nreturn DeathRenderer',a,true))
  local order={};local engine={particles={}};function engine:step(dt)table.insert(order,'age');eq(dt,.4)end
  local view={gui={},image={},part={}};local env
  env=setmetatable({TracerFlight={time=function()return 10 end},tracerClock={},engine=engine,impactConfig={},impacts={},emitImpactParticle=function()end,ImpactEffects={step=function()table.insert(order,'birth');table.insert(engine.particles,{x=5,y=6,x0=5,y0=6,h=0,size=2,len=1,rot=0,tex='disc',a0=.4,color=1})end},Fog={hidden=no,water=no},World={STUDS_PER_CELL=4,TOP_GUI_YAW=0,toWorld=function(x,y,z)return rb.Vector3.new(x*4,z,y*4)end},workspace={},slot=function()return view end,slots={},FRAMES={disc={1,0}},frame=24,Vector2=rb.Vector2,Vector3=rb.Vector3,CFrame=rb.CFrame,Color3=rb.Color3,DeathRenderer={}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();env.DeathRenderer.step(.4);eq(order[1],'age');eq(order[2],'birth');near(view.image.ImageTransparency,.6);eq(view.gui.Enabled,true);near(view.part.Size.X,8)
 end)
end
