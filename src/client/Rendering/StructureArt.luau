--!strict
-- Shared local original sprites. No per-building image allocation or coloured image copies.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Memory=require(script.Parent.ImageMemory)
local Effects=require(script.Parent.StructureEffects)
local Factory=require(script.Parent.FactoryRenderer)
local Gun=require(script.Parent.GunRenderer)
local Artillery=require(script.Parent.ArtilleryRenderer)
local Site=require(script.Parent.SiteRenderer)
local Tokens=require(Shared.Presentation.StructureTokens)
local Fade=require(script.Parent.StructureFade)
local Shadows=require(script.Parent.StructureShadows)
local fades:{[any]:boolean}={}
local Art={}
local Static=if script.Parent.StaticImages then require(script.Parent.StaticImages)else nil
local assets=script.Parent.Parent:FindFirstChild("DevAssets")
local module=assets and assets:FindFirstChild("OrigStructures")
local data:any=nil
if module then
	local ok,value=pcall(require,module :: ModuleScript)
	if ok and type(value)=="table" and type(value.armies)=="table" and type(value.nightAlpha)=="number" then data=value end
end
local gameData=Shared:FindFirstChild("GameData")
local lookModule=gameData and gameData:FindFirstChild("WorldLook")
local palette:any=nil
if lookModule then local ok,value=pcall(require,lookModule :: ModuleScript);if ok and type(value)=="table" then palette=value.palette end end
local sheets:{[string]:any}={}
local jobs:{any}={}
local deadline=0
local warned=false
local function sheet(army:string):any
	if not data then
		if not warned then warned=true;warn("[StructureArt] Generate local building art to replace fallback blocks") end
		return nil
	end
	local old=sheets[army]
	if old and old.image then return if old.ready then old else nil end
	if old and os.clock()<old.retry then return nil end
	local optional=string.sub(army,1,1)=="$" and army~="$badges"
	local meta=if army=="$badges" then data.badges elseif army=="$weapons" then data.weapons elseif army=="$artillery" then data.artillery elseif string.sub(army,1,5)=="$sam:" then data.launchers and data.launchers[string.sub(army,6)] else data.armies[army];if not meta then return nil end
	local state={retry=os.clock()+5,ready=false};sheets[army]=state
	local asset=Static and Static.get("OrigStructures:"..army,meta)
	if asset then state.image=asset;state.content=asset.content;state.meta=meta;state.ready=true;state.external=true;return state end
	if Static and Static.waiting("OrigStructures:"..army)then state.retry=os.clock()+.1;return nil end
	local image=Memory.create(Vector2.new(meta.width,meta.height),if optional then "detail" else "core","StructureArt:"..army);if not image then return nil end
	state.image=image;state.meta=meta
	local function done(success:boolean)
		if sheets[army]~=state then return end
		state.ready=success
		if not success then Memory.release(image);state.image=nil;state.retry=os.clock()+5 end
	end
	local job=coroutine.create(function()
		local ok,pixels=pcall(function()
			return Inflate.raw(Codec.base64Decode(meta.deflate),meta.width*meta.height*4,function()
				if os.clock()>=deadline then coroutine.yield() end
			end)
		end)
		if sheets[army]~=state then return end
		if not ok or not Memory.upload(image,Vector2.zero,Vector2.new(meta.width,meta.height),pixels,{priority=if optional then 2 else 1,done=done}) then
			Memory.release(image);state.image=nil;state.retry=os.clock()+5
		end
	end)
	table.insert(jobs,{thread=job,state=state,army=army})
	return nil
end
Memory.register(10,function()
	for name,state in sheets do
		if name=="$badges" or string.sub(name,1,1)~="$" or not state.image or state.external then continue end
		local image=state.image;Artillery.forgetSheet(image);Gun.forgetSheet(image)
		sheets[name]={retry=os.clock()+5,ready=false}
		Memory.release(image)
	end
end)
function Art.step()	
	for fade in fades do Fade.restore(fade);fade.writing=true end
	Factory.step();Artillery.step();Gun.step();Site.step()
	-- APPROX soft 2 ms bootstrap slice shared by both factions; no whole-atlas decode in a render tick.
	deadline=os.clock()+.002
	while jobs[1] do
		local job=jobs[1]
		if sheets[job.army]~=job.state then table.remove(jobs,1);continue end
		local ok=coroutine.resume(job.thread)
		if not ok then Memory.release(job.state.image);job.state.image=nil;job.state.retry=os.clock()+5 end
		if not ok or coroutine.status(job.thread)=="dead" then table.remove(jobs,1) end
		if os.clock()>=deadline then break end
	end
	Effects.step(deadline);Shadows.step(deadline)
	for fade in fades do fade.writing=false;Fade.apply(fade,fade.mix) end
