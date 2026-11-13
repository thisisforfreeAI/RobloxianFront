--!strict
-- Source piece order/drop poses. Source parameters are generated in ignored building metadata.
local Pieces={}
local function round(x:number):number return math.floor(x+.5) end
function Pieces.order(cfg:any,id:number,imul:any):{number}
	local count=cfg.count*cfg.count;local order={};for i=0,count-1 do order[i+1]=i end
	local n=(id+1)*cfg.seed
	for i=count-1,1,-1 do
		n=(imul(bit32.bxor(n,bit32.rshift(n,cfg.shift)),cfg.mul)+cfg.add)%4294967296
		local j=n%(i+1);order[i+1],order[j+1]=order[j+1],order[i+1]
	end
	return order
end
function Pieces.geometry(config:any,progress:number,side:number,order:{number}):any
	local c=config.pieces;local d=c.count;local total=d*d
	local scaled=math.clamp(progress,0,1)*total;local whole=math.floor(scaled);local part=scaled-whole;local size=side/d
	local result:any={tiles={},rects={}}
	local function rect(x,y,w,h,alpha)
		if w>0 and h>0 and alpha>0 then table.insert(result.rects,{x=x/side,y=y/side,w=w/side,h=h/side,alpha=alpha}) end
	end
	for i=0,math.min(total-1,whole) do
		local cell=order[i+1];local x,y=cell%d,cell//d;local active=i==whole
		local dy=if active then -size*config.site.dropShare*(1-math.min(1,part*c.liftRate))^2 else 0
		local alpha=if active then math.min(1,part*c.fadeRate) else 1
		table.insert(result.tiles,{cell=cell,col=x,row=y,x=x/d,y=y/d+dy/side,dy=dy,alpha=alpha,active=active})
		if not active then continue end
		local gx,gy,w=round(x*size)+1,round(y*size+dy)+1,round(size)-2
		local glow=alpha*config.site.pieceGlow*(1-part)
		if w>0 then rect(gx-1,gy-1,w+2,2,glow);rect(gx-1,gy+w-1,w+2,2,glow);rect(gx-1,gy+1,2,w-2,glow);rect(gx+w-1,gy+1,2,w-2,glow) end
		local edge=math.max(0,round(size)-1);local left,top=round(x*size)+.5,round(y*size)+.5
		-- APPROX bounded native path: preserve source dash duty ratio with <=48 repeats per edge.
		local period=math.max(c.scaffold[1]+c.scaffold[2],edge/48);local on=period*c.scaffold[1]/(c.scaffold[1]+c.scaffold[2])
		for k=0,3 do for at=(-k*edge)%period-period,edge,period do
			local lo,hi=math.max(0,at),math.min(edge,at+on);if hi<=lo then continue end
			if k==0 then rect(left+lo,top-.5,hi-lo,1,1)
			elseif k==1 then rect(left+edge-.5,top+lo,1,hi-lo,1)
			elseif k==2 then rect(left+edge-hi,top+edge-.5,hi-lo,1,1)
			else rect(left-.5,top+edge-hi,1,hi-lo,1) end
		end end
	end
	return result
end
-- Native integer UVs partition the original frame without overlaps/gaps, then intersect its trim.
-- APPROX versus Canvas2D fractional source rectangles; original pixels are never modified.
function Pieces.crop(r:any,frame:number,count:number,col:number,row:number):any
	local x0,y0=math.floor(col*frame/count),math.floor(row*frame/count)
	local x1,y1=math.floor((col+1)*frame/count),math.floor((row+1)*frame/count)
	x0,y0=math.max(x0,r[5]),math.max(y0,r[6]);x1,y1=math.min(x1,r[5]+r[3]),math.min(y1,r[6]+r[4])
	if x1<=x0 or y1<=y0 then return nil end
	return {sx=r[1]+x0-r[5],sy=r[2]+y0-r[6],sw=x1-x0,sh=y1-y0,x=x0/frame,y=y0/frame,w=(x1-x0)/frame,h=(y1-y0)/frame}
end
return Pieces
