--!strict
-- Imported IDs never replace local art before a matching, successfully loaded image is ready.
local Cache={}
function Cache.new(manifest:any,deps:any):any
	local self:any={entries={},running=nil,failures=0,rejected=0,hashes=setmetatable({},{__mode='k'})}
	function self.has(name:string):boolean return type(manifest)=='table' and type(manifest[name])=='table' end
	function self.get(name:string,meta:any):any
		local entry=type(manifest)=='table' and manifest[name]
		if type(entry)~='table' then return nil end
		local id=entry.id
		if type(id)~='string' or not id:match('^[1-9]%d*$') or #id>20 or entry.width~=meta.width or entry.height~=meta.height then
			if not self.entries[name]then self.rejected+=1;self.entries[name]={rejected=true}end
			return nil
		end
		local hash=self.hashes[meta]
		if not hash then hash=deps.hash(meta.rle or meta.deflate or '');self.hashes[meta]=hash end
		if hash~=entry.sourceHash then if not self.entries[name]then self.rejected+=1;self.entries[name]={rejected=true}end;return nil end
		local state=self.entries[name]
		if state and state.asset then return state.asset end
		if self.running or state and (state.rejected or deps.now()<(state.retryAt or 0)) then return nil end
		state={retryAt=math.huge};self.entries[name]=state;self.running=name
		local uri='rbxassetid://'..id
		local function done(ok:boolean)
			if self.entries[name]~=state or state.finished then return end
			state.finished=true
			self.running=nil
			if ok then local success,content=pcall(deps.content,uri);if success then state.asset={content=content,external=true,width=meta.width,height=meta.height};return end end
			self.failures+=1;state.retryAt=deps.now()+60
		end
		local ok=pcall(deps.start,uri,done)
		if not ok then done(false)end
		return state.asset
	end
	function self.waiting(name:string):boolean
		local entry=manifest[name];local state=self.entries[name]
		return type(entry)=='table' and (state==nil or not state.rejected and not state.asset and state.retryAt==math.huge)
	end
	function self.stats():any
		local ready=0;for _,entry in self.entries do if entry.asset then ready+=1 end end
		return {ready=ready,loading=self.running~=nil,failures=self.failures,rejected=self.rejected}
	end
	return self
end
return Cache
