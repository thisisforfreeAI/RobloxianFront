--!strict
return function(test:any,eq:any)
 local Client=require("../src/shared/Lobby/PrematchLobbyClientState")
 local function snapshot(revision:number):any return {sessionId="room",revision=revision,phase="waiting",players={},maps={},seats={},message=""} end
 local function fixture():any
  local h:any={calls={},changes=0};h.client=Client.new({sessionId="room",userId=1,
   fetch=function(done) table.insert(h.calls,{done=done}) end,send=function(command,done) table.insert(h.calls,{command=command,done=done}) end,
   subscribe=function(fn) h.receive=fn;return function() h.unsubscribed=true end end})
  h.client.onChanged(function() h.changes+=1 end);return h
 end
 test("prematch presenter displays cold loading, missing transport and retry recovery",function()
  local h=fixture();eq(h.client.view.phase,"loading");h.client.refresh();h.calls[1].done(nil);eq(h.client.view.phase,"unavailable")
  h.client.refresh();h.calls[2].done({ok=true,snapshot=snapshot(1)});eq(h.client.view.phase,"waiting")
 end)
 test("prematch presenter bounds requests and carries authoritative revision",function()
  local h=fixture();h.client.refresh();eq(h.client.refresh(),false);h.calls[1].done({ok=true,snapshot=snapshot(1)})
  eq(h.client.command("seat","blue"),true);eq(h.calls[2].command.revision,1);eq(h.calls[2].command.seatId,"blue")
  eq(h.client.command("ready",true),false);eq(#h.calls,2)
 end)
 test("prematch newer push beats an older response and another room is ignored",function()
  local h=fixture();h.client.refresh();h.receive(snapshot(4));h.calls[1].done({ok=true,snapshot=snapshot(2)})
  eq(h.client.view.snapshot.revision,4);local wrong=snapshot(9);wrong.sessionId="other";h.receive(wrong);eq(h.client.view.snapshot.revision,4)
 end)
 test("prematch failed command retains new authority state and actionable feedback",function()
  local h=fixture();h.receive(snapshot(1));h.client.command("start");h.calls[1].done({ok=false,snapshot=snapshot(2),message="Seat taken. Select another."})
  eq(h.client.view.snapshot.revision,2);eq(h.client.view.message,"Seat taken. Select another.");eq(h.client.view.pending,false)
 end)
 test("prematch destroy disconnects subscriptions and ignores delayed completions",function()
  local h=fixture();h.client.refresh();h.client.destroy();local n=h.changes
  h.calls[1].done({ok=true,snapshot=snapshot(1)});h.receive(snapshot(2));eq(h.changes,n);eq(h.unsubscribed,true);eq(h.client.refresh(),false)
 end)
 test("prematch thrown transport and malformed snapshots are recoverable errors",function()
  local c=Client.new({sessionId="room",fetch=function() error("offline") end});c.refresh();eq(c.view.phase,"unavailable")
  local h=fixture();h.client.refresh();h.calls[1].done({ok=true,snapshot={sessionId="room",revision=0/0}});eq(h.client.view.phase,"error");eq(h.client.view.pending,false)
 end)
 test("prematch equal snapshots cannot overwrite already received state",function()
  local h=fixture();h.receive(snapshot(3));local stale=snapshot(3);stale.phase="closed";h.receive(stale);eq(h.client.view.phase,"waiting")
 end)
end
