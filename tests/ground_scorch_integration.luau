--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	if not fs.isFile("src/shared/GameData/FireRules.luau") then return end
	local config=require("../src/shared/GameData/FireRules") ::any
	test("actual house and forest burnout callbacks feed ground burns once per source cell",function()
		local scars={};local time=0;local context={time=function() return time end,weather=function() return "clear" end,random=function() return .5 end,towns={},
			onScar=function(...) table.insert(scars,{...}) end}
		local house=require("../src/shared/Simulation/HouseWorld").new(config,{width=4,height=4,tileSize=config.tileSize,
			roof=function(x,y) return x>=4 and x<9 and y>=4 and y<9 end,builtAt=function() return true end,townIndex=function() return nil end},context)
		assert(house.model.ignite(7,7));local h=house.model.houses[1];h.life=.01;house.advance(.25);eq(#scars,1);eq(scars[1][5],"burn")
		local t={key=17,x=1.5,y=1.5,cell=5,size=.4,standing=true}
		local forest=require("../src/shared/Simulation/ForestWorld").new(config,{width=4,height=4,trees={t},byKey={[17]=t},forNear=function() end,fuelAt=function() return true end},context)
		assert(forest.model.ignite(t));forest.model.burns[1].life=.01;forest.advance(.25);eq(#scars,2);eq(scars[2][1],1.5);eq(scars[2][2],1.5);eq(scars[2][5],"burn")
		house.advance(.5);forest.advance(.5);eq(#scars,2)
	end)
	test("actual admin fire reset clears shared ground scars only for the authorized owner",function()
		local env:any=setmetatable({game={CreatorType="user",CreatorId=1,GetService=function(_,key)
			return if key=="RunService" then {IsStudio=function() return false end} else {PlayerRemoving={Connect=function() end}} end},
			Enum={CreatorType={User="user",Group="group"}},task={spawn=function(fn) fn() end},warn=function() end},{__index=getfenv()})
		local admin=luau.load(fs.readFile("src/server/Match/Admin.luau"),{environment=env})()
		local clears=0;local sim={time=0,sides={},houseFires={reset=function() end},groundScorch={reset=function() clears+=1 end}}
		admin.handle(sim,{UserId=2,Name="other"},1,{op="rebuildFires"});eq(clears,0)
		admin.handle(sim,{UserId=1,Name="owner"},1,{op="rebuildFires"});eq(clears,1)
	end)
end
