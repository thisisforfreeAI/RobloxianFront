--!strict
-- Source ground scar tones, applied to fresh tree-free town pixels before forest composition.
-- Roof pixels retain their separate source char/ruin treatment; transparency is preserved.
local Pixels={}
function Pixels.apply(px:buffer,cx:number,cy:number,cw:number,ch:number,tile:number,width:number,cells:any,config:any,roof:any,tones:any?)
	local w,h=cw*tile,ch*tile;assert(buffer.len(px)==w*h*4,"invalid town scorch dimensions")
	local palette={}
	local function color(tone:number):{number}
		if palette[tone] then return palette[tone] end
		local entry=if config.palette then config.palette[tone+1] else nil
		local hex=tonumber(string.sub(if entry then entry.color else config.color,2),16);assert(hex,"invalid scorch color")
		local rgb={bit32.extract(hex,16,8),bit32.extract(hex,8,8),bit32.extract(hex,0,8)};palette[tone]=rgb;return rgb
	end
	for cell,value in cells do
		local x,y=cell%width,math.floor(cell/width)
		if x<cx or y<cy or x>=cx+cw or y>=cy+ch then continue end
		local rgb=color(if tones then tones[cell] or 0 else 0)
		local amount=math.min(1,value/255*config.darken)
		for py=0,tile-1 do for pxx=0,tile-1 do
			local gx,gy=x*tile+pxx,y*tile+py
			if roof(gx,gy) then continue end
			local at=(((y-cy)*tile+py)*w+(x-cx)*tile+pxx)*4
			if buffer.readu8(px,at+3)==0 then continue end
			for channel=0,2 do
				local before=buffer.readu8(px,at+channel)
				buffer.writeu8(px,at+channel,math.clamp(math.floor(before+(rgb[channel+1]-before)*amount+.5),0,255))
			end
		end end
	end
end
return Pixels
