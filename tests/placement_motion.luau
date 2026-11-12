--!strict
return function(test:any,eq:any)
	local M=require("../src/shared/Presentation/PlacementMotion")
	local cfg={ok="#11aa44",bad="#aa2244",hover={pulseSec=2,liftShare=.1,bobSec=4,bobPx=2,jitterHz=1,jitterPx=1.5,alpha=.8,refusedAlpha=.4,scanSec=2,wash=.1,gridAlpha=.2,edgeDash={4,4},marchPxPerSec=8,bracketShare=.2},refused={cellAlpha=.4,hatchPx=4,clashSec=2,clashAlpha={.1,.3}}}
	local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("placement pose follows source bob, refusal jitter, alpha and native-size rounding",function()
		local p=M.geometry(cfg,101,3,1,true,{blocked={},clashes={}},.75)
		eq(p.bodySize,76);near(p.share,76/101);near(p.offset,13/101);near(p.lift,9.6);eq(p.jitter,0);eq(p.alpha,.8);near(p.scan,.5)
		local refused=M.geometry(cfg,100,3,.25,false,{blocked={},clashes={}});eq(refused.ink,cfg.bad);eq(refused.jitter,1.5);eq(refused.alpha,.4)
	end)
	test("placement grid and brackets retain source screen widths while border marches",function()
		local a=M.geometry(cfg,100,3,0,true,{blocked={},clashes={}});local b=M.geometry(cfg,100,3,.25,true,{blocked={},clashes={}})
		near(a.rects[2].w,.01);near(a.rects[3].h,.01);eq(a.rects[#a.rects].alpha,.9)
		local changed=false;for i=6,math.min(#a.rects,#b.rects)-8 do if a.rects[i].x~=b.rects[i].x or a.rects[i].y~=b.rects[i].y then changed=true end end;assert(changed)
	end)
	test("blocked cells have source wash and clipped diagonal hatch geometry",function()
		local p=M.geometry(cfg,90,3,0,false,{blocked={{dx=0,dy=0}},clashes={}})
		local wash,hatches=0,0
		for _,r in p.rects do
			if r.alpha==cfg.refused.cellAlpha*.55 then wash+=1;near(r.x,1/3);near(r.y,1/3);near(r.w,1/3) end
			if r.rotation==-45 then hatches+=1;eq(r.alpha,.4) end
		end
		eq(wash,1);assert(hatches>0)
	end)
	test("known clashes pulse above the preview and drawing caps do not grow with unlimited blockers",function()
		local clashes={};for i=1,30 do table.insert(clashes,{dx=i,dy=0,cells=3}) end
		local p=M.geometry(cfg,10000,3,0,false,{blocked={{dx=0,dy=0}},clashes=clashes})
		assert(#p.rects<450,#p.rects);local fills=0
		for _,r in p.rects do if r.z==4 then if r.alpha~=.95 then fills+=1;near(r.alpha,.2) end end end;eq(fills,8)
	end)
end
