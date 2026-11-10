--!strict
--!native
-- Source window selection/flicker and combined road/pool/city emission. Original map fields/settings
-- are generated locally. APPROX: quantized field masks and an HDR alpha layer replace additive GLSL.
local Lights={}
Lights.ENERGY=4 -- Rendering policy: high-energy/low-alpha layer approximates additive light.
function Lights.prepare(fields:buffer,w:number,h:number,config:any,hash:(number,number)->number,checkpoint:(()->())?):any
	assert(buffer.len(fields)==w*h*4,"night field dimensions differ")
	local indices,phases=buffer.create(w*h*4),buffer.create(w*h*4)
	local count=0
	for i=0,w*h-1 do
		if checkpoint and i%8192==0 then checkpoint() end
		if buffer.readu32(fields,i*4)==0 then continue end
		local phase=-1
		if buffer.readu8(fields,i*4)~=0 then
			local x,y=i%w,math.floor(i/w)
			local value=hash(x*.613+7.7,y*.613+7.7)
			if value<config.windows then phase=value*31 end
		end
		if phase<0 and buffer.readu8(fields,i*4+1)==0 and buffer.readu8(fields,i*4+2)==0 and buffer.readu8(fields,i*4+3)==0 then continue end
		buffer.writeu32(indices,count*4,i);buffer.writef32(phases,count*4,phase);count+=1
	end
	local compact,compactPhases=buffer.create(count*4),buffer.create(count*4)
	buffer.copy(compact,0,indices,0,count*4);buffer.copy(compactPhases,0,phases,0,count*4)
	local slots=buffer.create(count*4);buffer.fill(slots,0,255)
	return {fields=fields,w=w,h=h,count=count,indices=compact,phase=compactPhases,slots=slots,on=buffer.create(count)}
end
function Lights.paint(state:any,config:any,clock:number,near:number,divisor:number,hash:(number,number)->number,checkpoint:(()->())?,windowGain:number?):buffer
	assert(divisor==1 or divisor==2,"unsupported light resolution")
	local width,height=math.ceil(state.w/divisor),math.ceil(state.h/divisor)
	local out=buffer.create(width*height*4)
	near=math.clamp(near,0,1)
	local road=(config.lamps.far+(config.lamps.glow-config.lamps.far)*near)*config.roadGlow
	for n=0,state.count-1 do
		if checkpoint and n%2048==0 then checkpoint() end
		local index=buffer.readu32(state.indices,n*4)
		local x,y=index%state.w,math.floor(index/state.w)
		local phase=buffer.readf32(state.phase,n*4)
		local window=0
		if phase>=0 then
			local slot=math.floor(clock/config.flickerSec+phase)
			if slot~=buffer.readu32(state.slots,n*4) then
				buffer.writeu32(state.slots,n*4,slot)
				buffer.writeu8(state.on,n,if hash(x+slot,y+slot)>.1 then 1 else 0)
			end
			window=buffer.readu8(state.on,n)
		end
		local at=index*4
		local amount=window*buffer.readu8(state.fields,at)/255*(windowGain or 1)+buffer.readu8(state.fields,at+1)/255*road+buffer.readu8(state.fields,at+2)/255*near+buffer.readu8(state.fields,at+3)/255*config.glow
		if amount<=0 then continue end
		local target=(math.floor(y/divisor)*width+math.floor(x/divisor))*4
		local alpha=math.floor(amount/Lights.ENERGY*255/(divisor*divisor)+.5)
		if alpha>0 then
			buffer.writeu8(out,target,255);buffer.writeu8(out,target+1,255);buffer.writeu8(out,target+2,255)
			buffer.writeu8(out,target+3,math.min(255,buffer.readu8(out,target+3)+alpha))
		end
	end
	return out
end
function Lights.compensate(profile:any,color:{number}):any
	-- APPROX linear inverse of the existing post-effect adapter. Roblox tone mapping/colour space
	-- still requires Studio comparison. Source emission is added AFTER its night palette/contrast.
	local values,peak={},1
	for i=1,3 do values[i]=color[i]/math.max(.01,profile.tint[i]*(1+profile.contrast));peak=math.max(peak,values[i]) end
	return {color={values[1]/peak,values[2]/peak,values[3]/peak},brightness=math.min(1000,Lights.ENERGY*peak)}
end
return Lights
