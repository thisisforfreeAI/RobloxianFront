--!strict
return function(test:any,eq:any)
	local M=require('../src/shared/Presentation/VehicleMuzzle');local V=require('../src/shared/Presentation/VehicleRecoil');local R=require('../src/shared/Presentation/RifleFire')
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	-- Synthetic settings keep this suite independent of private source data.
	local cfg={gun={tank=.8,ifv=.5},gunHeight=.2,factions={coalition={flash=1,ball=1},republic={flash=1.2,ball=1.4}},colors={fire=1,hot=2,ember=3,smoke=4,smokeLight=5,dustLight=6},motion={rise=2,grow=1.5},sparks={muzzle=2,size={.1,.2},speed={2,4},life={.1,.3}},tank={flash=2,flashSec=.1,ball=1,ballSec=.2,dome=1.5,domeSec=.25,domeAlpha=.5,smoke=2,smokeLife=1,smokeSize=.5,smokeKick=2,evacuator={delay=.5,puffs=3,size=.3,life=1,kick=.5}},ifv={rounds=4,gap=.2,flash=1.5,follow=.8,flashLen=1.5,flashSec=.1,smoke=.4,cases={n=1,at=.4,out=.1,speed={1,2},rise={2,3},size=.1,len=2,life=1,color=1,shade=2},breath={delay=.3,puffs=2,size=.2,life=1,kick=.5}}}
	local function near(a,b)assert(math.abs(a-b)<1e-5,`{a} ~= {b}`)end
	local function rng()return .5 end
	local function visible()return false end
	local function active(kind:string?):(any,any)
		local s=M.new();local ride=V.new();V.receive(ride,{0,false,0,{},'coalition'},{10,1},0);M.receive(s,ride,20,5)
		V.receive(ride,{1,10,0,{},'coalition'},{10,1},0);M.receive(s,ride,20,5);M.place(s,5,5,4.8,5,0);return s,ride
	end
	local function step(s,ride,kind,time,b,output,hidden)
		M.step(s,ride,cfg,kind,time,hidden or visible,function(p)table.insert(output,p);return true end,b,rng)
	end
	test('vehicle muzzle observations reuse accepted recoil sequences and baseline old or reset samples',function()
		local s=M.new();local ride=V.new();V.receive(ride,{7,10,0,{}},{10,1},0);M.receive(s,ride);eq(s.pending,nil)
		V.receive(ride,{8,10,0,{}},{10,1},0);M.receive(s,ride);assert(s.pending);local pending=s.pending;M.receive(s,ride);eq(s.pending,pending)
		V.receive(ride,{9,9,0,{}},{10,1},0);M.receive(s,ride);eq(s.pending,nil)
		V.receive(ride,nil,nil,0);M.receive(s,ride);eq(s.sequence,nil);eq(s.events,nil)
	end)
	test('public faction metadata preserves the previous recoil fields and safely defaults legacy packets',function()
		local e={kind='tank',side=2,alive=true,x=5,y=5,id=1};local sim={time=10,armyOf=function(side)eq(side,2);return 'republic' end}
		local packet,known=V.snapshot(e,nil,sim);eq(packet[1],0);eq(packet[2],false);eq(#packet[4],0);eq(packet[5],'republic');eq(e.firedAt,nil)
		local ride=V.new();V.receive(ride,packet,{10,1},0);eq(ride.army,'republic');V.receive(ride,{0,false,0,{}},{10,1},0);eq(ride.army,'coalition')
		V.receive(ride,{0,false,0,{},'unrecognized'},{10,1},0);eq(ride.army,'coalition')
	end)
	test('muzzle geometry follows the rendered turret and retains source close-target reach clamping',function()
		local pose={barrelX=5,barrelY=5,heading=math.pi/2};local tip=M.tip(cfg,'tank',pose,1);near(tip.x,5);near(tip.y,5.5);near(tip.h,cfg.gunHeight)
		tip=M.tip(cfg,'tank',pose,100);near(tip.y,5.8);pose.barrelX=9;pose.heading=math.pi;tip=M.tip(cfg,'tank',pose,100);near(tip.x,8.2)
	end)
	test('tank firing emits distinct source flash, fireball, dome, sparks and delayed barrel gas',function()
		local s,ride=active();local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'tank',10,b,out);eq(#out,8);eq(out[1].tex,'star');eq(out[3].tex,'blobB');eq(out[5].tex,'spark');eq(#s.events,1)
		local before=#out;step(s,ride,'tank',10,b,out);eq(#out,before);R.begin(b,.5);M.place(s,8,5,7.8,5,0);step(s,ride,'tank',10.5,b,out);eq(#out,before+3);assert(out[before+1].x>8);eq(s.events,nil);assert(out[1].x<7)
	end)
	test('IFV firing produces four recoil-timed pulses, side-ejected cases and one post-burst breath',function()
		local s,ride=active('ifv');local b=R.newBudget();local out={}
		for _,time in {10,10.2,10.4,10.6}do R.begin(b,time-10);step(s,ride,'ifv',time,b,out)end
		eq(#out,20);for i=1,4 do eq(out[(i-1)*5+1].tex,'star');eq(out[i*5].tex,'shard');assert(out[i*5].vy>0)end
		near(out[6].size,out[1].size*cfg.ifv.follow);R.begin(b,.9);step(s,ride,'ifv',10.9,b,out);eq(#out,22);eq(s.events,nil)
	end)
	test('vehicle muzzle schedules pause on the shared clock and discard overdue pulses rather than catching up',function()
		local s,ride=active('ifv');local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'ifv',10,b,out);local first=#out
		V.receive(ride,{1,10,0,{}},{10,0},.1);R.begin(b,100);step(s,ride,'ifv',V.time(ride,100),b,out);eq(#out,first)
		V.receive(ride,{1,10,0,{}},{12,1},100);R.begin(b,100);step(s,ride,'ifv',V.time(ride,100),b,out);eq(#out,first);eq(s.events,nil)
		local late,clock=active();R.begin(b,0);step(late,clock,'tank',10.3,b,out);eq(late.events,nil)
	end)
	test('current root and muzzle fog suppress vehicle emission and hidden owners leave no delayed gas',function()
		local s,ride=active();local b=R.newBudget();R.begin(b,0);local out={};step(s,ride,'tank',10,b,out,function()return true end);eq(#out,0);eq(s.events,nil)
		s,ride=active();R.begin(b,0);step(s,ride,'tank',10,b,out,function(x)return x>5.1 end);eq(#out,0);R.begin(b,.5);step(s,ride,'tank',10.5,b,out);eq(#out,0);eq(s.events,nil)
	end)
	test('image or emission refusal stops optional particle work and does not create an orphaned gas puff',function()
		local s,ride=active();local b=R.newBudget();R.begin(b,0);local attempts=0
		M.step(s,ride,cfg,'tank',10,visible,function()attempts+=1;return false end,b,rng);eq(attempts,1)
		R.begin(b,.5);M.step(s,ride,cfg,'tank',10.5,visible,function()attempts+=1;return false end,b,rng);eq(attempts,1);eq(s.events,nil)
	end)
	test('dense mixed weapon work shares preparation, pulse and native request attempt limits',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function emitRifleParticle(',1,true));local z=assert(src:find('local UnitRenderer =',a,true));local b=R.newBudget();R.begin(b,0);local requests=0
		local env=setmetatable({rifleBudget=b,DeathRenderer={request=function(kind,p,tag)eq(kind,'spawn');eq(tag,b);requests+=1;return true end}},{__index=getfenv()});local emit=luau.load(src:sub(a,z-1)..'\nreturn emitRifleParticle',{environment=env})()
		local states={};for i=1,3000 do local s,ride=active();states[i]=s;M.step(s,ride,cfg,'ifv',10,visible,emit,b,rng)end
		eq(b.prepares,0);eq(b.pulses,0);eq(requests,128);eq(b.particles,0);for i=33,#states do eq(states[i].events,nil)end
		for _=1,100 do eq(emit({}),false)end;eq(requests,128);R.begin(b,1);eq(b.particles,128)
	end)
	test('actual vehicle placement supplies recoil-adjusted turret geometry without moving selection anchors',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function place(v:',1,true));local z=assert(src:find('local mortarSec',a,true));local look={size=1.3,cells=2.6,turret={}};local supplied
		local v={kind='tank',vehicle={},muzzle={},look=look,base=look,body={Size=rb.Vector3.new(4,.1,4)},model={FindFirstChild=function()return{}end},ring={},from=rb.Vector3.zero,to=rb.Vector3.zero,t=1,turretAt=0,turretWant=0,sprites={},fx={},facing=-1}
		local env=setmetatable({VehicleRecoil={pose=function()return -.16,0,.117 end,time=function()return 10 end},VehicleMuzzle={place=function(_,x,y,bx,by,heading)supplied={x,y,bx,by,heading}end,step=function(_,_,_,_,now)eq(now,10)end},vehicleMuzzleConfig=cfg,FogOverlay={hidden=visible},emitRifleParticle=function()return true end,rifleBudget={},Vector3=rb.Vector3,CFrame=rb.CFrame,Vector2=rb.Vector2,S=4,SPRITE_Y=0,GUI_YAW=0,TURRET_FOLLOW=20,os={clock=function()return 0 end},turretAt=function(_,pos)return pos end,updateStage=function()end,sootOf=function()return 0 end},{__index=getfenv()})
		local place=luau.load(src:sub(a,z-1)..'\nreturn place',{environment=env})();place(v,rb.Vector3.new(20,1,20),0,0);near(supplied[1],5);near(supplied[3],5-.16-.117);near(supplied[4],5);near(v.body.CFrame.Position.X,20)
	end)
	test('actual snapshot assignment shares recoil acceptance and resets legacy vehicle muzzle state',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('v.statusCode, v.sinceShot =',1,true));local z=assert(src:find('v.turretWant =',a,true));local v={kind='tank',flags=1,aimX=20,aimY=5};local u={[9]=0,[15]=9,[20]={0,false,0,{}}};local war={10,1}
		local env=setmetatable({v=v,u=u,kind='tank',war=war,VehicleRecoil=V,VehicleMuzzle=M,RifleFire=R,os={clock=function()return 0 end}},{__index=getfenv()});local apply=luau.load(src:sub(a,z-1),{environment=env});apply();eq(v.muzzle.pending,nil)
		u[20]={1,10,0,{},'republic'};apply();assert(v.muzzle.pending);eq(v.muzzle.pending.army,'republic');u[20]=nil;apply();eq(v.muzzle.events,nil);eq(v.muzzle.pending,nil)
	end)
end
