--!strict
--!native
-- Source quantized height-band projection. Original masks/reaches/settings stay in ignored data.
local Shadows={}
local function round(x:number):number return math.floor(x+.5) end
function Shadows.plan(cfg:any,source:any,x:number,y:number,limit:number):any
	local strength=math.sqrt(x*x+y*y)
	local angle=round(math.atan2(y,x)/(math.pi*2)*cfg.angleSteps)
	local reach=math.max(0,round(strength/cfg.reachStep))
	local radians=angle/cfg.angleSteps*math.pi*2;local mult=reach*cfg.reachStep*cfg.shadowPerHeight
	local top=0;for _,value in source.reach do top=math.max(top,value) end
	local margin=math.ceil(top*mult)+1;local width=source.frame+margin*2
	-- APPROX native storage: retain the source canvas extent but cap a pooled raster's resolution.
	local n=math.min(limit,width)
	return {key=`{angle}:{reach}`,angle=angle,reach=reach,dx=math.cos(radians),dy=math.sin(radians),mult=mult,top=top,margin=margin,width=width,n=n,scale=n/width}
end
function Shadows.prepare(raw:buffer,meta:any,checkpoint:any?):any
	local f=meta.frame;assert(f>0 and #meta.reach==#meta.bands and buffer.len(raw)==f*f*#meta.bands,'invalid shadow masks')
	local boxes={}
	for i=1,#meta.bands do
		local x0,y0,x1,y1=f,f,0,0;local start=(i-1)*f*f
		for y=0,f-1 do
			if checkpoint then checkpoint() end
			for x=0,f-1 do if buffer.readu8(raw,start+y*f+x)>0 then x0=math.min(x0,x);x1=math.max(x1,x+1);y0=math.min(y0,y);y1=math.max(y1,y+1) end end
		end
		boxes[i]={x0,y0,x1,y1}
	end
	return {raw=raw,frame=f,boxes=boxes,meta=meta}
end
function Shadows.raster(source:any,cfg:any,plan:any,checkpoint:any?):buffer
	local n,f,scale=plan.n,source.frame,plan.scale;local alpha=buffer.create(n*n)
	for i,reach in source.meta.reach do
		if plan.top<source.meta.bands[i] then continue end
		local box=source.boxes[i];if box[3]<=box[1] or box[4]<=box[2] then continue end
		local length=reach*plan.mult;local steps=math.max(1,math.ceil(length/cfg.stepPx));local start=(i-1)*f*f
		for step=0,steps do
			local distance=length*step/steps
			local left=(plan.margin+plan.dx*distance)*scale;local top=(plan.margin+plan.dy*distance)*scale
			local x0,x1=math.max(0,math.floor(left+box[1]*scale)),math.min(n-1,math.ceil(left+box[3]*scale)-1)
			for y=math.max(0,math.floor(top+box[2]*scale)),math.min(n-1,math.ceil(top+box[4]*scale)-1) do
				if checkpoint then checkpoint() end
				local sy=math.floor((y+.5-top)/scale);if sy<box[2] or sy>=box[4] then continue end
				for x=x0,x1 do
					local at=y*n+x;local old=buffer.readu8(alpha,at);if old==255 then continue end
					local sx=math.floor((x+.5-left)/scale);if sx<box[1] or sx>=box[3] then continue end
					local a=buffer.readu8(source.raw,start+sy*f+sx);if a==0 then continue end
					buffer.writeu8(alpha,at,old+round(a*(255-old)/255))
				end
			end
		end
	end
	local out=buffer.create(n*n*4);local rgb=tonumber(string.sub(cfg.ink,2),16) or 0
	for y=0,n-1 do
		if checkpoint then checkpoint() end
		for x=0,n-1 do local a=buffer.readu8(alpha,y*n+x);if a==0 then continue end;local at=(y*n+x)*4
			buffer.writeu8(out,at,bit32.band(bit32.rshift(rgb,16),255));buffer.writeu8(out,at+1,bit32.band(bit32.rshift(rgb,8),255));buffer.writeu8(out,at+2,bit32.band(rgb,255));buffer.writeu8(out,at+3,a)
		end
	end
	return out
end
return Shadows
