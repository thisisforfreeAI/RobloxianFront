--!strict
return function(test:any,eq:any)
	local Lods=require("../src/shared/Presentation/TownLods")
	test("town LOD source signatures match standard Adler and stale profiles never inflate",function()
		eq(Lods.signature(""),1);eq(Lods.signature("Wikipedia"),0x11e60398)
		local data={format=2,stride=2,baseFrame=1,width=2,height=2,sourceHash=12,deflate="pixels",patches={[1]={sourceHash=34,bytes=0,deflate=""}}};local calls=0
		local function inflate() calls+=1;return buffer.create(16) end
		assert(Lods.decode(data,2,1,4,4,12,34,inflate));eq(calls,1)
		for _,key in {"format","stride","width","height","sourceHash"} do
			local bad=table.clone(data);bad[key]+=1;eq(Lods.decode(bad,2,1,4,4,12,34,inflate),nil)
		end;eq(calls,1)
		eq(Lods.decode(data,2,2,4,4,12,34,inflate),nil);eq(Lods.decode(data,2,1,4,4,12,35,inflate),nil)
		assert(not pcall(Lods.decode,data,2,1,4,4,12,34,function() return buffer.create(1) end))
	end)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local path="src/client/DevAssets/City_saddle_0_0"
	if not fs.isFile(path.."_Mip2.luau") then return end
	local Inflate=require("../src/shared/Utilities/Inflate");local Codec=require("../src/shared/Maps/MapCodec")
	local Patch=require("../src/shared/Presentation/TownPatch");local Pixels=require("../src/shared/Presentation/ImagePixels")
	test("generated original town LOD pixels match runtime lighting and alpha-weighted reduction byte for byte",function()
		local function read(name) return luau.load(fs.readFile(name..".luau"))() end
		local source=read(path);local two,four=read(path.."_Mip2"),read(path.."_Mip4")
		local base=Inflate.raw(Codec.base64Decode(source.deflate),source.width*source.height*4);local sourceHash=Lods.signature(source.deflate)
		for frame in two.patches do
			local patch=if frame==two.baseFrame then {bytes=0,deflate=""} else read(path.."_Light"..frame)
			local original=buffer.create(buffer.len(base));buffer.copy(original,0,base)
			Patch.apply(original,if patch.bytes==0 then buffer.create(0) else Inflate.raw(Codec.base64Decode(patch.deflate),patch.bytes))
			local half,w,h=Pixels.half(original,source.width,source.height);local quarter=Pixels.half(half,w,h)
			for stride,expected in {[2]=half,[4]=quarter} do
				local data=if stride==2 then two else four
				local actual=Lods.decode(data,stride,frame,source.width,source.height,sourceHash,Lods.signature(patch.deflate or ""),function(text,bytes) return Inflate.raw(Codec.base64Decode(text),bytes) end,two.baseFrame)
				assert(actual);assert(buffer.tostring(actual)==buffer.tostring(expected),"generated LOD RGBA differs from runtime reduction")
			end
		end
	end)
end
