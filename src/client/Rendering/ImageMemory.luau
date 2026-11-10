--!strict
-- All editable-image consumers share this policy; map detail yields to live unit art and fog.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Budget = require(ReplicatedStorage:WaitForChild("Shared").Presentation.ImageBudget)
local budget = Budget.new(function(w: number, h: number)
	return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
end)
local ImageMemory = {}
local trimAt = 0

function ImageMemory.create(size: Vector2, kind: string?): EditableImage?
	return budget:create(size.X, size.Y, kind)
end
function ImageMemory.release(image: EditableImage?)
	if image then budget:release(image) end
end
function ImageMemory.register(priority: number, fn: (number, any) -> ()) return budget:register(priority, fn) end
function ImageMemory.onRelease(fn: () -> ()) budget:onRelease(fn) end
function ImageMemory.setGuard(fn: () -> any) budget.guard = fn end
function ImageMemory.stats(): (number, number) return budget.used, budget.detail end
function ImageMemory.canDetail(size: Vector2): boolean
	local bytes = size.X * size.Y * 4
	if budget:canDetail(bytes) then return true end
	if os.clock() < trimAt then return false end
	trimAt = os.clock() + 0.5
	return budget:prepareDetail(bytes)
end

return ImageMemory
