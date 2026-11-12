--!strict
return function(test:any,eq:any)
	local H=require("../src/shared/Presentation/PlacementHint");local Roads=require("../src/shared/Simulation/Roads")
	local function fixture():any
		local w,h=15,15;local rules:any={["terrain.plains.buildable"]=true,["terrain.plains.passable"]=true,["terrain.river.passable"]=false,["terrain.deep.passable"]=false,["production.roadClearShare"]=1,["production.roadClearPad"]=1,["production.spacing"]=0,["rigs.padCells"]=1,["movement.bridgeDeck.half"]=1}
		local map={width=w,height=h,terrain=buffer.create(w*h),data={legend={"plains","river","deep"},roads={},rigs={}}};local inside={};for c=0,w*h-1 do inside[c]=true end
		return {map=map,rules=rules,inside=inside}
	end
	test("local road preparation matches the authoritative raster including bridges and deep-water skips",function()
		local h=fixture();h.map.data.roads={{rank=1,pts={1.5,7.5,13.5,7.5}},{rank=0,pts={1.5,3.5,13.5,3.5}}}
		for y=6,8 do for x=5,8 do buffer.writeu8(h.map.terrain,y*15+x,1) end end;buffer.writeu8(h.map.terrain,7*15+8,2)
		local count=0;local model=H.prepare(h.map,h.rules,Roads.line,function() count+=1 end)
		local source=Roads.build({width=15,height=15,roads=h.map.data.roads,terrainAt=function(c) return h.map.data.legend[buffer.readu8(h.map.terrain,c)+1] end,passable=function(t) return h.rules[`terrain.{t}.passable`]==true end,bridgeHalf=1,truckCost={[0]=1,1,1,1},offRoadCost=1,offRoadReach=3})
		for c=0,224 do eq(buffer.readu8(model.road,c)==1,source.isRoad(c)) end;assert(count>0);eq(buffer.readu8(model.road,7*15+8),0)
	end)
	test("placement hints catch map bounds, terrain, road clearance and never wrap row edges",function()
		local h=fixture();h.map.data.roads={{rank=1,pts={2.5,4.5,12.5,4.5}}};local model=H.prepare(h.map,h.rules,Roads.line)
		local clean=H.check(model,7,10,1,h.inside,{},1,"barracks",nil);eq(clean.ok,true)
		eq(H.check(model,0,10,1,h.inside,{},1,"barracks",nil).reason,"terrain")
		eq(H.check(model,7,6,1,h.inside,{},1,"barracks",nil).reason,"onRoad")
		buffer.writeu8(h.map.terrain,10*15+7,1);local bad=H.check(model,7,10,1,h.inside,{},1,"barracks",nil);eq(bad.reason,"terrain");eq(#bad.blocked,1)
	end)
	test("only supplied known structures produce spacing and clash hints",function()
		local h=fixture();local model=H.prepare(h.map,h.rules,Roads.line)
		eq(H.check(model,7,7,1,h.inside,{},1,"barracks",nil).ok,true)
		local result=H.check(model,7,7,1,h.inside,{{kind="hq",x=10.5,y=7.5,side=2,built=1,stale=true}},1,"barracks",nil)
		eq(result.reason,"spacing");eq(#result.clashes,1);eq(result.clashes[1].cells,5)
	end)
	test("own private resources and completed prerequisites remain advisory and partial state is allowed",function()
		local h=fixture();local model=H.prepare(h.map,h.rules,Roads.line);h.rules["structures.factory.cost"]=100;h.rules["structures.factory.requires"]={"barracks"};h.rules["structures.factory.killCost"]=5
		local own={{kind="barracks",x=2.5,y=2.5,side=1,built=1}}
		eq(H.check(model,10,10,1,h.inside,own,1,"factory",{oil=99,kills=5}).reason,"oil")
		eq(H.check(model,10,10,1,h.inside,own,1,"factory",{oil=100,kills=4}).reason,"kills")
		eq(H.check(model,10,10,1,h.inside,{},1,"factory",{oil=100,kills=5}).reason,"requires")
		eq(H.check(model,10,10,1,h.inside,own,1,"factory",{oil=100,kills=5}).ok,true)
		eq(H.check(model,10,10,1,h.inside,own,1,"factory",nil).ok,true)
	end)
end