end
local function rectLabel(gui:SurfaceGui,s:any,key:any,frame:number,cells:number,x:number?,y:number?):ImageLabel?
	local rect=key and s.meta.rects[tostring(key)];if not rect then return nil end
	local image=Instance.new("ImageLabel");image.BackgroundTransparency=1
	image.ImageContent=(s.content or Content.fromObject(s.image));image.ResampleMode=Enum.ResamplerMode.Pixelated
	image.ImageRectOffset=Vector2.new(rect[1],rect[2]);image.ImageRectSize=Vector2.new(rect[3],rect[4])
	image.Size=UDim2.fromScale(rect[3]/frame*cells,rect[4]/frame*cells)
	image.Position=UDim2.fromScale((x or 0)+rect[5]/frame*cells,(y or 0)+rect[6]/frame*cells)
	image.Parent=gui;return image
end
-- The cursor shares the existing core page; it never allocates a separately coloured sprite.
function Art.scale(kind:string):number
	local meta=data and data.armies.coalition and data.armies.coalition.looks[kind]
	return if meta and meta.defence and data.site and data.site.preview then data.site.preview.defenceShare else 1
end
function Art.coverageStyle():any return data and data.site and data.site.coverage end
function Art.preview(kind:string,army:string,side:number):any
	if not data then return nil end
	local core=sheet(army)
	local meta=data.armies[army] and data.armies[army].looks[kind]
	return {sheet=core,badgeSheet=if data.badges then sheet("$badges") else core,meta=meta,style=data.site,tint=palette and palette[side] or {1,1,1}}
end
function Art.token(kind:string,army:string,side:number):any
	if not data or not data.badges then return nil end
	return {sheet=sheet("$badges"),meta=data.badges.looks[kind],status=data.badges.status,style=data.site,tint=palette and palette[side] or {1,1,1}}
end
function Art.setMix(art:any,mix:number)
	if art and art.fade then Fade.set(art.fade,mix);if mix<=0 then Shadows.hide(art.projectedShadow) end end
