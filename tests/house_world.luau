--!strict
return function(test:any,eq:any)
	if not require("@lune/fs").isFile("src/shared/GameData/FireRules.luau") then return end
	local Packets=require("../src/shared/Protocol/FirePackets")
	local World=require("../src/shared/Simulation/HouseWorld")
	local View=require("../src/shared/Presentation/HouseFireView")
	local settings=require("../src/shared/GameData/FireRules") ::any
	local refs=require("../src/shared/GameData/HouseFireVectors") ::any
	local function make():any
		local h:any={time=0,weather="clear"};local pw=refs.width*settings.tileSize
		h.world=World.new(settings,{width=refs.width,height=refs.height,tileSize=settings.tileSize,
			roof=function(x,y) return refs.roof[y*pw+x+1]==1 end,builtAt=function() return true end,townIndex=function() return nil end},
			{time=function() return h.time end,weather=function() return h.weather end,random=require("../src/shared/Utilities/Rng").new(912),towns={}})
		return h
	end
	local function visible() return true end
	test("fire packets bound pixel/roof buffers and reject malformed lengths, stages and coordinates",function()
		local rows={{0,0},{27,1},{88,3}};local out=Packets.readPixels(Packets.pixels(rows),100)
		for i,r in rows do eq(out[i][1],r[1]);eq(out[i][2],r[2]) end
		eq(pcall(Packets.readPixels,buffer.create(4),100),false)
		eq(pcall(Packets.readPixels,Packets.pixels({{100,1}}),100),false)
		eq(pcall(Packets.readPixels,Packets.pixels({{1,4}}),100),false)
		eq(pcall(Packets.readPixels,buffer.create((Packets.PIXELS_PER_PACKET+1)*5),100),false)
		local points=Packets.readPoints(Packets.points({0,99}),100,2);eq(points[2],99)
		eq(pcall(Packets.readPoints,Packets.points({0,99}),100,1),false)
		eq(pcall(Packets.readPoints,buffer.create(0),100,2),false)
		eq(pcall(Packets.readPoints,Packets.points({100}),100,2),false)
	end)
	test("authoritative house clock uses fixed source ticks, pauses and rain burnout rates",function()
		local h=make();assert(h.world.model.ignite(7,7));local actor=h.world.model.houses[1]
		h.world.advance(.1);eq(actor.age,0);h.world.advance(.25);eq(actor.age,.25);h.world.advance(.25);eq(actor.age,.25)
		h.weather="storm";h.world.advance(.5);eq(actor.age,.25+.25*settings.houses.rain.hurry)
		eq(actor.ageRate,settings.houses.rain.hurry);eq(h.world.sampleTime,.5)
		eq(pcall(h.world.advance,.4),false)
	end)
	test("fire view sends only visible actor births and char deltas, including later restorations",function()
		local h=make();assert(h.world.model.ignite(7,7));local a=h.world.model.houses[1];local p=a.px[1]
		h.world.paint[p]=1
		local packet,cache=h.world.view(nil,function() return false end);eq(#packet.actors,0);eq(buffer.len(packet.pixels),0)
		packet,cache=h.world.view(cache,visible);eq(#packet.actors,1);assert(packet.actors[1].points);eq(buffer.len(packet.pixels),5)
		packet,cache=h.world.view(cache,visible);eq(packet.actors[1].points,nil);eq(buffer.len(packet.pixels),0)
		h.world.paint[p]=3
		packet,cache=h.world.view(cache,function() return false end);eq(#packet.actors,0);eq(buffer.len(packet.pixels),0);eq(cache.known[p],1)
		packet,cache=h.world.view(cache,visible);assert(packet.actors[1].points);eq(Packets.readPixels(packet.pixels,1e9)[1][2],3)
		h.world.paint[p]=nil
		packet,cache=h.world.view(cache,function() return false end);eq(buffer.len(packet.pixels),0)
		packet,cache=h.world.view(cache,visible);eq(Packets.readPixels(packet.pixels,1e9)[1][2],0);eq(cache.known[p],nil)
	end)
	test("bounded fire updates retry unsent pixels and newly visible roofs rather than losing them",function()
		local h=make();for p=0,Packets.PIXELS_PER_PACKET+3 do h.world.paint[p]=2 end
		local packet,cache=h.world.view(nil,visible);eq(buffer.len(packet.pixels),Packets.PIXELS_PER_PACKET*5)
		packet,cache=h.world.view(cache,visible);eq(buffer.len(packet.pixels),4*5)
		packet=h.world.view(cache,visible);eq(buffer.len(packet.pixels),0)
		local px=table.create(settings.houses.house.maxPx,1)
		for i=1,settings.houses.cap.hard do table.insert(h.world.model.houses,{id=i,x=1,y=1,px=px,cell=0,r=1,age=0,life=50}) end
		packet,cache=h.world.view(nil,visible);local first=#packet.actors;assert(first>0 and first<settings.houses.cap.hard)
		packet,cache=h.world.view(cache,visible);assert(#packet.actors>first)
		local bytes=0;for _,row in packet.actors do if row.points then bytes+=buffer.len(row.points) end end;assert(bytes<=Packets.ROOF_BYTES_PER_PACKET)
	end)
	test("fire reset clears damage and forces a fresh epoch while actor ids remain monotonic",function()
		local h=make();assert(h.world.model.ignite(7,7));local id=h.world.model.houses[1].id;h.world.paint[1]=3
		local _,cache=h.world.view(nil,visible);h.world.reset()
		local packet,nextCache=h.world.view(cache,visible);eq(packet.reset,true);eq(next(nextCache.known),nil);eq(#packet.actors,0)
		assert(h.world.model.ignite(7,7));assert(h.world.model.houses[1].id>id)
	end)
	test("client fire views preserve phase, reject stale epochs, stop expired actors and never mutate packets",function()
		local clears,painted=0,{}
		local v=View.new(10,10,14,300,{random=function() return .4 end,clear=function() clears+=1 end,pixels=function(rows) painted=rows end})
		local row={id=1,x=1,y=1,cell=11,r=.2,age=1,life=10,rate=2,points=Packets.points({141,142})}
		local packet={epoch=1,reset=true,time=5,actors={row},pixels=Packets.pixels({{141,1}})}
		assert(v.apply(packet));eq(clears,1);eq(painted[1][2],1);eq(v.actors[1].flameAcc,.4)
		local actors,dt=v.frame(5.1);eq(dt,0);assert(math.abs(actors[1].drawAge-1.2)<1e-9);eq(row.age,1);assert(row.points)
		v.actors[1].flameAcc=.8
		local delta=table.clone(row);delta.points=nil;delta.age=2
		assert(v.apply({epoch=1,time=5.5,actors={delta},pixels=Packets.pixels({})}));eq(v.actors[1].flameAcc,.8)
		actors,dt=v.frame(5.5);assert(dt>0);eq(#actors,1)
		delta.age=10;v.apply({epoch=1,time=6,actors={delta},pixels=Packets.pixels({})});actors=v.frame(6);eq(#actors,0)
		v.apply({epoch=2,reset=true,time=6,actors={},pixels=Packets.pixels({})});eq(clears,2)
		eq(v.apply(packet),false);eq(clears,2);eq(next(v.actors),nil)
		local x,y=v.point(141);eq(x,1);eq(y,1)
	end)
end
