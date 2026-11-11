--!strict
-- Cooperative image admission/reclamation, pure Lua with an injected native-image factory.
-- These limits are our streaming policy, NOT Roblox's undocumented device-specific memory limit.
local ImageBudget = {}

function ImageBudget.new(factory: (number, number) -> any, options: any?)
	local o = options or {}
	local self: any = { used = 0, detail = 0, ceiling = o.ceiling or 48 * 1024 * 1024,
		detailLimit = o.detailLimit or 16 * 1024 * 1024, reserve = o.reserve or 8 * 1024 * 1024,
		records = {}, reclaimers = {}, listeners = {}, epoch = 0, guard = nil, knownCeiling = nil, reclaiming = false }
	function self:protect(): any
		return if self.guard then self.guard() else {}
	end
	function self:onRelease(fn: () -> ()) table.insert(self.listeners, fn) end
	function self:register(priority: number, fn: (number, any) -> ())
		local entry = { priority = priority, fn = fn }
		table.insert(self.reclaimers, entry)
		table.sort(self.reclaimers, function(a: any, b: any) return a.priority < b.priority end)
		return function()
			local i = table.find(self.reclaimers, entry)
			if i then table.remove(self.reclaimers, i) end
		end
	end
	function self:release(image: any)
		local record = self.records[image]
		if not record then return end
		self.records[image] = nil
		image:Destroy() -- EditableImage.Destroy immediately returns its native image storage.
		self.used -= record.bytes
		if record.kind == "detail" then self.detail -= record.bytes end
		self.epoch += 1
		for _, fn in self.listeners do fn() end
	end
	function self:reclaim(bytes: number, minimumPriority: number?)
		if bytes <= 0 or self.reclaiming then return end
		self.reclaiming = true
		local ok, protected = pcall(self.protect, self)
		if not ok then self.reclaiming = false; return end -- do not evict without a valid live-image guard
		local before = self.used
		for _, r in self.reclaimers do
			if r.priority < (minimumPriority or 0) then continue end
			local needed = bytes - (before - self.used)
			if needed <= 0 then break end
			local reclaimed, err = pcall(r.fn, needed, protected)
			if not reclaimed then warn("[ImageBudget] A reclaimer failed:", err) end
		end
		self.reclaiming = false
	end
	function self:canDetail(bytes: number): boolean
		local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
		return self.detail + bytes <= self.detailLimit and self.used + bytes + self.reserve <= ceiling
	end
	-- Read-only headroom for an aggregate LOD plan; no allocation, reclamation or native probe.
	function self:detailHeadroom(replacing:number?):number
		local ceiling=math.min(self.ceiling,self.knownCeiling or math.huge)
		local credit=math.clamp(replacing or 0,0,self.detail)
		return math.max(0,math.min(self.detailLimit-self.detail+credit,ceiling-self.used-self.reserve+credit))
	end
	function self:prepareDetail(bytes: number): boolean
		if self:canDetail(bytes) then return true end
		if self.detail + bytes > self.detailLimit then return false end
		local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
		-- Only unused art yields here; never evict one visible town chunk to load another.
		self:reclaim(math.max(0, self.used + bytes + self.reserve - ceiling), 20)
		return self:canDetail(bytes)
	end
	function self:create(w: number, h: number, kind: string?): any
		kind = kind or "core"
		assert(w > 0 and h > 0 and w <= 1024 and h <= 1024 and w % 1 == 0 and h % 1 == 0, "invalid image dimensions")
		local bytes = w * h * 4
		if kind == "detail" then
			-- Do not repeatedly probe Roblox when our policy already knows there is no headroom.
			if not self:prepareDetail(bytes) then return nil end
		else
			local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
			self:reclaim(math.max(0, self.used + bytes - ceiling))
			if self.knownCeiling and self.used + bytes > self.knownCeiling then return nil end
		end
		local ok, image = pcall(factory, w, h)
		if not ok or not image then
			-- First native refusal teaches a conservative ceiling. Release reusable detail and unused
			-- art before retrying a core image; do not retry an identical allocation without freeing.
			self.knownCeiling = math.min(self.knownCeiling or math.huge, self.used)
			if kind == "detail" then return nil end
			local before = self.used
			self:reclaim(math.huge)
			if self.used < before then ok, image = pcall(factory, w, h) end
			if not ok or not image then return nil end
		end
		self.records[image] = { bytes = bytes, kind = kind }
		self.used += bytes
		if kind == "detail" then self.detail += bytes end
		return image
	end
	return self
end

return ImageBudget
