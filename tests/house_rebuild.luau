--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/HouseRebuildVectors.luau") then return end
	local House=require("../src/shared/Simulation/HouseFire")
	local settings=require("../src/shared/GameData/FireRules") ::any
	local refs=require("../src/shared/GameData/HouseRebuildVectors") ::any
	test("house reconstruction matches original quiet periods, town pacing, nearby fires and lone ruins",function()
		for _,case in refs do
			local town={id=1,integrity=30,maxIntegrity=100,lastHitAt=-100};local raised={};local worldTime=0
			local fire=House.new(settings,{width=10,height=10,roof=function() return false end,
				townAt=function(cell) return if case.mode=="lone" or cell==4 then nil else town end,
				rebuildRules={quietSec=20,fullSec=200},worldTime=function() return worldTime end,
				onRestore=function(shell) table.insert(raised,{id=shell.id,at=worldTime}) end})
			for id=1,4 do table.insert(fire.shells,{id=id,cell=id,x=id,y=2,at=0,px={id}}) end
			if case.mode=="nearby" then fire.houses={{x=2,y=2}} end
			local checkpoint=1
			for time=1,400 do
				fire.time=time;worldTime=time
				if case.mode=="recent" and time==15 then town.lastHitAt=15 end
				if case.mode=="nearby" and time==50 then fire.houses={} end
				fire.rebuildShells();local e=case.states[checkpoint]
				if e and time==e.time then
					eq(#fire.shells,#e.remaining);for i,shell in fire.shells do eq(shell.id,e.remaining[i]) end
					eq(#raised,#e.raised);for i,record in raised do eq(record.id,e.raised[i].id);eq(record.at,e.raised[i].at) end
					local count=0;for _ in fire.nextUp do count+=1 end;eq(count,#e.nextUp)
					for _,nextUp in e.nextUp do eq(fire.nextUp[nextUp[1]],nextUp[2]) end
					checkpoint+=1
				end
			end
			eq(checkpoint,#case.states+1)
		end
	end)
	test("house tick uses the source rebuild cadence and reset clears its reconstruction timers",function()
		local fire=House.new(settings,{width=10,height=10,roof=function() return false end})
		fire.shells={{id=1,cell=1,x=1,y=1,at=0,px={1}}};fire.time=100
		local checks=0;local original=fire.rebuildShells
		fire.rebuildShells=function() checks+=1;original() end
		for _=1,3 do fire.tick(.25) end;eq(checks,0)
		fire.tick(.25);eq(checks,1);eq(#fire.shells,1)
		fire.tick(0);eq(checks,1);fire.reset();eq(next(fire.nextUp),nil);eq(fire.rebuildAcc,0);eq(#fire.shells,0)
	end)
end
