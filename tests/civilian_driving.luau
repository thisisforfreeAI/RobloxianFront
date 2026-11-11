--!strict
return function(test:any,eq:any)
	local Traffic=require("../src/shared/Presentation/CivilianTraffic")
	local Driving=require("../src/shared/Presentation/CivilianDriving")
	local look={widths={major={half=.8},minor={half=.4},track={half=.2}},look={major={lane=.35,edge=.65}}}
	local config={cars={speed=1.2,flee=2,waitCells=.9,fadeSec=.8,lane=.1,parked=.2,cross=.45,cells=.46,streetCells=.36},
		towns={critical=.1,damaged=.5,garrisoned=.5,calmSec=10,returnSec=10,nightCars=.2},criticalBelow=.2,damagedBelow=.6}
	local function car(line:number,a:number,b:number):any
		return {line=line,a=a,b=b,s=a,dir=math.sign(b-a),off=0,alpha=1,pullA=true,pullB=true,parkA=0,parkB=1000,seed=0,model="synthetic"}
	end
	local function make(cars:{any},cross:boolean?):(any,any)
		local roads={{rank=2,pts={0,15,30,15}}}
		local lines={{pts=roads[1].pts,cum={0,30},len=30}}
		if cross then table.insert(roads,{rank=2,pts={15,0,15,30}});table.insert(lines,{pts=roads[2].pts,cum={0,30},len=30}) end
		local state=Traffic.new({config=config,lines=lines,towns={{id=1,x=0,y=15,radius=3,cars=cars,parked={}}}})
		local flow=Driving.new(state,roads,look,Traffic)
		state.towns[1].known=true;state.towns[1].snap=false
		return state,flow
	end
	local function step(state:any,flow:any,time:number,dt:number,movers:{any}?):{any}
		Driving.plan(flow,time,dt,1,0,false,movers)
		local poses=Traffic.step(state,time,dt,1,0,movers or {},nil,false)
		Driving.finish(flow);return poses
	end
	test("road-width traffic uses opposite outer lanes instead of the highway centre",function()
		local state,flow=make({car(1,0,30),car(1,30,0)})
		local info=flow.lines[1];eq(info.lane,.5)
		local a=flow.pose(state.data.lines[1],15,info.lane,1)
		local b=flow.pose(state.data.lines[1],15,-info.lane,-1)
		eq(a.y,15.5);eq(b.y,14.5);assert(math.abs(a.y-15)+info.cells*.23<info.half)
	end)
	test("same-lane cars queue behind a stopped leader and maintain clearance",function()
		local state,flow=make({car(1,0,30),car(1,0,30)})
		local cars=state.towns[1].cars
		for i,c in cars do c.s=if i==1 then 20 else 18;c.off=.5;c.dir=1;c.flowShown=true end
		for k=1,150 do step(state,flow,100+k*.05,.05,{{x=20.9,y=15}});assert(cars[1].s-cars[2].s>=.63) end
		assert(cars[2].s>18);eq(cars[1].s,20)
		for k=151,230 do step(state,flow,100+k*.05,.05) end
		assert(cars[1].s>21 and cars[2].s>19)
	end)
	test("opposing civilian cars pass in separate lanes without blocking one another",function()
		local state,flow=make({car(1,0,30),car(1,30,0)})
		local a,b=state.towns[1].cars[1],state.towns[1].cars[2]
		a.s=12;a.off=.5;a.dir=1;a.flowShown=true
		b.s=18;b.off=-.5;b.dir=-1;b.flowShown=true
		for k=1,120 do step(state,flow,100+k*.05,.05) end
		assert(a.s>16 and b.s<14)
	end)
	test("crossing civilian flows take turns and both clear the junction",function()
		local state,flow=make({car(1,0,30),car(2,0,30)},true)
		eq(#flow.nodes,1)
		local a,b=state.towns[1].cars[1],state.towns[1].cars[2]
		for _,c in {a,b} do c.s=13;c.off=.5;c.dir=1;c.flowShown=true end
		local sawQueue=false
		for k=1,220 do
			local poses=step(state,flow,100+k*.05,.05)
			if a.s>15 and b.s<14 then sawQueue=true end
			if #poses==2 then assert((poses[1].x-poses[2].x)^2+(poses[1].y-poses[2].y)^2>.2,"cars collided inside junction") end
		end
		assert(sawQueue);assert(a.s>18 and b.s>18,"intersection starved one approach")
	end)
	test("arrival bays are staggered and new coincident actors do not appear as a stack",function()
		local state,flow=make({car(1,0,30),car(1,0,30),car(1,0,30)})
		local cars=state.towns[1].cars
		assert(math.abs(cars[1].a-cars[2].a)>.6)
		for _,c in cars do c.s=10;c.off=.5;c.dir=1;c.flowShown=false end
		local poses=step(state,flow,100,.05)
		eq(#poses,1)
	end)
	test("lane tangents blend through bends without a side jump onto the verge",function()
		local state,flow=make({car(1,0,30)})
		local bend={pts={0,0,10,0,10,10},cum={0,10,20},len=20}
		local a,b=flow.pose(bend,9.99,.5,1),flow.pose(bend,10.01,.5,1)
		assert(math.abs(a.heading-b.heading)<.1)
		assert((a.x-b.x)^2+(a.y-b.y)^2<.01)
		assert(math.min(math.abs(a.y),math.abs(a.x-10))<.8)
	end)
	test("a returning car can leave its curb bay when the old lane is occupied",function()
		local state,flow=make({car(1,0,30),car(1,30,0)})
		local a,b=state.towns[1].cars[1],state.towns[1].cars[2]
		a.s=a.a;a.dir=-1;a.off=-.79;a.flowShown=true
		b.s=1.1;b.dir=-1;b.off=-.5;b.flowShown=true
		for k=1,180 do step(state,flow,100+k*.05,.05) end
		assert(a.s>5,"departing car locked itself in the wrong lane")
	end)
	test("a blocked approach yields the intersection to the clear approach",function()
		local state,flow=make({car(1,0,30),car(2,0,30)},true)
		local a,b=state.towns[1].cars[1],state.towns[1].cars[2]
		for _,c in {a,b} do c.s=13;c.off=.5;c.dir=1;c.flowShown=true end
		for k=1,150 do step(state,flow,100+k*.05,.05,{{x=13.8,y=15.5}}) end
		eq(a.s,13);assert(b.s>18,"blocked road retained the junction reservation")
	end)
end
