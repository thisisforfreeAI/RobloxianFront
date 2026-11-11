--!strict
return function(test:any,eq:any)
	local Map=require("../src/shared/Simulation/FireMap")
	test("fire map adapter resolves swapped source tiles and rejects boundaries and malformed storage",function()
		local chunks={atlas=buffer.create(32),index=buffer.create(8),cells=buffer.fromstring(string.char(1,1)),reserved=buffer.fromstring(string.char(1,0))}
		for i=0,7 do buffer.writeu8(chunks.atlas,i*4,i+1);buffer.writeu8(chunks.atlas,i*4+3,if i%2==0 then 224 else 0) end
		buffer.writeu8(chunks.index,0,2);buffer.writeu8(chunks.index,4,1)
		local data={width=2,height=1,tileSize=2,atlasWidth=4,atlasHeight=2,perRow=2,count=2,roofFrom=224,atlas="atlas",index="index",cells="cells",reserved="reserved"}
		local function decode(name) return chunks[name] end
		local m=Map.new(data,decode);eq(m.sourceId(0,0),2);eq(m.sourceId(2,0),0);eq(m.sourceId(1,1),7);eq(m.sourceId(3,1),5)
		eq(m.original(0,0)[1],3);eq(m.roof(0,0),true);eq(m.roof(1,0),false);eq(m.noFire(0),true);eq(m.noFire(1),false);eq(m.builtAt(1),true)
		for _,p in {{-1,0},{0,-1},{4,0},{0,2},{.5,0}} do eq(m.sourceId(p[1],p[2]),nil);eq(m.roof(p[1],p[2]),false) end
		buffer.writeu8(chunks.index,0,3);eq(m.sourceId(0,0),nil)
		chunks.atlas=buffer.create(31);eq(pcall(Map.new,data,decode),false)
	end)
	test("fire map atlas pages must be ordered, complete and match their declared sizes",function()
		local data={width=1,height=1,tileSize=1,atlasWidth=1,atlasHeight=1,perRow=1,count=1,roofFrom=224,
			atlasParts={{name="page",offset=0,bytes=4}},index="index",cells="cells",reserved="reserved"}
		local chunks={page=buffer.fromstring(string.char(1,2,3,224)),index=buffer.fromstring(string.char(1,0,0,0)),cells=buffer.fromstring(string.char(1)),reserved=buffer.fromstring(string.char(0))}
		local function decode(key) return chunks[key] end
		local function load(name) return {deflate=name} end
		eq(Map.new(data,decode,load).roof(0,0),true);eq(pcall(Map.new,data,decode),false)
		data.atlasParts[1].offset=1;eq(pcall(Map.new,data,decode,load),false)
		data.atlasParts[1].offset=0;data.atlasParts[1].bytes=3;eq(pcall(Map.new,data,decode,load),false)
	end)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/FireMap_saddle.luau") then return end
	local Codec=require("../src/shared/Maps/MapCodec")
	local Inflate=require("../src/shared/Utilities/Inflate")
	local data=require("../src/shared/GameData/FireMap_saddle") ::any
	local refs=require("../src/shared/GameData/FireMapVectors_saddle") ::any
	local m=Map.new(data,function(encoded,size) return Inflate.raw(Codec.base64Decode(encoded),size) end,function(name) return require("../src/shared/GameData/"..name) end)
	test("generated fire map matches original city coordinate and RGBA queries",function()
		local found=0
		for _,r in refs.refs do
			local id=m.sourceId(r.x,r.y);eq(id,if r.id<0 then nil else r.id)
			local rgba=m.original(r.x,r.y)
			if r.rgba then found+=1;assert(rgba);for ch=1,4 do eq(rgba[ch],r.rgba[ch]) end;eq(m.roof(r.x,r.y),r.rgba[4]>=data.roofFrom)
			else eq(rgba,nil);eq(m.roof(r.x,r.y),false) end
		end
		assert(found>0)
		local reserved=0;for cell=0,data.width*data.height-1 do if m.noFire(cell) then reserved+=1 end end
		eq(reserved,refs.reservedCells);for _,rig in refs.rigs do eq(m.noFire(rig.cell),true) end
	end)
	test("fire town membership matches original runtime radii, nearest-town ties and packed zero sentinel",function()
		assert(data.towns and #refs.townSamples==2000)
		local found=0;local empty=0
		for _,r in refs.townSamples do
			eq(m.townIndex(r.cell),if r.town>0 then r.town else nil)
			if r.town>0 then found+=1 else empty+=1 end
		end
		assert(found>0 and empty>0);eq(m.townIndex(-1),nil);eq(m.townIndex(data.width*data.height),nil);eq(m.townIndex(.5),nil)
	end)
	test("house claims through the real city adapter match original connected roof pixels",function()
		local House=require("../src/shared/Simulation/HouseFire")
		local settings=require("../src/shared/GameData/FireRules") ::any
		assert(#refs.claims>0)
		for _,r in refs.claims do
			local fire=House.new(settings,m);local found=fire.claim(r.x,r.y);assert(found);eq(#found,#r.ids)
			for i,p in found do
				local x,y=p%(data.width*data.tileSize),math.floor(p/(data.width*data.tileSize))
				eq(m.roof(x,y),true);eq(m.sourceId(x,y),r.ids[i])
			end
		end
	end)
end
