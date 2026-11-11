--!strict
-- Original Ihe.draw/Ohe.draw emission requests. An adapter feeds the shared particle pool.
-- Not wired to native rendering yet. Simulation and particle RNG streams can remain independent.
local FireEffects={}
function FireEffects.new(config:any,context:any):any
	local random=context.random or math.random
	local self:any={maxCommands=512,used=0} -- APPROX port request cap, shared by both fire kinds per frame.
	local function range(a:number,b:number):number return a+(b-a)*random() end
	local function pick(values:{any}):any return values[math.floor(random()*#values)+1] end
	local function fireColor():number
		local mix=if context.nightVisionMix then context.nightVisionMix() else 0
		return pick(if mix>=config.nightFrom then config.nightColors else config.colors)
	end
	local function emit(kind:string,p:any)
		if self.used>=self.maxCommands then return end
		self.used+=1;context.emit(kind,p)
	end
	local function shown(actors:{any}):{any}
		local out={}
		for _,a in actors do
			if context.visible(a.x,a.y,a.cell) and context.onScreen(a.x,a.y) then table.insert(out,a) end
		end
		return out
	end
	local function intensity(age:number,life:number,c:any):number
		local u=age/life
		return if u<.15 then c.catching+(1-c.catching)*u/.15 elseif u>.8 then 1+(c.dying-1)*(u-.8)/.2 else 1
	end
	local function smoke(a:any,c:any,size:number)
		local s=size*range(.8,1.15)
		emit("puff",{x=a.x+range(-.2,.2),y=a.y+range(-.2,.2),h=c.smokeHeight,size=s,life=c.smokeLife*range(.85,1.2),vx=0,vy=0,color=config.smoke,small=true,ground=false,rise=c.smokeRise})
	end
	local function forest(actors:{any},dt:number,px:number)
		local list=shown(actors);if #list==0 then return end
		local c=config.forest
		local flames,smokes=math.min(c.flames,c.flamesPerSec/#list),math.min(c.smoke,c.smokePerSec/#list)
		local embers=if px>=config.forestEmbersFrom then math.min(c.embers,c.embersPerSec/#list) else 0
		for _,a in list do
			local strength=intensity(a.age,a.life,c);local root=math.max(.3,a.size)
			a.flameAcc+=dt*flames*strength
			for _=1,3 do
				if a.flameAcc<1 then break end;a.flameAcc-=1
				local size=math.max(root*c.flameSize,c.flameMinPx/px)*range(.7,1.2)*(.6+.4*strength)
				local tex=pick(config.textures)
				local x,y=a.x+range(-root,root)*.35,a.y+range(-root,root)*.35
				local rot=range(0,math.pi*2);local color=fireColor()
				emit("spawn",{tex=tex,x=x,y=y,h=c.flameHeight,vh=c.flameRise,size=size,rot=rot,life=c.flameLife,grow=-size/c.flameLife,color=color,a0=1,a1=1,step=true,small=true,emit=true})
			end
			if a.flameAcc>=1 then a.flameAcc=0 end
			a.smokeAcc+=dt*smokes*(.5+.5*strength)
			if a.smokeAcc>=1 then a.smokeAcc=0;smoke(a,c,math.max(c.smokeSize*(.7+root),c.smokeMinPx/px)) end
			a.emberAcc+=dt*embers*strength
			if a.emberAcc>=1 then a.emberAcc=0;emit("embers",{x=a.x,y=a.y,h=c.flameHeight+.2,count=1,spread=root*.4}) end
		end
	end
	local function houses(actors:{any},dt:number,px:number)
		local list=shown(actors);if #list==0 then return end
		local c=config.houses
		local flames=math.min(c.flames,c.flamesPerSec/(#list*c.most));local smokes=math.min(c.smoke,c.smokePerSec/#list)
		local embers=if px>=c.embersFromPx then math.min(c.embers,c.embersPerSec/#list) else 0
		for _,a in list do
			local strength=intensity(a.age,a.life,c);local share=math.min(c.most,math.max(.5,#a.px/c.perPx))
			a.flameAcc+=dt*flames*strength*share
			for _=1,4 do
				if a.flameAcc<1 then break end;a.flameAcc-=1
				local p=a.px[math.floor(random()*#a.px)+1];local x,y=context.point(p)
				if x==nil then continue end
				local size=math.max(c.flameSize,c.flameMinPx/px)*range(.7,1.2)*(.6+.4*strength)
				local tex=pick(config.textures);local rot=range(0,math.pi*2);local color=fireColor()
				emit("spawn",{tex=tex,x=(x+.5)/config.tileSize,y=(y+.5)/config.tileSize,h=c.flameHeight,vh=c.flameRise,size=size,rot=rot,life=c.flameLife,grow=-size/c.flameLife,color=color,a0=1,a1=1,step=true,small=true,emit=true})
			end
			if a.flameAcc>=1 then a.flameAcc=0 end
			a.smokeAcc+=dt*smokes*(.5+.5*strength)
			if a.smokeAcc>=1 then a.smokeAcc=0;smoke(a,c,math.max(c.smokeSize*(.7+a.r),c.smokeMinPx/px)) end
			a.emberAcc+=dt*embers*strength
			if a.emberAcc>=1 then a.emberAcc=0;emit("embers",{x=a.x,y=a.y,h=c.flameHeight+.2,count=1,spread=math.max(.2,a.r)}) end
		end
	end
	function self.frame(trees:{any},buildings:{any},dt:number,px:number):number
		self.used=0
		if dt<=0 or px<=0 then return 0 end
		forest(trees,dt,px);houses(buildings,dt,px);return self.used
	end
	return self
end
return FireEffects
