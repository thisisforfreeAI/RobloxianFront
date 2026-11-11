--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/HouseFireVectors.luau") then return end
	local Fire=require("../src/shared/Simulation/HouseFire")
	local Hash=require("../src/shared/Utilities/Hash")
	local refs=require("../src/shared/GameData/HouseFireVectors") ::any
	local blasts=require("../src/shared/GameData/FireBlastVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("house weapon ignition, sampled roof hits and hot wreck blasts match original cases",function()
		local pw=refs.width*refs.settings.tileSize
		for _,case in blasts.houses do
			local seed=case.seed;local draws=0
			local fire=Fire.new(refs.settings,{width=refs.width,height=refs.height,roof=function(x,y) return refs.roof[y*pw+x+1]==1 end,builtAt=function() return true end,
				random=function() seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;draws+=1;return seed/4294967296 end})
			fire.blast(8/refs.settings.tileSize,8/refs.settings.tileSize,case.size,case.weapon);eq(draws,case.draws);eq(#fire.houses,#case.houses)
			for i,h in fire.houses do local e=case.houses[i];close(h.life,e.life);eq(#h.px,#e.px);for j,p in h.px do eq(p,e.px[j]) end end
		end
	end)
	test("house roof claims, burn stages, wind generations and rain match original trajectories",function()
		local pw=refs.width*refs.settings.tileSize
		for _,case in refs.cases do
			local seed=case.seed;local draws=0
			local function random():number seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;draws+=1;return seed/4294967296 end
			local fire=Fire.new(refs.settings,{width=refs.width,height=refs.height,random=random,
				roof=function(x,y) return refs.roof[y*pw+x+1]==1 end,rain=function() return if case.mode=="rain" then .8 else 0 end})
			fire.ignite(7,7,0);fire.ignite(33,20,0);local checkpoint=1
			for _=1,400 do
				fire.tick(refs.settings.houses.tickSec);local expected=case.states[checkpoint]
				if expected and fire.time==expected.time then
					eq(draws,expected.draws);eq(fire.burnt,expected.burnt);eq(#fire.houses,#expected.houses);eq(#fire.shells,#expected.shells)
					for i,h in fire.houses do
						local e=expected.houses[i]
						for _,key in {"x","y","r","age","life","looked"} do close(h[key],e[key]) end
						for _,key in {"cell","gen","stage"} do eq(h[key],e[key]) end
						eq(#h.px,#e.px);for j,p in h.px do eq(p,e.px[j]) end
					end
					for i,h in fire.shells do
						local e=expected.shells[i];eq(h.cell,e.cell);close(h.at,e.at);close(h.x,e.x);close(h.y,e.y)
						eq(#h.px,#e.px);for j,p in h.px do eq(p,e.px[j]);eq(fire.mark[p],2) end
					end
					eq(#fire.scarOrder,#expected.scarred);for i,cell in fire.scarOrder do eq(cell,expected.scarred[i]) end
					checkpoint+=1
				end
			end
			eq(checkpoint,#case.states+1)
		end
	end)
	test("house claiming crosses cell seams, stops at its source budget and rolls back tiny fragments",function()
		local fire=Fire.new(refs.settings,{width=3,height=2,roof=function(x,y) return x>=10 and x<=35 and y>=2 and y<=20 end})
		local points=fire.claim(13,10);assert(points);eq(#points,refs.settings.houses.house.maxPx)
		local crossed=false;for _,p in points do if p%42>=14 then crossed=true end end;assert(crossed)
		fire.reset();eq(next(fire.mark),nil)
		local tiny=Fire.new(refs.settings,{width=1,height=1,roof=function(x,y) return x>=2 and x<4 and y==2 end})
		eq(tiny.claim(2,2),nil);eq(next(tiny.mark),nil);eq(tiny.ignite(-1,0),false)
		local forbidden=Fire.new(refs.settings,{width=1,height=1,roof=function() return true end,noFire=function() return true end})
		eq(forbidden.ignite(2,2),false);eq(next(forbidden.mark),nil)
	end)
	test("house hard caps, duplicate roof marks, restoration and reset prevent overlapping state",function()
		local settings=table.clone(refs.settings);settings.houses=table.clone(settings.houses);settings.houses.cap=table.clone(settings.houses.cap);settings.houses.cap.hard=1
		local stages={};local restores=0;local scar=0
		local fire=Fire.new(settings,{width=4,height=2,roof=function(x,y) return x%10<8 and y<8 end,random=function() return 0 end,
			onStage=function(_h,stage) table.insert(stages,stage) end,onRestore=function() restores+=1 end,onScar=function() scar+=1 end})
		eq(fire.ignite(2,2),true);eq(fire.ignite(2,2),false);eq(fire.ignite(12,2),false);eq(#fire.houses,1)
		eq(fire.burningNear(.5,.5,2),true);fire.tick(100);eq(#fire.houses,0);eq(#fire.shells,1);assert(fire.burnt>0);eq(scar,1)
		eq(stages[1],0);eq(stages[#stages],3)
		fire.raise(fire.shells[1]);eq(fire.burnt,0);eq(#fire.shells,0);eq(restores,1);eq(next(fire.mark),nil)
		eq(fire.ignite(2,2),true);fire.reset();eq(next(fire.mark),nil);eq(#fire.houses,0);eq(fire.time,0)
	end)
end
