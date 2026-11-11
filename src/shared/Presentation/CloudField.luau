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
function Clouds.pixels(c:any,light:any,w:number,h:number,view:any,noise:(number,number)->number):(buffer,number)
	local out=buffer.create(w*h*4)
	local color,alpha=Clouds.tone(c,light,view.cellPixels)
	if alpha<=0 then return out,0 end
	local rgb={};for i=1,3 do rgb[i]=math.clamp(math.floor(color[i]*255+.5),0,255) end
	local count=0
	-- Cache integer cloud-grid cells within this paint; near zoom repeats each cell many times.
	local cache:{[number]:{[number]:number}}={}
	for y=0,h-1 do
		local cy=math.floor(view.cy+((y+.5)/h-.5)*view.ry*2/(1+c.parallax)+view.time*c.dy)
		local row=cache[cy];if not row then row={};cache[cy]=row end
		for x=0,w-1 do
			local cx=math.floor(view.cx+((x+.5)/w-.5)*view.rx*2/(1+c.parallax)+view.time*c.dx)
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
return Clouds
