--!strict
-- Shared optional projected shadows. Every instance of one building look shares its current pose.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Pixels=require(Shared.Presentation.StructureShadows)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Memory=require(script.Parent.ImageMemory)
local Fade=require(script.Parent.StructureFade)
local Shadows={}
-- APPROX native policy: one 2.25 MiB detail image, nine 256px slots and six decoded mask sources.
local SLOT,ACROSS,LIMIT,CACHE=256,3,9,6
local image:any=nil
local content:any=nil
local entries:{[any]:any}={}
local slots:{any}={}
local sources:{[any]:any}={}
local views:{[any]:boolean}={}
local epoch,retry,serial,deadline,lastUse=0,0,0,0,0
local running:any=nil
local function display(h:any)
	if h.dead then return end
	Fade.restore(h.fade)
	local e=h.entry;local ready=h.active and e and e.current
	if h.fallback then h.fallback.Visible=h.active and not ready end
	if ready then
		if not h.label then
			local label=Instance.new("ImageLabel");label.BackgroundTransparency=1;h.smooth=label.ResampleMode;label.ZIndex=0;label.Parent=h.gui;h.label=label
		end
		local p=e.current;local label=h.label;local i=e.slot.index-1
		label.ResampleMode=if h.screenSide/h.source.frame<.95 then h.smooth else Enum.ResamplerMode.Pixelated
		label.ImageContent=content;label.ImageRectOffset=Vector2.new(i%ACROSS*SLOT+2,math.floor(i/ACROSS)*SLOT+2);label.ImageRectSize=Vector2.new(p.n,p.n)
		label.Position=UDim2.fromScale(-p.margin/h.source.frame,-p.margin/h.source.frame);label.Size=UDim2.fromScale(p.width/h.source.frame,p.width/h.source.frame)
		label.ImageTransparency=1-h.alpha;label.Visible=true
	elseif h.label then h.label.Visible=false end
	if not h.fade.writing then Fade.apply(h.fade,h.fade.mix) end
end
local free:any=nil
local function detach(h:any)
	if h.entry then local e=h.entry;e.handles[h]=nil;h.entry=nil;if not next(e.handles) then free(e) end end
end
free=function(e:any)
	e.active=false;e.slot.entry=nil;entries[e.key]=nil
	for h in e.handles do h.entry=nil;display(h) end;table.clear(e.handles)
end
local function releaseImage()
	epoch+=1;running=nil
	for _,e in entries do free(e) end;table.clear(slots)
	local old=image;image=nil;content=nil;Memory.release(old)
end
Memory.register(5,function() if image then releaseImage();retry=os.clock()+5 end end)
local function canvas():boolean
	if image then return true end
	if os.clock()<retry then return false end
	image=Memory.create(Vector2.new(SLOT*ACROSS,SLOT*ACROSS),"detail")
	if not image then retry=os.clock()+5;return false end
	local ok,value=pcall(Content.fromObject,image)
	if not ok then releaseImage();retry=os.clock()+5;return false end
	content=value;for i=1,LIMIT do slots[i]={index=i} end;return true
end
local function rank(e:any):number
	local best=-math.huge
	for h in e.handles do if h.active and os.clock()-h.last<=.5 then best=math.max(best,h.score) end end
	return best
end
local function acquire(h:any):any
	local e=entries[h.key];if e then return e end
	if not canvas() then return nil end
	local slot=nil;local lowest=nil
	for _,s in slots do
		if not s.entry then slot=s;break end
		if not lowest or rank(s.entry)<rank(lowest) then lowest=s.entry;slot=s end
	end
	if not slot then return nil end
	if slot.entry then if h.score<=rank(slot.entry)+.25 then return nil end;free(slot.entry) end
	e={key=h.key,source=h.source,cfg=h.cfg,slot=slot,handles={},active=true,last=os.clock(),retry=0};slot.entry=e;entries[h.key]=e;return e
end
function Shadows.attach(gui:any,meta:any,fallback:any,cfg:any,fade:any):any
	local source=meta.shadow and meta.shadow.source
	-- A cached private export from before projected shadows lacks the opacity settings.
	if not source or not cfg or type(cfg.alpha)~="number" or type(cfg.nightFade)~="number" then return nil end
	local h:any={gui=gui,fallback=fallback,key=meta.sourceName or source,source=source,cfg=cfg,fade=fade,last=0,active=false,score=0,alpha=0}
	views[h]=true;gui.Destroying:Connect(function() h.dead=true;detach(h);views[h]=nil end);return h
