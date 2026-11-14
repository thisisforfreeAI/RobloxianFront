--!strict
return function(test:any,eq:any)
	local H=require('../src/shared/Presentation/HeavyMuzzle');local M=require('../src/shared/Presentation/VehicleMuzzle');local V=require('../src/shared/Presentation/VehicleRecoil');local R=require('../src/shared/Presentation/RifleFire')
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	-- Synthetic configuration: no original settings/tables in public tests.
	local cfg={gun={artillery=1},gunHeight=.2,unitMuzzleHeight=.4,colors={fire=1,hot=2,ember=3,smoke=4,smokeLight=5,dust=6,dustLight=7},motion={rise=2,grow=1.5},sparks={muzzle=1,size={.1,.2},speed={2,4},life={.1,.3}},
		ground={dust=8,dustPale=9},groundMotion={dustHeight=.04,dustRise=.1,grow=1},muzzleDust={puffs=2,big=1,from=.2,kick=2,size=.4,life=1},
		artillery={flash=3,flashSec=.1,ball=1,ballSec=.2,brake=.8,smoke=2,smokeSize=.5,smokeLife=1,smokeKick=2,dust=2,dustFrom=.5,dustSize=.5,dustLife=1,kick=2,front=1,ringSize=.5,ringTo=2,ringSec=.4,lingerSec=1,lingerPerSec=40,lingerSize=.2,lingerLife=.8},
		rocket={flash=1,backblast=2,backblastSpeed=3,backblastSize=.5,backblastLife=1,embers=1,cloud=1,cloudBack=1,cloudSpread=.8,cloudSize=.6,cloudLife=2,cloudRise=.4,cloudColor=10,haze=2,hazeLife=2},tbm={flash=2,muzzleSmoke=3}}
	local function near(a,b)assert(math.abs(a-b)<1e-6,`{a} ~= {b}`)end
	local function rng()return .5 end
	local function visible()return false end
	local function active(kind,weapon,offsets)
		local ride=V.new();local s=M.new();V.receive(ride,{0,false,0,{},'coalition'},{10,1},0);M.receive(s,ride,20,5)
		V.receive(ride,{1,10,0,offsets or {},'coalition',weapon},{10,1},0);M.receive(s,ride,20,5);M.place(s,5,5,4.8,5,0,4.8,5);return s,ride
	end
	local function step(s,ride,kind,time,b,out,hidden,wet)
		M.step(s,ride,cfg,kind,time,hidden or visible,function(p)table.insert(out,p);return true end,b,rng,wet)
	end
	test('howitzer fire has a hot axial flash fireball side brakes sparks smoke and earth dust',function()
		local s,ride=active('artillery');local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'artillery',10,b,out)
		eq(#out,14);eq(out[1].tex,'star');eq(out[2].tex,'blobB');eq(out[3].tex,'disc');near(out[4].x,out[5].x);assert(out[4].y>out[5].y)
		eq(out[6].tex,'spark');eq(out[8].color,cfg.colors.smoke);eq(out[9].color,cfg.colors.smokeLight);eq(out[10].ground,true);eq(out[14].tex,'ring');assert(s.linger)
	end)
	test('howitzer ground dust and muzzle ring use independent root and muzzle water checks',function()
		local tip={x=6,y=5,h=.2,ux=1,uy=0};local function collect(wet)local out={};H.howitzer(cfg,tip,{x=5,y=5},function(p)table.insert(out,p);return true end,rng,wet);return out end
		local dry=collect(visible);local water=collect(function()return true end);eq(#dry,14);eq(#water,9);for _,p in water do assert(not p.ground)end
		local rootWet=collect(function(x)return x<5.5 end);eq(#rootWet,12);eq(rootWet[#rootWet].tex,'ring')
		local muzzleWet=collect(function(x)return x>5.5 end);eq(#muzzleWet,11);assert(muzzleWet[#muzzleWet].ground);assert(muzzleWet[#muzzleWet].tex~='ring')
	end)
	test('rocket salvos follow authoritative irregular timing alternate rail offsets and emit haze only on the last launch',function()
		local s,ride=active('rocket',nil,{0,.43,1.1});local b=R.newBudget();local out={};local stars={}
		for _,time in {10,10.43,11.1}do R.begin(b,time);local before=#out;step(s,ride,'rocket',time,b,out);table.insert(stars,out[before+1]);eq(#out-before,if time==11.1 then 9 else 7)end
		near(stars[1].x,5.1);near(stars[1].y,4.57);near(stars[2].y,5.37);near(stars[3].y,4.69);eq(s.events,nil);eq(s.linger,nil)
	end)
	test('rocket launch plume goes behind the rack and follows its current drawn body position',function()
		local s,ride=active('rocket',nil,{0,.5});local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'rocket',10,b,out)
		assert(out[4].x<out[1].x);assert(out[4].vx<0);eq(out[4].ground,true);eq(out[4].wind,false);eq(out[6].tex,'spark');eq(out[7].wind,true)
		M.place(s,9,8,8.8,8,math.pi/2,8.8,8);R.begin(b,.5);local before=#out;step(s,ride,'rocket',10.5,b,out);assert(out[before+1].y>8);near(out[before+1].x,8.4)
	end)
	test('single-missile artillery has one generic TBM flash and smoke event without howitzer brakes or salvo haze',function()
		local s,ride=active('artillery','tbm',{0,.5,1});local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'artillery',10,b,out)
		eq(#out,5);eq(out[1].size,cfg.tbm.flash);near(out[1].h,cfg.unitMuzzleHeight);eq(s.events,nil);eq(s.linger,nil)
		R.begin(b,1);step(s,ride,'artillery',11,b,out);eq(#out,5)
	end)
	test('public artillery weapon metadata uses resolved simulation rules and safely clears for old packets',function()
		local sim={time=10,armyOf=function()return 'republic'end,unitKey=function(e)eq(e.kind,'artillery');return 'armyUnits.republic.artillery'end,rules={has=function(_,key)eq(key,'armyUnits.republic.artillery.missile.splash');return true end,text=function()error('raw salvo weapon is not the missile discriminator')end}}
		local p=V.snapshot({kind='artillery',alive=true,side=2},nil,sim);eq(p[5],'republic');eq(p[6],'tbm');local ride=V.new();V.receive(ride,p,{10,1},0);eq(ride.weapon,'tbm')
		V.receive(ride,{0,false,0,{},'republic'},{10,1},0);eq(ride.weapon,nil);V.receive(ride,nil,nil,0);eq(ride.weapon,nil)
	end)
	test('heavy schedules baseline first sight pause on the shared clock and discard expired launches',function()
		local s=M.new();local ride=V.new();V.receive(ride,{8,10,0,{0,.43}},{10,1},0);M.receive(s,ride);eq(s.pending,nil)
		s,ride=active('rocket',nil,{0,.43,1.1});local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'rocket',10,b,out);local n=#out
		V.receive(ride,{1,10,0,{0,.43,1.1}},{10,0},.1);R.begin(b,100);step(s,ride,'rocket',V.time(ride,100),b,out);eq(#out,n)
		R.begin(b,1);step(s,ride,'rocket',10.8,b,out);eq(#out,n,'overdue second launch must drop');step(s,ride,'rocket',11.1,b,out);assert(#out>n);eq(s.events,nil)
	end)
	test('howitzer lingering smoke pauses drops stall catch-up and remains bounded by shared pulse admission',function()
		local s,ride=active('artillery');local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'artillery',10,b,out);local n=#out
		R.begin(b,.05);step(s,ride,'artillery',10.05,b,out);assert(#out>n);n=#out;step(s,ride,'artillery',10.05,b,out);eq(#out,n)
		R.begin(b,.7);step(s,ride,'artillery',10.7,b,out);eq(#out,n);eq(s.linger.acc,0)
		b.pulses=0;step(s,ride,'artillery',10.75,b,out);eq(#out,n);R.begin(b,.8);step(s,ride,'artillery',10.8,b,out);assert(#out-n<=4)
		step(s,ride,'artillery',11.01,b,out);eq(s.linger,nil)
	end)
	test('heavy root and muzzle fog drop events without a later hidden launch backlog',function()
		local s,ride=active('rocket',nil,{0,.5});local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'rocket',10,b,out,function()return true end);eq(#out,0);eq(s.events,nil)
		s,ride=active('artillery');R.begin(b,0);step(s,ride,'artillery',10,b,out,function(x)return x>5.5 end);eq(#out,0);eq(s.linger,nil)
	end)
	test('missing old heavy settings or missing salvo offsets never fabricate a burst or break existing art',function()
		local s,ride=active('artillery');local b=R.newBudget();R.begin(b,0);local n=0;M.step(s,ride,{},'artillery',10,visible,function()n+=1;return true end,b,rng);eq(n,0);eq(s.pending,nil)
		s,ride=active('rocket');local out={};step(s,ride,'rocket',10,b,out);eq(#out,0);eq(s.events,nil)
	end)
	test('shared image or particle refusal drops heavy work promptly with no orphaned howitzer gas',function()
		local s,ride=active('artillery');local b=R.newBudget();R.begin(b,0);local attempts=0;M.step(s,ride,cfg,'artillery',10,visible,function()attempts+=1;return false end,b,rng)
		eq(attempts,1);eq(s.linger,nil);eq(s.events,nil)
	end)
	test('dense heavy fire uses the actual shared 128-request emitter and bounded schedule preparation',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function emitRifleParticle(',1,true));local z=assert(src:find('local UnitRenderer =',a,true));local b=R.newBudget();R.begin(b,0);local attempts=0
		local env=setmetatable({rifleBudget=b,DeathRenderer={request=function(_,_,tag)eq(tag,b);attempts+=1;return true end}},{__index=getfenv()})
		local emit=luau.load(src:sub(a,z-1)..'\nreturn emitRifleParticle',{environment=env})();local states={}
		for i=1,3000 do local s,ride=active('rocket',nil,{0,.43,1.1});M.step(s,ride,cfg,'rocket',10,visible,emit,b,rng);states[i]=s end
		eq(attempts,128);eq(b.prepares,0);eq(b.pulses,0);eq(b.particles,0);for i=33,#states do eq(states[i].events,nil)end
	end)
	test('actual artillery and launcher placement use hull orientation recoil-adjusted body and static water probe',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function place(v:',1,true));local z=assert(src:find('local mortarSec',a,true))
		for _,kind in {'artillery','rocket'}do
			local supplied;local water=function()return false end;local look={size=1.4,cells=3};local v={kind=kind,vehicle={},muzzle={},look=look,base=look,body={Size=rb.Vector3.new(4,.1,4)},model={FindFirstChild=function()return{}end},ring={},from=rb.Vector3.zero,to=rb.Vector3.zero,t=1,turretAt=math.pi/2,turretWant=math.pi/2,sprites={},fx={},facing=-1}
			local env=setmetatable({VehicleRecoil={pose=function()return -.3,0,0 end,time=function()return 10 end},VehicleMuzzle={place=function(_,x,y,bx,by,h,vx,vy)supplied={x,y,bx,by,h,vx,vy}end,step=function(_,_,_,_,_,_,_,_,_,wet)eq(wet,water)end},vehicleMuzzleConfig=cfg,FogOverlay={hidden=visible,water=water},emitRifleParticle=function()return true end,rifleBudget={},Vector3=rb.Vector3,CFrame=rb.CFrame,Vector2=rb.Vector2,S=4,SPRITE_Y=0,GUI_YAW=0,TURRET_FOLLOW=20,os={clock=function()return 0 end},turretAt=function(_,pos)return pos end,updateStage=function()end,sootOf=function()return 0 end},{__index=getfenv()})
			luau.load(src:sub(a,z-1)..'\nreturn place',{environment=env})()(v,rb.Vector3.new(20,1,20),0,0);near(supplied[5],0);near(supplied[6],4.7);near(v.body.CFrame.Position.X,20)
		end
	end)
	test('static water lookup preserves fog decisions and skips unknown or out-of-bounds terrain',function()
		local src=fs.readFile('src/client/Rendering/FogOverlay.luau');local a=assert(src:find('function FogOverlay.water(',1,true));local env=setmetatable({FogOverlay={},width=5,height=1,terrain=buffer.fromstring(string.char(0,1,10,3,7)),Terrain=require('../src/shared/Definitions/Terrain')},{__index=getfenv()})
		local z=assert(src:find('return FogOverlay',a,true));local water=luau.load(src:sub(a,z-1)..'\nreturn FogOverlay.water',{environment=env})()
		eq(water(.5,.5),true);eq(water(1.5,.5),true);eq(water(2.5,.5),true);eq(water(3.5,.5),false);eq(water(4.5,.5),false);eq(water(-1,0),false);eq(water(5,0),false)
	end)
	test('incoming rocket offsets stay capped and inactive weapon views do no preparation or particle work',function()
		local offsets={};for i=1,5000 do offsets[i]=(i-1)*.5 end
		local s,ride=active('rocket',nil,offsets);eq(#ride.offsets,64);local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'rocket',10,b,out);eq(#s.events,63)
		local idle=M.new();M.place(idle,5,5,5,5,0);local clock=V.new();V.receive(clock,{0,false,0,{}},{10,1},0);local calls=0
		for _=1,1000 do M.step(idle,clock,cfg,'artillery',10,visible,function()calls+=1;return true end,b,function()error('idle RNG draw')end)end
		eq(calls,0);eq(idle.root,nil);eq(idle.events,nil);eq(idle.linger,nil)
	end)
	test('actual visible artillery rows carry resolved TBM metadata while hidden entities are not sampled',function()
		local src=fs.readFile('src/server/Match/MatchService.luau');local a=assert(src:find('local function viewFor(',1,true));local z=assert(src:find('-- vehicles destroyed',a,true));local units={}
		for i,kind in {'artillery','rocket','artillery'}do units[i]={id=i,kind=kind,cat='unit',alive=true,side=2,x=5,y=5,heading=0,hp=100,maxHp=100}end
		local sampled=0;local sim={list=units,time=10,armyOf=function()return 'republic'end,unitKey=function(e)eq(e.id,1);sampled+=1;return 'armyUnits.republic.artillery'end,rules={number=function(_,key)eq(key,'artillery.rocketSpread');return 3.3 end,has=function(_,key)eq(key,'armyUnits.republic.artillery.missile.splash');return true end}}
		local viewer={update=function()end,unitVisible=function(e)return e.id~=3 end,lastSeen={},runs=function()return{}end}
		local env=setmetatable({sim=sim,viewers={[1]=viewer},factoryViews={},weaponViews={},artilleryViews={},CrewMotion={snapshot=function()return nil end},VehicleRecoil=V,rules={data={}},unitLook=function()return 1,20,5,9 end,unitStatus=function()return 0 end,unitStage=function()return 0 end},{__index=getfenv()})
		local rows=luau.load(src:sub(a,z-1)..'\nreturn viewFor',{environment=env})()(1);eq(#rows,2);eq(rows[1][20][6],'tbm');eq(rows[2][20][6],false);eq(rows[2][20][7],3.3);eq(sampled,1)
	end)
end
