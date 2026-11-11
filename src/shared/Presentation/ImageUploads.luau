--!strict
-- APPROX port scheduler: one image per render frame, latest snapshots, bounded CPU storage.
-- Each image ages from its FIRST pending request, so continuous rewrites cannot starve it.
local Uploads={}
function Uploads.new(write:any,clock:any,options:any?):any
	local o=options or {}
	local self:any={records={},versions=setmetatable({},{__mode="k"}),bytes=0,count=0,serial=0,
		maxBytes=o.maxBytes or 16*1024*1024,criticalBytes=o.criticalBytes or 4*1024*1024,maxImages=o.maxImages or 64,maxRegions=o.maxRegions or 64,
		maxWrites=o.maxWrites or 32,maxFrameBytes=o.maxFrameBytes or 4*1024*1024,ageSec=o.ageSec or .25,submitted=0,coalesced=0,completed=0,rejected=0,failed=0}
	local function notify(job,ok,err) if job.done then pcall(job.done,ok,err) end end
	function self.cancel(image:any)
		self.versions[image]=(self.versions[image] or 0)+1
		local r=self.records[image];if not r then return end
		for _,job in r.jobs do self.bytes-=buffer.len(job.pixels) end
		self.records[image]=nil;self.count-=1
	end
	function self.submit(image:any,position:any,size:any,pixels:buffer,settings:any?):boolean
		local s=settings or {};local key=s.key or "full";local priority=s.priority or 2
		assert(image~=nil and type(priority)=="number" and priority>=0 and priority<=3,"invalid upload priority/image")
		assert(position.X>=0 and position.Y>=0 and position.X%1==0 and position.Y%1==0 and size.X>0 and size.Y>0 and size.X%1==0 and size.Y%1==0,"invalid image upload region")
		assert(typeof(pixels)=="buffer" and buffer.len(pixels)==size.X*size.Y*4,"invalid image upload pixels")
		local r=self.records[image];local replaced=0;local regions=0
		if r then for oldKey,job in r.jobs do regions+=1;if key=="full" or oldKey==key then replaced+=buffer.len(job.pixels) end end end
		local total=self.bytes-replaced+buffer.len(pixels)
		local byteLimit=self.maxBytes+(if priority==0 then self.criticalBytes else 0)
		local imageLimit=if priority==0 then self.maxImages else math.max(1,self.maxImages-4)
		if total>byteLimit or not r and self.count>=imageLimit or r and key~="full" and not r.jobs[key] and regions>=self.maxRegions then self.rejected+=1;return false end
		-- Own a snapshot: lighting/scar producers may mutate their source again before this frame.
		local copy=buffer.create(buffer.len(pixels));buffer.copy(copy,0,pixels)
		self.serial+=1
		if not r then r={since=clock(),sequence=self.serial,jobs={}};self.records[image]=r;self.count+=1 end
		if replaced>0 then self.coalesced+=1 end
		if key=="full" then table.clear(r.jobs) end
		r.jobs[key]={x=position.X,y=position.Y,w=size.X,h=size.Y,pixels=copy,priority=priority,sequence=self.serial,done=s.done,version=self.versions[image] or 0}
		self.bytes=total;self.submitted+=1;return true
	end
	function self.step():boolean
		local chosen,r,score=nil,nil,math.huge;local now=clock()
		for image,record in self.records do
			local priority=3;for _,job in record.jobs do priority=math.min(priority,job.priority) end
			local value=priority-(now-record.since)/self.ageSec
			if value<score or value==score and (not r or record.sequence<r.sequence) then chosen,r,score=image,record,value end
		end
		if not r then return false end
		local jobs={};for key,job in r.jobs do table.insert(jobs,{key=key,job=job}) end
		table.sort(jobs,function(a,b) return a.job.sequence<b.job.sequence end)
		local bytes=0;for i=1,math.min(#jobs,self.maxWrites) do
			local entry=jobs[i];local job=entry.job
			if bytes>0 and bytes+buffer.len(job.pixels)>self.maxFrameBytes then break end
			if (self.versions[chosen] or 0)~=job.version then break end
			-- Remove before callbacks; callbacks can submit, cancel, release or reuse this image.
			if self.records[chosen]~=r or r.jobs[entry.key]~=job then continue end
			r.jobs[entry.key]=nil;self.bytes-=buffer.len(job.pixels)
			bytes+=buffer.len(job.pixels)
			if next(r.jobs)==nil then self.records[chosen]=nil;self.count-=1 end
			local ok,err=pcall(write,chosen,job.x,job.y,job.w,job.h,job.pixels)
			if ok then self.completed+=1;notify(job,true,nil)
			else self.failed+=1;self.cancel(chosen);notify(job,false,err);break end
		end
		return true
	end
	function self.stats():any
		local oldest=0;for _,r in self.records do oldest=math.max(oldest,clock()-r.since) end
		return {images=self.count,bytes=self.bytes,oldest=oldest,submitted=self.submitted,coalesced=self.coalesced,completed=self.completed,rejected=self.rejected,failed=self.failed}
	end
	return self
end
return Uploads
