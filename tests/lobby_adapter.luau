--!strict
-- Executes the actual Roblox adapter against strict API-shaped stand-ins; not a live-service test.
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local D=require("../src/shared/Lobby/LobbyDirectory");local P=require("../src/shared/Lobby/LobbyProtocol")
	local function signal()
		local s:any={connections={}};function s:Connect(fn) local c={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.connections,c);return c end
		function s:fire(...) for _,c in self.connections do if not c.dead then c.fn(...) end end end;return s
	end
	local function fixture(studio:boolean?,state:any?)
		local h:any={t=1000000,values={},instances={},ranges={},teleports={},notices={},writes=0,reads=0,clock=0,friendCalls=0}
		local function instance(class)
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,c in h.instances do if c.Parent==self then c:Destroy() end end end
			function o:SetTeleportData(data) self.data=data end;function o:GetTeleportData() return self.data end
			function o:FireClient(player,payload) table.insert(h.notices,payload) end
			table.insert(h.instances,o);return o
		end
		local map:any={}
		function map:GetAsync(key) h.reads+=1;if h.outage then error("unavailable") end;return h.values[key] end
		function map:UpdateAsync(key,transform,ttl)
			h.writes+=1;if h.outage then error("unavailable") end
			transform(h.values[key]);local v=transform(h.values[key]);if v then h.values[key]=v end;return v
		end
		function map:RemoveAsync(key) h.values[key]=nil end
		function map:GetRangeAsync(direction,count,after)
			assert(after==nil or type(after)=="table");table.insert(h.ranges,{after=after,count=count})
			local keys={};for key in h.values do if not after or key>after.key then table.insert(keys,key) end end;table.sort(keys)
			local out={};for i=1,math.min(count,#keys) do table.insert(out,{key=keys[i],value=h.values[keys[i]]}) end;return out
		end
		h.players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
		local teleport={TeleportInitFailed=signal(),TeleportAsync=function(_,place,players,options) table.insert(h.teleports,{place=place,players=players,options=options});return {} end};h.tp=teleport
		local messageConnection={Disconnect=function() h.unsubscribed=true end}
		local shared={Lobby={LobbyDirectory="directory",LobbyProtocol="protocol"}}
		local rs={WaitForChild=function() return shared end}
		local services={Players=h.players,ReplicatedStorage=rs,RunService={IsStudio=function() return studio==true end},TeleportService=teleport,
			MemoryStoreService={GetSortedMap=function() return map end},MessagingService={SubscribeAsync=function() return messageConnection end,PublishAsync=function() end}}
		local fakeTask={spawn=function(fn,...) local co=coroutine.create(fn);local ok,err=coroutine.resume(co,...);assert(ok,err);return co end,wait=function() coroutine.yield() end}
		local game={JobId=if studio then "" else "local-job",PlaceId=111,PrivateServerId="",PrivateServerOwnerId=0,GetService=function(_,key) return services[key] end,BindToClose=function(_,fn) h.shutdown=fn end}
		local serviceEnv=setmetatable({game=game,require=function(key) return if key=="directory" then D else P end},{__index=getfenv()})
		local Service=luau.load(fs.readFile("src/server/Lobby/LobbyDirectoryService.luau"),{environment=serviceEnv})()
		local env=setmetatable({game=game,script={Parent={LobbyDirectoryService="service"}},require=function(key) return if key=="directory" then D elseif key=="protocol" then P else Service end,
			Instance={new=instance},Enum={SortDirection={Ascending=1}},task=fakeTask,os={time=function() return h.t end,clock=function() return h.clock end},warn=function() end},{__index=getfenv()})
		local adapter=luau.load(fs.readFile("src/server/Lobby/LobbyServer.luau"),{environment=env})();h.state=state or {map="Saddle",players=0,capacity=2,status="waiting",userIds={}}
		h.svc=adapter.start(function() return h.state end)
		function h:player(id)
			return {UserId=id,Parent=self.players,IsFriendsWithAsync=function(_,host) h.friendCalls+=1;return id==6 and host==42 end,Kick=function(_,message) h.kicked=message end}
		end
		function h:listing(id) self.values[id]=D.makeListing({lobbyId=id,jobId=id,placeId=111,map="Saddle",players=1,capacity=2,status="waiting",visibility="public"},self.t) end
		return h
	end
	test("native adapter passes a table cursor on a second sorted-map page",function()
		local h=fixture();for i=1,205 do h:listing(string.format("job-%03d",i)) end
		local result=h.svc.browse(h:player(1),{limit=100});eq(result.ok,true);eq(#h.ranges,2);eq(type(h.ranges[2].after),"table");assert(h.ranges[2].after.key)
	end)
	test("native teleport failures are correlated to our options before releasing a hold",function()
		local h=fixture();h:listing("target");local p=h:player(1);eq(h.svc.join(p,"target").ok,true)
		local sent=h.teleports[1];eq(sent.options.ServerInstanceId,"target");eq(sent.place,111);eq(sent.players[1],p)
		h.tp.TeleportInitFailed:fire(p,nil,"",111,{GetTeleportData=function() return {requestId="unrelated"} end});assert(h.values.target.reservations["1"])
		h.tp.TeleportInitFailed:fire(p,nil,"",111,sent.options);eq(h.values.target.reservations["1"],nil);eq(#h.notices,1)
	end)
	test("Studio keeps local play available without directory reads, writes or teleports",function()
		local h=fixture(true);local p=h:player(1);h.players.PlayerAdded:fire(p)
		eq(h.svc.arrival(p).seat,true);eq(h.svc.browse(p,nil).ok,false);eq(h.svc.join(p,"target").ok,false)
		eq(h.reads,0);eq(h.writes,0);eq(#h.teleports,0)
	end)
	test("adapter starts privacy checks before arrivals and uses the current friend API",function()
		local h=fixture(false,{map="Saddle",players=0,capacity=2,status="waiting",visibility="friends",hostUserId=42,userIds={}})
		local friend=h:player(6);h.players.PlayerAdded:fire(friend);eq(h.svc.arrival(friend).admit,true);assert(h.friendCalls>0)
		h.outage=true;local stranger=h:player(7);h.players.PlayerAdded:fire(stranger);eq(h.svc.arrival(stranger).admit,false);assert(h.kicked)
	end)
	test("adapter close disconnects owned callbacks and removes native remotes and listing",function()
		local h=fixture();h.svc.close();eq(h.values["local-job"],nil);eq(h.unsubscribed,true)
		for _,c in h.players.PlayerAdded.connections do eq(c.dead,true) end
		for _,item in h.instances do if item.ClassName=="Folder" then eq(item.dead,true) end end
	end)
end