end
function Shadows.sync(h:any,built:number,stale:boolean,light:any,score:number?,mix:number?,screenSide:number?)
	if not h or h.dead then return end
	h.last=os.clock();h.score=score or 0;h.screenSide=screenSide or h.source.frame
	local x,y=light.shadow[1],light.shadow[2]
	h.alpha=h.cfg.alpha*(1-h.cfg.nightFade*light.night)
	h.active=built>=1 and not stale and (mix or 1)>0 and h.alpha>0 and x*x+y*y>0
	if not h.active then detach(h);display(h);return end
	lastUse=h.last
	local e=acquire(h)
	if h.entry~=e then detach(h);h.entry=e;if e then e.handles[h]=true end end
	if e then
		e.last=h.last;local pose=Pixels.plan(h.cfg,h.source,x,y,SLOT-4)
		if not e.want or e.want.key~=pose.key then e.want=pose end
	end
	display(h)
end
function Shadows.hide(h:any)
	if not h or h.dead or not h.active then return end
	h.active=false;detach(h);display(h)
end
local function valid(job:any):boolean
	return image==job.image and epoch==job.epoch and job.entry.active and job.entry.slot.entry==job.entry
end
local function checkpoint(job:any)
	if not valid(job) then error("obsolete structure shadow") end
	if os.clock()>=deadline then coroutine.yield() end
end
local function source(job:any):any
	serial+=1;local meta=job.entry.source;local key=job.entry.key;local cached=sources[key]
	if cached then cached.used=serial;return cached.value end
	local raw=Inflate.raw(Codec.base64Decode(meta.deflate),meta.size,function() checkpoint(job) end)
	local value=Pixels.prepare(raw,meta,function() checkpoint(job) end)
	local count=0;local oldest,age=nil,math.huge
	for key,entry in sources do count+=1;if entry.used<age then oldest=key;age=entry.used end end
	if count>=CACHE and oldest then sources[oldest]=nil end
	sources[key]={value=value,used=serial};return value
end
local function makeJob(e:any):any
	local job={entry=e,pose=e.want,image=image,epoch=epoch}
	job.thread=coroutine.create(function()
		local decoded=source(job);local pixels=Pixels.raster(decoded,e.cfg,job.pose,function() checkpoint(job) end)
		local padded=buffer.create(SLOT*SLOT*4);local n=job.pose.n
		for y=0,n-1 do buffer.copy(padded,((y+2)*SLOT+2)*4,pixels,y*n*4,n*4);checkpoint(job) end
		if not valid(job) then return end
		local i=e.slot.index-1
		e.pending=true
		local accepted=Memory.upload(image,Vector2.new(i%ACROSS*SLOT,math.floor(i/ACROSS)*SLOT),Vector2.new(SLOT,SLOT),padded,
			{priority=3,key="structure-shadow:"..e.slot.index,done=function(ok)
				if not valid(job) then return end
				e.pending=false
				if not ok then releaseImage();retry=os.clock()+5;return end
				e.current=job.pose
				for h in e.handles do display(h) end
			end})
		if not accepted then e.pending=false;e.retry=os.clock()+.25 end
	end)
	return job
end
function Shadows.step(untilTime:number)
	local now=os.clock();deadline=untilTime
	for h in views do if h.active and now-h.last>.5 then h.active=false;detach(h);display(h) end end
	for _,e in entries do if now-e.last>.5 then free(e) end end
	if not image then return end
	-- APPROX idle grace prevents native allocation churn while zoom crosses the badge threshold.
	if not next(entries) then running=nil;if now-lastUse>.5 then releaseImage() end;return end
	if now>=deadline then return end
	if running and not valid(running) then running=nil end
	if not running then
		local selected=nil;local best=-math.huge
		for _,e in entries do
			if not e.want or e.pending or now<e.retry or e.current and e.current.key==e.want.key then continue end
			local priority=rank(e)+(if not e.current then 10000 else 0)
			if priority>best then best=priority;selected=e end
		end
		if selected then running=makeJob(selected) end
	end
	if not running then return end
	local job=running;local ok,err=coroutine.resume(job.thread)
	if not ok then
		if valid(job) then releaseImage();retry=os.clock()+5;warn("[StructureShadows] Optional projection waits until retry:",err) end
		running=nil
	elseif coroutine.status(job.thread)=="dead" then running=nil end
end
function Shadows.reset() releaseImage();table.clear(sources);for h in views do h.dead=true end;table.clear(views);retry=0 end
function Shadows.stats():any
	local count,cached=0,0;for _ in entries do count+=1 end;for _ in sources do cached+=1 end
	return {images=if image then 1 else 0,variants=count,sources=cached,working=running~=nil}
end
return Shadows
