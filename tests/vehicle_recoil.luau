--!strict
return function(test:any,eq:any)
 local M=require('../src/shared/Presentation/VehicleRecoil');local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
 local function near(a,b)assert(math.abs(a-b)<1e-5,`{a} ~= {b}`)end
 local function state(aim:number?)local s=M.new();M.receive(s,{0,false,0,{}},{10,1},0);M.receive(s,{1,10,aim or 0,{}},{10,1},0);return s end
 test('vehicle recoil begins only after a newly observed visible shot and follows the source backwards direction',function()
  local s=state();local x,y,slide=M.pose(s,'tank',1.3,1.3,0);near(x,-.16);near(y,0);near(slide,.09*1.3)
  s=state(math.pi/2);x,y=M.pose(s,'tank',1.3,1.3,0);near(x,0);near(y,-.16)
  s=M.new();M.receive(s,{7,10,0,{}},{10,1},0);eq(M.pose(s,'tank',1.3,1.3,0),0)
 end)
 test('source twelve-frame recoil holds within a frame and returns to rest with its signed overshoot',function()
  eq(M.wave('tank',.01),M.wave('tank',.08));assert(M.wave('tank',.25)<0);eq(M.wave('tank',.5),0);eq(M.wave('truck',0),0);eq(M.wave('tank',-1),0)
 end)
 test('IFV repeated rounds and authoritative irregular rocket offsets replay each source recoil pulse',function()
  for _,at in {0,.2,.4,.600000001}do near(M.wave('ifv',at),1)end;eq(M.wave('ifv',.8),0)
  local offsets={0,.4,1.2};near(M.wave('rocket',.4,offsets),1);eq(M.wave('rocket',1.1,offsets),0);near(M.wave('rocket',1.2,offsets),1);eq(M.wave('rocket',2,offsets),0)
 end)
 test('recoil pause and stalled prediction use shared snapshot war time without accumulating displacement',function()
  local s=state();M.receive(s,{1,10,0,{}},{10,0},.01);local x,y,slide=M.pose(s,'tank',1.3,1.3,100);near(x,-.16);near(slide,.117)
  M.receive(s,{1,10,0,{}},{10,1},100);near(M.time(s,101),10.2);M.receive(s,{1,10,0,{}},{10,1},102);near(M.time(s,103),10.2)
  M.receive(s,{1,10,0,{}},{11,1},104);eq(M.pose(s,'tank',1.3,1.3,104),0)
 end)
 test('late observations, sequence resets and older rows cannot restart an old firing animation',function()
  local s=M.new();M.receive(s,{0,false,0,{}},{10,1},0);M.receive(s,{1,9,0,{}},{10,1},0);eq(M.pose(s,'tank',1.3,1.3,0),0)
  M.receive(s,{2,10,0,{}},{10,1},0);assert(M.pose(s,'tank',1.3,1.3,0)~=0);M.receive(s,{0,false,0,{}},{10,1},0);eq(M.pose(s,'tank',1.3,1.3,0),0)
  M.receive(s,nil,nil,0);eq(s.sequence,nil);eq(s.shotAt,-math.huge)
 end)
 test('changing deployed art scale preserves the original ratio of body shove and turret slide',function()
  local s=state();local x,y,slide=M.pose(s,'tank',2.6,1.3,0);near(x,-.32);near(slide,.234);near(y,0)
 end)
 test('server baselines old firing and retains only a newly visible shot direction',function()
  local e={kind='tank',alive=true,id=1,x=10,y=10,heading=0,turret=1,firedAt=9,aimX=20,aimY=10};local sim={time=10}
  local p,known=M.snapshot(e,nil,sim);eq(p[1],0);eq(p[2],false);e.firedAt=10;p,known=M.snapshot(e,known,sim);eq(p[1],1);eq(p[2],10);near(p[3],0)
  e.aimX,e.aimY=10,30;local after,nextKnown=M.snapshot(e,known,sim);eq(after[3],0);eq(nextKnown,known)
  p=M.snapshot(e,nil,sim);eq(p[2],false);eq(M.snapshot({kind='infantry'},nil,sim),nil)
 end)
 test('server builds each rocket schedule only at a new observed salvo using the simulation seed and pattern',function()
  local calls=0;local sim={time=10,rules={number=function()return 8 end},salvoSeed=function(id,time)eq(id,4);eq(time,10);return 123 end,salvoPattern=function(seed,count,gap)eq(seed,123);eq(count,8);eq(gap,.75);calls+=1;return{{at=0},{at=.43},{at=1.1}}end}
  local e={id=4,kind='rocket',alive=true,x=5,y=5,heading=0};local _,before=M.snapshot(e,nil,sim);e.firedAt=10;local p,known=M.snapshot(e,before,sim);eq(#p[4],3);eq(p[4][2],.43);M.snapshot(e,known,sim);eq(calls,1)
  sim.time=20;p=M.snapshot(e,known,sim);eq(#p[4],0)
 end)
 test('actual server unit rows preserve crew/civilian fields and reset firing observations after fog',function()
  local src=fs.readFile('src/server/Match/MatchService.luau');local a=assert(src:find('local function viewFor(',1,true));local b=assert(src:find('-- vehicles destroyed',a,true));local e={id=1,kind='tank',cat='unit',alive=true,x=5,y=5,heading=0,side=2,hp=100,maxHp=100,hitAt=9,firedAt=9,aimX=15,aimY=5};local show=true
  local sim={list={e},time=10};local viewer={update=function()end,unitVisible=function()return show end,lastSeen={},runs=function()return{}end}
  local env=setmetatable({sim=sim,viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},CrewMotion={snapshot=function()return nil end},VehicleRecoil=M,rules={data={}},unitLook=function()return 1,15,5,1 end,unitStatus=function()return 0 end,unitStage=function()return 0 end},{__index=getfenv()})
  local view=luau.load(src:sub(a,b-1)..'\nreturn viewFor',{environment=env})();local rows=view(1);eq(#rows[1],20);eq(rows[1][18],1);eq(rows[1][19],false);eq(rows[1][20][2],false)
  e.firedAt=10;rows=view(1);eq(rows[1][20][1],1);eq(rows[1][20][2],10);show=false;eq(#view(1),0);show=true;e.firedAt=10.1;sim.time=10.1;rows=view(1);eq(rows[1][20][1],0);eq(rows[1][20][2],false)
 end)
 test('actual vehicle renderer moves body and turret art while keeping authoritative body and selection anchors fixed',function()
  local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function place(v:',1,true));local b=assert(src:find('local mortarSec',a,true));local look={size=1.3,cells=2.6,turret={}};local fx
  local v={kind='tank',vehicle=state(),look=look,base=look,body={Size=rb.Vector3.new(4,.1,4)},model={FindFirstChild=function()return{}end},ring={},from=rb.Vector3.zero,to=rb.Vector3.zero,t=1,turretAt=0,turretWant=0,sprites={{quad={},colour={},paint={},rise=0,facing=-1},{turret=true,quad={},colour={},paint={},rise=0,facing=-1}},fx={{}},facing=-1}
  local env=setmetatable({VehicleRecoil=M,Vector3=rb.Vector3,CFrame=rb.CFrame,Vector2=rb.Vector2,S=4,SPRITE_Y=0,GUI_YAW=0,TURRET_FOLLOW=20,os={clock=function()return 0 end},Facing={index=function()return 0 end,residual=function()return 0 end},SpriteBank={offset=function()return rb.Vector2.zero end},turretAt=function(_,pos)return pos end,updateStage=function()end,sootOf=function()return 0 end,placeFx=function(_,_,pos,_,_,slide)fx={pos,slide}end},{__index=getfenv()})
  local place=luau.load(src:sub(a,b-1)..'\nreturn place',{environment=env})();place(v,rb.Vector3.new(20,1,20),0,0);near(v.body.CFrame.Position.X,20);near(v.sprites[1].quad.CFrame.Position.X,20-.16*4);near(v.sprites[2].quad.CFrame.Position.X,20-(.16+.117)*4);near(fx[1].X,20-.16*4);near(fx[2],.117)
 end)
 test('actual vehicle shadow and rim renderer applies the same turret slide to its existing shared layers',function()
  local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function placeFx(',1,true));local b=assert(src:find('local MAST',a,true));local sheet={frame=120,content={},strips={hull=0,turret=120}};local look={size=1.3,cells=2.6,body={base='hull'},turret={base='turret'},fx={rim=sheet,shade=sheet}}
  local function layer(kind,part)return{kind=kind,layer=part,quad={},gui={},image={},alpha=.34,facing=-1,y0=-1}end;local v={fx={layer('shadow','body'),layer('shadow','turret'),layer('rim','turret')}}
  local env=setmetatable({workspace={},HALF_BELOW=72,S=4,SUN={X=0,Y=1},SHADOW_FADE=1,SPRITE_Y=0,GUI_YAW=0,TURRET_SHADOW={reach=.035},Vector3=rb.Vector3,Vector2=rb.Vector2,CFrame=rb.CFrame,shadowOf=function()return 0,0,1 end,turretAt=function(_,pos)return pos end,Facing={index=function()return 0 end,residual=function()return 0 end},SpriteBank={bind=function()end,offset=function()return rb.Vector2.zero end}},{__index=getfenv()})
  local place=luau.load(src:sub(a,b-1)..'\nreturn placeFx',{environment=env})();place(v,look,rb.Vector3.new(19.36,1,20),0,0,.117);near(v.fx[1].quad.CFrame.Position.X,19.36);near(v.fx[2].quad.CFrame.Position.X,19.36-.117*4);near(v.fx[3].quad.CFrame.Position.X,19.36-.117*4)
 end)
 test('actual client snapshot passes shared war time into vehicle animation without changing previous arguments',function()
  local src=fs.readFile('src/client/init.client.luau');local a=assert(src:find('snapshot.OnClientEvent:Connect',1,true));local b=assert(src:find('-- Both listeners',a,true));local callback;local war={10,0};local received
  local env=setmetatable({snapshot={OnClientEvent={Connect=function(_,fn)callback=fn end}},UnitRenderer={apply=function(tick,units,deaths,clock)eq(tick,1);received=clock end,react=function()end},CivilianRenderer={snapshot=function()end},StructureRenderer={apply=function()end},FogOverlay={apply=function()end},CollapseRenderer={apply=function()end}},{__index=getfenv()})
  luau.load(src:sub(a,b-1),{environment=env})();callback(1,{},{},nil,false,nil,nil,nil,war);eq(received,war)
 end)
end

