--!strict
-- Standalone pre-match surface. Caller owns presenter, screen flow and input gating.
-- Background must be a separately approved static Roblox image; no EditableImages are used.
local UI = {}
function UI.mount(options:any):any
 local presenter=options.presenter
 local connections={};local maps={};local seats={};local players={};local dead=false
 local gui=Instance.new("ScreenGui");gui.Name="WarFrontPrematch";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=70
 local function connect(signal:any,fn:any) table.insert(connections,signal:Connect(fn)) end
 local function box(class:string,parent:any):any
  local o=Instance.new(class);o.BorderSizePixel=0;o.Parent=parent;return o
 end
 local backdrop=box("Frame",gui);backdrop.Size=UDim2.fromScale(1,1);backdrop.BackgroundColor3=Color3.fromRGB(13,23,27);backdrop.Active=true
 local art=box("ImageLabel",backdrop);art.BackgroundTransparency=1;art.Size=UDim2.fromScale(1,1);art.ScaleType=Enum.ScaleType.Fit
 art.Image=options.backgroundImage or ""
 local function label(parent:any,text:string,height:number,size:number):any
  local o=box("TextLabel",parent);o.BackgroundTransparency=1;o.Size=UDim2.new(1,0,0,height);o.Text=text;o.TextSize=size
  o.Font=Enum.Font.Gotham;o.TextColor3=Color3.fromRGB(231,235,228);o.TextWrapped=true;o.TextXAlignment=Enum.TextXAlignment.Left;o.RichText=false;return o
 end
 local artNote=label(backdrop,"STATIC BACKGROUND NOT CONFIGURED\nAssign the approved monument image",50,12)
 artNote.Position=UDim2.fromScale(.04,.05);artNote.Size=UDim2.fromScale(.35,.12)
 local panel=box("ScrollingFrame",backdrop);panel.BackgroundColor3=Color3.fromRGB(18,28,31);panel.BackgroundTransparency=.04
 panel.Active=true;panel.ScrollBarThickness=5;panel.AutomaticCanvasSize=Enum.AutomaticSize.Y;panel.CanvasSize=UDim2.fromOffset(0,0)
 local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,20);pad.PaddingRight=UDim.new(0,20);pad.PaddingTop=UDim.new(0,18);pad.PaddingBottom=UDim.new(0,18);pad.Parent=panel
 local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,8);layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=panel
 local sequence=0
 local function row(parent:any,text:string,height:number,size:number):any sequence+=1;local o=label(parent,text,height,size);o.LayoutOrder=sequence;return o end
 local function button(parent:any,text:string,fn:any):any
  local o=box("TextButton",parent);o.Size=UDim2.new(1,0,0,36);o.Text=text;o.TextSize=14;o.Font=Enum.Font.GothamMedium;o.RichText=false
  o.TextColor3=Color3.fromRGB(237,240,230);o.BackgroundColor3=Color3.fromRGB(46,65,64);o.TextWrapped=true
  sequence+=1;o.LayoutOrder=sequence;connect(o.Activated,fn);return o
 end
 row(panel,"ROBLOXIANFRONT",27,21)
 row(panel,"PRE-MATCH LOBBY",20,12)
 local role=row(panel,"Connecting…",36,14)
 local message=row(panel,"Loading lobby…",52,14)
 row(panel,"MAP · HOST SELECTS",20,12)
 local mapGroup=box("Frame",panel);mapGroup.BackgroundTransparency=1;sequence+=1;mapGroup.LayoutOrder=sequence
 local mapLayout=Instance.new("UIListLayout");mapLayout.Padding=UDim.new(0,4);mapLayout.SortOrder=Enum.SortOrder.LayoutOrder;mapLayout.Parent=mapGroup
 row(panel,"PLAYERS · TEAM / SEAT · READY",20,12)
 local playerGroup=box("Frame",panel);playerGroup.BackgroundTransparency=1;sequence+=1;playerGroup.LayoutOrder=sequence
 local playerLayout=Instance.new("UIListLayout");playerLayout.Padding=UDim.new(0,4);playerLayout.SortOrder=Enum.SortOrder.LayoutOrder;playerLayout.Parent=playerGroup
 row(panel,"AVAILABLE SEATS",20,12)
 local seatGroup=box("Frame",panel);seatGroup.BackgroundTransparency=1;sequence+=1;seatGroup.LayoutOrder=sequence
 local seatLayout=Instance.new("UIListLayout");seatLayout.Padding=UDim.new(0,4);seatLayout.SortOrder=Enum.SortOrder.LayoutOrder;seatLayout.Parent=seatGroup
 local ready=button(panel,"Ready",function() local s=presenter.view.snapshot;local me=s and s.players[tostring(presenter.view.userId)];if me then presenter.command("ready",not me.ready) end end)
 local feedback=row(panel,"Host must select a map.",46,13)
 local start=button(panel,"Start match",function() presenter.command("start") end)
 local retry=button(panel,"Retry connection",function() presenter.refresh() end)
 local leave=button(panel,"Leave lobby",function() if options.onLeave then options.onLeave() end end)
 local function enabled(o:any,value:boolean) o.Active=value;o.AutoButtonColor=value;o.BackgroundTransparency=if value then 0 else .55 end
 local function render(view:any)
  if dead then return end
  local s=view.snapshot;local uid=view.userId;local me=s and s.players[tostring(uid)]
  local waiting=s~=nil and s.phase=="waiting" and me~=nil and not view.pending
  role.Text=if not s then "Connecting to host…" elseif s.phase=="closed" then "LOBBY CLOSED" elseif s.hostUserId==uid then "YOU ARE THE HOST · Choose a map and start when eligible." else "PLAYER · Choose a seat and mark yourself Ready."
  message.Text=if view.pending then view.message elseif view.message~="" then view.message elseif s then string.upper(s.phase) else "Loading lobby…"
  local list=s and s.maps or {}
  for i,m in list do
   local r=maps[i]
   if not r then r={};r.button=button(mapGroup,"",function() if r.id then presenter.command("map",r.id) end end);maps[i]=r end
   r.id=m.id;r.button.Visible=true;r.button.Text=(if s.mapId==m.id then "SELECTED · " else "")..m.name
   enabled(r.button,waiting and s.hostUserId==uid)
  end
  for i=#list+1,#maps do maps[i].button.Visible=false;maps[i].id=nil end
  mapGroup.Size=UDim2.new(1,0,0,#list*40)
  local roster={};if s then for _,p in s.players do table.insert(roster,p) end end
  table.sort(roster,function(a,b) return a.order<b.order end)
  for i,p in roster do
   local r=players[i];if not r then r=label(playerGroup,"",44,13);players[i]=r end
   r.Visible=true;r.Text=p.name..(if p.userId==s.hostUserId then " [HOST]" else " [PLAYER]")..(if p.userId==uid then " · YOU" else "").."\n"..(p.seatId or "Choose a seat").." · "..(if p.ready then "READY" else "NOT READY")
  end
  for i=#roster+1,#players do players[i].Visible=false end
  playerGroup.Size=UDim2.new(1,0,0,#roster*48)
  local available=s and s.seats or {};local selectedMap=nil
  if s then for _,m in s.maps do if m.id==s.mapId then selectedMap=m end end end
  for i,seat in available do
   local r=seats[i]
   if not r then r={};r.button=button(seatGroup,"",function() if r.id then presenter.command("seat",r.id) end end);seats[i]=r end
   local owner=nil;for _,p in roster do if p.seatId==seat.id then owner=p end end
   local allowed=selectedMap~=nil and (not selectedMap.seatIds or table.find(selectedMap.seatIds,seat.id)~=nil)
   r.id=seat.id;r.button.Visible=true;r.button.Text=seat.label.." · "..seat.team.." · "..(if not allowed then "Unavailable for this map" elseif owner then owner.name else "Open")
   enabled(r.button,waiting and allowed and (owner==nil or owner.userId==uid))
  end
  for i=#available+1,#seats do seats[i].button.Visible=false;seats[i].id=nil end
  seatGroup.Size=UDim2.new(1,0,0,#available*40)
  ready.Text=if me and me.ready then "Not ready" else "Mark Ready";enabled(ready,waiting and me.seatId~=nil)
  feedback.Text=if s then s.startFeedback else "Waiting for lobby state."
  start.Text=if s and s.phase=="starting" then "Starting…" else "Start match"
  enabled(start,waiting and s.hostUserId==uid and s.canStart==true)
  enabled(retry,not view.pending and (not s or s.phase=="loading" or s.phase=="unavailable" or s.phase=="error"))
  enabled(leave,options.onLeave~=nil)
 end
 local function resize()
  local size=backdrop.AbsoluteSize;local narrow=size.X<760 or size.X<size.Y
  -- Keep the whole monument visible outside the opaque text panel, with no stretch/crop.
  art.Size=if narrow then UDim2.fromScale(1,.34) else UDim2.fromScale(.46,1)
  art.Image=if narrow then options.backgroundImagePortrait or options.backgroundImage or "" else options.backgroundImage or ""
  artNote.Visible=art.Image==""
  panel.Position=if narrow then UDim2.fromScale(.03,.36) else UDim2.fromScale(.47,.07)
  panel.Size=if narrow then UDim2.fromScale(.94,.61) else UDim2.fromScale(.50,.86)
 end
 local unbind=presenter.onChanged(render)
 local handle={}
 function handle.destroy()
  if dead then return end
  dead=true;unbind();for _,c in connections do c:Disconnect() end;table.clear(connections);gui:Destroy()
 end
 connect(gui.Destroying,handle.destroy)
 connect(backdrop:GetPropertyChangedSignal("AbsoluteSize"),resize)
 gui.Parent=options.parent;resize();render(presenter.view)
 return handle
end
return UI
