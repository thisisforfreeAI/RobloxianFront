--!strict
-- Optional precomputed source-lighted LODs. Adler signatures detect stale converted inputs;
-- these are local trusted assets, not a cryptographic authentication mechanism.
local Lods={}
local Patch=if script then require(script.Parent.TownPatch) else require("./TownPatch")
function Lods.signature(text:string,checkpoint:any?):number
	local a,b=1,0
	for start=1,#text,5552 do
		for i=start,math.min(#text,start+5551) do a+=string.byte(text,i);b+=a end
		a%=65521;b%=65521
		if checkpoint then checkpoint(math.min(#text,start+5551)) end
	end
	return b*65536+a
end
function Lods.decode(data:any,stride:number,frame:number,w:number,h:number,sourceHash:number,patchHash:number,inflate:any,baseFrame:number?,checkpoint:any?):buffer?
	if type(data)~="table" or data.format~=2 or data.stride~=stride or baseFrame and data.baseFrame~=baseFrame
		or data.width~=math.ceil(w/stride) or data.height~=math.ceil(h/stride)
		or data.sourceHash~=sourceHash or type(data.deflate)~="string" or type(data.patches)~="table" then return nil end
	local patch=data.patches[frame]
	if type(patch)~="table" or patch.sourceHash~=patchHash or type(patch.bytes)~="number" or not (patch.bytes>=0 and patch.bytes<=data.width*data.height*12 and patch.bytes%1==0) or type(patch.deflate)~="string" then return nil end
	local px=inflate(data.deflate,data.width*data.height*4)
	assert(typeof(px)=="buffer" and buffer.len(px)==data.width*data.height*4,"invalid precomputed town pixels")
	if patch.bytes>0 then Patch.apply(px,inflate(patch.deflate,patch.bytes),checkpoint) end
	return px
end
return Lods
