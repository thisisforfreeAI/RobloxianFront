--!strict
-- Screen-space vector guides avoid large world GUI textures and allocate no EditableImages.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Motion=require(Shared.Presentation.CoverageMotion)
local Art=require(script.Parent.StructureArt)
local Renderer={}
local current:any=nil
local colours:{[any]:Color3}={}
local function colour(value:any):Color3
	if colours[value] then return colours[value] end
	if type(value)=="table" then local c=Color3.fromRGB(value[1],value[2],value[3]);colours[value]=c;return c end
	local n=tonumber(string.sub(value,2),16) or 0
	local c=Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255));colours[value]=c;return c
end
local function frame(parent:any,z:number):any
	local item=Instance.new("Frame");item.BorderSizePixel=0;item.AnchorPoint=Vector2.new(.5,.5);item.ZIndex=z;item.Parent=parent;return item
end
local function disc(parent:any,z:number):any
	local item=frame(parent,z);local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=item;return item
end
local function circle(item:any,x:number,y:number,radius:number,ink:any,alpha:number)
	item.Visible=radius>0 and alpha>0
	item.Position=UDim2.fromOffset(x,y);item.Size=UDim2.fromOffset(radius*2,radius*2)
	item.BackgroundColor3=colour(ink);item.BackgroundTransparency=1-alpha
end
local function strokes(parent:any,pool:any,radius:number,dash:any,limit:number,width:number,ink:any,alpha:number)
	if pool.radius~=radius or pool.dash~=dash then pool.pieces=Motion.dashes(radius,dash,limit);pool.radius=radius;pool.dash=dash;pool.dirty=true end
	for i,p in pool.pieces do
		local item=pool[i]
		if not item then item=frame(parent,2);pool[i]=item;pool.dirty=true end
		item.Visible=true
		if pool.dirty then item.Position=UDim2.fromOffset(p.x,p.y);item.Size=UDim2.fromOffset(p.length,width);item.Rotation=p.rotation end
		item.BackgroundColor3=colour(ink);item.BackgroundTransparency=1-alpha
	end
	for i=#pool.pieces+1,#pool do pool[i].Visible=false end
	pool.dirty=false
end
local function owner(gui:any):any
	local root=frame(gui,1);root.BackgroundTransparency=1;root.Size=UDim2.fromOffset(0,0)
	local turn=frame(root,3);turn.BackgroundTransparency=1;turn.Size=UDim2.fromOffset(0,0)
	local h={root=root,turn=turn,fill=disc(root,1),range={},back={},dash={},glow={},ticks={}}
	for i=1,8 do h.glow[i]=disc(root,2) end
	for i=1,4 do h.ticks[i]=frame(root,4) end
	return h
end
function Renderer.destroy() if current then local h=current;current=nil;h.gui:Destroy() end;table.clear(colours) end
function Renderer.hide() if current then current.gui.Enabled=false end end
local function host():any
	if current then return current end
	local player=Players.LocalPlayer;local parent=player and player:FindFirstChild("PlayerGui");if not parent then return nil end
	local gui=Instance.new("ScreenGui");gui.Name="PlacementCoverage";gui.IgnoreGuiInset=true;gui.DisplayOrder=-2;gui.ResetOnSpawn=false;gui.Parent=parent
	local h={gui=gui,sites={}};current=h;gui.Destroying:Connect(function() if current==h then current=nil end end);return h
end
function Renderer.update(kind:string,cx:number,cy:number,side:number,rules:any,views:any,pixels:number)
	local config=Art.coverageStyle();local camera=workspace.CurrentCamera
	if not config or not rules or not camera then Renderer.hide();return end
	local plan=Motion.plan(config,kind,cx,cy,side,rules,views,pixels,function(x,y)
		local p=camera:WorldToViewportPoint(World.toWorld(x,y,.7));return p.X,p.Y,p.Z
	end,camera.ViewportSize.X,camera.ViewportSize.Y)
	local h=host();if not h then return end;h.gui.Enabled=true
	local used={};local now=os.clock()
	for _,site in plan.sites do
		local v=h.sites[site.id];if not v then v=owner(h.gui);h.sites[site.id]=v end;used[site.id]=true
		v.root.Visible=true;v.root.Position=UDim2.fromOffset(site.x,site.y)
		local ink=if site.own then config.own else config.other
		circle(v.fill,0,0,site.radius,ink,config.same.fillAlpha)
		strokes(v.root,v.range,site.radius,config.same.dash,64,config.same.linePx,ink,config.same.lineAlpha)
		local marker=Motion.marker(config,site.token,now);v.turn.Rotation=marker.rotation
		strokes(v.turn,v.back,marker.radius,config.marker.dash,40,config.marker.backingPx,config.backing.rgb,config.backing.alpha)
		strokes(v.turn,v.dash,marker.radius,config.marker.dash,40,config.marker.linePx,ink,marker.alpha)
		local previous=0
		-- APPROX eight nested discs replace the source's smooth radial gradient; centre alpha agrees.
		for i,item in v.glow do
			local alpha=marker.glow*i/#v.glow;circle(item,0,0,marker.outer-(marker.outer-marker.inner)*(i-1)/(#v.glow-1),ink,(alpha-previous)/(1-previous));previous=alpha
		end
		for i,item in v.ticks do
			local angle=(i-1)*math.pi/2;item.Position=UDim2.fromOffset(math.cos(angle)*(marker.radius+config.marker.tickPx/2),math.sin(angle)*(marker.radius+config.marker.tickPx/2))
			item.Size=UDim2.fromOffset(config.marker.tickPx,config.marker.linePx);item.Rotation=math.deg(angle);item.BackgroundColor3=colour(ink);item.BackgroundTransparency=0
		end
	end
	for id,v in h.sites do if not used[id] then v.root:Destroy();h.sites[id]=nil end end
	if plan.ghost then
		if not h.ghost then local root=frame(h.gui,2);root.BackgroundTransparency=1;root.Size=UDim2.fromOffset(0,0);h.ghost={root=root,fill=disc(root,1),lines={}} end
		local g=h.ghost;g.root.Visible=true;g.root.Position=UDim2.fromOffset(plan.ghost.x,plan.ghost.y)
		circle(g.fill,0,0,plan.ghost.radius,config.radar.rgb,config.radar.fillAlpha)
		strokes(g.root,g.lines,plan.ghost.radius,config.radar.dash,64,config.radar.linePx,config.radar.rgb,config.radar.lineAlpha)
	elseif h.ghost then h.ghost.root:Destroy();h.ghost=nil end
end
return Renderer
