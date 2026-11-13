--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local source=fs.readFile("src/server/Match/MatchService.luau")
	local function fixture()
		local h:any={player={},ready={},seats={},sent={},built=0,version=1,resets=0}
		h.seats[h.player]=1
		local env=setmetatable({sideOf=h.seats,readyView=h.ready,tick=1,sim={time=0,fogOn=function() return false end},viewers={},sentVision={},deaths={},collapses={},blasts={},BlastEvents={visible=function()return{}end},CollapseEvents={visible=function() return {} end},
			viewFor=function() h.built+=1;return {{h.version}},{},{1,2,3} end,
			Net={sendSnapshot=function(player,tick,units,_,vision) table.insert(h.sent,{player=player,version=units[1][1],vision=vision,tick=tick}) end},MatchService={resetView=function() h.resets+=1 end}},{__index=getfenv()})
		local a=assert(source:find("local function snapshot()",1,true));local b=assert(source:find("-- Own territory",a,true))
		h.snapshot=luau.load(source:sub(a,b-1).."\nreturn snapshot",{environment=env})()
		a=assert(source:find("local function onIntent(",1,true));b=assert(source:find("\n\tif not side or side == 0 then",a,true))
		h.intent=luau.load(source:sub(a,b-1).."\nend\nreturn onIntent",{environment=env})();return h
	end
	test("loading clients receive no snapshots or viewer work until the actual ready handshake",function()
		local h=fixture();for _=1,1000 do h.snapshot() end;eq(#h.sent,0);eq(h.built,0)
		h.version=9;h.intent(h.player,{kind="viewReady"});h.snapshot();eq(#h.sent,1);eq(h.sent[1].version,9);assert(h.sent[1].vision)
		h.intent(h.player,{kind="viewReady"});eq(h.resets,1)
	end)
	test("unknown players cannot enable streaming and spectators use the same ready handshake",function()
		local h=fixture();h.intent({},{kind="viewReady"});eq(next(h.ready),nil);h.seats[h.player]=0
		h.intent(h.player,{kind="viewReady"});h.snapshot();eq(#h.sent,1)
	end)
	test("private state does not build payloads or enqueue messages for an unready client",function()
		local a=assert(source:find("local function privateState()",1,true));local b=assert(source:find("function MatchService.resetView(",a,true))
		local player={};local calls=0;local alerts={}
		local env=setmetatable({sideOf={[player]=1},readyView={},sim=nil,pendingAlerts=alerts,Net={sendState=function() calls+=1 end}},{__index=getfenv()})
		local state=luau.load(source:sub(a,b-1).."\nreturn privateState",{environment=env})();for _=1,1000 do state() end;eq(calls,0)
	end)
	test("the actual ready notification bypasses a modal's gameplay-order block",function()
		local client=fs.readFile("src/client/init.client.luau");local a=assert(client:find("-- Both listeners",1,true));local b=assert(client:find("\nend",a,true));local received=nil
		local env=setmetatable({intent={FireServer=function(_,payload) received=payload end},send=function() error("orders are blocked") end},{__index=getfenv()})
		luau.load(client:sub(a,b-1),{environment=env})();eq(received.kind,"viewReady")
	end)
end
