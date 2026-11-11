--!strict
-- Original Ohe roof claiming, ignition, burn stages and wind spread, over a world-pixel adapter.
-- HouseWorld supplies authoritative timing and fog-filtered replication; painting stays client-side.
local HouseFire={}
function HouseFire.new(settings:any,context:any):any
	local c=settings.houses;local tile=settings.tileSize;local pw=context.width*tile;local ph=context.height*tile
	local self:any={time=0,houses={},shells={},mark={},burnt=0,turn=0,scarred={},scarOrder={},nextUp={},rebuildAcc=0}
	local random=context.random or math.random
	local function range(a:number,b:number):number return a+(b-a)*random() end
	local function pixel(x:number,y:number):number? return if x>=0 and y>=0 and x<pw and y<ph then y*pw+x else nil end
	local function roof(p:number):boolean return context.roof(p%pw,math.floor(p/pw)) end
	function self.claim(x:number,y:number):{number}?
		local first=pixel(x,y)
		if first==nil or self.mark[first] or not roof(first) then return nil end
		local cell=math.floor(y/tile)*context.width+math.floor(x/tile)
		if context.noFire and context.noFire(cell) then return nil end
		local found={first};self.mark[first]=1;local cursor=1
		while cursor<=#found and #found<c.house.maxPx do
			local p=found[cursor];cursor+=1;local px,py=p%pw,math.floor(p/pw)
			for _,offset in {{1,0},{-1,0},{0,1},{0,-1}} do
				if #found>=c.house.maxPx then break end
				local n=pixel(px+offset[1],py+offset[2])
				if n~=nil and not self.mark[n] and roof(n) then self.mark[n]=1;table.insert(found,n) end
			end
		end
		if #found<c.house.minPx then for _,p in found do self.mark[p]=nil end;return nil end
		return found
	end
	local function stage(h:any):number
		local fraction=h.age/h.life
		return if fraction>=c.burn.charAt[2] then 2 elseif fraction>=c.burn.charAt[1] then 1 else 0
	end
	local function charTo(h:any,value:number)
		if h.stage==value then return end;h.stage=value
		if context.onStage then context.onStage(h,value) end
	end
	function self.ignite(x:number,y:number,generation:number?):boolean
		if #self.houses>=c.cap.hard then return false end
		local points=self.claim(x,y);if not points then return false end
		local sx,sy=0,0
		for _,p in points do sx+=p%pw+.5;sy+=math.floor(p/pw)+.5 end
		local cx,cy=sx/#points/tile,sy/#points/tile
		local h={px=points,x=cx,y=cy,r=math.sqrt(#points/math.pi)/tile,cell=math.min(context.height-1,math.floor(cy))*context.width+math.min(context.width-1,math.floor(cx)),
			age=0,life=range(c.burn.sec[1],c.burn.sec[2])*(1+c.burn.bigger*math.min(1,#points/c.house.maxPx)),gen=generation or 0,stage=-1,looked=self.time,
			flameAcc=random(),smokeAcc=random(),emberAcc=random()}
		h.ageRate=1+(if context.rain then context.rain(cx,cy) else 0)*(c.rain.hurry-1)
		table.insert(self.houses,h);charTo(h,stage(h));return true
	end
	function self.igniteAt(x:number,y:number,reach:number?):number
		local radius=math.ceil((reach or c.matchCells)*tile);local gx,gy=math.floor(x*tile),math.floor(y*tile);local count=0
		for r=0,radius,2 do
			if count>=c.matchHouses then break end
			local samples=if r==0 then 1 else math.ceil(math.pi*2*r/2)
			for i=0,samples-1 do
				if count>=c.matchHouses then break end
				local angle=i/samples*math.pi*2
				if self.ignite(gx+math.floor(math.cos(angle)*r+.5),gy+math.floor(math.sin(angle)*r+.5),0) then count+=1 end
			end
		end
		return count
	end
	function self.burningNear(x:number,y:number,reach:number):boolean
		for _,h in self.houses do if (h.x-x)^2+(h.y-y)^2<=reach^2 then return true end end;return false
	end
	function self.builtNear(x:number,y:number,reach:number):boolean
		for cy=math.max(0,math.floor(y-reach)),math.min(context.height-1,math.floor(y+reach)) do
			for cx=math.max(0,math.floor(x-reach)),math.min(context.width-1,math.floor(x+reach)) do
				if context.builtAt then
					if context.builtAt(cy*context.width+cx) then return true end
				else
					for py=cy*tile,(cy+1)*tile-1 do for px=cx*tile,(cx+1)*tile-1 do if context.roof(px,py) then return true end end end
				end
			end
		end
		return false
	end
	function self.blast(x:number,y:number,size:number,weapon:string):number
		local b;local scale=1
		if weapon=="wreck" or weapon=="razed" then b=c.hot[weapon]
		else
			b=c.blast[weapon];local reference=if weapon=="blast" then c.blastSize else settings.weaponBlast[weapon]
			scale=if reference and reference>0 then size/reference else 0
		end
		if not b or scale<=0 or b.reach<=0 or b.ignite<=0 or not self.builtNear(x,y,b.reach*scale) or random()>=b.ignite then return 0 end
		local count=0
		for i=0,c.blastTries-1 do
			if count>=c.blastHouses then break end
			local angle=range(0,math.pi*2);local distance=if i==0 then 0 else math.sqrt(random())*b.reach*scale
			if self.ignite(math.floor((x+math.cos(angle)*distance)*tile),math.floor((y+math.sin(angle)*distance)*tile),0) then count+=1 end
			if count==1 and random()<.6 then break end
		end
		return count
	end
	local function burnDown(dt:number)
		local excess=#self.houses-c.cap.soft;local kept={}
		for i,h in self.houses do
			local rain=if context.rain then context.rain(h.x,h.y) else 0
			h.ageRate=(if i<=excess then c.cap.hurry else 1)*(1+rain*(c.rain.hurry-1))
			h.age+=dt*h.ageRate
			if h.age>=h.life then
				for _,p in h.px do self.mark[p]=2 end
				self.burnt+=#h.px;charTo(h,3)
				table.insert(self.shells,{px=h.px,x=h.x,y=h.y,cell=h.cell,at=self.time})
				if not self.scarred[h.cell] then
					self.scarred[h.cell]=true;table.insert(self.scarOrder,h.cell)
					if context.onScar then context.onScar(math.floor(h.x)+.5,math.floor(h.y)+.5,c.scar.r,c.scar.strength,"burn") end
				end
			else charTo(h,stage(h));table.insert(kept,h) end
		end
		self.houses=kept
	end
	local function spread()
		local s=c.spread;local budget=math.min(s.budget,#self.houses)
		for _=1,budget do
			if #self.houses>=c.cap.hard then return end
			self.turn=(self.turn+1)%#self.houses;local h=self.houses[self.turn+1]
			local elapsed=self.time-h.looked;h.looked=self.time
			if h.age<c.burn.catchSec or h.age>h.life*c.burn.spreadUntil or h.gen+1>=s.generations or context.rain and context.rain(h.x,h.y)>=c.rain.noSpread then continue end
			local rate=s.perSec*elapsed*s.falloff^h.gen
			for _=1,s.tries do
				local p=h.px[math.floor(random()*#h.px)+1];local x,y=p%pw,math.floor(p/pw)
				local along,across=range(-.4,s.reachDown),range(-.7,s.reachCross)
				local probability=1-math.exp(-rate*(if along>=0 then 1 else s.up))
				if random()>=probability then continue end
				local wind=settings.wind
				self.ignite(x+math.floor((wind.x*along-wind.y*across)*tile+.5),y+math.floor((wind.y*along+wind.x*across)*tile+.5),h.gen+1)
			end
		end
	end
	function self.raise(shell:any)
		for _,p in shell.px do if self.mark[p]==2 then self.mark[p]=nil;self.burnt-=1 end end
		self.scarred[shell.cell]=nil
		local i=table.find(self.scarOrder,shell.cell);if i then table.remove(self.scarOrder,i) end
		local at=table.find(self.shells,shell);if at then table.remove(self.shells,at) end
		if context.onRestore then context.onRestore(shell) end
	end
	function self.rebuildShells()
		local r=c.rebuild;local current=table.clone(self.shells);local towns={};local count={}
		for i,shell in current do
			local town=if context.townAt then context.townAt(shell.cell) else nil
			towns[i]=town
			if town then count[town.id]=(count[town.id] or 0)+1 end
		end
		local kept={}
		for i,shell in current do
			local town=towns[i]
			local ready=self.time-shell.at>=(if town then r.afterSec else r.loneSec) and not self.burningNear(shell.x,shell.y,r.clearCells)
			if ready and town then
				assert(context.rebuildRules,"missing settlement rebuild rules")
				local worldTime=if context.worldTime then context.worldTime() else self.time
				ready=worldTime-town.lastHitAt>=context.rebuildRules.quietSec and self.time>=(self.nextUp[town.id] or -math.huge)
				if ready then
					local deficit=(1-town.integrity/math.max(1,town.maxIntegrity))*context.rebuildRules.fullSec
					self.nextUp[town.id]=self.time+math.clamp(deficit/math.max(1,count[town.id] or 1),r.minSec,r.maxSec)
				end
			end
			if ready then self.raise(shell) else table.insert(kept,shell) end
		end
		self.shells=kept
	end
	function self.tick(dt:number)
		assert(dt==dt and dt<math.huge and dt>=0,"invalid fire time step");if dt==0 then return end
		self.time+=dt
		if context.autoRebuild~=false and #self.shells>0 then
			self.rebuildAcc+=dt
			if self.rebuildAcc>=c.rebuild.everySec then self.rebuildAcc=0;self.rebuildShells() end
		end
		burnDown(dt);spread()
	end
	function self.reset()
		if context.onReset then context.onReset() end
		self.time=0;self.houses={};self.shells={};self.mark={};self.burnt=0;self.turn=0;self.scarred={};self.scarOrder={};self.nextUp={};self.rebuildAcc=0
	end
	return self
end
return HouseFire
