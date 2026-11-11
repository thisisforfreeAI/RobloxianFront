--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/PowerLineVectors.luau") then return end
	local Power=require("../src/shared/Presentation/PowerLines")
	local refs=require("../src/shared/GameData/PowerLineVectors") ::any
	local data=require("../src/client/DevAssets/OrigPowerLines_saddle") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("power wires move only in rain or storm and keep their attachments at every detail level",function()
		for _,weather in {"clear","fog","sandstorm",""} do eq(Power.motion(weather),0) end
		for _,weather in {"downpour","rain","storm"} do eq(Power.motion(weather),1) end
		local moving=false
		for _,link in refs.links do
			local still=Power.curves(refs,link,0,16,0)
			local later=Power.curves(refs,link,1,16,0)
			local windy=Power.curves(refs,link,1,16,1)
			for k,path in still do for j,p in path do
				close(p.x,later[k][j].x);close(p.y,later[k][j].y)
				if j==1 or j==#path then close(p.x,windy[k][j].x);close(p.y,windy[k][j].y)
				elseif math.abs(p.x-windy[k][j].x)+math.abs(p.y-windy[k][j].y)>1e-7 then moving=true end
			end end
			for _,quality in {2,4} do
				for k,path in Power.curves(refs,link,1,16,1,quality) do
					eq(#path,quality+1)
					close(path[1].x,windy[k][1].x);close(path[1].y,windy[k][1].y)
					close(path[#path].x,windy[k][#windy[k]].x);close(path[#path].y,windy[k][#windy[k]].y)
				end
			end
		end
		assert(moving,"wet weather must still move the conductors")
	end)
	test("wire tiles cover entire strokes in either direction without seams or hidden-cell bridges",function()
		local function visible() return true end
		for _,ends in {{{x=.5,y=1.5},{x=28.5,y=14.5}},{{x=32,y=32},{x=0,y=0}},{{x=8,y=20},{x=8,y=-2}}} do
			for flip=0,1 do
				local a,b=ends[1+flip],ends[2-flip];local sections=Power.sections(a,b,visible,8)
				local previous=a;local length=0
				for _,s in sections do
					close(previous.x,s.a.x);close(previous.y,s.a.y);previous=s.b
					for _,p in {s.a,s.b} do
						assert(p.x>=s.tx*8-1e-8 and p.x<=(s.tx+1)*8+1e-8)
						assert(p.y>=s.ty*8-1e-8 and p.y<=(s.ty+1)*8+1e-8)
					end
					length+=math.sqrt((s.b.x-s.a.x)^2+(s.b.y-s.a.y)^2)
				end
				close(previous.x,b.x);close(previous.y,b.y);close(length,math.sqrt((b.x-a.x)^2+(b.y-a.y)^2))
			end
		end
		local sections=Power.sections({x=.5,y=.5},{x=5.5,y=.5},function(x) return math.floor(x)~=2 end,8)
		eq(#sections,2);close(sections[1].b.x,2);close(sections[2].a.x,3)
		eq(#Power.sections({x=0,y=0},{x=0,y=0},visible,8),0)
	end)
	test("power wire hang points and wind sway match original drawSky on every Saddle span",function()
		for _,v in refs.vectors do
			local paths={}
			for _,link in refs.links do for _,curve in Power.curves(refs,link,v.time,8) do table.insert(paths,curve) end end
			eq(#paths,#v.paths)
			for i,curve in paths do
				eq(#curve*2,#v.paths[i])
				for j,p in curve do close(p.x,v.paths[i][j*2-1]);close(p.y,v.paths[i][j*2]) end
			end
		end
	end)
	test("power wire ground shadows match the original height and sag projection",function()
		for _,v in refs.shadows do
			eq(#v.paths,#refs.links)
			for i,link in refs.links do
				local path=Power.shadow(refs,link,v.sun);eq(#path*2,#v.paths[i])
				for j,p in path do close(p.x,v.paths[i][j*2-1]);close(p.y,v.paths[i][j*2]) end
			end
		end
	end)
	test("power line width and far alpha follow source zoom treatment",function()
		for _,v in refs.styles do local width,alpha=Power.style(refs.config,v.pixels);close(width,v.width);close(alpha,v.alpha) end
		local wood
		for _,link in refs.links do if not refs.nodes[link.a].steel then wood=link;break end end
		assert(wood);eq(#Power.curves(refs,wood,0,2),0)
		eq(#Power.curves(refs,wood,0,3),1)
	end)
	test("generated power plan is connected to plant roots and every span has valid endpoints",function()
		local steel,wood=0,0
		for _,n in data.nodes do
			assert(n.x>0 and n.x<384 and n.y>0 and n.y<240)
			if n.plant then continue end
			if n.steel then steel+=1 else wood+=1 end
			local at=n;local seen={}
			while not at.plant do
				assert(not seen[at.id],"power plan has a cycle");seen[at.id]=true
				assert(at.up>0 and data.nodes[at.up]);at=data.nodes[at.up]
			end
		end
		assert(steel>0 and wood>0);eq(#data.links,#data.nodes-data.plantCount)
		for _,link in data.links do assert(data.nodes[link.a] and data.nodes[link.b]);assert(link.a~=link.b) end
	end)
	test("source pole/pylon frames and neutral plant decode in one shared full/half atlas",function()
		local Codec=require("../src/shared/Maps/MapCodec")
		local Inflate=require("../src/shared/Utilities/Inflate")
		for _,variant in {data,data.half} do
			local raw=Inflate.raw(Codec.base64Decode(variant.deflate),variant.width*variant.height*4)
			eq(buffer.len(raw),variant.width*variant.height*4);assert(variant.width<=1024 and variant.height<=1024)
		end
		local raw=Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4)
		for row=0,2 do for face=0,data.facings-1 do
			local count=0
			for y=0,data.frame-1 do for x=0,data.frame-1 do if buffer.readu8(raw,((row*data.frame+y)*data.width+face*data.frame+x)*4+3)>0 then count+=1 end end end
			assert(count>0 and count<data.frame^2)
		end end
		eq(data.width/2,data.half.width);eq(data.height/2,data.half.height)
	end)
	test("power presentation does not mutate the static plan while sampling changing sun and wind",function()
		local serde=require("@lune/serde")
		local before=serde.encode("json",{nodes=refs.nodes,links=refs.links})
		for t=0,30 do for _,link in refs.links do Power.curves(refs,link,t*.1,10);Power.shadow(refs,link,{.2,1}) end end
		eq(before,serde.encode("json",{nodes=refs.nodes,links=refs.links}))
	end)
end
