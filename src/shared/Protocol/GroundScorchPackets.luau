--!strict
-- Port transport policy: at most 5 KiB of visible cell/strength deltas per snapshot.
local Packets={LIMIT=1024}
function Packets.encode(rows:{any}):buffer
	assert(#rows<=Packets.LIMIT,"scorch packet exceeds budget");local out=buffer.create(#rows*5)
	for i,row in rows do
		local cell,value=row[1],row[2]
		assert(type(cell)=="number" and cell>=0 and cell<4294967296 and cell%1==0 and type(value)=="number" and value>=0 and value<=255 and value%1==0,"invalid scorch row")
		buffer.writeu32(out,(i-1)*5,cell);buffer.writeu8(out,(i-1)*5+4,value)
	end;return out
end
function Packets.decode(data:buffer,total:number):{any}
	assert(typeof(data)=="buffer" and buffer.len(data)%5==0 and buffer.len(data)<=Packets.LIMIT*5,"invalid scorch packet length")
	local rows={};for at=0,buffer.len(data)-1,5 do
		local cell=buffer.readu32(data,at);assert(cell<total,"invalid scorch cell");table.insert(rows,{cell,buffer.readu8(data,at+4)})
	end;return rows
end
return Packets
