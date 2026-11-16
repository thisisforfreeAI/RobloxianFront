--!strict
-- Actual Luau UI module against native-shaped stand-ins; not a Roblox visual/performance test.
return function(test:any,eq:any)
 local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
 local State=require("../src/shared/Lobby/PrematchLobbyState");local Client=require("../src/shared/Lobby/PrematchLobbyClientState")
 local function fixture(background:string?,viewer:number?,portraitImage:string?):any
  local h:any={objects={},connections={},sent=0,left=0}
  local function signal():any
   local s:any={cs={}}
   function s:Connect(fn:any):any
    local c={fn=fn};function c:Disconnect() self.dead=true end
    table.insert(h.connections,c);table.insert(self.cs,c);return c
   end
   function s:fire(...) for _,c in table.clone(self.cs) do if not c.dead then c.fn(...) end end end
   return s
  end
  local function instance(class:string):any
   local o:any={ClassName=class,AbsoluteSize=rb.Vector2.new(1280,720),Activated=signal(),Destroying=signal(),properties={}}
   function o:GetPropertyChangedSignal(key:string):any if not self.properties[key] then self.properties[key]=signal() end;return self.properties[key] end
   function o:Destroy()
    if self.dead then return end;self.dead=true;self.Destroying:fire()
    for _,child in h.objects do if child.Parent==self then child:Destroy() end end
   end
   table.insert(h.objects,o);return o
  end
  local env=setmetatable({Instance={new=instance},UDim=rb.UDim,UDim2=rb.UDim2,Color3=rb.Color3,
   Enum={ScaleType={Fit=1},AutomaticSize={Y=1},SortOrder={LayoutOrder=1},Font={Gotham=1,GothamMedium=2},TextXAlignment={Left=1}}},{__index=getfenv()})
  local UI=luau.load(fs.readFile("src/client/UI/PrematchLobby.luau"),{environment=env})()
  h.state=State.new({sessionId="room",hostUserId=1,hostName="Host",maps={{id="a",name="Alpha"},{id="b",name="Bravo"}},seats={{id="one",label="First",team="Blue"},{id="two",label="Second",team="Red"}}})
  h.state.join(2,"Guest")
  h.presenter=Client.new({sessionId="room",userId=viewer or 1,fetch=function(done:any) done({ok=true,snapshot=h.state.snapshot()}) end,
   send=function(c:any,done:any) h.sent+=1;done(h.state.dispatch(viewer or 1,c)) end})
  h.handle=UI.mount({parent={},presenter=h.presenter,backgroundImage=background,backgroundImagePortrait=portraitImage,onLeave=function() h.left+=1 end})
  function h:click(text:string)
   for _,o in self.objects do if o.ClassName=="TextButton" and o.Text==text and o.Active then o.Activated:fire();return end end
   error("active button missing: "..text)
  end
  h.presenter.refresh()
  return h
 end
 test("prematch actual UI mounts a static Fit background and a visible unconfigured-image label",function()
  local h=fixture();local found=false;local art=false
  for _,o in h.objects do
   if o.ClassName=="ImageLabel" then art=true;eq(o.Image,"");eq(o.ScaleType,1) end
   if o.Text and o.Text:find("STATIC BACKGROUND NOT CONFIGURED",1,true) then found=true end
   assert(o.ClassName~="EditableImage")
  end
  eq(found,true);eq(art,true);h.handle.destroy()
 end)
 test("prematch actual UI pools controls on repeated snapshots and teardown disconnects events",function()
  local h=fixture("rbxassetid://123");local count=#h.objects
  for _=1,10 do h.state.setAvailability("loading","Loading map list");h.presenter.receive(h.state.snapshot());h.state.setAvailability("waiting");h.presenter.receive(h.state.snapshot()) end
  eq(#h.objects,count);h.handle.destroy();for _,c in h.connections do eq(c.dead,true) end
  local n=#h.objects;h.presenter.receive(h.state.snapshot());eq(#h.objects,n)
 end)
 test("prematch actual UI callbacks select map and seat and toggle host Ready",function()
  local h=fixture();h:click("Alpha");eq(h.state.snapshot().mapId,"a")
  h:click("First · Blue · Open");eq(h.state.snapshot().players["1"].seatId,"one")
  h:click("Mark Ready");eq(h.state.snapshot().players["1"].ready,true)
  h:click("Not ready");eq(h.state.snapshot().players["1"].ready,false)
  h:click("Leave lobby");eq(h.left,1)
 end)
 test("prematch actual UI reports start eligibility and emits a single start command",function()
  local h=fixture();h:click("Alpha");h:click("First · Blue · Open")
  local function guest(kind:string,value:any?)
   local c={kind=kind,revision=h.state.snapshot().revision,seatId=value,ready=value}
   assert(h.state.dispatch(2,c).ok);h.presenter.receive(h.state.snapshot())
  end
  guest("seat","two");h:click("Mark Ready");guest("ready",true)
  h:click("Start match");eq(h.state.snapshot().phase,"starting")
  local n=h.sent
  for _,o in h.objects do if o.ClassName=="TextButton" and o.Text=="Starting…" then eq(o.Active,false) end end
  eq(h.sent,n)
 end)
 test("prematch actual UI switches portrait layout on size changes without stretching artwork",function()
  local h=fixture("rbxassetid://123");local backdrop=nil;local panel=nil
  for _,o in h.objects do if o.ClassName=="Frame" and o.Active then backdrop=o elseif o.ClassName=="ScrollingFrame" then panel=o end end
  assert(backdrop and panel);assert(math.abs(panel.Position.X.Scale-.47)<1e-6)
  backdrop.AbsoluteSize=rb.Vector2.new(390,844);backdrop:GetPropertyChangedSignal("AbsoluteSize"):fire()
  assert(math.abs(panel.Position.Y.Scale-.36)<1e-6);assert(math.abs(panel.Size.X.Scale-.94)<1e-6)
 end)

 test("prematch actual guest UI disables host-only map and start controls",function()
  local h=fixture(nil,2);local maps=0;local roles=0
  for _,o in h.objects do
   if o.ClassName=="TextButton" and (o.Text=="Alpha" or o.Text=="Bravo" or o.Text=="Start match") then eq(o.Active,false);maps+=1 end
   if o.ClassName=="TextLabel" and o.Text:find("PLAYER · Choose",1,true) then roles+=1 end
  end
  eq(maps,3);eq(roles,1)
 end)
 test("prematch external screen destruction releases listeners without destroying the presenter",function()
  local h=fixture();for _,o in h.objects do if o.ClassName=="ScreenGui" then o:Destroy() end end
  for _,c in h.connections do eq(c.dead,true) end
  eq(h.presenter.refresh(),true)
 end)

 test("prematch portrait-only static image hides the configuration label after resize",function()
  local h=fixture(nil,nil,"rbxassetid://456");local backdrop=nil;local art=nil;local note=nil
  for _,o in h.objects do
   if o.ClassName=="Frame" and o.Active then backdrop=o end
   if o.ClassName=="ImageLabel" then art=o end
   if o.ClassName=="TextLabel" and o.Text:find("STATIC BACKGROUND NOT CONFIGURED",1,true) then note=o end
  end
  assert(backdrop and art and note);eq(note.Visible,true);eq(art.Image,"")
  backdrop.AbsoluteSize=rb.Vector2.new(390,844);backdrop:GetPropertyChangedSignal("AbsoluteSize"):fire()
  eq(art.Image,"rbxassetid://456");eq(note.Visible,false);eq(art.ScaleType,1)
  assert(math.abs(art.Size.Y.Scale-.34)<1e-6)
 end)

end
