--!strict
-- Owner-requested APPROX traffic upgrade. Rendered road widths/markings determine lanes;
-- headway, curb bays and FIFO junction reservations replace the source's centre-line crowding.
local Driving={}
local GAP,HEADWAY,ACCEL,BRAKE=.18,.8,1.1,3
local function approach(a:number,b:number,amount:number):number
	return if a<b then math.min(b,a+amount) else math.max(b,a-amount)
end
function Driving.new(state:any,roads:{any},look:any,traffic:any):any
	local flow:any={state=state,traffic=traffic,lines={},nodes={},waits={}}
	local function pose(line:any,s:number,offset:number,dir:number):any
		local p=traffic.sample(line,s)
		local a,b=traffic.sample(line,s-.35),traffic.sample(line,s+.35)
		local dx,dy=b.x-a.x,b.y-a.y;local norm=math.sqrt(dx*dx+dy*dy)
		if norm>1e-8 then dx/=norm;dy/=norm else dx,dy=p.dx,p.dy end
		return {x=p.x-dy*offset,y=p.y+dx*offset,dx=dx*dir,dy=dy*dir,heading=math.atan2(dy*dir,dx*dir)}
	end
	flow.pose=pose
	local lineId=0
	local segments={}
	for _,road in roads do if road.rank>=1 then
		local length=0
		for i=3,#road.pts-1,2 do length+=math.sqrt((road.pts[i]-road.pts[i-2])^2+(road.pts[i+1]-road.pts[i-1])^2) end
		if length<=.5 then continue end
		lineId+=1
		local line=state.data.lines[lineId];if not line then break end
		local kind=if road.rank>=2 then "major" elseif road.track then "track" else "minor"
		local half=look.widths[kind].half
		local cells=math.min(state.data.config.cars.cells,half*2)
		local lane=if kind=="major" then (look.look.major.lane+look.look.major.edge)/2 else half/2
		flow.lines[lineId]={lane=lane,cells=cells,parked=cells*.46+.08,half=half,junctions={}}
		for i=2,#line.cum do
			table.insert(segments,{line=lineId,ax=line.pts[i*2-3],ay=line.pts[i*2-2],bx=line.pts[i*2-1],by=line.pts[i*2],s=line.cum[i-1],length=line.cum[i]-line.cum[i-1]})
		end
	end end
	for i,a in segments do for j=i+1,#segments do
		local b=segments[j];if a.line==b.line then continue end
		local ax,ay,bx,by=a.bx-a.ax,a.by-a.ay,b.bx-b.ax,b.by-b.ay
		local cross=ax*by-ay*bx;if math.abs(cross)<1e-8 then continue end
		local ox,oy=b.ax-a.ax,b.ay-a.ay
		local ta,tb=(ox*by-oy*bx)/cross,(ox*ay-oy*ax)/cross
		if ta<0 or ta>1 or tb<0 or tb>1 then continue end
		local x,y=a.ax+ax*ta,a.ay+ay*ta
		local node=nil
		for _,n in flow.nodes do if (n.x-x)^2+(n.y-y)^2<.25 then node=n;break end end
		if not node then node={id=#flow.nodes+1,x=x,y=y,at={},radius=0,owner=nil};table.insert(flow.nodes,node) end
		node.at[a.line]=a.s+a.length*ta;node.at[b.line]=b.s+b.length*tb
		node.radius=math.max(node.radius,flow.lines[a.line].half,flow.lines[b.line].half)
	end end
	for _,node in flow.nodes do
		node.radius+=state.data.config.cars.cells*.6
		for id,s in node.at do table.insert(flow.lines[id].junctions,{s=s,node=node}) end
	end
	local bays={}
	for _,town in state.towns do for i,car in town.cars do
		local info=flow.lines[car.line];if not info then continue end
		car.flowId=town.id*100+i
		local direction=math.sign(car.b-car.a);local distance=math.abs(car.b-car.a)
		local function berth(s:number,dir:number):number
			local key=car.line..":"..math.floor(s*2+.5)..":"..dir
			local index=bays[key] or 0;bays[key]=index+1
			local shift=.25+index*(info.cells+GAP)
			for _,junction in info.junctions do
				if math.abs(junction.s-s)<junction.node.radius+info.cells then shift=math.max(shift,junction.node.radius+info.cells+index*(info.cells+GAP)) end
			end
			return s+dir*math.min(shift,math.max(0,(distance-1)*.4))
		end
		car.a=berth(car.a,direction);car.b=berth(car.b,-direction)
		car.flowSpeed=0;car.flowShown=false
	end end
	-- Original parked points can lie on a major road's centre strip. Put these at a curb,
	-- outside the junction and travelling lane, while keeping internal-street parking intact.
	for _,town in state.towns do for i,car in town.parked do
		local nearest=nil;local best=math.huge
		for id,info in flow.lines do
			local line=state.data.lines[id]
			for k=2,#line.cum do
				local ax,ay=line.pts[k*2-3],line.pts[k*2-2]
				local dx,dy=line.pts[k*2-1]-ax,line.pts[k*2]-ay
				local squared=dx*dx+dy*dy
				if squared<=0 then continue end
				local t=math.clamp(((car.x-ax)*dx+(car.y-ay)*dy)/squared,0,1)
				local distance=(car.x-ax-dx*t)^2+(car.y-ay-dy*t)^2
				if distance<best and distance<(info.half+.08)^2 then
					best=distance;nearest={id=id,s=line.cum[k-1]+t*(line.cum[k]-line.cum[k-1])}
				end
			end
		end
		if nearest then
			local info=flow.lines[nearest.id];local line=state.data.lines[nearest.id]
			local p=traffic.sample(line,nearest.s)
			local dir=if math.cos(car.heading)*p.dx+math.sin(car.heading)*p.dy>=0 then 1 else -1
			local s=nearest.s
			for _,junction in info.junctions do
				if math.abs(s-junction.s)<junction.node.radius+info.cells then s=junction.s+dir*(junction.node.radius+info.cells+i*(info.cells+GAP)) end
			end
			local at=pose(line,math.clamp(s,0,line.len),(info.lane+info.parked)*dir,dir)
			car.x,car.y,car.heading=at.x,at.y,at.heading
		end
	end end
	return flow
end
function Driving.plan(flow:any,time:number,dt:number,share:number,night:number,snap:boolean,movers:{any}?)
	local traffic,state=flow.traffic,flow.state
	local config=state.data.config.cars
	local entries,commands={},{}
	for _,town in state.towns do
		if not town.known or town.destroyed or town.integrity<=0 then continue end
		local density,_,flee=traffic.activity(town,state.data.config,time,share,night)
		for i,car in town.cars do
			local info=flow.lines[car.line];if not info then continue end
			local reset=snap or town.snap
			local scheduled,away=traffic.cycle(car,config,time)
			local active=(i-.5)/#town.cars<=density
			if reset then car.s=scheduled;car.alpha=if active and not flee then 1 else 0;car.flowShown=false end
			local target=if flee or (active and away) then car.b else car.a
			local dir=if target~=car.s then math.sign(target-car.s) else car.dir
			local pull=math.max(if car.pullA then 1-math.abs(car.s-car.a)/.9 else 0,if car.pullB then 1-math.abs(car.s-car.b)/.9 else 0,0)
			if reset then car.dir=dir;car.off=(info.lane+info.parked*pull)*dir end
			local command={speed=if flee then config.flee else config.speed,limit=math.huge,lane=info.lane,parked=info.parked,cells=info.cells,pose=flow.pose,hide=false}
			commands[car]=command
			if active or car.alpha>0 then
				local p=flow.pose(state.data.lines[car.line],car.s,car.off,dir)
				table.insert(entries,{car=car,info=info,command=command,pose=p,dir=dir,target=target,id=car.flowId})
			end
		end
	end
	table.sort(entries,function(a,b) return if a.car.flowShown~=b.car.flowShown then a.car.flowShown else a.id<b.id end)
	local accepted={}
	for _,e in entries do
		if not e.car.flowShown then
			for _,other in accepted do
				local dx,dy=e.pose.x-other.pose.x,e.pose.y-other.pose.y
				if dx*dx+dy*dy<((e.info.cells+other.info.cells)*.5+GAP)^2 then e.command.hide=true;break end
			end
		end
		if not e.command.hide then table.insert(accepted,e) end
	end
	for _,e in accepted do
		local look=flow.pose(state.data.lines[e.car.line],e.car.s+e.dir*config.waitCells,e.info.lane*e.dir,e.dir)
		for _,unit in movers or {} do
			if (unit.x-look.x)^2+(unit.y-look.y)^2<(config.waitCells*.7)^2 then e.command.limit=0;e.command.speed=0;break end
		end
		for _,other in accepted do if other~=e then
			local dx,dy=other.pose.x-e.pose.x,other.pose.y-e.pose.y
			local ahead=dx*e.pose.dx+dy*e.pose.dy
			local side=math.abs(dx*e.pose.dy-dy*e.pose.dx)
			if ahead>0 and side<(e.info.cells+other.info.cells)*.23+.04 then
				local gap=(e.info.cells+other.info.cells)*.5+GAP
				e.command.limit=math.min(e.command.limit,math.max(0,ahead-gap))
				e.command.speed=math.min(e.command.speed,math.max(0,(ahead-gap)/HEADWAY))
			end
		end end
	end
	-- A junction admits one car at a time, in arrival order, and only when its exit is clear.
	for _,node in flow.nodes do
		local requests={};local owner=nil
		for _,e in accepted do
			local s=node.at[e.car.line]
			if s then
				local ahead=(s-e.car.s)*e.dir
				local reaches=(e.target-e.car.s)*e.dir>=ahead+node.radius+e.info.cells*.5
				if ahead>=-node.radius-e.info.cells and ahead<=node.radius+3 and (reaches or math.abs(ahead)<node.radius) then
					local key=node.id..":"..e.id
					flow.waits[key]=flow.waits[key] or time
					table.insert(requests,{e=e,ahead=ahead,key=key,at=flow.waits[key]})
					if node.owner==e.id and (e.command.limit>.01 or math.abs(ahead)<node.radius) then owner=e end
				else flow.waits[node.id..":"..e.id]=nil end
			end
		end
		if not owner then node.owner=nil end
		if not node.owner then
			table.sort(requests,function(a,b) return if a.at==b.at then a.e.id<b.e.id else a.at<b.at end)
			for _,r in requests do
				local e=r.e
				local exit=flow.pose(state.data.lines[e.car.line],node.at[e.car.line]+e.dir*(node.radius+e.info.cells+GAP),e.info.lane*e.dir,e.dir)
				local clear=true
				for _,other in accepted do if other~=e and (other.pose.x-exit.x)^2+(other.pose.y-exit.y)^2<(e.info.cells+GAP)^2 then clear=false;break end end
				if clear and (e.command.limit>.01 or math.abs(r.ahead)<node.radius) then node.owner=e.id;break end
			end
		end
		for _,r in requests do if r.e.id~=node.owner and r.ahead>0 then
			r.e.command.limit=math.min(r.e.command.limit,math.max(0,r.ahead-node.radius))
		end end
	end
	for _,e in entries do
		local c=e.command
		local desired=math.min(c.speed,c.limit/math.max(dt,.001))
		e.car.flowSpeed=approach(e.car.flowSpeed or 0,desired,(if desired<(e.car.flowSpeed or 0) then BRAKE else ACCEL)*dt)
		c.speed=e.car.flowSpeed
	end
	state.driving=commands
end
function Driving.finish(flow:any)
	for car,command in flow.state.driving or {} do car.flowShown=car.alpha>.02 and not command.hide end
end
return Driving
