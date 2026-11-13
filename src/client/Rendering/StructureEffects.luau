--!strict
-- Bounded shared canvas for source construction and damage. Native failure keeps static art.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Pixels=require(Shared.Presentation.StructurePixels)
local Codec=require(Shared.Maps.MapCodec)
local Inflate=require(Shared.Utilities.Inflate)
local Rng=require(Shared.Utilities.Rng)
local Memory=require(script.Parent.ImageMemory)
local Effects={}
-- APPROX pool policy: nine full-resolution slots, one optional 2.25 MiB image and six CPU sources.
local SLOT,ACROSS,LIMIT,CACHE=256,3,9,6
local config:any=nil
local image:any=nil
local slots:{any}={}
local sources:{[any]:any}={}
local serial,epoch,retry,cursor=0,0,0,1
local deadline=0
local running:any=nil
local function hide(handle:any)
	local changed=handle.readyMode~=nil
	if handle.label then handle.label.Visible=false end
	for _,item in handle.static or {} do item.Visible=true end
	handle.readyMode=nil
	if changed and handle.onDisplay then handle.onDisplay(nil) end
end
local function show(handle:any,mode:string)
	local changed=handle.readyMode~=mode
	for _,item in handle.static or {} do item.Visible=mode~="construction" end
	handle.readyMode=mode;handle.label.Visible=true
	if changed and handle.onDisplay then handle.onDisplay(mode) end
end
function Effects.release(handle:any)
	if not handle then return end
	hide(handle)
	if handle.slot then handle.slot.handle=nil;handle.slot.version+=1;handle.slot=nil end
end
local function releaseImage()
	epoch+=1;running=nil
	for _,slot in slots do if slot.handle then Effects.release(slot.handle) end end
	table.clear(slots);Memory.release(image);image=nil
end
Memory.register(10,function() if image then releaseImage();retry=os.clock()+5 end end)
function Effects.configure(data:any)
	Effects.reset()
	config=if data and data.construction and data.damage then data else nil
end
function Effects.attach(gui:SurfaceGui,meta:any,static:{any}?,onDisplay:any?):any
	local handle={gui=gui,meta=meta,stage=0,static=static or {},onDisplay=onDisplay}
	gui.Destroying:Connect(function() Effects.release(handle) end)
	return handle
end
local function canvas():boolean
	if image then return true end
	if os.clock()<retry then return false end
	image=Memory.create(Vector2.new(SLOT*ACROSS,SLOT*ACROSS),"detail")
	if not image then retry=os.clock()+5;return false end
	for i=1,LIMIT do slots[i]={index=i,version=0} end
	return true
end
local function acquire(handle:any,score:number):any
	if handle.slot then return handle.slot end
	local selected=nil
	for _,slot in slots do
		if not slot.handle then selected=slot;break end
		if not selected or slot.handle.score<selected.handle.score then selected=slot end
	end
	if not selected or selected.handle and score<=selected.handle.score+.25 then return nil end
	if selected.handle then Effects.release(selected.handle) end
	selected.version+=1;selected.handle=handle;selected.currentKey=nil;selected.uploading=nil
	handle.slot=selected
	return selected
end
local function label(handle:any,slot:any)
	if not handle.label then
		local item=Instance.new("ImageLabel");item.BackgroundTransparency=1;item.Size=UDim2.fromScale(1,1)
		item.ResampleMode=Enum.ResamplerMode.Pixelated;item.ZIndex=2;item.Visible=false;item.Parent=handle.gui
		handle.label=item
	end
	local i=slot.index-1;local item=handle.label
	item.ImageContent=Content.fromObject(image)
	item.ImageRectOffset=Vector2.new(i%ACROSS*SLOT+2,math.floor(i/ACROSS)*SLOT+2)
	item.ImageRectSize=Vector2.new(handle.meta.frame,handle.meta.frame)
end
function Effects.request(handle:any,built:number,hp:number,maxHp:number,stale:boolean,id:number,tint:any,side:number,importance:number?):string?
	if not handle or not config or not handle.meta.effects or stale then Effects.release(handle);return nil end
	local mode,step
	local progress=built
	if built<1 and config.site then
		local yard=config.site.yardShare
		if built<yard then Effects.release(handle);return "yard" end
		progress=math.min(1,(built-yard)/math.max(1e-6,1-yard))
	end
	if built<1 and handle.meta.effects.top>0 then mode="construction";step=Pixels.buildStep(config.construction,progress)
	elseif built>=1 then
		handle.stage=Pixels.damageStage(config.damage,handle.stage,hp,maxHp)
		if handle.stage>0 then mode="damage";step=handle.stage end
	end
	if not mode then Effects.release(handle);return nil end
	if not canvas() then hide(handle);return nil end
	handle.score=(importance or 0)+(if mode=="construction" then 3 else 2)
	local slot=acquire(handle,handle.score);if not slot then hide(handle);return nil end
	label(handle,slot)
	local key=`{mode}:{step}:{id}:{side}`
	local cohort=`{mode}:{id}:{side}`
	if handle.cohort~=cohort then slot.version+=1;slot.currentKey=nil;slot.uploading=nil;hide(handle) end
	if handle.step and step<handle.step then hide(handle);slot.currentKey=nil end
	handle.mode,handle.step,handle.key,handle.cohort=mode,step,key,cohort
	handle.tint,handle.id,handle.last=tint,id,os.clock()
	if slot.currentKey==key then show(handle,mode) end
	return handle.readyMode
