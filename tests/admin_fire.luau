--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local function make():any
		local h:any={ignites=0,resets=0,studio=false}
		local env:any=setmetatable({game={CreatorType="user",CreatorId=1,GetService=function(_,key)
			return if key=="RunService" then {IsStudio=function() return h.studio end} else {PlayerRemoving={Connect=function() end}} end},
			Enum={CreatorType={User="user",Group="group"}},task={spawn=function(fn) fn() end},warn=function() end},{__index=getfenv()})
		h.admin=luau.load(fs.readFile("src/server/Match/Admin.luau"),{environment=env})()
		h.sim={time=0,sides={},deps={map={width=100,height=50}},houseFires={
			igniteAt=function(x,y) h.ignites+=1;h.x=x;h.y=y;return 2 end,reset=function() h.resets+=1 end}}
		h.owner={UserId=1,Name="owner"};h.other={UserId=2,Name="other"};return h
	end
	test("fire admin commands enforce server ownership, opening pause and finite map bounds",function()
		local h=make();local function fire(player,x,y) return h.admin.handle(h.sim,player,1,{op="townFire",x=x,y=y}) end
		fire(h.other,1,1);eq(h.ignites,0)
		h.sim.drop={phase="pick"};fire(h.owner,1,1);eq(h.ignites,0);h.sim.drop=nil
		for _,xy in {{-1,0},{0,-1},{100,1},{1,50},{math.huge,1},{0/0,1},{"1",1}} do fire(h.owner,xy[1],xy[2]);eq(h.ignites,0) end
		eq(fire(h.owner,20.5,11.5),"Ignited 2 nearby roofs");eq(h.ignites,1);eq(h.x,20.5);eq(h.y,11.5)
		h.sim.winner=1;fire(h.owner,1,1);eq(h.ignites,1)
	end)
	test("fire resets preserve permanent houses and remain owner-only for other layers",function()
		local h=make();local ground=0;h.sim.groundScorch={reset=function() ground+=1 end}
		h.admin.handle(h.sim,h.other,1,{op="rebuildFires"});eq(h.resets,0);eq(ground,0)
		eq(h.admin.handle(h.sim,h.owner,1,{op="rebuildFires"}),"Forest and ground reset; houses stay ruined until next match");eq(h.resets,0);eq(ground,1)
		h.sim.groundScorch=nil;h.sim.houseFires=nil;eq(h.admin.handle(h.sim,h.owner,1,{op="townFire",x=1,y=1}),"House fire data unavailable on this map")
		eq(h.admin.handle(h.sim,h.owner,1,{op="rebuildFires"}),"House fire data unavailable on this map");eq(h.resets,0)
	end)
	test("forest ignition and reset enforce server authority while preserving house ruins",function()
		local h=make();local ignites,resets=0,0
		h.sim.forestFires={igniteAt=function(x,y) ignites+=1;eq(x,20);eq(y,10);return 3 end,reset=function() resets+=1 end}
		h.admin.handle(h.sim,h.other,1,{op="forestFire",x=20,y=10});eq(ignites,0)
		h.admin.handle(h.sim,h.owner,1,{op="forestFire",x=math.huge,y=10});eq(ignites,0)
		eq(h.admin.handle(h.sim,h.owner,1,{op="forestFire",x=20,y=10}),"Ignited 3 nearby trees");eq(ignites,1)
		h.admin.handle(h.sim,h.other,1,{op="rebuildFires"});eq(resets,0)
		h.admin.handle(h.sim,h.owner,1,{op="rebuildFires"});eq(h.resets,0);eq(resets,1)
		h.sim.houseFires=nil;h.sim.forestFires=nil;eq(h.admin.handle(h.sim,h.owner,1,{op="forestFire",x=20,y=10}),"Forest fire data unavailable on this map")
	end)
end
