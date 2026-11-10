--!strict
return function(test: any,eq: any)
	local Visibility = require("../src/shared/Simulation/Visibility")
	local Pixels = require("../src/shared/Presentation/FogPixels")
	test("building ray walk sees the wall but hides ground behind it",function()
		local mask=buffer.create(100)
		for y=0,9 do buffer.writeu8(mask,y*10+5,1) end
		local v=Visibility.new(10,10,mask)
		assert(v.clear(2.5,5.5,5.5,5.5));assert(not v.clear(2.5,5.5,7.5,5.5))
		assert(v.clear(5.5,5.5,7.5,5.5));eq(v.count,10)
		assert(v.clear(2.5,2.5,2.5,8.5))
	end)
	test("track exemption and empty blocker fast path preserve clear sight",function()
		local mask=buffer.create(100);buffer.writeu8(mask,55,1)
		local v=Visibility.new(10,10,mask,function() return 1 end)
		eq(v.count,0);assert(v.clear(2.5,5.5,8.5,5.5))
		assert(not Visibility.new(10,10,mask).clear(2.5,5.5,8.5,5.5))
	end)
	test("fog feather is smooth and never mutates the detection mask",function()
		local mask=buffer.create(40*10)
		for y=0,9 do for x=0,19 do buffer.writeu8(mask,y*40+x,1) end end
		local original=buffer.tostring(mask)
		local px=Pixels.soften(mask,40,10,150)
		eq(buffer.tostring(mask),original)
		eq(buffer.readu8(px,(5*40+2)*4+3),0)
		eq(buffer.readu8(px,(5*40+37)*4+3),150)
		local prior=0
		for x=10,29 do local a=buffer.readu8(px,(5*40+x)*4+3);assert(a>=prior);prior=a end
		assert(buffer.readu8(px,(5*40+19)*4+3)>0 and buffer.readu8(px,(5*40+20)*4+3)<150)
	end)
	test("source fog colours distinguish unexplored terrain and explored memory",function()
		local mask,terrain,seen=buffer.create(400),buffer.create(400),buffer.create(400)
		local profile={rgb={60,40,20},alpha=0.8,chart={plains={60,40,20}},seen={rgb={20,40,60},alpha=0.5},featherCells=2.4}
		local first=Pixels.colour(mask,terrain,seen,{"plains"},profile,40,10)
		local at=(5*40+20)*4
		eq(buffer.readu8(first,at+3),204)
		assert(buffer.readu8(first,at)>buffer.readu8(first,at+2),"unexplored fog should retain its warm chart tone")
		for i=0,399 do buffer.writeu8(mask,i,1) end
		local open=Pixels.colour(mask,terrain,seen,{"plains"},profile,40,10)
		eq(buffer.readu8(open,at+3),0);eq(buffer.readu8(seen,220),1)
		for i=0,399 do buffer.writeu8(mask,i,0) end
		local memory=Pixels.colour(mask,terrain,seen,{"plains"},profile,40,10)
		eq(buffer.readu8(memory,at+3),128)
		assert(buffer.readu8(memory,at+2)>buffer.readu8(memory,at),"explored fog should retain its separate cool tone")
		eq(buffer.readu8(mask,220),0,"display must not alter detection")
	end)
	test("incremental fog recolouring matches a full rebuild after movement and exploration",function()
		local mask,terrain,seen=buffer.create(900),buffer.create(900),buffer.create(900)
		local p={rgb={60,40,20},alpha=0.8,chart={},seen={rgb={20,40,60},alpha=0.5},featherCells=2.4}
		local cache={}
		Pixels.colour(mask,terrain,seen,{"plains"},p,30,30,cache)
		for _,cell in {450,451,452,899,0} do
			buffer.writeu8(mask,cell,1)
			local cached=Pixels.colour(mask,terrain,seen,{"plains"},p,30,30,cache)
			local full=Pixels.colour(mask,terrain,seen,{"plains"},p,30,30)
			eq(buffer.tostring(cached),buffer.tostring(full))
		end
	end)
end
