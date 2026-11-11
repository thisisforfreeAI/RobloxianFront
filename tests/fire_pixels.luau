--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/FirePixelVectors.luau") then return end
	local Pixels=require("../src/shared/Presentation/FirePixels")
	local settings=require("../src/shared/GameData/FireRules") ::any
	local refs=require("../src/shared/GameData/FirePixelVectors") ::any
	test("house soot, char and ruined wall/floor pixels match the original byte for byte",function()
		for _,v in refs do
			local p=Pixels.house(settings,v.id,v.original,v.stage,v.edge)
			for channel=1,4 do eq(p[channel],v.result[channel]) end
		end
	end)
	test("fire modules load through Roblox ModuleScript dependencies as well as local test paths",function()
		local luau=require("@lune/luau");local Hash=require("../src/shared/Utilities/Hash");local marker={}
		local env=setmetatable({script={Parent={Parent={Utilities={Hash=marker}}}},require=function(mod) eq(mod,marker);return Hash end},{__index=getfenv()})
		local pixels=luau.load(fs.readFile("src/shared/Presentation/FirePixels.luau"),{environment=env})()
		local forest=luau.load(fs.readFile("src/shared/Simulation/ForestFire.luau"),{environment=env})()
		local v=refs[1];local p=pixels.house(settings,v.id,v.original,v.stage,v.edge)
		for i=1,4 do eq(p[i],v.result[i]) end
		eq(forest.hash(37,61),Hash.seed(37,61))
	end)
end
