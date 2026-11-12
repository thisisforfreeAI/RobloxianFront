--!strict
return function(test:any,eq:any)
	local Lights=require("../src/shared/Presentation/NightLightPixels")
	local Noise=require("../src/shared/Presentation/GroundWetness")
	local Windows=require("../src/shared/Presentation/NightWindows")
	-- Synthetic settings exercise the renderer without distributing original extracted tables.
	local config={windows=.5,flickerSec=10,lamps={far=.8,glow=.2},roadGlow=.5,glow=.4}
	local function field(w:number,h:number,channel:number):buffer
		local out=buffer.create(w*h*4)
		for i=0,w*h-1 do buffer.writeu8(out,i*4+channel,255) end
		return out
	end
	local function alpha(b:buffer,index:number):number return buffer.readu8(b,index*4+3) end
	test("night windows are restricted to the material mask and selected occupancy",function()
		local f=buffer.create(16);buffer.writeu8(f,0,255);buffer.writeu8(f,8,255)
		local state=Lights.prepare(f,4,1,config,function(x) return if x<8 then .2 else .8 end)
		eq(state.count,1)
		local out=Lights.paint(state,config,0,1,1,function() return .9 end)
		assert(alpha(out,0)>0);eq(alpha(out,1),0);eq(alpha(out,2),0);eq(alpha(out,3),0)
	end)
	test("window flicker is stable within its staggered interval and advances in real time",function()
		local state=Lights.prepare(field(1,1,0),1,1,config,function() return .2 end)
		local calls=0
		local function flicker(x:number):number calls+=1;return if x<7 then .9 else .05 end
		local a=Lights.paint(state,config,0,1,1,flicker)
		local b=Lights.paint(state,config,1,1,1,flicker)
		eq(buffer.tostring(a),buffer.tostring(b));eq(calls,1);assert(alpha(a,0)>0)
		local c=Lights.paint(state,config,10,1,1,flicker)
		eq(alpha(c,0),0);eq(calls,2)
	end)
	test("near zoom adds lamp pools while highway glow remains visible from far away",function()
		local f=buffer.create(12);buffer.writeu8(f,1,255);buffer.writeu8(f,6,255);buffer.writeu8(f,11,255)
		local state=Lights.prepare(f,3,1,config,Noise.hash21)
		local far=Lights.paint(state,config,0,0,1,Noise.hash21)
		local near=Lights.paint(state,config,0,1,1,Noise.hash21)
		assert(alpha(far,0)>alpha(near,0) and alpha(near,0)>0)
		eq(alpha(far,1),0);assert(alpha(near,1)>0)
		eq(alpha(far,2),alpha(near,2));assert(alpha(far,2)>0)
	end)
	test("half resolution preserves average light energy without spreading into empty blocks",function()
		local f=buffer.create(8*4*4)
		for y=0,1 do for x=0,1 do buffer.writeu8(f,(y*8+x)*4+3,255) end end
		local state=Lights.prepare(f,8,4,config,Noise.hash21)
		local full=Lights.paint(state,config,0,1,1,Noise.hash21)
		local half=Lights.paint(state,config,0,1,2,Noise.hash21)
		eq(buffer.len(half),4*2*4)
		assert(math.abs(alpha(half,0)-alpha(full,0))<=2)
		for i=1,7 do eq(alpha(half,i),0) end
	end)
	test("light preparation and repaint yield cooperatively and handle empty maps",function()
		local checkpoints=0;local function yield() checkpoints+=1 end
		local state=Lights.prepare(buffer.create(128*128*4),128,128,config,Noise.hash21,yield)
		eq(state.count,0);assert(checkpoints>=2)
		eq(buffer.tostring(Lights.paint(state,config,0,0,1,Noise.hash21)),string.rep("\0",128*128*4))
		assert(not pcall(Lights.prepare,buffer.create(1),2,2,config,Noise.hash21))
	end)
	local fs=require("@lune/fs")
	test("window shapes use the same occupancy and clock as broad lights",function()
		local points={{0,0,0,0,0},{14,0,3,0,0}}
		local selected=Windows.prepare(points,config,function(x) return if x<8 then .2 else .8 end)
		eq(#selected,1)
		assert(Windows.on(selected[1],config,0,function(x) return if x<7 then .9 else .05 end))
		assert(not Windows.on(selected[1],config,10,function(x) return if x<7 then .9 else .05 end))
	end)
	test("window view selection clips offscreen lights, caps nearest and has deterministic ties",function()
		local points={}
		for i=1,Windows.MAX_VISIBLE+10 do points[i]={0,0,0,0,0} end
		points[#points+1]={14000,0,0,0,0}
		local selected=Windows.visible(Windows.prepare(points,config,function() return .2 end),14,0,0,10,10)
		eq(#selected,Windows.MAX_VISIBLE);eq(selected[1].item.id,1);eq(selected[#selected].item.id,Windows.MAX_VISIBLE)
		eq(Windows.fade(0,{nearFrom=5,nearTo=9}),0)
		eq(Windows.fade(7,{nearFrom=5,nearTo=9}),.5)
		eq(Windows.fade(12,{nearFrom=5,nearTo=9}),1)
	end)
	test("projected facades remain when occupancy or flicker switches their windows off",function()
		local points={{0,0,0,0,0,1,1},{14,0,3,0,0,2,0}}
		local dark=Windows.prepare(points,config,function() return .9 end)
		eq(#dark,2)
		for _,item in dark do assert(not Windows.on(item,config,0,function() return .9 end)) end
		local lit=Windows.prepare(points,config,function() return .2 end)
		eq(#lit,2);assert(Windows.on(lit[1],config,0,function() return .9 end))
		assert(not Windows.on(lit[2],config,0,function() return .9 end))
	end)
	test("bounded window selection keeps the same nearest visible fragments as a complete sort",function()
		local points={}
		for y=0,99 do for x=0,99 do table.insert(points,{x*14,y*14,x*3,y*3,0}) end end
		local items=Windows.prepare(points,config,function() return .2 end)
		local selected=Windows.visible(items,14,51,58,48,49)
		local expected={}
		for _,item in items do
			local x,y=(item.point[1]+6)/14,(item.point[2]+6)/14
			if math.abs(x-51)<=49 and math.abs(y-58)<=50 then table.insert(expected,{item=item,distance=(x-51)^2+(y-58)^2}) end
		end
		table.sort(expected,function(a,b) return if a.distance==b.distance then a.item.id<b.item.id else a.distance<b.distance end)
		eq(#selected,math.min(#expected,Windows.MAX_VISIBLE))
		for i,item in selected do eq(item.item.id,expected[i].item.id) end
	end)
	test("coarse window energy respects material coverage and fades out independently of city glow",function()
		local f=buffer.create(12);buffer.writeu8(f,0,255);buffer.writeu8(f,4,64);buffer.writeu8(f,11,255)
		local state=Lights.prepare(f,3,1,config,function() return .2 end)
		local full=Lights.paint(state,config,0,1,1,function() return .9 end)
		assert(alpha(full,0)>alpha(full,1)*3)
		local none=Lights.paint(state,config,0,1,1,function() return .9 end,nil,0)
		eq(alpha(none,0),0);eq(alpha(none,1),0);eq(alpha(none,2),alpha(full,2))
	end)
	if not fs.isFile("src/shared/GameData/WorldLook.luau") or not fs.isFile("src/shared/GameData/Daylight.luau") then return end
	local look=require("../src/shared/GameData/WorldLook") ::any
	local daylight=require("../src/shared/GameData/Daylight") ::any
	local Daylight=require("../src/shared/Presentation/Daylight")
	test("night emission compensation preserves warm channel ratios throughout the source day",function()
		for i=0,100 do
			local post=Daylight.postEffect(Daylight.sample(daylight,i/100))
			local adapted=Lights.compensate(post,look.nightLights.color)
			assert(adapted.brightness>0 and adapted.brightness<=1000)
			for ch=1,3 do
				assert(adapted.color[ch]>=0 and adapted.color[ch]<=1)
				local energy=adapted.color[ch]*adapted.brightness*post.tint[ch]*(1+post.contrast)
				assert(math.abs(energy-Lights.ENERGY*look.nightLights.color[ch])<1e-8)
			end
		end
	end)
	test("generated map light fields decode at their declared dimensions and remain sparse",function()
		local path="src/client/DevAssets/NightLights_saddle.luau"
		if not fs.isFile(path) then return end
		local data=require("../src/client/DevAssets/NightLights_saddle") ::any
		local Codec=require("../src/shared/Maps/MapCodec")
		local Inflate=require("../src/shared/Utilities/Inflate")
		local bytes=Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4)
		if data.windows and data.windows.mode=="facades" then
			for i=0,data.width*data.height-1 do eq(buffer.readu8(bytes,i*4),0) end
		end
		eq(data.width,data.mapWidth*data.scale);eq(data.height,data.mapHeight*data.scale)
		local state=Lights.prepare(bytes,data.width,data.height,look.nightLights,Noise.hash21)
		assert(state.count>0 and state.count<data.width*data.height/2)
		local full=Lights.paint(state,look.nightLights,12,1,1,Noise.hash21)
		eq(buffer.len(full),data.width*data.height*4)
		if data.windows then
			local detail=data.windows
			local atlas=Inflate.raw(Codec.base64Decode(detail.deflate),detail.width*detail.height*4)
			eq(buffer.len(atlas),detail.width*detail.height*4)
			assert(detail.width<=1024 and detail.height<=1024)
			assert(#detail.points>0)
			for _,p in detail.points do assert(p[5]*detail.slot*detail.slot<detail.width*detail.height) end
			if detail.half then
				local half=detail.half
				eq(half.width*2,detail.width);eq(half.height*2,detail.height)
				eq(buffer.len(Inflate.raw(Codec.base64Decode(half.deflate),half.width*half.height*4)),half.width*half.height*4)
			end
		end
	end)
end
