--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/ForestFireVectors.luau") then return end
	local Fire=require("../src/shared/Simulation/ForestFire")
	local Hash=require("../src/shared/Utilities/Hash")
	local refs=require("../src/shared/GameData/ForestFireVectors") ::any
	local blasts=require("../src/shared/GameData/FireBlastVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("forest dryness hash matches the original across signed seed values",function()
		for _,v in refs.hashes do close(Fire.hash(v.x,refs.settings.drynessSalt),v.y) end
	end)
	test("forest weapon splintering, felling, ignition and hot wrecks match original blast cases",function()
		for _,case in blasts.forest do
			local seed=case.seed;local draws=0
			local fire=Fire.new(refs.settings,{width=32,trees=refs.trees,random=function()
				seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;draws+=1;return seed/4294967296
			end})
			fire.blast(8,7,case.size,case.weapon);eq(draws,case.draws);eq(#fire.burns,#case.burns);eq(#fire.fateOrder,#case.fates);eq(#fire.hot,#case.hot)
			for i,b in fire.burns do eq(b.key,case.burns[i].key);close(b.life,case.burns[i].life) end
			for i,key in fire.fateOrder do
				local e=case.fates[i];eq(key,e.key);eq(fire.fates[key].kind,e.kind);eq(fire.fates[key].char,e.char)
				if e.rot then close(fire.fates[key].rot,e.rot) end
			end
			for i,h in fire.hot do local e=case.hot[i];close(h.x,e.x);close(h.y,e.y);close(h.reach,e.reach);close(h.perSec,e.perSec);close(h.untilTime,e["until"]) end
		end
	end)
	test("forest ignition, wind spread, char, rain, firebreaks and regrowth match original trajectories",function()
		for _,case in refs.cases do
			local seed=case.seed;local draws=0
			local function random():number seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;draws+=1;return seed/4294967296 end
			local context:any={width=32,trees=refs.trees,random=random,rain=function() return if case.mode=="rain" then .8 else 0 end,
				firebreakAt=function(cell) return case.mode=="firebreak" and cell%32==7 end}
			if case.mode=="gap" then context.fuelAt=function() return false end end
			local fire=Fire.new(refs.settings,context);fire.ignite(refs.trees[39]);fire.ignite(refs.trees[45])
			local checkpoint=1
			for _=1,6400 do
				fire.tick(refs.settings.forest.tickSec)
				local expected=case.states[checkpoint]
				if expected and fire.time==expected.time then
					eq(draws,expected.draws);eq(#fire.burns,#expected.burns)
					for i,b in fire.burns do
						local e=expected.burns[i];eq(b.key,e.key);eq(b.char,e.char);close(b.age,e.age);close(b.life,e.life);close(b.looked,e.looked)
					end
					eq(#fire.fateOrder,#expected.fates)
					for i,key in fire.fateOrder do local e=expected.fates[i];eq(key,e.key);eq(fire.fates[key].kind,e.kind);eq(fire.fates[key].char,e.char) end
					eq(#fire.scarOrder,#expected.scarred);for i,cell in fire.scarOrder do eq(cell,expected.scarred[i]) end
					checkpoint+=1
				end
			end
			eq(checkpoint,#case.states+1)
		end
	end)
	test("forest hard cap, duplicate ignition and reset keep model state bounded without mutating map trees",function()
		local serde=require("@lune/serde");local before=serde.encode("json",refs.trees)
		local settings=table.clone(refs.settings);settings.forest=table.clone(settings.forest);settings.forest.cap=table.clone(settings.forest.cap);settings.forest.cap.hard=3
		local fire=Fire.new(settings,{width=32,trees=refs.trees,random=function() return .5 end})
		eq(fire.igniteAt(8,7,20),3);eq(#fire.burns,3);eq(fire.ignite(refs.trees[1]),false)
		fire.tick(.25);fire.reset();eq(#fire.burns,0);eq(#fire.fateOrder,0);eq(#fire.scarOrder,0);eq(next(fire.burning),nil);eq(fire.time,0)
		eq(fire.ignite(refs.trees[1]),true);eq(fire.ignite(refs.trees[1]),false)
		eq(before,serde.encode("json",refs.trees))
	end)
	test("forest spread cannot cross water or a firebreak and only rarely jumps one empty cell",function()
		local a,b={key=1,x=1.5,y=1.5,cell=11,size=.5,standing=true},{key=2,x=3.5,y=1.5,cell=13,size=.5,standing=true}
		local random=.5;local water,barrier=true,false
		local fire=Fire.new(refs.settings,{width=10,trees={a,b},random=function() return random end,
			waterAt=function(cell) return water and cell==12 end,firebreakAt=function(cell) return barrier and cell==12 end})
		eq(fire.open(a,b),false);water=false;barrier=true;eq(fire.open(a,b),false)
		barrier=false;eq(fire.open(a,b),false);random=0;eq(fire.open(a,b),true)
		b.x=4.5;b.cell=14;eq(fire.open(a,b),false)
	end)
	test("forest hot wreck ignition expires and scars emit once per burned cell",function()
		local settings=table.clone(refs.settings);settings.forest=table.clone(settings.forest);settings.forest.burn=table.clone(settings.forest.burn);settings.forest.burn.sec={.1,.1}
		local scars=0
		local fire=Fire.new(settings,{width=32,trees=refs.trees,random=function() return 0 end,onScar=function() scars+=1 end})
		fire.heat(6,6,2,100,1);fire.tick(.25);assert(scars>0);eq(scars,#fire.scarOrder)
		fire.tick(1);eq(#fire.hot,0);eq(scars,#fire.scarOrder)
		fire.reset();eq(#fire.hot,0)
	end)
end
