--!strict
-- APPROX rendering policy, not game rules: screen-space resolution with hysteresis.
local TownDetail = {}
function TownDetail.predict(x:number,y:number,lastX:number?,lastY:number?,dt:number,rx:number,ry:number):(number,number)
	if not lastX or not lastY or dt<=0 then return x,y end
	local dx,dy=(x-lastX)*.35/dt,(y-lastY)*.35/dt
	local length=math.sqrt(dx*dx+dy*dy);local cap=math.max(rx,ry)
	if length>cap then dx*=cap/length;dy*=cap/length end
	return x+dx,y+dy
end
-- Visible rectangle first; direction-predicted candidates warm CPU pixels without native images.
function TownDetail.plan(chunks:{any},x:number,y:number,rx:number,ry:number,limit:number,px:number,py:number):({any},any,{any},number)
	local visible,prefetch={},{}
	local function intersects(c,cx,cy,pad)
		return c.cx<=cx+rx+pad and c.cy<=cy+ry+pad and c.cx+c.cw>=cx-rx-pad and c.cy+c.ch>=cy-ry-pad
	end
	local function d(c,cx,cy) return (c.cx+c.cw/2-cx)^2+(c.cy+c.ch/2-cy)^2 end
	for _,c in chunks do
		if intersects(c,x,y,0) then table.insert(visible,c)
		elseif intersects(c,px,py,math.max(c.cw,c.ch)) then table.insert(prefetch,c) end
	end
	table.sort(visible,function(a,b) return d(a,x,y)<d(b,x,y) end)
	table.sort(prefetch,function(a,b) return d(a,px,py)<d(b,px,py) end)
	local want,keep={},{};for i=1,math.min(#visible,limit) do table.insert(want,visible[i]);keep[visible[i]]=true end
	for i=1,math.min(#prefetch,4) do keep[prefetch[i]]=true end
	return want,keep,prefetch,#visible
end
-- APPROX port policy: cover the selected view at one affordable tier before upgrading a few tiles.
function TownDetail.bytes(chunks:{any},stride:number,tile:number):number
	local bytes=0;for _,c in chunks do bytes+=math.ceil(c.cw*tile/stride)*math.ceil(c.ch*tile/stride)*4 end;return bytes
end
function TownDetail.fitStride(preferred:number,chunks:{any},tile:number,bytes:number):number
	local stride=preferred
	while stride<4 and TownDetail.bytes(chunks,stride,tile)>bytes do stride*=2 end
	return stride
end
function TownDetail.stride(cellPixels: number, previous: number): number
	if previous == 1 and cellPixels >= 7 then return 1 end
	if cellPixels >= 8 then return 1 end
	if previous == 2 and cellPixels >= 3.6 then return 2 end
	if cellPixels >= 4.2 then return 2 end
	if previous == 4 and cellPixels >= 2.2 then return 4 end
	if cellPixels >= 2.8 then return 4 end
	return 0
end
function TownDetail.frame(phase: number, sunUp: number, steps: number): number
	local p = phase % 1
	local progress = if p < sunUp then p / sunUp else (p - sunUp) / (1 - sunUp)
	return math.clamp(math.floor(progress * steps + 0.5), 0, steps) + 1
end
return TownDetail
