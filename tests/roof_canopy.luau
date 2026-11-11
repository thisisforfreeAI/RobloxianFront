--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");if not fs.isFile("src/shared/GameData/FireRules.luau") then return end
	local Scorch=require("../src/shared/Presentation/FireScorch")
	local Pixels=require("../src/shared/Presentation/FirePixels")
	local config=require("../src/shared/GameData/FireRules") ::any
	local map={tileSize=2,sourceId=function() return 19 end,original=function() return {100,120,140,226} end,roof=function() return true end}
	local b={tx=0,ty=0,points={{p=33,x=1,y=1,stage=1}}};local at=(1*16+1)*4
	local function layer(alpha)
		local cover=buffer.create(16*16*4);buffer.writeu8(cover,at,20);buffer.writeu8(cover,at+1,200);buffer.writeu8(cover,at+2,40);buffer.writeu8(cover,at+3,alpha);return cover
	end
	test("opaque forest foreground stays above every roof char and ruin stage",function()
		for stage=1,3 do
			b.points[1].stage=stage
			local px,count=Scorch.paint(map,config,b,function() return true end,function() return {20,200,40} end,layer(255))
			eq(count,1);eq(buffer.readu8(px,at),20);eq(buffer.readu8(px,at+1),200);eq(buffer.readu8(px,at+2),40);eq(buffer.readu8(px,at+3),255)
		end
	end)
	test("partial canopy recovers the underlying roof shade before compositing damage",function()
		b.points[1].stage=1;local alpha=128/255;local original={100,120,140,226};local fg={20,200,40}
		local px=Scorch.paint(map,config,b,function() return true end,function()
			return {original[1]*.6*(1-alpha)+fg[1]*alpha,original[2]*.6*(1-alpha)+fg[2]*alpha,original[3]*.6*(1-alpha)+fg[3]*alpha}
		end,layer(128))
		local char=Pixels.house(config,19,original,1,false)
		for ch=0,2 do eq(buffer.readu8(px,at+ch),math.floor(char[ch+1]*.6*(1-alpha)+fg[ch+1]*alpha+.5)) end
	end)
	test("empty cover preserves existing roof output while fog still suppresses the entire pixel",function()
		b.points[1].stage=2;local function lit() return {60,72,84} end
		local baseline=Scorch.paint(map,config,b,function() return true end,lit)
		local empty=Scorch.paint(map,config,b,function() return true end,lit,layer(0));eq(buffer.tostring(empty),buffer.tostring(baseline))
		local hidden,n=Scorch.paint(map,config,b,function() return false end,lit,layer(255));eq(n,0);eq(buffer.tostring(hidden),string.rep("\0",buffer.len(hidden)))
		assert(not pcall(Scorch.paint,map,config,b,function() return true end,lit,buffer.create(1)))
	end)
end
