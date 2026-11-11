--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/FireParticleVectors.luau") then return end
	local Effects=require("../src/shared/Presentation/DeathEffects")
	local Hash=require("../src/shared/Utilities/Hash")
	local config=require("../src/shared/GameData/DeathFx") ::any
	local refs=require("../src/shared/GameData/FireParticleVectors") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("shared fire puff and ember primitives match original spawn fields",function()
		for _,case in refs do
			local seed=case.seed
			local fx=Effects.new(config,function() seed=(Hash.imul(seed,1664525)+1013904223)%4294967296;return seed/4294967296 end)
			eq(fx:request(case.kind,case.p,"map"),true);eq(#fx.particles,#case.particles)
			for i,p in fx.particles do
				local e=case.particles[i]
				for key,value in e do if type(value)=="number" then close(p[key],value) else eq(p[key],value) end end
				eq(p.worldTag,"map");eq(p.age,0)
			end
		end
	end)
	test("world fire requests share the death pool cap and tag cleanup preserves unrelated particles",function()
		local fx=Effects.new(config,function() return .5 end)
		local p={tex="blobA",x=1,y=2,h=.3,vh=1,size=.5,life=2,color=config.colors.fire}
		eq(fx:request("spawn",p,"a"),true);eq(p.age,nil);eq(p.worldTag,nil)
		fx:request("spawn",p,"b");fx:request("spawn",p,nil);fx:clearTag("a");eq(#fx.particles,2)
		fx:clearTag(nil);eq(#fx.particles,2)
		fx:request("embers",{x=1,y=2,h=.4,count=100000,spread=.5},"b");eq(#fx.particles,fx.maxParticles)
		eq(fx:request("spawn",p,"c"),false);fx:clearTag("b");eq(#fx.particles,1);eq(fx.particles[1].worldTag,nil)
		fx:step(3);eq(#fx.particles,0);eq(fx:request("unknown",p,"a"),false)
	end)
end
