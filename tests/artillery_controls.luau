--!strict
return function(test:any,eq:any)
 local M=require('../src/shared/Presentation/ArtilleryControls');local P=require('../src/shared/Protocol/Protocol')
 local fs=require('@lune/fs');local luau=require('@lune/luau')
 local rules={['artyBase.barrage.price']=15,['artyBase.flare.price']=3,['artyBase.range']=100}
 local function fixture()
  local views={[7]={id=7,kind='artybase',side=1,hp=100,built=1,x=20,y=20},[8]={id=8,kind='artybase',side=1,hp=100,built=1,x=40,y=40}}
  local m=M.new(1,rules);M.pick(m,7,'artybase');M.update(m,{kills=30,artyBases={{7,0,0,false},{8,0,0,false}},oil=100});return m,views
 end
 test('artillery controls use selected base with source prices and correlated server acknowledgments',function()
  local m,v=fixture();assert(M.arm(m,v,'barrage'));local i=M.fire(m,v,45,55,2);eq(i.structureId,7);eq(i.power,'barrage');assert(P.parse(i,200,200));eq(M.fire(m,v,45,55,2),nil)
  M.update(m,{artyResult={8,'barrage',i.requestId,true,false}});assert(m.pending)
  M.update(m,{artyResult={7,'barrage',i.requestId+1,true,false}});assert(m.pending)
  M.update(m,{artyResult={7,'barrage',i.requestId,true,false}});eq(m.pending,nil);eq(m.note,'Barrage launched')
 end)
 test('artillery readiness rejects missing status, cooldown, damaged, unfinished, hidden and enemy bases',function()
  local m,v=fixture();m.status={};assert(not M.arm(m,v,'barrage'));m.status={[7]={7,4,0,false}};assert(not M.arm(m,v,'barrage'));assert(M.arm(m,v,'flare'));M.cancel(m)
  m.status[7]={7,0,0,'damaged'};assert(not M.arm(m,v,'flare'));m.status[7][4]=false;m.kills=2;assert(not M.arm(m,v,'flare'));m.kills=30
  for _,change in {{'built',.5},{'hp',0},{'stale',true},{'side',2}} do local old=v[7][change[1]];v[7][change[1]]=change[2];assert(not M.arm(m,v,'flare'));v[7][change[1]]=old end
 end)
 test('out of range targeting stays armed and cancellation or ownership loss cannot send',function()
  local m,v=fixture();assert(M.arm(m,v,'flare'));eq(M.fire(m,v,150,150,0),nil);eq(m.mode,'flare');eq(m.pending,nil)
  M.cancel(m);eq(M.fire(m,v,21,21,0),nil);assert(M.arm(m,v,'flare'));v[7].side=2;eq(M.fire(m,v,21,21,0),nil);eq(m.mode,nil)
 end)
 test('selection changes, match state and partial updates do not resurrect targets or clear an unrelated pending reply',function()
  local m,v=fixture();assert(M.arm(m,v,'flare'));local i=M.fire(m,v,21,21,1);M.pick(m,8,'artybase');M.update(m,{artyResult={7,'flare',i.requestId,false,'cooldown'}});eq(m.note,'');eq(m.pending,nil)
  assert(M.arm(m,v,'barrage'));M.update(m,{houseFires={}});eq(m.mode,'barrage');M.update(m,{oil=100,drop={phase='pick'}});eq(m.mode,nil);assert(not M.arm(m,v,'barrage'))
  M.update(m,{oil=100});assert(M.arm(m,v,'barrage'));M.update(m,{winner=1});eq(m.mode,nil);assert(not M.arm(m,v,'flare'))
 end)
 test('timed out requests allow a retry and obsolete acknowledgments cannot finish the newer request',function()
  local m,v=fixture();M.arm(m,v,'flare');local old=M.fire(m,v,21,21,0);M.expire(m,6);eq(m.pending,nil);M.arm(m,v,'flare');local fresh=M.fire(m,v,21,21,6)
  M.update(m,{artyResult={7,'flare',old.requestId,true,false}});eq(m.pending.request,fresh.requestId);M.pick(m,nil,nil);eq(M.base(m,v),nil)
 end)
 test('power protocol preserves legacy hotkeys and rejects malformed base or correlation fields',function()
  assert(P.parse({kind='power',power='barrage',x=2,y=3},100,100))
  for _,fields in {{structureId=0},{structureId=1.5},{structureId=math.huge},{structureId=2,requestId=0},{structureId=2,requestId=0/0},{requestId=1},{structureId='2'},{structureId=2,requestId=2147483648},{structureId=2,power='drone'}} do
   local raw={kind='power',power='barrage',x=2,y=3};for k,val in fields do raw[k]=val end;eq(P.parse(raw,100,100),nil)
  end
 end)
 test('actual server intent targets only the explicit base while legacy hotkeys still choose nearest eligible',function()
  local source=fs.readFile('src/server/Match/MatchService.luau');local a=assert(source:find('local function onIntent(',1,true));local b=assert(source:find('local function assignSide(',a,true));local player={Name='test'};local sent,calls={},{}
  local sim={list={{id=7,alive=true,kind='artybase',side=1,x=1,y=1},{id=8,alive=true,kind='artybase',side=1,x=10,y=10}},artyProblem=function() return nil end,artyStrike=function(side,id,kind,x,y) table.insert(calls,{side,id,kind,x,y});return id==8,if id==8 then nil else 'notOwned' end}
  local env=setmetatable({Protocol=P,sideOf={[player]=1},map={width=100,height=100},sim=sim,Net={sendState=function(_,value) table.insert(sent,value) end},warn=function() error('unexpected warning') end},{__index=getfenv()})
  local handle=luau.load(source:sub(a,b-1)..'\nreturn onIntent',{environment=env})();handle(player,{kind='power',power='barrage',structureId=7,requestId=4,x=10,y=10});eq(#calls,1);eq(calls[1][2],7);eq(sent[1].artyResult[4],false);eq(sent[1].artyResult[3],4)
  handle(player,{kind='power',power='flare',x=10,y=10});eq(#calls,2);eq(calls[2][2],8)
 end)
 test('actual private artillery rows reveal only own bases and preserve the existing ready aggregate',function()
  local source=fs.readFile('src/server/Match/MatchService.luau');local a=assert(source:find('local artyB, artyF',1,true));local b=assert(source:find('local airfields',a,true));local payload={}
  local sim={time=10,list={{id=7,alive=true,kind='artybase',side=1,strikeReady={barrage=12.2}},{id=8,alive=true,kind='artybase',side=1,reason='damaged'},{id=9,alive=true,kind='artybase',side=2},{id=10,alive=false,kind='artybase',side=1}},inactiveReason=function(e) return e.reason end}
  luau.load(source:sub(a,b-1),{environment=setmetatable({sim=sim,side=1,payload=payload},{__index=getfenv()})})();eq(#payload.artyBases,2);eq(payload.artyBases[1][2],3);eq(payload.artyBases[2][4],'damaged');eq(payload.arty[1],3);eq(payload.arty[2],0)
 end)
end
