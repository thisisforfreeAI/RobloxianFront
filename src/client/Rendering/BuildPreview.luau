--!strict
-- One cursor GUI, sharing the structure core pages and their alpha masks. No EditableImages.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Motion=require(Shared.Presentation.PlacementMotion)
local SiteMotion=require(Shared.Presentation.SiteMotion)
local Art=require(script.Parent.StructureArt)
local Preview={}
local current:any=nil
local function ink(hex:string):Color3
	local n=tonumber(string.sub(hex,2),16) or 0
	return Color3.fromRGB(bit32.band(bit32.rshift(n,16),255),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255))
end
local function image(parent:any,z:number):ImageLabel
	local item=Instance.new("ImageLabel");item.BackgroundTransparency=1;item.Visible=false;item.ZIndex=z;item.ResampleMode=Enum.ResamplerMode.Pixelated;item.Parent=parent;return item
end
local function bind(h:any,item:any,sheet:any,key:any,frame:number,alpha:number,color:any,x:number?,y:number?,scale:number?)
	local r=key and sheet.meta.rects[tostring(key)];item.Visible=r~=nil and alpha>0
	if not r then return end
	item.ImageContent=h.content;item.ImageRectOffset=Vector2.new(r[1],r[2]);item.ImageRectSize=Vector2.new(r[3],r[4])
	local k=scale or 1;item.Position=UDim2.fromScale((x or 0)+r[5]/frame*k,(y or 0)+r[6]/frame*k);item.Size=UDim2.fromScale(r[3]/frame*k,r[4]/frame*k)
	item.ImageTransparency=1-alpha;item.ImageColor3=color
end
function Preview.destroy() if current then local h=current;current=nil;if h.partConnection then h.partConnection:Disconnect() end;h.gui:Destroy() end end
function Preview.hide() if current then current.gui.Enabled=false end end
local function attach(part:any):any
	Preview.destroy()
	local player=Players.LocalPlayer;local parent=player and player:FindFirstChild("PlayerGui");if not parent then return nil end
	local gui=Instance.new("ScreenGui");gui.Name="PlacementPreview";gui.IgnoreGuiInset=true;gui.DisplayOrder=-1;gui.ResetOnSpawn=false;gui.Parent=parent
	local root=Instance.new("Frame");root.BackgroundTransparency=1;root.ClipsDescendants=false;root.Parent=gui
	local sprite=Instance.new("Frame");sprite.BackgroundTransparency=1;sprite.ClipsDescendants=false;sprite.ZIndex=3;sprite.Parent=root
	local h:any={part=part,gui=gui,root=root,sprite=sprite,pool={},previous={},bands={},body=image(sprite,1),paint=image(sprite,2),shadow=image(root,2),scan=image(sprite,4)}
	h.gradient=Instance.new("UIGradient");h.gradient.Rotation=90;h.gradient.Parent=h.scan
	current=h;gui.Destroying:Connect(function() if h.partConnection then h.partConnection:Disconnect();h.partConnection=nil end;if current==h then current=nil end end)
	if part.Destroying then h.partConnection=part.Destroying:Connect(function() if current==h then Preview.destroy() end end) end
	return h
end
local function geometry(h:any,pose:any)
	for i,r in pose.rects do
		local item=h.pool[i];if not item then item=Instance.new("Frame");item.BorderSizePixel=0;item.ZIndex=1;item.Parent=h.root;h.pool[i]=item end
		local old=h.previous[i]
		if not old then item.Visible=true end
		if not old or old.z~=r.z then item.ZIndex=r.z end
		if not old or old.ink~=r.ink then item.BackgroundColor3=ink(r.ink) end
		if not old or old.alpha~=r.alpha then item.BackgroundTransparency=1-r.alpha end
		if not old or old.x~=r.x or old.y~=r.y then item.Position=UDim2.fromScale(r.x,r.y) end
		if not old or old.w~=r.w or old.h~=r.h then item.Size=UDim2.fromScale(r.w,r.h) end
		if not old or old.rotation~=r.rotation then item.Rotation=r.rotation end
		h.previous[i]=r
	end
	for i=#pose.rects+1,#h.pool do h.pool[i].Visible=false;h.previous[i]=nil end
