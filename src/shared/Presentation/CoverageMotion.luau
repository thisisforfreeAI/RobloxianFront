--!strict
-- Planning guides from current match rules and already-filtered structure views. No sight queries.
local Motion={}
local TAU=math.pi*2
function Motion.token(config:any,definition:string,pixels:number,spacing:number):number
	local t,d=config.token,config.detail
	local n=if pixels<t.detailFrom then t.tokenFarPx else math.min(t.tokenMaxPx,math.max(t.tokenMinPx,pixels*t.tokenPerCell))
	if spacing>=0 and pixels>=t.detailFrom then n=math.max(t.tokenFloorPx,math.min(n,(spacing+2.5)*pixels)) end
	local fade=math.clamp((pixels-d.from)/d.fadePx,0,1)
	local share=if definition=="hq" then t.hqShare else t.facilityShare
	return math.floor(n*share*(t.farScale+(1-t.farScale)*fade)+.5)
end
local function coverage(rules:any,kind:string):number
	local radar=rules[`structures.{kind}.radar`] or 0
	if radar>0 then return radar end -- Current Sim.radarsOf uses base radius: city boosts/power are not ported.
	return if rules[`structures.{kind}.kind`]=="defence" then rules[`structures.{kind}.range`] or 0 else 0
end
function Motion.plan(config:any,kind:string,cx:number,cy:number,side:number,rules:any,views:any,pixels:number,project:any,width:number,height:number):any
	pixels=math.max(.001,pixels)
	local out:any={sites={}}
	local token=Motion.token(config,rules[`structures.{kind}.kind`] or "facility",pixels,rules["production.spacing"] or 0)
	for key,view in views do
		if view.kind~=kind or view.hidden or (not view.stale and view.hp and view.hp<=0) then continue end
		local x,y,z=project(view.x,view.y)
		local radius=coverage(rules,kind)*pixels
		local margin=math.max(radius+token,token*config.marker.glowShare)
		if z<=0 or x+margin<0 or y+margin<0 or x-margin>width or y-margin>height then continue end
		table.insert(out.sites,{id=view.id or key,x=x,y=y,radius=radius,token=token,own=view.side==side,distance=(view.x-cx-.5)^2+(view.y-cy-.5)^2})
	end
	table.sort(out.sites,function(a,b) if a.distance~=b.distance then return a.distance<b.distance end;return tostring(a.id)<tostring(b.id) end)
	-- APPROX bounded preview policy: the nearest twelve known same-kind sites get full guides.
	while #out.sites>12 do table.remove(out.sites) end
	local radar=rules[`structures.{kind}.radar`] or 0
	if radar>0 then local x,y,z=project(cx+.5,cy+.5);if z>0 then out.ghost={x=x,y=y,radius=radar*pixels} end end
	return out
end
function Motion.marker(config:any,token:number,wall:number):any
	local c=config.marker;local pulse=.5+.5*math.sin(wall*TAU/c.pulseSec)
	return {radius=token*c.ringShare,outer=token*c.glowShare,inner=token*c.ringShare*.55,
		rotation=wall/c.spinSec*360%360,alpha=.7+.3*pulse,glow=math.floor((.26+.14*pulse)*1000+.5)/1000}
end
-- Native frames use short chords in place of Canvas2D arc strokes. The source dash duty ratio remains.
function Motion.dashes(radius:number,dash:any,limit:number):any
	if radius<=0 then return {} end
	local circumference=TAU*radius;local period=math.max(dash[1]+dash[2],circumference/limit)
	local on=period*dash[1]/(dash[1]+dash[2]);local pieces={}
	for start=0,circumference-1e-9,period do
		local finish=math.min(circumference,start+on);local angle=(finish-start)/radius
		local steps=math.max(1,math.ceil(angle/(math.pi/8)))
		for i=0,steps-1 do
			local a=(start+(finish-start)*i/steps)/radius;local b=(start+(finish-start)*(i+1)/steps)/radius
			local x1,y1=math.cos(a)*radius,math.sin(a)*radius;local x2,y2=math.cos(b)*radius,math.sin(b)*radius
			table.insert(pieces,{x=(x1+x2)/2,y=(y1+y2)/2,length=math.sqrt((x2-x1)^2+(y2-y1)^2),rotation=math.deg(math.atan2(y2-y1,x2-x1))})
		end
	end
	return pieces
end
return Motion
