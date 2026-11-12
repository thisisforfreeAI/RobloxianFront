--!strict
return function(test:any,eq:any)
	local Labels=require("../src/shared/Presentation/StructureLabels")
	test("healthy distant structures keep art without idle health labels; focus exposes health",function()
		local v={kind="barracks",hp=100,maxHp=100,built=1}
		local detail=Labels.detail(v,5,false,false);eq(detail.visible,false);eq(detail.bar,false);eq(detail.numbers,false)
		detail=Labels.detail(v,5,true,false);eq(detail.visible,true);eq(detail.bar,true);eq(detail.numbers,true)
		detail=Labels.detail(v,15,false,false);eq(detail.visible,true);eq(detail.bar,false)
	end)
	test("construction and damage retain indicators while fog memory never exposes health",function()
		local v={kind="factory",hp=50,maxHp=100,built=1}
		eq(Labels.detail(v,5,false,false).bar,true)
		v.stale=true;local detail=Labels.detail(v,20,true,true)
		eq(detail.bar,false);eq(detail.numbers,false)
		v.stale=false;v.hp=100;v.built=.3;eq(Labels.detail(v,2,false,false).visible,true)
	end)
	test("dense label layout reserves selected structure first and never overlaps placed labels",function()
		local input={};for i=1,60 do table.insert(input,{id=i,x=200+i%5*12,y=120+math.floor(i/5)*4,w=144,h=26,priority=if i==60 then 100 else 10}) end
		local out=Labels.layout(input,400,250);assert(out[60]);local count=0
		for id,a in out do count+=1;assert(a.x>=0 and a.y>=0 and a.x+a.w<=400 and a.y+a.h<=250)
			for other,b in out do if other~=id then assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y) end end
		end
		assert(count>1 and count<60)
		local reversed=table.clone(input);table.sort(reversed,function(a,b) return a.id>b.id end)
		local again=Labels.layout(reversed,400,250);for id,a in out do eq(a.x,again[id].x);eq(a.y,again[id].y) end
	end)
	test("label packing handles a viewport smaller than a label",function()
		local out=Labels.layout({{id=1,x=0,y=0,w=144,h=26,priority=100}},80,20)
		eq(out[1].x,0);eq(out[1].y,0);eq(out[1].w,80);eq(out[1].h,20)
	end)
end
