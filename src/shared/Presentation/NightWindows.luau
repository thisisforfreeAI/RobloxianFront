--!strict
-- Original fine-cell occupancy/flicker, shared by pixel-shaped building fragments.
local Windows={}
Windows.MAX_VISIBLE=4096 -- APPROX batched-fragment cap; these share spatial canvases, not one Part each.
function Windows.prepare(points:{any},config:any,hash:(number,number)->number):{any}
	local out={}
	for id,p in points do
		local h=hash(p[3]*.613+7.7,p[4]*.613+7.7)
		local lit=h<config.windows and p[7]~=0
		local facade=p[6]~=nil and p[6]>=0
		if lit or facade then table.insert(out,{id=id,point=p,phase=if lit then h*31 else -1}) end
	end
	return out
end
function Windows.on(item:any,config:any,clock:number,hash:(number,number)->number):boolean
	if item.phase<0 then return false end
	local slot=math.floor(clock/config.flickerSec+item.phase)
	return hash(item.point[3]+slot,item.point[4]+slot)>.1
end
function Windows.fade(pixels:number,config:any):number
	return math.clamp((pixels-config.nearFrom)/(config.nearTo-config.nearFrom),0,1)
end
-- APPROX: conservative provenance for the owner's projected south/east facades. A fragment
-- stops drawing when any roof pixel that could project its wall is burning/charred/ruined.
-- Neighboring intact panes inside that shared fragment can disappear until the source restores.
function Windows.damaged(item:any,pixelsPerCell:number,fine:number,blocked:any):boolean
	local p=item.point;local tx,ty=math.floor(p[3]/fine),math.floor(p[4]/fine)
	local function cut(i) return if i==0 then 0 elseif i==fine then pixelsPerCell else math.ceil(i*pixelsPerCell/fine-.5) end
	local fx,fy=p[3]%fine,p[4]%fine
	for y=ty*pixelsPerCell+cut(fy),ty*pixelsPerCell+cut(fy+1)-1 do
		for x=tx*pixelsPerCell+cut(fx),tx*pixelsPerCell+cut(fx+1)-1 do
			if blocked(x,y-1) or blocked(x,y-2) or blocked(x-1,y) or blocked(x-2,y) then return true end
		end
	end;return false
end
function Windows.visible(items:{any},pixelsPerCell:number,cx:number,cy:number,rx:number,ry:number,eligible:any?):{any}
	local out={}
	local function farther(a:any,b:any):boolean
		return if a.distance==b.distance then a.item.id>b.item.id else a.distance>b.distance
	end
	for _,item in items do
		local x,y=(item.point[1]+6)/pixelsPerCell,(item.point[2]+6)/pixelsPerCell
		if math.abs(x-cx)<=rx+1 and math.abs(y-cy)<=ry+1 then
			if eligible and not eligible(item) then continue end
			local distance=(x-cx)^2+(y-cy)^2
			if #out<Windows.MAX_VISIBLE then
				table.insert(out,{item=item,distance=distance})
				local index=#out
				while index>1 do
					local parent=math.floor(index/2);if not farther(out[index],out[parent]) then break end
					out[index],out[parent]=out[parent],out[index];index=parent
				end
			elseif distance<out[1].distance or (distance==out[1].distance and item.id<out[1].item.id) then
				out[1]={item=item,distance=distance}
				local index=1
				while index*2<=#out do
					local child=index*2
					if child<#out and farther(out[child+1],out[child]) then child+=1 end
					if not farther(out[child],out[index]) then break end
					out[index],out[child]=out[child],out[index];index=child
				end
			end
		end
	end
	table.sort(out,function(a,b) return if a.distance==b.distance then a.item.id<b.item.id else a.distance<b.distance end)
	return out
end
return Windows
