--!strict
return function(test: any, eq: any)
	local Budget = require("../src/shared/Presentation/ImageBudget")
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
	test("reclamation visits detail before unused sprites and passes active-image protection", function()
		local create = factory(1000)
		local b = Budget.new(create, { ceiling = 100, detailLimit = 100, reserve = 0 })
		local protected = {}; local called = {}
		b.guard = function() return protected end
		b:register(20, function(_, guard) table.insert(called, "sprites"); eq(guard, protected) end)
		b:register(10, function() table.insert(called, "town") end)
		b:reclaim(1)
		eq(called[1], "town"); eq(called[2], "sprites")
	end)
	test("image release is idempotent and notifies failed-cache retry listeners", function()
		local create, state = factory(100)
		local b = Budget.new(create)
		local released = 0; b:onRelease(function() released += 1 end)
		local image = b:create(2, 2)
		b:release(image); b:release(image)
		eq(state.destroyed, 1); eq(released, 1); eq(b.epoch, 1); eq(b.used, 0)
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
		b:register(10, function() townEvicted = true end)
		b:register(20, function() b:release(unused) end)
		assert(b:prepareDetail(24))
		eq(townEvicted, false); eq(state.attempts, 2)
		assert(b:create(2, 3, "detail"))
		eq(state.attempts, 3); eq(b.used, 64)
	end)
end
