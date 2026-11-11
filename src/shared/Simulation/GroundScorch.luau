--!strict
-- Original JLt burn/crater/rubble footprints and ZDt fade/heal behavior. Coefficients stay local.
local Hash=if script then require(script.Parent.Parent.Utilities.Hash) else require("../Utilities/Hash")
local Scorch={}
function Scorch.towns(config:any,w:number,h:number,towns:{any}):any
	local ids=buffer.create(w*h*2);local distance=buffer.create(w*h*4)
	for c=0,w*h-1 do buffer.writef32(distance,c*4,math.huge) end
	for id,t in towns do
		local radius=t.radius*config.townReach+config.townPad
		for y=math.max(0,math.floor(t.y-radius)),math.min(h-1,math.ceil(t.y+radius)) do
			for x=math.max(0,math.floor(t.x-radius)),math.min(w-1,math.ceil(t.x+radius)) do
				local d=math.sqrt((x+.5-t.x)^2+(y+.5-t.y)^2)/radius;local c=y*w+x
				if d<=1 and d<buffer.readf32(distance,c*4) then buffer.writef32(distance,c*4,d);buffer.writeu16(ids,c*2,id) end
			end
		end
	end
	return function(cell:number):any local id=buffer.readu16(ids,cell*2);return if id>0 then towns[id] else nil end
end
function Scorch.new(config:any,w:number,h:number,context:any):any
	local self:any={amount=buffer.create(w*h*4),settle=buffer.create(w*h*4),tone=buffer.create(w*h),cells={},healing={}}
	local function mark(cell:number,value:number,tone:number)
		if value<=0 then return end
		local at=cell*4;local old=buffer.readf32(self.settle,at)
		local keep=if config.palette then config.palette[tone+1].keep else config.keep
		local stain=math.min(1,value)*keep
		buffer.writef32(self.settle,at,math.min(math.max(old,stain)+math.min(old,stain)*config.settle.deepen,math.max(old,stain,config.settle.cap)))
		if value>=buffer.readf32(self.amount,at) then buffer.writeu8(self.tone,cell,tone) end
		buffer.writef32(self.amount,at,math.min(1,math.max(buffer.readf32(self.amount,at),value,buffer.readf32(self.settle,at))))
		self.cells[cell]=true;self.healing[cell]=true
	end
	function self.scar(x:number,y:number,radius:number,power:number,kind:string)
		assert(kind=="burn" or (kind=="crater" or kind=="rubble") and config.shapes and config.shapes[kind] and config.palette,"unsupported ground scar kind")
		assert(x==x and y==y and math.abs(x)<math.huge and math.abs(y)<math.huge and radius>=0 and radius<math.huge and power>=0 and power<math.huge,"invalid scorch impulse")
		local shape=if kind=="burn" then config.burn else config.shapes[kind]
		local gx,gy=math.floor(x),math.floor(y);local r=math.max(1,radius)
		local reach=math.ceil(r*(if kind=="burn" then shape.stretch elseif kind=="crater" then shape.throwTo else 1)+1)
		local wind=if context.wind then context.wind() else config.wind;local wx,wy=wind[1],wind[2];local length=math.sqrt(wx*wx+wy*wy);if length==0 then length=1 end
		for cy=math.max(0,gy-reach),math.min(h-1,gy+reach) do for cx=math.max(0,gx-reach),math.min(w-1,gx+reach) do
			local cell=cy*w+cx;local dx,dy=cx-gx,cy-gy
			local noise=Hash.seed(cell,119);local scale=r*(1-shape.wobble/2+shape.wobble*noise)
			if kind=="burn" then
				local along=(dx*wx+dy*wy)/length;local cross=(dx*wy-dy*wx)/length
				if along>0 then along/=shape.stretch end
				local distance=math.sqrt(along*along+cross*cross)/scale
				if distance<=1 then mark(cell,power*shape.strength*(1-distance*distance*.6),config.tone) end
			elseif kind=="crater" then
				local distance=math.sqrt(dx*dx+dy*dy)/scale
				if distance<=shape.floor then mark(cell,power*shape.floorStrength,config.tones.earth)
				elseif distance<=1 then mark(cell,power*shape.rimStrength*(1-(distance-shape.floor)/(1-shape.floor)*.5),config.tones.burnt)
				elseif distance<=shape.throwTo and noise<shape.throwShare then mark(cell,power*shape.throwStrength,config.tones.earth) end
			elseif math.max(math.abs(dx),math.abs(dy))/scale<=1 then
				mark(cell,power*shape.strength*(.7+.3*noise),if noise<shape.burntShare then config.tones.burnt else config.tones.ash)
			end
		end end
	end
	function self.fade(dt:number)
		assert(dt==dt and dt>=0 and dt<math.huge,"invalid scorch time step")
		if dt<=0 then return end
		for cell in self.cells do
			local at=cell*4;local value=buffer.readf32(self.amount,at);local target=buffer.readf32(self.settle,at)
			if value>target then buffer.writef32(self.amount,at,math.max(target,value-dt/config.fadeSec)) end
		end
	end
	function self.heal(dt:number)
		assert(dt==dt and dt>=0 and dt<math.huge,"invalid scorch time step");if dt<=0 then return end
		for cell in self.healing do
			local town=context.townAt and context.townAt(cell)
			if not town then self.healing[cell]=nil;continue end
			if not context.quiet(town) then continue end
			local at=cell*4;local value=math.max(0,buffer.readf32(self.amount,at)-dt/config.heal.sec)
			buffer.writef32(self.amount,at,value)
			buffer.writef32(self.settle,at,math.max(0,math.min(buffer.readf32(self.amount,at),buffer.readf32(self.settle,at)-dt/config.heal.sec)))
			if value<=0 then self.cells[cell]=nil;self.healing[cell]=nil end
		end
	end
	function self.reset() buffer.fill(self.amount,0,0);buffer.fill(self.settle,0,0);buffer.fill(self.tone,0,0);table.clear(self.cells);table.clear(self.healing) end
	return self
end
return Scorch
