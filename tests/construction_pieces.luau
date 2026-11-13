--!strict
return function(test:any,eq:any)
	local P=require("../src/shared/Presentation/ConstructionPieces");local R=require("../src/shared/Utilities/Rng")
	local cfg={pieces={count=3,seed=33,shift=11,mul=123457,add=19,liftRate=1.25,fadeRate=2,scaffold={2,3}},site={dropShare=.6,pieceGlow=.5}}
	local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." != "..tostring(b)) end
	test("piece order is deterministic per building, complete and independent of other sites",function()
		local a=P.order(cfg.pieces,2,R.imul);local b=P.order(cfg.pieces,2,R.imul);local c=P.order(cfg.pieces,3,R.imul);local seen={};local different=false
		for i,v in a do eq(v,b[i]);assert(v>=0 and v<9 and not seen[v]);seen[v]=true;if v~=c[i] then different=true end end
		eq(#a,9);assert(different)
	end)
	test("assembled cells stay grounded while only the next cell drops and fades in",function()
		local order=P.order(cfg.pieces,2,R.imul);local p=P.geometry(cfg,.5,90,order);eq(#p.tiles,5)
		for i,t in p.tiles do eq(t.cell,order[i]);if i<5 then eq(t.dy,0);eq(t.alpha,1);eq(t.active,false) else near(t.dy,-2.53125);eq(t.alpha,1);eq(t.active,true) end end
		local start=P.geometry(cfg,0,90,order);eq(#start.tiles,1);eq(start.tiles[1].alpha,0)
		local done=P.geometry(cfg,1,90,order);eq(#done.tiles,9);for _,t in done.tiles do eq(t.alpha,1);eq(t.active,false) end
	end)
	test("integer crops cover every trimmed source pixel exactly once with preserved canvas offsets",function()
		local r={10,20,5,4,1,2};local seen={}
		for y=0,2 do for x=0,2 do local c=P.crop(r,7,3,x,y);if c then
			near(c.x,(c.sx-10+1)/7);near(c.y,(c.sy-20+2)/7)
			for yy=c.sy,c.sy+c.sh-1 do for xx=c.sx,c.sx+c.sw-1 do local key=yy*100+xx;assert(not seen[key]);seen[key]=true end end
		end end end
		local n=0;for _ in seen do n+=1 end;eq(n,20);eq(P.crop(r,7,3,0,0),nil)
	end)
	test("fallback geometry stays bounded and keeps finite poses at extreme screen scales",function()
		local order=P.order(cfg.pieces,123,R.imul)
		for _,side in {6,90,10000} do local p=P.geometry(cfg,.83,side,order);assert(#p.tiles<=9);assert(#p.rects<=210)
			for _,t in p.tiles do assert(t.alpha>=0 and t.alpha<=1 and t.dy==t.dy) end
		end
	end)
end
