--!strict
return function(test:any,eq:any)
 local Lod=require('../src/shared/Presentation/SpriteLod');local Codec=require('../src/shared/Assets/PixelCodec');local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
 local function signal()local s:any={cs={}};function s:Connect(fn)local c:any={fn=fn};function c:Disconnect()self.dead=true end;table.insert(self.cs,c);return c end;function s:fire()for _,c in self.cs do if not c.dead then c.fn()end end end;return s end
 local function label()return {Destroying=signal(),ImageRectOffset=rb.Vector2.zero,ImageRectSize=rb.Vector2.zero}end
 local function fixture()
  local h:any={now=0,images={},uploads={},released={},warnings=0}
  local deps={now=function()return h.now end,vector=rb.Vector2.new,content=function(image)if h.failContent then error('content unavailable')end;return image end,warn=function()h.warnings+=1 end,
   create=function(w,height,kind)if h.refuse then return nil end;local image={width=w,height=height,kind=kind};table.insert(h.images,image);return image end,
   release=function(image)assert(not image.dead);for _,l in h.watched or {} do assert(l.ImageContent~=image,'released image is still bound')end;image.dead=true;table.insert(h.released,image)end,
   cancel=function(image)for _,u in h.uploads do if u.image==image then u.dead=true end end end,
   prepare=function(p,stride,checkpoint)if h.missing==stride then return nil end;if h.yieldWork then for _=1,5 do h.now+=.001;checkpoint()end end;return {width=p.meta.width/stride,height=p.meta.height/stride,pixels=buffer.create(p.meta.width*p.meta.height*4/stride^2)}end,
   upload=function(image,data,done)if h.throwUpload then error('upload failure')end;table.insert(h.uploads,{image=image,data=data,done=done});return true end}
  h.manager=Lod.new(deps);h.p={name='test',meta={frame=120,width=240,height=480},cells=2.6,stride=1,image={},content={},kind='core',at=0};h.p.content=h.p.image;h.manager.register(h.p)
  function h:step(px,dt)h.now+=dt or .1;h.manager.step(px)end
  function h:finish(ok)local u=table.remove(h.uploads,1);assert(u);if not u.dead then u.done(ok~=false)end end
  return h
 end
 test('sprite quality policy uses physical image tiers with hysteresis rather than oscillating on small zoom changes',function()
  eq(Lod.stride(120,110),1);eq(Lod.stride(120,40),2);eq(Lod.stride(120,10),4)
  eq(Lod.stride(120,51,1),1);eq(Lod.stride(120,50,1),2);eq(Lod.stride(120,75,2),2);eq(Lod.stride(120,85,2),1)
  eq(Lod.stride(120,25,4),4);eq(Lod.stride(120,42,4),2)
 end)
 test('shared page downgrade waits for complete upload then updates all crops before releasing the old image',function()
  local h=fixture();local a,b=label(),label();local rec=h.manager.track({frame=120},h.p);h.manager.bind(a,rec);h.manager.bind(b,rec);a.ImageRectOffset=rb.Vector2.new(120,240);b.ImageRectOffset=rb.Vector2.new(0,360);h.watched={a,b}
  local old=h.p.image;h:step(3);h:step(3,.4);eq(#h.uploads,1);eq(h.p.stride,1);eq(a.ImageContent,old);eq(old.dead,nil)
  h:finish();eq(h.p.stride,4);eq(a.ImageRectOffset.X,30);eq(a.ImageRectOffset.Y,60);eq(b.ImageRectOffset.Y,90);eq(a.ImageRectSize.X,30);eq(a.ImageContent,b.ImageContent);eq(rec.content,a.ImageContent);eq(old.dead,true)
  eq(h.manager.stats().bytes,240*480*4/16)
 end)
 test('zoom changes before queued publication discard obsolete detail without blanking or leaking the current page',function()
  local h=fixture();h:step(3);h:step(3,.4);local old=h.p.image;h:step(100);h:finish();eq(h.p.image,old);eq(old.dead,nil);eq(h.images[1].dead,true)
 end)
 test('image refusal, failed writes and failed content binding retain the complete existing sprite',function()
  for _,failure in {'refuse','write','content','throwUpload'} do
   local h=fixture();local l=label();h.manager.bind(l,h.manager.track({frame=120},h.p));local old=h.p.image
   if failure=='refuse' or failure=='throwUpload' then h[failure]=true end
   h:step(3);h:step(3,.4)
   if failure=='write' then h:finish(false)elseif failure=='content' then h.failContent=true;h:finish()end
   eq(h.p.image,old);eq(l.ImageContent,old);eq(old.dead,nil);eq(h.p.pending,nil)
  end
 end)
 test('cooperative preparation cancels safely during zoom reversal and page reclamation',function()
  local h=fixture();h.yieldWork=true;h:step(3);h:step(3,.4);eq(h.manager.stats().preparing,true);eq(#h.images,0)
  h:step(100);eq(h.manager.stats().preparing,false);eq(#h.images,0)
  h:step(3);h:step(3,.4);h.manager.drop(h.p);h:step(3);eq(h.manager.stats().pages,0);eq(#h.images,0)
 end)
 test('destroyed labels and labels rebound to another page leave no stale publication owner',function()
  local h=fixture();local l=label();local a=h.manager.track({frame=120},h.p);h.manager.bind(l,a);l.Destroying:fire();eq(next(h.p.labels),nil)
  local other={name='other',meta=h.p.meta,cells=2.6,image={},content={},at=0,kind='core'};h.manager.register(other);l=label();h.manager.bind(l,a);h.manager.bind(l,h.manager.track({frame=120},other));eq(next(h.p.labels),nil);assert(other.labels[l]);l.Destroying:fire();eq(next(other.labels),nil)
 end)
 test('missing optional sprite mips do not retry preparation endlessly or discard a valid source sheet',function()
  local h=fixture();h.missing=4;h:step(3);h:step(3,.4);eq(h.p.missing[4],true);h:step(3);h:step(3,.4);eq(h.p.goal,2);h:finish();eq(h.p.stride,2)
 end)
 test('RGBA RLE decode checkpoints suspend without changing transparent or opaque pixels',function()
  local raw=buffer.create(12);buffer.writeu16(raw,0,4096);buffer.writeu32(raw,2,0x44332211);buffer.writeu16(raw,6,4096);buffer.writeu32(raw,8,0)
  local expected=Codec.decode(raw,128,64);local calls=0;local thread=coroutine.create(function()return Codec.decode(raw,128,64,function()calls+=1;coroutine.yield()end)end);local result
  repeat local ok,value=coroutine.resume(thread);assert(ok,value);result=value until coroutine.status(thread)=='dead'
  assert(calls>=8);eq(buffer.tostring(result),buffer.tostring(expected))
 end)

 test('failed label rebinding rolls every touched label back before discarding the replacement',function()
  local h=fixture();local a=label();local backing=label();local old=h.p.image
  local b=setmetatable({},{__index=backing,__newindex=function(_,key,value)if key=='ImageContent' and value~=old then error('synthetic label failure')end;backing[key]=value end})
  local rec=h.manager.track({frame=120},h.p);h.manager.bind(a,rec);h.manager.bind(b,rec);a.ImageRectOffset=rb.Vector2.new(120,240);h.watched={a,b}
  h:step(3);h:step(3,.4);h:finish();eq(h.p.image,old);eq(a.ImageContent,old);eq(b.ImageContent,old);eq(a.ImageRectOffset.X,120);eq(a.ImageRectSize.X,120);eq(h.images[1].dead,true);eq(h.warnings,1)
 end)
 test('pending image reclamation cancels its upload and releases its image exactly once',function()
  local h=fixture();h:step(3);h:step(3,.4);local pending=h.uploads[1].image;h.manager.drop(h.p);eq(pending.dead,true);h:finish();eq(#h.released,1);eq(h.manager.stats().pending,0)
 end)
 test('an upgrade refused by memory pressure retries later while the existing coarse image remains bound',function()
  local h=fixture();h:step(3);h:step(3,.4);h:finish();local coarse=h.p.image;h.refuse=true;h:step(100);h:step(100,.4);eq(h.p.image,coarse)
  h.refuse=false;h:step(100,2);h:finish();eq(h.p.stride,1);eq(coarse.dead,true)
 end)

 test('delayed uploads cannot accumulate multiple replacement native images across page families',function()
  local h=fixture();local p={name='other',meta=h.p.meta,cells=2.6,image={},content={},kind='core',at=1};h.manager.register(p);h:step(3);h:step(3,.4)
  for _=1,10 do h:step(3)end;eq(#h.uploads,1);eq(#h.images,1);h:finish();h:step(3);eq(#h.images,2)
 end)
 local function bankFixture()
  local h:any={now=0,images={},pending={},warning=0,cameraY=10000,decodes=0,modules={}}
  local Lods=require('../src/shared/Presentation/TownLods')
  local function add(name,strips)
   local source={frame=4,width=8,height=16,columns=2,strips=strips,rle=name};h.modules[name]={value=source,IsA=function()return true end}
   for _,stride in {2,4} do h.modules[name..'_Mip'..stride]={value={lod=stride,frame=4/stride,width=8/stride,height=16/stride,columns=2,sourceHash=Lods.signature(name),rle=name..stride},IsA=function()return true end}end
  end
  add('OrigTank',{hull_colour=0,hull_paint=4,turret_colour=8,turret_paint=12});add('OrigMenRifle',{stand_colour=0,stand_paint=4,walk0_colour=8,walk0_paint=12})
  local memory={create=function(size,kind)if h.refuse then return nil end;local image={size=size,kind=kind};function image:WritePixelsBuffer()self.written=true end;table.insert(h.images,image);return image end,upload=function(image,pos,size,pixels,options)table.insert(h.pending,{image=image,done=options.done});return true end,
   release=function(image)if image then assert(not image.dead);image.dead=true;if h.onRelease then h.onRelease()end end end,cancelUploads=function()end,
   stats=function()return 0 end,register=function(_,fn)h.reclaim=fn end,onRelease=function(fn)h.onRelease=fn end}
  local folder={FindFirstChild=function(_,name)return h.modules[name]end,GetChildren=function()return{}end}
  local shared={Maps={MapCodec='codec'},Assets={PixelCodec='pixels'},Presentation={SpriteLod='lod',TownLods='hash'},Config={World='world'}}
  local mods={memory=memory,codec={base64Decode=function(text,checkpoint)if checkpoint then checkpoint(0)end;return text end},pixels={decode=function(_,w,height,checkpoint)h.decodes+=1;if checkpoint then checkpoint(0)end;return buffer.create(w*height*4)end},lod=Lod,hash=Lods,world={STUDS_PER_CELL=4,GROUND_Y=0}}
  local env=setmetatable({game={GetService=function()return{WaitForChild=function()return shared end}end},script={Parent={ImageMemory='memory',Parent={FindFirstChild=function()return folder end}}},require=function(key)return if type(key)=='table' then key.value else mods[key]end,
   workspace={CurrentCamera={CFrame={Position=rb.Vector3.new(0,h.cameraY,0),LookVector=rb.Vector3.new(0,-1,0)},ViewportSize=rb.Vector2.new(800,600),FieldOfView=60}},Vector2=rb.Vector2,Content={fromObject=function(image)return image end},os={clock=function()return h.now end},warn=function()h.warning+=1 end,print=function()end},{__index=getfenv()})
  h.bank=luau.load(fs.readFile('src/client/Rendering/SpriteBank.luau'),{environment=env})();function h:step(y,dt)self.now+=dt or .1;env.workspace.CurrentCamera.CFrame.Position=rb.Vector3.new(0,y,0);self.bank.step()end
  function h:finish()for _,pending in self.pending do pending.done(true)end;self.pending={}end
  return h
 end
 test('actual SpriteBank first admits quarter-size vehicle and figure sheets while preserving logical frame geometry',function()
  local h=bankFixture();local tank=h.bank.look('tank');local rifle=h.bank.figure('rifle');eq(tank.frame,4);eq(rifle.frame,4);eq(tank.page.stride,4);eq(rifle.page.stride,4);eq(#h.images,2);eq(h.images[1].size.X,2);eq(h.images[1].size.Y,4)
  local l=label();h.bank.bind(l,tank.body,4);eq(l.ImageRectSize.X,1);local at=h.bank.offset(tank,4,1);eq(at.X,1);eq(at.Y,1);eq(tank.cells,1*1.3/.492)
 end)
 test('actual SpriteBank upgrades live figure crops and shared contents after settled zoom without retaining the old native image',function()
  local h=bankFixture();local fig=h.bank.figure('rifle');local l=label();h.bank.bind(l,fig,4);local old=fig.content;h:step(20);h:step(20,.4);eq(fig.content,old);h:finish();eq(fig.page.stride,1);eq(l.ImageContent,fig.content);eq(l.ImageRectSize.X,4);eq(old.dead,true)
 end)
 test('actual SpriteBank rejects stale generated sheets and falls back to source art',function()
  local h=bankFixture();h.modules.OrigTank_Mip4.value.sourceHash+=1;h.modules.OrigTank_Mip2=nil;local look=h.bank.look('tank');eq(look.page.stride,1);eq(h.warning,0);eq(h.images[1].size.X,8)
 end)
end
