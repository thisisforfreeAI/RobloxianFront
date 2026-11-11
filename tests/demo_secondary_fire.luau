--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	if not fs.isFile("src/shared/GameData/FireImpactVectors.luau") then return end
	local Impacts=require("../src/shared/Simulation/WorldFireImpacts")
	local config=require("../src/shared/GameData/FireImpactRules") ::any
	local refs=require("../src/shared/GameData/FireImpactVectors") ::any
	if not refs.pops then return end
	local function fixture():any
		local h:any={time=0,draw=0,requests={}}
		h.model=Impacts.new(config,20,16,{time=function() return h.time end,random=function() h.draw+=1;return assert(refs.pops.draws[h.draw]) end,
			water=function(x,y) return if h.water then h.water(x,y) else false end,emit=function(x,y,weapon,size) table.insert(h.requests,{x=x,y=y,weapon=weapon,size=size}) end})
		return h
	end
	local function close(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("demolition secondary ignition positions and delays match original effect pop callbacks",function()
		local h=fixture();h.model.event({type="demoBlast",x=7.5,y=9.5});eq(#h.requests,1);eq(#h.model.pending,#refs.pops.requests)
		eq(h.draw,#refs.pops.draws)
		for i,p in h.model.pending do local expected=refs.pops.requests[i];close(p.at,expected.at);close(p.x,expected.x);close(p.y,expected.y);eq(p.weapon,expected.weapon) end
		local first=math.huge;for _,p in h.model.pending do first=math.min(first,p.at) end
		h.model.advance(first/2);eq(#h.requests,1)
		h.time=config.pops.to;h.model.advance(h.time);eq(#h.requests,1+config.pops.count);eq(#h.model.pending,0)
		h.model.advance(h.time+1);eq(#h.requests,1+config.pops.count)
	end)
	test("delayed fire impacts pause on war time and reset cancels every pending pop",function()
		local h=fixture();h.model.event({type="demoBlast",x=7.5,y=9.5});local n=#h.model.pending
		h.model.advance(0);h.model.advance(0);eq(#h.model.pending,n);eq(#h.requests,1)
		h.model.reset();eq(#h.model.pending,0);h.model.advance(10);eq(#h.requests,1)
		assert(not pcall(function() h.model.advance(9) end))
	end)
	test("demolition pops check each landing surface independently of a water-covered blast centre",function()
		local h=fixture();h.water=function(x,y) return x==7.5 and y==9.5 end
		eq(h.model.event({type="demoBlast",x=7.5,y=9.5}),false);eq(#h.requests,0);eq(#h.model.pending,config.pops.count)
		h.model.advance(config.pops.to);eq(#h.requests,config.pops.count)
		local wet=fixture();wet.water=function() return true end;wet.model.event({type="demoBlast",x=7.5,y=9.5});wet.model.advance(config.pops.to);eq(#wet.requests,0);eq(#wet.model.pending,0)
	end)
	test("owner fire reset cancels delayed impacts without granting other players control",function()
		local clears=0;local env:any=setmetatable({game={CreatorType="user",CreatorId=1,GetService=function(_,key)
			return if key=="RunService" then {IsStudio=function() return false end} else {PlayerRemoving={Connect=function() end}} end},
			Enum={CreatorType={User="user",Group="group"}},task={spawn=function(fn) fn() end},warn=function() end},{__index=getfenv()})
		local admin=luau.load(fs.readFile("src/server/Match/Admin.luau"),{environment=env})()
		local sim={time=0,sides={},houseFires={reset=function() end},fireImpacts={reset=function() clears+=1 end}}
		admin.handle(sim,{UserId=2,Name="other"},1,{op="rebuildFires"});eq(clears,0)
		admin.handle(sim,{UserId=1,Name="owner"},1,{op="rebuildFires"});eq(clears,1)
	end)
	test("incomplete delayed-pop profiles are rejected while legacy primary-only profiles remain usable",function()
		local bad=table.clone(config);bad.pops={weapon="shell",radius={.5,1},count=3}
		eq(Impacts.valid(bad),false)
		local legacy=table.clone(config);legacy.pops=nil;eq(Impacts.valid(legacy),true)
		local h=Impacts.new(legacy,20,16,{emit=function() end});h.event({type="demoBlast",x=7.5,y=9.5});eq(#h.pending,0)
	end)
end