end
local function valid(job:any):boolean
	return image==job.image and epoch==job.epoch and job.slot.version==job.version and job.slot.handle==job.handle
end
local function publishable(job:any):boolean
	if not valid(job) then return false end
	local h=job.handle
	return h.key==job.key or h.mode=="construction" and job.mode=="construction" and h.step>=job.step and h.cohort==job.cohort
end
local function checkpoint(job:any)
	if not valid(job) then error("obsolete structure pixels") end
	if os.clock()>=deadline then coroutine.yield() end
end
local function source(job:any):any
	local meta=job.handle.meta;serial+=1
	local cached=sources[meta]
	if cached then cached.used=serial;return cached.value end
	local packed=meta.effects
	local raw=Inflate.raw(Codec.base64Decode(packed.deflate),packed.size,function() checkpoint(job) end)
	local decoded=Pixels.prepare(raw,meta.frame,packed.n,packed.top)
	local count=0;local oldest,age=nil,math.huge
	for key,value in sources do count+=1;if value.used<age then oldest,age=key,value.used end end
	if count>=CACHE and oldest then sources[oldest]=nil end
	sources[meta]={used=serial,value=decoded}
	return decoded
end
local function makeJob(slot:any):any
	local h=slot.handle
	local job={slot=slot,handle=h,key=h.key,mode=h.mode,step=h.step,cohort=h.cohort,tint=table.clone(h.tint),id=h.id,
		image=image,version=slot.version,epoch=epoch}
	job.thread=coroutine.create(function()
		local decoded=source(job)
		local pixels
		if job.mode=="construction" then pixels=Pixels.construction(decoded,config.construction,job.step,job.id,job.tint,function() checkpoint(job) end)
		else pixels=Pixels.damage(decoded,config.damage,job.step,job.id,h.meta.cells,h.meta.defence,{rng=Rng.new,imul=Rng.imul},function() checkpoint(job) end) end
		if not publishable(job) then return end
		local padded=buffer.create(SLOT*SLOT*4);local f=h.meta.frame
		for row=0,f-1 do buffer.copy(padded,((row+2)*SLOT+2)*4,pixels,row*f*4,f*4);checkpoint(job) end
		local i=slot.index-1
		local accepted=Memory.upload(image,Vector2.new(i%ACROSS*SLOT,math.floor(i/ACROSS)*SLOT),Vector2.new(SLOT,SLOT),padded,
			{priority=2,key="structure:"..slot.index,done=function(ok)
				if not valid(job) then return end
				slot.uploading=nil
				if not ok then releaseImage();retry=os.clock()+5;return end
				if not publishable(job) then hide(h);return end
				slot.currentKey=job.key;show(h,job.mode)
			end})
		if accepted then slot.uploading=job.key else slot.retry=os.clock()+.25 end
	end)
	return job
end
function Effects.step(untilTime:number)
	if not image then return end
	deadline=untilTime
	for _,slot in slots do if slot.handle and os.clock()-slot.handle.last>.5 then Effects.release(slot.handle) end end
	local active=false;for _,slot in slots do if slot.handle then active=true;break end end
	if not active then releaseImage();return end
	if os.clock()>=deadline then return end
	if running and not valid(running) then running=nil end
	if not running then
		for _=1,#slots do
			local slot=slots[cursor];cursor=cursor%#slots+1
			if slot.handle and slot.currentKey~=slot.handle.key and not slot.uploading and os.clock()>=(slot.retry or 0) then running=makeJob(slot);break end
		end
	end
	if not running then return end
	local job=running;local ok,err=coroutine.resume(job.thread)
	if not ok then
		if valid(job) then Effects.release(job.handle);retry=os.clock()+5;releaseImage();warn("[StructureEffects] Optional pixels disabled until retry:",err) end
		running=nil
	elseif coroutine.status(job.thread)=="dead" then running=nil end
end
function Effects.reset()
	releaseImage();table.clear(sources);config=nil;retry=0;cursor=1
end
function Effects.stats():any
	local active,cached=0,0;for _,slot in slots do if slot.handle then active+=1 end end;for _ in sources do cached+=1 end
	return {images=if image then 1 else 0,slots=active,capacity=LIMIT,sources=cached,working=running~=nil}
end
return Effects
