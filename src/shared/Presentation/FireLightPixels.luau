--!strict
--!native
-- Source world-anchored Bayer light lookup, float32 accumulation, knee and color-dodge encoding.
-- Native rendering uses the same HDR/alpha approximation as NightLightPixels instead of CSS blending.
local Pixels={ENERGY=4}
function Pixels.lookup(config:any,mix:number):any
	local nv=config.nv;local useNV=mix>=nv.tableFrom;local bands=if useNV then nv.bands else config.light.bands
	local dither=if useNV then nv.dither else config.light.dither;local falloff=if useNV then nv.falloff else config.light.falloff
	local size=config.lookupSize;local out=buffer.create(size*16)
	for p=0,15 do for i=0,size-1 do
		local strength=(1-math.sqrt((i+.5)/size))^falloff
		buffer.writeu8(out,p*size+i,math.clamp(math.floor(strength*bands+.5+((config.bayer[p+1]+.5)/16-.5)*dither),0,bands))
	end end
	return {pixels=out,bands=bands}
end
function Pixels.paint(config:any,lights:{any},x0:number,y0:number,cw:number,ch:number,scale:number,mix:number,lookup:any,visible:any?):buffer
	local w,h=cw*scale,ch*scale;local ox,oy=x0*scale,y0*scale;local acc=buffer.create(w*h*12)
	local nv=config.nv;local reachGain=1+(nv.reach-1)*mix;local powerGain=1+(nv.power-1)*mix;local neutral=nv.neutral*mix
	for _,p in lights do
		local reach=p.reach*reachGain;local power=p.power*powerGain;if reach<=0 or power<=.01 then continue end
		local xmin,xmax=math.max(0,math.floor((p.x-reach)*scale)-ox),math.min(w-1,math.ceil((p.x+reach)*scale)-ox)
		local ymin,ymax=math.max(0,math.floor((p.y-reach)*scale)-oy),math.min(h-1,math.ceil((p.y+reach)*scale)-oy)
		local radii=reach*reach;local indexScale=config.lookupSize/radii
		local rgb={};for c=1,3 do rgb[c]=(p.color[c]+(1-p.color[c])*neutral)*power/lookup.bands end
		for y=ymin,ymax do
			local py=oy+y;local dy=(py+.5)/scale-p.y;local yy=dy*dy;if yy>=radii then continue end
			for x=xmin,xmax do
				local px=ox+x;local dx=(px+.5)/scale-p.x;local distance=dx*dx+yy;if distance>=radii then continue end
				if visible and not visible((px+.5)/scale,(py+.5)/scale) then continue end
				local amount=buffer.readu8(lookup.pixels,((py%4)*4+px%4)*config.lookupSize+math.floor(distance*indexScale));if amount==0 then continue end
				local at=(y*w+x)*12
				for c=0,2 do buffer.writef32(acc,at+c*4,buffer.readf32(acc,at+c*4)+amount*rgb[c+1]) end
			end
		end
	end
	local out=buffer.create(w*h*4);local knee=config.light.knee+(nv.knee-config.light.knee)*mix
	local tail=config.light.ceiling+(nv.ceiling-config.light.ceiling)*mix-knee
	for i=0,w*h-1 do
		local rgb={};local sum=0
		for c=0,2 do local value=buffer.readf32(acc,i*12+c*4);if value>knee then value=knee+tail*(1-math.exp(-(value-knee)/tail)) end;rgb[c+1]=value;sum+=value end
		if sum<=.004 then continue end
		for c=0,2 do
			local value=rgb[c+1]/(1+rgb[c+1])*255;local whole=math.floor(value);local fraction=value-whole
			-- Uint8ClampedArray uses ties-to-even.
			buffer.writeu8(out,i*4+c,whole+(if fraction>.5 or fraction==.5 and whole%2==1 then 1 else 0))
		end;buffer.writeu8(out,i*4+3,255)
	end;return out
end
function Pixels.native(source:buffer):buffer
	local out=buffer.create(buffer.len(source))
	for at=0,buffer.len(source)-1,4 do
		local peak=math.max(buffer.readu8(source,at),buffer.readu8(source,at+1),buffer.readu8(source,at+2));if peak==0 then continue end
		for c=0,2 do buffer.writeu8(out,at+c,math.floor(buffer.readu8(source,at+c)/peak*255+.5)) end
		buffer.writeu8(out,at+3,math.floor(peak/Pixels.ENERGY+.5))
	end;return out
end
return Pixels
