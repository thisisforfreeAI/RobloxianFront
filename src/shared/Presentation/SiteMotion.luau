--!strict
-- Source construction-site geometry/timing. Original style parameters remain in local metadata.
local Motion={}
local function round(value:number):number return math.floor(value+.5) end
function Motion.observe(previous:any,built:number,visible:boolean,wall:number,initial:boolean?):any
	if not visible then return {built=built,hidden=true,placed=-math.huge,done=-math.huge} end
	if not previous or previous.hidden then
		return {built=built,placed=if not initial and not previous and built<.05 then wall else -math.huge,done=-math.huge}
	end
	return {built=built,placed=previous.placed,done=if previous.built<1 and built>=1 then wall else previous.done}
end
function Motion.raise(built:number,yard:number):number?
	return if built<yard then nil else math.min(1,(built-yard)/math.max(1e-6,1-yard))
end
function Motion.geometry(config:any,state:any,side:number,cells:number,wall:number):any
	local result:any={rects={},active=false}
	if not state or state.hidden or side<1 then return result end
	local function rect(x,y,w,h,ink,alpha,z)
		if w>0 and h>0 and alpha>0 then table.insert(result.rects,{x=x/side,y=y/side,w=w/side,h=h/side,ink=ink,alpha=alpha,z=z or 1}) end
	end
	local function border(x,y,w,ink,alpha,width,z)
		rect(x-width/2,y-width/2,w+width,width,ink,alpha,z);rect(x-width/2,y+w-width/2,w+width,width,ink,alpha,z)
		rect(x-width/2,y+width/2,width,math.max(0,w-width),ink,alpha,z);rect(x+w-width/2,y+width/2,width,math.max(0,w-width),ink,alpha,z)
	end
	if state.built<1 then
		result.active=true;result.blueprint=config.site.blueprintAlpha
		for i=1,cells-1 do local at=round(i*side/cells)+.5;rect(at-.5,0,1,side,config.accent,config.site.gridAlpha);rect(0,at-.5,side,1,config.accent,config.site.gridAlpha) end
		local p=config.site.pegPx;local alpha=.75+.25*math.sin(wall*1000/180)
		for _,corner in {{0,0},{1,0},{0,1},{1,1}} do rect(round(corner[1]*side)-p/2,round(corner[2]*side)-p/2,p,p,config.accent,alpha,3) end
		if Motion.raise(state.built,config.yardShare)==nil then
			local phase=wall%config.site.laserSec/config.site.laserSec
			result.laser={y=(round(side*(if phase<.5 then phase*2 else 2-phase*2))-1)/side,h=2/side,alpha=config.site.laserAlpha}
			local survey=config.survey;local inset=side/cells/4;local x=round(inset)+.5;local w=round(side-inset*2)-1
			-- APPROX native UI pool: retain dash ratio but cap each edge at 48 dashes when extremely close.
			local period=math.max(survey.dash[1]+survey.dash[2],math.max(1,w)/48);local on=period*survey.dash[1]/(survey.dash[1]+survey.dash[2])
			for edge=0,3 do
				local start=-(edge*w)%period-period
				for at=start,w,period do
					local lo,hi=math.max(0,at),math.min(w,at+on)
					if edge==0 then rect(x+lo,x-.5,hi-lo,1,survey.ink,survey.alpha,5)
					elseif edge==1 then rect(x+w-.5,x+lo,1,hi-lo,survey.ink,survey.alpha,5)
					elseif edge==2 then rect(x+w-hi,x+w-.5,hi-lo,1,survey.ink,survey.alpha,5)
					else rect(x-.5,x+w-hi,1,hi-lo,survey.ink,survey.alpha,5) end
				end
			end
			local gap=(side-inset*2)/cells;local peg=survey.pegPx
			for i=0,cells do for _,point in {{inset+i*gap,inset},{inset+i*gap,side-inset},{inset,inset+i*gap},{side-inset,inset+i*gap}} do
				rect(round(point[1]-peg/2),round(point[2]-peg/2),peg,peg,survey.ink,1,5)
			end end
		end
		local age=wall-state.placed
		if age>=0 and age<config.drop.sec then
			local share=age/config.drop.sec;result.drop={lift=-config.hover.liftShare*(1-share*share),alpha=config.hover.alpha*(1-share)}
		end
		if age>=0 and age<config.drop.ringSec then
			local n=age/config.drop.ringSec;local reach=side*config.drop.ringGrow*(1-(1-n)^2)
			border(-reach/2,-reach/2,side+reach,config.ok,(1-n)*config.drop.flash,3*(1-n)+1,6)
		end
	else
		local age=wall-state.done
		if age>=0 and age<config.done.sec then
			result.active=true;local n=age/config.done.sec;local reach=side*config.done.ringGrow*n
			result.done={center=(-.28+n*(2+config.done.band*2))/2,band=config.done.band,alpha=config.done.glow*(1-n*.5)}
			border(-reach/2,-reach/2,side+reach,config.accent,(1-n)*.8,2,8)
		end
	end
	return result
end
-- A clipped triangular gradient, expressed without duplicate native sequence key times.
function Motion.gradient(center:number,band:number):any
	local points={0,1,math.clamp(center-band/2,0,1),math.clamp(center,0,1),math.clamp(center+band/2,0,1)}
	table.sort(points);local out={}
	for _,point in points do if not out[#out] or out[#out][1]~=point then table.insert(out,{point,math.clamp(1-math.abs(point-center)/(band/2),0,1)}) end end
	return out
end
return Motion
