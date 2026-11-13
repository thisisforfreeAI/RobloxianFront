--!strict
-- Shared source building badges and public status bars; no per-site images or input handlers.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Players=game:GetService("Players")
local Motion=require(Shared.Presentation.StructureTokens)
local Art=require(script.Parent.StructureArt)
local Tokens={}
local gui:any=nil
local owners:{[number]:any}={}
local serial=0
local bankImage:any=nil
local bankContent:any=nil
local function ink(value:string):(Color3,number)
	if string.sub(value,1,1)=="#" then local n=tonumber(string.sub(value,2),16) or 0;return Color3.fromRGB(bit32.rshift(n,16),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255)),1 end
	local r,g,b,a=string.match(value,"rgba%(([%d.]+),%s*([%d.]+),%s*([%d.]+),%s*([%d.]+)%)")
	return Color3.fromRGB(tonumber(r) or 255,tonumber(g) or 255,tonumber(b) or 255),tonumber(a) or 1
end
local function frame(parent:any,z:number):any
	local o=Instance.new("Frame");o.BackgroundTransparency=1;o.BorderSizePixel=0;o.ZIndex=z;o.Parent=parent;return o
end
local function image(parent:any,z:number):any
	local o=Instance.new("ImageLabel");o.BackgroundTransparency=1;o.ZIndex=z;o.Visible=false;o.Parent=parent;return o
end
local function root():boolean
	if gui then return true end
	local player=Players.LocalPlayer;local parent=player and player:FindFirstChild("PlayerGui");if not parent then return false end
	local made=Instance.new("ScreenGui");made.Name="StructureTokens";made.IgnoreGuiInset=true;made.ResetOnSpawn=false;made.DisplayOrder=-3;made.Parent=parent;gui=made
	made.Destroying:Connect(function() if gui==made then gui=nil;table.clear(owners) end end);return true
end
local function bind(h:any,item:any,key:any,meta:any,size:number,color:Color3,alpha:number)
	local r=key and h.sheet.meta.rects[tostring(key)];item.Visible=r~=nil and alpha>0;if not r then return end
	item.ImageContent=h.content;item.ImageRectOffset=Vector2.new(r[1],r[2]);item.ImageRectSize=Vector2.new(r[3],r[4]);item.ImageColor3=color;item.ImageTransparency=1-alpha
	item.Position=UDim2.fromOffset(-size/2+r[5]/meta.frame*size,-size/2+r[6]/meta.frame*size);item.Size=UDim2.fromOffset(r[3]/meta.frame*size,r[4]/meta.frame*size)
end
local function rect(item:any,r:any,alpha:number?)
	local color,a=ink(r.ink);item.Visible=true;item.BackgroundColor3=color;item.BackgroundTransparency=1-a*(alpha or r.alpha or 1)
	item.Position=UDim2.fromOffset(r.x,r.y);item.Size=UDim2.fromOffset(r.w,r.h)
