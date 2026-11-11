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
	test("mixed crater rubble and burn overlap match original cell strengths settlement and tone",function()
		assert(refs.impacts and #refs.impacts==18,"regenerate GroundScorchVectors")
		for _,scene in refs.impacts do
			local model=Scorch.new(config,refs.width,refs.height,{})
			local impulse=0
			for _,state in scene.states do
				if state.label=="impulse" then impulse+=1;model.scar(table.unpack(scene.impulses[impulse])) else model.fade(tonumber(string.sub(state.label,6))) end
				local seen={}
				for _,row in state.rows do
					seen[row[1]]=true;close(buffer.readf32(model.amount,row[1]*4),row[2]);close(buffer.readf32(model.settle,row[1]*4),row[3]);eq(buffer.readu8(model.tone,row[1]),row[4])
				end
				for cell=0,refs.width*refs.height-1 do if not seen[cell] then eq(buffer.readf32(model.amount,cell*4),0) end end
			end
		end
	end)
	test("tone-only changes obey fog deltas and restoration carries a clean tone",function()
		local world=World.new(config,{width=4,height=4},{time=function() return 0 end})
		world.scar(1.5,1.5,0,.7,"burn");local packet,known=world.view(nil,function() return true end)
		local view=View.new(4,4,config);view.apply(packet);local amount=buffer.readf32(world.model.amount,5*4)
		buffer.writeu8(world.model.tone,5,config.tones.earth)
		local hidden,hiddenKnown=world.view(known,function() return false end);eq(buffer.len(hidden.rows),0)
		local changed;changed,known=world.view(hiddenKnown,function() return true end)
		local rows=Packets.decode(changed.rows,16,changed.tones);eq(#rows,1);eq(rows[1][1],5);eq(rows[1][3],config.tones.earth)
		eq(buffer.readf32(world.model.amount,5*4),amount);view.apply(changed);eq(view.buckets["0:0"].tones[5],config.tones.earth)
		world.model.reset();local reset=world.view(known,function() return true end);view.apply(reset);eq(next(view.buckets),nil)
		for _,row in Packets.decode(reset.rows,16,reset.tones) do eq(row[2],0);eq(row[3],0) end
	end)
	test("tone transport rejects malformed lengths and palettes before mutating the live view",function()
		local rows={{5,200,config.tones.ash}};local bytes=Packets.encode(rows);local tones=Packets.tones(rows)
		local view=View.new(4,4,config);view.apply({epoch=1,rows=bytes,tones=tones});local prior=view.buckets["0:0"]
		for _,bad in {buffer.create(0),buffer.create(2),"invalid"} do
			assert(not pcall(function() view.apply({epoch=2,reset=true,rows=bytes,tones=bad}) end));eq(view.epoch,1);eq(view.buckets["0:0"],prior)
		end
		buffer.writeu8(tones,0,255);assert(not pcall(function() view.apply({epoch=2,reset=true,rows=bytes,tones=tones}) end));eq(view.buckets["0:0"],prior)
		for _,tone in {-1,256,.5,math.huge} do assert(not pcall(Packets.tones,{{0,200,tone}})) end
		local legacy=View.new(4,4,{color=config.color,darken=config.darken});legacy.apply({epoch=1,rows=bytes});eq(legacy.buckets["0:0"].tones[5],0)
	end)
	test("impact scars use source weapon presets and legacy profiles retain their burn layer",function()
		local world=World.new(config,{width=20,height=16},{time=function() return 0 end})
		for weapon,profile in config.impacts.weapons do
			world.reset();local expected=Scorch.new(config,20,16,{})
			if profile.power>0 then expected.scar(10.5,8.5,profile.radius,profile.power,profile.kind) end
			eq(world.blast(10.5,8.5,weapon),profile.power>0);eq(buffer.tostring(world.model.amount),buffer.tostring(expected.amount));eq(buffer.tostring(world.model.tone),buffer.tostring(expected.tone))
		end
		world.reset();assert(world.blast(10.5,8.5,"missile",9,"demo"));local demo=buffer.tostring(world.model.amount)
		world.reset();world.blast(10.5,8.5,"missile");assert(buffer.tostring(world.model.amount)~=demo)
		for _,args in {{-1,0,"shell"},{math.huge,0,"shell"},{0/0,0,"shell"},{1,1,"missing"},{1,1,"razed"},{1,1,"razed",-1}} do eq(world.blast(table.unpack(args)),false) end
		local legacy=table.clone(config);legacy.palette=nil;legacy.shapes=nil;legacy.impacts=nil
		local old=World.new(legacy,{width=20,height=16},{time=function() return 0 end});eq(old.blast(10,8,"shell"),false);old.scar(10,8,1,.5,"burn");assert(next(old.model.cells))
	end)
	test("actual match impact callback feeds guarded shell demo rubble and delayed-pop ground marks",function()
		local luau=require("@lune/luau");local code=fs.readFile("src/server/Match/MatchService.luau")
		local a=assert(string.find(code,"sim.fireImpacts=WorldFireImpacts.new",1,true));a=assert(string.find(code,"emit=function",a,true))+#"emit="
		local b=assert(string.find(code,"\n\t\t\tend,",a,true))+#"\n\t\t\tend"
		local factory=luau.load("return function(sim) return "..string.sub(code,a,b-1).." end")()
		local fire=require("../src/shared/GameData/FireImpactRules");local Impacts=require("../src/shared/Simulation/WorldFireImpacts")
		local world=World.new(config,{width=20,height=16},{time=function() return 0 end});local marks={};local scar=world.scar
		world.scar=function(...) table.insert(marks,{...});scar(...) end
		local house,forest=0,0;local emit=factory({groundScorch=world,houseFires={blast=function() house+=1 end},forestFires={blast=function() forest+=1 end}})
		local wet=false;local adapter=Impacts.new(fire,20,16,{time=function() return 0 end,random=function() return .5 end,water=function() return wet end,emit=emit})
		adapter.fire(10,8,"shell");eq(#marks,1);eq(marks[1][3],config.impacts.weapons.shell.radius);eq(marks[1][5],"crater");eq(house,1);eq(forest,1)
		adapter.event({type="demoBlast",x=10,y=8});eq(#marks,2);eq(marks[2][3],config.impacts.demo.radius);eq(marks[2][4],config.impacts.demo.power)
		adapter.event({type="destroyed",cat="structure",kind="hq",x=10,y=8});eq(#marks,3);eq(marks[3][3],fire.razedSize*fire.hqScale);eq(marks[3][5],"rubble")
		adapter.advance(fire.pops.to+1);eq(#marks,3+fire.pops.count)
		for i=4,#marks do eq(marks[i][3],config.impacts.weapons[fire.pops.weapon].radius) end
		local count=#marks;wet=true;adapter.fire(10,8,"shell");adapter.event({type="destroyed",cat="structure",kind="factory",x=10,y=8});eq(#marks,count)
		wet=false;adapter.event({type="demolished",cat="structure",kind="factory",x=10,y=8});eq(#marks,count)
		adapter.fire(10,8,"bullets");eq(#marks,count)
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
