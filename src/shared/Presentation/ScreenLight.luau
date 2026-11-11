--!strict
--!native
-- Source sun-side wash, shade-side falloff and vignette. APPROX: source additive highlights
-- use an alpha-blended light-colour wash in Roblox; the original ground-only shader is screen-wide.
local ScreenLight={}
function ScreenLight.pixels(config: any,light: any,w: number,h: number,view:any?,noise:((number,number)->number)?,clouds:any?): buffer
	local out=buffer.create(w*h*4)
	local night,golden=light.night,light.golden or 0
	local wash=(config.wash.noon+(config.wash.golden-config.wash.noon)*golden)*(1-night)+config.wash.moon*night*(light.elevation or 0)
	local strength=config.vignette+config.vignetteNight*night
	local cloudX,cloudY,cloudStrength=0,0,0
	if view and noise and clouds and night<1 then
		cloudX,cloudY=clouds.offset(config.cloud,light)
		cloudStrength=config.cloud.shadow*(1-night)*clouds.share(config.cloud,view.cellPixels)
	end
	for y=0,h-1 do for x=0,w-1 do
		local qx,qy=(x+.5)/w-.5,(y+.5)/h-.5
		local side=math.clamp(qx*light.toward[1]+qy*light.toward[2]+.5,0,1)
		local t=math.clamp((math.sqrt(qx*qx+qy*qy)*math.sqrt(2)-config.vignetteFrom)/(1-config.vignetteFrom),0,1)
		local vignette=t*t*(3-2*t)*strength
		local highlight=wash*side*side
		local shade=wash*config.wash.shade*(1-side)
		local cloud=0
		if view and noise and clouds and cloudStrength>0 then
			cloud=clouds.density(config.cloud,view.cx+qx*view.rx*2-cloudX,view.cy+qy*view.ry*2-cloudY,view.time,noise)*cloudStrength
		end
		local alpha=1-(1-highlight)*(1-shade)*(1-vignette)*(1-cloud)
		local at=(y*w+x)*4
		if alpha>0 then
			for ch=0,2 do buffer.writeu8(out,at+ch,math.clamp(math.floor(light.color[ch+1]*highlight*(1-vignette)/alpha*255+.5),0,255)) end
			buffer.writeu8(out,at+3,math.floor(alpha*255+.5))
		end
	end end
	return out
end
return ScreenLight
