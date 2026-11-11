--!strict
-- Original Dtt/tQt column sampling and appearance. Rows carry visible actors, never hidden routes.
local Column={}
function Column.sample(path:{number},w:number,at:number):any
	local function point(t:number):(number,number)
		t=math.clamp(t,0,#path-1)
		local index=math.min(#path-2,math.floor(t));local f=t-index
		local a,b=path[index+1],path[index+2]
		return a%w+.5+(b%w-a%w)*f,math.floor(a/w)+.5+(math.floor(b/w)-math.floor(a/w))*f
	end
	local ax,ay=point(at-.5);local bx,by=point(at+.5)
	return {x=(ax+bx)/2,y=(ay+by)/2}
end
function Column.poses(column:any,time:number,w:number,config:any,hash:any,visible:any):{any}
	local out={}
	if #column.path<2 or time>=column.untilTime then return out end
	local head=math.min(#column.path-1,math.max(0,(time-column.t)*column.speed));local tail=math.max(0,head-column.length)
	local rules=config.refugees
	local count=math.min(rules.max,math.floor(column.length*rules.perCell+.5))
	local step=column.length/math.max(1,count)
	local advance=if (time-column.t)*column.speed>=#column.path-1 then 0 else column.speed
	for i=0,count-1 do
		local g=head-(i+hash(column.id,i))*step
		if g<tail or g<0 then continue end
		local p=Column.sample(column.path,w,g)
		if not visible(p.x,p.y) then continue end
		local nextPoint=Column.sample(column.path,w,g+.4)
		local dx,dy=nextPoint.x-p.x,nextPoint.y-p.y;local norm=math.sqrt(dx*dx+dy*dy)
		if norm==0 then norm=1 end
		local heading=math.atan2(dy,dx)
		local spread=(hash(column.id,i+100)-.5)*2*rules.spread
		local x,y=p.x-dy/norm*spread,p.y+dx/norm*spread
		if not visible(x,y) then continue end
		local a,b=Column.sample(column.path,w,g-.01),Column.sample(column.path,w,g+.01)
		local vx,vy=(b.x-a.x)/.02*advance,(b.y-a.y)/.02*advance
		local function add(id:string,model:string,group:string,px:number,py:number,cells:number,phase:number?,coarse:boolean)
			if not visible(px,py) then return end
			table.insert(out,{id=id,model=model,group=group,x=px,y=py,heading=heading,cells=cells,alpha=1,vx=vx,vy=vy,
				phase=if phase then phase%(2/config.people.stride) else nil,speed=advance,coarse=coarse})
		end
		local key=column.id..":"..i
		local choice=hash(column.id,i+200)
		if choice<rules.cars then
			local model=config.models[math.floor(hash(column.id,i+300)*#config.models)+1]
			add("r"..key,model,"cars",x,y,config.cars.cells,nil,true)
		else
			local phase=g+hash(column.id,i+400)
			local frame=if math.floor(phase*config.people.stride)%2==1 then 1 else 2
			local model="person"..string.char(65+math.floor(hash(column.id,i+500)*3))..frame
			local cart=choice<rules.cars+rules.carts
			if cart then add("c"..key,"cart","people",x-dx/norm*.32,y-dy/norm*.32,.4,nil,true) end
			add("r"..key,model,"people",x,y,config.people.cells,phase,cart)
		end
	end
	return out
end
-- APPROX network adapter: short tangent prediction/foot animation, stopped with the war clock.
function Column.predict(row:any,time:number,stride:number):any
	local p=table.clone(row);local age=math.clamp(time-row.time,0,.5)
	p.x+=row.vx*age;p.y+=row.vy*age
	if row.phase then
		local frame=if math.floor((row.phase+row.speed*age)*stride)%2==1 then 1 else 2
		p.model=string.sub(row.model,1,-2)..frame
	end
	return p
end
return Column
