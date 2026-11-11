--!strict
-- Port transport policy, not gameplay: bounded compact roof-pixel deltas and one-time actor points.
local Packets={PIXELS_PER_PACKET=2048,ROOF_BYTES_PER_PACKET=16384,TREES_PER_PACKET=512}
local kinds={burning=1,fallen=2,stump=3,burnt=4};local names={"burning","fallen","stump","burnt"}
function Packets.trees(rows:{any}):buffer
	assert(#rows<=Packets.TREES_PER_PACKET,"forest packet exceeds budget");local out=buffer.create(#rows*14)
	for i,row in rows do local at=(i-1)*14;local fate=row[2]
		buffer.writef64(out,at,row[1]);buffer.writeu8(out,at+8,if fate then assert(kinds[fate.kind],"invalid tree fate") else 0)
		buffer.writeu8(out,at+9,if fate and fate.char~=nil then fate.char else 255);buffer.writef32(out,at+10,if fate then fate.rot or 0 else 0)
	end;return out
end
function Packets.readTrees(data:buffer,known:any,stages:number):{any}
	assert(buffer.len(data)%14==0 and buffer.len(data)<=Packets.TREES_PER_PACKET*14,"invalid forest packet length")
	local rows={}
	for at=0,buffer.len(data)-1,14 do
		local key=buffer.readf64(data,at);local kind,char,rot=buffer.readu8(data,at+8),buffer.readu8(data,at+9),buffer.readf32(data,at+10)
		assert(known[key] and kind<=4 and (char==255 or char<stages) and rot==rot and math.abs(rot)<math.huge,"invalid forest packet value")
		local fate=if kind>0 then {kind=names[kind]} else nil
		if fate then
			if kind==1 then assert(char~=255,"missing tree char stage") end
			if kind==1 or kind==2 then fate.char=if char==255 then nil else char end
			if kind==2 then fate.rot=rot end
		end
		table.insert(rows,{key,fate})
	end;return rows
end
function Packets.pixels(rows:{any}):buffer
	assert(#rows<=Packets.PIXELS_PER_PACKET,"fire pixel packet exceeds budget")
	local out=buffer.create(#rows*5)
	for i,row in rows do buffer.writeu32(out,(i-1)*5,row[1]);buffer.writeu8(out,(i-1)*5+4,row[2]) end
	return out
end
function Packets.readPixels(data:buffer,total:number):{any}
	assert(buffer.len(data)%5==0 and buffer.len(data)<=Packets.PIXELS_PER_PACKET*5,"invalid fire pixel packet length")
	local out={}
	for at=0,buffer.len(data)-1,5 do
		local p,stage=buffer.readu32(data,at),buffer.readu8(data,at+4)
		assert(p<total and stage<=3,"invalid fire pixel packet value");table.insert(out,{p,stage})
	end
	return out
end
function Packets.points(points:{number}):buffer
	local out=buffer.create(#points*4);for i,p in points do buffer.writeu32(out,(i-1)*4,p) end;return out
end
function Packets.readPoints(data:buffer,total:number,maxPixels:number):{number}
	assert(buffer.len(data)>0 and buffer.len(data)%4==0 and buffer.len(data)<=maxPixels*4,"invalid fire roof packet length")
	local out={};for at=0,buffer.len(data)-1,4 do local p=buffer.readu32(data,at);assert(p<total,"invalid fire roof pixel");table.insert(out,p) end;return out
end
return Packets