end
function Preview.update(part:any,kind:string,army:string,side:number,hint:any,pixels:number):boolean
	pixels=math.max(1,pixels)
	local resource=Art.preview(kind,army,side);local cfg=resource and resource.style
	local camera=workspace.CurrentCamera
	if not cfg or not camera then Preview.hide();return false end
	local h=if current and current.part==part then current else attach(part)
	if not h then return false end
	local center=camera:WorldToViewportPoint(part.Position)
	if center.Z<=0 then Preview.hide();return true end
	h.root.Position=UDim2.fromOffset(center.X-pixels/2,center.Y-pixels/2);h.root.Size=UDim2.fromOffset(pixels,pixels)
	h.gui.Enabled=true
	local meta,sheet=resource.meta,resource.sheet
	local share=if meta and meta.defence and cfg.preview then cfg.preview.defenceShare else 1
	local pose=Motion.geometry(cfg,pixels,3,os.clock(),hint.ok,hint,share)
	geometry(h,pose);h.sprite.Position=UDim2.fromScale(pose.offset+pose.jitter/pixels,pose.offset-pose.lift/pixels);h.sprite.Size=UDim2.fromScale(pose.share,pose.share)
	local full=not cfg.preview or pixels/3>=cfg.preview.from+cfg.preview.fadePx
	h.body.Visible=false;h.paint.Visible=false;h.shadow.Visible=false;h.scan.Visible=false
	for _,band in h.bands do band.Visible=false end
	if not meta or not sheet or not full then return true end
	if h.image~=sheet.image then h.image=sheet.image;h.content=Content.fromObject(sheet.image) end
	local tone=ink(pose.ink);local tint=resource.tint;local team=Color3.new(tint[1],tint[2],tint[3])
	-- APPROX: native multiplicative tint/layer alpha replaces the source's precomposited source-atop copy.
	bind(h,h.body,sheet,meta.base,meta.frame,pose.alpha,Color3.new(1,1,1):Lerp(tone,cfg.hover.tint))
	bind(h,h.paint,sheet,meta.paint,meta.frame,pose.alpha,team:Lerp(tone,cfg.hover.tint))
	local mask=meta.siteMask;local r=mask and sheet.meta.rects[tostring(mask.tile)]
	if r then
		bind(h,h.shadow,sheet,mask.tile,mask.frame,cfg.hover.shadowAlpha,Color3.new(),pose.offset+pose.lift*.4/pixels,pose.offset+pose.lift*.5/pixels,pose.share)
		bind(h,h.scan,sheet,mask.tile,mask.frame,pose.alpha*.75,Color3.new(1,1,1))
		local keys={};local center=pose.scan*(1+cfg.hover.scanShare)-cfg.hover.scanShare/2
		for _,point in SiteMotion.gradient(center,cfg.hover.scanShare) do table.insert(keys,NumberSequenceKeypoint.new(point[1],1-point[2])) end
		h.gradient.Transparency=NumberSequence.new(keys)
		-- APPROX native UV sampling: thin source-masked scan stripes, capped at 64 at extreme zoom.
		local period=math.max(cfg.hover.scanlinePx,pose.bodySize/64);local index=0
		for at=0,pose.bodySize-1,period do
			local sy=math.floor(at/pose.bodySize*mask.frame)
			if sy<r[6] or sy>=r[6]+r[4] then continue end
			index+=1;local band=h.bands[index];if not band then band=image(h.sprite,3);h.bands[index]=band end
			band.Visible=true;band.ImageContent=h.content;band.ImageRectOffset=Vector2.new(r[1],r[2]+sy-r[6]);band.ImageRectSize=Vector2.new(r[3],1)
			band.Position=UDim2.fromScale(r[5]/mask.frame,at/pose.bodySize);band.Size=UDim2.fromScale(r[3]/mask.frame,1/pose.bodySize)
			band.ImageColor3=Color3.new();band.ImageTransparency=1-.22*pose.alpha
		end
	end
	return true
end
return Preview
