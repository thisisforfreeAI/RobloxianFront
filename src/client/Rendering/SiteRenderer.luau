--!strict
-- Site accents reuse the core alpha mask. No new EditableImages or per-site pixel buffers.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Motion=require(ReplicatedStorage:WaitForChild("Shared").Presentation.SiteMotion)
local Renderer={}
local views:{[any]:boolean}={}
local function colour(value:any):Color3
	if type(value)=="table" then return Color3.fromRGB(value[1],value[2],value[3]) end
	local n=tonumber(string.sub(value,2),16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255))
end
local function clear(h:any)
	if not h.root then return end
	h.root:Destroy();if h.overlay then h.overlay:Destroy() end;h.root=nil;h.overlay=nil;h.pool={};h.previous={};h.blueprint=nil;h.drop=nil;h.done=nil;h.laser=nil
end
function Renderer.attach(gui:any,meta:any,core:any,config:any,cells:number):any
	if not config then return nil end
	local h:any={gui=gui,meta=meta,core=core,cfg=config,cells=cells,pool={},previous={},last=0}
	views[h]=true;gui.Destroying:Connect(function() h.dead=true;clear(h);views[h]=nil end)
	return h
end
local function frame(parent:any,z:number):Frame
	local item=Instance.new("Frame");item.BorderSizePixel=0;item.ZIndex=z;item.Parent=parent
	return item
end
local function picture(h:any,z:number):any
	local mask=h.meta.siteMask;local r=mask and h.core.meta.rects[tostring(mask.tile)]
	if not r then return nil end
	local item=Instance.new("ImageLabel");item.BackgroundTransparency=1;item.ZIndex=z;item.Visible=false
	item.ImageContent=Content.fromObject(h.core.image);item.ImageRectOffset=Vector2.new(r[1],r[2]);item.ImageRectSize=Vector2.new(r[3],r[4])
	item.ResampleMode=Enum.ResamplerMode.Pixelated;item.Size=UDim2.fromScale(r[3]/mask.frame,r[4]/mask.frame);item.Parent=if z>=6 then h.overlay else h.root
	return {label=item,x=r[5]/mask.frame,y=r[6]/mask.frame}
end
local function show(p:any,ink:any,alpha:number,lift:number?)
	if not p then return end
	p.label.Visible=alpha>0;p.label.ImageColor3=colour(ink);p.label.ImageTransparency=1-math.clamp(alpha,0,1)
	p.label.Position=UDim2.fromScale(p.x,p.y+(lift or 0))
end
local function root(h:any)
	if h.root then return end
	h.root=frame(h.gui,1);h.root.Name="ConstructionSite";h.root.BackgroundTransparency=1;h.root.Size=UDim2.fromScale(1,1);h.root.ClipsDescendants=false
	h.overlay=frame(h.gui,8);h.overlay.Name="ConstructionFlash";h.overlay.BackgroundTransparency=1;h.overlay.Size=UDim2.fromScale(1,1);h.overlay.ClipsDescendants=false
	h.blueprint=picture(h,2);h.drop=picture(h,6);h.done=picture(h,8)
	if h.done then
		local gradient=Instance.new("UIGradient");gradient.Rotation=45;gradient.Parent=h.done.label;h.done.gradient=gradient
	end
	h.laser=frame(h.root,4);h.laser.Visible=false
	local inks=h.cfg.site.laserInks
	local gradient=Instance.new("UIGradient");gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,colour(inks[1])),ColorSequenceKeypoint.new(.5,colour(inks[2])),ColorSequenceKeypoint.new(1,colour(inks[3]))})
	gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})
	gradient.Parent=h.laser;h.laser.BackgroundColor3=Color3.new(1,1,1)
end
local function render(h:any,now:number)
	local pose=if h.stale then nil else Motion.geometry(h.cfg,h.state,h.side,h.cells,now)
	if not pose or not pose.active then clear(h);h.at=nil;return end
	root(h)
	for i,r in pose.rects do
		local item=h.pool[i]
		if not item then item=frame(if r.z>=6 then h.overlay else h.root,r.z);h.pool[i]=item end
		local old=h.previous[i]
		if not old then item.Visible=true end
		if not old or old.z~=r.z then item.ZIndex=r.z;item.Parent=if r.z>=6 then h.overlay else h.root end
		if not old or old.ink~=r.ink then item.BackgroundColor3=colour(r.ink) end
		if not old or old.alpha~=r.alpha then item.BackgroundTransparency=1-math.clamp(r.alpha,0,1) end
		if not old or old.x~=r.x or old.y~=r.y then item.Position=UDim2.fromScale(r.x,r.y) end
		if not old or old.w~=r.w or old.h~=r.h then item.Size=UDim2.fromScale(r.w,r.h) end
		h.previous[i]=r
	end
	for i=#pose.rects+1,#h.pool do h.pool[i].Visible=false;h.previous[i]=nil end
	show(h.blueprint,h.cfg.accent,pose.blueprint or 0)
	show(h.drop,h.cfg.ok,if pose.drop then pose.drop.alpha else 0,if pose.drop then pose.drop.lift else 0)
	-- APPROX native UI: the placement ghost uses the shared half-size silhouette, not a tinted body copy.
	show(h.done,{255,255,255},if pose.done then pose.done.alpha else 0)
	if h.done and pose.done then
		local numbers,colours={},{};local inks=h.cfg.done.inks;local d=pose.done
		for _,point in Motion.gradient(d.center,d.band) do
			table.insert(numbers,NumberSequenceKeypoint.new(point[1],1-point[2]))
			local t=point[2];local edge=inks[1];local middle=inks[2]
			table.insert(colours,ColorSequenceKeypoint.new(point[1],Color3.fromRGB(edge[1]+(middle[1]-edge[1])*t,edge[2]+(middle[2]-edge[2])*t,edge[3]+(middle[3]-edge[3])*t)))
		end
		-- APPROX: native alpha interpolation replaces Canvas2D additive glow and its premultiplied gradient.
		h.done.gradient.Transparency=NumberSequence.new(numbers);h.done.gradient.Color=ColorSequence.new(colours)
	end
	h.laser.Visible=pose.laser~=nil
	if pose.laser then
		h.laser.Position=UDim2.fromScale(0,pose.laser.y);h.laser.Size=UDim2.fromScale(1,pose.laser.h);h.laser.BackgroundTransparency=1-pose.laser.alpha
	end
end
function Renderer.sync(h:any,state:any,stale:boolean,side:number?)
	if not h or h.dead then return end
	h.state=state;h.stale=stale;h.side=math.max(1,side or h.meta.frame);h.last=os.clock();h.at=h.last;render(h,h.last)
end
function Renderer.step()
	local now=os.clock()
	for h in views do
		if not h.at then continue end
		if now-h.last>.25 then clear(h);h.at=nil else render(h,now) end
	end
end
function Renderer.reset() for h in views do h.dead=true;clear(h) end;table.clear(views) end
function Renderer.count():number local n=0;for _ in views do n+=1 end;return n end
return Renderer
