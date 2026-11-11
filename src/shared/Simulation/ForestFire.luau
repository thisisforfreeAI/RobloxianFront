--!strict
-- Pure port of original Ihe ignition/burnDown/spread/open/dryness/heal.
-- Coefficients come from ignored FireRules, never a duplicated settings table.
-- ForestWorld supplies authoritative timing/replication. This model adds no unit damage/pathing.
local Hash=if script then require(script.Parent.Parent.Utilities.Hash) else require("../Utilities/Hash")
local ForestFire={}
local function lerp(a:number,b:number,t:number):number return a+(b-a)*t end
function ForestFire.hash(value:number,salt:number):number
	return Hash.seed(value,salt)
end
function ForestFire.new(settings:any,context:any):any
	local c=settings.forest
	local self:any={time=0,burns={},burning={},fates={},fateOrder={},healing={},healedAt=0,scarred={},scarOrder={},turn=0,hot={}}
	local byKey={}
	for _,tree in context.trees do
		assert(not byKey[tree.key],"duplicate tree key");byKey[tree.key]=tree
		if tree.fate then self.fates[tree.key]=table.clone(tree.fate);table.insert(self.fateOrder,tree.key) end
	end
	local random=context.random or math.random
	local function range(a:number,b:number):number return lerp(a,b,random()) end
	local function fate(tree:any,value:any)
		if self.fates[tree.key]==nil and value then table.insert(self.fateOrder,tree.key) end
		self.fates[tree.key]=value
		if not value then
			local i=table.find(self.fateOrder,tree.key);if i then table.remove(self.fateOrder,i) end
		end
		if context.onFate then context.onFate(tree,value) end
	end
	local function eligible(tree:any):boolean
		local f=self.fates[tree.key]
		return tree.standing and (not f or f.kind=="burning")
	end
	local function nearby(x:number,y:number,reach:number,fn:any)
		-- A live tree layer can provide its own stable cell/spatial query.
		if context.forNear then context.forNear(x,y,reach,fn);return end
		for _,tree in context.trees do
			local distance=math.sqrt((tree.x-x)^2+(tree.y-y)^2)
			if distance<=reach then fn(tree,distance) end
		end
	end
	local function fuel(cell:number):boolean
		if context.fuelAt then return context.fuelAt(cell,self.fates) end
		for _,tree in context.trees do if tree.cell==cell and eligible(tree) then return true end end
		return false
	end
	function self.ignite(tree:any):boolean
		if not eligible(tree) or self.burning[tree.key] or #self.burns>=c.cap.hard then return false end
		self.burning[tree.key]=true
		local burn={key=tree.key,x=tree.x,y=tree.y,cell=tree.cell,size=tree.size,age=0,
			life=range(c.burn.sec[1],c.burn.sec[2])*(1+c.burn.bigger*math.min(1,tree.size/.65)),char=0,looked=self.time,
			flameAcc=random(),smokeAcc=random(),emberAcc=random()}
		burn.ageRate=1+(if context.rain then context.rain(tree.x,tree.y) else 0)*(c.rain.hurry-1)
		table.insert(self.burns,burn);fate(tree,{kind="burning",char=0});return true
	end
	function self.igniteAt(x:number,y:number,reach:number?):number
		local count=0;nearby(x,y,reach or c.matchCells,function(tree) if self.ignite(tree) then count+=1 end end);return count
	end
	function self.dryness(x:number,y:number):number
		local s=c.spread;local px,py=x/s.dryBlock,y/s.dryBlock;local ix,iy=math.floor(px),math.floor(py)
		local function h(a:number,b:number):number return ForestFire.hash(b*4099+a,settings.drynessSalt) end
		local u=lerp(lerp(h(ix,iy),h(ix+1,iy),px-ix),lerp(h(ix,iy+1),h(ix+1,iy+1),px-ix),py-iy)
		return if u<s.dampBelow then s.damp else lerp(s.dry[1],s.dry[2],u)
	end
	function self.open(from:any,to:any):boolean
		local steps=math.ceil(math.sqrt((to.x-from.x)^2+(to.y-from.y)^2)/.4)
		local previous,gaps=from.cell,0
		for i=1,steps-1 do
			local x=math.floor(lerp(from.x,to.x,i/steps));local y=math.floor(lerp(from.y,to.y,i/steps));local cell=y*context.width+x
			if cell==previous or cell==from.cell or cell==to.cell then continue end
			previous=cell
			if context.waterAt and context.waterAt(cell) or context.firebreakAt and context.firebreakAt(cell) then return false end
			if not fuel(cell) then gaps+=1 end
		end
		return gaps==0 or gaps==1 and random()<c.spread.gapJump
	end
	local function burnDown(dt:number)
		local excess=#self.burns-c.cap.soft;local kept={}
		for i,b in self.burns do
			local tree=byKey[b.key];local f=self.fates[b.key]
			if not tree or not tree.standing or not f or f.kind~="burning" then self.burning[b.key]=nil;continue end
			local rain=if context.rain then context.rain(b.x,b.y) else 0
			b.ageRate=(if i<=excess then c.cap.hurry else 1)*(1+rain*(c.rain.hurry-1))
			b.age+=dt*b.ageRate
			if b.age>=b.life then
				self.burning[b.key]=nil;fate(tree,{kind="burnt"})
				if not self.scarred[b.cell] then
					self.scarred[b.cell]=true;table.insert(self.scarOrder,b.cell)
					if context.onScar then context.onScar(math.floor(b.x)+.5,math.floor(b.y)+.5,c.scar.r,c.scar.strength,"burn") end
				end
				continue
			end
			local stage=0
			while stage+1<#c.burn.charAt and b.age/b.life>=c.burn.charAt[stage+2] do stage+=1 end
			if stage~=b.char then b.char=stage;fate(tree,{kind="burning",char=stage}) end
			table.insert(kept,b)
		end
		self.burns=kept
	end
	local function spread()
		local s=c.spread;local budget=math.min(s.budget,#self.burns)
		for _=1,budget do
			if #self.burns>=c.cap.hard then return end
			-- Original zero-based rotating cursor increments before reading.
			self.turn=(self.turn+1)%#self.burns;local b=self.burns[self.turn+1]
			local elapsed=self.time-b.looked;b.looked=self.time
			if b.age<c.burn.catchSec or b.age>b.life*c.burn.spreadUntil then continue end
			if context.rain and context.rain(b.x,b.y)>=c.rain.noSpread then continue end
			local wind=settings.wind
			nearby(b.x+wind.x*s.reachDown*.4,b.y+wind.y*s.reachDown*.4,s.reachDown,function(tree)
				if self.fates[tree.key] or not tree.standing or self.burning[tree.key] then return end
				local dx,dy=tree.x-b.x,tree.y-b.y;local distance=math.sqrt(dx^2+dy^2);if distance<1e-6 then return end
				local dot=(dx*wind.x+dy*wind.y)/distance
				local reach=if dot>=0 then lerp(s.reachCross,s.reachDown,dot) else lerp(s.reachCross,s.reachUp,-dot)
				if distance>=reach then return end
				local share=if dot>=0 then lerp(s.cross,1,dot) else lerp(s.cross,s.up,-dot)
				local probability=1-math.exp(-.04*share*(1-distance/reach)*self.dryness(tree.x,tree.y)*elapsed)
				if random()<probability and self.open(b,tree) then self.ignite(tree) end
			end)
		end
	end
	local function heal()
		local r=c.regrow;if self.time-self.healedAt<r.everySec then return end;self.healedAt=self.time
		local done=0;local budget=math.max(r.perLook,math.ceil(#self.fateOrder*r.perLookShare))
		for _,key in table.clone(self.fateOrder) do
			local f=self.fates[key];local cooling=f.kind=="burning" and not self.burning[key]
			if f.kind~="burnt" and not cooling then continue end
			local start=self.healing[key];if start==nil then self.healing[key]=self.time;continue end
			local wait=if cooling then r.stageSec else lerp(r.afterSec[1],r.afterSec[2],ForestFire.hash(key,107))
			if self.time-start<wait or done>=budget then continue end
			local tree=byKey[key]
			if tree then
				done+=1
				if f.kind=="burnt" then fate(tree,{kind="burning",char=settings.charStages-1})
				elseif f.char>0 then fate(tree,{kind="burning",char=f.char-1})
				else fate(tree,nil);self.healing[key]=nil;continue end
				self.healing[key]=self.time
			end
		end
	end
	function self.heat(x:number,y:number,reach:number,perSec:number,seconds:number)
		if seconds>0 then table.insert(self.hot,{x=x,y=y,reach=reach,perSec=perSec,untilTime=self.time+seconds}) end
	end
	function self.blast(x:number,y:number,size:number,weapon:string):number
		if weapon=="wreck" or weapon=="razed" then
			local h=c.hot[weapon];self.heat(x,y,h.reach*(if weapon=="razed" then size/2.5 else 1),h.perSec,h.sec);return 0
		end
		local b=c.blast[weapon];local reference=if weapon=="blast" then c.blastSize else settings.weaponBlast[weapon]
		if not b or not reference or reference<=0 then return 0 end
		local scale=size/reference;if scale<=0 or b.reach<=0 then return 0 end
		local changed=0
		nearby(x,y,math.max(b.fell,b.reach)*scale,function(tree,distance)
			if not eligible(tree) then return end
			if distance<=b.splinter*scale then
				local stump=random()<c.stumpShare
				fate(tree,if stump then {kind="stump"} else {kind="fallen",rot=math.atan2(tree.y-y,tree.x-x)+range(-.5,.5)})
				changed+=1
			elseif distance<=b.fell*scale and random()<c.fellShare then
				fate(tree,{kind="fallen",rot=math.atan2(tree.y-y,tree.x-x)+range(-.4,.4)});changed+=1
			elseif distance<=b.reach*scale and random()<b.ignite and self.ignite(tree) then changed+=1 end
		end)
		return changed
	end
	function self.tick(dt:number)
		assert(dt==dt and dt<math.huge and dt>=0,"invalid fire time step");if dt==0 then return end
		self.time+=dt
		local hot={}
		for _,h in self.hot do
			if self.time>h.untilTime then continue end;table.insert(hot,h)
			local probability=1-math.exp(-h.perSec*dt)
			nearby(h.x,h.y,h.reach,function(tree) if random()<probability then self.ignite(tree) end end)
		end
		self.hot=hot;burnDown(dt);spread();heal()
	end
	function self.reset()
		for _,key in table.clone(self.fateOrder) do fate(byKey[key],nil) end
		self.time=0;self.healedAt=0;self.burns={};self.burning={};self.healing={};self.hot={};self.scarred={};self.scarOrder={};self.turn=0
	end
	return self
end
return ForestFire
