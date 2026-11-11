--!strict
-- Authoritative roof/forest actors feed one shared, fog-gated particle emitter and atlas/pool.
-- APPROX: bounded 0.5s war-clock extrapolation, independent cosmetic RNG, native alpha quads.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Effects=require(Shared.Presentation.FireEffects)
local View=require(Shared.Presentation.HouseFireView)
local ForestView=require(Shared.Presentation.ForestFireView)
local Scorch=require(script.Parent.FireScorchRenderer)
local Death=require(script.Parent.DeathRenderer)
local Fog=require(script.Parent.FogOverlay)
local WorldLight=require(script.Parent.WorldLight)
local Town=require(script.Parent.TownRenderer)
local Renderer={}
local current:any=nil
function Renderer.destroy() if current then current.folder:Destroy() end end
function Renderer.start(map:any,parent:Instance):boolean
	Renderer.destroy()
	local data=Shared:FindFirstChild("GameData")
	local profile=data and data:FindFirstChild("FireEffectsRules")
	local rules=data and data:FindFirstChild("FireRules")
	if not profile or not rules then return false end
	local ok,config,settings=pcall(function() return require(profile),require(rules) end)
	if not ok then warn("[WorldFire] Local fire settings unavailable:",config);return false end
	local house=Scorch.start(map,parent);local forest=Town.getForestMap()
	if not house and not forest then return false end
	local folder=Instance.new("Folder");folder.Name="WorldFireEffects";folder.Parent=parent
	local rng=Random.new();local random=function() return rng:NextNumber() end
	local st:any={folder=folder,clock=nil,at=os.clock(),running=false,nv=false,dead=false};current=st
	local view=View.new(map.width,map.height,config.tileSize,settings.houses.house.maxPx,{
		random=random,pixels=function(rows) Scorch.apply(rows) end,
		clear=function() Death.clearTag(folder);Scorch.apply({},true) end})
	st.view=view
	if forest then st.forest=ForestView.new(forest,settings,{random=random,
		clear=function() Death.clearTag(folder) end,fates=Town.setForestFates}) end
	local bounds:any=nil
	local effects=Effects.new(config,{random=random,
		visible=function(x,y,cell)
			if cell then x,y=cell%map.width+.5,math.floor(cell/map.width)+.5 end
			return not Fog.hidden(x,y)
		end,
		onScreen=function(x,y) return bounds and math.abs(x-bounds.cx)<=bounds.rx+4 and math.abs(y-bounds.cy)<=bounds.ry+4 end,
		point=view.point,nightVisionMix=function() return if st.nv then 1 else 0 end,
		emit=function(kind,p) Death.request(kind,p,folder) end})
	local connection=RunService.RenderStepped:Connect(function()
		if st.clock==nil then return end
		local camera=workspace.CurrentCamera;if not camera then return end
		local time=st.clock+(if st.running then math.min(.5,os.clock()-st.at) else 0)
		local actors,dt=view.frame(time);if dt<=0 then return end
		local trees=if st.forest then st.forest.frame(time) else {}
		bounds=WorldLight.view(camera)
		-- FireEffects expects age; retain the packet baseline while it updates emission accumulators.
		for _,a in actors do a.baseAge=a.age;a.age=a.drawAge end
		for _,a in trees do a.baseAge=a.age;a.age=a.drawAge end
		effects.frame(trees,actors,dt,bounds.cellPixels)
		for _,a in actors do a.age=a.baseAge end
		for _,a in trees do a.age=a.baseAge end
	end)
	folder.Destroying:Connect(function()
		st.dead=true;connection:Disconnect();Death.clearTag(folder);Scorch.destroy()
		if current==st then current=nil end
	end)
	return true
end
function Renderer.syncClock(time:number,running:boolean)
	if current then current.clock=time;current.running=running;current.at=os.clock() end
end
function Renderer.apply(packet:any)
	if current then current.view.apply(packet) end
end
function Renderer.applyForest(packet:any)
	if current and current.forest then current.forest.apply(packet) end
end
function Renderer.setNightVision(on:boolean) if current then current.nv=on end end
return Renderer
