--!strict
-- Source BJt.hang/drawSky wire geometry. Generated nodes retain original Float32 axes/seed phases.
local Power={}
function Power.motion(weather:string):number
	-- APPROX owner override: the original wind runs in dry weather too.
	return if weather=="downpour" or weather=="rain" or weather=="storm" then 1 else 0
end
function Power.style(config:any,pixels:number):(number,number)
	local c=config.wireLook
	local near=math.clamp((pixels-c.from)/(c.to-c.from),0,1)
	return math.max(c.minPx,pixels*config.look.wire.px*c.wire),c.alpha*(c.far+(1-c.far)*near)
end
function Power.hang(a:any,b:any,index:number,flip:boolean,look:any):any
	if a.plant then
		local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx^2+dy^2);if length==0 then length=1 end
		local side=if index==0 then -1 elseif index==1 then 1 else 0
		return {x=a.x+dx/length*look.portal.out-dy/length*look.portal.arm*side,y=a.y+dy/length*look.portal.out+dx/length*look.portal.arm*side,h=look.portal.height}
	end
	local c=if a.steel then look.pylon else look.pole
	local side=(if index==0 then -1 elseif index==1 then 1 else 0)*(if flip then -1 else 1)
	return {x=a.x+a.ax*c.arm*side,y=a.y+a.ay*c.arm*side,h=if a.steel and index==2 then c.height else c.armAt}
end
function Power.curves(data:any,link:any,time:number,pixels:number,motion:number?,quality:number?):{any}
	local a,b=data.nodes[link.a],data.nodes[link.b]
	local look=data.config.look;local near=pixels>=look.towersFrom
	if not near and not a.steel and pixels<2.2 then return {} end
	local count=if a.steel and (b.steel or b.plant) then 3 else 2
	local flip=not b.plant and a.ax*b.ax+a.ay*b.ay<0
	local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx^2+dy^2);if length==0 then length=1 end
	local clock=math.floor(time*data.config.fps)/data.config.fps
	local sway=if near then math.sin(clock/look.wire.swaySec*math.pi*2+a.phase)*look.wire.sway*(if motion==nil then 1 else motion) else 0
	local steps=if near then math.min(look.wire.steps,quality or look.wire.steps) else 2
	local paths={}
	for k=if near then 0 else 2,if near then count-1 else 2 do
		local from,to=Power.hang(a,b,k,false,look),Power.hang(b,a,k,flip,look)
		local sag=math.min(look.wire.sagMax,math.sqrt((to.x-from.x)^2+(to.y-from.y)^2)*look.wire.sag)
		local path={}
		for i=0,steps do
			local t=i/steps;local bow=4*t*(1-t)
			table.insert(path,{x=from.x+(to.x-from.x)*t-dy/length*sway*bow,y=from.y+(to.y-from.y)*t+dx/length*sway*bow,h=from.h+(to.h-from.h)*t-sag*bow})
		end
		table.insert(paths,path)
	end
	return paths
end
-- Clip at fog cells, then merge straight visible runs inside one non-overlapping GUI tile.
-- This avoids deleting an entire long stroke just because an endpoint is hidden.
function Power.sections(a:any,b:any,visible:(number,number)->boolean,tileSize:number):{any}
	local dx,dy=b.x-a.x,b.y-a.y
	if dx*dx+dy*dy<1e-16 then return {} end
	local cuts={0,1}
	local function crosses(from:number,to:number,delta:number)
		if math.abs(delta)<1e-10 then return end
		for edge=math.floor(math.min(from,to))+1,math.ceil(math.max(from,to))-1 do
			local t=(edge-from)/delta;if t>1e-9 and t<1-1e-9 then table.insert(cuts,t) end
		end
	end
	crosses(a.x,b.x,dx);crosses(a.y,b.y,dy);table.sort(cuts)
	local out={};local previous=0
	for _,at in cuts do
		if at-previous<=1e-9 then continue end
		local mid=(previous+at)/2;local mx,my=a.x+dx*mid,a.y+dy*mid
		if visible(mx,my) then
			local tx,ty=math.floor(mx/tileSize),math.floor(my/tileSize)
			local from,to={x=a.x+dx*previous,y=a.y+dy*previous},{x=a.x+dx*at,y=a.y+dy*at}
			local last=out[#out]
			if last and last.tx==tx and last.ty==ty and math.abs(last.b.x-from.x)+math.abs(last.b.y-from.y)<1e-8 then last.b=to
			else table.insert(out,{a=from,b=to,tx=tx,ty=ty}) end
		end
		previous=at
	end
	return out
end
function Power.shadow(data:any,link:any,sun:{number}):{any}
	local a,b=data.nodes[link.a],data.nodes[link.b];local look=data.config.look
	local from,to=Power.hang(a,b,2,false,look),Power.hang(b,a,2,false,look)
	local sag=math.min(look.wire.sagMax,math.sqrt((to.x-from.x)^2+(to.y-from.y)^2)*look.wire.sag)
	local out={}
	for i=0,4 do
		local t=i/4;local height=from.h+(to.h-from.h)*t-4*sag*t*(1-t)
		table.insert(out,{x=from.x+(to.x-from.x)*t+sun[1]*look.wire.shadowReach*height,y=from.y+(to.y-from.y)*t+sun[2]*look.wire.shadowReach*height})
	end
	return out
end
return Power
