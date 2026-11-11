--!strict
-- All editable-image consumers share this policy; map detail yields to live unit art and fog.
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Budget = require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImageBudget)
local Uploads = require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImageUploads)
local budget = Budget.new(function(w: number, h: number)
	return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
end)
local ImageMemory = {}
local trimAt = 0
local uploadConnection:any=nil
local warned=setmetatable({},{__mode="k"})
local uploads=Uploads.new(function(image,x,y,w,h,pixels)
	assert(budget.records[image],"released image upload")
	image:WritePixelsBuffer(Vector2.new(x,y),Vector2.new(w,h),pixels)
end,os.clock)

-- Displayed-image writes share one render-frame lane. Core and first map coverage lead effects;
-- aging still guarantees that a continuously rewritten background image gets its turn.
function ImageMemory.upload(image:any,position:any,size:any,pixels:buffer,options:any?):boolean
	if not budget.records[image] then return false end
	local opts=table.clone(options or {});local done=opts.done
	opts.done=function(ok,err)
		if not budget.records[image] then return end
		if not ok and not warned[image] then warned[image]=true;warn("[ImageUploads] Image write failed:",err) end
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

function ImageMemory.create(size: Vector2, kind: string?): EditableImage?
	return budget:create(size.X, size.Y, kind)
end
function ImageMemory.release(image: EditableImage?)
	if image then uploads.cancel(image);budget:release(image);warned[image]=nil end
end
function ImageMemory.register(priority: number, fn: (number, any) -> ()) return budget:register(priority, fn) end
function ImageMemory.onRelease(fn: () -> ()) budget:onRelease(fn) end
function ImageMemory.setGuard(fn: () -> any) budget.guard = fn end
function ImageMemory.stats(): (number, number) return budget.used, budget.detail end
function ImageMemory.detailHeadroom(replacing:number?):number return budget:detailHeadroom(replacing) end
function ImageMemory.canDetail(size: Vector2): boolean
	local bytes = size.X * size.Y * 4
	if budget:canDetail(bytes) then return true end
	if os.clock() < trimAt then return false end
	trimAt = os.clock() + 0.5
	return budget:prepareDetail(bytes)
end

return ImageMemory
