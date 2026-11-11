--!strict
return function(test:any,eq:any)
	local Pixels=require("../src/shared/Presentation/GroundScorchPixels")
	test("urban scorch uses source tint while preserving roof pixels and coverage alpha",function()
		local px=buffer.create(4*4*4);for i=0,15 do buffer.writeu8(px,i*4,100);buffer.writeu8(px,i*4+1,120);buffer.writeu8(px,i*4+2,140);buffer.writeu8(px,i*4+3,128) end
		buffer.writeu8(px,15*4+3,0)
		Pixels.apply(px,0,0,2,2,2,2,{[0]=255,[3]=255},{color="#000000",darken=.5},function(x,y) return x==0 and y==0 end)
		eq(buffer.readu8(px,0),100);eq(buffer.readu8(px,4),50);eq(buffer.readu8(px,4+3),128)
		eq(buffer.readu8(px,2*4),100);eq(buffer.readu8(px,15*4),100);eq(buffer.readu8(px,15*4+3),0)
	end)
	test("urban scorch clips by world cell coordinates and strength across chunk boundaries",function()
		local function tile()
			local px=buffer.create(4*4*4);for i=0,15 do buffer.writeu8(px,i*4,200);buffer.writeu8(px,i*4+3,255) end;return px
		end
		local a,b=tile(),tile();local cells={[1]=128,[2]=255};local config={color="#000000",darken=1};local roof=function() return false end
		Pixels.apply(a,0,0,2,2,2,4,cells,config,roof);Pixels.apply(b,2,0,2,2,2,4,cells,config,roof)
		eq(buffer.readu8(a,0),200);eq(buffer.readu8(a,2*4),math.floor(200*(1-128/255)+.5));eq(buffer.readu8(b,0),0);eq(buffer.readu8(b,2*4),200)
		assert(not pcall(Pixels.apply,buffer.create(1),0,0,2,2,2,4,cells,config,roof))
	end)
end
