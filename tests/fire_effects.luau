--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/FireEffectsVectors.luau") then return end
	local Effects=require("../src/shared/Presentation/FireEffects")
	local Hash=require("../src/shared/Utilities/Hash")
	local config=require("../src/shared/GameData/FireEffectsRules") ::any
	local refs=require("../src/shared/GameData/FireEffectsVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	local function clone(actors:{any}):{any} local out={};for _,a in actors do table.insert(out,table.clone(a)) end;return out end
	local function point(p:number):(number?,number?) return if p>=0 then p%64 else nil,if p>=0 then math.floor(p/64) else nil end
	test("fire flame, smoke and ember requests match original frames across zoom, age and night vision",function()
		for _,case in refs.cases do
			local trees,houses=clone(refs.trees),clone(refs.houses);local seed,draws=case.seed,0;local commands={}
			local fx=Effects.new(config,{random=function() seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;draws+=1;return seed/4294967296 end,
				visible=function(_x,_y,cell) return cell>=0 end,onScreen=function(x) return x<50 end,point=point,nightVisionMix=function() return case.mix end,
				emit=function(kind,p) table.insert(commands,{kind=kind,p=p}) end})
			fx.frame(trees,houses,case.dt,case.zoom);eq(draws,case.draws);eq(#commands,#case.commands)
			for i,command in commands do
				local e=case.commands[i];eq(command.kind,e.kind)
				for key,value in command.p do if type(value)=="number" then close(value,e.p[key]) else eq(value,e.p[key]) end end
				for key in e.p do assert(command.p[key]~=nil,"missing fire request field "..key) end
			end
			for i,a in trees do close(a.flameAcc,case.treeAcc[i][1]);close(a.smokeAcc,case.treeAcc[i][2]);close(a.emberAcc,case.treeAcc[i][3]) end
			for i,a in houses do close(a.flameAcc,case.houseAcc[i][1]);close(a.smokeAcc,case.houseAcc[i][2]);close(a.emberAcc,case.houseAcc[i][3]) end
		end
	end)
	test("combined forest and town emission stays capped after a hitch and drops overdue bursts",function()
		local trees,houses={},{}
		for i=1,200 do table.insert(trees,{x=i,y=1,cell=i,size=.7,age=50,life=100,flameAcc=.9,smokeAcc=.9,emberAcc=.9}) end
		for i=1,32 do table.insert(houses,{x=i,y=2,cell=i,r=.7,px={65,66,129,130},age=50,life=100,flameAcc=.9,smokeAcc=.9,emberAcc=.9}) end
		local commands=0;local fx=Effects.new(config,{random=function() return .5 end,visible=function() return true end,onScreen=function() return true end,point=point,emit=function() commands+=1 end})
		eq(fx.frame(trees,houses,20,32),512);eq(commands,512)
		for _,actors in {trees,houses} do for _,a in actors do assert(a.flameAcc<1 and a.smokeAcc<1 and a.emberAcc<1) end end
		commands=0;eq(fx.frame(trees,houses,.001,32),0);eq(commands,0)
	end)
	test("hidden and offscreen fire sources emit nothing and do not consume cosmetic RNG",function()
		local random=0;local trees,houses=clone(refs.trees),clone(refs.houses)
		local fx=Effects.new(config,{random=function() random+=1;return .5 end,visible=function() return false end,onScreen=function() return true end,point=point,emit=function() error("hidden fire emitted") end})
		eq(fx.frame(trees,houses,1,16),0);eq(random,0)
		for i,a in trees do eq(a.flameAcc,refs.trees[i].flameAcc);eq(a.smokeAcc,refs.trees[i].smokeAcc) end
		for i,a in houses do eq(a.flameAcc,refs.houses[i].flameAcc);eq(a.smokeAcc,refs.houses[i].smokeAcc) end
	end)
end
