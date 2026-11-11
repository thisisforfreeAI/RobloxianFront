--!strict
--!native
-- Source cloudAtCell grid and sky pass, with injected source value noise (CPU doubles).
local Clouds={}
function Clouds.share(c:any,pixels:number):number
	return math.clamp((pixels-c.hidePx)/(c.showPx-c.hidePx),0,1)
end
function Clouds.cell(c:any,x:number,y:number,noise:(number,number)->number):number
	local px,py=x/c.scale,y/c.scale
	local n=noise(px,py)*.55+noise(px*2.3+7.1,py*2.3+7.1)*.3+noise(px*4.7+13.7,py*4.7+13.7)*.15
	return ((if n>=c.cover then 1 else 0)+(if n>=c.cover+c.step then 1 else 0))*.5
end
function Clouds.density(c:any,x:number,y:number,time:number,noise:(number,number)->number):number
	return Clouds.cell(c,math.floor(x+time*c.dx),math.floor(y+time*c.dy),noise)
end
function Clouds.offset(c:any,light:any):(number,number)
	local s=light.shadow or {0,0}
	local length=math.sqrt(s[1]^2+s[2]^2)
	if length==0 then return 0,0 end
	-- Older local WorldLook data has no offset settings; preserve its unshifted fallback.
	local reach=math.min(c.shadowMax or 0,length*(c.shadowReach or 0))
	return s[1]/length*reach,s[2]/length*reach
end
function Clouds.tone(c:any,light:any,pixels:number):({number},number)
	local color={}
	for i=1,3 do
		color[i]=math.min(1,c.color[i]*light.mul[i]+light.add[i]+light.color[i]*c.golden*(light.golden or 0))
	end
	return color,c.body*Clouds.share(c,pixels)*(1-c.nightThin*light.night)
end
-- Reproject a cached world-space image every frame, independently of expensive noise repainting.
function Clouds.project(painted:any,view:any,c:any,offsetX:number?,offsetY:number?):any
	local elapsed=view.time-painted.time
	local cx,cy=painted.cx-elapsed*c.dx+(offsetX or 0),painted.cy-elapsed*c.dy+(offsetY or 0)
	return {x=.5+(cx-view.cx)/(view.rx*2),y=.5+(cy-view.cy)/(view.ry*2),
		width=painted.rx/view.rx,height=painted.ry/view.ry,
		covered=math.abs(cx-view.cx)+view.rx<=painted.rx+1e-9 and math.abs(cy-view.cy)+view.ry<=painted.ry+1e-9}
end
-- Fixed spacing and a wind-advected global lattice prevent camera-dependent resampling jitter.
-- APPROX cache policy: quarter-cell spacing increments, padded bounds for sky plus ground shadow.
function Clouds.bounds(c:any,view:any,w:number,h:number,offsetX:number,offsetY:number):any
	local extentX=view.rx*1.75+math.abs(offsetX)/2
	local extentY=view.ry*1.75+math.abs(offsetY)/2
	local step=math.max(.25,math.ceil(math.max(extentX*2/w,extentY*2/h)*4)/4)
	local field=table.clone(view)
	field.rx=w*step/2;field.ry=h*step/2
	field.cx=math.floor((view.cx-offsetX/2+view.time*c.dx)/step+.5)*step-view.time*c.dx
	field.cy=math.floor((view.cy-offsetY/2+view.time*c.dy)/step+.5)*step-view.time*c.dy
	return field
end
local function raster(c:any,w:number,h:number,view:any,noise:(number,number)->number,lift:number,rgb:{number},alpha:number):(buffer,number)
	local out=buffer.create(w*h*4)
	if alpha<=0 then return out,0 end
	local count=0
	-- Cache integer cloud-grid cells within this paint; near zoom repeats each cell many times.
	local cache:{[number]:{[number]:number}}={}
	for y=0,h-1 do
		local cy=math.floor(view.cy+((y+.5)/h-.5)*view.ry*2/lift+view.time*c.dy)
		local row=cache[cy];if not row then row={};cache[cy]=row end
		for x=0,w-1 do
			local cx=math.floor(view.cx+((x+.5)/w-.5)*view.rx*2/lift+view.time*c.dx)
			local cover=row[cx]
			if cover==nil then cover=Clouds.cell(c,cx,cy,noise);row[cx]=cover end
			local a=math.floor(alpha*cover*255+.5)
			if a<=0 then continue end
			local at=(y*w+x)*4
			for ch=0,2 do buffer.writeu8(out,at+ch,rgb[ch+1]) end
			buffer.writeu8(out,at+3,a);count+=1
		end
	end
	return out,count
end
-- One neutral density image serves the world-anchored sky AND shadow labels.
function Clouds.mask(c:any,w:number,h:number,view:any,noise:(number,number)->number):(buffer,number)
	return raster(c,w,h,view,noise,1,{255,255,255},1)
end
function Clouds.pixels(c:any,light:any,w:number,h:number,view:any,noise:(number,number)->number,parallax:number?):(buffer,number)
	local color,alpha=Clouds.tone(c,light,view.cellPixels)
	local rgb={};for i=1,3 do rgb[i]=math.clamp(math.floor(color[i]*255+.5),0,255) end
	-- nil retains source projection for independent comparisons; the runtime mask has no parallax.
	return raster(c,w,h,view,noise,1+(if parallax~=nil then parallax else c.parallax),rgb,alpha)
end
return Clouds
