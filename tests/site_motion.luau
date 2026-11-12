--!strict
return function(test:any,eq:any)
	local M=require("../src/shared/Presentation/SiteMotion")
	local c={yardShare=.25,accent="#112233",ok="#224455",hover={liftShare=.1,alpha=.8},site={blueprintAlpha=.2,gridAlpha=.1,pegPx=3,laserSec=4,laserAlpha=.5},survey={ink="#eeeedd",alpha=.4,dash={4,4},pegPx=2},drop={sec=.5,ringSec=1,ringGrow=1,flash=.6},done={sec=2,band=.2,glow=.8,ringGrow=1}}
	local function near(a,b) assert(math.abs(a-b)<1e-8,`{a} != {b}`) end
	test("site observation marks fresh placement and completion but never initial or hidden history",function()
		local first=M.observe(nil,.01,true,10,true);eq(first.placed,-math.huge)
		local fresh=M.observe(nil,.01,true,10,false);eq(fresh.placed,10)
		local halfway=M.observe(fresh,.8,true,20);eq(halfway.placed,10)
		local done=M.observe(halfway,1,true,30);eq(done.done,30);eq(M.observe(done,1,true,40).done,30)
		local hidden=M.observe(halfway,1,false,30);eq(hidden.hidden,true)
		local reveal=M.observe(hidden,1,true,40);eq(reveal.done,-math.huge);eq(reveal.placed,-math.huge)
	end)
	test("yard timing normalizes height raising only after the survey stage",function()
		eq(M.raise(.249,.25),nil);near(M.raise(.25,.25),0);near(M.raise(.625,.25),.5);near(M.raise(1,.25),1)
		local yard=M.geometry(c,{built=.1,placed=-math.huge,done=-math.huge},100,3,1)
		eq(yard.active,true);near(yard.laser.y,.49);near(yard.laser.h,.02);eq(yard.blueprint,.2)
		local raise=M.geometry(c,{built=.4,placed=-math.huge,done=-math.huge},100,3,1);eq(raise.laser,nil);eq(raise.blueprint,.2)
	end)
	test("source survey pegs retain rounded screen positions and strings keep their separate opacity",function()
		local pose=M.geometry(c,{built=.1,placed=-math.huge,done=-math.huge},120,3,1);local pegs,strings=0,0
		for _,r in pose.rects do if r.ink==c.survey.ink then
			if r.alpha==1 then pegs+=1;near(r.w,2/120);near(r.h,2/120) else strings+=1;eq(r.alpha,.4) end
		end end
		eq(pegs,16);assert(strings>0)
		local found=false;for _,r in pose.rects do if r.ink==c.survey.ink and r.alpha==1 and r.x==9/120 and r.y==9/120 then found=true end end;assert(found)
	end)
	test("site lines and corner pegs retain screen-pixel widths across zoom levels",function()
		local state={built=.4,placed=-math.huge,done=-math.huge}
		for _,side in {20,100,400} do
			local p=M.geometry(c,state,side,3,1);near(p.rects[1].w,1/side);near(p.rects[2].h,1/side)
			local count=0;for _,r in p.rects do if r.alpha~=.1 then near(r.w,3/side);near(r.h,3/side);count+=1 end end;eq(count,4)
		end
	end)
	test("placement lift and expanding rings expire while completion uses its own lifetime",function()
		local p=M.geometry(c,{built=.1,placed=0,done=-math.huge},100,3,.25);near(p.drop.lift,-.075);near(p.drop.alpha,.4)
		local p2=M.geometry(c,{built=.1,placed=0,done=-math.huge},100,3,1);eq(p2.drop,nil)
		for _,r in p2.rects do assert(r.z~=6) end
		local done=M.geometry(c,{built=1,placed=0,done=1},100,3,2);eq(done.active,true);near(done.done.alpha,.6);near(done.done.center,.46)
		eq(M.geometry(c,{built=1,placed=0,done=1},100,3,3).active,false)
	end)
	test("completion gradient stays sorted unique and bounded at both ends of the sweep",function()
		for _,center in {-.2,0,.03,.5,.99,1,1.2} do
			local points=M.gradient(center,.2);eq(points[1][1],0);eq(points[#points][1],1)
			for i,p in points do assert(p[2]>=0 and p[2]<=1);if i>1 then assert(p[1]>points[i-1][1]) end end
		end
	end)
	test("survey UI remains bounded at extreme zoom and hidden sites expose no geometry",function()
		local state={built=.1,placed=-math.huge,done=-math.huge};local p=M.geometry(c,state,10000,5,1)
		assert(#p.rects<250,#p.rects);eq(M.geometry(c,{hidden=true},100,3,1).active,false);eq(M.geometry(c,nil,100,3,1).active,false)
	end)
end
