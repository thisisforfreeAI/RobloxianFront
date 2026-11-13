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
	local Codec=require("../src/shared/Maps/MapCodec")
	test("base64 and source signatures can suspend and resume without changing bytes or checksums",function()
		local encoded=string.rep("AAECAwQF",5000).."YQ==";local expected=Codec.base64Decode(encoded);local hash=Lods.signature(encoded);local calls=0
		local thread=coroutine.create(function()
			local function checkpoint() calls+=1;coroutine.yield() end
			return Codec.base64Decode(encoded,checkpoint),Lods.signature(encoded,checkpoint)
		end)
		local actual,signature
		repeat local ok,a,b=coroutine.resume(thread);assert(ok,a);actual,signature=a,b until coroutine.status(thread)=="dead"
		eq(buffer.tostring(actual),buffer.tostring(expected));eq(signature,hash);assert(calls>10)
	end)
	test("LOD patch validation and XOR application yield without exposing incomplete results",function()
		local patch=buffer.create(8+4096*4);buffer.writeu32(patch,4,4096);for i=8,buffer.len(patch)-4,4 do buffer.writeu32(patch,i,0x99887766) end
		local data={format=2,stride=2,baseFrame=1,width=64,height=64,sourceHash=1,deflate="base",patches={[1]={sourceHash=1,bytes=buffer.len(patch),deflate="patch"}}}
		local calls=0;local thread=coroutine.create(function()
			return Lods.decode(data,2,1,128,128,1,1,function(name,size) return if name=="patch" then patch else buffer.create(size) end,1,function() calls+=1;coroutine.yield() end)
		end)
		local result;repeat local ok,value=coroutine.resume(thread);assert(ok,value);result=value until coroutine.status(thread)=="dead"
		assert(calls>=5);eq(buffer.readu32(result,0),0x99887766);eq(buffer.readu32(result,buffer.len(result)-4),0x99887766)
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
