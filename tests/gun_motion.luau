--!strict
return function(test:any,eq:any)
	local Motion=require("../src/shared/Presentation/GunMotion")
	local cfg={kind="atgun",initialStep=.73,holdSec=2,turn=2,sweep=.3,sweepSec=6,kick=.2,kickSec=.5,x=.1,y=.2,
		slits={{0,.1},{math.pi/2,.2},{math.pi,.1},{-math.pi/2,.2}}}
	local function near(a,b) assert(math.abs(a-b)<1e-8,`{a} != {b}`) end
	test("weapon clock tails are dense for every supported kind and retain visibility filtering",function()
		for _,kind in {"atgun","bunker","sam"} do
			local packet=Motion.snapshot({kind=kind},true,true,nil,42,if kind=="sam" then 10 else nil,false)
			eq(#packet,9);for i=1,9 do assert(packet[i]~=nil) end;eq(packet[8],42);eq(packet[9],0)
			eq(Motion.snapshot({kind=kind},false,true,nil,42,10,true),nil)
		end
	end)
	test("recoil and aim hold freeze with the war clock and resume without a replayed pulse",function()
		local c=table.clone(cfg);c.turn=100;local s=Motion.new(c,0)
		Motion.advance(s,c,{1,1,0,0,3600,0,0,10,1},100,0,true,0)
		Motion.advance(s,c,{1,1,1,1,0,1,0,10.1,1},100.1,.1,true,0)
		local paused={1,1,0,1,.05,1,0,10.15,0}
		Motion.advance(s,c,paused,100.2,.1,true,0);local kick=Motion.pose(s,c,100.2,16).kick
		Motion.advance(s,c,paused,160,.1,true,0);near(Motion.pose(s,c,160,16).kick,kick);near(s.heading,1)
		Motion.advance(s,c,{1,1,0,1,.1,1,0,10.2,1},160.1,.1,true,0)
		assert(Motion.pose(s,c,160.2,16).kick<kick);eq(s.sequence,1)
	end)
	test("SAM reload age pauses and clock extrapolation is bounded during a network stall",function()
		local c=table.clone(cfg);c.kind="sam";c.sam={stay=.5,half=1.1,rise=2.4,up=1.3};local s=Motion.new(c,1)
		Motion.advance(s,c,{1,0,0,0,3600,0,10,100,1},1,0,true,1)
		Motion.advance(s,c,{1,0,0,1,2,0,10,102,0},2,.1,true,1)
		eq(Motion.samStage(c,Motion.time(s,200)-s.shotAt,10),0)
		Motion.advance(s,c,{1,0,0,1,8,0,10,108,1},201,.1,true,1)
		near(Motion.time(s,300),108.2);eq(Motion.samStage(c,Motion.time(s,300)-s.shotAt,10),1)
		Motion.advance(s,c,nil,301,.1,false,1);eq(s.warAt,nil);eq(s.sequence,nil)
	end)
	test("war pauses leave the source real-time idle sweep independent from shot age",function()
		local c=table.clone(cfg);c.turn=100;local s=Motion.new(c,1);local sample={1,0,0,0,3600,0,0,20,0}
		Motion.advance(s,c,sample,1,.1,true,1);local first=s.heading
		Motion.advance(s,c,sample,2,.1,true,1);assert(math.abs(s.heading-first)>.01);eq(Motion.time(s,100),20)
	end)
	test("SAM reload stages use source transition boundaries and the authoritative reload duration",function()
		local c={sam={stay=.5,half=1.1,rise=2.4,up=1.3}}
		for _,case in {{0,2},{.499,2},{.5,1},{1.099,1},{1.1,0},{7.6,0},{7.601,1},{8.699,1},{8.7,2},{10,2}} do eq(Motion.samStage(c,case[1],10),case[2]) end
		eq(Motion.samStage(c,12,20),0);eq(Motion.samStage(c,19,20),2)
		local e={kind="sam",weaponShotAt=8,weaponShotAim=1}
		local first,cache=Motion.snapshot(e,true,true,nil,8,20);eq(#first,7);eq(first[7],20);eq(first[4],0)
		e.weaponShotAt=30;local shot=Motion.snapshot(e,true,true,cache,30.1,20);eq(shot[4],1);near(shot[5],.1);eq(shot[7],20)
	end)
	test("SAM lowers toward its reload bearing and single-facing art never rotates",function()
		local c=table.clone(cfg);c.kind="sam";c.sam={stay=.5,half=1.1,rise=2.4,up=1.3};c.turn=100;c.kick=0
		local s=Motion.new(c,0);Motion.advance(s,c,{1,0,0,0,3600,0,10},0,0,true,0)
		Motion.advance(s,c,{1,0,0,1,0,1.5,10},1,.1,true,0);near(s.heading,1.5)
		Motion.advance(s,c,{1,0,0,1,1,1.5,10},2,.1,true,0);near(s.heading,0)
		s.heading=1.5;near(Motion.pose(s,c,2,1).residual,0);assert(math.abs(Motion.pose(s,c,2,16).residual)>0)
	end)
	test("weapon transport includes only visible supported structures and never replays a hidden shot",function()
		local e={kind="atgun",weaponAim=1,weaponShotAt=9,weaponShotAim=.9}
		local row,known=Motion.snapshot(e,true,true,nil,9.1);eq(row[4],0);eq(row[5],3600);eq(row[6],0)
		e.weaponShotAt=10;row,known=Motion.snapshot(e,true,true,known,10.05);eq(row[4],1);near(row[5],.05);eq(row[6],.9)
		eq(Motion.snapshot(e,false,true,known,11),nil)
		e.weaponShotAt=20;row=Motion.snapshot(e,true,true,nil,20.1);eq(row[4],0);eq(row[5],3600)
		e.kind="factory";eq(Motion.snapshot(e,true,true,known,20.1),nil)
	end)
	test("multiple viewers on one side receive the same observed pulse age and aim",function()
		local e={kind="bunker",weaponAim=.5};local _,known=Motion.snapshot(e,true,true,nil,1)
		e.weaponShotAt=2;e.weaponShotAim=.4
		local a;a,known=Motion.snapshot(e,true,true,known,2.05)
		local b;b,known=Motion.snapshot(e,true,true,known,2.05)
		for i=1,6 do eq(a[i],b[i]) end
	end)
	test("guns turn along the shortest arc with the source per-frame turn bound",function()
		local s=Motion.new(cfg,1);s.heading=math.pi-.05
		Motion.advance(s,cfg,{1,1,-math.pi+.05,0,9,0},1,.1,true,1);near(Motion.wrap(s.heading-(-math.pi+.05)),0)
		s.heading=0;Motion.advance(s,cfg,{1,1,math.pi,0,9,0},2,20,true,1);near(math.abs(s.heading),.2)
	end)
	test("observed recoil decays quadratically and recent aim holds until its source timeout",function()
		local c=table.clone(cfg);c.turn=100;local s=Motion.new(c,0)
		Motion.advance(s,c,{1,1,0,0,9,0},0,.1,true,0)
		Motion.advance(s,c,{1,1,math.pi/2,1,0,math.pi/2},1,.1,true,0);near(s.heading,math.pi/2)
		local p=Motion.pose(s,c,1.25,16);near(p.kick,.05);near(p.x,.1);near(p.y,.15)
		Motion.advance(s,c,{1,1,0,1,9,0},2,.1,true,0);near(s.heading,math.pi/2)
		Motion.advance(s,c,{1,1,0,1,9,0},3.1,.1,true,0);near(s.heading,0);near(Motion.pose(s,c,3.1,16).kick,0)
	end)
	test("bunker goals clamp to the nearest slit and facing residuals preserve smooth wrap",function()
		near(Motion.slit(.05,cfg.slits),.05);near(Motion.slit(.7,cfg.slits),.1)
		near(Motion.slit(1.1,cfg.slits),math.pi/2-.2)
		local s={heading=math.pi*2-.01,shotAt=-math.huge};local p=Motion.pose(s,cfg,1,16)
		eq(p.index,1);near(p.residual,-.01)
	end)
	test("first sighting and fog changes keep recoil dormant, while inactive guns do not sweep",function()
		local s=Motion.new(cfg,1);Motion.advance(s,cfg,{1,1,1,99,0,1},20,.1,true,1)
		eq(Motion.pose(s,cfg,20,16).kick,0)
		local h=s.heading;Motion.advance(s,cfg,{0,0,0,99,9,0},21,.1,true,1);eq(s.heading,h)
		Motion.advance(s,cfg,{1,1,2,100,0,2},22,.1,false,1);eq(s.sequence,nil);eq(Motion.pose(s,cfg,22,16).kick,0)
	end)
end
