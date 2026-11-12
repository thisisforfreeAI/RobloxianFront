--!strict
-- Source roof footprints with owner-requested projected side facades and roof-clipped windows.
-- APPROX: flat town art gets a thin wall rim; original roof-surface emitters are intentionally removed.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local World=require(Shared.Config.World)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Windows=require(Shared.Presentation.NightWindows)
local Pixels=require(Shared.Presentation.NightLightPixels)
local Noise=require(Shared.Presentation.GroundWetness)
local Memory=require(script.Parent.ImageMemory)
local Daylight=require(script.Parent.DaylightController)
local Renderer={}
local EMISSION_GAIN=2.4 -- APPROX owner request: more noticeable window/lamp glow.
local PAGE=64 -- APPROX canvas batching; shared atlas and source fragment positions stay unchanged.
local CREATE_SECONDS=.001 -- APPROX soft per-Heartbeat budget, not a native frame-time guarantee.
local CREATE_LIMIT=24 -- A fast clock must not admit an unbounded burst of instance creation.
function Renderer.start(data:any,profile:any,parent:Instance,born:number,damage:any?):any
	local state:any={ready=false,fade=0}
	local coverage={}
	state.windowGain=function()
		local snapshot=coverage
		return function(x,y) return 1-(snapshot[x..":"..y] or 0) end
	end
	if not data or not profile.city then return state end
	local folder=Instance.new("Folder");folder.Name="BuildingWindows";folder.Parent=parent
	local items=Windows.prepare(data.points,profile,Noise.hash21)
	local spatial=Windows.index(items,data.pixelsPerCell)
	local views:{[number]:any}={}
	local pages:{[string]:any}={}
	local changing:{[number]:any}={}
	local pending:{any}={};local cursor=1
	local selected:{any}={};local selection:any=nil
	local appearance:any=nil;local selectionQueries=0
	state.stats=function()
		local fragments,canvases,animating=0,0,0
		for _ in views do fragments+=1 end;for _ in pages do canvases+=1 end;for _ in changing do animating+=1 end
		return {fragments=fragments,canvases=canvases,animating=animating,limit=Windows.MAX_VISIBLE,pending=math.max(0,#pending-cursor+1),selectionQueries=selectionQueries,candidates=spatial.lastVisited}
	end
	local damageCache:any={}
	local image:EditableImage?=nil
	local imageDivisor=1
	local preferHalf=false
	local retry=0
	local creating:Part?=nil
	local function release()
		coverage={}
		pending={};cursor=1;selected={};selection=nil;appearance=nil
		for _,page in pages do page.part:Destroy() end
		table.clear(pages);table.clear(views);table.clear(changing)
		Memory.release(image);image=nil;state.ready=false;state.fade=0
	end
	local function pageAt(x:number,y:number):any
		local key=x..":"..y
		if pages[key] then return pages[key] end
		local scale=data.pixelsPerCell
		local part=Instance.new("Part");part.Name="WindowPage_"..key
		creating=part;part.Parent=folder
		part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;part.Transparency=1
		part.Size=Vector3.new(PAGE/scale*World.STUDS_PER_CELL,.01,PAGE/scale*World.STUDS_PER_CELL)
		part.CFrame=CFrame.new((x*PAGE+PAGE/2)/scale*World.STUDS_PER_CELL,World.GROUND_Y+.245,(y*PAGE+PAGE/2)/scale*World.STUDS_PER_CELL)*CFrame.Angles(0,World.TOP_GUI_YAW,0)
		local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
		gui.Parent=part
		gui.CanvasSize=Vector2.new(PAGE,PAGE);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.MaxDistance=0
		-- Adjacent pages never overlap. Crossing fragments are repeated and clipped at the seam.
		-- Masonry is composited before every emission in this canvas, avoiding coplanar GUI sorting.
		local clip=Instance.new("Frame");clip.BackgroundTransparency=1;clip.BorderSizePixel=0
		clip.Size=UDim2.fromScale(1,1);clip.ClipsDescendants=true;clip.Parent=gui
		local page={part=part,gui=gui,clip=clip,x=x,y=y,key=key,refs=0}
		if appearance then page.brightness=appearance.correction.brightness;gui.Brightness=page.brightness*EMISSION_GAIN end
		pages[key]=page;creating=nil;return page
	end
	local function create(item:any):any
		local p=item.point;local layers={}
		local function layer(page:any,index:number,z:number):ImageLabel
			local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
			label.Size=UDim2.fromScale(data.slot/PAGE,data.slot/PAGE)
			label.Position=UDim2.fromScale((p[1]-page.x*PAGE)/PAGE,(p[2]-page.y*PAGE)/PAGE)
			label.BorderSizePixel=0;label.ZIndex=z;label.Parent=page.clip
			label.ImageContent=Content.fromObject(image :: EditableImage)
			label.ImageRectOffset=Vector2.new((index%data.perRow)*data.slot/imageDivisor,math.floor(index/data.perRow)*data.slot/imageDivisor)
			label.ImageRectSize=Vector2.new(data.slot/imageDivisor,data.slot/imageDivisor);label.ResampleMode=Enum.ResamplerMode.Default
			label.ImageTransparency=1;return label
		end
		for y=math.floor(p[2]/PAGE),math.ceil((p[2]+data.slot)/PAGE)-1 do
			for x=math.floor(p[1]/PAGE),math.ceil((p[1]+data.slot)/PAGE)-1 do
				local page=pageAt(x,y);page.refs+=1
				local face=if p[6]~=nil and p[6]>=0 then layer(page,p[6],1) else nil
				if face then
					local gain=1.4/EMISSION_GAIN
					face.ImageColor3=Color3.new(.035*gain,.032*gain,.028*gain)
				end
				table.insert(layers,{page=page,label=layer(page,p[5],2),face=face})
			end
		end
		local view={layers=layers,item=item,strength=0,reveal=0,target=0,opacity=0}
		changing[item.id]=view;return view
	end
	local function remove(id:number,v:any)
		for _,layer in v.layers do
			layer.label:Destroy();if layer.face then layer.face:Destroy() end
			local page=layer.page;page.refs-=1
			if page.refs==0 then page.part:Destroy();pages[page.key]=nil end
		end
		views[id]=nil;changing[id]=nil
	end
	local function animate(dt:number)
		local step=1-math.exp(-dt/.18)
		for id,v in changing do
			v.strength+=(v.target-v.strength)*step;v.reveal+=(1-v.reveal)*step
			local settled=math.abs(v.strength-v.target)<.002 and v.reveal>.998
			if settled then v.strength=v.target;v.reveal=1;changing[id]=nil end
			for _,layer in v.layers do
				layer.label.ImageTransparency=1-v.opacity*v.strength
				if layer.face then layer.face.ImageTransparency=1-v.opacity*v.reveal end
			end
		end
	end
	local function style(v:any)
		local c=appearance.correction.color
		if not v.color or c[1]~=v.color[1] or c[2]~=v.color[2] or c[3]~=v.color[3] then
			local color=Color3.new(c[1],c[2],c[3]);v.color=c
			for _,layer in v.layers do layer.label.ImageColor3=color end
		end
		local target=if Windows.on(v.item,profile,appearance.clock,Noise.hash21) then 1 else 0
		if v.target~=target or v.opacity~=appearance.opacity then changing[v.item.id]=v end
		v.target=target;v.opacity=appearance.opacity
	end
	local function fill()
		if not appearance or not image or cursor>#pending then return end
		local began=os.clock();local created=0
		while cursor<=#pending do
			local item=pending[cursor];cursor+=1
			local view=create(item);views[item.id]=view;style(view);created+=1
			if created>=CREATE_LIMIT or os.clock()-began>=CREATE_SECONDS then break end
		end
		state.fade=if cursor>#pending then appearance.fade else 0
	end
	local acc=0
	local function update(dt:number)
		acc+=dt;if acc<.1 then return end;acc=0
		local night=Daylight.get().night
		if night<=0 then if image then release() end;return end
		local camera=workspace.CurrentCamera;if not camera then appearance=nil;pending={};cursor=1;selection=nil;return end
		local dist=math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)
		local ry=dist*math.tan(math.rad(camera.FieldOfView/2))/World.STUDS_PER_CELL
		local rx=ry*camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
		local px=camera.ViewportSize.Y/(2*ry)
		local fade=Windows.fade(px,profile.city)
		if fade<=0 then
			coverage={}
			appearance=nil;pending={};cursor=1;selection=nil
			state.fade=0
			for _,page in pages do page.gui.Enabled=false end
			return
		end
		if not image then
			if os.clock()<retry then return end
			local variant=if preferHalf and data.half then data.half else data
			image=Memory.create(Vector2.new(variant.width,variant.height))
			if not image and not preferHalf and data.half then
				preferHalf=true;variant=data.half
				image=Memory.create(Vector2.new(variant.width,variant.height))
			end
			if not image then retry=os.clock()+5;return end
			imageDivisor=if preferHalf then 2 else 1
			local ok,err=pcall(function() (image :: EditableImage):WritePixelsBuffer(Vector2.zero,Vector2.new(variant.width,variant.height),Inflate.raw(Codec.base64Decode(variant.deflate),variant.width*variant.height*4)) end)
			if not ok then release();retry=math.huge;warn("[NightWindows] Local atlas unavailable:",err);return end
			state.ready=true
		end
		local cx,cy=camera.CFrame.Position.X/World.STUDS_PER_CELL,camera.CFrame.Position.Z/World.STUDS_PER_CELL
		local version=if damage and damage.any() then damage.version() else nil
		if not selection or selection.cx~=cx or selection.cy~=cy or selection.rx~=rx or selection.ry~=ry or selection.version~=version then
			local blocked={};local eligible:any=nil
			if version~=nil then
				eligible=function(item)
					local cached=damageCache[item.id]
					if not cached or cached.version~=version then
						cached={version=version,blocked=Windows.damaged(item,data.pixelsPerCell,profile.fine,damage.blocked)};damageCache[item.id]=cached
					end
					if cached.blocked then blocked[item.point[3]..":"..item.point[4]]=1 end
					return not cached.blocked
				end
			end
			selected=Windows.visible(items,data.pixelsPerCell,cx,cy,rx,ry,eligible,spatial);selectionQueries+=1
			selection={cx=cx,cy=cy,rx=rx,ry=ry,version=version,blocked=blocked}
		end
		local wanted={};local nextCoverage=table.clone(selection.blocked)
		pending={};cursor=1
		for _,entry in selected do
			local item=entry.item;wanted[item.id]=true
			if not views[item.id] then table.insert(pending,item) end
		end
		for id,v in views do if not wanted[id] then remove(id,v) end end
		local clock=os.clock()-born
		local correction=Pixels.compensate(Daylight.postEffect(),profile.color)
		appearance={clock=clock,opacity=night*fade,fade=fade,correction=correction}
		for _,page in pages do
			page.gui.Enabled=true
			if page.brightness~=correction.brightness then page.gui.Brightness=correction.brightness*EMISSION_GAIN;page.brightness=correction.brightness end
		end
		for _,v in views do
			style(v)
			if v.item.phase>=0 then nextCoverage[v.item.point[3]..":"..v.item.point[4]]=fade*v.strength end
		end
		coverage=nextCoverage
		-- Keep coarse coverage until all selected fragments exist; no empty camera-pan interval.
		state.fade=if #pending==0 then fade else 0
	end
	local connection=RunService.Heartbeat:Connect(function(dt)
		local ok,err=pcall(function() update(dt);fill();animate(dt) end)
		if not ok then
			if creating then creating:Destroy();creating=nil end
			-- Stop this optional layer once, releasing partial views, instead of failing every heartbeat.
			folder:Destroy();warn("[NightWindows] Disabled after a rendering failure:",err)
		end
	end)
	folder.Destroying:Connect(function() connection:Disconnect();release();table.clear(damageCache) end)
	return state
end
return Renderer
