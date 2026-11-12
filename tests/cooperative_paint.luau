--!strict
return function(test:any,eq:any)
	local Raster=require("../src/shared/Presentation/ForestRaster")
	local Scars=require("../src/shared/Presentation/GroundScorchPixels")
	local Patch=require("../src/shared/Presentation/TownPatch")
	local Pixels=require("../src/shared/Presentation/ImagePixels")
	local function run(fn:any):any
		local calls=0;local resumes=0
		local thread=coroutine.create(function() return fn(function() calls+=1;if calls%3==0 then coroutine.yield() end end) end)
		local result
		repeat local values=table.pack(coroutine.resume(thread));assert(values[1],tostring(values[2]));result=values[2];resumes+=1;assert(resumes<10000) until coroutine.status(thread)=="dead"
		assert(calls>0 and resumes>1,"work must actually yield");return result
	end
	local function pattern(w,h):buffer
		local b=buffer.create(w*h*4);for i=0,w*h-1 do buffer.writeu32(b,i*4,bit32.bor(bit32.lshift((i*31)%256,24),(i*193)%16777216)) end;return b
	end
	test("cooperative standing fallen stump char and shadow raster matches synchronous pixels without mutating its base",function()
		local source=pattern(4,16);local frame={offset=0,w=4,h=4}
		local family={standing=frame,fallen={offset=64,w=4,h=4},stump={offset=128,w=4,h=4},burnt={offset=192,w=4,h=4},shadowX=1,shadowY=1}
		local trees={};for i=1,4 do trees[i]={key=i,x=2+i*2,y=3+i,drawX=2+i*4,drawY=4+i*2,sprite=1} end
		local map={data={tileSize=2,shadow={alpha=.34,dx=.2,dy=.3},fallenAnchor=.5,charColors={0x808080,0x404040},families={family}},
			inWindow=function() return trees end,pixels=function() return source end}
		local fates={[1]={kind="burning",char=1},[2]={kind="fallen",rot=.7,char=0},[3]={kind="stump"},[4]={kind="burnt"}}
		local base=pattern(24,24);local prior=buffer.tostring(base)
		local expected=Raster.paint(map,base,0,0,12,12,fates)
		local actual=run(function(checkpoint) return Raster.paint(map,base,0,0,12,12,fates,checkpoint) end)
		assert(buffer.tostring(actual)==buffer.tostring(expected));assert(buffer.tostring(base)==prior)
		assert(not pcall(Raster.paint,map,base,0,0,12,12,fates,function() error("cancelled") end));assert(buffer.tostring(base)==prior)
	end)
	test("cooperative downsample and overview preserve exact alpha rounding and odd-edge behavior",function()
		local source=pattern(17,19);local expected,w,h=Pixels.half(source,17,19)
		local actual=run(function(checkpoint) local out,ow,oh=Pixels.half(source,17,19,checkpoint);eq(ow,w);eq(oh,h);return out end)
		assert(buffer.tostring(actual)==buffer.tostring(expected))
		local large=pattern(28,28);expected=Raster.overview(large,28,28,2,1)
		actual=run(function(checkpoint) return Raster.overview(large,28,28,2,1,checkpoint) end)
		assert(buffer.tostring(actual)==buffer.tostring(expected))
	end)
	test("cooperative ground scars preserve roof exclusion tones and transparency exactly",function()
		local source=pattern(28,28);local a,b=buffer.create(buffer.len(source)),buffer.create(buffer.len(source));buffer.copy(a,0,source);buffer.copy(b,0,source)
		local cells={[0]=255,[1]=180,[2]=80,[3]=220};local tones={[0]=0,[1]=1,[2]=0,[3]=1}
		local config={color="#11171f",darken=.6,palette={{color="#11171f"},{color="#805020"}}}
		local function roof(x,y) return x%5==0 or y%7==0 end
		Scars.apply(a,0,0,2,2,14,2,cells,config,roof,tones)
		run(function(checkpoint) Scars.apply(b,0,0,2,2,14,2,cells,config,roof,tones,checkpoint);return b end)
		assert(buffer.tostring(a)==buffer.tostring(b))
	end)
	test("cooperative sparse lighting validates before mutation and matches reversible synchronous patches",function()
		local source=pattern(64,64);local delta=buffer.create(8+buffer.len(source));buffer.writeu32(delta,0,0);buffer.writeu32(delta,4,4096)
		for i=0,4095 do buffer.writeu32(delta,8+i*4,i*13) end
		local a,b=buffer.create(buffer.len(source)),buffer.create(buffer.len(source));buffer.copy(a,0,source);buffer.copy(b,0,source)
		Patch.apply(a,delta);run(function(checkpoint) Patch.apply(b,delta,checkpoint);return b end);assert(buffer.tostring(a)==buffer.tostring(b))
		run(function(checkpoint) Patch.apply(b,delta,checkpoint);return b end);assert(buffer.tostring(b)==buffer.tostring(source))
		local bad=buffer.create(20);buffer.writeu32(bad,4,1);buffer.writeu32(bad,12,0);buffer.writeu32(bad,16,1)
		local original=buffer.tostring(b);assert(not pcall(Patch.apply,b,bad,function() end));assert(buffer.tostring(b)==original)
	end)
end
