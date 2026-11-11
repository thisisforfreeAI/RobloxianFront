--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs")
	if not fs.isFile("src/shared/GameData/ChimneySmokeVectors.luau") or not fs.isFile("src/client/DevAssets/OrigChimneySmoke_saddle.luau") then return end
	local Smoke=require("../src/shared/Presentation/ChimneySmoke")
	local Hash=require("../src/shared/Utilities/Hash")
	local refs=require("../src/shared/GameData/ChimneySmokeVectors") ::any
	local data=require("../src/client/DevAssets/OrigChimneySmoke_saddle") ::any
	local function close(a:number,b:number) assert(math.abs(a-b)<1e-9,tostring(a).." != "..tostring(b)) end
	local function town():any return {id=refs.town.id,known=true,integrity=100,garrison=0,hitAt=0} end
	test("chimney puff positions, sizes, turns, alpha and density match original draw/smoke",function()
		local seen=0
		for _,v in refs.cases do
			local t=town();t.integrity=v.integrity;t.garrison=v.garrison;t.hitAt=v.time
			local poses=Smoke.poses(t,refs.town.chimneys,refs.config,v.time,v.share,v.night,Hash.ambient)
			eq(#poses,#v.poses)
			for i,p in poses do for _,key in {"x","y","cells","heading","alpha"} do close(p[key],v.poses[i][key]) end end
			seen+=#poses
		end
		assert(seen>0,"reference must exercise live puffs as well as night/damage suppression")
	end)
	test("chimneys require known live towns and current origin/puff visibility",function()
		local t=town();local sites={refs.town.chimneys[1]}
		local function sample(visible:any?) return Smoke.poses(t,sites,refs.config,1,1,0,Hash.ambient,nil,visible) end
		assert(#sample()>0)
		t.known=false;eq(#sample(),0);t.known=true
		t.destroyed=true;eq(#sample(),0);t.destroyed=false
		t.integrity=0;eq(#sample(),0);t.integrity=100
		eq(#sample(function() return false end),0)
		-- The source is visible at the boundary, but its wind-blown puffs cross into hidden cells.
		eq(#sample(function(x) return x<=sites[1].x end),0)
		eq(#Smoke.poses(t,sites,refs.config,1,1,0,Hash.ambient,{x0=-1000,x1=-999,y0=-1000,y1=-999}),0)
	end)
	test("chimney smoke follows quantized war time without mutating city or combat state",function()
		local t=town();t.hitAt=0
		local before=table.clone(t)
		local a=Smoke.poses(t,refs.town.chimneys,refs.config,0,1,0,Hash.ambient)
		local b=Smoke.poses(t,refs.town.chimneys,refs.config,.25/refs.config.smoke.fps,1,0,Hash.ambient)
		eq(#a,#b);assert(#a>0)
		for i,p in a do for _,key in {"x","y","cells","heading","alpha"} do eq(p[key],b[i][key]) end end
		for key,value in before do eq(t[key],value) end
		-- A hit suppresses cars/people during calm, but does not shut off ambient chimney smoke.
		eq(#Smoke.poses(t,refs.town.chimneys,refs.config,0,1,0,Hash.ambient),#a)
		eq(#Smoke.poses(t,refs.town.chimneys,refs.config,1,0,0,Hash.ambient),0)
		eq(#Smoke.poses(t,refs.town.chimneys,refs.config,1,1,1,Hash.ambient),0)
	end)
	test("local chimney sites stay in their source urban cells and clear the road raster",function()
		local input=require("@lune/serde").decode("json",fs.readFile("docs/private/smoke-input_saddle.json"))
		local count=0
		for _,t in data.towns do
			assert(#t.chimneys<=data.config.towns.chimneys[t.kind])
			for _,site in t.chimneys do
				local c=math.floor(site.y)*input.w+math.floor(site.x)+1
				assert(input.urban[c]>0 and input.road[c]==0,"Saddle chimney must be urban and off road")
				assert(site.seed>=0 and site.seed<1);count+=1
			end
		end
		assert(count>0)
	end)
	test("all original puff facings decode in one small transparent atlas",function()
		local Codec=require("../src/shared/Maps/MapCodec")
		local Inflate=require("../src/shared/Utilities/Inflate")
		local rgba=Inflate.raw(Codec.base64Decode(data.deflate),data.width*data.height*4)
		eq(buffer.len(rgba),data.width*data.height*4)
		eq(data.width,data.frame*data.facings);eq(data.height,data.frame)
		assert(data.width<=1024 and data.height<=1024 and buffer.len(rgba)<128*1024)
		for frame=0,data.facings-1 do
			local solid,clear=0,0
			for y=0,data.frame-1 do for x=0,data.frame-1 do
				local alpha=buffer.readu8(rgba,(y*data.width+frame*data.frame+x)*4+3)
				if alpha>0 then solid+=1 else clear+=1 end
			end end
			assert(solid>0 and clear>0,"each puff frame needs visible soft art and transparent surroundings")
		end
	end)
end
