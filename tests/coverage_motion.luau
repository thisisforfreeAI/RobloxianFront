--!strict
return function(test:any,eq:any)
	local M=require("../src/shared/Presentation/CoverageMotion")
	local c={token={detailFrom=3,tokenFarPx=18,tokenMaxPx=64,tokenMinPx=28,tokenPerCell=3.5,tokenFloorPx=16,hqShare=1.4,facilityShare=1.2,farScale=2},detail={from=8,fadePx=2},marker={ringShare=1.1,glowShare=1.7,pulseSec=2,spinSec=8}}
	local rules={["structures.radar.kind"]="defence",["structures.radar.radar"]=50,["structures.bunker.kind"]="defence",["structures.bunker.range"]=16,["structures.factory.kind"]="facility",["production.spacing"]=0}
	local function project(x,y) return x*10,y*10,1 end
	local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("coverage token follows source far/detail/spacing transitions",function()
		eq(M.token(c,"facility",2,0),43);eq(M.token(c,"facility",10,0),30);eq(M.token(c,"hq",10,0),35)
		eq(M.token(c,"facility",10,-1),42)
	end)
	test("radar preview and known same-type sites use current base match radii",function()
		local sites={{id=1,kind="radar",side=1,x=5,y=5,built=1,hp=100},{id=2,kind="radar",side=2,x=9,y=5,stale=true,hp=1},{id=3,kind="bunker",side=1,x=6,y=6}}
		local p=M.plan(c,"radar",6,6,1,rules,sites,2,project,800,600)
		eq(#p.sites,2);eq(p.ghost.radius,100)
		for _,s in p.sites do eq(s.radius,100);eq(s.own,s.id==1) end
		local b=M.plan(c,"bunker",6,6,1,rules,sites,2,project,800,600);eq(#b.sites,1);eq(b.sites[1].radius,32);eq(b.ghost,nil)
	end)
	test("guides omit hidden/dead/different sites, keep intersecting offscreen circles and cap nearest twelve",function()
		local sites={{id=100,kind="radar",hidden=true,x=5,y=5},{id=101,kind="radar",hp=0,x=5,y=5},{id=102,kind="factory",x=5,y=5}}
		for i=1,30 do table.insert(sites,{id=i,kind="radar",side=1,x=i,y=10,hp=10}) end
		local p=M.plan(c,"radar",1,10,1,rules,sites,2,project,100,100);eq(#p.sites,12)
		for _,s in p.sites do assert(s.id<100) end;eq(p.sites[1].id,1)
		local off=M.plan(c,"radar",1,1,1,rules,{{id=9,kind="radar",x=-3,y=5,hp=1}},2,project,100,100);eq(#off.sites,1)
		local behind=M.plan(c,"radar",1,1,1,rules,sites,2,function(x,y) return x,y,-1 end,100,100);eq(#behind.sites,0);eq(behind.ghost,nil)
	end)
	test("source marker rotation, pulse and rounded radial-glow peak are deterministic",function()
		local a=M.marker(c,40,0);near(a.radius,44);near(a.outer,68);near(a.alpha,.85);near(a.glow,.33);eq(a.rotation,0)
		local b=M.marker(c,40,.5);near(b.alpha,1);near(b.glow,.4);near(b.rotation,22.5)
	end)
	test("arc chords retain radius/duty geometry and stay bounded at tiny or enormous zoom",function()
		for _,radius in {.1,1,10,100,10000} do
			local parts=M.dashes(radius,{8,6},64);assert(#parts<=80,#parts);assert(#parts>0)
			for _,p in parts do assert(p.length>0 and p.length==p.length);assert(math.sqrt(p.x*p.x+p.y*p.y)<=radius+1e-8);assert(p.rotation==p.rotation) end
		end
		eq(#M.dashes(0,{8,6},64),0)
	end)
end
