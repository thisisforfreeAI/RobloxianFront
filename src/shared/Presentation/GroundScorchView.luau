--!strict
-- Source cell tint with port transport quantization and disjoint 32-cell canvases.
local Packets=if script then require(script.Parent.Parent.Protocol.GroundScorchPackets) else require("../Protocol/GroundScorchPackets")
local View={TILE=32}
function View.new(w:number,h:number,config:any):any
	local hex=tonumber(string.sub(config.color,2),16);assert(hex,"invalid scorch color")
	local color={bit32.extract(hex,16,8),bit32.extract(hex,8,8),bit32.extract(hex,0,8)}
	local self:any={epoch=nil,buckets={},serial=0}
	function self.apply(packet:any):boolean
		assert(type(packet.epoch)=="number" and packet.epoch>=1 and packet.epoch<math.huge and packet.epoch%1==0,"invalid scorch epoch")
		if self.epoch and packet.epoch<self.epoch then return false end
		local rows=Packets.decode(packet.rows,w*h)
		if packet.reset==true or packet.epoch~=self.epoch then table.clear(self.buckets);self.serial+=1 end
		self.epoch=packet.epoch
		for _,row in rows do
			local x,y=row[1]%w,math.floor(row[1]/w);local tx,ty=math.floor(x/View.TILE),math.floor(y/View.TILE);local key=tx..":"..ty
			local b=self.buckets[key]
			if not b and row[2]>0 then b={key=key,x=tx*View.TILE,y=ty*View.TILE,cw=math.min(View.TILE,w-tx*View.TILE),ch=math.min(View.TILE,h-ty*View.TILE),cells={}};self.buckets[key]=b end
			if b then
				b.cells[row[1]]=if row[2]>0 then row[2] else nil;self.serial+=1;b.version=self.serial
				if next(b.cells)==nil then self.buckets[key]=nil end
			end
		end;return true
	end
	function self.pixels(b:any,visible:any):(buffer,number)
		local out=buffer.create(b.cw*b.ch*4);local count=0
		for cell,value in b.cells do
			local x,y=cell%w,math.floor(cell/w);if not visible(x+.5,y+.5) then continue end
			local at=((y-b.y)*b.cw+x-b.x)*4;local alpha=math.floor(math.min(1,value/255*config.darken)*255+.5)
			if alpha<=0 then continue end
			for c=0,2 do buffer.writeu8(out,at+c,color[c+1]) end;buffer.writeu8(out,at+3,alpha);count+=1
		end;return out,count
	end
	return self
end
return View
