--!strict
return function(test:any,eq:any)
	local Policy=require('../src/shared/Presentation/ImagePressure');local Lod=require('../src/shared/Presentation/SpriteLod');local Cache=require('../src/shared/Presentation/StaticAssetCache')
	local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox')
	local function signal()local s={};function s:Connect(fn)self.fn=fn end;return s end
	local function label()return {Visible=true,Destroying=signal(),ImageRectOffset=rb.Vector2.zero,ImageRectSize=rb.Vector2.new(48,48)}end
	local function fixture(cropped:boolean?):any
		local h:any={now=0,epoch=0,creates=0,prepares=0,uploads={},released=0,floor=1,labels={}}
		local deps={now=function()return h.now end,vector=rb.Vector2.new,emptyContent='empty',content=function(image)return image.content or image end,
			minimum=function(_,visible)return if h.camera and not visible then 4 else h.floor end,epoch=function()return h.epoch end,
			asset=function()return h.asset end,
			create=function(w,height)h.creates+=1;if h.refuse then return nil end;return {width=w,height=height}end,
			release=function(image)if not image then return end;for _,l in h.labels do assert(l.ImageContent~=image,'released image still bound')end;image.dead=true;h.epoch+=1;h.released+=1 end,
			cancel=function()end,warn=function()h.warnings=(h.warnings or 0)+1 end,
			prepare=function(_,stride)h.prepares+=1;return {width=128,height=64,meta={rects={a={2,3,8,10},empty={0,0,0,0}}},pixels=buffer.create(128*64*4)}end,
			upload=function(image,data,done)table.insert(h.uploads,{image=image,done=done});return true end}
		h.m=Lod.new(deps);local image={};h.p={name='test',meta={frame=48,width=512,height=500},layout={},cells=2,stride=1,image=image,content=image,kind=if cropped then 'detail'else 'core',cropped=cropped,at=0};h.m.register(h.p)
		function h:step(dt)self.now+=dt or .4;self.m.step(100)end
		function h:finish()local u=table.remove(self.uploads,1);assert(u);u.done(true)end
		return h
	end
	test('image pressure escalates on native refusal and restores quality only after a sustained calm interval',function()
		local s=Policy.new();eq(Policy.sample(s,20,10,100,100,0,0),0);eq(Policy.sample(s,90,10,100,100,0,1),1)
		eq(Policy.sample(s,30,10,100,100,1,2),2);eq(Policy.sample(s,30,10,100,100,1,4),2)
		eq(Policy.sample(s,30,10,100,100,1,20),2);eq(Policy.sample(s,30,10,100,100,1,26),1);eq(Policy.sample(s,30,10,100,100,1,35),0)
		eq(Policy.floor(0,'core',true),1);eq(Policy.floor(1,'detail',true),2);eq(Policy.floor(2,'core',true),2);eq(Policy.floor(0,'core',false),4)
	end)
	test('camera residency reduces only offscreen pages and retains the current visible source tier',function()
		local h=fixture();h.camera=true
		local distant={name='offscreen',meta=h.p.meta,cells=2,image={},content={},kind='core',at=0};distant.content=distant.image;h.m.register(distant)
		for _=1,6 do h.m.observe(h.m.track({},h.p),true);h:step(.3)end
		eq(h.p.goal,1);eq(distant.goal,4);eq(#h.uploads,1);h:finish();eq(distant.stride,4);eq(h.p.stride,1);eq(h.m.stats().offscreen,1)
	end)
	test('cropped masks rebind actual native rectangles while preserving logical crop geometry',function()
		local h=fixture(true);local l=label();h.labels={l};local record=h.m.track({},h.p);local original={20,30,32,40,4,8,48}
		h.m.bindCrop(l,record,'a',original);eq(l.ImageRectOffset,rb.Vector2.new(20,30));local old=h.p.image
		h.floor=4;h:step();h:step();eq(l.ImageContent,old);h:finish();eq(l.ImageRectOffset,rb.Vector2.new(2,3));eq(l.ImageRectSize,rb.Vector2.new(8,10));eq(old.dead,true);eq(record.content,l.ImageContent)
	end)
	test('optional mask downshift can free its old image before retry without blanking a unit body',function()
		local h=fixture(true);local l=label();h.labels={l};local rec=h.m.track({},h.p);h.m.bindCrop(l,rec,'a',{20,30,32,40,4,8,48});local old=h.p.image
		h.refuse=true;h.floor=4;h:step();h:step();eq(old.dead,true);eq(l.ImageContent,'empty');eq(l.Visible,false);eq(h.p.suspended,true)
		h.refuse=false;h:step(2);h:finish();eq(h.p.stride,4);eq(l.Visible,true);eq(h.p.suspended,false)
	end)
	test('transparent pose changes during mask suspension cannot restore an old visible crop',function()
		local h=fixture(true);local l=label();h.labels={l};local rec=h.m.track({},h.p);h.m.bindCrop(l,rec,'a',{0,0,32,40,0,0,48})
		h.refuse=true;h.floor=4;h:step();h:step();h.m.bindCrop(l,rec,'empty',{0,0,0,0,0,0,48});h.refuse=false;h:step(2);h:finish();eq(l.Visible,false)
	end)
	test('core image refusal retains bound art and skips preparation until the budget release epoch changes',function()
		local h=fixture();local l=label();h.labels={l};h.m.bind(l,h.m.track({frame=48},h.p));local old=h.p.image
		h.floor=2;h.refuse=true;h:step();h:step();local preparations=h.prepares;eq(old.dead,nil);eq(l.ImageContent,old)
		for _=1,10 do h:step(2)end;eq(h.prepares,preparations);eq(h.creates,1)
		h.refuse=false;h.epoch+=1;h:step(2);h:finish();eq(old.dead,true);eq(h.p.stride,2)
	end)
	test('native replacements for cropped masks and unit pages share a single pending upload',function()
		local h=fixture(true);local other={name='body',meta=h.p.meta,cells=2,image={},content={},kind='core',at=1};h.m.register(other)
		h.floor=4;h:step();h:step();for _=1,20 do h:step()end;eq(h.creates,1);eq(#h.uploads,1)
		h:finish();h:step();eq(h.creates,2)
	end)
	test('loaded regular image publishes into existing owners without creating or uploading another EditableImage',function()
		local h=fixture();local l=label();h.labels={l};local rec=h.m.track({frame=48},h.p);h.m.bind(l,rec);local old=h.p.image
		h.asset={content='rbxassetid://123',external=true,width=512,height=500};h:step();eq(l.ImageContent,'rbxassetid://123');eq(rec.content,l.ImageContent);eq(old.dead,true);eq(h.creates,0);eq(#h.uploads,0);eq(h.m.stats().bytes,0);eq(h.m.stats().external,1)
	end)
	test('pressure cannot replace a resident regular asset with an EditableImage when another uploaded tier is absent',function()
		local h=fixture();h.p.external=true;h.floor=4;for _=1,20 do h:step()end
		eq(h.p.stride,1);eq(h.creates,0);eq(h.prepares,0);eq(h.m.stats().bytes,0)
	end)
	local function cacheFixture():any
		local h:any={now=0,starts={},callbacks={}};local manifest={a={id='123',width=8,height=8,sourceHash=7},b={id='456',width=8,height=8,sourceHash=7}}
		h.meta={width=8,height=8,rle='pixels'}
		h.cache=Cache.new(manifest,{now=function()return h.now end,hash=function()return 7 end,content=function(uri)return uri end,start=function(uri,done)table.insert(h.starts,uri);table.insert(h.callbacks,done)end});h.manifest=manifest;return h
	end
	test('regular asset loading is serialized and local fallback stays active until successful preload',function()
		local h=cacheFixture();eq(h.cache.get('a',h.meta),nil);eq(h.cache.get('b',h.meta),nil);eq(#h.starts,1);assert(h.cache.waiting('a'));h.callbacks[1](true)
		local asset=h.cache.get('a',h.meta);eq(asset.content,'rbxassetid://123');assert(asset.external);eq(h.cache.get('b',h.meta),nil);eq(#h.starts,2)
	end)
	test('rejected or unavailable static assets safely retain local pixels without a request loop',function()
		local h=cacheFixture();h.manifest.a.sourceHash=99;eq(h.cache.get('a',h.meta),nil);eq(h.cache.waiting('a'),false);eq(#h.starts,0)
		h.cache.get('b',h.meta);h.callbacks[1](false);for _=1,100 do eq(h.cache.get('b',h.meta),nil)end;eq(#h.starts,1);eq(h.cache.waiting('b'),false)
		h.now=61;h.cache.get('b',h.meta);eq(#h.starts,2);h.callbacks[2](true);h.callbacks[2](false);eq(h.cache.stats().failures,1)
	end)
	test('invalid image IDs and mismatched atlas dimensions cannot stall normal fallback loading',function()
		for _,bad in {{id='0',width=8,height=8,sourceHash=7},{id='rbxassetid://123',width=8,height=8,sourceHash=7},{id='123',width=16,height=8,sourceHash=7}}do
			local h=cacheFixture();h.manifest.a=bad;eq(h.cache.get('a',h.meta),nil);eq(h.cache.waiting('a'),false);eq(#h.starts,0)
		end
	end)
	test('actual mask crop placement retains source pivots independently of native atlas resolution',function()
		local src=fs.readFile('src/client/Rendering/ManEffects.luau');local a=assert(src:find('local function crop(',1,true));local z=assert(src:find('function ManEffects.attach(',a,true));local supplied
		local env=setmetatable({Bank={bindCrop=function(_,atlas,key,rect)supplied={atlas,key,rect};return true end},UDim2=rb.UDim2},{__index=getfenv()});local crop=luau.load(src:sub(a,z-1)..'\nreturn crop',{environment=env})();local image={};local rect={100,200,12,18,6,9,48};local atlas={}
		crop(image,rect,atlas,'kneel:rim:1');eq(supplied[1],atlas);eq(supplied[2],'kneel:rim:1');eq(image.Size.X.Scale,12/48);eq(image.Position.Y.Scale,9/48)
	end)
	test('failed suspended-mask publication restores both crop and visibility before releasing the replacement',function()
		local h=fixture(true);local record=h.m.track({},h.p);local backing={};local writes=0;local armed=false
		for i=1,2 do
			local state=label();backing[i]=state
			local proxy=setmetatable({},{__index=state,__newindex=function(_,key,value)
				if armed and key=='ImageContent' and type(value)=='table' then writes+=1;if writes==2 then error('destroyed label fixture')end end
				state[key]=value
			end})
			h.m.bindCrop(proxy,record,'a',{20,30,32,40,4,8,48})
		end
		h.refuse=true;h.floor=4;h:step();h:step();h.refuse=false;h:step(2);armed=true;h:finish()
		for _,l in backing do eq(l.Visible,false);eq(l.ImageContent,'empty');eq(l.ImageRectOffset,rb.Vector2.new(20,30))end
		eq(h.p.suspended,true);eq(h.warnings,1)
	end)
	 test('unconfigured static images do not hash metadata or start preload work',function()
		local c=Cache.new({},{hash=function()error('unconfigured hash')end,start=function()error('unconfigured preload')end})
		eq(c.has('absent'),false);eq(c.get('absent',{}),nil);eq(c.stats().loading,false)
	end)
	test('actual SpriteBank can cold-load static sprite sheets without native allocation or pixel decode',function()
		local meta={frame=4,width=8,height=16,columns=2,rle='pixels',strips={hull_colour=0,hull_paint=4,turret_colour=8,turret_paint=12}}
		local source={value=meta,IsA=function()return true end};local shared={Maps={MapCodec='codec'},Assets={PixelCodec='pixels'},Presentation={SpriteLod='lod',TownLods='hash'},Config={World='world'}}
		local reclaim;local clock=0
		local memory={create=function()error('unexpected native allocation')end,release=function()end,cancelUploads=function()end,register=function(_,fn)reclaim=fn end,onRelease=function()end,stats=function()return 0 end}
		local mods={memory=memory,codec={},pixels={decode=function()error('unexpected pixel decode')end},lod=Lod,hash={signature=function()return 1 end},world={STUDS_PER_CELL=4,GROUND_Y=0},static={get=function(name)if name=='OrigTank'then return{content='regular',external=true,width=8,height=16}end end,stats=function()return{}end}}
		local folder={FindFirstChild=function(_,name)return if name=='OrigTank'then source else nil end,GetChildren=function()return{}end}
		local env=setmetatable({game={GetService=function()return{WaitForChild=function()return shared end}end},script={Parent={ImageMemory='memory',StaticImages='static',Parent={FindFirstChild=function()return folder end}}},require=function(key)return if type(key)=='table'then key.value else mods[key]end,workspace={},os={clock=function()return clock end},Vector2=rb.Vector2,Content={fromObject=function()error('external image treated as editable')end},warn=function()end,print=function()end},{__index=getfenv()})
		local bank=luau.load(fs.readFile('src/client/Rendering/SpriteBank.luau'),{environment=env})();local look=bank.look('tank');eq(look.body.content,'regular');eq(look.frame,4);eq(bank.stats().bytes,0);eq(bank.stats().external,1);clock=3;reclaim(100,{});eq(bank.look('tank'),look);eq(bank.stats().external,1)
	end)
	local function adapterFixture(mode:string?):any
		local h:any={now=0,tasks={},created=0,destroyed=0,live=0,peak=0,requests=0}
		local manifest={a={id='123',width=8,height=8,sourceHash=7},b={id='456',width=8,height=8,sourceHash=7}}
		if mode=='unmapped'then manifest={}end
		local shared={Presentation={StaticAssetCache='cache',TownLods='hash'},FindFirstChild=function(_,name)
			if name=='GameData'then return{FindFirstChild=function(_,key)return if key=='StaticImageIds'then 'manifest'else nil end}end
		end}
		local provider={PreloadAsync=function(_,items,callback)
			h.requests+=1;eq(#items,1);local image=items[1]
			eq(type(image),'table');eq(image.className,'ImageLabel');eq(image.Parent,nil)
			assert(image.ImageContent:match('^content:rbxassetid://%d+$'));eq(h.live,1)
			if mode=='throw'then error('fetch fixture')end
			if mode=='empty'then return end
			callback(image.ImageContent,if mode=='failure'then 'failure'else 'success')
		end}
		local mods={cache=Cache,hash={signature=function()return 7 end},manifest=manifest}
		local env=setmetatable({game={GetService=function(_,service)
			if service=='ContentProvider'then return provider end
			eq(service,'ReplicatedStorage');return{WaitForChild=function()return shared end}
		end},require=function(key)return mods[key]end,os={clock=function()return h.now end},
			task={spawn=function(fn)table.insert(h.tasks,fn)end},Content={fromUri=function(uri)if mode=='content'then error('content fixture')end;return 'content:'..uri end},
			Enum={AssetFetchStatus={Success='success'}},Instance={new=function(className)
				eq(className,'ImageLabel');h.created+=1;h.live+=1;h.peak=math.max(h.peak,h.live)
				return{className=className,Destroy=function()h.destroyed+=1;h.live-=1 end}
			end}},{__index=getfenv()})
		h.cache=luau.load(fs.readFile('src/client/Rendering/StaticImages.luau'),{environment=env})();h.meta={width=8,height=8,rle='pixels'}
		function h:finish()local job=table.remove(self.tasks,1);assert(job);job()end
		return h
	end
	test('actual static preload adapter uses one typed unparented image and releases it before publishing',function()
		local h=adapterFixture();eq(h.cache.get('a',h.meta),nil);eq(h.cache.get('b',h.meta),nil);eq(#h.tasks,1);eq(h.created,0)
		h:finish();eq(h.cache.get('a',h.meta).content,'content:rbxassetid://123');eq(h.live,0);eq(h.destroyed,1)
		h.cache.get('b',h.meta);h:finish();eq(h.cache.get('b',h.meta).content,'content:rbxassetid://456');eq(h.peak,1);eq(h.created,2);eq(h.destroyed,2)
		for _=1,100 do h.cache.get('a',h.meta)end;eq(h.created,2);eq(h.cache.stats().ready,2)
	end)
	test('typed preload failures and absent success callbacks release their label and retain cooldown fallback',function()
		for _,mode in {'throw','failure','empty'}do
			local h=adapterFixture(mode);h.cache.get('a',h.meta);h:finish();eq(h.live,0);eq(h.destroyed,1);eq(h.cache.stats().ready,0);eq(h.cache.stats().failures,1);eq(h.cache.waiting('a'),false)
			for _=1,100 do eq(h.cache.get('a',h.meta),nil)end;eq(#h.tasks,0);eq(h.created,1)
			h.now=61;h.cache.get('a',h.meta);eq(#h.tasks,1)
		end
	end)
	test('Content conversion failure cleans the temporary label without starting a preload',function()
		local h=adapterFixture('content');h.cache.get('a',h.meta);h:finish();eq(h.created,1);eq(h.destroyed,1);eq(h.requests,0);eq(h.live,0);eq(h.cache.stats().failures,1)
	end)
	test('actual static adapter with no imported mapping creates no preload labels or requests',function()
		local h=adapterFixture('unmapped');eq(h.cache.has('a'),false);eq(h.cache.get('a',h.meta),nil);eq(#h.tasks,0);eq(h.created,0);eq(h.requests,0)
	end)
end
