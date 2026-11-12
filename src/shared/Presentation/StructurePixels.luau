--!strict
--!native
-- Source construction height reveal and deterministic damage raster. Settings/art stay local.
-- APPROX: straight-alpha CPU rounding replaces Canvas2D's premultiplied pixel arithmetic.
local Pixels={}
local function round(v:number):number return math.floor(v+.5) end
local function colour(out:buffer,at:number,rgb:any,alpha:number)
	for c=0,2 do buffer.writeu8(out,at+c,math.clamp(round(rgb[c+1]),0,255)) end
	buffer.writeu8(out,at+3,math.clamp(round(alpha),0,255))
end
local function over(out:buffer,at:number,r:number,g:number,b:number,a:number)
	if a<=0 then return end
	local old=buffer.readu8(out,at+3)/255;local alpha=a+old*(1-a)
	for c=1,3 do
		local value=if c==1 then r elseif c==2 then g else b
		local dest=buffer.readu8(out,at+c-1)
		buffer.writeu8(out,at+c-1,math.clamp(round((value*a+dest*old*(1-a))/alpha),0,255))
	end
	buffer.writeu8(out,at+3,round(alpha*255))
end
function Pixels.prepare(raw:buffer,frame:number,n:number,top:number):any
	assert(frame>0 and n>0 and buffer.len(raw)==frame*frame*10+n*n*3,"invalid structure source pixels")
	return {raw=raw,frame=frame,n=n,top=top,paint=frame*frame*4,height=frame*frame*8,
		low=frame*frame*8+n*n,there=frame*frame*8+n*n*2,lowMask=frame*frame*8+n*n*3,highMask=frame*frame*9+n*n*3}
end
function Pixels.buildStep(config:any,built:number):number
	local b=math.clamp(built,0,1)
	return if b<config.slabShare then math.min(config.pourSteps-1,math.floor(b/config.slabShare*config.pourSteps))
		else config.pourSteps+math.min(config.steps-1,math.floor((b-config.slabShare)/(1-config.slabShare)*config.steps))
end
function Pixels.construction(source:any,config:any,step:number,id:number,tint:any,checkpoint:any?):buffer
	local f,n,raw=source.frame,source.n,source.raw;local out=buffer.create(f*f*4)
	local pouring=step<config.pourSteps
	local share=if pouring then (step+1)/config.pourSteps else 1
	local height=if pouring then -1 else config.ground+(step-config.pourSteps+1)/config.steps*(source.top-config.ground)
	local band=math.max(config.bandMin,source.top*config.band)
	for y=0,f-1 do
		if checkpoint then checkpoint() end
		local sy=math.min(n-1,math.floor((y+.5)*n/f))
		for x=0,f-1 do
			local sx=math.min(n-1,math.floor((x+.5)*n/f));local point=sy*n+sx
			if buffer.readu8(raw,source.there+point)==0 then continue end
			local at=(y*f+x)*4
			if pouring then
				local direction=((if id%2==1 then n-1-sx else sx)+(if math.floor(id/2)%2==1 then n-1-sy else sy))/(2*n)
				if direction<=share then colour(out,at,if direction>share-.06 then config.slabWet else config.slab,255) end
				continue
			end
			colour(out,at,config.slab,255)
			local h=buffer.readu8(raw,source.height+point);local low=buffer.readu8(raw,source.low+point)
			if h<=height then
				local a=buffer.readu8(raw,at+3)/255
				over(out,at,buffer.readu8(raw,at),buffer.readu8(raw,at+1),buffer.readu8(raw,at+2),a)
				local paint=source.paint+at
				over(out,at,buffer.readu8(raw,paint)*tint[1],buffer.readu8(raw,paint+1)*tint[2],buffer.readu8(raw,paint+2)*tint[3],buffer.readu8(raw,paint+3)/255)
				if h>config.ground and h>height-band then
					local ink=if sx%config.poleEvery==0 or sy%config.poleEvery==0 then config.pole else config.scaffold
					over(out,at,ink[1],ink[2],ink[3],round(config.scaffoldAlpha*255)/255)
				end
			elseif low<=height and h-low>=config.wallDrop then colour(out,at,config.wall,255) end
		end
	end
	return out
