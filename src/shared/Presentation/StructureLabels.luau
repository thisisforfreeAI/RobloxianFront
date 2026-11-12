--!strict
-- APPROX port UX: screen-space packing and zoom thresholds, independent of combat rules.
local Labels={}
function Labels.detail(v:any,pixels:number,focus:boolean,hover:boolean):any
	local active=focus or hover
	local stale=v.stale==true
	local damaged=not stale and (v.hp or 1)<(v.maxHp or 1)
	local building=not stale and (v.built or 1)<1
	return {visible=active or building or damaged and pixels>=3 or pixels>=12 or v.kind=="hq" and pixels>=4,
		bar=not stale and (active or damaged or building),numbers=active and not stale,
		priority=if focus then 100 elseif hover then 90 elseif building then 70 elseif damaged then 60 elseif v.kind=="hq" then 40 else 10}
end
local function intersects(a:any,b:any):boolean
	return a.x<b.x+b.w+3 and a.x+a.w+3>b.x and a.y<b.y+b.h+3 and a.y+a.h+3>b.y
end
function Labels.layout(candidates:{any},width:number,height:number):{[number]:any}
	local ordered=table.clone(candidates)
	table.sort(ordered,function(a,b) return if a.priority==b.priority then a.id<b.id else a.priority>b.priority end)
	local occupied={};local result={}
	for _,v in ordered do
		local w,h=math.min(v.w,width),math.min(v.h,height)
		for _,offset in {{0,-h-10},{w/2+6,-h/2},{-w/2-6,-h/2},{0,12},{0,-2*h-14}} do
			local rect={x=math.clamp(v.x-w/2+offset[1],0,math.max(0,width-w)),y=math.clamp(v.y+offset[2],0,math.max(0,height-h)),w=w,h=h}
			local free=true;for _,old in occupied do if intersects(rect,old) then free=false;break end end
			if free then result[v.id]=rect;table.insert(occupied,rect);break end
		end
	end
	return result
end
return Labels
