--!strict
-- All editable-image consumers share this policy; map detail yields to live unit art and fog.
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Budget = require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImageBudget)
local Uploads = require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImageUploads)
local Pressure=if ReplicatedStorage:WaitForChild("Shared").Presentation.ImagePressure then require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImagePressure)else nil
local quality=if Pressure then Pressure.new()else nil
local accessFailure:string?=nil
local accessListeners:{any}={}
local function reportAccess(err:any)
	if accessFailure then return end
	local message=tostring(err)
	if not string.find(string.lower(message),"editableimage is not accessible",1,true) then return end
	-- A published-experience permission failure is not native image-memory pressure.
	-- Retry requires the creator to enable Mesh / Image APIs and the player to rejoin.
	accessFailure=message
	warn("[ImageMemory] Artwork API access is disabled. Enable Allow Mesh / Image APIs in Experience Settings > Security, publish, then rejoin.")
	for _,listener in table.clone(accessListeners) do if listener.active then pcall(listener.fn,message) end end
end
local budget = Budget.new(function(w: number, h: number)
	if accessFailure then return nil end
	local ok,image=pcall(function() return AssetService:CreateEditableImage({Size=Vector2.new(w,h)}) end)
	if not ok then reportAccess(image);return nil end
	return image
end,{terrainReserve=4*1024*1024}) -- APPROX: carve terrain coverage from the existing 16 MiB detail pool.
local ImageMemory = {}
local trimAt = 0
local recoverAt=0
local recoveryPasses,recoveryReleased=0,0
local uploadConnection:any=nil
local warned=setmetatable({},{__mode="k"})
local uploads=Uploads.new(function(image,x,y,w,h,pixels)
	assert(budget.records[image],"released image upload")
	if accessFailure then error(accessFailure,0) end
	local ok,err=pcall(function() image:WritePixelsBuffer(Vector2.new(x,y),Vector2.new(w,h),pixels) end)
	if not ok then reportAccess(err);error(err,0) end
end,os.clock)

-- Displayed-image writes share one render-frame lane. Core and first map coverage lead effects;
-- aging still guarantees that a continuously rewritten background image gets its turn.
function ImageMemory.upload(image:any,position:any,size:any,pixels:buffer,options:any?):boolean
	if accessFailure or not budget.records[image] then return false end
	local opts=table.clone(options or {});local done=opts.done
	opts.done=function(ok,err)
		if not budget.records[image] then return end
		if not ok and not accessFailure and not warned[image] then warned[image]=true;warn("[ImageUploads] Image write failed:",err) end
		if done then done(ok,err) end
	end
	local accepted=uploads.submit(image,position,size,pixels,opts)
	if accepted and not uploadConnection then
		uploadConnection=RunService.RenderStepped:Connect(function()
			uploads.step()
			if uploads.count==0 and uploadConnection then uploadConnection:Disconnect();uploadConnection=nil end
		end)
	end
	return accepted
end
function ImageMemory.cancelUploads(image:any) uploads.cancel(image) end
function ImageMemory.uploadStats():any return uploads.stats() end

function ImageMemory.quality():number
	if not quality then return 0 end
	return Pressure.sample(quality,budget.used,budget.detail,math.min(budget.ceiling,budget.knownCeiling or math.huge),budget.detailLimit,budget.nativeRefusals,os.clock())
end
function ImageMemory.stride(kind:string,visible:boolean):number
	return if Pressure then Pressure.floor(ImageMemory.quality(),kind,visible)else (if visible then 1 else 4)
end
function ImageMemory.create(size: Vector2, kind: string?,owner:string?): EditableImage?
	if accessFailure then return nil end
	-- Optional large effects yield before another native failure; terrain has its separate reserve.
	if kind=="detail" and ImageMemory.quality()>=2 and size.X*size.Y*4>512*1024 then return nil end
	return budget:create(size.X, size.Y, kind,owner)
