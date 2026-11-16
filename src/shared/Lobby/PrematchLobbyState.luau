--!strict
-- Proposed port policies, NOT traced WarFront multiplayer rules. Server-owned, non-yielding model.
local Model = {}
local function copy(value:any):any
 if type(value) ~= "table" then return value end
 local out = {}; for k,v in value do out[k] = copy(v) end; return out
end
local function id(value:any):boolean
 return type(value)=="string" and #value>0 and #value<=64
end
local function user(value:any):boolean
 return type(value)=="number" and value>0 and value%1==0 and value<2^53
end
function Model.new(config:any):any
 assert(type(config)=="table" and user(config.hostUserId),"hostUserId required")
 assert(id(config.sessionId),"unique sessionId required")
 assert(type(config.maps)=="table" and #config.maps<=32,"at most 32 maps")
 assert(type(config.seats)=="table" and #config.seats>0 and #config.seats<=16,"1..16 seats required")
 local maps,seats,seenMaps,seenSeats={},{},{},{}
 for _,s in config.seats do
  assert(id(s.id) and id(s.team) and not seenSeats[s.id],"invalid/duplicate seat")
  seenSeats[s.id]=true;table.insert(seats,{id=s.id,team=s.team,label=tostring(s.label or s.id):sub(1,50)})
 end
 for _,m in config.maps do
  assert(id(m.id) and not seenMaps[m.id],"invalid/duplicate map")
  seenMaps[m.id]=true
  if m.seatIds then
   assert(type(m.seatIds)=="table" and #m.seatIds>0 and #m.seatIds<=#seats,"invalid map seats")
   local used={};for _,key in m.seatIds do assert(seenSeats[key] and not used[key],"unknown/duplicate map seat");used[key]=true end
  end
  table.insert(maps,{id=m.id,name=tostring(m.name or m.id):sub(1,50),seatIds=copy(m.seatIds)})
 end
 local p=config.policy or {}
 local policy={minPlayers=p.minPlayers or 2,requireAllReady=p.requireAllReady~=false,
  requireDistinctTeams=p.requireDistinctTeams~=false,hostDeparture=p.hostDeparture or "close",
  resetReadyOnRosterChange=p.resetReadyOnRosterChange~=false,resetReadyOnSeatChange=p.resetReadyOnSeatChange~=false,
  resetReadyOnMapChange=p.resetReadyOnMapChange~=false}
 assert(type(policy.minPlayers)=="number" and policy.minPlayers%1==0 and policy.minPlayers>=1 and policy.minPlayers<=#seats,"invalid minimum players")
 assert(policy.hostDeparture=="close" or policy.hostDeparture=="transfer","invalid host departure policy")
 local state:any={sessionId=config.sessionId,revision=0,phase=if #maps==0 then "unavailable" else "waiting",
  hostUserId=config.hostUserId,maps=maps,seats=seats,players={},policy=policy,launchId=0,message=""}
 local order=0
 local function reset() for _,v in state.players do v.ready=false end end
 local function changed() state.revision+=1 end
 local function mapById(key:any):any for _,m in maps do if m.id==key then return m end end;return nil end
 local function seatAllowed(key:any):boolean
  if not seenSeats[key] then return false end
  local map=mapById(state.mapId)
  if not map then return false end
  if not map.seatIds then return true end
  return table.find(map.seatIds,key)~=nil
 end
 local function eligibility():(boolean,string)
  if state.phase~="waiting" then
   local messages={loading="Loading lobby…",unavailable="Lobby unavailable. Reconnect or retry.",error="Lobby error. Reconnect or retry.",starting="Starting match…",started="Match has started.",closed="Lobby closed: the host left or no players remain."}
   return false,messages[state.phase] or "Lobby unavailable."
  end
  if not mapById(state.mapId) then return false,"Host must select a map." end
  local count,teams=0,{}
  for _,v in state.players do count+=1;if not v.seatId then return false,"Every player must choose an available seat." end end
  if count<policy.minPlayers then return false,`Need at least {policy.minPlayers} players.` end
  for _,v in state.players do
   for _,s in seats do if s.id==v.seatId then teams[s.team]=true end end
   if policy.requireAllReady and not v.ready then return false,"Waiting for every player, including the host, to be Ready." end
  end
  local n=0;for _ in teams do n+=1 end
  if policy.requireDistinctTeams and n<2 then return false,"Players must occupy at least two different teams." end
  return true,"All conditions met. Host can start."
 end
 local self={}
 function self.snapshot():any
  local view=copy(state);view.players={}
  -- String keys preserve a sparse UserId dictionary through Roblox remote serialization.
  for uid,player in state.players do view.players[tostring(uid)]=copy(player) end
  view.canStart,view.startFeedback=eligibility();return view
 end
 function self.join(userId:number,name:string):any
  if not user(userId) then return {ok=false,message="Invalid player."} end
  if state.players[userId] then return {ok=true,snapshot=self.snapshot()} end
  if state.phase~="waiting" and state.phase~="loading" and state.phase~="unavailable" and state.phase~="error" then return {ok=false,message="Lobby is not accepting players."} end
  local count=0;for _ in state.players do count+=1 end
  if count>=#seats then return {ok=false,message="Lobby is full."} end
  order+=1;state.players[userId]={userId=userId,name=tostring(name):sub(1,40),ready=false,order=order}
  if policy.resetReadyOnRosterChange then reset() end
  changed();return {ok=true,snapshot=self.snapshot()}
 end
 function self.leave(userId:number)
  if not state.players[userId] then return end
  state.players[userId]=nil
  if state.phase=="starting" then state.phase="waiting";state.message="A player left during startup. Host must start again." end
  if userId==state.hostUserId then
   local nextHost=nil
   if policy.hostDeparture=="transfer" then for _,v in state.players do if not nextHost or v.order<nextHost.order then nextHost=v end end end
   if nextHost and state.phase~="started" and state.phase~="closed" then
    state.hostUserId=nextHost.userId;state.message="Host left. Hosting transferred to "..nextHost.name..".";reset()
   else state.phase="closed";state.message="Host disconnected. Leave this lobby and reconnect." end
  end
  if not next(state.players) then state.phase="closed" end
  if policy.resetReadyOnRosterChange then reset() end
  changed()
 end
 -- Internal trusted authority API, never expose directly as client commands.
 function self.setAvailability(phase:string,message:string?):boolean
  if state.phase=="starting" or state.phase=="started" or state.phase=="closed" then return false end
  if not table.find({"waiting","loading","unavailable","error"},phase) then return false end
  state.phase=if #maps==0 then "unavailable" else phase;state.message=message or "";reset();changed();return true
 end
 function self.finishStart(launchId:number,ok:boolean,message:string?):boolean
  if state.phase~="starting" or state.launchId~=launchId then return false end
  state.phase=if ok then "started" else "waiting"
  state.message=if ok then "Match ready." else (message or "Start failed. Host can try again.")
  if not ok then reset() end
  changed();return true
 end
 -- actor comes from authenticated server context, not a userId sent by the client.
 function self.dispatch(actor:number,command:any):any
  local function fail(message:string):any return {ok=false,message=message,snapshot=self.snapshot()} end
  if type(command)~="table" then return fail("Invalid command.") end
  if command.revision~=state.revision then return fail("Lobby changed. Review the latest state and try again.") end
  local player=state.players[actor];if not player then return fail("You are not in this lobby.") end
  if state.phase~="waiting" then return fail("Lobby is not accepting changes. "..select(2,eligibility())) end
  if command.kind=="map" then
   if actor~=state.hostUserId then return fail("Only the host can choose the map.") end
   if not mapById(command.mapId) then return fail("That map is unavailable.") end
   if state.mapId==command.mapId then return {ok=true,snapshot=self.snapshot()} end
   state.mapId=command.mapId
   for _,v in state.players do if v.seatId and not seatAllowed(v.seatId) then v.seatId=nil;v.ready=false end end
   if policy.resetReadyOnMapChange then reset() end
  elseif command.kind=="seat" then
   if not seatAllowed(command.seatId) then return fail("Choose a seat supported by the selected map.") end
   for uid,v in state.players do if uid~=actor and v.seatId==command.seatId then return fail("That seat was taken. Choose another.") end end
   if player.seatId==command.seatId then return {ok=true,snapshot=self.snapshot()} end
   player.seatId=command.seatId;player.ready=false
   if policy.resetReadyOnSeatChange then reset() end
  elseif command.kind=="ready" then
   if type(command.ready)~="boolean" then return fail("Invalid Ready value.") end
   if not seatAllowed(player.seatId) then return fail("Select a map and seat before Ready.") end
   player.ready=command.ready
  elseif command.kind=="start" then
   if actor~=state.hostUserId then return fail("Only the host can start.") end
   local ok,reason=eligibility();if not ok then return fail(reason) end
   state.phase="starting";state.launchId+=1
  else return fail("Unknown command.") end
  state.message="";changed();return {ok=true,snapshot=self.snapshot()}
 end
 assert(self.join(config.hostUserId,config.hostName or "Host").ok)
 return self
end
return Model
