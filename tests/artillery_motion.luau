--!strict
return function(test:any,eq:any)
	local M=require("../src/shared/Presentation/ArtilleryMotion")
	local c={rest=-.4,turn=2,raiseSec=.5,holdSec=3,recoilSec=.8,recoilShare=.25,kick=.2,cells=4,gun={-.5,-.25},pod={.5,.25},parts={gun={"g0","g1","g2"},pod={"p0","p1"}}}
	local function near(a,b) assert(math.abs(a-b)<1e-8,`{a} != {b}`) end
	local function sample(t,gun,pod,active,running) return {if active==false then 0 else 1,t,if running==false then 0 else 1,gun or {0,0,0,0,{}},pod or {0,0,0,0,{}}} end
	test("artillery snapshots baseline existing shots and discard hidden launch history",function()
		local e={kind="artybase",artilleryVisual={gun={x=10,y=20,last=4,fires={4}},pod={x=30,y=40,last=8,fires={6,8}}}}
		local p,cache=M.snapshot(e,true,true,nil,9,true);eq(#p,5);eq(p[4][1],0);eq(#p[4][5],0);eq(#p[5][5],0)
		e.artilleryVisual.gun={x=11,y=21,last=10,fires={10}};p,cache=M.snapshot(e,true,true,cache,10,true)
		eq(p[4][1],1);eq(p[4][2],11);eq(p[4][5][1],10);eq(p[5][1],0)
		eq(M.snapshot(e,false,true,cache,11,true),nil)
		p=M.snapshot(e,true,true,nil,11,true);eq(#p[4][5],0);eq(M.snapshot({kind="sam"},true,true,nil,0,true),nil)
	end)
	test("same-side viewers receive identical gun and pod schedules without mutating them",function()
		local e={kind="artybase"};local _,cache=M.snapshot(e,true,true,nil,1,true)
		e.artilleryVisual={pod={x=9,y=8,last=4,fires={2,3,4}}}
		local a;a,cache=M.snapshot(e,true,true,cache,2,true);local b=M.snapshot(e,true,true,cache,2,true)
		for i=1,4 do eq(a[5][i],b[5][i]) end;eq(a[5][5],b[5][5]);eq(#e.artilleryVisual.pod.fires,3)
	end)
	test("artillery aims from each mounted origin with bounded turning and raising",function()
		local s=M.new(c);local origin={10,20,8}
		M.advance(s,c,sample(1),0,0,true,1,origin)
		M.advance(s,c,sample(2,{1,9,30,2,{2}},{1,11,30,2,{2}}),1,.1,true,1,origin)
		near(s.slots[1].heading,-.2);near(s.slots[2].heading,-.2);near(s.slots[1].up,.2)
		for i=1,20 do M.advance(s,c,sample(2,{1,9,30,2,{2}},{1,11,30,2,{2}}),1+i*.05,.05,true,1,origin) end
		near(s.slots[1].heading,math.pi/2);near(s.slots[2].heading,math.pi/2);near(s.slots[1].up,1)
	end)
	test("scheduled pod pulses wait for firing time and the gun uses its short recoil sprite",function()
		local s=M.new(c);M.advance(s,c,sample(1),0,0,true,0,{0,0,4})
		M.advance(s,c,sample(2,{1,20,0,4,{2,4}},{1,20,0,3,{3}}),1,0,true,0,{0,0,4})
		local g=M.pose(s,c,1,1);eq(g.part,"g2");near(g.kick,.2);eq(M.pose(s,c,2,1).kick,0)
		s.warAt=2.3;g=M.pose(s,c,1,1);eq(g.part,"g0");assert(g.kick>0)
		s.warAt=3;local p=M.pose(s,c,2,1);eq(p.part,"p0");near(p.kick,.05)
		s.warAt=4;eq(M.pose(s,c,1,1).part,"g2");near(M.pose(s,c,1,1).kick,.2)
	end)
	test("hold lasts beyond the last scheduled shell and inactive artillery lowers toward rest",function()
		local s=M.new(c);M.advance(s,c,sample(1),0,0,true,3,{0,0,4})
		M.advance(s,c,sample(2,nil,{1,20,0,5,{2,5}}),1,.1,true,3,{0,0,4})
		for i=1,10 do M.advance(s,c,sample(7,nil,{1,20,0,5,{2,5}}),1+i*.05,.05,true,3,{0,0,4}) end
		eq(s.slots[2].up,1)
		M.advance(s,c,sample(7,nil,{1,20,0,5,{2,5}},false),2,.1,true,3,{0,0,4});near(s.slots[2].up,.8)
		for i=1,15 do M.advance(s,c,sample(9,nil,{1,20,0,5,{2,5}}),2+i*.1,.1,true,3,{0,0,4}) end
		near(s.slots[2].up,0);near(s.slots[2].heading,c.rest+.25+(3*.7)%.3)
	end)
	test("war pause holds recoil while mount turning uses real time and extrapolation is bounded",function()
		local s=M.new(c);M.advance(s,c,sample(1),0,0,true,0,{0,0,4})
		local p=sample(2,{1,0,20,2,{2}},nil,true,false)
		M.advance(s,c,p,1,.1,true,0,{0,0,4});local heading=s.slots[1].heading;local kick=M.pose(s,c,1,1).kick
		M.advance(s,c,p,30,.1,true,0,{0,0,4});near(M.pose(s,c,1,30).kick,kick);assert(s.slots[1].heading~=heading)
		M.advance(s,c,sample(2.1,{1,0,20,2,{2}}),31,.1,true,0,{0,0,4});near(M.time(s,100),2.3)
	end)
	test("fog clears artillery clocks, holds and pulses before reveal baselines",function()
		local s=M.new(c);M.advance(s,c,sample(1),0,0,true,0,{0,0,4})
		local p=sample(2,{4,10,10,2,{2}});M.advance(s,c,p,1,.1,true,0,{0,0,4})
		M.advance(s,c,p,2,.1,false,0,{0,0,4});eq(s.warAt,nil);eq(s.slots[1].sequence,nil);eq(#s.slots[1].fires,0)
		M.advance(s,c,p,3,.1,true,0,{0,0,4});eq(M.pose(s,c,1,3).kick,0);eq(s.slots[1].sequence,4)
	end)
end
