--!strict
-- Original Ohe.pixelAt/roof/builtNear coordinate adapter. Lazy callers choose when to decode the
-- ignored source city atlas; no native images or live match hooks are introduced here.
local FireMap={}
function FireMap.new(data:any,decode:(string,number)->buffer,load:((string)->any)?):any
	for _,key in {"width","height","tileSize","atlasWidth","atlasHeight","perRow","count"} do
		local v=data[key];assert(type(v)=="number" and v>0 and v<math.huge and v%1==0,"invalid fire map dimensions")
	end
	assert(data.perRow*data.tileSize<=data.atlasWidth,"invalid fire atlas row")
	assert(math.ceil(data.count/data.perRow)*data.tileSize<=data.atlasHeight,"invalid fire atlas height")
	local total=data.width*data.height
	local atlasBytes=data.atlasWidth*data.atlasHeight*4
	local atlas
	if data.atlasParts then
		assert(load,"missing fire atlas page loader");atlas=buffer.create(atlasBytes)
		local cursor=0
		for _,part in data.atlasParts do
			assert(part.offset==cursor and part.bytes>0 and cursor+part.bytes<=atlasBytes,"invalid fire atlas page bounds")
			local page=(load :: (string)->any)(part.name)
			local px=decode(page.deflate,part.bytes);assert(buffer.len(px)==part.bytes,"invalid fire atlas page size")
			buffer.copy(atlas,cursor,px);cursor+=part.bytes
		end
		assert(cursor==atlasBytes,"incomplete fire atlas")
	else atlas=decode(data.atlas,atlasBytes) end
	local index=decode(data.index,total*4);local cells=decode(data.cells,total);local reserved=decode(data.reserved,total)
	local towns=if data.towns then decode(data.towns,total*2) else nil
	assert(not towns or buffer.len(towns)==total*2,"invalid fire town map size")
	assert(buffer.len(atlas)==data.atlasWidth*data.atlasHeight*4 and buffer.len(index)==total*4 and buffer.len(cells)==total and buffer.len(reserved)==total,"invalid decoded fire map size")
	local self:any={width=data.width,height=data.height,tileSize=data.tileSize}
	local function tileAt(cell:number):number?
		if cell<0 or cell>=total or cell%1~=0 then return nil end
		local at=cell*4;local tile=buffer.readu8(index,at)+buffer.readu8(index,at+1)*256+buffer.readu8(index,at+2)*65536-1
		return if tile>=0 and tile<data.count then tile else nil
	end
	function self.sourceId(x:number,y:number):number?
		if x<0 or y<0 or x>=data.width*data.tileSize or y>=data.height*data.tileSize or x%1~=0 or y%1~=0 then return nil end
		local cx,cy=math.floor(x/data.tileSize),math.floor(y/data.tileSize);local tile=tileAt(cy*data.width+cx)
		if tile==nil then return nil end
		return (math.floor(tile/data.perRow)*data.tileSize+y%data.tileSize)*data.atlasWidth+tile%data.perRow*data.tileSize+x%data.tileSize
	end
	function self.original(x:number,y:number):{number}?
		local id=self.sourceId(x,y);if id==nil then return nil end
		local at=id*4;return {buffer.readu8(atlas,at),buffer.readu8(atlas,at+1),buffer.readu8(atlas,at+2),buffer.readu8(atlas,at+3)}
	end
	function self.roof(x:number,y:number):boolean
		local id=self.sourceId(x,y);return id~=nil and buffer.readu8(atlas,id*4+3)>=data.roofFrom
	end
	function self.builtAt(cell:number):boolean return cell>=0 and cell<total and cell%1==0 and buffer.readu8(cells,cell)>0 end
	function self.noFire(cell:number):boolean return cell>=0 and cell<total and cell%1==0 and buffer.readu8(reserved,cell)>0 end
	function self.townIndex(cell:number):number?
		if not towns or cell<0 or cell>=total or cell%1~=0 then return nil end
		local id=buffer.readu16(towns,cell*2);return if id>0 then id else nil
	end
	-- Context fields match HouseFire directly; callers attach a clock/RNG/rain and visual callbacks.
	return self
end
return FireMap
