--!strict
return function(test:any,eq:any)
	local Events=require("../src/shared/Protocol/CollapseEvents")
	test("collapse events bound transient structure losses and exclude noncollapse events",function()
		local queue={}
		for _,event in {{type="destroyed",cat="unit",kind="tank"},{type="demolished",cat="structure",kind="factory"},{type="destroyed",cat="structure",kind="rig"},{type="destroyed",cat="structure",kind="minefield"}} do
			event.id=1;event.x=1;event.y=1;eq(Events.push(queue,event,20,16),false)
		end
		for i=1,Events.LIMIT+10 do Events.push(queue,{type="destroyed",cat="structure",id=i,kind="hq",x=i%20+.5,y=4},20,16) end
		eq(#queue,Events.LIMIT);eq(Events.push(queue,{type="destroyed",cat="structure",id=1,kind="hq",x=1,y=1},20,16),false)
		local seen=Events.visible(queue,function(x) return x<10 end);assert(#seen>0 and #seen<#queue)
		for _,row in seen do assert(row[3]<10) end
		table.clear(queue);eq(#Events.visible(queue,function() return true end),0)
	end)
	test("collapse rows reject malformed bounds and deduplicate without retaining packet references",function()
		local row={7,"factory",3,4};local rows=Events.read({row,row},20,16);eq(#rows,1);row[3]=12;eq(rows[1][3],3)
		for _,bad in {{{1,"hq",0/0,1}},{{1,"hq",1,math.huge}},{{1,"hq",20,1}},{{0,"hq",1,1}},{{1,"rig",1,1}},{{1,"minefield",1,1}},{{1,"hq",1,1},{-1,"factory",1,1}},{[1]={1,"hq",1,1},unexpected={2,"hq",1,1}}} do eq(#Events.read(bad,20,16),0) end
		local long={};for i=1,Events.LIMIT+1 do long[i]={i,"hq",1,1} end;eq(#Events.read(long,20,16),0);eq(#Events.read(nil,20,16),0)
	end)
	local fs=require("@lune/fs");if not fs.isFile("src/shared/GameData/CollapseVectors.luau") then print("skip CollapseVectors (export_collapse_fx.cjs)");return end
	local Effects=require("../src/shared/Presentation/CollapseEffects");local Hash=require("../src/shared/Utilities/Hash")
	local config=require("../src/shared/GameData/CollapseFx") ::any
	local references=require("../src/shared/GameData/CollapseVectors") ::any
	local function compare(actual:any,expected:any)
		for key,value in expected do
			if type(value)=="table" then compare(actual[key],value)
			elseif type(value)=="number" then assert(type(actual[key])=="number" and math.abs(actual[key]-value)<1e-8,tostring(key)..": "..tostring(actual[key]).." != "..value)
			else eq(actual[key],value,tostring(key)) end
		end
		for key in actual do assert(expected[key]~=nil,"unexpected field "..tostring(key)) end
	end
	test("factory and HQ collapse requests match original razed and burner sequences",function()
		for _,case in references do
			local seed=case.seed;local commands={}
			local fx=Effects.new(config,{random=function() seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;return seed/4294967296 end,
				visible=function() return true end,emit=function(kind,p) table.insert(commands,{kind=kind,p=p}) end})
			assert(fx.raze(case.building,7.5,9.5));compare(commands,case.frames[1].commands);commands={}
			for i=2,#case.frames do
				local frame=case.frames[i];fx.step(frame.dt);eq(#commands,#frame.commands,case.building.." at "..frame.time)
				compare(commands,frame.commands);commands={}
			end
			eq(#fx.active,0);eq(#fx.later,0)
		end
	end)
	test("hidden collapse emission drains its clock without replaying hidden requests",function()
		local shown=true;local commands=0
		local fx=Effects.new(config,{visible=function() return shown end,emit=function() commands+=1 end,random=function() return .5 end})
		shown=false;eq(fx.raze("factory",2,3),false);eq(commands,0)
		shown=true;assert(fx.raze("factory",2,3));shown=false;local before=commands
		for _=1,math.ceil(config.collapse.smokeSec/.05)+2 do fx.step(.05) end
		eq(commands,before);eq(#fx.active,0);shown=true;fx.step(.05);eq(commands,before)
	end)
	test("collapse bursts bound timers requests and hitch work while sharing the death particle cap",function()
		local Death=require("../src/shared/Presentation/DeathEffects");local deathConfig=require("../src/shared/GameData/DeathFx")
		local engine=Death.new(deathConfig,function() return .5 end);engine.maxParticles=20;local requests=0
		local fx=Effects.new(config,{visible=function() return true end,random=function() return .5 end,emit=function(kind,p) requests+=1;engine:request(kind,p,"map") end})
		for _=1,100 do fx.raze("hq",2,3) end
		eq(#fx.active,fx.maxActive);assert(#fx.later<=fx.maxLater);assert(requests<=fx.maxCommands);assert(#engine.particles<=20)
		local before=fx.time;requests=0;fx.step(60);assert(fx.time-before<=.1+1e-8);assert(requests<=fx.maxCommands)
		fx.clear();eq(#fx.active,0);eq(#fx.later,0);requests=0;fx.step(1);eq(requests,0)
		engine:clearTag("map");eq(#engine.particles,0)
	end)
	test("invalid optional collapse settings are rejected before starting an effect",function()
		eq(Effects.valid(config),true)
		for _,bad in {{}, {collapse={}},setmetatable({},{})} do eq(Effects.valid(bad),false) end
		for _,key in {"hqScale","ringSec","fireLife","smokeSec","thump","firePerSec"} do
			local bad=table.clone(config);bad.collapse=table.clone(config.collapse);bad.collapse[key]=math.huge;eq(Effects.valid(bad),false)
		end
	end)
end
