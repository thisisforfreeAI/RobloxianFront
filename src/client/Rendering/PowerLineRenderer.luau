--!strict
-- Visual power infrastructure only. Source planner/art/wire geometry; no electrical simulation.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Power=require(Shared.Presentation.PowerLines)
local Memory=require(script.Parent.ImageMemory)
local Fog=require(script.Parent.FogOverlay)
local Daylight=require(script.Parent.DaylightController)
local WorldLight=require(script.Parent.WorldLight)
local Renderer={}
local current:Instance?=nil
local TILE=8 -- Disjoint world canvases prevent coplanar per-span GUI overlap.
-- APPROX owner override: static map infrastructure remains visible through fog of war.
-- Lift only fogged portions above fog's .40 top; revealed portions retain normal unit layering.
local WIRE_HEIGHT,NODE_HEIGHT=.22,.225
local FOG_WIRE_HEIGHT,FOG_NODE_HEIGHT=.425,.43
local weather="clear"
local S=World.STUDS_PER_CELL
local function color(hex:string):Color3
	local value=tonumber(string.sub(hex,2),16) or 0
	return Color3.fromRGB(bit32.extract(value,16,8),bit32.extract(value,8,8),bit32.extract(value,0,8))
end
function Renderer.destroy() if current then current:Destroy() end end
function Renderer.setWeather(value:string?) if value then weather=value end end
function Renderer.start(map:any,parent:Instance)
	Renderer.destroy()
	local assets=script.Parent.Parent:FindFirstChild("DevAssets")
	local module=assets and assets:FindFirstChild("OrigPowerLines_"..map.data.id)
	if not module then return end -- Maps without a generated plan have no visual power layer.
	local ok,data=pcall(require,module :: ModuleScript)
	if not ok then warn("[PowerLines] Local art/layout unavailable:",data);return end
	local folder=Instance.new("Folder");folder.Name="PowerInfrastructure";folder.Parent=parent;current=folder
	local image:EditableImage?=nil
	local preferHalf,disabled=false,false
	local divisor,retry,idle,acc=1,0,os.clock(),0
	local cached:{[number]:buffer}={}
	local nodes:{[number]:any}={}
	local tiles:{[string]:any}={}
	local raised:{[any]:boolean}={}
	local look=data.config.look
	local wireInk=color(look.wire.ink)
	local function clear()
		table.clear(raised)
		for _,v in nodes do v.part:Destroy() end;table.clear(nodes)
		for _,v in tiles do v.part:Destroy() end;table.clear(tiles)
		Memory.release(image);image=nil
	end
	local unregister=Memory.register(10,function() clear();retry=os.clock()+5 end)
	local function atlas():boolean
		if image then return true end
		if os.clock()<retry or disabled then return false end
		local variant=if preferHalf then data.half else data
		image=Memory.create(Vector2.new(variant.width,variant.height),"detail")
		if not image and not preferHalf and data.half then
			preferHalf=true;variant=data.half;image=Memory.create(Vector2.new(variant.width,variant.height),"detail")
		end
		if not image then retry=os.clock()+5;return false end
		divisor=if preferHalf then 2 else 1
		local loaded,err=pcall(function()
			cached[divisor]=cached[divisor] or Inflate.raw(Codec.base64Decode(variant.deflate),variant.width*variant.height*4)
			local target=image :: EditableImage
			target:WritePixelsBuffer(Vector2.zero,Vector2.new(variant.width,variant.height),cached[divisor])
		end)
		if not loaded then clear();disabled=true;warn("[PowerLines] Atlas unavailable:",err);return false end
		return true
	end
	local function place(v:any)
		local layout=v.layout;local x,y=layout.x,layout.y;local ratio=1
		local camera=workspace.CurrentCamera
		if layout.height~=layout.base and camera then
			local p=camera.CFrame.Position
			local floorY=World.GROUND_Y or 0
			-- Put the lifted top face on the same camera rays as its ordinary map plane.
			-- This preserves joins with revealed spans instead of introducing height parallax.
			local distance=p.Y-floorY-layout.base-.005
			if distance>1 then
				ratio=math.max(.01,(p.Y-floorY-layout.height-.005)/distance)
				x=(p.X+(x*S-p.X)*ratio)/S;y=(p.Z+(y*S-p.Z)*ratio)/S
			end
		end
		v.part.Size=Vector3.new(layout.h*S*ratio,.01,layout.w*S*ratio)
		v.part.CFrame=CFrame.new(World.toWorld(x,y,layout.height))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
	end
	local function surface(name:string,x:number,y:number,w:number,h:number,height:number,base:number):any
		local part=Instance.new("Part");part.Name=name;part.Anchored=true;part.Transparency=1
		part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
		local v={part=part,layout={x=x,y=y,w=w,h=h,height=height,base=base}}
		if height~=base then raised[v]=true end
		place(v)
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0;gui.ClipsDescendants=false;gui.Parent=part
		part.Destroying:Connect(function() raised[v]=nil end)
		v.gui=gui;part.Parent=folder;return v
	end
	local function nodeView(n:any,fogged:boolean):any
		local size=if n.plant then look.plant.cells else data.frame/data.px
		local v=surface(if n.plant then "NeutralPowerPlant" elseif n.steel then "PowerPylon" else "PowerPole",n.x,n.y,size,size,if fogged then FOG_NODE_HEIGHT else NODE_HEIGHT,NODE_HEIGHT)
		v.fogged=fogged
		v.size=size;v.gui.CanvasSize=Vector2.new(data.frame,data.frame)
		local function label():ImageLabel
			local l=Instance.new("ImageLabel");l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.ResampleMode=Enum.ResamplerMode.Default;l.Parent=v.gui;return l
		end
		v.shadow=label();v.shadow.ImageColor3=Color3.new(0,0,0)
		v.body=label()
		v.dot=Instance.new("Frame");v.dot.AnchorPoint=Vector2.new(.5,.5);v.dot.Position=UDim2.fromScale(.5,.5);v.dot.BorderSizePixel=0
		v.dot.BackgroundColor3=color(look.pylon.mid);v.dot.Parent=v.gui
		v.glow=Instance.new("Frame");v.glow.AnchorPoint=Vector2.new(.5,.5);v.glow.Position=UDim2.fromScale(.5,.5);v.glow.BorderSizePixel=0
		v.glow.BackgroundColor3=color(look.lamp);v.glow.BackgroundTransparency=.7;v.glow.Parent=v.gui
		v.beacon=Instance.new("Frame");v.beacon.AnchorPoint=Vector2.new(.5,.5);v.beacon.Position=UDim2.fromScale(.5,.5);v.beacon.BorderSizePixel=0
		v.beacon.BackgroundColor3=color(look.lamp);v.beacon.Parent=v.gui
		return v
	end
	local function rect(label:ImageLabel,r:{number})
		label.ImageContent=Content.fromObject(image :: EditableImage)
		label.ImageRectOffset=Vector2.new(r[1]/divisor,r[2]/divisor);label.ImageRectSize=Vector2.new(r[3]/divisor,r[4]/divisor)
	end
	local layers={
		{fogged=false,visible=function(x:number,y:number):boolean return not Fog.hidden(x,y) end},
		{fogged=true,visible=function(x:number,y:number):boolean return Fog.hidden(x,y) end},
	}
	local function line(a:any,b:any,width:number,alpha:number,tint:Color3,pixels:number,layer:number,view:any)
		if alpha<=0 then return end
		-- APPROX: one native GUI pixel minimum, with half a stroke of overlap at each joint.
		local stroke=math.max(1,width)
		-- Both cell sets draw. Fog selects only depth, while the disjoint canvases keep joins intact.
		for _,layerView in layers do for _,section in Power.sections(a,b,layerView.visible,TILE) do
			local x0,y0=section.tx*TILE,section.ty*TILE
			if x0>view.cx+view.rx+1 or x0+TILE<view.cx-view.rx-1 or y0>view.cy+view.ry+1 or y0+TILE<view.cy-view.ry-1 then continue end
			local key=section.tx..":"..section.ty..(if layerView.fogged then "_Fog" else "")
			local v=tiles[key]
			if not v then
				v=surface("PowerWireTile_"..key,x0+TILE/2,y0+TILE/2,TILE,TILE,if layerView.fogged then FOG_WIRE_HEIGHT else WIRE_HEIGHT,WIRE_HEIGHT)
				v.gui.ClipsDescendants=true;v.x0=x0;v.y0=y0;v.frames={};v.used=0;tiles[key]=v
			end
			v.gui.CanvasSize=Vector2.new(TILE*pixels,TILE*pixels)
			v.used+=1;local f=v.frames[v.used]
			if not f then f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.BorderSizePixel=0;f.Parent=v.gui;v.frames[v.used]=f end
			local p,q=section.a,section.b;local dx,dy=q.x-p.x,q.y-p.y
			f.Visible=true;f.ZIndex=layer
			f.Position=UDim2.fromOffset(((p.x+q.x)/2-v.x0)*pixels,((p.y+q.y)/2-v.y0)*pixels)
			f.Size=UDim2.fromOffset(math.sqrt(dx^2+dy^2)*pixels+stroke,stroke)
			f.Rotation=math.deg(math.atan2(dy,dx));f.BackgroundColor3=tint;f.BackgroundTransparency=1-alpha
		end end
	end
	local connection=RunService.Heartbeat:Connect(function(dt)
		acc+=dt;if acc<.1 or disabled then return end;acc=0
		local camera=workspace.CurrentCamera;if not camera then return end
		local view=WorldLight.view(camera);local px=view.cellPixels
		if px<2.2 then clear();return end
		local light=Daylight.get();local sun=light.shadow or {0,0}
		local near=px>=look.towersFrom
		local candidates={}
		for _,n in data.nodes do
			if math.abs(n.x-view.cx)>view.rx+4 or math.abs(n.y-view.cy)>view.ry+4 then continue end
			table.insert(candidates,{n=n,d=(n.x-view.cx)^2+(n.y-view.cy)^2})
		end
		table.sort(candidates,function(a,b) return if a.d==b.d then a.n.id<b.n.id else a.d<b.d end)
		local wanted={};local usingImage=false
		for i=1,#candidates do
			local n=candidates[i].n
			local detailed=(near or n.plant) and atlas()
			wanted[n.id]=true
			local fogged=Fog.hidden(n.x,n.y)
			local v=nodes[n.id]
			if not v then v=nodeView(n,fogged);nodes[n.id]=v
			elseif v.fogged~=fogged then
				v.fogged=fogged
				v.layout.height=if fogged then FOG_NODE_HEIGHT else NODE_HEIGHT
				raised[v]=if fogged then true else nil;place(v)
			end
			v.dot.Visible=not detailed;v.body.Visible=detailed;v.shadow.Visible=detailed and not n.plant
			if v.dot.Visible then
				local dot=if n.plant then 1 else math.max(2,math.floor(px*.55+.5))/px/v.size
				v.dot.Size=UDim2.fromScale(dot,dot)
				v.dot.BackgroundColor3=color(if n.plant then look.plant.neutral elseif n.steel then look.pylon.mid else look.pole.wood)
			end
			if v.body.Visible then
				usingImage=true
				local r
				if n.plant then r=data.plantRect else
					local angle=math.atan2(n.ay,n.ax)
					local facing=math.floor(angle/(math.pi*2)*data.facings+.5)%data.facings
					local residual=(angle-facing/data.facings*math.pi*2+math.pi)%(math.pi*2)-math.pi
					v.body.Rotation=math.deg(residual);v.shadow.Rotation=math.deg(residual)
					r={facing*data.frame,(if n.steel then 0 elseif n.feed then 2 else 1)*data.frame,data.frame,data.frame}
				end
				rect(v.body,r)
				if v.shadow.Visible then
					rect(v.shadow,r)
					-- APPROX: translated sprite shadow replaces the source's height-varying tower lines.
					local height=if n.steel then look.pylon.height else look.pole.height
					v.shadow.Position=UDim2.fromScale(sun[1]*look.wire.shadowReach*height/v.size,sun[2]*look.wire.shadowReach*height/v.size)
					v.shadow.ImageTransparency=1-look.shadow.alpha*(light.shadowAlpha or 1)
				end
			end
			local lit=near and n.steel and light.night>.35 and (view.time%look.lampSec)/look.lampSec<look.lampOn
			v.beacon.Visible=lit;v.glow.Visible=lit
			if lit then
				v.beacon.Size=UDim2.fromScale(2/px/v.size,2/px/v.size)
				v.glow.Size=UDim2.fromScale(10/px/v.size,10/px/v.size)
			end
		end
		for id,v in nodes do if not wanted[id] then v.part:Destroy();nodes[id]=nil end end
		local links={}
		for id,link in data.links do
			local a,b=data.nodes[link.a],data.nodes[link.b]
			if math.max(a.x,b.x)<view.cx-view.rx-5 or math.min(a.x,b.x)>view.cx+view.rx+5 or math.max(a.y,b.y)<view.cy-view.ry-5 or math.min(a.y,b.y)>view.cy+view.ry+5 then continue end
			table.insert(links,{id=id,link=link,d=((a.x+b.x)/2-view.cx)^2+((a.y+b.y)/2-view.cy)^2})
		end
		table.sort(links,function(a,b) return if a.d==b.d then a.id<b.id else a.d<b.d end)
		for _,v in tiles do v.used=0 end
		local width,alpha=Power.style(data.config,px)
		local quality=if px<8 then 2 elseif px<14 then 4 else look.wire.steps
		local motion=Power.motion(weather)
		for i=1,#links do
			local entry=links[i];local link=entry.link
			local curves=Power.curves(data,link,view.time,px,motion,quality);if #curves==0 then continue end
			if near then
				local points=Power.shadow(data,link,sun)
				for j=2,#points do line(points[j-1],points[j],width,look.wire.shadowAlpha*(light.shadowAlpha or 1),Color3.new(0,0,0),px,1,view) end
			end
			for _,points in curves do for j=2,#points do line(points[j-1],points[j],width,alpha,wireInk,px,2,view) end end
		end
		for key,v in tiles do
			if v.used==0 then v.part:Destroy();tiles[key]=nil
			else for j=v.used+1,#v.frames do v.frames[j].Visible=false end end
		end
		if usingImage then idle=os.clock() elseif image and os.clock()-idle>3 then Memory.release(image);image=nil end
	end)
	local previousCamera:any=nil;local previousPosition:Vector3?=nil
	local projection=RunService.RenderStepped:Connect(function()
		local camera=workspace.CurrentCamera;if not camera then return end
		local position=camera.CFrame.Position
		if camera==previousCamera and position==previousPosition then return end
		previousCamera,previousPosition=camera,position
		for v in raised do place(v) end
	end)
	folder.Destroying:Connect(function() connection:Disconnect();projection:Disconnect();unregister();clear();if current==folder then current=nil end end)
	print(`[PowerLines] {map.data.id}: {#data.nodes-data.plantCount} visual poles/pylons, {data.plantCount} neutral plants`)
end
return Renderer