end
function Pixels.damageStage(config:any,previous:number,hp:number,maxHp:number):number
	local fraction=hp/math.max(1,maxHp);local stage=previous
	while stage<#config.below and fraction<config.below[stage+1] do stage+=1 end
	while stage>0 and fraction>=config.below[stage]+config.back do stage-=1 end
	return stage
end
-- Source To integer mixer; Rng.imul is injected so this module stays pure in both runtimes.
function Pixels.hash(seed:number,salt:number,imul:any):number
	local v=bit32.bxor(imul(bit32.bxor(seed,salt),2654435761),2246822507)
	v=imul(bit32.bxor(v,bit32.rshift(v,15)),739982445)
	v=imul(bit32.bxor(v,bit32.rshift(v,12)),695872825)
	return bit32.bxor(v,bit32.rshift(v,15))/4294967296
end
local function pointList(source:any,config:any,checkpoint:any?):any
	if source.points then return source.points end
	local f=source.frame;local h=math.floor(f/config.px);local raw=source.raw;local low,high,coreLow,coreHigh={},{},{},{}
	local f32=buffer.create(4)
	local function float(v:number):number buffer.writef32(f32,0,v);return buffer.readf32(f32,0) end
	local function inside(offset:number,x:number,y:number):boolean
		if x<0 or y<0 or x>=h or y>=h then return false end
		local sx=math.min(f-1,math.floor((x+.5)*config.px));local sy=math.min(f-1,math.floor((y+.5)*config.px))
		return buffer.readu8(raw,offset+sy*f+sx)>128
	end
	for y=0,h-1 do
		if checkpoint then checkpoint() end
		for x=0,h-1 do
			for _,layer in {{source.lowMask,low,coreLow},{source.highMask,high,coreHigh}} do
				if not inside(layer[1],x,y) then continue end
				local point={float((x+.5)/h),float((y+.5)/h)};table.insert(layer[2],point)
				if inside(layer[1],x-1,y) and inside(layer[1],x+1,y) and inside(layer[1],x,y-1) and inside(layer[1],x,y+1) then table.insert(layer[3],point) end
			end
		end
	end
	local tall=if #high>=12 then high elseif #low>0 then low else {{.5,.5}}
	local core=if #high>=12 then coreHigh else coreLow
	local result={low=if #low>0 then low else {{.5,.5}},tall=tall,core=if #core>=12 then core else tall,
		tallMask=if #high>=12 then source.highMask else source.lowMask,h=h}
	source.points=result;return result
end
local function dot(out:buffer,w:number,x:number,y:number,rgb:any)
	if x<0 or y<0 or x>=w or y>=w then return end;colour(out,(y*w+x)*4,rgb,255)
end
local function radial(cx:number,cy:number,radius:number,factors:{number}):any
	return function(x:number,y:number):boolean
		local dx,dy=x+.5-cx,y+.5-cy;local angle=(math.atan2(dy,dx)/(math.pi*2)+1)%1*#factors
		local i=math.floor(angle);local t=angle-i;local scale=factors[i+1]*(1-t)+factors[(i+1)%#factors+1]*t
		return math.sqrt(dx*dx+dy*dy)<=radius*scale
	end
end
local function blob(out:buffer,w:number,cx:number,cy:number,radius:number,rng:any,rgb:any,alpha:number,cfg:any)
	local factors={};for _=1,7 do table.insert(factors,1-cfg.wobble/2+cfg.wobble*rng()) end
	local reach=math.ceil(radius*(1+cfg.wobble/2))+1
	for y=math.max(0,math.floor(cy-reach)),math.min(w-1,math.ceil(cy+reach)) do for x=math.max(0,math.floor(cx-reach)),math.min(w-1,math.ceil(cx+reach)) do
		local dx,dy=x+.5-cx,y+.5-cy;local angle=(math.atan2(dy,dx)/(math.pi*2)+1)%1*7
		local i=math.floor(angle);local t=angle-i
		local distance=math.sqrt(dx*dx+dy*dy)/(radius*(factors[i+1]*(1-t)+factors[(i+1)%7+1]*t))
		if distance>1 or distance>cfg.solid and (cfg.dither[(y%4)*4+x%4+1]+.5)/16>=(1-distance)/(1-cfg.solid) then continue end
		local at=(y*w+x)*4;local a=math.max(buffer.readu8(out,at+3),round(alpha*255));colour(out,at,rgb,a)
	end end
end
local function hole(out:buffer,w:number,cx:number,cy:number,radius:number,rng:any,cfg:any)
	local factors={};for _=1,5 do table.insert(factors,.6+.8*rng()) end
	local inside=radial(cx,cy,radius,factors);local reach=math.ceil(radius*1.4)+1
	for y=math.floor(cy-reach),math.ceil(cy+reach) do for x=math.floor(cx-reach),math.ceil(cx+reach) do
		if inside(x,y) then dot(out,w,x,y,if not inside(x,y-1) or not inside(x-1,y) then cfg.colours.rim else cfg.colours.hole) end
	end end
end
local function firePoints(points:any,cells:number,defence:boolean,id:number,cfg:any,hash:any):{any}
	local core=points.core;local count=math.min(if defence then cfg.defenceSpots else cfg.spots[tostring(cells)] or 3,#core)
	local dx,dy=if hash(id,81)<.5 then -1 else 1,if hash(id,82)<.5 then -1 else 1
	local first,score=1,-math.huge
	for i,p in core do local value=(p[1]-.5)*dx+(p[2]-.5)*dy+hash(id*977+i-1,83)*.12;if value>score then first,score=i,value end end
	local chosen={core[first]}
	for nextIndex=2,count do
		local best,bestScore=1,-1
		for i,p in core do
			local distance=math.huge;for _,old in chosen do distance=math.min(distance,math.sqrt((p[1]-old[1])^2+(p[2]-old[2])^2)) end
			distance+=hash(id*613+i-1,84+nextIndex-1)*.08;if distance>bestScore then best,bestScore=i,distance end
		end;table.insert(chosen,core[best])
	end;return chosen
end
function Pixels.damage(source:any,cfg:any,stage:number,id:number,cells:number,defence:boolean,helpers:any,checkpoint:any?):buffer
	local points=pointList(source,cfg,checkpoint);local h=points.h;local low,high,cave=buffer.create(h*h*4),buffer.create(h*h*4),buffer.create(h*h*4)
	local scale=h/cells;local area=cells*cells/9;local ink=cfg.colours
	local hash=function(seed,salt) return Pixels.hash(seed,salt,helpers.imul) end
	local fire=firePoints(points,cells,defence,id,cfg.fire,hash)
	local function scatter(salt:number,count:number,locations:{any},draw:any)
		local rng=helpers.rng((id*2654435761+salt)%4294967296)
		for _=1,math.max(1,round(count*area)) do
			if checkpoint then checkpoint() end
			local p=locations[math.floor(rng()*#locations)+1]
			draw(p[1]*h+(rng()-.5)*scale*.4,p[2]*h+(rng()-.5)*scale*.4,rng)
		end
	end
	local function size(range:any,rng:any):number return (range[1]+(range[2]-range[1])*rng())*scale end
	scatter(26,cfg.sootCount[stage],points.low,function(x,y,rng) blob(low,h,x,y,size(cfg.soot,rng),rng,ink.soot,ink.sootAlpha,cfg) end)
	scatter(43,cfg.charCount[stage],points.tall,function(x,y,rng) blob(low,h,x,y,size(cfg.char,rng),rng,ink.char,1,cfg) end)
	for i=1,(if stage>=3 then #fire elseif stage>=2 then 1 else 0) do
		local rng=helpers.rng((id*40503+(i-1)*977+60)%4294967296)
		blob(low,h,fire[i][1]*h,fire[i][2]*h,cfg.char[2]*scale*(if stage>=3 then 1.25 else 1),rng,ink.char,1,cfg)
	end
	scatter(77,cfg.holeCount[stage],points.core,function(x,y,rng)
		local radius=size(cfg.hole,rng);hole(high,h,x,y,radius,rng,cfg)
		for _=1,round(cfg.rubble[1]+(cfg.rubble[2]-cfg.rubble[1])*rng()) do
			local angle=rng()*math.pi*2;local distance=radius*(1.1+(cfg.rubbleTo-1.1)*rng())
			dot(low,h,round(x+math.cos(angle)*distance),round(y+math.sin(angle)*distance),ink.rubble)
		end
	end)
	if stage>=3 then
		local c=cfg.cave;local rng=helpers.rng((id*2246822519+94)%4294967296)
		for index=1,math.max(1,round(c.count*area)) do
			if checkpoint then checkpoint() end
			local best,bestScore=1,-1
			for i,p in points.core do
				local distance=math.huge;for _,old in fire do distance=math.min(distance,math.sqrt((p[1]-old[1])^2+(p[2]-old[2])^2)) end
				distance=math.min(distance,.28)+hash(id*811+i-1,95+index-1)*.1;if distance>bestScore then best,bestScore=i,distance end
			end
			local p=points.core[best];local cx,cy=p[1]*h,p[2]*h;local radius=(c.size[1]+(c.size[2]-c.size[1])*rng())*scale/2
			local factors={};for _=1,7 do table.insert(factors,1-c.wobble/2+c.wobble*rng()) end
			local inside=radial(cx,cy,radius,factors);local reach=math.ceil(radius*(1+c.wobble/2))+1
			for y=math.floor(cy-reach),math.ceil(cy+reach) do for x=math.floor(cx-reach),math.ceil(cx+reach) do
				if not inside(x,y) then continue end
				local rgb
				if not inside(x,y-1) or not inside(x-1,y) then rgb=c.lit
				elseif not inside(x,y+1) or not inside(x+1,y) then rgb=c.shade
				else local noise=hash(math.floor(x/2)*7919+math.floor(y/2)*104729+round(cx*31),97);rgb=if noise<c.heap then c.heapInks[math.floor(noise/c.heap*#c.heapInks)+1] else ink.hole end
				dot(cave,h,x,y,rgb)
			end end
			for _=1,c.beams do
				local angle=rng()*math.pi;local offset=(rng()-.5)*radius*.8
				for along=-radius,radius,.5 do
					local x,y=round(cx-math.sin(angle)*offset+math.cos(angle)*along),round(cy+math.cos(angle)*offset+math.sin(angle)*along)
					if inside(x,y) and inside(x-1,y) and inside(x,y-1) then dot(cave,h,x,y,c.beam) end
				end
			end
			for _=1,c.spill do
				local angle=rng()*math.pi*2;local distance=radius*(1+(c.spillTo-1)*rng())
				dot(low,h,round(cx+math.cos(angle)*distance),round(cy+math.sin(angle)*distance),if rng()<.5 then ink.rubble else c.heapInks[2])
			end
		end
	end
	local f=source.frame;local out=buffer.create(f*f*4)
	local layers={low,high,cave}
	for y=0,f-1 do
		if checkpoint then checkpoint() end
		for x=0,f-1 do
			local at=(y*f+x)*4;local small=(math.min(h-1,math.floor((y+.5)*h/f))*h+math.min(h-1,math.floor((x+.5)*h/f)))*4
			for i,layer in layers do
				local mask=if i==2 then buffer.readu8(source.raw,points.tallMask+y*f+x) elseif i==3 and stage<3 then 0 else buffer.readu8(source.raw,at+3)
				local alpha=buffer.readu8(layer,small+3)/255*mask/255
				over(out,at,buffer.readu8(layer,small),buffer.readu8(layer,small+1),buffer.readu8(layer,small+2),alpha)
			end
		end
	end
	return out
end
return Pixels
