--!strict
return function(test:any,eq:any)
	local Motion=require('../src/shared/Presentation/StructureTokens')
	local c={preview={from=7,fadePx=4},coverage={detail={from=7,fadePx=4},token={detailFrom=2,tokenFarPx=12,tokenMinPx=18,tokenMaxPx=40,tokenPerCell=2,tokenFloorPx=10,hqShare=1.4,facilityShare=1.1,farScale=2}},tokens={buildingAlpha=.4,stale={iconAlpha=.2,reach=.6,arm=.3,rimPx=4,linePx=2,rim='#112233',color='#eeeeee',alpha=.7},bar={max=70,widthShare=.75,buildGap=3,hpGap=6,height=3},accent='#123456',secured='#abcdef',contested='#dd0000'}}
	local rules={['production.spacing']=2,['structures.hq.kind']='hq'}
	test('placed badges retain token sizing and smoothly exchange alpha with footprint art',function()
		local v={kind='hq',cells=5,built=1,side=1,hp=100,maxHp=100}
		local far=Motion.plan(c,v,1,rules,1);eq(far.mix,0);eq(far.alpha,1);eq(#far.bars,0)
		local mid=Motion.plan(c,v,9,rules,1);eq(mid.mix,.5);eq(mid.alpha,.5)
		local near=Motion.plan(c,v,11,rules,1);eq(near.mix,1);eq(near.alpha,0)
		local pending=Motion.plan(c,v,11,rules,1,false);eq(pending.mix,0);eq(pending.alpha,1);eq(pending.detailMix,1)
	end)
	test('only own unfinished sites get construction bars and source health tolerance hides full bars',function()
		local v={kind='factory',cells=3,built=.5,side=1,hp=99,maxHp=100}
		local p=Motion.plan(c,v,8,rules,1);assert(math.abs(p.alpha-.3)<1e-9);eq(#p.bars,1);eq(p.bars[1].share,.5)
		local span=p.size+(24-p.size)*.25;eq(p.bars[1].y,span/2+3);eq(p.bars[1].h,3)
		v.hp=50;p=Motion.plan(c,v,8,rules,1);eq(#p.bars,2);eq(p.bars[2].ink,c.tokens.contested);eq(p.bars[2].y,-span/2-6)
		v.side=2;p=Motion.plan(c,v,8,rules,1);eq(#p.bars,1)
	end)
	test('damaged facility symbols follow server flags, ownership and the source zoom threshold',function()
		c.tokens.status={minPx=11,sizeShare=.4,offsetShare=.45,discShare=.6,ink='#ffff00',plate='rgba(11, 16, 24, 0.88)'}
		local v={kind='factory',cells=3,built=1,side=1,hp=20,maxHp=100,markerFlags=1};local p=Motion.plan(c,v,8,rules,1)
		assert(p.warning);eq(p.warning.size,math.max(11,math.floor(p.size*.4+.5)));eq(p.warning.radius,p.warning.size*.6)
		eq(Motion.plan(c,v,1,rules,1).warning,nil);v.side=2;eq(Motion.plan(c,v,8,rules,1).warning,nil)
		v.side=1;v.markerFlags=2;eq(Motion.plan(c,v,8,rules,1).warning,nil);v.markerFlags=0;eq(Motion.plan(c,v,8,rules,1).warning,nil)
	end)
	test('ground symbols preserve absolute pixel rounding, night fade and known visibility',function()
		c.ground={from=20,fadePx=4,share=.5,symbolShare=.4,gapCells=.3,alpha=.8,nightFade=.5,shadePx=2}
		local p=Motion.ground(c,100,22,.5,false,0,{X=10.25,Y=20.75});eq(p.x,18.75);eq(p.y,-37.75);eq(p.size,125);assert(math.abs(p.alpha-.3)<1e-9);eq(p.shade,2)
		eq(Motion.ground(c,100,20,0,false),nil);eq(Motion.ground(c,100,24,0,true),nil);eq(Motion.ground(c,100,24,0,false,2),nil);eq(Motion.ground({},100,24,0,false),nil)
	end)
	test('fog markers expose no health construction colour or live operation and ignore zoom detail',function()
		local v={kind='factory',built=.1,side=2,hp=2,maxHp=100,stale=true}
		for _,px in {1,8,40} do local p=Motion.plan(c,v,px,rules,1);eq(p.mix,0);eq(p.alpha,.2);eq(#p.bars,0);eq(#p.rects,16)
			for _,r in p.rects do assert(r.w>0 and r.h>0);assert(r.ink==c.tokens.stale.rim or r.ink==c.tokens.stale.color) end
		end
		eq(Motion.plan({},v,8,rules,1),nil)
	end)
end
