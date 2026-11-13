--!strict
-- APPROX port image LOD policy; source geometry/animation stays at its original logical resolution.
local Lod={}
function Lod.stride(frame:number,pixels:number,previous:number?):number
 local ratio=pixels/math.max(1,frame)
 if previous==1 and ratio>=.42 then return 1 end
 if previous==2 and ratio<=.68 and ratio>=.18 then return 2 end
 if previous==4 and ratio<=.32 then return 4 end
 return if ratio>=.55 then 1 elseif ratio>=.22 then 2 else 4
end
function Lod.valid(source:any,data:any,stride:number,hash:number):boolean
 return type(data)=='table' and data.lod==stride and data.sourceHash==hash and data.frame==source.frame/stride
  and data.width==source.width/stride and data.height==source.height/stride and data.columns==source.columns and type(data.rle)=='string'
end
function Lod.new(deps:any):any
 local m:any={pages={},bound=setmetatable({},{__mode='k'}),job=nil,lastSliceMs=0,maxSliceMs=0}
 function m.register(p:any)
  p.stride=p.stride or 1;p.goal=p.stride;p.changed=deps.now();p.records=setmetatable({},{__mode='k'});p.labels=setmetatable({},{__mode='k'});p.missing=p.missing or {};m.pages[p]=true
 end
 function m.track(record:any,p:any):any record.page=p;record.content=p.content;p.records[record]=true;return record end
 function m.bind(label:any,record:any,frame:number?)
  local p=record.page;if not p then label.ImageContent=record.content;local size=frame or record.frame;if size then label.ImageRectSize=deps.vector(size,size) end;return end
  local old=m.bound[label]
  if old and old.page~=p then old.page.labels[label]=nil end
  if not old then label.Destroying:Connect(function()local current=m.bound[label];if current then current.page.labels[label]=nil;m.bound[label]=nil end end) end
  if not old or old.page~=p then label.ImageRectOffset=deps.vector(0,0) end
  local b={page=p,frame=frame or record.frame or p.meta.frame};m.bound[label]=b;p.labels[label]=b
  label.ImageContent=p.content;label.ImageRectSize=deps.vector(b.frame/p.stride,b.frame/p.stride)
 end
 function m.drop(p:any)
  p.dead=true;m.pages[p]=nil
  if p.pending then local pending=p.pending;p.pending=nil;deps.cancel(pending.image);deps.release(pending.image) end
 end
 local function publish(p:any,pending:any,ok:boolean)
  if p.pending~=pending then return end;p.pending=nil
  if not ok or p.dead or p.goal~=pending.stride then deps.release(pending.image);p.retryAt=deps.now()+1.5;return end
  local previous=p.content;local oldStride=p.stride;local rebound={};local content
  local success,err=pcall(function()
   content=deps.content(pending.image)
   for label,b in p.labels do
    local offset=label.ImageRectOffset;table.insert(rebound,{label,b,offset})
    label.ImageRectOffset=deps.vector(offset.X*oldStride/pending.stride,offset.Y*oldStride/pending.stride)
    label.ImageRectSize=deps.vector(b.frame/pending.stride,b.frame/pending.stride);label.ImageContent=content
   end
  end)
  if not success then
   for _,entry in rebound do pcall(function()entry[1].ImageContent=previous;entry[1].ImageRectOffset=entry[3];entry[1].ImageRectSize=deps.vector(entry[2].frame/oldStride,entry[2].frame/oldStride)end)end
   deps.release(pending.image);p.retryAt=deps.now()+1.5;deps.warn(p.name,err);return
  end
  local old=p.image;p.image,p.content,p.stride=pending.image,content,pending.stride
  for record in p.records do record.content=content end
  deps.release(old)
 end
 function m.step(cellPixels:number)
  local now=deps.now()
  for p in m.pages do
   local goal=Lod.stride(p.meta.frame,p.cells*cellPixels,p.goal)
   if p.missing[goal] then goal=if goal==4 and not p.missing[2] then 2 else 1 end
   if goal~=p.goal then p.goal=goal;p.changed=now end
  end
  -- Keep at most one replacement native image in flight, including a delayed upload.
  for p in m.pages do if p.pending then return end end
  local job=m.job
  if job and (job.page.dead or job.page.goal~=job.stride) then m.job=nil;job=nil end
  if not job then
   local candidate
   for p in m.pages do
    if not p.dead and not p.pending and p.goal~=p.stride and now-p.changed>=.3 and now>=(p.retryAt or 0) then
     if not candidate or p.at>candidate.at then candidate=p end
    end
   end
   if candidate then
    job={page=candidate,stride=candidate.goal};m.job=job
    job.thread=coroutine.create(function()
     local began=deps.now()
     return deps.prepare(candidate,job.stride,function()if deps.now()-began>=.002 then coroutine.yield();began=deps.now() end end)
    end)
   end
  end
  if not job then return end
  local began=deps.now();local ok,result=coroutine.resume(job.thread);m.lastSliceMs=(deps.now()-began)*1000;m.maxSliceMs=math.max(m.maxSliceMs,m.lastSliceMs)
  if not ok then m.job=nil;job.page.retryAt=deps.now()+1.5;deps.warn(job.page.name,result);return end
  if coroutine.status(job.thread)~='dead' then return end
  m.job=nil;local p=job.page
  if not result then p.missing[job.stride]=true;return end
  if p.dead or p.goal~=job.stride then return end
  local image=deps.create(result.width,result.height,p.kind)
  if not image then p.retryAt=deps.now()+1.5;return end
  if p.dead or p.goal~=job.stride then deps.release(image);return end
  local pending={image=image,stride=job.stride};p.pending=pending
  local called,accepted=pcall(deps.upload,image,result,function(success)publish(p,pending,success)end)
  if not called then deps.warn(p.name,accepted) end
  if not called or not accepted and p.pending==pending then publish(p,pending,false) end
 end
 function m.stats():any
  local count,bytes,full,half,quarter,pending=0,0,0,0,0,0
  for p in m.pages do count+=1;bytes+=p.meta.width*p.meta.height*4/p.stride^2;if p.stride==1 then full+=1 elseif p.stride==2 then half+=1 else quarter+=1 end;if p.pending then pending+=1 end end
  return {pages=count,bytes=bytes,full=full,half=half,quarter=quarter,pending=pending,preparing=m.job~=nil,lastSliceMs=m.lastSliceMs,maxSliceMs=m.maxSliceMs}
 end
 return m
end
return Lod
