--!strict
return function(test:any,eq:any)
	local People=require("../src/shared/Presentation/CivilianPeople")
	local Traffic=require("../src/shared/Presentation/CivilianTraffic")
	local Hash=require("../src/shared/Utilities/Hash")
	local fs=require("@lune/fs")
	if not fs.isFile("src/client/DevAssets/OrigCivilianTraffic_saddle.luau") then return end
	local data=require("../src/client/DevAssets/OrigCivilianTraffic_saddle") ::any
	if not data.config.people then return end
	local refs=require("../src/shared/GameData/CivilianVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-9,tostring(a).." differs from "..tostring(b)) end
	local function poses(actual:{any},expected:{any})
		eq(#actual,#expected)
		for i,p in expected do
			eq(actual[i].model,p.model)
			for _,key in {"x","y","heading","alpha"} do close(actual[i][key],p[key]) end
		end
	end
	test("ambient pedestrian hash agrees with original seed vectors",function()
		for _,v in refs.hash do close(Hash.ambient(v.id,v.channel),v.value) end
	end)
	test("walking, standing and fading pedestrian poses match original reference runs",function()
		for _,case in refs.people do
			local w=table.clone(case.walker);local index=1
			for step=0,600 do
				local time=step/10
				local pose=People.walker(w,refs.road,data.config.people,Traffic.sample,time,if step==0 then 0 else .1,step==0,not(case.mode=="fade" and time>=5))
				if step%5==0 then
					local expected=case.vectors[index];index+=1
					close(w.alpha,expected.alpha);poses(if pose then {pose} else {},expected.poses)
				end
			end
		end
	end)
	local view={x0=-100,x1=100,y0=-100,y1=100}
	local function make(case:any):any
		local world=Traffic.new({config=data.config,lines={refs.road},towns={{id=1,seedId=case.seedId,kind=case.kind,x=case.x,y=case.y,radius=case.radius,cars={},parked={},walkers={},exits=case.exits}}})
		world.towns[1].known=true;world.towns[1].hitAt=if case.mode=="fight" then -99 else 10
		return People.new(world,Traffic,Hash.ambient)
	end
	test("town-hit, nearby-fight and ruined-town evacuation match original wave references",function()
		for _,case in refs.flee do
			local state=make(case);local index=1
			for step=0,200 do
				local time=10+step/10
				if case.mode=="ruined" and step==50 then state.world.towns[1].destroyed=true;state.world.towns[1].integrity=0 end
				local fighters=if case.mode=="fight" then {{x=15,y=0,shotAge=time-10,hitAge=9}} else {}
				local actual=People.step(state,time,if step==0 then 0 else .1,1,0,fighters,0,view,function() return true end,step==0)
				if step%5==0 then poses(actual,case.vectors[index].poses);index+=1 end
			end
		end
	end)
	test("hidden fights and unknown towns never create visible fleeing civilians",function()
		local state=make(refs.flee[2])
		local fighters={{x=15,y=0,shotAge=0,hitAge=0}}
		for step=0,30 do
			local out=People.step(state,10+step*.1,.1,1,0,fighters,0,view,function() return false end,step==0)
			eq(#out,0);eq(state.places[1].fightAt,-math.huge)
		end
		state.world.towns[1].known=false
		for step=0,30 do eq(#People.step(state,10+step*.1,.1,1,0,fighters,0,view,function() return true end,false),0) end
	end)
	test("quiet town pedestrians recede at night and stale combat does not restart evacuation",function()
		local world=Traffic.new(data)
		for _,town in world.towns do town.known=true end
		local state=People.new(world,Traffic,Hash.ambient)
		local wide={x0=-1000,x1=1000,y0=-1000,y1=1000}
		assert(#People.step(state,100,0,1,0,{},0,wide,function() return true end,true)>0)
		eq(#People.step(state,100,.1,1,1,{},0,wide,function() return true end,true),0)
		local fight=make(refs.flee[2])
		People.look(fight,100,{{x=15,y=0,shotAge=0,hitAge=0}},20,view,function() return true end)
		eq(fight.places[1].fightAt,-math.huge)
	end)
	test("evacuation stays capped and clock rewind clears old waves",function()
		local world=Traffic.new(data)
		for _,town in world.towns do town.known=true;town.hitAt=10 end
		local state=People.new(world,Traffic,Hash.ambient)
		local wide={x0=-1000,x1=1000,y0=-1000,y1=1000}
		People.step(state,10,0,0,1,{},0,wide,function() return true end,true)
		local out=People.step(state,13,0,0,1,{},0,wide,function() return true end,false)
		assert(#out>0 and #out<=data.config.fleeing.maxShown)
		for _,town in world.towns do town.hitAt=-99 end
		eq(#People.step(state,0,0,0,1,{},0,wide,function() return true end,true),0)
	end)
	test("pedestrian atlas variants preserve world scale and complete all poses/facings",function()
		local pixels=require("../src/client/DevAssets/OrigCivilianPeople_saddle") ::any
		local Codec=require("../src/shared/Maps/MapCodec")
		local Inflate=require("../src/shared/Utilities/Inflate")
		close(pixels.frame/pixels.px,pixels.half.frame/pixels.half.px)
		for _,variant in {pixels,pixels.half} do
			local size=variant.width*variant.height*4
			eq(buffer.len(Inflate.raw(Codec.base64Decode(variant.deflate),size)),size)
			eq(buffer.len(Inflate.raw(Codec.base64Decode(variant.shade),size)),size)
			local count=0
			for _,y in variant.rects do count+=1;assert(y+variant.frame<=variant.height) end
			eq(count,10);assert(variant.rects.cart~=nil);eq(variant.width,variant.frame*variant.facings)
			assert(variant.width<=1024 and variant.height<=1024)
		end
	end)
end
