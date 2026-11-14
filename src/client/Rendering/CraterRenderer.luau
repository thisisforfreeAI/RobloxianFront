--!strict
-- Bounded dynamic crater textures. APPROX residency/transport; painter rules come from the source.
local Shared=game:GetService('ReplicatedStorage'):WaitForChild('Shared')
local RunService=game:GetService('RunService')
local Pixels=require(Shared.Presentation.CraterPixels)
local View=require(Shared.Presentation.CraterView)
local World=require(Shared.Config.World)
local Memory=require(script.Parent.ImageMemory)
local Light=require(script.Parent.WorldLight)
local Roof=require(script.Parent.FireScorchRenderer)
local Renderer={MAX_VIEWS=16,ACTIVE_BYTES=512*1024,PEAK_BYTES=768*1024}
local current:any=nil
local function epoch():number return Memory.epoch()end
function Renderer.destroy()if current then current.folder:Destroy()end end
function Renderer.start(map:any,parent:Instance):boolean
 Renderer.destroy();local data=Shared:FindFirstChild('GameData');local source=data and data:FindFirstChild('CraterRules')
 if not source then return false end
 local ok,config=pcall(require,source);if not ok then return false end
 local folder=Instance.new('Folder');folder.Name='GroundCraters';folder.Parent=parent
 local st:any={folder=folder,config=config,view=View.new(map.width,map.height,config),views={},wanted={},bytes=0,dead=false};current=st
 local function dispose(v:any)
  if v.part then v.part:Destroy()end
  if v.image then local image=v.image;v.image=nil;Memory.cancelUploads(image);Memory.release(image);st.bytes-=v.bytes end
 end
 local function cancel()
  local job=st.job;st.job=nil;if job and job.image then dispose(job)end
 end
 local function clear()
  cancel();for id,v in st.views do dispose(v);st.views[id]=nil end
 end
 local unregister=Memory.register(10,function()clear();st.refused=epoch()end)
 local function valid(job:any):boolean
  local h=st.view.items[job.id]
  return not st.dead and st.job==job and st.wanted[job.id]~=nil and h~=nil and h.version==job.version
 end
 local function publish(job:any,box:any,good:boolean)
  if not good or not valid(job)then if job.image then dispose(job)end;if st.job==job then st.job=nil end;return end
  local built,part=pcall(function()
   local p=Instance.new('Part');job.part=p;p.Name='Crater_'..job.id
   p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Transparency=1
   p.Size=Vector3.new(box.height/box.scale*World.STUDS_PER_CELL,.01,box.width/box.scale*World.STUDS_PER_CELL)
   -- Top .115: above baked town detail (.105), below house-char/ruin pixels (.125).
   p.CFrame=CFrame.new(World.toWorld(box.left+box.width/box.scale/2,box.top+box.height/box.scale/2,.11))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
   local gui=Instance.new('SurfaceGui');gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=job.size;gui.LightInfluence=0
   local label=Instance.new('ImageLabel');label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.ResampleMode=Enum.ResamplerMode.Pixelated
   label.ImageContent=Content.fromObject(job.image);label.Parent=gui;gui.Parent=p;p.Parent=folder;return p
  end)
  if not built then dispose(job);st.job=nil;st.refused=epoch();return end
  local old=st.views[job.id];st.views[job.id]=job;st.job=nil;if old then dispose(old)end
 end
 local function prepare(h:any,mask:any)
  local job={id=h.id,version=h.version,key=h.key..(if mask then ':roof'else ':plain')};st.job=job
  task.spawn(function()
   local good,box=pcall(function()
    return Pixels.paint(config,h,function()
     assert(valid(job),'cancelled crater paint');task.wait();assert(valid(job),'cancelled crater paint')
    end,function(x,y)
     return x>=0 and y>=0 and x<map.width and y<map.height and (not mask or not mask.roof(math.floor(x*mask.tileSize),math.floor(y*mask.tileSize)))
    end)
   end)
   if not good or not valid(job)then if st.job==job then st.job=nil end;return end
   job.size=Vector2.new(box.width,box.height);job.bytes=box.width*box.height*4
   if st.bytes+job.bytes>Renderer.PEAK_BYTES or not Memory.canDetail(job.size,'detail')then st.refused=epoch();st.job=nil;return end
   if not valid(job)then return end
   job.image=Memory.create(job.size,'detail','CraterRenderer')
   if not job.image then st.refused=epoch();st.job=nil;return end
   st.bytes+=job.bytes
   if not valid(job)then dispose(job);return end
   local success,accepted=pcall(function()return Memory.upload(job.image,Vector2.zero,job.size,box.pixels,{priority=3,done=function(loaded)publish(job,box,loaded)end})end)
   if not success or not accepted then publish(job,box,false);st.refused=epoch()end
  end)
 end
 local elapsed=0
 local connection=RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt;if elapsed<.2 then return end;elapsed=0
  local camera=workspace.CurrentCamera;if not camera then clear();return end
  local bounds=Light.view(camera);local order={}
  if bounds.cellPixels>=config.paint.fromPx then for _,h in st.view.items do
   local reach=h.r*config.paint.throwTo+.5
   if math.abs(h.x-bounds.cx)<=bounds.rx+reach and math.abs(h.y-bounds.cy)<=bounds.ry+reach then table.insert(order,{hole=h,box=Pixels.bounds(config,h),distance=(h.x-bounds.cx)^2+(h.y-bounds.cy)^2})end
  end end
  table.sort(order,function(a,b)return if a.distance==b.distance then a.hole.id<b.hole.id else a.distance<b.distance end)
  local bytes,count=0,0;local wanted={}
  for _,item in order do local n=item.box.width*item.box.height*4
   if count>=Renderer.MAX_VIEWS then break end
   if bytes+n<=Renderer.ACTIVE_BYTES then wanted[item.hole.id]=true;bytes+=n;count+=1 end
  end;st.wanted=wanted
  for id,v in st.views do if not wanted[id]then dispose(v);st.views[id]=nil end end
  if st.job then if not valid(st.job)then cancel()else return end end
  if st.refused and st.refused==epoch()then return end
  local mask=nil
  for _,item in order do local h=item.hole;if not wanted[h.id]then continue end
   -- One shared lazy roof sampler; no duplicate atlas/image. Never paint a crater over roofs.
   if not mask then mask=Roof.source()end
   if not mask then
    local urban=false;local box=item.box
    for y=math.max(0,math.floor(box.top)),math.min(map.height-1,math.ceil(box.top+box.height/box.scale))do
     for x=math.max(0,math.floor(box.left)),math.min(map.width-1,math.ceil(box.left+box.width/box.scale))do
      if map.urban and buffer.readu8(map.urban,y*map.width+x)>0 then urban=true;break end
     end;if urban then break end
    end
    if urban then continue end
   end
   local key=h.key..(if mask then ':roof'else ':plain');local old=st.views[h.id]
   if not old or old.key~=key then
    local size=Vector2.new(item.box.width,item.box.height)
    if Memory.canDetail(size,'detail')then prepare(h,mask)else st.refused=epoch()end
    break
   end
  end
 end)
 folder.Destroying:Connect(function()st.dead=true;connection:Disconnect();unregister();clear();if current==st then current=nil end end)
 st.clear=clear;return true
end
function Renderer.apply(packet:any):boolean
 local st=current;if not st or st.dead then return false end
 local before=st.view.epoch
 if not st.view.apply(packet)then return false end
 if before~=st.view.epoch or packet.reset then st.clear()end;return true
end
function Renderer.stats():any
 local st=current;if not st then return {views=0,bytes=0,pending=0}end
 local count=0;for _ in st.views do count+=1 end
 return {views=count,bytes=st.bytes,pending=if st.job then 1 else 0,known=st.view.count}
end
return Renderer
