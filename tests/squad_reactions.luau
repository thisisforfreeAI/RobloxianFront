--!strict
return function(test:any,eq:any)
 local E=require('../src/shared/Protocol/BlastEvents');local R=require('../src/shared/Presentation/SquadReaction');local SM=require('../src/client/Rendering/SquadMen');local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
 local function near(a,b)assert(math.abs(a-b)<1e-9,`{a} ~= {b}`)end
 local function squad(id,x,y)return{id=id,men={{up=true,x=x,y=y,flatUntil=0,kind='rifle',heading=0,vx=0,vy=0}}}end
 test('transient blast transport validates and bounds the newest events without changing previous snapshot fields',function()
  local q={};assert(E.push(q,1,5,5,2,0,100,100));for i=2,80 do E.push(q,i,5,5,4,1,100,100)end;eq(#q,E.MAX);eq(q[1][1],17)
  for _,row in {{1,0,0,1.9,0},{1,-1,0,4,0},{1,100,0,4,0},{1,0,0,0/0,0},{1,0,0,65,0},{1.5,0,0,4,0},{1,0,0,4,-1}}do eq(#E.read({row},100,100),0)end
  local read=E.read(q,100,100);q[1][2]=50;eq(read[1][2],5);eq(#E.visible(read,function()return false end),0)
 end)
 test('living soldiers react inside the original reach and keep deterministic per-soldier expiry',function()
  local m=R.new(SM.hash);m.sync({10,0},0);local a,b=squad(1,10,10),squad(2,15,10);b.men[1].up=false
  eq(m.apply({a,b},{{1,10,10,4,10}},0),1);near(a.men[1].flatUntil,10+.85+SM.hash(1,70)*.35);eq(b.men[1].flatUntil,0)
  eq(m.apply({a},{{1,10,10,4,10}},0),0)
 end)
 test('exact reach is inclusive while already prone soldiers and expired or future events do not replay',function()
  local m=R.new(function()return .5 end);m.sync({10,0},0);local s=squad(1,10+4*.5+2.2,10)
  eq(m.apply({s},{{1,10,10,4,10}},0),1);local untilTime=s.men[1].flatUntil
  m.sync({10.5,0},0);eq(m.apply({s},{{2,10,10,4,10.5}},0),0);eq(s.men[1].flatUntil,untilTime)
  s.men[1].flatUntil=0;m.sync({20,0},0);eq(m.apply({s},{{3,10,10,4,10},{4,10,10,4,21}},0),0)
 end)
 test('reaction clocks pause and cap lost-snapshot prediction without accepting older clocks',function()
  local m=R.new(SM.hash);m.sync({20,1},100);near(m.time(101),20.2);m.sync({20,1},102);near(m.time(103),20.2)
  m.sync({20,0},103);near(m.time(200),20);m.sync({19,1},200);near(m.time(201),20);m.sync({21,1},201);near(m.time(201.1),21.1)
 end)
 test('dense repeated blasts prune affected soldiers from the working grid instead of retesting the whole crowd',function()
  local m=R.new(SM.hash);m.sync({10,0},0);local squads,rows={},{}
  for i=1,1000 do table.insert(squads,squad(i,10,10))end;for i=1,64 do table.insert(rows,{i,10,10,4,10})end
  eq(m.apply(squads,rows,0),1000);eq(m.stats().checked,1000);eq(next(m.buckets),nil);eq(m.entries[1].m,nil);eq(m.entries[1].sq,nil)
  local cap=m.stats().entries;m.sync({20,0},0);m.apply({squad(2000,10,10)},{{65,10,10,4,20}},0);eq(m.stats().entries,cap);eq(m.entries[1].m,nil)
 end)
 test('distant soldiers use spatial bins and small blasts never flinch the crowd',function()
  local m=R.new(SM.hash);m.sync({10,0},0);local squads={};for i=1,500 do table.insert(squads,squad(i,i*10,10))end
  eq(m.apply(squads,{{1,10,10,4,10}},0),1);assert(m.stats().checked<10)
  m.sync({20,0},0);eq(m.apply(squads,{{2,10,10,1.9,20}},0),0)
 end)
 local function input()return{x=5,y=5,vx=0,vy=0,hpFrac=1,firing=true,aimX=25,aimY=5,road=false,contact=false,cover=false,warTime=10}end
 test('a flinching soldier holds position and heading, then kneels and resumes the existing formation motion',function()
  local inp=input();local sq=SM.new(1,'infantry',inp);SM.step(sq,inp,0);local man=sq.men[1];man.flatUntil=11;local x,y,h=man.x,man.y,man.heading
  inp.vx=1;inp.warTime=10.1;SM.step(sq,inp,.1);eq(man.pose,'prone');eq(man.x,x);eq(man.y,y);eq(man.heading,h);eq(man.vx,0)
  inp.warTime=10.9;SM.step(sq,inp,.1);eq(man.pose,'kneel');eq(man.x,x)
  inp.warTime=11.1;SM.step(sq,inp,.1);assert(man.pose:find('walk'));assert(man.x>x)
 end)
 test('mortar crew flinch overrides its load pose while a restored squad member clears old reaction state',function()
  local inp=input();inp.mortar='set';inp.sinceShot=2;inp.shotLeft=.5;inp.phaseProgress=1;local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);sq.men[2].flatUntil=11
  inp.warTime=10.1;SM.step(sq,inp,.1);eq(sq.men[2].pose,'prone');eq(sq.tube.pose,'set')
  inp.hpFrac=.4;SM.step(sq,inp,0);eq(sq.men[2].up,false);inp.hpFrac=1;SM.step(sq,inp,0);eq(sq.men[2].flatUntil,0)
 end)
 test('actual prone sprite placement applies the source backward anchor to body and shadow together',function()
  local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function setFigure(',1,true));local b=assert(src:find('local function placeMen(',a,true));local shade
  local env=setmetatable({Facing={index=function()return 0 end,residual=function()return 0 end},SpriteBank={offset=function()return rb.Vector2.zero end},World={toWorld=function(x,y,z)return rb.Vector3.new(x*4,z,y*4)end},CFrame=rb.CFrame,GUI_YAW=0,SquadReaction=R,SquadMen=SM,SUN={X=0,Y=1},SHADOW_FADE=1,ManEffects={place=function(_,_,_,_,x,y)shade={x,y}end}},{__index=getfenv()})
  local place=luau.load(src:sub(a,b-1)..'\nreturn setFigure',{environment=env})();local ms={fig={poses={prone={colour=0,paint=0},stand={colour=0,paint=0}}},quad={},colour={},paint={}}
  place(ms,'prone',0,5,5,.4);assert(math.abs(ms.quad.CFrame.Position.X-(5-.57*SM.MAN_CELLS)*4)<1e-5);near(shade[1],5-.57*SM.MAN_CELLS)
  ms.fig.poses.prone=nil;place(ms,'prone',0,5,5,.4);near(ms.quad.CFrame.Position.X,20)
 end)
 test('actual client snapshot uses its current fog before accepting blast reactions and preserves old-server compatibility',function()
  local src=fs.readFile('src/client/init.client.luau');local a=assert(src:find('snapshot.OnClientEvent:Connect',1,true));local b=assert(src:find('-- Both listeners',a,true));local fn,ready,calls=nil,false,0
  local env=setmetatable({snapshot={OnClientEvent={Connect=function(_,cb)fn=cb end}},UnitRenderer={apply=function()end,react=function(tick,rows,war)assert(ready);eq(tick,10);eq(rows[1][4],4);eq(war[1],10);calls+=1 end},CivilianRenderer={snapshot=function()end},StructureRenderer={apply=function()end},FogOverlay={apply=function()ready=true end},CollapseRenderer={apply=function()end}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();fn(10,{},{},{},false,nil,nil,{{1,5,5,4,10}},{10,1});eq(calls,1);fn(11,{},{},{},false);eq(calls,1)
 end)
 test('actual server snapshots filter blast sources per side and never replay a transient for an unready arrival',function()
  local src=fs.readFile('src/server/Match/MatchService.luau');local a=assert(src:find('local function snapshot()',1,true));local b=assert(src:find('-- Own territory',a,true));local one,two,spec={},{},{};local ready={[one]=true,[spec]=true};local q={{1,2,2,4,10},{2,8,2,4,10}};local sent={}
  local env=setmetatable({sideOf={[one]=1,[two]=2,[spec]=0},readyView=ready,tick=10,sim={time=10,fogOn=function()return true end},viewers={[1]={visibleAt=function(x)return x<5 end},[2]={visibleAt=function(x)return x>5 end}},deaths={},collapses={},blasts=q,sentVision={},BlastEvents=E,CollapseEvents={visible=function()return{}end},viewFor=function()return{},{},nil end,Net={sendSnapshot=function(p,_tick,_units,_structures,_vision,_all,_deaths,_collapses,rows,war)sent[p]={rows,war}end}},{__index=getfenv()})
  local snapshot=luau.load(src:sub(a,b-1)..'\nreturn snapshot',{environment=env})();snapshot();eq(#sent[one][1],1);eq(sent[one][1][1][1],10*E.MAX+1);eq(#sent[spec][1],2);eq(sent[two],nil);eq(sent[one][2][1],10);eq(#q,0)
  ready[two]=true;snapshot();eq(sent[two][1],nil)
 end)
 test('actual authoritative blast bridge uses source weapon sizes while ignoring bullets and unknown profiles',function()
  local src=fs.readFile('src/server/Match/MatchService.luau');local a=assert(src:find('sim.presentBlast=function',1,true));local b=assert(src:find('\n\tdo',a,true));local sim={time=10};local q={}
  local env=setmetatable({sim=sim,blastSizes={shell=4,bullets=.4},BlastEvents=E,blastSequence=0,blasts=q,map={width=100,height=100}},{__index=getfenv()});luau.load(src:sub(a,b-1),{environment=env})();sim.presentBlast(5,5,'shell');sim.presentBlast(5,5,'bullets');sim.presentBlast(5,5,'unknown');sim.presentBlast(5,5,'wreck',2);eq(#q,2);eq(q[1][4],4);eq(q[2][4],2)
 end)
 test('actual client reaction receiver drops hidden sources, duplicate snapshots and hidden squads',function()
  local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('function UnitRenderer.react(',1,true));local b=assert(src:find('function UnitRenderer.reactionStats(',a,true));local sq=squad(1,5,5);local reaction=R.new(SM.hash);local hidden=true
  local env=setmetatable({UnitRenderer={},DeathRenderer={impacts=function()end},reactions=reaction,reactionTick=0,reactionWidth=100,reactionHeight=100,BlastEvents=E,S=4,FogOverlay={hidden=function()return hidden end},views={[1]={squad=sq,to=rb.Vector3.new(20,0,20)}},os={clock=function()return 0 end}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();env.UnitRenderer.react(1,{{1,5,5,4,10}},{10,0});eq(sq.men[1].flatUntil,0);hidden=false;env.UnitRenderer.react(2,{{2,5,5,4,10}},{10,0});assert(sq.men[1].flatUntil>10);local untilTime=sq.men[1].flatUntil
  env.UnitRenderer.react(2,{{3,5,5,4,11}},{11,0});eq(sq.men[1].flatUntil,untilTime)
  sq.men[1].flatUntil=0;env.views[1].statusCode=4;env.UnitRenderer.react(3,{{4,5,5,4,12}},{12,0});eq(sq.men[1].flatUntil,0)
 end)
 test('public blast ids count only visible rows instead of exposing hidden event sequence gaps',function()
  local visible=function(x)return x<5 end
  local a=E.visible({{1,2,2,4,10},{2,8,2,4,10}},visible,20)
  local b=E.visible({{30,8,2,4,10},{55,2,2,4,10}},visible,20)
  eq(a[1][1],b[1][1]);eq(a[1][1],20*E.MAX+1);eq(#a,1);eq(#b,1)
 end)

end
