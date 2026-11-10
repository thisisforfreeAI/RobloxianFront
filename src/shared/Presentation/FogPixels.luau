--!strict
--!native
-- APPROX adapter for the source's Canvas blur(2.4 cells): separable finite Gaussian, bilinear GUI.
-- The unfiltered visibility mask is kept separately for entity hiding.
local FogPixels = {}
function FogPixels.soften(mask: buffer,w: number,h: number,dark: number): buffer
	local radius,sigma = 8,2.4 -- traced N0.featherCells; source pads to three blur radii
	local weights,total = {},0
	for i=-radius,radius do local weight=math.exp(-i*i/(2*sigma*sigma));weights[i]=weight;total+=weight end
	for i=-radius,radius do weights[i]/=total end
	local tmp,out = buffer.create(w*h*4),buffer.create(w*h*4)
	for y=0,h-1 do for x=0,w-1 do
		local value=0
		for i=-radius,radius do value+=(1-buffer.readu8(mask,y*w+math.clamp(x+i,0,w-1)))*weights[i] end
		buffer.writef32(tmp,(y*w+x)*4,value)
	end end
	for y=0,h-1 do for x=0,w-1 do
		local value=0
		for i=-radius,radius do value+=buffer.readf32(tmp,(math.clamp(y+i,0,h-1)*w+x)*4)*weights[i] end
		buffer.writeu8(out,(y*w+x)*4+3,math.clamp(math.floor(value*dark+0.5),0,255))
	end end
	return out
end
function FogPixels.colour(mask: buffer,terrain: buffer,seen: buffer,names: {string},profile: any,w: number,h: number,cache: any?): buffer
	local state=cache or {}
	local raw=state.raw or buffer.create(w*h*4)
	local out=state.out or buffer.create(w*h*4)
	state.raw,state.out=raw,out
	local x0,y0,x1,y1=w,h,-1,-1
	for i=0,w*h-1 do
		local value=0
		if buffer.readu8(mask,i)==1 then buffer.writeu8(seen,i,1)
		else
			local explored=buffer.readu8(seen,i)==1
			local color=if explored then profile.seen.rgb else profile.chart[names[buffer.readu8(terrain,i)+1]] or profile.rgb
			local alpha=if explored then profile.seen.alpha else profile.alpha
			value=math.floor(color[1]*alpha+0.5)+math.floor(color[2]*alpha+0.5)*256+math.floor(color[3]*alpha+0.5)*65536+math.floor(alpha*255+0.5)*16777216
		end
		if buffer.readu32(raw,i*4)~=value then
			buffer.writeu32(raw,i*4,value)
			local x,y=i%w,math.floor(i/w)
			x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x),math.max(y1,y)
		end
	end
	if x1<0 then return out end
	-- Blur premultiplied RGBA together, as Canvas does; this avoids black/grey fringes around
	-- the clear region and blends neighbouring terrain chart colours. Detection is untouched.
	local sigma=profile.featherCells
	local radius=math.ceil(sigma*3)
	x0,y0,x1,y1=math.max(0,x0-radius),math.max(0,y0-radius),math.min(w-1,x1+radius),math.min(h-1,y1+radius)
	local weights,total={},0
	for i=-radius,radius do local weight=math.exp(-i*i/(2*sigma*sigma));weights[i]=weight;total+=weight end
	for i=-radius,radius do weights[i]/=total end
	local tmp=state.tmp or buffer.create(w*h*4)
	state.tmp=tmp
	for _,ch in {3,0,1,2} do
		for y=math.max(0,y0-radius),math.min(h-1,y1+radius) do for x=x0,x1 do
			local value=0
			for k=-radius,radius do value+=buffer.readu8(raw,(y*w+math.clamp(x+k,0,w-1))*4+ch)*weights[k] end
			buffer.writef32(tmp,(y*w+x)*4,value)
		end end
		for y=y0,y1 do for x=x0,x1 do
			local value=0
			for k=-radius,radius do value+=buffer.readf32(tmp,(math.clamp(y+k,0,h-1)*w+x)*4)*weights[k] end
			local at=(y*w+x)*4
			if ch~=3 then
				local alpha=buffer.readu8(out,at+3)
				value=if alpha>0 then value*255/alpha else 0
			end
			buffer.writeu8(out,at+ch,math.clamp(math.floor(value+0.5),0,255))
		end end
	end
	return out
end
return FogPixels
