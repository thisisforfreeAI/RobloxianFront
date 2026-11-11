--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/FireLightVectors.luau") then return end
	local Light=require("../src/shared/Presentation/FireLight")
	local Pixels=require("../src/shared/Presentation/FireLightPixels")
	local Codec=require("../src/shared/Maps/MapCodec")
	local Inflate=require("../src/shared/Utilities/Inflate")
	local config=require("../src/shared/GameData/FireLightRules") ::any
	local refs=require("../src/shared/GameData/FireLightVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("fire light grouping, caps and refresh timers match original forest and house calls",function()
		for _,case in refs.grouping do
			local requests={};local light=Light.new(config,64,{visible=function(_x,_y,cell) return not cell or cell%5~=3 end,
				enabled=function() return false end,emit=function(p) table.insert(requests,p) end})
			for _,state in case.states do
				light.time=state.time;table.clear(requests);light.refresh(case.actors,case.kind);eq(#requests,#state.requests)
				for i,p in requests do for key,value in p do
					local expected=state.requests[i][key]
					if type(value)=="number" then close(value,expected) elseif type(value)=="table" then for c,v in value do close(v,expected[c]) end else eq(value,expected) end
				end end
				local count=0;for key,value in light.due[case.kind] do
					count+=1;local found=false;for _,row in state.due do if row[1]==key then close(value,row[2]);found=true end end;assert(found)
				end;eq(count,#state.due)
			end
		end
	end)
	test("fire burn light fade, flicker and expiry match original effect frames",function()
		for _,case in refs.animation do
			local light=Light.new(config,64,{visible=function() return true end})
			light.lights={{x=1,y=1,h=.6,reach=5,power=1.25,age=0,life=7,seed=case.seed,curve="burn"}}
			for _,state in case.states do
				light.step(state.dt);eq(#light.lights,state.active)
				if state.active>0 then close(light.lights[1].age,state.age);close(light.lights[1].now,state.now) end
			end
		end
	end)
	test("fire light raster matches original Bayer, overlap, knee and night vision at each resolution",function()
		for _,case in refs.raster do
			local scale=math.max(1,math.min(config.light.texelsPerCell,math.floor(case.scale/config.light.minTexelPx)))
			local actual=Pixels.paint(config,case.lights,0,0,12,10,scale,case.mix,Pixels.lookup(config,case.mix))
			local expected=Inflate.raw(Codec.base64Decode(case.deflate),case.w*case.h*4)
			eq(buffer.len(actual),buffer.len(expected))
			for i=0,buffer.len(actual)-1 do eq(buffer.readu8(actual,i),buffer.readu8(expected,i),`raster mix={case.mix} scale={scale} byte={i}`) end
		end
	end)
	test("disjoint fire tiles retain world Bayer phase and fog clips illuminated texels",function()
		local lights=refs.raster[1].lights;local lookup=Pixels.lookup(config,0)
		local whole=Pixels.paint(config,lights,-1,-1,20,16,3,0,lookup)
		local tile=Pixels.paint(config,lights,6,3,7,8,3,0,lookup)
		for y=0,23 do for x=0,20 do for c=0,3 do eq(buffer.readu8(tile,(y*21+x)*4+c),buffer.readu8(whole,((y+12)*60+x+21)*4+c)) end end end
		local hidden=Pixels.paint(config,lights,0,0,12,10,2,0,lookup,function(x) return x<4 end)
		for y=0,19 do for x=8,23 do eq(buffer.readu32(hidden,(y*24+x)*4),0) end end
	end)
	test("fire lights pause, obey visibility and reset without growing the source pool",function()
		local visible=true;local random=0
		local light=Light.new(config,64,{visible=function() return visible end,random=function() random+=1;return .5 end})
		local actors=refs.grouping[#refs.grouping].actors
		light.advance(actors,actors,config.tickSec);assert(#light.lights>0);assert(#light.lights<=config.light.max)
		local age=light.lights[1].age;light.advance(actors,actors,0);eq(light.lights[1].age,age)
		visible=false;local before=random;light.advance(actors,actors,20);eq(random,before);eq(#light.lights,0)
		light.reset();eq(light.time,0);eq(next(light.due.forest),nil);eq(next(light.due.houses),nil)
	end)
end
