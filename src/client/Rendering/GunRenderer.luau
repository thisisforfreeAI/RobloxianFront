--!strict
-- AT/bunker guns: optional shared facing atlas, always-available resting pose from the body atlas.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Motion=require(ReplicatedStorage:WaitForChild("Shared").Presentation.GunMotion)
local Gun={}
local views:{[any]:boolean}={}
local function ink(hex:string):Color3
	local n=tonumber(string.sub(hex,2),16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255))
end
local function picture(parent:any,z:number):ImageLabel
	local image=Instance.new("ImageLabel");image.BackgroundTransparency=1;image.ResampleMode=Enum.ResamplerMode.Pixelated
	image.ZIndex=z;image.Visible=false;image.Parent=parent;return image
end
function Gun.attach(gui:SurfaceGui,meta:any,core:any):any
	local cfg=meta.gun;if not cfg then return nil end
	local h:any={cfg=cfg,meta=meta,core=core,id=0,state=Motion.new(cfg,0),all={},last=0}
	local function frame(z:number):Frame
		local root=Instance.new("Frame");root.BackgroundTransparency=1;root.ClipsDescendants=false;root.AnchorPoint=Vector2.new(.5,.5);root.ZIndex=z;root.Parent=gui
		root.Size=UDim2.fromScale(cfg.cells/cfg.footprint,cfg.cells/cfg.footprint);table.insert(h.all,root);return root
	end
	if cfg.kind~="bunker" then h.shadowRoot=frame(3);h.shadow=picture(h.shadowRoot,3);h.shadow.ImageColor3=ink(cfg.shadowInk) end
	h.root=frame(4);h.base=picture(h.root,4);h.paint=picture(h.root,4)
	if cfg.cap then
		h.cap={base=picture(gui,5),paint=picture(gui,5)}
		for _,image in h.cap do table.insert(h.all,image) end
	end
	views[h]=true
	gui.Destroying:Connect(function() h.dead=true;views[h]=nil end)
	return h
end
local function bind(image:ImageLabel,sheet:any,key:any,frame:number,visible:boolean)
	local rect=key and sheet.meta.rects[tostring(key)]
	image.Visible=visible and rect~=nil
	if not rect then return end
	image.ImageContent=Content.fromObject(sheet.image)
	image.ImageRectOffset=Vector2.new(rect[1],rect[2]);image.ImageRectSize=Vector2.new(rect[3],rect[4])
	image.Position=UDim2.fromScale(rect[5]/frame,rect[6]/frame);image.Size=UDim2.fromScale(rect[3]/frame,rect[4]/frame)
end
local function render(h:any,now:number)
	if not h.at then return end
	local cfg=h.cfg;local live=h.built>=1
	local name=if h.driven then h.driven.part elseif cfg.parts then cfg.parts[Motion.samStage(cfg,Motion.time(h.state,now)-h.state.shotAt,h.state.reload or 0)+1] else cfg.part
	if h.stale then name=if cfg.parts then cfg.parts[3] else cfg.part end
	local part=h.bank and h.bank.meta.parts[name]
	local sheet=if part then h.bank else h.core
	local pose:any
	if h.driven then
		local headings=if part then #part.frames else 1;local fraction=(h.driven.heading/(math.pi*2))%1;local index=math.floor(fraction*headings+.5)
		pose={index=index%headings+1,residual=if headings>1 then (fraction-index/headings)*math.pi*2 else 0,x=h.driven.x,y=h.driven.y,kick=h.driven.kick}
	else pose=Motion.pose(h.state,cfg,now,if part then #part.frames else 1) end
	if not part or h.stale then pose={index=1,residual=0,x=cfg.x,y=cfg.y,kick=0} end
	local frame=if part then part.frames[pose.index] else cfg.fallback
	if h.boundImage~=sheet.image or h.index~=pose.index or h.boundPart~=name or h.wasVisible~=live then
		bind(h.base,sheet,frame.base,cfg.frame,live);bind(h.paint,sheet,frame.paint,cfg.frame,live)
		if h.shadow then bind(h.shadow,sheet,frame.base,cfg.frame,live) end
		h.boundImage=sheet.image;h.index=pose.index;h.boundPart=name;h.wasVisible=live
	end
	h.base.ImageColor3=h.baseTint;h.paint.ImageColor3=h.paintTint;h.base.ImageTransparency=h.alpha;h.paint.ImageTransparency=h.alpha
	local x,y=.5+pose.x/cfg.footprint,.5+pose.y/cfg.footprint
	h.root.Position=UDim2.fromScale(x,y);h.root.Rotation=math.deg(pose.residual)
	if h.shadow then
		local reach=cfg.shadowScale*(if part then part.tall else cfg.tall)*cfg.cells/cfg.frame/cfg.footprint
		h.shadowRoot.Position=UDim2.fromScale(x+h.light.shadow[1]*reach,y+h.light.shadow[2]*reach)
		h.shadowRoot.Rotation=h.root.Rotation
		-- APPROX native alpha matches the existing structure-shadow policy; source height/reach is exact.
		h.shadow.ImageTransparency=1-.35*h.light.shadowAlpha*(1-h.alpha)
	end
	if h.cap then
		for layer,image in h.cap do
			if not h.capBound or h.capVisible~=live then bind(image,h.core,cfg.cap[layer],h.meta.frame,live) end
			image.ImageColor3=if layer=="paint" then h.paintTint else h.baseTint;image.ImageTransparency=h.alpha
		end
		h.capBound=true;h.capVisible=live
	end
end
function Gun.sync(h:any,built:number,stale:boolean,sample:any,id:number,base:Color3,paint:Color3,alpha:number,light:any,bank:any,driven:any?)
	if not h or h.dead then return end
	local now=os.clock();local dt=if h.at then math.max(0,now-h.at) else 0
	if h.id~=id then h.state=Motion.new(h.cfg,id) end
	h.id=id;h.built=built;h.stale=stale;h.sample=sample;h.baseTint=base;h.paintTint=paint;h.alpha=alpha;h.light=light;h.bank=bank;h.last=now;h.driven=driven
	if not driven then Motion.advance(h.state,h.cfg,sample,now,dt,not stale and built>=1,id) end;h.at=now;render(h,now)
end
function Gun.step()
	local now=os.clock()
	for h in views do
		if h.driven then continue end -- The artillery owner advances these paired mechanisms together.
		if not h.at then continue end
		if now-h.last>.25 then
			Motion.advance(h.state,h.cfg,nil,now,0,false,h.id);h.at=nil
		else
			Motion.advance(h.state,h.cfg,h.sample,now,now-h.at,not h.stale and h.built>=1,h.id);h.at=now;render(h,now)
		end
	end
end
function Gun.forgetSheet(image:any)
	for h in views do if h.bank and h.bank.image==image then h.bank=nil;h.boundImage=nil;render(h,os.clock()) end end
end
function Gun.reset()
	for h in views do h.dead=true;for _,item in h.all do item:Destroy() end end;table.clear(views)
end
function Gun.count():number local n=0;for _ in views do n+=1 end;return n end
return Gun
