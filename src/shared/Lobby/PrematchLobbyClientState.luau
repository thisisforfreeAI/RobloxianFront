--!strict
-- Transport-independent presenter. No remotes, match startup or polling are installed here.
local Client = {}
function Client.new(deps:any):any
 local alive=true;local busy=false;local token:any=nil;local listeners={};local stop:any=nil
 local self:any={view={phase="loading",snapshot=nil,message="Loading lobby…",pending=false,userId=deps.userId}}
 local function emit() if alive then for fn in listeners do fn(self.view) end end end
 local function accept(snapshot:any):boolean
  if type(snapshot)~="table" or snapshot.sessionId~=deps.sessionId or type(snapshot.revision)~="number" or snapshot.revision%1~=0 or snapshot.revision<0 then return false end
  if type(snapshot.players)~="table" or type(snapshot.maps)~="table" or type(snapshot.seats)~="table" then return false end
  local old=self.view.snapshot
  if old and snapshot.revision<=old.revision then return false end
  self.view.snapshot=snapshot;self.view.phase=snapshot.phase;self.view.message=snapshot.message or "";return true
 end
 function self.receive(snapshot:any)
  if alive and accept(snapshot) then emit() end
 end
 function self.onChanged(fn:any):any
  listeners[fn]=true
  return function() listeners[fn]=nil end
 end
 local function request(command:any?):boolean
  if not alive or busy then return false end
  busy=true;token={};local mine=token;self.view.pending=true;self.view.message=if command then "Updating lobby…" else "Loading lobby…";emit()
  local function done(result:any)
   if not alive or token~=mine then return end
   token=nil;busy=false;self.view.pending=false
   local applied=type(result)=="table" and accept(result.snapshot)
   if type(result)~="table" or result.ok~=true then
    self.view.message=if type(result)=="table" and type(result.message)=="string" then result.message else "Lobby unavailable. Retry the connection."
    if not self.view.snapshot then self.view.phase="unavailable" end
   elseif not applied then
    self.view.message=if self.view.snapshot then self.view.snapshot.message or "" else "Waiting for a valid lobby state. Retry the connection."
    if not self.view.snapshot then self.view.phase="error" end
   end
   emit()
  end
  local ok=pcall(function() if command then deps.send(command,done) else deps.fetch(done) end end)
  if not ok then done(nil) end
  return true
 end
 function self.refresh():boolean return request(nil) end
 function self.command(kind:string,value:any?):boolean
  local s=self.view.snapshot
  if not s or s.phase~="waiting" then return false end
  local command={kind=kind,revision=s.revision}
  if kind=="map" then command.mapId=value elseif kind=="seat" then command.seatId=value elseif kind=="ready" then command.ready=value end
  return request(command)
 end
 function self.destroy()
  if not alive then return end
  alive=false;token=nil;table.clear(listeners)
  if stop then stop();stop=nil end
 end
 if deps.subscribe then stop=deps.subscribe(self.receive) end
 return self
end
return Client
