--!strict
return function(test:any,eq:any)
	local Pixels=require("../src/shared/Presentation/StructurePixels")
	local Rng=require("../src/shared/Utilities/Rng")
	local build={slabShare=.25,pourSteps=2,steps=4,ground=0,band=.25,bandMin=1,wallDrop=2,poleEvery=2,scaffoldAlpha=.5,
		slab={90,80,70},slabWet={50,45,40},wall={140,135,130},pole={30,35,40},scaffold={100,110,120}}
	local function source(f:number):any
		local n=f/2;local raw=buffer.create(f*f*10+n*n*3)
		for y=0,f-1 do for x=0,f-1 do
			local at=(y*f+x)*4;buffer.writeu8(raw,at,200);buffer.writeu8(raw,at+1,180);buffer.writeu8(raw,at+2,160)
			buffer.writeu8(raw,at+3,if x>0 and y>0 and x<f-1 and y<f-1 then 255 else 0)
		end end
		for y=0,n-1 do for x=0,n-1 do local p=y*n+x;buffer.writeu8(raw,f*f*8+p,math.floor(x/n*8));buffer.writeu8(raw,f*f*8+n*n*2+p,1) end end
		for y=2,f-3 do for x=2,f-3 do buffer.writeu8(raw,f*f*8+n*n*3+y*f+x,255);buffer.writeu8(raw,f*f*9+n*n*3+y*f+x,255) end end
		return Pixels.prepare(raw,f,n,8)
	end
	local function rgb(bufferValue:buffer,f:number,x:number,y:number):string
		local at=(y*f+x)*4;return `{buffer.readu8(bufferValue,at)},{buffer.readu8(bufferValue,at+1)},{buffer.readu8(bufferValue,at+2)}`
	end
	test("construction quantizes foundation and height steps at their shared boundary",function()
		eq(Pixels.buildStep(build,0),0);eq(Pixels.buildStep(build,.249),1);eq(Pixels.buildStep(build,.25),2);eq(Pixels.buildStep(build,1),5)
	end)
	test("foundation pouring reverses with site id; walls and scaffolds follow height rather than image rows",function()
		local s=source(8);local a=Pixels.construction(s,build,0,0,{1,1,1});local b=Pixels.construction(s,build,0,3,{1,1,1})
		assert(buffer.readu8(a,3)>0);eq(buffer.readu8(b,3),0)
		local raised=Pixels.construction(s,build,2,0,{1,1,1})
		eq(rgb(raised,8,6,4),"140,135,130")
		assert(rgb(raised,8,2,4)~="140,135,130","lower roof pixels must be revealed/scaffolded")
	end)
	test("construction owner paint multiplies only paint pixels and preserves source buffers",function()
		local s=source(8);local at=(2*8+2)*4+s.paint
		for c=0,3 do buffer.writeu8(s.raw,at+c,255) end
		local before=buffer.tostring(s.raw);local full=table.clone(build);full.scaffoldAlpha=0
		local a=Pixels.construction(s,full,5,0,{1,.5,.25})
		eq(rgb(a,8,2,2),"255,128,64");eq(rgb(a,8,3,2),"200,180,160");eq(buffer.tostring(s.raw),before)
	end)
	test("construction cooperative output matches synchronous and propagates cancellation",function()
		local s=source(24);local expected=Pixels.construction(s,build,3,7,{.5,1,.5});local count=0
		local thread=coroutine.create(function() return Pixels.construction(s,build,3,7,{.5,1,.5},function() count+=1;coroutine.yield() end) end)
		local actual;repeat local ok,value=coroutine.resume(thread);assert(ok,tostring(value));actual=value until coroutine.status(thread)=="dead"
		assert(count>=24);eq(buffer.tostring(actual),buffer.tostring(expected))
		assert(not pcall(Pixels.construction,s,build,3,7,{1,1,1},function() error("cancel") end))
	end)
	test("damage severity has separate entry and repair thresholds",function()
		local c={below={.8,.55,.3},back=.05}
		eq(Pixels.damageStage(c,0,79,100),1);eq(Pixels.damageStage(c,1,82,100),1);eq(Pixels.damageStage(c,1,86,100),0)
		eq(Pixels.damageStage(c,0,20,100),3);eq(Pixels.damageStage(c,3,61,100),1);eq(Pixels.damageStage(c,1,100,100),0)
	end)
	local damage={px=3,sootCount={1,2,3},charCount={1,1,2},holeCount={1,2,3},soot={.3,.6},char={.2,.4},hole={.1,.2},rubble={1,3},rubbleTo=2,solid=.5,wobble=.4,
		dither={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5},colours={soot={12,13,14},sootAlpha=.5,char={18,18,18},hole={5,6,7},rim={110,100,90},rubble={130,120,110}},
		fire={spots={["3"]=3},defenceSpots=2},cave={count=1,size={.8,1.2},wobble=.4,heap=.7,beams=2,spill=8,spillTo=1.5,
			heapInks={{90,80,70},{120,110,100},{100,90,80}},lit={140,130,120},shade={3,4,5},beam={60,50,40}}}
	test("damage raster is deterministic, clipped to building masks and changes with severity and id",function()
		local s=source(24);local before=buffer.tostring(s.raw);local helpers={rng=Rng.new,imul=Rng.imul}
		local a=Pixels.damage(s,damage,3,47,3,false,helpers);local b=Pixels.damage(s,damage,3,47,3,false,helpers)
		eq(buffer.tostring(a),buffer.tostring(b));assert(buffer.tostring(a)~=buffer.tostring(Pixels.damage(s,damage,1,47,3,false,helpers)))
		assert(buffer.tostring(a)~=buffer.tostring(Pixels.damage(s,damage,3,48,3,false,helpers)))
		for i=0,24*24-1 do if buffer.readu8(s.raw,i*4+3)==0 then eq(buffer.readu8(a,i*4+3),0) end end
		eq(buffer.tostring(s.raw),before)
	end)
	test("damage raster yields without changing deterministic geometry",function()
		local s=source(24);local h={rng=Rng.new,imul=Rng.imul};local expected=Pixels.damage(s,damage,3,47,3,true,h);local count=0
		local thread=coroutine.create(function() return Pixels.damage(s,damage,3,47,3,true,h,function() count+=1;coroutine.yield() end) end)
		local actual;repeat local ok,value=coroutine.resume(thread);assert(ok,tostring(value));actual=value until coroutine.status(thread)=="dead"
		assert(count>24);eq(buffer.tostring(actual),buffer.tostring(expected))
	end)
end
