--!strict
--!native
-- Original tAt road escape search, zN cooldown, WN span and i2t convoy crawl rule.
local Refugees={}
function Refugees.route(w:number,h:number,onRoad:any,town:any,rules:any,random:any):{number}?
	local reach=town.radius+rules.reach
	local start,best=-1,reach*reach
	for y=math.max(0,math.floor(town.y-reach)),math.min(h-1,math.floor(town.y+reach)) do
		for x=math.max(0,math.floor(town.x-reach)),math.min(w-1,math.floor(town.x+reach)) do
			local cell=y*w+x;local distance=(x+.5-town.x)^2+(y+.5-town.y)^2
			if onRoad(cell) and distance<best then start=cell;best=distance end
		end
	end
	if start<0 then return nil end
	local previous,depth,order={[start]=-1},{[start]=0},{start}
	local frontier={start};local deepest=0
	for level=1,math.max(2,math.floor(rules.pathCells+.5)) do
		if #frontier==0 then break end
		local nextFrontier={}
		for _,cell in frontier do
			local x,y=cell%w,math.floor(cell/w)
			for _,offset in {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}} do
				local nx,ny=x+offset[1],y+offset[2]
				if nx<0 or ny<0 or nx>=w or ny>=h then continue end
				local n=ny*w+nx
				if previous[n]~=nil or not onRoad(n) then continue end
				previous[n]=cell;depth[n]=level;table.insert(nextFrontier,n);table.insert(order,n)
			end
		end
		if #nextFrontier>0 then deepest=level end
		frontier=nextFrontier
	end
	if deepest<2 then return nil end
	local candidates={};local farthest=0
	local function distance(cell:number):number return math.sqrt((cell%w+.5-town.x)^2+(math.floor(cell/w)+.5-town.y)^2) end
	for _,cell in order do if depth[cell]>=deepest*.8 then table.insert(candidates,cell);farthest=math.max(farthest,distance(cell)) end end
	local ends={}
	for _,cell in candidates do if distance(cell)>=farthest*.85 then table.insert(ends,cell) end end
	table.sort(ends)
	local current=ends[math.floor(random()*#ends)%#ends+1]
	local reversed={}
	while current>=0 do table.insert(reversed,current);current=previous[current] end
	local path={}
	for i=#reversed,1,-1 do table.insert(path,reversed[i]) end
	return path
end
function Refugees.span(column:any,time:number):(number,number)
	local head=math.min(#column.path-1,math.max(0,(time-column.t)*column.speed))
	return head,math.max(0,head-column.length)
end
function Refugees.new(context:any):any
	local self={list={},fled={},seq=0,context=context}
	function self.onShelled(town:any,time:number):any
		if not context.enabled or town.destroyed then return nil end
		local rules=context.rules
		if time-(self.fled[town.id] or -math.huge)<rules.cooldownSec then return nil end
		-- The original records this attempt even when no usable road route exists.
		self.fled[town.id]=time
		local path=Refugees.route(context.width,context.height,context.onRoad,town,rules,context.random)
		if not path then return nil end
		self.seq+=1
		local speed=math.max(.001,rules.speed)
		local column={id=self.seq,city=town.id,t=time,untilTime=time+(#path-1)/speed+rules.lingerSec,path=path,speed=speed,length=rules.length}
		table.insert(self.list,column)
		return column
	end
	function self.step(time:number)
		for i=#self.list,1,-1 do if time>=self.list[i].untilTime then table.remove(self.list,i) end end
	end
	function self.truckFactor(x:number,y:number,time:number):number
		if not context.gameplay then return 1 end
		local radius=context.rules.widthCells+.75
		for _,column in self.list do if time<column.untilTime then
			local head,tail=Refugees.span(column,time)
			for i=math.floor(tail),math.min(#column.path-1,math.ceil(head)) do
				local cell=column.path[i+1]
				if (cell%context.width+.5-x)^2+(math.floor(cell/context.width)+.5-y)^2<=radius*radius then return context.rules.truckShare end
			end
		end end
		return 1
	end
	return self
end
return Refugees
