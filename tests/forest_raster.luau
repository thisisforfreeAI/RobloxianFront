--!strict
return function(test:any,eq:any)
	local Raster=require("../src/shared/Presentation/ForestRaster")
	local Map=require("../src/shared/Simulation/ForestMap")
	test("forest replacement exposes the underlying ground, preserves overlapping crowns and restores on regrowth",function()
		local source=buffer.fromstring(string.char(0,200,0,255,0,0,0,0,100,40,10,255))
		local family={standing={offset=0,w=1,h=1},fallen={offset=8,w=1,h=1},stump={offset=8,w=1,h=1},burnt={offset=4,w=1,h=1},shadowX=0,shadowY=0}
		local t={key=1,x=1.5,y=1.5,drawX=1,drawY=1,sprite=1}
		local data={tileSize=1,shadow={dx=0,dy=0,alpha=0},fallenAnchor=.5,charColors={0x808080},families={family}}
		local map={data=data,inWindow=function() return {t} end,pixels=function() return source end}
		local base=buffer.create(16);for at=0,12,4 do buffer.writeu8(base,at,20);buffer.writeu8(base,at+3,255) end
		local original=buffer.tostring(base)
		local intact=Raster.paint(map,base,0,0,2,2,{});eq(buffer.readu8(intact,13),200)
		local burnt=Raster.paint(map,base,0,0,2,2,{[1]={kind="burnt"}});eq(buffer.readu8(burnt,12),20);eq(buffer.readu8(burnt,13),0)
		local char=Raster.paint(map,base,0,0,2,2,{[1]={kind="burning",char=0}});eq(buffer.readu8(char,13),100)
		eq(buffer.tostring(base),original);eq(buffer.tostring(Raster.paint(map,base,0,0,2,2,{})),buffer.tostring(intact))
		map.inWindow=function() return {t,{key=2,x=1.5,y=1.5,drawX=1,drawY=1,sprite=1}} end
		eq(buffer.readu8(Raster.paint(map,base,0,0,2,2,{[1]={kind="burnt"}}),13),200)
	end)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/Forest_saddle.luau") then return end
	local Codec=require("../src/shared/Maps/MapCodec");local Inflate=require("../src/shared/Utilities/Inflate")
	local data=require("../src/shared/GameData/Forest_saddle") ::any;local refs=require("../src/shared/GameData/Forest_saddleVectors") ::any
	local loads=0;local function decode(encoded,bytes) return Inflate.raw(Codec.base64Decode(encoded),bytes) end
	local map=Map.new(data,decode,function(name) loads+=1;return require("../src/shared/GameData/"..name) end)
	test("forest map retains source quantized roots, keys, sizes and original ordered cell queries without decoding art",function()
		eq(#map.trees,refs.count);eq(loads,0)
		for _,r in refs.samples do for _,key in {"key","x","y","size","cell"} do eq(map.trees[r.index][key],r[key]) end end
		local target=map.trees[500];local list={};map.forNear(target.x,target.y,1,function(t,d) assert(d<=1);table.insert(list,t) end);assert(#list>0)
		for i=2,#list do assert(list[i].cell>list[i-1].cell or list[i].cell==list[i-1].cell and list[i].index>list[i-1].index) end
		local fates={};eq(map.fuelAt(target.cell,fates),true);for _,t in map.cells[target.cell] do fates[t.key]={kind="burnt"} end;eq(map.fuelAt(target.cell,fates),false)
	end)
	test("forest sprite poses match all original standing, charred, fallen, stump and burnt cases",function()
		for _,r in refs.poses do
			local kind=if r.fate and r.fate.kind~="burning" then r.fate.kind else "standing"
			local f=refs.settings.frames[kind][r.tile];local pose=Raster.pose({w=f[3],h=f[4]},137,211,1.25,r.fate,refs.settings)
			for _,key in {"x","y","anchorX","anchorY","rotation"} do eq(pose[key],r.leaf[key]) end
			local color=r.leaf.color;local rgb=bit32.extract(color,0,8)*65536+bit32.extract(color,8,8)*256+bit32.extract(color,16,8);eq(pose.tint,rgb)
			if r.shadow.x then eq(pose.shadowX,r.shadow.x);eq(pose.shadowY,r.shadow.y) end
		end
	end)
	test("forest firebreaks match the original game's complete Saddle rank-filtered raster",function()
		local roads=require("../src/shared/GameData/Maps/Saddle") ::any
		local ref=refs.settings.firebreaks;assert(ref);local expected=decode(ref.deflate,ref.width*ref.height)
		eq(buffer.tostring(Map.firebreaks(ref.width,ref.height,roads.roads,ref.rank)),buffer.tostring(expected))
	end)
	test("dynamic forest composition preserves the existing tree bake within declared CPU alpha precision",function()
		for _,pos in {{0,0},{128,64},{192,64},{192,128},{320,192}} do
			local name="City_saddle_"..pos[1].."_"..pos[2]
			local old=require("../src/client/DevAssets/"..name);local bare=require("../src/client/DevAssets/"..name.."_Bare")
			local px=Raster.paint(map,decode(bare.deflate,bare.width*bare.height*4),pos[1],pos[2],bare.width/14,bare.height/14,{})
			local expected=decode(old.deflate,old.width*old.height*4)
			for at=0,buffer.len(px)-1 do assert(math.abs(buffer.readu8(px,at)-buffer.readu8(expected,at))<=2,"CPU alpha composition drift") end
		end
		local before=loads;map.pixels();eq(loads,before)
	end)
end
