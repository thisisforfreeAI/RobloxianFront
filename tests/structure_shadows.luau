--!strict
return function(test:any,eq:any)
	local P=require('../src/shared/Presentation/StructureShadows')
	local cfg={angleSteps=8,reachStep=.25,shadowPerHeight=1,stepPx=1,ink='#05080b'}
	test('height projection quantizes direction and strength, expands its bounds and caps stored resolution',function()
		local meta={frame=8,reach={2,4},bands={1,3}}
		local p=P.plan(cfg,meta,1,0,252);eq(p.angle,0);eq(p.reach,4);eq(p.margin,5);eq(p.width,18);eq(p.n,18)
		local tall=P.plan(cfg,meta,20,0,20);eq(tall.n,20);assert(tall.width>20)
		local left=P.plan(cfg,meta,-1,0,252);assert(math.abs(left.dx+1)<1e-9);eq(left.margin,p.margin)
	end)
	test('only supplied raised masks cast, with taller bands projecting farther and no coloured yard pixels',function()
		local meta={frame=8,reach={2,4},bands={1,3}};local raw=buffer.create(128)
		buffer.writeu8(raw,3*8+3,255);buffer.writeu8(raw,64+3*8+4,255)
		local p=P.plan(cfg,meta,1,0,252);local source=P.prepare(raw,meta);local out=P.raster(source,cfg,p)
		local function alpha(x,y) return buffer.readu8(out,(y*p.n+x)*4+3) end
		eq(alpha(8,8),255);eq(alpha(13,8),255);eq(alpha(14,8),0);eq(alpha(5,5),0)
		for at=0,buffer.len(out)-4,4 do if buffer.readu8(out,at+3)>0 then eq(buffer.readu8(out,at),5);eq(buffer.readu8(out,at+1),8);eq(buffer.readu8(out,at+2),11) end end
	end)
	test('translucent stamps composite once into a mask and cooperative work can be cancelled',function()
		local meta={frame=2,reach={0},bands={0}};local raw=buffer.create(4);buffer.writeu8(raw,0,128)
		local source=P.prepare(raw,meta);local p=P.plan(cfg,meta,0,0,252);local out=P.raster(source,cfg,p)
		eq(buffer.readu8(out,(1*p.n+1)*4+3),192)
		local calls=0;local ok=pcall(function() P.raster(source,cfg,p,function() calls+=1;error('cancel') end) end);eq(ok,false);eq(calls,1)
		eq(pcall(function() P.prepare(buffer.create(3),meta) end),false)
	end)
end
