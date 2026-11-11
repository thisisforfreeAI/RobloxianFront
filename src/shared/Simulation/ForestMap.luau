--!strict
-- Stable source tree keys, quantized positions, cell-query order and lazily decoded CPU art.
-- No native images are allocated. The ignored pack data includes the port's existing road clearing.
local Map={}
function Map.firebreaks(width:number,height:number,roads:{any},rank:number):buffer
	local out=buffer.create(width*height)
	for _,road in roads do if road.rank<rank then continue end
		local p=road.pts
		for i=3,#p-1,2 do
			local dx,dy=p[i]-p[i-2],p[i+1]-p[i-1];local steps=math.max(1,math.ceil(math.sqrt(dx^2+dy^2)*4))
			for n=0,steps do local x,y=math.floor(p[i-2]+dx*n/steps),math.floor(p[i-1]+dy*n/steps)
				if x>=0 and y>=0 and x<width and y<height then buffer.writeu8(out,y*width+x,1) end
			end
		end
	end
	return out
end
function Map.new(data:any,decode:(string,number)->buffer,load:((string)->any)?):any
	assert(data.width>0 and data.height>0 and data.tileSize>0 and data.stride==48,"invalid forest dimensions")
	local bytes=decode(data.trees,data.count*48);assert(buffer.len(bytes)==data.count*48,"invalid forest tree storage")
	local self:any={width=data.width,height=data.height,tileSize=data.tileSize,trees={},byKey={},cells={},data=data}
	local sprites:buffer?=nil;local windows={}
	for index=1,data.count do
		local at=(index-1)*48
		local t={key=buffer.readf64(bytes,at),x=buffer.readf64(bytes,at+8),y=buffer.readf64(bytes,at+16),size=buffer.readf64(bytes,at+24),
			cell=buffer.readu32(bytes,at+32),sprite=buffer.readu16(bytes,at+36),drawX=buffer.readi32(bytes,at+40),drawY=buffer.readi32(bytes,at+44),standing=true,index=index}
		assert(t.key>=0 and t.key<math.huge and t.key%1==0 and not self.byKey[t.key],"invalid/duplicate forest key")
		assert(t.x==t.x and t.y==t.y and t.size>0 and t.size<math.huge and t.x>=0 and t.y>=0 and t.x<=data.width+.01 and t.y<=data.height+.01,"invalid forest tree coordinates")
		assert(t.cell<data.width*data.height and t.sprite>0 and data.families[t.sprite],"invalid forest tree reference")
		self.trees[index]=t;self.byKey[t.key]=t
		local cell=self.cells[t.cell];if not cell then cell={};self.cells[t.cell]=cell end;table.insert(cell,t)
	end
	function self.forNear(x:number,y:number,reach:number,fn:any)
		for cy=math.max(0,math.floor(y-reach)),math.min(data.height-1,math.floor(y+reach)) do
			for cx=math.max(0,math.floor(x-reach)),math.min(data.width-1,math.floor(x+reach)) do
				for _,t in self.cells[cy*data.width+cx] or {} do
					local distance=math.sqrt((t.x-x)^2+(t.y-y)^2);if distance<=reach then fn(t,distance) end
				end
			end
		end
	end
	function self.fuelAt(cell:number,fates:any):boolean
		for _,t in self.cells[cell] or {} do local f=fates[t.key];if not f or f.kind=="burning" then return true end end;return false
	end
	function self.inWindow(cx:number,cy:number,cw:number,ch:number):{any}
		local key=cx..":"..cy..":"..cw..":"..ch;local list=windows[key];if list then return list end
		list={}
		for _,t in self.trees do
			local family=data.families[t.sprite];local reach=math.max(family.fallen.w,family.standing.w,family.standing.h)/data.tileSize+1
			if t.x+reach>=cx and t.x-reach<=cx+cw and t.y+reach>=cy and t.y-reach<=cy+ch then table.insert(list,t) end
		end
		table.sort(list,function(a,b) return a.key<b.key end);windows[key]=list;return list
	end
	function self.pixels():buffer
		if sprites then return sprites end
		assert(load,"missing forest sprite loader");local out=buffer.create(data.pixelBytes);local cursor=0
		for _,part in data.pixelParts do
			assert(part.offset==cursor and part.bytes>0 and cursor+part.bytes<=data.pixelBytes,"invalid forest sprite bounds")
			local page=(load :: any)(part.name);local px=decode(page.deflate,part.bytes);assert(buffer.len(px)==part.bytes,"invalid forest sprite size")
			buffer.copy(out,cursor,px);cursor+=part.bytes
		end
		assert(cursor==data.pixelBytes,"incomplete forest sprite storage")
		for _,family in data.families do for _,kind in {"standing","fallen","stump","burnt"} do
			local f=family[kind];assert(f.w>0 and f.h>0 and f.w%1==0 and f.h%1==0 and f.offset>=0 and f.offset+f.w*f.h*4<=cursor,"invalid forest sprite frame")
		end end
		sprites=out;return out
	end
	return self
end
return Map