end
function Art.attach(part:Part,kind:string,army:string):any
	local s=sheet(army);if not s then return nil end
	local meta=s.meta.looks[kind];if not meta then return nil end
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize=Vector2.new(meta.frame,meta.frame);gui.LightInfluence=0;gui.MaxDistance=0;gui.ClipsDescendants=false
	-- This sibling is created before shadow labels, so ground symbols stay behind their projections.
	local groundRoot:Frame?=nil
	if data.site and data.site.ground and data.badges then
		groundRoot=Instance.new("Frame");groundRoot.Name="BuildingGroundSymbols";groundRoot.BackgroundTransparency=1;groundRoot.BorderSizePixel=0;groundRoot.Size=UDim2.fromScale(1,1);groundRoot.ClipsDescendants=false;groundRoot.ZIndex=0;groundRoot.Parent=gui
	end
	-- Only raised-object masks cast shadows. Older local atlases omit this layer until regenerated.
	-- APPROX: combined source height masks, rather than the full height-band extrusion.
	local caster=meta.shadow
	local shadow=if caster then rectLabel(gui,s,caster.tile,caster.frame,1) else nil
	if shadow then shadow.ImageColor3=Color3.fromRGB(5,8,11);shadow.ZIndex=0 end
	local body=rectLabel(gui,s,meta.base,meta.frame,1);local paint=rectLabel(gui,s,meta.paint,meta.frame,1)
	local night=rectLabel(gui,s,meta.night,meta.frame,1)
	if night then night.ZIndex=3 end
	local dish:any=nil
	if meta.dish then
		local cfg=meta.dish;local size=cfg.cells/meta.cells
		local x,y=.5+cfg.x/meta.cells-size/2,.5+cfg.y/meta.cells-size/2
		dish={x=x,y=y,size=size,index=0}
		for _,layer in {"base","paint"} do
			for _,frame in cfg.frames do
				if frame[layer] then dish[layer]=rectLabel(gui,s,frame[layer],cfg.frame,size,x,y);dish[layer].ZIndex=4;break end
			end
		end
	end
	gui.Parent=part
	local origin=if meta.artillery then {part.Position.X/World.STUDS_PER_CELL,part.Position.Z/World.STUDS_PER_CELL,part.Size.X/World.STUDS_PER_CELL} else nil
	local site=Site.attach(gui,meta,s,data.site,if part.Size then math.floor(part.Size.X/World.STUDS_PER_CELL/Art.scale(kind)+.5) else meta.cells)
	local fade=Fade.new(gui);fades[fade]=true;gui.Destroying:Connect(function() fades[fade]=nil end)
	local effects=Effects.attach(gui,meta,{body,paint},function(mode)
		Fade.restore(fade)
		Site.covered(site,mode=="construction")
		-- Reclaim can run between presentation ticks. Keep the completed body hidden behind the fallback.
		if site and site.state and site.state.built<1 and not site.stale then
			if body then body.Visible=false end;if paint then paint.Visible=false end
		end
		if not fade.writing then Fade.apply(fade,fade.mix) end
	end)
	return {gui=gui,kind=kind,groundRoot=groundRoot,fade=fade,projectedShadow=Shadows.attach(gui,meta,shadow,data.shadowProjection,fade),sheet=s,meta=meta,body=body,paint=paint,night=night,shadow=shadow,dish=dish,army=army,effects=effects,factory=Factory.attach(gui,meta,s),gun=Gun.attach(gui,meta,s),artillery=Artillery.attach(gui,meta,s,origin),site=site}
end
local function ground(art:any,side:number,stale:boolean,light:any,screenSide:number?,flags:number?,origin:any?)
	local cfg=data.site and data.site.ground
	local pose=if screenSide and cfg then Tokens.ground(data.site,screenSide,screenSide/(art.meta.cells*Art.scale(art.kind)),light.night,stale,flags,origin) else nil
	local meta=data.badges and data.badges.looks[art.kind];local core=if pose and meta and meta.ghost then sheet("$badges") else nil
	if not pose or not core or not art.groundRoot then if art.ground then art.ground.shade.Visible=false;art.ground.ink.Visible=false end;return end
	local h=art.ground
	if not h then
		h={};for _,key in {"shade","ink"} do local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.ZIndex=1;label.Parent=art.groundRoot;h[key]=label end;art.ground=h
	end
	if h.image~=core.image then h.image=core.image;h.content=(core.content or Content.fromObject(core.image)) end
	local r=core.meta.rects[tostring(meta.ghost)];if not r then h.shade.Visible=false;h.ink.Visible=false;return end
	local rgb=palette and palette[side];local tone=if rgb then Color3.new(rgb[1],rgb[2],rgb[3]) else Color3.fromRGB(cfg.inkRgb[1],cfg.inkRgb[2],cfg.inkRgb[3])
	for key,label in {shade=h.shade,ink=h.ink} do
		local shift=if key=="shade" then pose.shade else 0;local share=pose.size/(screenSide :: number)
		label.Visible=true;label.ImageContent=h.content;label.ImageRectOffset=Vector2.new(r[1],r[2]);label.ImageRectSize=Vector2.new(r[3],r[4])
		label.Position=UDim2.fromScale(.5+(pose.x+shift)/(screenSide :: number)+r[5]/meta.frame*share,.5+(pose.y+shift)/(screenSide :: number)+r[6]/meta.frame*share)
		label.Size=UDim2.fromScale(r[3]/meta.frame*share,r[4]/meta.frame*share)
		label.ImageColor3=if key=="shade" then Color3.fromRGB(cfg.shadeRgb[1],cfg.shadeRgb[2],cfg.shadeRgb[3]) else tone
		label.ImageTransparency=1-pose.alpha*(if key=="shade" then cfg.shadeAlpha else 1)
	end
