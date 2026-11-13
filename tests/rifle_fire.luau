--!strict
return function(test:any,eq:any)
	local R=require('../src/shared/Presentation/RifleFire')
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	-- Deliberately synthetic settings: actual original settings remain in ignored GameData.
	local cfg={men={muzzleH={stand=.2,kneel=.1,prone=.05},aimSlack=.7,shooters=3,stagger=.09,jitter=.05,flash=.6,core=.4,follow=.7,wisp={size=.2,life=.4,rise=.2,drift=.5,color=1,pale=2},brass={size=.1,speed={1,2},rise={2,3},life={.2,.4},color=3}},flash={size=1.2,sec=.07},haze={life={7,11},size={.5,.8},grow=2,alpha=.5,rise=.1,color=1,pale=2,max=120},rhythm={burst={2,5},jitter=.35},rifle={gap=.07,spread=.5},muzzle={rifle={stand={.5,.2},kneel={.8,.1},prone={1,.1}}},colors={fire=5,hot=6},grow=1.5,proneBack=.4}
	local function near(a,b)assert(math.abs(a-b)<1e-5,`{a} ~= {b}`)end
	local function soldier(kind:string?,pose:string?,x:number?):any return {kind=kind or 'rifle',pose=pose or 'kneel',x=x or 5,y=5,heading=0,up=true} end
	local function observe(s,age,time,wall,status,flags)R.receive(s,age,flags or 1,status or 0,20,5,{time,1},wall)end
	local function active(id:number?):any local s=R.new(id or 1);observe(s,9,10,0);observe(s,0,10.1,.1);return s end
	local function random()return .5 end
	local function visible()return false end
	test('rifle observation baselines first sight and ignores capped ages, unchanged shots and old rows',function()
		local s=R.new(1);observe(s,0,10,0);eq(s.pending,nil)
		observe(s,.1,10.1,.1);eq(s.pending,nil);observe(s,.1+1e-8,10.1,.2);eq(s.pending,nil)
		observe(s,0,10.2,.3);assert(s.pending);R.cancel(s);observe(s,9,20,1);observe(s,9,21,2);eq(s.pending,nil)
		R.receive(s,nil,1,0,20,5,nil,3);eq(s.war,nil);eq(s.observed,false)
	end)
	test('garrison, fog view recreation and late observations cannot replay unseen rifle firing',function()
		local s=active();observe(s,0,10.2,.2,4);eq(s.pending,nil);eq(s.observed,false)
		observe(s,0,10.3,.3);eq(s.pending,nil);observe(s,0,10.4,.4);assert(s.pending)
		R.cancel(s);observe(s,.4,11,1);eq(s.pending,nil);local fresh=R.new(1);observe(fresh,0,11,1);eq(fresh.pending,nil)
		observe(s,0,11.1,1.1,0,0);eq(s.pending,nil)
	end)
	test('rifle clock freezes with pause, caps stalled prediction and clears work on rollback',function()
		local s=active();R.receive(s,0,1,0,20,5,{10.1,0},.2);near(R.time(s,100),10.1)
		R.receive(s,0,1,0,20,5,{10.1,1},100);near(R.time(s,101),10.3)
		R.receive(s,0,1,0,20,5,{10.1,1},102);near(R.time(s,103),10.3)
		observe(s,0,1,104);eq(s.pending,nil);eq(s.pulses,nil)
	end)
	test('muzzle pose anchors include rotated side offsets, aim slack and the existing prone body shift',function()
		local m=soldier('leader','prone');local p=R.muzzle(cfg,m,20,5,.5);near(p.x,5+.5-.2);near(p.y,5+.05);near(p.h,.05)
		m.heading=math.pi/2;m.pose='stand';p=R.muzzle(cfg,m,5,20,.5);near(p.x,5-.1);near(p.y,5+.25)
		m.heading=0;p=R.muzzle(cfg,m,5,20,.5);near(p.ux,0);near(p.uy,1)
		p=R.muzzle(cfg,m,20,6,.5);near(p.ux,1);near(p.uy,0)
	end)
	test('rifle bursts rotate living shooters, stagger rounds and capture independent muzzle positions',function()
		local men={soldier('leader','kneel',4),soldier('rifle','kneel',5),soldier('para','kneel',6),soldier('gunner'),soldier('loader')};men[2].up=false
		local pulses,haze=R.plan(cfg,men,1,1,20,5,.5,10,random);eq(#pulses,4);near(pulses[1].tip.x,6+.4)
		for i=2,#pulses do assert(pulses[i].at>=pulses[i-1].at)end
		local x=pulses[1].tip.x;men[3].x=100;eq(pulses[1].tip.x,x);assert(haze)
		local none=R.plan(cfg,{},1,0,20,5,.5,10,random);eq(#none,0)
	end)
	test('muzzle flash emits the shared star, hot core, wisp and solid brass with bounded refusal work',function()
		local emitted={};local tip={x=5,y=6,h=.1,ux=1,uy=0}
		assert(R.flash(cfg,tip,1,.5,function(p)table.insert(emitted,p);return true end,random));eq(#emitted,4)
		eq(emitted[1].tex,'star');eq(emitted[2].tex,'disc');eq(emitted[3].tex,'puffB');eq(emitted[4].tex,'px')
		near(emitted[1].x,5+cfg.men.flash*cfg.flash.size*.3);near(emitted[4].x,4.75);assert(emitted[4].vy>0);assert(emitted[4].falls)
		local calls=0;eq(R.flash(cfg,tip,1,.5,function()calls+=1;return false end,random),false);eq(calls,1)
	end)
	test('current fog is checked again at each scheduled muzzle and hidden work is never emitted',function()
		local s=active();local b=R.newBudget();R.begin(b,.1);local emitted=0;local hidden=true
		R.step(s,cfg,{soldier()},.5,.1,function()return hidden end,function()emitted+=1;return true end,b,random);eq(emitted,0)
		hidden=false;R.begin(b,.3);R.step(s,cfg,{soldier()},.5,.3,visible,function()emitted+=1;return true end,b,random)
		assert(emitted>0);local before=emitted;R.begin(b,2);R.receive(s,2,1,0,20,5,{12.1,1},2);R.step(s,cfg,{soldier()},.5,2,visible,function()emitted+=1;return true end,b,random);eq(emitted,before);eq(s.pulses,nil)
	end)
	test('dense simultaneous rifle fire bounds preparation and pulses without retaining rejected backlogs',function()
		local b=R.newBudget();R.begin(b,.1);local accepted=0;local states={}
		for id=1,3000 do local s=active(id);states[id]=s;R.step(s,cfg,{soldier()},.5,.1,visible,function()accepted+=1;return true end,b,random)end
		eq(b.prepares,0);eq(b.pulses,0);assert(accepted<=32*5);for id=33,#states do eq(states[id].pending,nil);eq(states[id].pulses,nil)end
	end)
	test('rifle haze admission has a global live cap and refuses no-memory work without retry queues',function()
		local b=R.newBudget();for i=1,cfg.haze.max do b.haze[i]=100 end;R.begin(b,.1)
		local emitted={};R.step(active(),cfg,{soldier()},.5,.1,visible,function(p)table.insert(emitted,p);return true end,b,random);eq(#emitted,4);eq(#b.haze,120)
		R.begin(b,101);eq(#b.haze,0);local s=active();R.step(s,cfg,{soldier()},.5,.1,visible,function()return false end,b,random);eq(#b.haze,0)
	end)
	test('actual client snapshot derives rifle observations from existing fields and shared war clock',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('v.statusCode, v.sinceShot =',1,true));local z=assert(src:find('v.turretWant =',a,true));local v={id=3,kind='infantry',flags=1,aimX=20,aimY=5};local u={[9]=0,[15]=9};local war={10,1}
		local env=setmetatable({v=v,id=3,kind='infantry',u=u,war=war,RifleFire=R,VehicleRecoil=require('../src/shared/Presentation/VehicleRecoil'),os={clock=function()return .1 end}},{__index=getfenv()})
		local apply=luau.load(src:sub(a,z-1),{environment=env});apply();eq(v.rifle.pending,nil);u[15]=0;war[1]=10.1;apply();assert(v.rifle.pending);eq(v.rifle.pending.tx,20);eq(v.rifle.id,3)
	end)
	test('actual soldier placement emits only after current poses and cancels garrisoned or fogged bursts',function()
		local src=fs.readFile('src/client/Rendering/UnitRenderer.luau');local a=assert(src:find('local function placeMen(',1,true));local z=assert(src:find('-- seconds a mortar',a,true));local events={};local hidden=false;local men={soldier()}
		local env=setmetatable({SquadMen={MAN_CELLS=.5,step=function()table.insert(events,'pose')end},CrewMotion={sample=function()return nil,nil,nil,9 end},reactions={time=function()return 10 end},S=4,SNAPSHOT_SEC=.1,mortarSec={},SPRITE_Y=0,World={GROUND_Y=0},os={clock=function()return .1 end},setFigure=function()table.insert(events,'draw')end,RifleFire={step=function(_,_,actual)table.insert(events,'fire');eq(actual,men)end,cancel=function()table.insert(events,'cancel')end},rifleConfig=cfg,rifleBudget={},FogOverlay={hidden=function()return hidden end},emitRifleParticle=function()return true end},{__index=getfenv()})
		local place=luau.load(src:sub(a,z-1)..'\nreturn placeMen',{environment=env})();local v={id=1,kind='infantry',from=rb.Vector3.zero,to=rb.Vector3.zero,statusCode=0,hpFrac=1,flags=1,aimX=20,aimY=5,inTrench=false,sinceShot=0,t=1,squad={men=men},men={{gui={}}},rifle={}}
		place(v,rb.Vector3.new(20,.4,20),0);eq(table.concat(events,','),'pose,draw,fire');events={};hidden=true;place(v,rb.Vector3.new(20,.4,20),0);eq(events[3],'cancel');events={};hidden=false;v.statusCode=4;place(v,rb.Vector3.new(20,.4,20),0);eq(events[3],'cancel')
	end)
	test('actual shared particle renderer restores ordinary atlas crops after a brass pixel reuses a slot',function()
		local src=fs.readFile('src/client/Rendering/DeathRenderer.luau');local a=assert(src:find('function DeathRenderer.step(',1,true));local z=assert(src:find('\nreturn DeathRenderer',a,true));local label={};local owner={gui={},image=label,part={}};local p={tex='px',x=5,y=5,x0=5,y0=5,h=0,drawSize=.1,len=1,alpha=1,tint=255,rot=0}
		local env=setmetatable({DeathRenderer={},engine={particles={p},step=function()end},World={STUDS_PER_CELL=4,TOP_GUI_YAW=0,toWorld=function(x,y)return rb.Vector3.new(x,0,y)end},Fog={hidden=visible},workspace={},slots={owner},slot=function()return owner end,FRAMES={disc={1,0}},frame=24,Vector2=rb.Vector2,Vector3=rb.Vector3,CFrame=rb.CFrame,Color3=rb.Color3},{__index=getfenv()})
		luau.load(src:sub(a,z-1),{environment=env})();env.DeathRenderer.step(.01);eq(label.ImageRectOffset,rb.Vector2.new(1,1));eq(label.ImageRectSize,rb.Vector2.new(4,4));p.tex='disc';env.DeathRenderer.step(.01);eq(label.ImageRectOffset,rb.Vector2.new(24,0));eq(label.ImageRectSize,rb.Vector2.new(24,24))
	end)
end
