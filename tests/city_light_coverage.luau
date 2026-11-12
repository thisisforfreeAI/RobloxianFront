--!strict
return function(test:any,eq:any)
	local Pixels=require("../src/shared/Presentation/NightLightPixels")
	test("fine window coverage suppresses only matching coarse windows while retaining distant city and road lights",function()
		local fields=buffer.create(8);buffer.writeu8(fields,0,255);buffer.writeu8(fields,4,255)
		local config={windows=1,flickerSec=10,lamps={far=1,glow=1},roadGlow=1,glow=1}
		local hash=function() return .2 end;local state=Pixels.prepare(fields,2,1,config,hash)
		local out=Pixels.paint(state,config,0,1,1,hash,nil,function(x) return if x==0 then 0 else 1 end)
		eq(buffer.readu8(out,3),0);assert(buffer.readu8(out,7)>0)
		buffer.writeu8(fields,1,255);out=Pixels.paint(state,config,0,1,1,hash,nil,function() return 0 end)
		assert(buffer.readu8(out,3)>0);eq(buffer.readu8(out,7),0)
	end)
end