end
function Art.update(art:any,side:number,stale:boolean,built:number,light:any,id:number,hp:number?,maxHp:number?,importance:number?,production:any?,weapon:any?,artillery:any?,site:any?,screenSide:number?,markerFlags:number?,screenOrigin:any?)
	Fade.restore(art.fade);art.fade.writing=true
	local rgb=palette and palette[side] or {1,1,1}
	local tint=Color3.new(rgb[1],rgb[2],rgb[3]);local base=Color3.new(1,1,1)
	if stale then base=Color3.fromRGB(112,112,112);tint=base end
	local mode=Effects.request(art.effects,built,hp or 1,maxHp or 1,stale,id,rgb,side,importance)
	local constructing=mode=="construction" or mode=="yard" or (built<1 and data.site~=nil and not stale)
	-- Resting-art fade remains an optional-memory/old-asset fallback while a source stage prepares.
	local alpha=if stale then .22 elseif built<1 then .55*(1-math.clamp(built,0,1)) else 0
	Factory.sync(art.factory,built,stale,production,id,base,tint,alpha)
	Gun.sync(art.gun,built,stale,weapon,id,base,tint,alpha,light,if art.gun and not stale and built>=1 then sheet(art.meta.gun.bank or "$weapons") else nil)
	Artillery.sync(art.artillery,built,stale,artillery,id,base,tint,alpha,light,if art.artillery and not stale and built>=1 then sheet("$artillery") else nil)
	Site.sync(art.site,site,stale,screenSide,{id=id,base=base,tint=tint,score=importance})
	if art.body then art.body.ImageColor3=base;art.body.ImageTransparency=alpha;art.body.Visible=not constructing end
	if art.paint then art.paint.ImageColor3=tint;art.paint.ImageTransparency=alpha;art.paint.Visible=not constructing end
	if art.night then art.night.ImageTransparency=if stale or built<1 then 1 else 1-light.night*data.nightAlpha end
	if art.shadow then
		local caster=art.meta.shadow
		local rect=art.sheet.meta.rects[tostring(caster.tile)]
		local reach=.18 -- APPROX silhouette reach in footprint widths.
		art.shadow.Position=UDim2.fromScale(rect[5]/caster.frame+light.shadow[1]*reach,rect[6]/caster.frame+light.shadow[2]*reach)
		art.shadow.ImageTransparency=1-(if stale then .15 else .35)*light.shadowAlpha*(1-alpha)
		if built<1 then art.shadow.ImageTransparency=1 end
	end
	Shadows.sync(art.projectedShadow,built,stale,light,importance,art.fade.mix,screenSide)
	local dish=art.dish
	if dish then
		local cfg=art.meta.dish
		-- Remembered buildings never animate or emit live operational information.
		local index=if stale or built<1 then 1 else math.floor((os.clock()*cfg.speed+id*.37)%1*#cfg.frames+.5)%#cfg.frames+1
		if index~=dish.index then
			dish.index=index
			for _,layer in {"base","paint"} do
				local image=dish[layer];local key=cfg.frames[index][layer];local rect=key and art.sheet.meta.rects[tostring(key)]
				if image then
					image.Visible=rect~=nil
					if rect then
						image.ImageRectOffset=Vector2.new(rect[1],rect[2]);image.ImageRectSize=Vector2.new(rect[3],rect[4])
						image.Size=UDim2.fromScale(rect[3]/cfg.frame*dish.size,rect[4]/cfg.frame*dish.size)
						image.Position=UDim2.fromScale(dish.x+rect[5]/cfg.frame*dish.size,dish.y+rect[6]/cfg.frame*dish.size)
					end
				end
			end
		end
		if dish.base then dish.base.ImageColor3=base;dish.base.ImageTransparency=if built<1 then 1 else alpha end
		if dish.paint then dish.paint.ImageColor3=tint;dish.paint.ImageTransparency=if built<1 then 1 else alpha end
	end
	ground(art,side,stale,light,screenSide,markerFlags,screenOrigin)
	art.fade.writing=false;Fade.apply(art.fade,art.fade.mix)
end
function Art.reset()
	Factory.reset();Artillery.reset();Gun.reset();Site.reset();Shadows.reset()
	for fade in fades do Fade.restore(fade) end;table.clear(fades)
	for _,s in sheets do Memory.release(s.image) end;table.clear(sheets);table.clear(jobs)
	Effects.configure(data)
end
return Art
