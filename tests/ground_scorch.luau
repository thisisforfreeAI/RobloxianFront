--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");if not fs.isFile("src/shared/GameData/GroundScorchVectors.luau") then return end
	local Scorch=require("../src/shared/Simulation/GroundScorch")
	local World=require("../src/shared/Simulation/GroundScorchWorld")
	local Packets=require("../src/shared/Protocol/GroundScorchPackets")
	local View=require("../src/shared/Presentation/GroundScorchView")
	local config=require("../src/shared/GameData/GroundScorchRules") ::any
	local refs=require("../src/shared/GameData/GroundScorchVectors") ::any
	local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
	test("burn scar footprint, overlaps, fade and town recovery match original source scenes",function()
		for _,scene in refs.scenes do
			local quiet=false;local model=Scorch.new(config,refs.width,refs.height,{wind=function() return scene.wind end,townAt=function() return true end,quiet=function() return quiet end})
			for _,p in scene.impulses do model.scar(p[1],p[2],p[3],p[4],"burn") end
			for _,state in scene.states do
				if string.sub(state.label,1,5)=="fade:" then model.fade(tonumber(string.sub(state.label,6)))
				elseif state.label=="busy town" then model.heal(60)
				elseif state.label=="quiet town" then quiet=true;model.heal(60)
				elseif state.label=="restored town" then model.heal(300) end
				local seen={}
				for _,row in state.rows do seen[row[1]]=true;close(buffer.readf32(model.amount,row[1]*4),row[2]);close(buffer.readf32(model.settle,row[1]*4),row[3]);eq(row[4],config.tone) end
				for cell=0,refs.width*refs.height-1 do if not seen[cell] then eq(buffer.readf32(model.amount,cell*4),0) end end
			end
		end
	end)
	test("ground scar town catchment matches original normalized-distance cells",function()
		local townAt=Scorch.towns(config.towns,refs.width,refs.height,refs.towns)
		for cell,id in refs.townCells do eq(townAt(cell-1),if id>0 then refs.towns[id] else nil) end
	end)
	test("rural fire stains settle without inventing automatic ground restoration",function()
		local model=Scorch.new(config,20,16,{townAt=function() return nil end})
		model.scar(10.5,8.5,2,.9,"burn");model.fade(1000);model.heal(1000)
		assert(next(model.cells));for cell in model.cells do eq(buffer.readf32(model.amount,cell*4),buffer.readf32(model.settle,cell*4));assert(buffer.readf32(model.amount,cell*4)>0) end
		model.reset();eq(next(model.cells),nil);eq(next(model.healing),nil)
	end)
	test("scorch transport validates bounds, quantization and packet sizes",function()
		local encoded=Packets.encode({{0,1},{19,255},{20,0}});local rows=Packets.decode(encoded,100);eq(#rows,3);eq(rows[2][2],255)
		for _,fn in {function() Packets.decode(buffer.create(4),100) end,function() Packets.decode(Packets.encode({{100,1}}),100) end,
			function() Packets.encode({{-1,1}}) end,function() Packets.encode({{0,256}}) end,function() Packets.decode(buffer.create((Packets.LIMIT+1)*5),100) end} do assert(not pcall(fn)) end
	end)
	test("ground scorch sends visible deltas, withholds hidden restoration and resends for a new viewer",function()
		local time=0;local town={x=10,y=8,radius=20,lastHitAt=-100}
		local world=World.new(config,{width=20,height=16},{time=function() return time end,towns={town},quietSec=30})
		world.scar(10.5,8.5,2,.9,"burn");local p,cache=world.view(nil,function() return false end);eq(buffer.len(p.rows),0);eq(p.reset,true)
		p,cache=world.view(cache,function() return true end);assert(buffer.len(p.rows)>0)
		local client=View.new(20,16,config);client.apply(p);assert(next(client.buckets))
		time=400;world.advance(time);local hidden,nextCache=world.view(cache,function() return false end);eq(buffer.len(hidden.rows),0)
		p,cache=world.view(nextCache,function() return true end);assert(buffer.len(p.rows)>0)
		for _,row in Packets.decode(p.rows,320) do eq(row[2],0) end
		client.apply(p);eq(next(client.buckets),nil)
		world.scar(10.5,8.5,1,.9,"burn");local late=world.view(nil,function() return true end);eq(late.reset,true);assert(buffer.len(late.rows)>0)
	end)
	test("bounded scorch packets retry unsent cells and epochs clear cached stains",function()
		local world=World.new(config,{width=64,height=64},{time=function() return 0 end})
		for cell=0,2099 do world.model.cells[cell]=true;buffer.writef32(world.model.amount,cell*4,.5) end
		local cache=nil;local total=0;local client=View.new(64,64,config)
		for _=1,3 do local p;p,cache=world.view(cache,function() return true end);total+=buffer.len(p.rows)/5;assert(buffer.len(p.rows)<=5120);client.apply(p) end;eq(total,2100)
		local stale=world.view(nil,function() return true end);world.reset();local p=world.view(cache,function() return true end);client.apply(p);eq(next(client.buckets),nil)
		eq(client.apply(stale),false);eq(next(client.buckets),nil)
	end)
	test("fixed scorch clock respects pause, town quiet time and monotonic time",function()
		local time=0;local town={x=10,y=8,radius=20,lastHitAt=0}
		local world=World.new(config,{width=20,height=16},{time=function() return time end,towns={town},quietSec=30})
		world.scar(10.5,8.5,1,.9,"burn");local before=buffer.tostring(world.model.amount)
		world.advance(0);eq(buffer.tostring(world.model.amount),before);world.advance(.5);eq(buffer.tostring(world.model.amount),before)
		world.advance(2);assert(buffer.tostring(world.model.amount)~=before);local cell=8*20+10;local stain=buffer.readf32(world.model.settle,cell*4)
		world.advance(20);eq(buffer.readf32(world.model.settle,cell*4),stain);world.advance(40);assert(buffer.readf32(world.model.settle,cell*4)<stain)
		assert(not pcall(function() world.advance(39) end))
	end)
	test("ground tint uses source color/darken and world cell coordinates without touching hidden cells",function()
		local view=View.new(40,40,config);view.apply({epoch=1,rows=Packets.encode({{33*40+33,255},{33*40+34,128}})})
		local b=view.buckets["1:1"];eq(b.cw,8);eq(b.ch,8)
		local px,n=view.pixels(b,function(x) return x<34 end);eq(n,1)
		eq(buffer.readu8(px,(1*8+1)*4+3),math.floor(config.darken*255+.5));eq(buffer.readu32(px,(1*8+2)*4),0)
		local before=b;assert(not pcall(function() view.apply({epoch=2,rows=buffer.create(1)}) end));eq(view.buckets["1:1"],before)
	end)
end
