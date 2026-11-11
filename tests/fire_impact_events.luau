--!strict
return function(test:any,eq:any)
	local Impacts=require("../src/shared/Simulation/WorldFireImpacts")
	local function make(config)
		local h:any={requests={},wet=false};h.model=Impacts.new(config,20,16,{water=function() return h.wet end,emit=function(x,y,weapon,size) table.insert(h.requests,{x=x,y=y,weapon=weapon,size=size}) end});return h
	end
	test("fire-impact adapter keeps direct impacts available without optional event settings",function()
		local h=make(nil);assert(h.model.fire(1.5,2.5,"shell"));eq(#h.requests,1)
		eq(h.model.event({type="mineBlast",x=1,y=1}),false);eq(#h.requests,1)
		for _,xy in {{-1,0},{0,-1},{20,0},{0,16},{math.huge,1},{0/0,1},{"1",1},{nil,1}} do eq(h.model.fire(xy[1],xy[2],"shell"),false) end
		eq(#h.requests,1);h.wet=true;eq(h.model.fire(1,1,"shell"),false);eq(#h.requests,1)
	end)
	local fs=require("@lune/fs");if not fs.isFile("src/shared/GameData/FireImpactVectors.luau") then return end
	local config=require("../src/shared/GameData/FireImpactRules") ::any
	local refs=require("../src/shared/GameData/FireImpactVectors") ::any
	test("structure and primary demolition fire hooks match original effect callbacks",function()
		for _,case in refs.references do
			local h=make(config)
			if case.kind=="razed" then h.model.event({type="destroyed",cat="structure",kind=case.building,x=7.5,y=9.5})
			else h.model.event({type="demoBlast",x=7.5,y=9.5}) end
			eq(#case.requests,1);local expected=case.requests[1];eq(#h.requests,1)
			for key,value in expected do eq(h.requests[1][key],value) end
		end
	end)
	test("water splash filtering preserves the source road bridge exception",function()
		for _,surface in refs.surfaces do
			local count=0;local water={};for _,name in config.water do water[name]=true end
			local adapter=Impacts.new(config,2,2,{water=function() return not surface.road and water[surface.name]==true end,emit=function() count+=1 end})
			eq(adapter.fire(.5,.5,"shell"),not surface.wet);eq(count,if surface.wet then 0 else 1)
		end
	end)
	test("mine and destroyed-minefield impacts use shell settings without inventing a blast radius",function()
		local h=make(config);h.model.event({type="mineBlast",x=3.25,y=5.75});h.model.event({type="destroyed",cat="structure",kind="minefield",x=7.5,y=.5})
		eq(#h.requests,2);for _,r in h.requests do eq(r.weapon,config.mineWeapon);eq(r.size,nil) end
		eq(h.requests[1].x,3.25);eq(h.requests[2].x,7.5);eq(h.requests[2].y,.5)
	end)
	test("cancelled buildings, friendly demolition, rigs and unit losses do not duplicate extra fire hooks",function()
		local h=make(config)
		for _,event in {"demolished","buildCancelled","delivered","minefieldSpent","convoyLost"} do h.model.event({type=event,cat="structure",x=1,y=1,kind="factory"}) end
		h.model.event({type="destroyed",cat="structure",kind="rig",x=.5,y=.5})
		h.model.event({type="destroyed",cat="unit",kind="tank",x=.5,y=.5})
		h.model.event({type="destroyed",kind="factory"})
		h.model.event({type="destroyed",cat="structure",kind="factory",x=-1,y=.5})
		eq(#h.requests,0)
	end)
	test("all added event fire sources obey the same ground-water gate",function()
		local h=make(config);h.wet=true
		h.model.event({type="mineBlast",x=1,y=1});h.model.event({type="demoBlast",x=1,y=1});h.model.event({type="destroyed",cat="structure",kind="hq",x=.5,y=.5})
		eq(#h.requests,0)
	end)
	test("invalid optional fire-event settings disable extras while retaining guarded direct hits",function()
		local h=make({demoWeapon="missile"});eq(h.model.hasEvents,false);assert(h.model.fire(1,1,"shell"))
		eq(h.model.event({type="demoBlast",x=1,y=1}),false);eq(#h.requests,1)
		for _,size in {0/0,math.huge,-1,"1"} do eq(h.model.fire(1,1,"shell",size),false) end
		eq(#h.requests,1)
	end)
end
