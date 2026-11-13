--!strict
return function(test:any,eq:any)
	local C=require('../src/shared/Presentation/CrewMuzzle');local R=require('../src/shared/Presentation/RifleFire');local Motion=require('../src/shared/Presentation/CrewMotion')
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	-- Synthetic settings; no source-derived tables in this public suite.
	local cfg={men={aimSlack=.5,muzzleH={stand=.2,kneel=.1,prone=.05}},proneBack=.4,tubeRear=-.3,tubeRearProne=-.2,
		muzzle={gunner={stand={1,.2},kneel={.9,.2},prone={1.1,.1}},loader={stand={.8,.1},kneel={.7,.1}},tube={set={.6,0},kick={.4,.1},base={-.2,0}}},
		backblast={tipFlash=1,rearFlash=.8,rearSec=.1,puffs=3,cone=.3,reach=1.2,speed={1,3},size={.2,.8},life={.5,1},smokeEvery=2,dust=1,smoke=2,pale=3,grit=2,gritSpeed={2,4},ring=.4,ringTo=2,ringSec=.5},backblastOverrides={republic={reach=.4,smokeEvery=1,dust=6,smoke=7}},rocketSmoke=1,
		mortar={muzzleH=.3,flash=.6,flashSec=.1,ring=.2,ringTo=1,ringSec=.3,dust=2,kick=2,dustSize=.3,dustLife=.8,smoke=2,rise=1.5,smokeSize=.3,smokeLife=2,smokeColor=6,smokePale=7},
		colors={fire=8,hot=9,smokeLight=10,dustLight=11,debris=12},motion={rise=2,grow=1.5},ground={dust=13,dustPale=14,dustHang=1}}
	local function near(a,b)assert(math.abs(a-b)<1e-6,`{a} ~= {b}`)end
	local function rng()return .5 end
	local function visible()return false end
	local function squad()return {men={{kind='gunner',x=5,y=5,heading=0,pose='kneel',up=true},{kind='loader',x=4,y=6,heading=0,pose='kneel',up=true}},tube={x=5.1,y=5,heading=0,pose='kick'}}end
	local function active(army)
		local s=C.new(1);C.receive(s,9,1,0,20,5,{10,1},100,army);C.receive(s,.05,1,0,20,5,{10,1},100,army);return s
	end
	local function step(s,kind,b,out,hidden,wall)
		C.step(s,cfg,kind,squad(),5,5,.5,wall or 100,hidden or visible,function(p)table.insert(out,p);return true end,b,rng)
	end
	test('crew firing baselines first observations and emits a newly observed shot only once',function()
		local s=C.new(1);C.receive(s,.05,1,0,20,5,{10,1},100);eq(s.pending,nil)
		C.receive(s,.01,1,0,20,5,{10,1},100);assert(s.pending);local out={};local b=R.newBudget();R.begin(b,100)
		step(s,'at',b,out);eq(#out,11);local n=#out;step(s,'at',b,out);eq(#out,n)
		C.receive(s,.01,1,0,20,5,{10,1},100);eq(s.pending,nil)
	end)
	test('AT tip and rear follow the actual gunner pose including aim slack and prone anchor',function()
		local sq=squad();local t=C.tip(cfg,'at',sq,5,5,20,5,.5);near(t.x,5.45);near(t.y,5.1);near(t.rearX,4.85);near(t.rearY,t.y)
		local m=sq.men[1];m.pose='prone';m.heading=math.pi/2;t=C.tip(cfg,'at',sq,5,5,20,5,.5)
		near(t.x,5.55);near(t.y,4.85);near(t.rearX,4.9)
		m.up=false;t=C.tip(cfg,'at',sq,5,5,20,5,.5);assert(t.x<5,'surviving loader is the source fallback');sq.men[2].up=false;eq(C.tip(cfg,'at',sq,5,5,20,5,.5),nil)
	end)
	test('AT firing has separate front smoke rear plume grit and ring with republic-specific backblast',function()
		local outputs={}
		for _,army in {'coalition','republic'}do local b=R.newBudget();R.begin(b,100);local out={};step(active(army),'at',b,out);eq(#out,11);outputs[army]=out end
		local base,rep=outputs.coalition,outputs.republic
		eq(base[1].tex,'star');eq(base[3].wind,true);eq(base[4].tex,'star');assert(base[4].x<base[1].x)
		eq(base[6].ground,true);eq(base[7].wind,true);eq(base[9].tex,'px');assert(base[9].vx<0);eq(base[11].tex,'ring')
		eq(rep[6].wind,true);eq(rep[6].color,7);assert(math.abs(rep[8].x-rep[4].x)<math.abs(base[8].x-base[4].x));eq(cfg.backblast.reach,1.2)
	end)
	test('mortar kick and set use their actual tube offsets with a root fallback when travelling',function()
		local sq=squad();local t=C.tip(cfg,'mortar',sq,5,5,20,5,.5);near(t.x,5.3);near(t.y,5.05);near(t.h,.3)
		sq.tube.pose='set';sq.tube.heading=math.pi/2;t=C.tip(cfg,'mortar',sq,5,5,20,5,.5);near(t.x,5.1);near(t.y,5.3)
		sq.tube=nil;t=C.tip(cfg,'mortar',sq,5,5,5,20,.5);near(t.x,5);near(t.uy,1)
	end)
	test('mortar firing emits source ring radial ground dust and rising layered tube smoke',function()
		local b=R.newBudget();R.begin(b,100);local out={};step(active(),'mortar',b,out);eq(#out,7)
		eq(out[1].tex,'star');eq(out[2].glow,true);eq(out[3].ground,true);eq(out[4].ground,true);eq(out[4].color,13)
		eq(out[6].wind,true);eq(out[6].color,6);assert(out[7].h>out[6].h);assert(out[7].vh<out[6].vh)
	end)
	test('crew observation clocks pause cap stalls and discard late invalid garrisoned and reset events',function()
		local s=active();C.receive(s,.05,1,0,20,5,{10,0},100);local out={};local b=R.newBudget();R.begin(b,100);step(s,'at',b,out,nil,10000);eq(#out,11)
		s=active();R.begin(b,100);step(s,'at',b,out,nil,10000);eq(#out,22,'prediction stops after .2s');s=active();C.receive(s,.5,1,0,20,5,{12,1},102);step(s,'at',b,out,nil,102);eq(#out,22);eq(s.pending,nil)
		for _,bad in {false,{}, {0,1}}do s=active();C.receive(s,.01,1,0,20,5,bad,100);eq(s.pending,nil)end
		s=active();C.receive(s,.01,1,4,20,5,{10,1},100);eq(s.pending,nil);C.receive(s,.01,1,0,20,5,{10,1},100);eq(s.pending,nil)
		s=active();C.receive(s,0,1,0,20,5,{1,1},101);eq(s.pending,nil);C.cancel(s);eq(s.pending,nil)
	end)
	test('root and muzzle fog suppress crew firing without retaining an emission backlog',function()
		local out={};local b=R.newBudget();R.begin(b,100);local s=active();step(s,'at',b,out,function()return true end);eq(#out,0);eq(s.pending,nil)
		step(active(),'mortar',b,out,function(x)return x>5.2 end);eq(#out,0);eq(b.pulses,32)
		step(s,'at',b,out);eq(#out,0)
	end)
	test('refused crew particle requests stop immediately and mixed firing shares native request limits',function()
		local b=R.newBudget();R.begin(b,100);local attempts=0;local s=active()
		C.step(s,cfg,'at',squad(),5,5,.5,100,visible,function()attempts+=1;return false end,b,rng);eq(attempts,1);eq(s.pending,nil)
		local source=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(source:find('local function emitRifleParticle(',1,true));local z=assert(source:find('local UnitRenderer =',a,true))
		local env=setmetatable({rifleBudget=b,DeathRenderer={request=function(_,_,tag)eq(tag,b);attempts+=1;return true end}},{__index=getfenv()})
		local emit=luau.load(source:sub(a,z-1)..'\nreturn emitRifleParticle',{environment=env})();R.begin(b,100);attempts=0
		for i=1,3000 do s=active();C.step(s,cfg,if i%2==0 then 'at'else 'mortar',squad(),5,5,.5,100,visible,emit,b,rng);eq(s.pending,nil)end
		eq(attempts,128);eq(b.particles,0);eq(b.prepares,0);eq(b.pulses,0)
	end)
	test('public AT army appends only a compatible optional crew field and legacy packets reset its palette',function()
		local p=Motion.snapshot({kind='at',alive=true,shotTimer=1},10,true,2,1,'republic');eq(#p,6);eq(p[6],'republic')
		eq(#Motion.snapshot({kind='mortar',alive=true},10,true,2,1,'republic'),5)
		local s={};Motion.receive(s,p,100);eq(s.army,'republic');p[6]=nil;Motion.receive(s,p,100);eq(s.army,'coalition');Motion.receive(s,nil,100);eq(s.army,'coalition')
	end)
	test('actual client snapshot uses visible shot age clock and public crew army and clears legacy clocks',function()
		local source=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(source:find('v.statusCode, v.sinceShot =',1,true));local z=assert(source:find('v.turretWant =',a,true))
		local v={id=1,kind='at',flags=1,aimX=20,aimY=5};local row={[9]=0,[15]=9,[19]={1,0,0,10,1,'republic'}};local war={10,1}
		local env=setmetatable({v=v,u=row,kind='at',war=war,CrewMotion=Motion,CrewMuzzle=C,VehicleRecoil=require('../src/shared/Presentation/VehicleRecoil'),RifleFire=R,os={clock=function()return 100 end}},{__index=getfenv()})
		local apply=luau.load(source:sub(a,z-1),{environment=env});apply();eq(v.crewMuzzle.pending,nil);row[15]=.05;apply();eq(v.crewMuzzle.pending.army,'republic')
		war[2]=nil;apply();eq(v.crewMuzzle.pending,nil)
	end)
	test('actual server appends public AT faction only after visibility filtering without changing other rows',function()
		local source=fs.readFile('src/server/Match/MatchService.luau');local a=assert(source:find('local function viewFor(',1,true));local z=assert(source:find('-- vehicles destroyed',a,true))
		local units={};for id,kind in {'at','mortar','infantry','at'}do units[id]={id=id,cat='unit',kind=kind,side=2,alive=true,x=5,y=5,heading=0,hp=100,maxHp=100,shotTimer=.5,still=2}end
		local calls=0;local sim={list=units,time=10,armyOf=function(side)eq(side,2);calls+=1;return 'republic'end}
		local viewer={update=function()end,unitVisible=function(e)return e.id~=4 end,lastSeen={},runs=function()return{}end}
		local env=setmetatable({sim=sim,viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},rules={data={['mortar.setupSec']=2,['mortar.packSec']=1}},CrewMotion=Motion,VehicleRecoil=require('../src/shared/Presentation/VehicleRecoil'),unitLook=function()return 1,20,5,.05 end,unitStatus=function()return 0 end,unitStage=function()return 0 end},{__index=getfenv()})
		local view=luau.load(source:sub(a,z-1)..'\nreturn viewFor',{environment=env})();local rows=view(1)
		eq(#rows,3);eq(rows[1][19][6],'republic');eq(#rows[2][19],5);eq(#rows[3],18);eq(calls,1,'hidden AT army is not sampled')
	end)
	test('actual crew placement emits after positioning the current mortar tube and skips garrison visuals',function()
		local source=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(source:find('local function placeMen(',1,true));local z=assert(source:find('-- seconds a mortar',a,true))
		local sq=squad();local out={};local b=R.newBudget();R.begin(b,100);local placed=false
		local v={id=1,kind='mortar',from=rb.Vector3.zero,to=rb.Vector3.zero,hpFrac=1,flags=1,aimX=20,aimY=5,statusCode=0,sinceShot=.05,t=1,men={},squad=sq,tube={gui={}},crewMuzzle=active()}
		local env=setmetatable({CrewMotion=Motion,CrewMuzzle=C,crewMuzzleConfig=cfg,SquadMen={MAN_CELLS=.5,step=function()end},reactions={time=function()return 10 end},S=4,SNAPSHOT_SEC=.1,mortarSec={setting=2,packing=1},SPRITE_Y=0,World={GROUND_Y=0},os={clock=function()return 100 end},FogOverlay={hidden=visible},rifleBudget=b,emitRifleParticle=function(p)assert(placed,'tube pose must be drawn first');table.insert(out,p);return true end,setFigure=function()placed=true end},{__index=getfenv()})
		local place=luau.load(source:sub(a,z-1)..'\nreturn placeMen',{environment=env})();place(v,rb.Vector3.new(20,.4,20),0);eq(#out,7);near(out[1].x,5.3);near(out[1].y,5.05)
		v.statusCode=4;v.crewMuzzle=active();place(v,rb.Vector3.new(20,.4,20),0);eq(#out,7);eq(v.crewMuzzle.pending,nil)
	end)
end
