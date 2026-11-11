--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	local Packets=require("../src/shared/Protocol/FirePackets")
	local World=require("../src/shared/Simulation/ForestWorld")
	local View=require("../src/shared/Presentation/ForestFireView")
	local Map=require("../src/shared/Simulation/ForestMap")
	test("forest packets preserve source keys, fates, optional char and bounded rotation buffers",function()
		local known={[3000000000]={},[17]={},[19]={},[21]={},[23]={}}
		local rows={{3000000000,{kind="burning",char=0}},{17,{kind="fallen",rot=-1.25}},{19,{kind="stump"}},{21,{kind="burnt"}},{23,nil}}
		local px=Packets.trees(rows);local result=Packets.readTrees(px,known,3);eq(buffer.len(px),70)
		for i,row in rows do eq(result[i][1],row[1]);if row[2] then eq(result[i][2].kind,row[2].kind);eq(result[i][2].char,row[2].char) else eq(result[i][2],nil) end end
		eq(result[2][2].rot,-1.25)
		eq(pcall(Packets.readTrees,buffer.create(13),known,3),false)
		eq(pcall(Packets.readTrees,Packets.trees({{5,{kind="burnt"}}}),known,3),false)
		eq(pcall(Packets.readTrees,Packets.trees({{17,{kind="burning",char=3}}}),known,3),false)
		eq(pcall(Packets.readTrees,Packets.trees({{17,{kind="fallen",rot=math.huge}}}),known,3),false)
		eq(pcall(Packets.readTrees,buffer.create((Packets.TREES_PER_PACKET+1)*14),known,3),false)
	end)
	test("forest firebreak raster uses source road rank and four samples per cell",function()
		local roads={{rank=1,pts={.5,.5,9.5,.5}},{rank=2,pts={.5,1.5,9.5,1.5}},{rank=3,pts={-5,3.5,14,3.5}}}
		local mask=Map.firebreaks(10,5,roads,2)
		for x=0,9 do eq(buffer.readu8(mask,x),0);eq(buffer.readu8(mask,10+x),1);eq(buffer.readu8(mask,30+x),1) end
	end)
	if not fs.isFile("src/shared/GameData/FireRules.luau") then return end
	local settings=require("../src/shared/GameData/FireRules") ::any
	local function make():any
		local h:any={time=0,weather="clear"};local map:any={width=32,height=24,trees={},byKey={}}
		for i=0,699 do local t={key=i,x=5+(i%35)*.1,y=5+math.floor(i/35)*.1,cell=5*32+5,size=.4,standing=true};table.insert(map.trees,t);map.byKey[i]=t end
		function map.forNear(x,y,reach,fn) for _,t in map.trees do local d=math.sqrt((t.x-x)^2+(t.y-y)^2);if d<=reach then fn(t,d) end end end
		function map.fuelAt(_cell,fates) for _,t in map.trees do local f=fates[t.key];if not f or f.kind=="burning" then return true end end;return false end
		h.map=map;h.world=World.new(settings,map,{time=function() return h.time end,weather=function() return h.weather end,random=require("../src/shared/Utilities/Rng").new(517)})
		return h
	end
	local function visible() return true end
	test("forest world pauses at fixed source ticks and applies map-wide rain rates without changing tree data",function()
		local h=make();h.world.model.ignite(h.map.trees[1]);local b=h.world.model.burns[1]
		h.world.advance(.1);eq(b.age,0);h.world.advance(.25);eq(b.age,.25);h.world.advance(.25);eq(b.age,.25)
		h.weather="downpour";h.world.advance(.5);eq(b.age,.25+.25*settings.forest.rain.hurry);eq(b.ageRate,settings.forest.rain.hurry)
		eq(h.map.trees[1].fate,nil);eq(pcall(h.world.advance,.4),false)
	end)
	test("forest world filters hidden changes and restorations, retries overflow and resets epochs",function()
		local h=make();for _,t in h.map.trees do h.world.versions[t.key]=1;h.world.model.fates[t.key]={kind="burnt"} end
		local packet,cache=h.world.view(nil,function() return false end);eq(buffer.len(packet.fates),0)
		packet,cache=h.world.view(cache,visible);eq(buffer.len(packet.fates),Packets.TREES_PER_PACKET*14)
		packet,cache=h.world.view(cache,visible);eq(buffer.len(packet.fates),(700-Packets.TREES_PER_PACKET)*14)
		h.world.model.fates[0]=nil;h.world.versions[0]=2
		packet,cache=h.world.view(cache,function() return false end);eq(buffer.len(packet.fates),0)
		packet,cache=h.world.view(cache,visible);local rows=Packets.readTrees(packet.fates,h.map.byKey,settings.charStages);eq(rows[1][1],0);eq(rows[1][2],nil)
		h.world.reset();packet,cache=h.world.view(cache,visible);eq(packet.reset,true);eq(next(cache.known),nil)
	end)
	test("forest client actors preserve emission phases and age baselines while stale epochs cannot restore old damage",function()
		local h=make();local updates,resets={},0
		local view=View.new(h.map,settings,{random=function() return .5 end,clear=function() resets+=1 end,fates=function(rows,reset) updates=rows end})
		local packet={epoch=1,reset=true,time=10,fates=Packets.trees({{0,{kind="burning",char=1}}}),actors={{key=0,age=4,life=20,rate=2}}}
		view.apply(packet);eq(resets,1);eq(updates[1][2].char,1);view.actors[0].flameAcc=.8
		packet.reset=false;packet.time=10.5;packet.actors[1].age=5;view.apply(packet);eq(view.actors[0].flameAcc,.8)
		local actors=view.frame(10.75);eq(actors[1].drawAge,5.5);eq(packet.actors[1].age,5);eq(actors[1].x,h.map.trees[1].x)
		view.apply({epoch=2,reset=true,time=11,fates=Packets.trees({}),actors={}});eq(resets,2);eq(view.apply(packet),false);eq(next(view.actors),nil)
	end)
end
