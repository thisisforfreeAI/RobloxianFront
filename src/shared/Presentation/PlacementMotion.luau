--!strict
-- Original placement wash, marching border, corner brackets, hover and known clash motion.
local Motion={}
local TAU=math.pi*2
local function round(v:number):number return math.floor(v+.5) end
function Motion.geometry(config:any,side:number,cells:number,wall:number,ok:boolean,hint:any,share:number?):any
	local s,a=config.hover,config.refused;side=math.max(1,side)
	local ink=if ok then config.ok else config.bad;local pulse=.5+.5*math.sin(wall*TAU/s.pulseSec)
	local body=math.max(1,round(round(side)*(share or 1)))
	local p:any={rects={},ink=ink,lift=body*s.liftShare+math.sin(wall*TAU/s.bobSec)*s.bobPx,offset=round((round(side)-body)/2)/side,
		jitter=if ok then 0 else round(math.sin(wall*s.jitterHz*TAU))*s.jitterPx,
		alpha=if ok then s.alpha else s.refusedAlpha,scan=wall%s.scanSec/s.scanSec,share=body/side,bodySize=body}
	local function rect(x,y,w,h,color,alpha,rotation)
		if w>0 and h>0 then table.insert(p.rects,{x=x/side,y=y/side,w=w/side,h=h/side,ink=color,alpha=alpha,rotation=rotation or 0,z=1}) end
	end
	local function line(x1,y1,x2,y2,width,color,alpha)
		if x1==x2 then rect(x1-width/2,math.min(y1,y2),width,math.abs(y2-y1),color,alpha)
		else rect(math.min(x1,x2),y1-width/2,math.abs(x2-x1),width,color,alpha) end
	end
	local function brackets(x,y,size,reach,gap,color,alpha,width)
		local r=size/2+gap
		for _,corner in {{-1,-1},{1,-1},{1,1},{-1,1}} do
			local cx,cy=x+corner[1]*r,y+corner[2]*r
			line(cx-corner[1]*reach,cy,cx,cy,width,color,alpha);line(cx,cy,cx,cy-corner[2]*reach,width,color,alpha)
		end
	end
	local rounded=round(side);rect(0,0,rounded,rounded,ink,s.wash)
	for i=1,cells-1 do local x=round(i*rounded/cells)+.5;line(x,0,x,rounded,1,ink,s.gridAlpha);line(0,x,rounded,x,1,ink,s.gridAlpha) end
	-- APPROX bounded native UI: at extreme zoom retain the dash duty ratio with <=48 dashes per edge.
	local edge=math.max(0,round(side)-1);local period=math.max(s.edgeDash[1]+s.edgeDash[2],edge/48);local on=period*s.edgeDash[1]/(s.edgeDash[1]+s.edgeDash[2])
	for i=0,3 do
		local start=(-i*edge+wall*s.marchPxPerSec)%period-period
		for at=start,edge,period do local lo,hi=math.max(0,at),math.min(edge,at+on)
			if hi<=lo then continue end
			if i==0 then line(.5+lo,.5,.5+hi,.5,2,ink,.9)
			elseif i==1 then line(.5+edge,.5+lo,.5+edge,.5+hi,2,ink,.9)
			elseif i==2 then line(.5+edge-hi,.5+edge,.5+edge-lo,.5+edge,2,ink,.9)
			else line(.5,.5+edge-hi,.5,.5+edge-lo,2,ink,.9) end
		end
	end
	brackets(side/2,side/2,side,side*s.bracketShare,4+pulse*5,ink,.9,2.5)
	for _,cell in hint.blocked or {} do
		local size=side/cells;local x=round((cell.dx+(cells-1)/2)*size);local y=round((cell.dy+(cells-1)/2)*size);local width=math.ceil(size)
		rect(x,y,width,width,config.bad,a.cellAlpha*.55)
		local period=math.max(a.hatchPx,width/24)
		for start=-width,width,period do
			local lo=math.max(0,-start);local hi=math.min(width,width-start)
			if hi>lo then local x1=x+start+lo;local y1=y+width-lo;local x2=x+start+hi;local y2=y+width-hi
				-- Diagonal frame centre follows the source clipped hatch segment.
				rect((x1+x2)/2-math.sqrt(2)*(hi-lo)/2,(y1+y2)/2-.6,math.sqrt(2)*(hi-lo),1.2,config.bad,a.cellAlpha,-45)
			end
		end
	end
	local blink=.5+.5*math.sin(wall*TAU/a.clashSec)
	local lowCount=#p.rects
	-- APPROX visual pool cap; every known collision still affects the advisory verdict.
	for i,clash in hint.clashes or {} do
		if i>8 then break end
		local size=clash.cells*side/cells;local x=side/2+clash.dx*side/cells;local y=side/2+clash.dy*side/cells
		rect(x-size/2,y-size/2,size,size,config.bad,a.clashAlpha[1]+(a.clashAlpha[2]-a.clashAlpha[1])*blink)
		local left,top=round(x-size/2)+.5,round(y-size/2)+.5;local width=round(size)-1
		line(left,top,left+width,top,2,config.bad,.95);line(left+width,top,left+width,top+width,2,config.bad,.95)
		line(left+width,top+width,left,top+width,2,config.bad,.95);line(left,top+width,left,top,2,config.bad,.95)
		brackets(x,y,size,size*s.bracketShare,3+blink*3,config.bad,.95,2)
	end
	for i=lowCount+1,#p.rects do p.rects[i].z=4 end
	return p
end
return Motion
