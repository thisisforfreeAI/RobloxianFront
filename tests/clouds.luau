--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/CloudLook.luau") then return end
	local Clouds=require("../src/shared/Presentation/CloudField")
	local Wet=require("../src/shared/Presentation/GroundWetness")
	local Screen=require("../src/shared/Presentation/ScreenLight")
	local config=require("../src/shared/GameData/CloudLook") ::any
	local refs=require("../src/shared/GameData/CloudVectors") ::any
	local function close(a:number,b:number,tolerance:number?) assert(math.abs(a-b)<(tolerance or 1e-9),tostring(a).." != "..tostring(b)) end
	test("cloud grid and noise agree with 720 evaluated original shader cases",function()
		local thick=0
		for _,v in refs.cases do
			close(Wet.valueNoise(v.x/config.scale,v.y/config.scale),v.noise,1e-7)
			eq(Clouds.density(config,v.x,v.y,v.time,Wet.valueNoise),v.density)
			if v.density>0 then thick+=1 end
		end
		assert(thick>0 and thick<#refs.cases)
	end)
	test("cloud palette and zoom/night opacity match original sky class",function()
		for _,v in refs.tones do
			local color,alpha=Clouds.tone(config,v.light,v.pixels)
			close(alpha,v.alpha);for i=1,3 do close(color[i],v.color[i]) end
		end
	end)
	test("painted cloud pixels match original sky projection, parallax and body opacity",function()
		local shown=0
		for _,v in refs.pixels do
			local rgba,count=Clouds.pixels(config,v.light,v.width,v.height,v.view,Wet.valueNoise)
			local expected=0
			for i,a in v.alpha do
				local alpha=math.floor(a*255+.5);eq(buffer.readu8(rgba,(i-1)*4+3),alpha)
				if alpha>0 then
					expected+=1
					for ch=0,2 do eq(buffer.readu8(rgba,(i-1)*4+ch),math.floor(v.color[ch+1]*255+.5)) end
				end
			end
			eq(count,expected);shown+=count
		end
		assert(shown>0)
	end)
	test("cloud shadows use the sun offset and fade at far zoom and full night",function()
		local c=table.clone(config)
		local light={night=0,golden=0,elevation=1,toward={0,-1},color={1,1,1},shadow={1,0}}
		local x,y=Clouds.offset(c,light);close(x,config.shadowReach);eq(y,0)
		x,y=Clouds.offset(c,{shadow={100,0}});close(x,config.shadowMax);eq(y,0)
		x,y=Clouds.offset(c,{shadow={0,0}});eq(x,0);eq(y,0)
		local look={cloud=c,wash={noon=0,golden=0,moon=0,shade=0},vignette=0,vignetteNight=0,vignetteFrom=.55}
		local view={cx=config.shadowReach*.5,cy=0,rx=1,ry=1,time=0,cellPixels=config.showPx}
		local function noise(px:number,_py:number):number return if px>=0 then 1 else 0 end
		local function alpha():number return buffer.readu8(Screen.pixels(look,light,1,1,view,noise,Clouds),3) end
		eq(alpha(),0) -- The cloud is overhead to the left; its shadow has moved with the sun.
		view.cx=config.shadowReach*1.5;assert(alpha()>0)
		view.cellPixels=config.hidePx;eq(alpha(),0)
		view.cellPixels=config.showPx;light.night=1;eq(alpha(),0)
	end)
	test("drifting clouds stay in world coordinates and cache repeated cells at near zoom",function()
		local light=refs.tones[1].light
		local view={cx=100,cy=100,rx=3,ry=2,time=20,cellPixels=20}
		local calls=0
		local function noise(x:number,y:number):number calls+=1;return Wet.valueNoise(x,y) end
		local a=Clouds.pixels(config,light,128,80,view,noise)
		assert(calls<128*80,"near cloud texels should share integer-cell density work")
		local shifted=table.clone(view);shifted.time+=10;shifted.cx-=10*config.dx;shifted.cy-=10*config.dy
		local b=Clouds.pixels(config,light,128,80,shifted,Wet.valueNoise)
		eq(buffer.tostring(a),buffer.tostring(b))
		view.cellPixels=config.hidePx
		local empty,count=Clouds.pixels(config,light,16,10,view,Wet.valueNoise)
		eq(count,0);eq(buffer.tostring(empty),string.rep("\0",16*10*4))
	end)
	test("map-locked cloud sampling preserves overlapping world pixels during camera pans",function()
		local view={cx=0,cy=0,rx=14,ry=10,time=0,cellPixels=10}
		local moved=table.clone(view);moved.cx=2
		local function noise(x:number,_y:number):number return if x>=0 then 1 else 0 end
		local a,count=Clouds.pixels(config,refs.tones[1].light,28,20,view,noise,0)
		local b=Clouds.pixels(config,refs.tones[1].light,28,20,moved,noise,0)
		assert(count>0 and count<28*20)
		for y=0,19 do for x=0,25 do
			eq(buffer.readu32(a,(y*28+x+2)*4),buffer.readu32(b,(y*28+x)*4))
		end end
	end)
	test("cached clouds reproject with camera translation/zoom every frame and only wind moves their world position",function()
		local painted={cx=100,cy=80,rx=50,ry=40,time=10}
		for _,view in {{cx=100,cy=80,rx=20,ry=15,time=10},{cx=115,cy=74,rx=20,ry=15,time=10},{cx=95,cy=85,rx=30,ry=20,time=10.12}} do
			local p=Clouds.project(painted,view,config);assert(p.covered)
			for _,anchor in {{90,75},{110,90}} do
				local u=(anchor[1]-painted.cx)/(painted.rx*2)+.5
				local v=(anchor[2]-painted.cy)/(painted.ry*2)+.5
				local sx,sy=p.x+(u-.5)*p.width,p.y+(v-.5)*p.height
				close(view.cx+(sx-.5)*view.rx*2,anchor[1]-(view.time-painted.time)*config.dx)
				close(view.cy+(sy-.5)*view.ry*2,anchor[2]-(view.time-painted.time)*config.dy)
			end
		end
	end)
	test("cloud cache edges stay hidden when a teleport or large zoom outruns padded coverage",function()
		local painted={cx=100,cy=80,rx=35,ry=25,time=10}
		assert(not Clouds.project(painted,{cx=200,cy=80,rx=20,ry=15,time=10},config).covered)
		assert(not Clouds.project(painted,{cx=100,cy=80,rx=70,ry=50,time=10},config).covered)
	end)
end
