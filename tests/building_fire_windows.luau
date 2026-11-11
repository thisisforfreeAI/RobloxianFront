--!strict
return function(test:any,eq:any)
	local Mask=require("../src/shared/Presentation/BuildingFireMask")
	local Windows=require("../src/shared/Presentation/NightWindows")
	test("burning roof actors and lasting char independently suppress lights until restoration",function()
		local mask=Mask.new(4,3,14);local p=10*56+12
		mask.actors({{px={p}}});assert(mask.blocked(12,10));eq(mask.blocked(13,10),false)
		mask.apply({{p,3}});mask.actors({});assert(mask.blocked(12,10))
		mask.apply({{p,0}});eq(mask.blocked(12,10),false)
		mask.apply({{p,1}});mask.reset();eq(mask.blocked(12,10),false)
		eq(mask.any(),false);local revision=mask.revision;mask.apply({});mask.actors({});eq(mask.revision,revision)
		mask.actors({{px={p}}});revision=mask.revision;mask.actors({{px={p}}});eq(mask.revision,revision)
		eq(mask.blocked(-1,0),false);eq(mask.blocked(56,0),false)
	end)
	test("projected windows find damaged parent roof pixels across source tile boundaries",function()
		local mask=Mask.new(4,3,14);local item={point={11,6,3,2,0,1,1}}
		local blocked=function(x,y) return mask.blocked(x,y) end
		eq(Windows.damaged(item,14,3,blocked),false)
		mask.apply({{10*56+12,2}});eq(Windows.damaged(item,14,3,blocked),true)
		mask.reset();mask.apply({{10*56+30,3}});eq(Windows.damaged(item,14,3,blocked),false)
	end)
	test("destroyed window fragments do not consume the nearest visible intact-fragment cap",function()
		local items={};for id=1,Windows.MAX_VISIBLE*2 do table.insert(items,{id=id,point={0,0,0,0,0}}) end
		local selected=Windows.visible(items,14,0,0,10,10,function(item) return item.id%2==0 end)
		eq(#selected,Windows.MAX_VISIBLE);for i,row in selected do eq(row.item.id,i*2) end
	end)
end
