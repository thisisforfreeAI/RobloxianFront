--!strict
return function(test:any,eq:any)
 local M=require('../src/shared/Presentation/CrewMotion');local SM=require('../src/client/Rendering/SquadMen');local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
 local function near(a,b) assert(math.abs(a-b)<1e-9,`{a} ~= {b}`) end
 local function input()return {x=5,y=5,vx=0,vy=0,hpFrac=1,firing=true,aimX=25,aimY=5,road=false,contact=false,cover=false,mortar='set',phaseSec=2,sinceShot=2,shotLeft=.5,phaseProgress=1}end
 test('crew samples retain actual reload and source setup/packing progress without mutating simulation',function()
  local e={alive=true,kind='mortar',shotTimer=1.25,still=1.2};local p=M.snapshot(e,10,true,2,1.5);eq(#p,5);eq(p[1],1.25);eq(p[2],1);near(p[3],.6);eq(p[4],10);eq(p[5],1);eq(e.shotTimer,1.25)
  e.packAt=10.6;p=M.snapshot(e,10,false,2,1.5);eq(p[2],2);near(p[3],.6);eq(p[5],0)
  e.packAt=nil;e.path={};eq(M.snapshot(e,10,true,2,1.5)[2],0);e.path=nil;e.still=2;eq(M.snapshot(e,10,true,2,1.5)[2],3)
  eq(M.snapshot({kind='infantry',alive=true},0,true,2,1),nil);eq(M.snapshot({kind='mortar',alive=false},0,true,2,1),nil)
 end)
 test('crew prediction caps stalled snapshots and freezes reload and shot age on a paused match',function()
  local s={};M.receive(s,{2,1,.25,10,1},100);local left,phase,progress,age=M.sample(s,101,.05,2,1);near(left,1.8);eq(phase,'setting');near(progress,.35);near(age,.25)
  M.receive(s,{2,1,.25,10,1},102);near(M.sample(s,103,.05,2,1),1.8)
  M.receive(s,{2,1,.25,10,0},103);left,phase,progress,age=M.sample(s,1000,.05,2,1);near(left,2);near(progress,.25);near(age,.05)
  M.receive(s,{2,1,.25,10,1},1000);near(M.sample(s,1000.1,.05,2,1),1.9)
 end)
 test('older/missing crew packets clear observed reloads and preserve fallback shot age',function()
  local s={};M.receive(s,{.4,3,1,10,1},20);M.receive(s,nil,21);local left,phase,progress,age=M.sample(s,30,9,2,1);eq(left,nil);eq(phase,nil);eq(progress,nil);eq(age,9)
  for _,bad in {false,{}, {1,99,0,0,1}} do M.receive(s,bad,0);eq(s.packet,nil) end
 end)
 test('mortar bearer uses original load pose, position and quarter-turn in the last 0.6 seconds',function()
  local inp=input();local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);eq(sq.tube.pose,'set');eq(sq.men[2].pose,'load');near(sq.men[2].x,5+.5*SM.MAN_CELLS);near(sq.men[2].y,5+.62*SM.MAN_CELLS);near(sq.men[2].heading,-math.pi/2)
  eq(sq.men[1].pose,'kneel');near(sq.men[1].heading,0)
 end)
 test('mortar kick/duck, setup, packing, idle and travel take precedence over loading',function()
  for _,change in {{sinceShot=.05},{shotLeft=.60001},{firing=false},{mortar='setting',phaseProgress=.2},{mortar='packing',phaseProgress=.8},{vx=1}} do
   local inp=input();for k,v in change do inp[k]=v end;local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);assert(sq.men[2].pose~='load')
  end
  local inp=input();inp.sinceShot=.2;inp.shotLeft=1;local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);near(sq.men[2].heading,2.3)
 end)
 test('mortar first sighting uses authoritative half-progress instead of restarting deployment locally',function()
  local inp=input();inp.mortar='setting';inp.phaseProgress=.75;local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);eq(sq.tube.pose,'set')
  inp.mortar='packing';inp.phaseProgress=.8;SM.step(sq,inp,0);eq(sq.tube.pose,'base')
 end)
 test('AT loader faces the surviving gunner only above the original reload-ready threshold',function()
  for _,remaining in {1,.7} do
   local inp=input();inp.mortar=nil;inp.shotLeft=remaining;local sq=SM.new(1,'at',inp);SM.step(sq,inp,0)
   local loader,gunner=sq.men[2],sq.men[1];local expected=if remaining>.7 then math.atan2(gunner.y-loader.y,gunner.x-loader.x) else math.atan2(inp.aimY-loader.y,inp.aimX-loader.x)
   near(loader.heading,expected);eq(loader.pose,'kneel')
  end
 end)
 test('legacy reload omission retains kneeling crews and existing infantry poses',function()
  local inp=input();inp.shotLeft=nil;local sq=SM.new(1,'mortar',inp);SM.step(sq,inp,0);eq(sq.men[2].pose,'kneel')
  inp.mortar=nil;inp.shotLeft=3;sq=SM.new(1,'infantry',inp);SM.step(sq,inp,0);for _,m in sq.men do eq(m.pose,'kneel') end
 end)
 test('actual server view appends optional field 19 only for visible crews and leaves field 18 intact',function()
  local source=fs.readFile('src/server/Match/MatchService.luau');local a=assert(source:find('local function viewFor(',1,true));local b=assert(source:find('-- vehicles destroyed',a,true));local units={}
  for id,kind in {'mortar','at','infantry','mortar'} do table.insert(units,{id=id,cat='unit',kind=kind,alive=true,show=id~=4,side=if id==2 then 2 else 1,x=5,y=5,heading=0,hp=100,maxHp=100,shotTimer=.5,still=2,hitAt=9.5}) end
  local viewer={update=function()end,unitVisible=function(e)return e.show end,lastSeen={},runs=function()return{}end}
  local env=setmetatable({sim={list=units,time=10},viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},rules={data={['mortar.setupSec']=2,['mortar.packSec']=1}},CrewMotion=M,VehicleRecoil=require("../src/shared/Presentation/VehicleRecoil"),unitLook=function()return 1,25,5,2 end,unitStatus=function()return 0 end,unitStage=function()return 0 end},{__index=getfenv()})
  local view=luau.load(source:sub(a,b-1)..'\nreturn viewFor',{environment=env})();local rows=view(1);eq(#rows,3);eq(#rows[1],19);eq(rows[1][18],.5);eq(rows[1][19][1],.5);eq(rows[2][19][2],0);eq(#rows[3],18)
 end)
 test('actual client crew placement passes sampled load art through the existing figure renderer',function()
  local source=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(source:find('local function placeMen(',1,true));local b=assert(source:find('-- seconds a mortar',a,true));local drawn={};local now=20
  local env=setmetatable({SquadMen=SM,CrewMotion=M,reactions={time=function()return 0 end},S=4,SNAPSHOT_SEC=.1,mortarSec={setting=2,packing=1},SPRITE_Y=.1,World={GROUND_Y=0},os={clock=function()return now end},setFigure=function(_,pose,heading,x,y) table.insert(drawn,{pose,heading,x,y}) end},{__index=getfenv()})
  local place=luau.load(source:sub(a,b-1)..'\nreturn placeMen',{environment=env})();local v={id=1,kind='mortar',from=rb.Vector3.zero,to=rb.Vector3.zero,statusCode=0,hpFrac=1,flags=1,aimX=25,aimY=5,inTrench=false,sinceShot=2,t=1,crew={},men={{gui={}},{gui={}}},tube={gui={}}}
  M.receive(v.crew,{.5,3,1,10,0},now);place(v,rb.Vector3.new(20,.4,20),0);eq(drawn[2][1],'load');eq(drawn[3][1],'set');eq(v.men[2].gui.Enabled,true)
  M.receive(v.crew,nil,now);drawn={};place(v,rb.Vector3.new(20,.4,20),0);eq(drawn[2][1],'kneel')
 end)
 test('actual client snapshot assignment clears missing crew state rather than retaining a stale reload',function()
  local source=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(source:find('v.statusCode, v.sinceShot =',1,true));local b=assert(source:find('v.turretWant =',a,true));local v={kind='mortar',crew={}};local row={[9]=0,[15]=2,[19]={.4,3,1,10,0}}
  local env=setmetatable({v=v,u=row,CrewMotion=M,CrewMuzzle=require("../src/shared/Presentation/CrewMuzzle"),VehicleRecoil=require("../src/shared/Presentation/VehicleRecoil"),kind="mortar",RifleFire=require("../src/shared/Presentation/RifleFire"),os={clock=function()return 20 end}},{__index=getfenv()});local apply=luau.load(source:sub(a,b-1),{environment=env});apply();eq(v.crew.packet[1],.4);row[19]=nil;apply();eq(v.crew.packet,nil)
 end)
end



