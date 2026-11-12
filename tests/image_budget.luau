--!strict
return function(test: any, eq: any)
	local Budget = require("../src/shared/Presentation/ImageBudget")
	test("aggregate LOD headroom respects core reserve detail limits and learned native refusal without probing",function()
		local attempts=0;local b=Budget.new(function() attempts+=1;return {Destroy=function() end} end,{ceiling=100,detailLimit=60,reserve=20})
		eq(b:detailHeadroom(),60);b.used=50;b.detail=20;eq(b:detailHeadroom(),30)
		b.knownCeiling=60;eq(b:detailHeadroom(),0);b.knownCeiling=nil;b.detail=60;eq(b:detailHeadroom(),0)
		b.used=90;b.detail=50;eq(b:detailHeadroom(),0);eq(b:detailHeadroom(50),40,"replacement must restore core reserve even if current allocations exceed it")
		eq(attempts,0)
	end)
	local function factory(limit: number)
		local state: any = { used = 0, attempts = 0, destroyed = 0 }
		local function create(w: number, h: number)
			state.attempts += 1
			local bytes = w * h * 4
			if state.used + bytes > limit then return nil end
			state.used += bytes
			local image: any = {}
			function image:Destroy() state.used -= bytes; state.destroyed += 1 end
			return image
		end
		return create, state
	end
	test("image detail respects core headroom without calling the native allocator", function()
		local create, state = factory(100)
		local b = Budget.new(create, { ceiling = 100, detailLimit = 100, reserve = 40 })
		assert(b:create(3, 5, "detail")) -- 60 bytes
		eq(b:create(1, 1, "detail"), nil)
		eq(state.attempts, 1)
	end)
	test("core images reclaim map detail before allocation when soft capacity is reached", function()
		local create, state = factory(100)
		local b = Budget.new(create, { ceiling = 100, detailLimit = 100, reserve = 0 })
		local detail = b:create(4, 5, "detail") -- 80 bytes
		b:register(10, function() b:release(detail) end)
		assert(b:create(3, 5, "core")) -- 60 bytes
		eq(state.attempts, 2); eq(state.destroyed, 1); eq(b.used, 60); eq(b.detail, 0)
	end)
	test("native refusal frees detail and retries core once after actual reclamation", function()
		local create, state = factory(100)
		local b = Budget.new(create, { ceiling = 1000, detailLimit = 1000, reserve = 0 })
		local detail = b:create(4, 5, "detail")
		b:register(10, function() b:release(detail) end)
		assert(b:create(3, 5, "core"))
		eq(state.attempts, 3); eq(b.used, 60); eq(b.knownCeiling, 80)
	end)
	test("learned capacity stops repeated failed detail probes", function()
		local create, state = factory(80)
		local b = Budget.new(create, { ceiling = 1000, detailLimit = 1000, reserve = 0 })
		assert(b:create(4, 5, "core"))
		eq(b:create(1, 1, "detail"), nil)
		for _ = 1, 100 do eq(b:create(1, 1, "detail"), nil) end
		eq(state.attempts, 2)
	end)
	test("reclamation visits optional detail then unused sprites before terrain and passes active-image protection", function()
		local create = factory(1000)
		local b = Budget.new(create, { ceiling = 100, detailLimit = 100, reserve = 0 })
		local protected = {}; local called = {}
		b.guard = function() return protected end
		b:register(20, function(_, guard) table.insert(called, "sprites"); eq(guard, protected) end)
		b:register(30, function() table.insert(called, "town") end)
		b:register(10, function() table.insert(called, "effects") end)
		b:reclaim(1)
		eq(called[1], "effects"); eq(called[2], "sprites");eq(called[3],"town")
	end)
	test("image release is idempotent and notifies failed-cache retry listeners", function()
		local create, state = factory(100)
		local b = Budget.new(create)
		local released = 0; b:onRelease(function() released += 1 end)
		local image = b:create(2, 2)
		b:release(image); b:release(image)
		eq(state.destroyed, 1); eq(released, 1); eq(b.epoch, 1); eq(b.used, 0)
	end)
	test("terrain recovery clears idle detail without wasting core art when only the detail pool is full",function()
		local create,state=factory(1000);local b=Budget.new(create,{ceiling=1000,detailLimit=100,reserve=0})
		local terrain=b:create(2,5,"terrain");local idleDetail=b:create(2,5,"detail");local idleCore=b:create(4,5)
		local filtered=false
		b:register(10,function() error("visible effects must not be reclaimed here") end)
		b:register(30,function() b:release(terrain) end)
		b:register(20,function(_,_,detailOnly) filtered=detailOnly;b:release(idleDetail) end)
		eq(b:recoverTerrain(80,40),100);eq(filtered,true);assert(b.records[terrain]);assert(b.records[idleCore]);eq(state.attempts,3)
	end)
	test("terrain recovery can clear idle core art when global capacity is the remaining constraint",function()
		local create,state=factory(1000);local b=Budget.new(create,{ceiling=200,detailLimit=100,reserve=20})
		local terrain=b:create(2,5,"terrain");local live=b:create(4,5);local idle=b:create(2,5)
		local protected={[live]=true};b.guard=function() return protected end
		b:register(20,function(_,guard,detailOnly) eq(guard,protected);eq(detailOnly,nil);b:release(idle) end)
		eq(b:recoverTerrain(80,40),100);assert(b.records[live]);assert(b.records[terrain]);eq(state.attempts,3)
	end)
	test("terrain recovery stops after its bounded release pass and skips impossible plans or invalid guards",function()
		local create,state=factory(1000);local b=Budget.new(create,{ceiling=1000,detailLimit=100,reserve=0,recoveryLimit=16})
		local terrain=b:create(2,5,"terrain");local idle={b:create(1,5,"detail"),b:create(1,5,"detail"),b:create(1,5,"detail")}
		for _,image in idle do b:register(20,function() b:release(image) end) end
		eq(b:recoverTerrain(100,40),60);eq(state.destroyed,1,"one indivisible image may exceed the byte target")
		b.guard=function() error("no valid visible-image guard") end
		eq(b:recoverTerrain(100,40),60);eq(b:recoverTerrain(101,40),60);eq(state.destroyed,1);eq(state.attempts,4);assert(b.records[terrain])
	end)
	test("actual sprite cache recovery retains active wreck art and frees it only after it becomes idle",function()
		local fs=require("@lune/fs");local luau=require("@lune/luau");local now=0
		local create,state=factory(1000)
		local b=Budget.new(function(w,h) local image=create(w,h);image.WritePixelsBuffer=function() end;return image end,{ceiling=1000,detailLimit=100,reserve=0})
		local terrain=b:create(2,5,"terrain")
		local function module(meta) return {meta=meta,IsA=function() return true end} end
		local assets={OrigTank=module({width=1,height=7,frame=1,columns=1,rle="",strips={hull_colour=0,hull_paint=0,turret_colour=0,turret_paint=0}}),
			OrigTankWreck=module({width=3,height=4,frame=1,columns=1,rle="",strips={wreck_hull_colour=0,wreck_hull_paint=0,wreck_turret_colour=0,wreck_turret_paint=0}})}
		local memory={create=function(size,kind) return b:create(size.X,size.Y,kind) end,release=function(image) b:release(image) end,
			register=function(priority,fn) return b:register(priority,fn) end,onRelease=function(fn) b:onRelease(fn) end,stats=function() return b.used end}
		local modules={memory=memory,codec={base64Decode=function() return buffer.create(0) end},pixels={decode=function(_data,w,h) return buffer.create(w*h*4) end}}
		local shared={Maps={MapCodec="codec"},Assets={PixelCodec="pixels"}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",Parent={FindFirstChild=function() return {FindFirstChild=function(_,name) return assets[name] end} end}}},
			require=function(key) return if type(key)=="table" then key.meta else modules[key] end,
			Content={fromObject=function(image) return image end},Vector2={new=function(x,y) return {X=x,Y=y} end},os={clock=function() return now end},warn=function() end},{__index=getfenv()})
		local bank=luau.load(fs.readFile("src/client/Rendering/SpriteBank.luau"),{environment=env})()
		local live=bank.look("tank").body.content;local soot=bank.soot("tank").content
		local protected={[live]=true,[soot]=true};b.guard=function() return protected end
		now=2;eq(b:recoverTerrain(92,40),52);assert(b.records[soot])
		protected[soot]=nil;eq(b:recoverTerrain(92,40),100);eq(b.records[soot],nil);assert(b.records[live]);assert(b.records[terrain]);eq(state.attempts,3)
	end)
	test("battle detail cannot spend the reserved terrain floor before the map arrives",function()
		local create,state=factory(100)
		local b=Budget.new(create,{ceiling=100,detailLimit=80,reserve=0,terrainReserve=32})
		local battle=b:create(4,3,"detail");assert(battle);eq(b:detailHeadroom(),0);eq(b:detailHeadroom(nil,"terrain"),32)
		eq(b:create(1,1,"detail"),nil);eq(state.attempts,1)
		local terrain=b:create(4,2,"terrain");assert(terrain);eq(b.terrain,32);eq(b.detail,80)
		b:release(battle);eq(b.detail,32);eq(b.terrain,32);assert(b:create(4,3,"detail"))
		b:release(terrain);eq(b.terrain,0);eq(b.detail,48);eq(b:create(1,1,"detail"),nil)
	end)
	test("a new unit image frees idle art before removing visible terrain",function()
		local create,state=factory(100)
		local b=Budget.new(create,{ceiling=100,detailLimit=80,reserve=0,terrainReserve=20})
		local terrain=b:create(3,5,"terrain");local idle=b:create(2,4,"core");local townEvicted=false
		b:register(30,function() townEvicted=true;b:release(terrain) end)
		b:register(20,function() b:release(idle) end)
		assert(b:create(2,5,"core"));eq(townEvicted,false);eq(b.terrain,60);eq(b.used,100);eq(state.destroyed,1)
	end)
	test("a refused battle image never reclaims the map or retries the native allocator immediately",function()
		local create,state=factory(80)
		local b=Budget.new(create,{ceiling=1000,detailLimit=1000,reserve=0,terrainReserve=20})
		local terrain=b:create(3,5,"terrain");local townEvicted=false
		b:register(30,function() townEvicted=true;b:release(terrain) end)
		eq(b:create(2,5,"detail"),nil);eq(townEvicted,false);eq(state.attempts,2);eq(b.terrain,60)
		for _=1,20 do eq(b:create(2,5,"detail"),nil) end;eq(state.attempts,2)
	end)
	test("terrain admission never invokes the last-resort visible-map reclaimer",function()
		local create,state=factory(100)
		local b=Budget.new(create,{ceiling=100,detailLimit=100,reserve=20,terrainReserve=20})
		local terrain=b:create(3,5,"terrain");assert(b:create(1,5,"core"));local called=false
		b:register(30,function() called=true;b:release(terrain) end)
		eq(b:prepareDetail(24,"terrain"),false);eq(called,false);eq(state.attempts,2);eq(b.terrain,60)
	end)
	test("actual damaged-unit atlas admission keeps the live unit and terrain when its wreck sheet cannot fit",function()
		local fs=require("@lune/fs");local luau=require("@lune/luau")
		local create,state=factory(100)
		local b=Budget.new(function(w,h) local image=create(w,h);if image then image.WritePixelsBuffer=function() end end;return image end,
			{ceiling=100,detailLimit=60,reserve=0,terrainReserve=24})
		local terrain=b:create(2,5,"terrain");local evicted=false;b:register(30,function() evicted=true;b:release(terrain) end)
		local function module(meta) return {meta=meta,IsA=function() return true end} end
		local assets={OrigTank=module({width=1,height=7,frame=1,columns=1,rle="",strips={hull_colour=0,hull_paint=0,turret_colour=0,turret_paint=0}}),
			OrigTankWreck=module({width=3,height=4,frame=1,columns=1,rle="",strips={wreck_hull_colour=0,wreck_hull_paint=0,wreck_turret_colour=0,wreck_turret_paint=0}})}
		local memory={create=function(size,kind) return b:create(size.X,size.Y,kind) end,release=function(image) b:release(image) end,
			register=function(priority,fn) return b:register(priority,fn) end,onRelease=function(fn) b:onRelease(fn) end,stats=function() return b.used end}
		local decodes=0
		local modules={memory=memory,codec={base64Decode=function() return buffer.create(0) end},pixels={decode=function(_data,w,h) decodes+=1;return buffer.create(w*h*4) end}}
		local shared={Maps={MapCodec="codec"},Assets={PixelCodec="pixels"}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return shared end} end},
			script={Parent={ImageMemory="memory",Parent={FindFirstChild=function() return {FindFirstChild=function(_,name) return assets[name] end} end}}},
			require=function(key) return if type(key)=="table" then key.meta else modules[key] end,
			Content={fromObject=function(image) return image end},Vector2={new=function(x,y) return {X=x,Y=y} end},warn=function() end},{__index=getfenv()})
		local bank=luau.load(fs.readFile("src/client/Rendering/SpriteBank.luau"),{environment=env})()
		local live=bank.look("tank");assert(live);local image=live.body.content
		b.guard=function() return {[image]=true} end
		eq(bank.soot("tank"),nil);eq(evicted,false);eq(b.terrain,40);eq(b.used,68);eq(state.attempts,2)
		eq(decodes,1,"refused wreck art must not decode an unused full pixel buffer")
		eq(bank.look("tank").body.content,image);eq(b.records[image].kind,"core")
	end)
	test("releasing core storage lets detail use learned free capacity again", function()
		local create = factory(100)
		local b = Budget.new(create, { ceiling = 1000, detailLimit = 1000, reserve = 0 })
		local core = b:create(4, 5)
		eq(b:create(2, 3, "detail"), nil)
		b:release(core)
		assert(b:create(2, 3, "detail"))
	end)
	test("thrown allocations never enter image accounting or cause a pointless retry", function()
		local attempts = 0
		local b = Budget.new(function() attempts += 1; error("refused") end)
		eq(b:create(2, 2), nil); eq(b.used, 0); eq(attempts, 1)
		eq(b:create(2, 2), nil); eq(attempts, 1)
	end)
	test("map downsampling preserves transparent-edge color without a dark fringe", function()
		local Pixels = require("../src/shared/Presentation/ImagePixels")
		local source = buffer.create(16)
		buffer.writeu32(source, 0, 0xff0000ff) -- one opaque red pixel, three transparent black
		local out, w, h = Pixels.half(source, 2, 2)
		eq(w, 1); eq(h, 1); eq(buffer.readu8(out, 0), 255); eq(buffer.readu8(out, 3), 64)
	end)
	test("map downsampling handles odd dimensions and opaque pixels", function()
		local Pixels = require("../src/shared/Presentation/ImagePixels")
		local source = buffer.create(3 * 3 * 4)
		for i = 0, 8 do buffer.writeu32(source, i * 4, 0xff332211) end
		local out, w, h = Pixels.half(source, 3, 3)
		eq(w, 2); eq(h, 2)
		for i = 0, 3 do eq(buffer.readu32(out, i * 4), 0xff332211) end
	end)
	test("destroyed map sessions can unregister their reclamation callbacks", function()
		local create = factory(100)
		local b = Budget.new(create)
		local called = false
		local disconnect = b:register(10, function() called = true end)
		disconnect(); b:reclaim(1); eq(called, false)
	end)
	test("town detail upgrades reclaim unused art without evicting another town or allocating early", function()
		local create, state = factory(100)
		local b = Budget.new(create, { ceiling = 100, detailLimit = 100, reserve = 20 })
		assert(b:create(2, 5)) -- active art: 40 bytes
		local unused = b:create(2, 5)
		local townEvicted = false
		b:register(30, function() townEvicted = true end)
		b:register(20, function() b:release(unused) end)
		assert(b:prepareDetail(24))
		eq(townEvicted, false); eq(state.attempts, 2)
		assert(b:create(2, 3, "detail"))
		eq(state.attempts, 3); eq(b.used, 64)
	end)
end
