--!strict
return function(test:any,eq:any)
	local Inflate=require("../src/shared/Utilities/Inflate")
	test("cooperative inflate yields at output checkpoints without exposing a partial result",function()
		local size=12000;local src=buffer.create(size+5);buffer.writeu8(src,0,1);buffer.writeu16(src,1,size);buffer.writeu16(src,3,65535-size)
		for i=0,size-1 do buffer.writeu8(src,5+i,i%251) end
		local progress={};local thread=coroutine.create(function() return Inflate.raw(src,size,function(n) table.insert(progress,n);coroutine.yield(n) end) end)
		local output
		while coroutine.status(thread)~="dead" do local ok,value=coroutine.resume(thread);assert(ok,value);if coroutine.status(thread)=="dead" then output=value else eq(typeof(value),"number") end end
		eq(#progress,2);eq(progress[1],4096);eq(progress[2],8192)
		assert(buffer.tostring(output)==buffer.tostring(Inflate.raw(src,size)))
	end)
	test("cooperative inflate propagates cancellation and retains strict size validation",function()
		local size=5000;local src=buffer.create(size+5);buffer.writeu8(src,0,1);buffer.writeu16(src,1,size);buffer.writeu16(src,3,65535-size)
		local ok,err=pcall(Inflate.raw,src,size,function() error("cancelled decode") end);assert(not ok and string.find(tostring(err),"cancelled decode",1,true))
		assert(not pcall(Inflate.raw,src,size+1,function() end))
	end)
	local fs=require("@lune/fs");if not fs.isFile("src/client/DevAssets/City_saddle_0_0.luau") then return end
	test("cooperative Huffman and backreference decoding matches an actual town source exactly",function()
		local luau=require("@lune/luau");local Codec=require("../src/shared/Maps/MapCodec")
		local source=luau.load(fs.readFile("src/client/DevAssets/City_saddle_0_0.luau"))();local packed=Codec.base64Decode(source.deflate);local size=source.width*source.height*4
		local count=0;local thread=coroutine.create(function() return Inflate.raw(packed,size,function() count+=1;coroutine.yield() end) end)
		local output;repeat local ok,value=coroutine.resume(thread);assert(ok,value);output=value until coroutine.status(thread)=="dead"
		assert(count>1);assert(buffer.tostring(output)==buffer.tostring(Inflate.raw(packed,size)))
	end)
end
