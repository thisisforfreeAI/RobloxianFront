--!strict
--!native
-- Source wet-ground colours and puddle noise/threshold. APPROX: admin weather wets the whole map;
-- rise time derives from the source front's edge duration; residual mud dries over two dry periods.
local GroundWetness={}
function GroundWetness.advance(state: any,raining: boolean,dt: number,timing: any)
	assert(dt>=0,"negative weather step")
	state.wet=math.clamp(state.wet+(if raining then dt/timing.riseSec else -dt/timing.drySec),0,1)
	state.mud=math.max(state.wet,math.max(0,state.mud-dt/(timing.drySec*2)))
end
local function hash(x:number,y:number):number
	local a,b,c=(x*.1031)%1,(y*.1030)%1,(x*.0973)%1
	local k=a*(b+33.33)+b*(c+33.33)+c*(a+33.33)
	return ((a+b+2*k)*(c+k))%1
end
local function noise(x:number,y:number):number
	local ix,iy=math.floor(x),math.floor(y)
	local fx,fy=x-ix,y-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
	local a,b,c,d=hash(ix,iy),hash(ix+1,iy),hash(ix,iy+1),hash(ix+1,iy+1)
	return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy
end
function GroundWetness.noise(w:number,h:number,scale:number,config:any):buffer
	local out=buffer.create(w*h*4)
	for y=0,h-1 do for x=0,w-1 do
		local px,py=(x+.5)/scale*3,(y+.5)/scale*3
		local k=config.puddleTexels
		buffer.writef32(out,(y*w+x)*4,noise(px/k,py/k)*.75+noise(px/(k*.41)+7.3,py/(k*.41)+7.3)*.25)
	end end
	return out
end
GroundWetness.valueNoise=noise -- shared source numerical helper for the cloud-grid pass
function GroundWetness.pixels(field:buffer,eligible:buffer,w:number,h:number,state:any,config:any,checkpoint:(()->())?):buffer
	local out=buffer.create(w*h*4)
	local from=config.puddleNone+(config.puddleFrom-config.puddleNone)*state.wet
	for i=0,w*h-1 do
		if checkpoint and i%8192==0 then checkpoint() end
		local kind=buffer.readu8(eligible,i)
		if kind==0 then continue end
		local muddy=if kind==2 then config.mud*state.mud else 0
		local dark=config.wetDark*math.max(state.wet,state.mud*.5)
		local puddle=if kind==2 and state.wet>0 and buffer.readf32(field,i*4)>from+config.puddleRim then config.puddle else 0
		local alpha=1-(1-dark)*(1-muddy)*(1-puddle)
		if alpha<=0 then continue end
		for ch=0,2 do
			local rgb=(config.mudColor[ch+1]*muddy*(1-puddle)+config.sky[ch+1]*puddle)/alpha
			buffer.writeu8(out,i*4+ch,math.clamp(math.floor(rgb*255+.5),0,255))
		end
		buffer.writeu8(out,i*4+3,math.floor(alpha*255+.5))
	end
	return out
end
return GroundWetness
