--!strict
return function(test:any,eq:any)
	local Refugees=require("../src/shared/Simulation/Refugees")
	local Column=require("../src/shared/Presentation/RefugeeColumn")
	local Hash=require("../src/shared/Utilities/Hash")
	local fs=require("@lune/fs")
	local synthetic={reach=2,pathCells=6,speed=1,length=3,lingerSec=2,widthCells=1,truckShare=.4,cooldownSec=5}
	local town={id=1,x=2.5,y=2.5,radius=1,destroyed=false}
	local function road(c:number):boolean return math.floor(c/10)==2 end
	local function make(enabled:boolean,gameplay:boolean):any
		return Refugees.new({width=10,height=5,onRoad=road,rules=synthetic,enabled=enabled,gameplay=gameplay,random=function() return .5 end})
	end
	test("refugee shelling cooldown also covers failed routes and disabled/ruined towns",function()
		local state=make(true,false)
		assert(state.onShelled(town,0));eq(state.onShelled(town,4),nil);assert(state.onShelled(town,5))
		eq(make(false,false).onShelled(town,0),nil)
		eq(state.onShelled({id=2,x=2.5,y=2.5,radius=1,destroyed=true},10),nil)
		local absent=Refugees.new({width=10,height=5,onRoad=function() return false end,rules=synthetic,enabled=true,gameplay=false,random=function() return .5 end})
		eq(absent.onShelled(town,0),nil);eq(absent.fled[1],0)
		eq(Refugees.route(10,5,function(c) return c==22 or c==23 end,town,synthetic,function() return .5 end),nil)
	end)
	test("refugee spans stop at route end, linger, expire and keep visual-only trucks unchanged",function()
		local visual=make(true,false);local column=visual.onShelled(town,0)
		local head,tail=Refugees.span(column,100);eq(head,#column.path-1);eq(tail,math.max(0,head-3))
		eq(visual.truckFactor(2.5,2.5,0),1)
		local gameplay=make(true,true);gameplay.onShelled(town,0)
		eq(gameplay.truckFactor(2.5,2.5,0),.4);eq(gameplay.truckFactor(2.5,20,0),1)
		visual.step(column.untilTime);eq(#visual.list,0)
	end)
	if not fs.isFile("src/shared/GameData/RefugeeVectors.luau") then return end
	local refs=require("../src/shared/GameData/RefugeeVectors") ::any
	local look=require("../src/shared/GameData/RefugeeLook") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-9,tostring(a).." != "..tostring(b)) end
	test("refugee escape routes match original BFS and endpoint selection on Saddle",function()
		for _,v in refs.routes do
			local path=Refugees.route(refs.width,refs.height,function(c) return refs.road[c+1]==1 end,v.town,refs.rules,function() return v.random end)
			eq(table.concat(path or {},","),table.concat(v.path or {},","))
		end
	end)
	test("column spans, person/cart/car positions and looks match the original renderer",function()
		local cart,car=false,false
		for _,v in refs.columnVectors do
			local head,tail=Refugees.span(refs.column,v.time);close(head,v.head);close(tail,v.tail)
			local poses=Column.poses(refs.column,v.time,refs.width,look,Hash.ambient,function() return true end)
			eq(#poses,#v.poses)
			for i,p in poses do
				local source=v.poses[i];eq(p.model,source.model)
				for _,key in {"x","y","heading","cells"} do close(p[key],source[key]) end
				cart=cart or p.model=="cart";car=car or p.group=="cars"
			end
		end
		assert(cart and car,"reference should exercise carts and cars")
	end)
	test("truck crawl footprint agrees with original active-column rule",function()
		local state=Refugees.new({width=refs.width,height=refs.height,rules=refs.rules,enabled=true,gameplay=true})
		state.list={refs.column}
		for _,point in refs.factors do close(state.truckFactor(point.x,point.y,35),point.value) end
		eq(state.truckFactor(0,0,refs.column.untilTime),1)
	end)
	test("refugee actor packets expose visible positions without origin, route or destination",function()
		local count=0
		local poses=Column.poses(refs.column,35,refs.width,look,Hash.ambient,function(x,y) return x<200 and y>100 end)
		for _,p in poses do
			assert(p.x<200 and p.y>100);assert(p.path==nil and p.city==nil and p.t==nil and p.untilTime==nil)
			if p.phase then assert(p.phase>=0 and p.phase<2/look.people.stride) end
			count+=1
		end
		assert(count>0)
		eq(#Column.poses(refs.column,35,refs.width,look,Hash.ambient,function() return false end),0)
	end)
	test("ended columns vanish and lingering actors do not drift during client prediction",function()
		local poses=Column.poses(refs.column,refs.column.untilTime-1,refs.width,look,Hash.ambient,function() return true end)
		assert(#poses>0)
		for _,p in poses do
			eq(p.vx,0);eq(p.vy,0);eq(p.speed,0);p.time=refs.column.untilTime-1
			local predicted=Column.predict(p,p.time+.5,look.people.stride);close(p.x,predicted.x);close(p.y,predicted.y)
		end
		eq(#Column.poses(refs.column,refs.column.untilTime,refs.width,look,Hash.ambient,function() return true end),0)
	end)
	test("shelling integrates with the simulation while visual columns preserve combat and economy",function()
		local Sim=require("../src/shared/Simulation/Sim")
		local Rules=require("../src/shared/Config/Rules")
		local Roads=require("../src/shared/Simulation/Roads")
		local Pathing=require("../src/shared/Simulation/Pathing")
		local Territory=require("../src/shared/Simulation/Territory")
		local ValueNoise=require("../src/shared/Utilities/ValueNoise")
		local Rng=require("../src/shared/Utilities/Rng")
		local rules=table.clone(require("../src/shared/GameData/RulesMatch") ::any);rules["events.on"]=false
		local function makeSim(enabled:boolean):any
			return Sim.new({rules=Rules.new(rules),roadsLib=Roads,pathingLib=Pathing,territoryLib=Territory,valueNoise=ValueNoise,rng=Rng,
				refugeesLib=Refugees,refugeesEnabled=enabled,seed=117,
				map={width=180,height=60,terrainAt=function() return "plains" end,roads={{rank=2,pts={.5,30.5,179.5,30.5}}}},
				starts={{x=10.5,y=30.5},{x=170.5,y=30.5}},rigs={},settlements={{kind="village",x=10,y=30}}})
		end
		local baseline,visual=makeSim(false),makeSim(true)
		for _,sim in {baseline,visual} do
			local hq=sim.hqOf(1)
			sim.spawnUnit("infantry",2,15.5,30.5)
			sim.strikes={{kind="structure",at=0,target=hq.id,damage=1,bombard=true,by=2}}
		end
		for _=1,120 do baseline.step(.05);visual.step(.05) end
		eq(#baseline.refugees.list,0);eq(#visual.refugees.list,1)
		eq(visual.refugees.truckFactor(10.5,30.5,visual.time),1)
		eq(#visual.list,#baseline.list);eq(visual.sides[1].oil,baseline.sides[1].oil)
		for i,e in baseline.list do
			local other=visual.list[i];eq(other.id,e.id);close(other.hp,e.hp);close(other.x,e.x);close(other.y,e.y);close(other.shotTimer or 0,e.shotTimer or 0)
		end
	end)
end
