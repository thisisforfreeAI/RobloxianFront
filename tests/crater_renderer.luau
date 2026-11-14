--!strict
return function(test:any,eq:any)
 local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox');local fixture=require('./fixtures/crater_config')
 local function make():any
  local h:any={epoch=0,created=0,released=0,instances={},workers={},uploads={},listeners={},mask=nil,bounds={cx=15,cy=15,rx=100,ry=100,cellPixels=10}}
  local function signal()
   local s:any={listeners={}};function s:Connect(fn)local c={active=true,fn=fn};function c:Disconnect()self.active=false end;table.insert(self.listeners,c);return c end
   function s:fire(...)for _,c in table.clone(self.listeners)do if c.active then c.fn(...)end end end;return s
  end
  h.heartbeat=signal()
  local function instance(class)
   local obj:any={ClassName=class,Destroying=signal()};function obj:Destroy()if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy()end end end
   table.insert(h.instances,obj);return obj
  end
  local memory={epoch=function()return h.epoch end,canDetail=function(_,kind)eq(kind,'detail');if h.reclaimOnCheck then h.reclaimOnCheck();h.reclaimOnCheck=nil end;return not h.noSpace end,
   register=function(_,fn)table.insert(h.listeners,fn);local alive=true;return function()alive=false end end,
   create=function(size,kind,owner)eq(kind,'detail');eq(owner,'CraterRenderer');h.created+=1;if h.refuse then return nil end;return {size=size}end,
   cancelUploads=function(image)h.uploads[image]=nil end,
   release=function(image)assert(not image.dead,'double release');image.dead=true;h.released+=1;h.epoch+=1 end,
   upload=function(image,_,size,pixels,options)if h.rejectUpload then return false end;h.uploads[image]={image=image,size=size,pixels=pixels,done=options.done};return true end}
  local shared:any={Presentation={CraterPixels='pixels',CraterView='view'},Config={World='world'}}
  local data={FindFirstChild=function()return if h.missing then nil else 'config'end};function shared:FindFirstChild()return data end
  local modules={pixels=require('../src/shared/Presentation/CraterPixels'),view=require('../src/shared/Presentation/CraterView'),world={STUDS_PER_CELL=4,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z)return rb.Vector3.new(x*4,z,y*4)end},memory=memory,light={view=function()return h.bounds end},roof={source=function()return h.mask end},config=fixture}
  local env=setmetatable({game={GetService=function(_,name)return if name=='RunService'then {Heartbeat=h.heartbeat}else {WaitForChild=function()return shared end}end},script={Parent={ImageMemory='memory',WorldLight='light',FireScorchRenderer='roof'}},require=function(n)return assert(modules[n],tostring(n))end,
   task={spawn=function(fn)table.insert(h.workers,coroutine.create(fn))end,wait=function()coroutine.yield()end},Instance={new=instance},workspace={CurrentCamera={}},Vector2=rb.Vector2,Vector3=rb.Vector3,CFrame=rb.CFrame,UDim2=rb.UDim2,Content={fromObject=function(image)if h.failContent then error('synthetic Content failure')end;assert(not image.dead);return image end},Enum={NormalId={Top=0},SurfaceGuiSizingMode={FixedSize=0},ResamplerMode={Pixelated=0}}},{__index=getfenv()})
  h.renderer=luau.load(fs.readFile('src/client/Rendering/CraterRenderer.luau'),{environment=env})();h.map={width=100,height=100,urban=buffer.create(10000)};h.parent=instance('Folder')
  function h.start()return h.renderer.start(h.map,h.parent)end
  function h.step()h.heartbeat:fire(.2)end
  function h.pump()
   for _=1,100 do if #h.workers==0 then break end;local keep={};for _,thread in h.workers do local ok,err=coroutine.resume(thread);assert(ok,err);if coroutine.status(thread)~='dead'then table.insert(keep,thread)end end;h.workers=keep end;eq(#h.workers,0)
  end
  function h.flush(good)
   local jobs=h.uploads;h.uploads={};for _,job in jobs do if not job.image.dead then job.image.last=job.pixels;job.done(good~=false)end end
  end
  function h.packet(sequence,rows,reset)return h.renderer.apply({epoch=1,sequence=sequence,reset=reset==true,rows=rows})end
  function h.finish()h.step();h.pump();h.flush()end
  function h.parts()local n=0;for _,v in h.instances do if v.ClassName=='Part'and not v.dead then n+=1;eq(v.CanQuery,false);eq(v.CastShadow,false);eq(v.CanCollide,false)end end;return n end
  h.memory=memory;h.env=env;return h
 end
 local function row(id,r,fill,x,y)return {id,x or 10,y or 12,r or 1,fill or 0,'#556644',''}end
 test('actual crater renderer publishes only complete uploads and uses one shared-budget image per visible hole',function()
  local h=make();assert(h.start());assert(h.packet(1,{row(1)},true));h.step();eq(h.renderer.stats().pending,1);eq(h.parts(),0);h.pump();eq(h.created,1);eq(h.parts(),0);h.flush();eq(h.parts(),1);eq(h.renderer.stats().views,1);assert(h.renderer.stats().bytes>0)
  for _,part in h.instances do if part.ClassName=='Part'and not part.dead then local top=part.CFrame.Position.Y+part.Size.Y/2;assert(top>.105 and top<.125,'craters must clear baked detail while remaining below the ruin overlay')end end
  h.step();h.pump();eq(h.created,1,'unchanged crater must not repaint');h.renderer.destroy();eq(h.released,1);eq(h.parts(),0);eq(h.renderer.stats().bytes,0)
 end)
 test('crater replacement keeps old content through paint and upload then releases the old image',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.finish();eq(h.parts(),1);h.packet(2,{row(1,1.4)},false);h.step();h.pump();eq(h.parts(),1);eq(h.released,0);h.flush();eq(h.parts(),1);eq(h.released,1);eq(h.created,2)
 end)
 test('failed or rejected uploads retain previous crater and release the unbound replacement',function()
  for _,rejected in {false,true}do local h=make();h.start();h.packet(1,{row(1)},true);h.finish();h.packet(2,{row(1,1.4)},false);h.rejectUpload=rejected;h.step();h.pump();if not rejected then h.flush(false)end;eq(h.parts(),1);eq(h.released,1);eq(h.renderer.stats().pending,0)end
 end)
 test('image refusal latches until a tracked release instead of preparing every heartbeat',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.refuse=true;h.step();h.pump();eq(h.created,1);for _=1,10 do h.step();h.pump()end;eq(h.created,1);h.refuse=false;h.epoch+=1;h.finish();eq(h.created,2);eq(h.parts(),1)
 end)
 test('offscreen camera change cancels cooperative raster and unloads native views',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.step();h.bounds.cx=1000;h.step();h.pump();eq(h.created,0);eq(h.renderer.stats().pending,0);h.bounds.cx=15;h.finish();eq(h.parts(),1);h.bounds.cellPixels=0;h.step();eq(h.parts(),0);eq(h.created,h.released)
 end)
 test('view reset cancels queued writes and late callbacks cannot publish stale parts',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.step();h.pump();local saved;for _,job in h.uploads do saved=job end;assert(saved);h.packet(2,{},true);eq(h.released,1);saved.done(true);eq(h.parts(),0);eq(h.renderer.stats().pending,0);h.renderer.destroy();eq(h.released,1)
 end)
 test('native binding failure releases partial objects while keeping the previous image',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.finish();h.packet(2,{row(1,1.4)},false);h.failContent=true;h.finish();eq(h.parts(),1);eq(h.released,1);eq(h.renderer.stats().views,1)
 end)
 test('shared pressure reclamation cancels in-flight work and clears every owned image',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.finish();h.packet(2,{row(1,1.4)},false);h.step();h.pump();eq(h.created,2);h.listeners[1]();h.flush();eq(h.parts(),0);eq(h.released,2);eq(h.renderer.stats().bytes,0);eq(h.renderer.stats().pending,0)
 end)
 test('reclamation during admission cannot leave a job or image outside the ownership cache',function()
  local h=make();h.start();h.packet(1,{row(1)},true);h.step();h.reclaimOnCheck=h.listeners[1];h.pump();h.flush();eq(h.parts(),0);eq(h.created,0);eq(h.renderer.stats().pending,0);eq(h.renderer.stats().bytes,0)
 end)
 test('wide-view selection stays at sixteen images with one cooperative worker and bounded bytes',function()
  local h=make();h.start();local rows={};for id=1,24 do table.insert(rows,row(id,1,0,10+id,15))end;h.packet(1,rows,true)
  for _=1,30 do h.step();assert(h.renderer.stats().pending<=1);h.pump();h.flush();assert(h.renderer.stats().bytes<=h.renderer.PEAK_BYTES)end
  eq(h.parts(),16);eq(h.renderer.stats().views,16);eq(h.created,16);assert(h.renderer.stats().bytes<=h.renderer.ACTIVE_BYTES);h.renderer.destroy();eq(h.created,h.released)
 end)
 test('urban craters wait for the shared roof mask and never paint over roof texels',function()
  local h=make();buffer.fill(h.map.urban,0,1);h.start();h.packet(1,{row(1)},true);h.finish();eq(h.created,0)
  h.mask={tileSize=4,roof=function()return true end};h.finish();eq(h.parts(),1);for _,v in h.instances do if v.ClassName=='ImageLabel'and v.ImageContent then local pixels=v.ImageContent.last;for at=3,buffer.len(pixels)-1,4 do eq(buffer.readu8(pixels,at),0)end end end
 end)
 test('missing private crater settings leave no callbacks or native images',function()
  local h=make();h.missing=true;eq(h.start(),false);h.finish();eq(h.created,0);eq(#h.heartbeat.listeners,0);eq(h.parts(),0)
 end)
end
