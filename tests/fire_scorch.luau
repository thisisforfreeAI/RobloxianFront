--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	local Scorch=require("../src/shared/Presentation/FireScorch")
	test("fire scorch buckets cross tile seams and retain exact world-pixel identities",function()
		local p1,p2=15,16
		local buckets=Scorch.bucket(16,2,{[p1]=1,[p2]=3})
		eq(#buckets["0:0"].points,1);eq(#buckets["1:0"].points,1)
		eq(buckets["0:0"].points[1].p,p1);eq(buckets["1:0"].points[1].p,p2)
	end)
	if not fs.isFile("src/shared/GameData/FireMap_saddle.luau") then return end
	local Map=require("../src/shared/Simulation/FireMap")
	local Pixels=require("../src/shared/Presentation/FirePixels")
	local Codec=require("../src/shared/Maps/MapCodec")
	local Inflate=require("../src/shared/Utilities/Inflate")
	local data=require("../src/shared/GameData/FireMap_saddle") ::any
	local refs=require("../src/shared/GameData/FireMapVectors_saddle") ::any
	local settings=require("../src/shared/GameData/FireRules") ::any
	local map=Map.new(data,function(encoded,size) return Inflate.raw(Codec.base64Decode(encoded),size) end,function(name) return require("../src/shared/GameData/"..name) end)
	test("scorch painting uses original roof IDs, applies town shade and leaves every other pixel clear",function()
		local root=refs.claims[1];assert(root)
		local patches={};local width=data.width*data.tileSize
		for _,sample in refs.claims do patches[sample.y*width+sample.x]=3 end
		local visited=0
		for _,b in Scorch.bucket(data.width,data.tileSize,patches) do
			local px,count=Scorch.paint(map,settings,b,function() return true end,function(x,y)
				local raw=map.original(math.floor(x*data.tileSize),math.floor(y*data.tileSize));return {raw[1]*.6,raw[2]*.6,raw[3]*.6}
			end)
			local side=data.tileSize*Scorch.TILE;local filled=0
			for i=0,side*side-1 do if buffer.readu8(px,i*4+3)>0 then filled+=1 end end
			eq(filled,count);eq(count,#b.points);visited+=count
			for _,p in b.points do
				local id=map.sourceId(p.x,p.y);local original=map.original(p.x,p.y)
				local edge=not map.roof(p.x+1,p.y) or not map.roof(p.x-1,p.y) or not map.roof(p.x,p.y+1) or not map.roof(p.x,p.y-1)
				local expected=Pixels.house(settings,id,original,3,edge)
				local at=((p.y-b.ty*side)*side+p.x-b.tx*side)*4
				for ch=0,2 do eq(buffer.readu8(px,at+ch),math.floor(expected[ch+1]*.6+.5)) end
			end
			local hidden,n=Scorch.paint(map,settings,b,function() return false end);eq(n,0);eq(buffer.tostring(hidden),string.rep("\0",buffer.len(hidden)))
		end
		local total=0;for _ in patches do total+=1 end;eq(visited,total)
	end)
end
