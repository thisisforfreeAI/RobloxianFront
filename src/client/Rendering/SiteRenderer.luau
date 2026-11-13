--!strict
-- Site accents reuse the core alpha mask. No new EditableImages or per-site pixel buffers.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Motion=require(Shared.Presentation.SiteMotion)
local Pieces=require(Shared.Presentation.ConstructionPieces)
local Rng=require(Shared.Utilities.Rng)
local Renderer={}
local views:{[any]:boolean}={}
-- APPROX native UI policy: eight visible fallback sites, with cells >=2 screen pixels.
local pieceOwners:{[any]:boolean}={}
local function clearPieces(h:any)
	if not h.pieceRoot and not pieceOwners[h] then return end
	if h.pieceRoot then h.pieceRoot:Destroy() end
	h.pieceRoot=nil;h.pieceLayers={};h.pieceFrames={};h.pieceBuilt=nil;h.pieceContent=nil;h.pieceImage=nil
	pieceOwners[h]=nil
end
local function colour(value:any):Color3
	if type(value)=="table" then return Color3.fromRGB(value[1],value[2],value[3]) end
	local n=tonumber(string.sub(value,2),16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255))
end
local function clear(h:any)
	clearPieces(h)
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
local function acquirePieces(h:any):boolean
	if pieceOwners[h] then return true end
	local count=0;local lowest=nil
	for owner in pieceOwners do count+=1;if not lowest or owner.score<lowest.score then lowest=owner end end
	if count>=8 then
		if not lowest or h.score<=lowest.score+.25 then return false end
		clearPieces(lowest)
	end
	pieceOwners[h]=true;return true
end
local function renderPieces(h:any)
	local c=h.cfg.pieces;local context=h.context;local state=h.state
	local progress=if state and not state.hidden and state.built<1 then Motion.raise(state.built,h.cfg.yardShare) else nil
	if h.covered or h.stale or not c or not context or progress==nil or h.side<c.count*2 or not h.meta.base then clearPieces(h);return end
	if not acquirePieces(h) then return end
	if h.pieceRoot and h.pieceBuilt==state.built and h.pieceSide==h.side and h.pieceBase==context.base and h.pieceTint==context.tint and h.pieceImage==h.core.image then return end
	if not h.order or h.orderId~=context.id or h.orderCount~=c.count then h.order=Pieces.order(c,context.id,Rng.imul);h.orderId=context.id;h.orderCount=c.count end
	if not h.pieceRoot then
		h.pieceRoot=frame(h.root,3);h.pieceRoot.Name="ConstructionPieces";h.pieceRoot.BackgroundTransparency=1;h.pieceRoot.Size=UDim2.fromScale(1,1);h.pieceRoot.ClipsDescendants=false
		h.pieceLayers={};h.pieceFrames={}
	end
	if h.pieceImage~=h.core.image then h.pieceImage=h.core.image;h.pieceContent=Content.fromObject(h.core.image) end
	for _,layers in h.pieceLayers do for _,label in layers do label.Visible=false end end
	local pose=Pieces.geometry(h.cfg,progress,h.side,h.order)
	for _,tile in pose.tiles do
		local layers=h.pieceLayers[tile.cell];if not layers then layers={};h.pieceLayers[tile.cell]=layers end
		for _,kind in {"base","paint"} do
			local key=h.meta[kind];local r=key and h.core.meta.rects[tostring(key)]
			local crop=r and Pieces.crop(r,h.meta.frame,c.count,tile.col,tile.row)
			if not crop then continue end
			local label=layers[kind]
			if not label then label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.ResampleMode=Enum.ResamplerMode.Pixelated;label.ZIndex=1;label.Parent=h.pieceRoot;layers[kind]=label end
			label.Visible=tile.alpha>0;label.ImageContent=h.pieceContent;label.ImageRectOffset=Vector2.new(crop.sx,crop.sy);label.ImageRectSize=Vector2.new(crop.sw,crop.sh)
			label.Position=UDim2.fromScale(crop.x,crop.y+tile.dy/h.side);label.Size=UDim2.fromScale(crop.w,crop.h)
			label.ImageColor3=if kind=="paint" then context.tint else context.base;label.ImageTransparency=1-tile.alpha
		end
	end
	for i,r in pose.rects do
		local item=h.pieceFrames[i];if not item then item=frame(h.pieceRoot,2);h.pieceFrames[i]=item end
		item.Visible=true;item.Position=UDim2.fromScale(r.x,r.y);item.Size=UDim2.fromScale(r.w,r.h);item.BackgroundColor3=colour(h.cfg.accent);item.BackgroundTransparency=1-r.alpha
	end
	for i=#pose.rects+1,#h.pieceFrames do h.pieceFrames[i].Visible=false end
	h.pieceBuilt=state.built;h.pieceSide=h.side;h.pieceBase=context.base;h.pieceTint=context.tint
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
	renderPieces(h)
end
function Renderer.sync(h:any,state:any,stale:boolean,side:number?,context:any?)
	if not h or h.dead then return end
	if context and h.context and context.id~=h.context.id then clearPieces(h);h.order=nil end
	h.context=context;h.score=if context then context.score or 0 else 0
	h.state=state;h.stale=stale;h.side=math.max(1,side or h.meta.frame);h.last=os.clock();h.at=h.last;render(h,h.last)
end
function Renderer.covered(h:any,covered:boolean)
	if not h or h.dead or h.covered==covered then return end
	h.covered=covered
	if covered then clearPieces(h) elseif h.at then render(h,os.clock()) end
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
function Renderer.pieceCount():number local n=0;for _ in pieceOwners do n+=1 end;return n end
return Renderer
