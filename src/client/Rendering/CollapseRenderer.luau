--!strict
-- Visible transient structure collapses. No new images: every request uses the shared death pool.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Effects=require(Shared.Presentation.CollapseEffects)
local Events=require(Shared.Protocol.CollapseEvents)
local Death=require(script.Parent.DeathRenderer)
local Fog=require(script.Parent.FogOverlay)
local WorldLight=require(script.Parent.WorldLight)
local Renderer={}
local current:any=nil
function Renderer.destroy() if current then current.folder:Destroy() end end
function Renderer.start(map:any,parent:Instance)
	Renderer.destroy()
	local folder=Instance.new("Folder");folder.Name="StructureCollapseEffects";folder.Parent=parent
	local st:any={folder=folder,width=map.width,height=map.height,lastTick=-1,dead=false,disabled=false,effects=nil};current=st
	st.fail=function(err:any)
		st.disabled=true;if st.effects then st.effects.clear();st.effects=nil end;Death.clearTag(folder)
		warn("[CollapseRenderer] Optional collapse effects unavailable:",err)
	end
	local function visible(x:number,y:number):boolean
		if Fog.hidden(x,y) then return false end
		local camera=workspace.CurrentCamera;if not camera then return false end
		local view=WorldLight.view(camera)
		-- APPROX: fixed conservative view padding replaces source particle-extent calculations.
		return math.abs(x-view.cx)<=view.rx+16 and math.abs(y-view.cy)<=view.ry+16
	end
	st.load=function():boolean
		if st.effects then return true end;if st.disabled then return false end
		local data=Shared:FindFirstChild("GameData");local module=data and data:FindFirstChild("CollapseFx")
		local ok,model=pcall(function()
			assert(module,"generate CollapseFx with tools/conversion/export_collapse_fx.cjs")
			return Effects.new(require(module),{visible=visible,emit=function(kind,p) Death.request(kind,p,folder) end})
		end)
		if not ok then st.fail(model);return false end
		st.effects=model;return true
	end
	local connection=RunService.Heartbeat:Connect(function(dt)
		if st.effects and not st.dead then local ok,err=pcall(st.effects.step,dt);if not ok then st.fail(err) end end
	end)
	folder.Destroying:Connect(function()
		st.dead=true;connection:Disconnect();if st.effects then st.effects.clear();st.effects=nil end;Death.clearTag(folder)
		if current==st then current=nil end
	end)
end
function Renderer.reset()
	local st=current;if st and not st.dead then if st.effects then st.effects.clear() end;Death.clearTag(st.folder) end
end
function Renderer.apply(tick:number,rows:any)
	local st=current;if not st or st.dead or type(tick)~="number" or not (tick>st.lastTick and tick<math.huge and tick%1==0) then return end
	st.lastTick=tick
	local entries=Events.read(rows,st.width,st.height);if #entries==0 or not st.load() then return end
	local ok,err=pcall(function() for _,row in entries do st.effects.raze(row[2],row[3],row[4]) end end)
	if not ok then st.fail(err) end
end
return Renderer
