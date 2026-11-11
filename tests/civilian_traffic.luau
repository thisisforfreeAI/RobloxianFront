--!strict
return function(test:any,eq:any)
	local Traffic=require("../src/shared/Presentation/CivilianTraffic")
	local line={pts={0,0,20,0,20,10},cum={0,20,30},len=30}
	-- Synthetic fixtures, independent of the private extracted configuration.
	local config={speed=1,flee=2,waitCells=1,fadeSec=1,lane=.1,parked=.2,cross=.5,cells=.5,streetCells=.4}
	local function car():any return {a=0,b=20,pullA=true,pullB=true,parkA=0,parkB=10,seed=0,s=0,dir=1,alpha=1,off=0,model="synthetic",line=1} end
	test("civilian polyline sampling follows bends, clamps ends and retains tangent",function()
		local a=Traffic.sample(line,10);eq(a.x,10);eq(a.y,0);eq(a.dx,1)
		local b=Traffic.sample(line,25);eq(b.x,20);eq(b.y,5);eq(b.dx,0);eq(b.dy,1)
		eq(Traffic.sample(line,-4).x,0);eq(Traffic.sample(line,100).y,10)
	end)
	test("civilian cars yield to nearby units and stop at a cut road without teleporting",function()
		local a=car()
		Traffic.advance(a,line,config,1,1,false,true,false,{{x=1,y=0}},nil);eq(a.s,0)
		Traffic.advance(a,line,config,1,1,false,true,false,{},function() return false end);eq(a.s,0)
		Traffic.advance(a,line,config,1,1,false,true,false,{},function() return true end);eq(a.s,1)
	end)
	test("civilian route cycles park, return in the opposite lane, and stay on the polyline",function()
		local a=car()
		local out=Traffic.advance(a,line,config,10,0,true,true,false,{},nil)
		eq(a.s,10);eq(out.y,.1)
		a.s=20
		out=Traffic.advance(a,line,config,35,1,false,true,false,{},nil)
		eq(a.s,19);eq(a.dir,-1);assert(out.y<0)
	end)
	test("civilian panic uses fleeing speed and fades at its endpoint",function()
		local a=car();a.s=15
		Traffic.advance(a,line,config,0,1,false,false,true,{},nil);eq(a.s,17)
		Traffic.advance(a,line,config,0,2,false,false,true,{},nil);eq(a.s,20);eq(a.alpha,0)
	end)
	local data={lines={line},towns={{id=1,x=5,y=0,radius=3,cars={car()},parked={}}},config={cars=config,towns={critical=.1,damaged=.5,garrisoned=.5,calmSec=10,returnSec=10,nightCars=.2},criticalBelow=.2,damagedBelow=.6}}
	test("hidden and ruined settlements do not emit civilian traffic or expose stale health",function()
		local state=Traffic.new(data)
		eq(#Traffic.step(state,100,0,1,0,{},nil,true),0)
		Traffic.applyCities(state,{{1,0,0,0,1,0,2,"",0,100,0,-99}},100)
		assert(#Traffic.step(state,100,0,1,0,{},nil,true)>0)
		Traffic.applyCities(state,{{1,0,0,0,1,0,0,"",0,-1,0}},100)
		eq(#Traffic.step(state,100,0,1,0,{},nil,true),0)
		Traffic.applyCities(state,{{1,0,0,0,1,0,2,"",0,0,1,100}},100)
		eq(#Traffic.step(state,100,0,1,0,{},nil,true),0)
	end)
	test("town damage, garrisons, night and the calm interval reduce civilian activity",function()
		local t={known=true,integrity=100,garrison=0,hitAt=-99}
		local moving,parked,flee=Traffic.activity(t,data.config,100,1,1)
		assert(math.abs(moving-.2)<1e-12);eq(parked,1);eq(flee,false)
		t.integrity=50;t.garrison=1
		moving=Traffic.activity(t,data.config,100,1,0);eq(moving,.25)
		t.hitAt=100
		moving,parked,flee=Traffic.activity(t,data.config,105,1,0);eq(moving,0);eq(parked,0);eq(flee,true)
		moving=Traffic.activity(t,data.config,115,1,0);eq(moving,.125)
	end)
	local fs=require("@lune/fs")
	if not fs.isFile("src/client/DevAssets/OrigCivilianTraffic_saddle.luau") then return end
	local original=require("../src/client/DevAssets/OrigCivilianTraffic_saddle") ::any
	if fs.isFile("src/shared/GameData/CivilianVectors.luau") then
		local refs=require("../src/shared/GameData/CivilianVectors") ::any
		test("civilian normal/night/panic/blocked motion agrees with original class reference runs",function()
			for _,case in refs.cases do
				local a=table.clone(case.car);local nextVector=1
				for step=0,1800 do
					local time=step/10
					local movers=if case.scenario=="blocked" then {{x=a.s+.9,y=0}} else {}
					Traffic.advance(a,refs.road,original.config.cars,time,if step==0 then 0 else .1,step==0,case.scenario~="night" and case.scenario~="shock",case.scenario=="shock" and step>0,movers,nil)
					if step%15==0 then
						local expected=case.vectors[nextVector];nextVector+=1
						for _,key in {"s","alpha","off","dir"} do assert(math.abs(a[key]-expected[key])<1e-10,case.scenario.." "..key.." differs at "..time) end
					end
				end
			end
		end)
	end
	test("civilian shared sheets decode with all vehicle looks and source facings",function()
		local Codec=require("../src/shared/Maps/MapCodec")
		local Inflate=require("../src/shared/Utilities/Inflate")
		local expected=original.width*original.height*4
		eq(buffer.len(Inflate.raw(Codec.base64Decode(original.deflate),expected)),expected)
		eq(buffer.len(Inflate.raw(Codec.base64Decode(original.shade),expected)),expected)
		assert(original.width<=1024 and original.height<=1024)
		local count=0
		for _,y in original.rects do count+=1;assert(y+original.frame<=original.height) end
		eq(count,5);eq(original.width,original.frame*original.facings)
	end)
end
