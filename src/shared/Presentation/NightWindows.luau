--!strict
-- Original fine-cell occupancy/flicker, shared by pixel-shaped building fragments.
local Windows={}
Windows.MAX_VISIBLE=768 -- APPROX port rendering cap, not a gameplay/source limit.
function Windows.prepare(points:{any},config:any,hash:(number,number)->number):{any}
	local out={}
	for id,p in points do
		local h=hash(p[3]*.613+7.7,p[4]*.613+7.7)
		if h<config.windows then table.insert(out,{id=id,point=p,phase=h*31}) end
	end
	return out
end
function Windows.on(item:any,config:any,clock:number,hash:(number,number)->number):boolean
	local slot=math.floor(clock/config.flickerSec+item.phase)
	return hash(item.point[3]+slot,item.point[4]+slot)>.1
end
function Windows.fade(pixels:number,config:any):number
	return math.clamp((pixels-config.nearFrom)/(config.nearTo-config.nearFrom),0,1)
end
function Windows.visible(items:{any},pixelsPerCell:number,cx:number,cy:number,rx:number,ry:number):{any}
	local out={}
	for _,item in items do
		local x,y=(item.point[1]+6)/pixelsPerCell,(item.point[2]+6)/pixelsPerCell
		if math.abs(x-cx)<=rx+1 and math.abs(y-cy)<=ry+1 then
			table.insert(out,{item=item,distance=(x-cx)^2+(y-cy)^2})
		end
	end
	table.sort(out,function(a,b) return if a.distance==b.distance then a.item.id<b.item.id else a.distance<b.distance end)
	while #out>Windows.MAX_VISIBLE do table.remove(out) end
	return out
end
return Windows