end
function Tokens.begin() serial+=1 end
function Tokens.draw(v:any,point:any,pixels:number,rules:any,viewer:number,width:number,height:number):any
	local resource=Art.token(v.kind,v.army,v.side)
	local meta,sheet=resource and resource.meta,resource and resource.sheet
	if not meta or not meta.fill or not meta.face or not meta.ghost or not sheet or not root() then return nil end
	local h=owners[v.id]
	local changed=not h or h.image~=sheet.image or h.meta~=meta or h.style~=resource.style or h.pixels~=pixels or h.rules~=rules or h.viewer~=viewer or h.side~=v.side or h.hp~=v.hp or h.maxHp~=v.maxHp or h.built~=v.built or h.stale~=v.stale or h.ready~=(v.art~=nil) or h.markerFlags~=v.markerFlags or h.statusMeta~=resource.status
	local plan=if changed then Motion.plan(resource.style,v,pixels,rules,viewer,v.art~=nil) else h.plan;if not plan then return nil end
	local margin=plan.size
	for _,b in plan.bars do margin=math.max(margin,math.abs(b.x),math.abs(b.x+b.w),math.abs(b.y),math.abs(b.y+b.h)) end
	if plan.warning then margin=math.max(margin,math.abs(plan.warning.x)+plan.warning.radius,math.abs(plan.warning.y)+plan.warning.radius) end
	if point.Z<=0 or point.X+margin<0 or point.Y+margin<0 or point.X-margin>width or point.Y-margin>height then return plan end
	if not h then
		local r=frame(gui,1);r.Name="Building"..v.id;r.Size=UDim2.fromOffset(0,0);r.ClipsDescendants=false
		h={root=r,back=image(r,1),fill=image(r,2),face=image(r,3),ghost=image(r,3),bars={},rects={}};owners[v.id]=h
	end
	h.last=serial;if not h.root.Visible then h.root.Visible=true end
	local x,y=math.floor(point.X+.5),math.floor(point.Y+.5)
	if h.x~=x or h.y~=y then h.x=x;h.y=y;h.root.Position=UDim2.fromOffset(x,y) end
	if not changed then return plan end
	if bankImage~=sheet.image then bankImage=sheet.image;bankContent=sheet.content or Content.fromObject(sheet.image) end
	h.image=sheet.image;h.sheet=sheet;h.content=bankContent
	local tint=resource.tint;local team=if v.side<=0 then ink(resource.style.tokens.neutral) else Color3.new(tint[1],tint[2],tint[3]);local white=Color3.new(1,1,1)
	bind(h,h.back,meta.back,meta,plan.size,white,if plan.stale then 0 else plan.alpha)
	bind(h,h.fill,meta.fill,meta,plan.size,team,if plan.stale then 0 else plan.alpha)
	bind(h,h.face,meta.face,meta,plan.size,white,if plan.stale then 0 else plan.alpha)
	bind(h,h.ghost,meta.ghost,meta,plan.size,ink(resource.style.tokens.stale.color),if plan.stale then plan.alpha else 0)
	for i,r in plan.rects do local item=h.rects[i];if not item then item=frame(h.root,4);h.rects[i]=item end;rect(item,r) end
	for i=#plan.rects+1,#h.rects do h.rects[i].Visible=false end
	for i,b in plan.bars do
		local bar=h.bars[i];if not bar then bar={back=frame(h.root,5),fill=frame(h.root,6)};h.bars[i]=bar end
		rect(bar.back,{x=b.x,y=b.y,w=b.w,h=b.h,ink=resource.style.tokens.bar.back})
		rect(bar.fill,{x=b.x,y=b.y,w=b.w*b.share,h=b.h,ink=b.ink})
	end
	for i=#plan.bars+1,#h.bars do h.bars[i].back.Visible=false;h.bars[i].fill.Visible=false end
	local warning=plan.warning;local icon=resource.status and resource.status.damaged
	if warning and icon then
		if not h.warningRoot then
			h.warningRoot=frame(h.root,7);h.warningRoot.Name="DamagedStatus";h.warningRoot.Size=UDim2.fromOffset(0,0);h.warningRoot.ClipsDescendants=false
			h.warningDisc=frame(h.warningRoot,1);local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(.5,0);corner.Parent=h.warningDisc
			h.warningImage=image(h.warningRoot,2)
		end
		h.warningRoot.Visible=true;h.warningRoot.Position=UDim2.fromOffset(warning.x,warning.y)
		rect(h.warningDisc,{x=-warning.radius,y=-warning.radius,w=warning.radius*2,h=warning.radius*2,ink=warning.plate})
		bind(h,h.warningImage,icon.tile,icon,warning.size,ink(warning.ink),1)
	elseif h.warningRoot then h.warningRoot.Visible=false;h.warningImage.Visible=false end
	h.markerFlags=v.markerFlags;h.statusMeta=resource.status
	h.meta=meta;h.style=resource.style;h.pixels=pixels;h.rules=rules;h.viewer=viewer;h.side=v.side;h.hp=v.hp;h.maxHp=v.maxHp;h.built=v.built;h.stale=v.stale;h.ready=v.art~=nil;h.plan=plan
	return plan
end
function Tokens.finish(views:any)
	for id,h in owners do
		if not views[id] or views[id].kind=="rig" then h.root:Destroy();owners[id]=nil
		elseif h.last~=serial and h.root.Visible then h.root.Visible=false end
	end
end
function Tokens.reset() local old=gui;gui=nil;bankImage=nil;bankContent=nil;table.clear(owners);if old then old:Destroy() end end
function Tokens.count():number local n=0;for _ in owners do n+=1 end;return n end
return Tokens