end
-- Bootstrap writes before the image is displayed. Normal displayed images keep using upload().
function ImageMemory.write(image:any,position:any,size:any,pixels:buffer):(boolean,any)
	if accessFailure then return false,accessFailure end
	if not budget.records[image] then return false,"released image upload" end
	local ok,err=pcall(function() image:WritePixelsBuffer(position,size,pixels) end)
	if not ok then reportAccess(err) end
	return ok,err
end
function ImageMemory.accessFailure():string? return accessFailure end
function ImageMemory.onAccessFailure(fn:any):any
	local listener={active=true,fn=fn};table.insert(accessListeners,listener)
	if accessFailure then pcall(fn,accessFailure) end
	return function() listener.active=false;local i=table.find(accessListeners,listener);if i then table.remove(accessListeners,i) end end
end
function ImageMemory.release(image: EditableImage?)
	if image then uploads.cancel(image);budget:release(image);warned[image]=nil end
end
function ImageMemory.register(priority: number, fn: (number, any) -> ()) return budget:register(priority, fn) end
function ImageMemory.onRelease(fn: () -> ()) budget:onRelease(fn) end
function ImageMemory.setGuard(fn: () -> any) budget.guard = fn end
function ImageMemory.stats(): (number, number) return budget.used, budget.detail end
function ImageMemory.epoch():number return budget.epoch end
function ImageMemory.pressureStats():any
	local owners={}
	for _,record in budget.records do local key=record.owner or record.kind;local item=owners[key]or{bytes=0,count=0};owners[key]=item;item.bytes+=record.bytes;item.count+=1 end
	return {quality=ImageMemory.quality(),owners=owners,suppressed=budget.suppressed,epoch=budget.epoch,used=budget.used,detail=budget.detail,terrain=budget.terrain,terrainReserve=budget.terrainReserve,detailLimit=budget.detailLimit,ceiling=math.min(budget.ceiling,budget.knownCeiling or math.huge),recoveryPasses=recoveryPasses,recoveryReleased=recoveryReleased,
		accessDisabled=accessFailure~=nil,
		terrainSwap=budget.terrainSwap~=nil,terrainSwapBytes=if budget.terrainSwap then budget.terrainSwap.bytes else 0,
		refusals=table.clone(budget.refusals),nativeRefusals=budget.nativeRefusals,lastRefusal=if budget.lastRefusal then table.clone(budget.lastRefusal) else nil}
end
function ImageMemory.terrainLimit():number return budget.detailLimit end
function ImageMemory.canReplaceTerrain(size:Vector2,previous:any):boolean
	return not accessFailure and budget:canReplaceTerrain(size.X,size.Y,previous)
end
function ImageMemory.replaceTerrain(size:Vector2,previous:any):EditableImage?
	if accessFailure then return nil end
	return budget:replaceTerrain(size.X,size.Y,previous)
end
function ImageMemory.recoverTerrain(required:number,replacing:number?):number
	if accessFailure then return 0 end
	local available=budget:detailHeadroom(replacing,"terrain")
	if required<=available or required>budget.detailLimit or os.clock()<recoverAt then return available end
	recoverAt=os.clock()+1;recoveryPasses+=1
	local before=budget.used;available=budget:recoverTerrain(required,replacing)
	recoveryReleased+=before-budget.used;return available
end
function ImageMemory.detailHeadroom(replacing:number?):number return if accessFailure then 0 else budget:detailHeadroom(replacing,"terrain") end
function ImageMemory.canDetail(size: Vector2,kind:string?): boolean
	if accessFailure then return false end
	local bytes = size.X * size.Y * 4
	local ownerKind=kind or "terrain" -- legacy terrain callers retain their reserved coverage policy
	if budget:canDetail(bytes,ownerKind) then return true end
	if os.clock() < trimAt then return false end
	trimAt = os.clock() + 0.5
	return budget:prepareDetail(bytes,ownerKind)
end

return ImageMemory
