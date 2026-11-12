--!strict
-- Original factory parts share the existing building atlas; no images/particles allocated per site.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Motion=require(Shared.Presentation.FactoryMotion)
local Rng=require(Shared.Utilities.Rng)
local Factory={}
local views:{[any]:boolean}={}
local function colour(hex:string):Color3
	local n=tonumber(string.sub(hex,2),16) or 16777215
	return Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255))
end
function Factory.attach(gui:SurfaceGui,meta:any,sheet:any):any
	local cfg=meta.factory;if not cfg then return nil end
	local h:any={gui=gui,cfg=cfg,sheet=sheet,state=Motion.new(),doors={},crane={},sparks={},all={},id=0,built=0,stale=true,last=0}
	local function layer(key:any):any
		local r=key and sheet.meta.rects[tostring(key)];if not r then return nil end
		local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.ResampleMode=Enum.ResamplerMode.Pixelated
		label.ImageContent=Content.fromObject(sheet.image);label.ImageRectOffset=Vector2.new(r[1],r[2]);label.ImageRectSize=Vector2.new(r[3],r[4]);label.Visible=false
		label.ZIndex=4;label.Parent=gui;table.insert(h.all,label)
		return {label=label,rect=r}
	end
	for _=1,#cfg.doors do table.insert(h.doors,{base=layer(cfg.door.base),paint=layer(cfg.door.paint)}) end
	if cfg.craneArt then h.crane={base=layer(cfg.craneArt.base),paint=layer(cfg.craneArt.paint)} end
	for _=1,cfg.weld.count do
		local spark=Instance.new("Frame");spark.BorderSizePixel=0;spark.Visible=false;spark.ZIndex=5;spark.AnchorPoint=Vector2.new(.5,.5);spark.Parent=gui
		table.insert(h.sparks,spark);table.insert(h.all,spark)
	end
	views[h]=true
	gui.Destroying:Connect(function() views[h]=nil;h.dead=true end)
	return h
end
local function render(h:any,clock:number)
	local cfg=h.cfg;local visible=h.built>=1;local cells=cfg.cells
	for index,door in h.doors do
		local pose=Motion.door(cfg,h.state.open,index)
		local sx,sy=math.floor(pose.sx+.5),math.floor(pose.sy+.5)
		local sw=math.max(1,math.floor(pose.sw+.5));local sh=math.max(1,math.floor(pose.sh+.5))
		for kind,layer in door do
			local label,r=layer.label,layer.rect;label.Visible=visible and pose.visible
			label.ImageColor3=if kind=="paint" then h.tint else h.base;label.ImageTransparency=h.alpha
			label.ImageRectOffset=Vector2.new(r[1]+sx,r[2]+sy)
			label.ImageRectSize=Vector2.new(math.min(sw,r[3]-sx),math.min(sh,r[4]-sy))
			label.Position=UDim2.fromScale(.5+pose.x/cells,.5+pose.y/cells);label.Size=UDim2.fromScale(pose.w/cells,pose.h/cells)
		end
	end
	if cfg.craneArt then
		local pose=Motion.crane(cfg,h.state,clock,h.id);local size=cfg.craneArt.cells/cells
		for kind,layer in h.crane do
			local label=layer.label;label.Visible=visible;label.ImageColor3=if kind=="paint" then h.tint else h.base;label.ImageTransparency=h.alpha
			label.Position=UDim2.fromScale(.5+pose.x/cells-size/2,.5+pose.y/cells-size/2);label.Size=UDim2.fromScale(size,size)
		end
	end
	local points=if visible and not h.stale and h.state.busy then Motion.weld(cfg,clock,h.id,Rng.imul) else {}
	for i,spark in h.sparks do
		local p=points[i];spark.Visible=p~=nil
		if p then
			-- APPROX native UI: bright opaque source-colour sparks replace additive Canvas2D blending.
			spark.BackgroundColor3=colour(p.ink);spark.BackgroundTransparency=0
			spark.Position=UDim2.fromScale(.5+p.x/cells,.5+p.y/cells);spark.Size=UDim2.fromScale(p.size/cfg.frame,p.size/cfg.frame)
		end
	end
end
function Factory.sync(h:any,built:number,stale:boolean,sample:any,id:number,base:Color3,tint:Color3,alpha:number)
	if not h or h.dead then return end
	local now=os.clock();local dt=if h.at then math.max(0,now-h.at) else 0
	h.last=now;h.at=now;h.id=id;h.built=built;h.stale=stale;h.sample=sample;h.base=base;h.tint=tint;h.alpha=alpha
	Motion.advance(h.state,h.cfg,sample,now,dt,not stale and built>=1)
	render(h,now)
end
function Factory.step()
	local now=os.clock()
	for h in views do
		if not h.at then continue end
		if now-h.last>.25 then
			Motion.advance(h.state,h.cfg,nil,now,0,false);for _,spark in h.sparks do spark.Visible=false end
			h.at=nil
		else
			Motion.advance(h.state,h.cfg,h.sample,now,now-h.at,not h.stale and h.built>=1);h.at=now;render(h,now)
		end
	end
end
function Factory.reset()
	for h in views do h.dead=true;for _,item in h.all do item:Destroy() end end;table.clear(views)
end
function Factory.count():number local n=0;for _ in views do n+=1 end;return n end
return Factory
