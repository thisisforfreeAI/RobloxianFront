--!strict
-- Source k6/hN: cell-boundary ray walk, with a summed-area fast path. Origin and destination
-- buildings do not hide themselves; intermediate settlement footprints block ground sight.
local Visibility = {}
function Visibility.new(w: number, h: number, source: buffer?, classAt: ((number) -> number)?)
	local mask = buffer.create(w*h)
	local sum = buffer.create((w+1)*(h+1)*4)
	assert(not source or buffer.len(source)==w*h,"building visibility map dimensions differ")
	local count = 0
	for y=0,h-1 do
		local row = 0
		for x=0,w-1 do
			local cell = y*w+x
			local blocked = source and buffer.readu8(source,cell)==1 and (not classAt or classAt(cell)~=1)
			if blocked then buffer.writeu8(mask,cell,1);row+=1;count+=1 end
			buffer.writeu32(sum,((y+1)*(w+1)+x+1)*4,row+buffer.readu32(sum,(y*(w+1)+x+1)*4))
		end
	end
	local self = {count=count}
	function self.hasIn(ax: number,ay: number,bx: number,by: number): boolean
		local x0,y0 = math.max(0,math.floor(math.min(ax,bx))),math.max(0,math.floor(math.min(ay,by)))
		local x1,y1 = math.min(w-1,math.floor(math.max(ax,bx))),math.min(h-1,math.floor(math.max(ay,by)))
		if x0>x1 or y0>y1 or count==0 then return false end
		local function at(x,y) return buffer.readu32(sum,(y*(w+1)+x)*4) end
		return at(x1+1,y1+1)-at(x0,y1+1)-at(x1+1,y0)+at(x0,y0)>0
	end
	function self.clear(ax: number,ay: number,bx: number,by: number): boolean
		if not self.hasIn(ax,ay,bx,by) then return true end
		local x,y,tx,ty = math.floor(ax),math.floor(ay),math.floor(bx),math.floor(by)
		local dx,dy = bx-ax,by-ay
		local sx,sy = if dx>0 then 1 else -1,if dy>0 then 1 else -1
		local ix,iy = if dx~=0 then math.abs(1/dx) else math.huge,if dy~=0 then math.abs(1/dy) else math.huge
		local nx = (if dx>0 then x+1-ax else ax-x)*ix
		local ny = (if dy>0 then y+1-ay else ay-y)*iy
		if dx==0 then nx=math.huge end
		if dy==0 then ny=math.huge end
		for _=1,math.abs(tx-x)+math.abs(ty-y) do
			if nx<ny then x+=sx;nx+=ix else y+=sy;ny+=iy end
			if (x==tx and y==ty) or x<0 or y<0 or x>=w or y>=h then return true end
			if buffer.readu8(mask,y*w+x)==1 then return false end
		end
		return true
	end
	return self
end
return Visibility
