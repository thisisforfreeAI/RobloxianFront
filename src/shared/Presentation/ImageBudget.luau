--!strict
-- Cooperative image admission/reclamation, pure Lua with an injected native-image factory.
-- These limits are our streaming policy, NOT Roblox's undocumented device-specific memory limit.
local ImageBudget = {}

function ImageBudget.new(factory: (number, number) -> any, options: any?)
	local o = options or {}
	local self: any = { used = 0, detail = 0, ceiling = o.ceiling or 48 * 1024 * 1024,
		detailLimit = o.detailLimit or 16 * 1024 * 1024, reserve = o.reserve or 8 * 1024 * 1024,
		terrain = 0, terrainReserve = o.terrainReserve or 0,
		recoveryLimit = o.recoveryLimit or 4 * 1024 * 1024,
		records = {}, reclaimers = {}, listeners = {}, epoch = 0, guard = nil, knownCeiling = nil, reclaiming = false,
		refusals={core=0,detail=0,terrain=0},nativeRefusals=0,lastRefusal=nil,blockedEpoch=nil,suppressed=0 }
	function self:protect(): any
		return if self.guard then self.guard() else {}
	end
	function self:onRelease(fn: () -> ()) table.insert(self.listeners, fn) end
	function self:register(priority: number, fn: (number, any) -> ())
		local entry = { priority = priority, fn = fn, active=true }
		table.insert(self.reclaimers, entry)
		table.sort(self.reclaimers, function(a: any, b: any) return a.priority < b.priority end)
		return function()
			entry.active=false
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
		if record.kind == "detail" or record.kind == "terrain" then self.detail -= record.bytes end
		if record.kind == "terrain" then self.terrain -= record.bytes end
		self.epoch += 1
		for _, fn in self.listeners do fn() end
	end
	function self:reclaim(bytes: number, minimumPriority: number?, maximumPriority: number?, detailOnly:boolean?)
		if bytes <= 0 or self.reclaiming then return end
		self.reclaiming = true
		local ok, protected = pcall(self.protect, self)
		if not ok then self.reclaiming = false; return end -- do not evict without a valid live-image guard
		local before = if detailOnly then self.detail else self.used
		-- A reclaimed owner can unregister itself/other owners during this pass.
		for _, r in table.clone(self.reclaimers) do
			if not r.active then continue end
			if r.priority < (minimumPriority or 0) then continue end
			if maximumPriority and r.priority > maximumPriority then continue end
			local needed = bytes - (before - (if detailOnly then self.detail else self.used))
			if needed <= 0 then break end
			local reclaimed, err = pcall(r.fn, needed, protected,detailOnly)
			if not reclaimed then warn("[ImageBudget] A reclaimer failed:", err) end
		end
		self.reclaiming = false
	end
	function self:terrainGap(kind:string?):number
		return if kind=="terrain" then 0 else math.max(0,self.terrainReserve-self.terrain)
	end
	function self:canDetail(bytes: number,kind:string?): boolean
		local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
		local gap=self:terrainGap(kind)
		return self.detail + bytes + gap <= self.detailLimit and self.used + bytes + self.reserve + gap <= ceiling
	end
	-- Read-only headroom for an aggregate LOD plan; no allocation, reclamation or native probe.
	function self:detailHeadroom(replacing:number?,kind:string?):number
		local ceiling=math.min(self.ceiling,self.knownCeiling or math.huge)
		local credit=math.clamp(replacing or 0,0,self.detail)
		local gap=self:terrainGap(kind)
		return math.max(0,math.min(self.detailLimit-self.detail+credit-gap,ceiling-self.used-self.reserve+credit-gap))
	end
	function self:prepareDetail(bytes: number,kind:string?): boolean
		if self:canDetail(bytes,kind) then return true end
		local gap=self:terrainGap(kind)
		if self.detail + bytes + gap > self.detailLimit then return false end
		local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
		-- Only unused art yields here; never evict one visible town chunk to load another.
		self:reclaim(math.max(0, self.used + bytes + self.reserve + gap - ceiling), 20, 20)
		return self:canDetail(bytes,kind)
	end
	-- Recover a feasible aggregate terrain plan without allocating or evicting visible detail.
	-- Clear the detail-pool constraint first; freeing a core image alone cannot fix that constraint.
	function self:recoverTerrain(required:number,replacing:number?):number
		local credit=math.clamp(replacing or 0,0,self.terrain)
		local available=self:detailHeadroom(credit,"terrain")
		if required<=available or required>self.detailLimit then return available end
		local before=self.used
		local detailNeed=math.max(0,self.detail+required-credit-self.detailLimit)
		if detailNeed>0 then self:reclaim(math.min(detailNeed,self.recoveryLimit),20,20,true) end
		local remaining=self.recoveryLimit-(before-self.used)
		if self.detail+required-credit<=self.detailLimit and remaining>0 then
			local need=required-self:detailHeadroom(credit,"terrain")
			self:reclaim(math.min(need,remaining),20,20)
		end
		return self:detailHeadroom(credit,"terrain")
	end
	function self:create(w: number, h: number, kind: string?,owner:string?): any
		kind = kind or "core"
		assert(w > 0 and h > 0 and w <= 1024 and h <= 1024 and w % 1 == 0 and h % 1 == 0, "invalid image dimensions")
		local bytes = w * h * 4
		local function refused()
			self.refusals[kind]=(self.refusals[kind] or 0)+1
			self.lastRefusal={kind=kind,width=w,height=h,used=self.used,detail=self.detail}
			return nil
		end
		if kind == "detail" or kind == "terrain" then
			-- Do not repeatedly probe Roblox when our policy already knows there is no headroom.
			if not self:prepareDetail(bytes,kind) then return refused() end
		else
			local ceiling = math.min(self.ceiling, self.knownCeiling or math.huge)
			self:reclaim(math.max(0, self.used + bytes - ceiling))
			if self.used + bytes > ceiling then return refused() end
		end
		-- A native refusal is a session-wide signal. No native re-probe until a tracked
		-- image was actually destroyed; merely waiting or retrying another owner is not progress.
		if self.blockedEpoch==self.epoch then self.suppressed+=1;return refused() end
		local ok, image = pcall(factory, w, h)
		if not ok or not image then
			self.nativeRefusals+=1;self.blockedEpoch=self.epoch
			-- First native refusal teaches a conservative ceiling. Release reusable detail and unused
			-- art before retrying a core image; do not retry an identical allocation without freeing.
			self.knownCeiling = math.min(self.knownCeiling or math.huge, self.used)
			if kind == "detail" or kind == "terrain" then return refused() end
			local before = self.used
			self:reclaim(math.huge)
			if self.used < before then
				ok, image = pcall(factory, w, h)
				if not ok or not image then self.nativeRefusals+=1;self.blockedEpoch=self.epoch end
			end
			if not ok or not image then return refused() end
		end
		self.blockedEpoch=nil
		self.records[image] = { bytes = bytes, kind = kind,owner=owner or kind,width=w,height=h }
		self.used += bytes
		if kind == "detail" or kind == "terrain" then self.detail += bytes end
		if kind == "terrain" then self.terrain += bytes end
		return image
	end
	return self
end

return ImageBudget
