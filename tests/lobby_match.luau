--!strict
return function(test:any,eq:any)
	local Policy=require("../src/shared/Lobby/MatchLobby")
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local source=fs.readFile("src/server/Match/MatchService.luau");local a=assert(source:find("local function assignSide(",1,true));local b=assert(source:find("-- Fog of war:",a,true))
	local function fixture()
		local h:any={seats={},sim={},map={data={id="Saddle"},width=10,height=10},bots=0,defers={},players={}}
		h.player={UserId=1,Parent=h.players,Kick=function(_,message) h.kicked=message end};h.match={directoryRequired=true,lobby={waitArrival=function() return h.arrival end,heartbeat=function() end}}
		local env=setmetatable({Players=h.players,MatchService=h.match,MatchLobby=Policy,sideOf=h.seats,map=h.map,sim=h.sim,updateBots=function() h.bots+=1 end,
			task={defer=function(fn) table.insert(h.defers,fn) end,wait=function() error("unexpected bootstrap wait") end}},{__index=getfenv()})
		h.assign=luau.load(source:sub(a,b-1).."\nreturn assignSide",{environment=env})();return h
	end
	test("directory status follows deployment and keeps unclaimed bot seats joinable until victory",function()
		local map={data={id="Saddle"}};local sim={drop={phase="pick"}};local p={UserId=7};local seats={[p]=1,[{UserId=8}]=0}
		local s=Policy.state(map,sim,seats);eq(s.status,"waiting");eq(s.players,1);eq(#s.userIds,1);eq(s.joinInProgress,true)
		sim.drop.phase="done";eq(Policy.state(map,sim,seats).status,"inProgress");sim.winner=1;s=Policy.state(map,sim,seats);eq(s.status,"closing");eq(s.joinInProgress,false)
		eq(Policy.state(nil,sim,seats),nil)
	end)
	test("actual match Join waits for arrival then assigns one authoritative side",function()
		local h=fixture();h.arrival={admit=true,seat=true};eq(h.assign(h.player).side,1);eq(h.seats[h.player],1);eq(h.bots,1)
		eq(h.assign(h.player).side,1);eq(h.bots,1);eq(#h.defers,1)
	end)
	test("full/started arrivals stay spectators and refusal never enters snapshot membership",function()
		local h=fixture();h.arrival={admit=true,seat=false};eq(h.assign(h.player).side,0);eq(h.seats[h.player],0)
		local denied=fixture();denied.arrival={admit=false};denied.assign(denied.player);eq(denied.seats[denied.player],nil);assert(denied.kicked);eq(denied.bots,0)
		local timeout=fixture();timeout.assign(timeout.player);eq(timeout.seats[timeout.player],nil);assert(timeout.kicked)
	end)
	test("seating rechecks after a yielding arrival and never claims a third side",function()
		local h=fixture();h.match.lobby.waitArrival=function() coroutine.yield();return {admit=true,seat=true} end
		local thread=coroutine.create(function() return h.assign(h.player) end);assert(coroutine.resume(thread))
		h.seats[{UserId=2}]=1;h.seats[{UserId=3}]=2;local ok,info=coroutine.resume(thread);assert(ok);eq(info.side,0)
	end)
	test("a player leaving during admission cannot retain a match seat",function()
		local h=fixture();h.match.lobby.waitArrival=function() h.player.Parent=nil;return {admit=true,seat=true} end
		h.assign(h.player);eq(h.seats[h.player],nil);eq(h.bots,0)
	end)
	test("finished matches cannot hand a newly arriving player a side",function()
		local h=fixture();h.arrival={admit=true,seat=true};h.sim.winner=1;eq(h.assign(h.player).side,0)
	end)
end
