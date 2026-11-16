--!strict
-- Execute the real helper with event-driven API-shaped stand-ins, not a native Roblox session.
return function(test:any,eq:any)
 local fs=require("@lune/fs");local luau=require("@lune/luau")
 local source=fs.readFile("src/client/UI/PrematchNavigation.luau")
 local function fixture():any
  local h:any={connections={},bindings={},writes=0,activations=0}
  local function signal():any
   local s:any={cs={}}
   function s:Connect(fn:any):any
    local c={fn=fn};function c:Disconnect() self.dead=true end
    table.insert(self.cs,c);table.insert(h.connections,c);return c
   end
   function s:fire(...) for _,c in table.clone(self.cs) do if not c.dead then c.fn(...) end end end
   return s
  end
  local function object(class:string,props:any?):any
   local data=props or {};local signals={};local methods={}
   data.ClassName=class;data.Visible=data.Visible~=false;data.Enabled=data.Enabled~=false
   if data.Active==nil then data.Active=true end
   if data.Selectable==nil then data.Selectable=true end
   data.AncestryChanged=signal();data.Destroying=signal();data.Activated=signal()
   function methods:IsA(name:string):boolean
    return name==class or (name=="GuiButton" and class=="TextButton") or (name=="GuiObject" and table.find({"Frame","ScrollingFrame","TextButton"},class)~=nil)
   end
   function methods:IsDescendantOf(ancestor:any):boolean local node=self.Parent;while node do if node==ancestor then return true end;node=node.Parent end;return false end
   function methods:GetPropertyChangedSignal(key:string):any if not signals[key] then signals[key]=signal() end;return signals[key] end
   return setmetatable({}, {__index=function(_,key)
    if key=="AbsolutePosition" and class=="TextButton" and data.AbsolutePosition and h.panel then
     return {X=data.AbsolutePosition.X,Y=data.AbsolutePosition.Y-(h.panel.CanvasPosition.Y-(data.positionAtCanvasY or 0))}
    end
    return methods[key] or data[key]
   end,
    __newindex=function(self,key,value)
     local old=data[key];data[key]=value
     if key=="AbsolutePosition" and class=="TextButton" and h.panel then data.positionAtCanvasY=h.panel.CanvasPosition.Y end
     if old~=value then
      if class=="GuiService" and key=="SelectedObject" then h.writes+=1 end
      if signals[key] then signals[key]:fire() end
      if key=="Parent" then data.AncestryChanged:fire(self,value) end
     end
    end})
  end
  local function vec(x:number,y:number):any return {X=x,Y=y} end
  h.container=object("PlayerGui")
  h.root=object("ScreenGui",{Parent=h.container,Enabled=true})
  h.panel=object("ScrollingFrame",{Parent=h.root,CanvasPosition=vec(7,0),AbsolutePosition=vec(0,100),AbsoluteSize=vec(500,200),AbsoluteWindowSize=vec(500,200),AbsoluteCanvasSize=vec(500,1000)})
  h.gui=object("GuiService")
  h.input={LastInputTypeChanged=signal(),last={Name="MouseMovement"},shift=false}
  function h.input:GetFocusedTextBox() return self.textbox end
  function h.input:GetLastInputType() return self.last end
  function h.input:IsKeyDown() return self.shift end
  h.actions={}
  function h.actions:BindActionAtPriority(name,fn,touch,priority,...) h.bindings[name]={fn=fn,touch=touch,priority=priority,keys={...}} end
  function h.actions:UnbindAction(name) h.bindings[name]=nil end
  h.enum={KeyCode={},UserInputType={},UserInputState={Begin="Begin",End="End"},ContextActionResult={Pass="Pass",Sink="Sink"},ContextActionPriority={High={Value=3000}}}
  for _,key in {"Tab","Up","Down","Left","Right","DPadUp","DPadDown","DPadLeft","DPadRight","LeftShift","RightShift"} do h.enum.KeyCode[key]=key end
  for _,key in {"Touch","MouseMovement","MouseButton1","MouseButton2","MouseButton3","MouseWheel","Keyboard","Gamepad1"} do h.enum.UserInputType[key]={Name=key} end
  h.records={}
  function h:button(key:string,index:number?):any
   local b=object("TextButton",{Parent=self.panel,AbsolutePosition=vec(10,100+((index or 1)-1)*80),AbsoluteSize=vec(200,36)})
   b.Activated:Connect(function() self.activations+=1 end)
   return {key=key,button=b}
  end
  for i,key in {"map:a","map:b","seat:blue","seat:red","ready","start","retry","leave"} do table.insert(h.records,h:button(key,i)) end
  h.prior=object("TextButton",{Parent=object("ScreenGui",{Parent=h.container})})
  h.gui.SelectedObject=h.prior
  local Module=luau.load(source,{environment=setmetatable({},{__index=getfenv()})})()
  function h:mount(extra:any?):any
   local opts={root=self.root,panel=self.panel,guiService=self.gui,inputService=self.input,actionService=self.actions,enums=self.enum,vector2=vec,controls=self.records}
   for k,v in extra or {} do opts[k]=v end
   return Module.mount(opts)
  end
  function h:press(key:string,state:any?):any
   local _,binding=next(self.bindings);assert(binding)
   return binding.fn("test",state or "Begin",{KeyCode=key})
  end
  function h:inputType(key:string) self.input.last=self.enum.UserInputType[key];self.input.LastInputTypeChanged:fire(self.input.last) end
  function h:watchCount():number local count=0;for _,c in self.connections do if not c.dead then count+=1 end end;return count end
  return h
 end
 test("navigation orders maps seats Ready Start Retry Leave and creates native links",function()
  local h=fixture();local nav=h:mount();eq(h.gui.SelectedObject,h.prior)
  for _,r in h.records do h:press("Tab");eq(h.gui.SelectedObject,r.button) end
  h:press("Tab");eq(h.gui.SelectedObject,h.records[1].button)
  h.input.shift=true;h:press("Tab");eq(h.gui.SelectedObject,h.records[8].button)
  eq(h.records[1].button.NextSelectionUp,h.records[1].button);eq(h.records[8].button.NextSelectionDown,h.records[8].button)
  eq(h.activations,0);nav.destroy()
 end)
 test("navigation skips disabled hidden ancestor-hidden and explicitly disabled controls",function()
  local h=fixture();h.records[2].button.Active=false;h.records[3].button.Visible=false
  h.records[4].enabled=false;local hidden=h:button("hidden").button;hidden.Visible=false;h.records[5].button.Parent=hidden
  local nav=h:mount();nav.focus();eq(h.gui.SelectedObject,h.records[1].button)
  nav.step(1);eq(h.gui.SelectedObject,h.records[6].button)
  for i=2,5 do eq(h.records[i].button.Selectable,false) end
 end)
 test("navigation preserves stable focus and does not rewrite selection after roster redraw",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");local count=h.writes
  nav.setControls(h.records);nav.refresh();eq(h.gui.SelectedObject,h.records[5].button);eq(h.writes,count)
 end)
 test("navigation preserves identity across portrait geometry and keeps it visible",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");h.panel.CanvasPosition={X=7,Y=0}
  h.panel.AbsoluteWindowSize={X=350,Y=120};h.records[5].button.AbsolutePosition={X=10,Y=500}
  nav.refresh();eq(h.gui.SelectedObject,h.records[5].button);eq(h.panel.CanvasPosition.X,7);assert(h.panel.CanvasPosition.Y>0 and h.panel.CanvasPosition.Y<=880)
 end)
 test("navigation disabled selection moves to the next semantic control",function()
  local h=fixture();local nav=h:mount();nav.focus("start");h.records[6].button.Active=false
  eq(h.gui.SelectedObject,h.records[7].button)
  h.records[7].button.Visible=false;eq(h.gui.SelectedObject,h.records[8].button)
 end)
 test("navigation removed selection prefers a surviving successor then predecessor",function()
  local h=fixture();local nav=h:mount();nav.focus("map:b")
  local records=table.clone(h.records);table.remove(records,2);nav.setControls(records)
  eq(h.gui.SelectedObject,h.records[3].button)
  nav.focus("leave");table.remove(records,#records);nav.setControls(records);eq(h.gui.SelectedObject,h.records[7].button)
 end)
 test("navigation pooled button reuse does not mistake a new id for the selected map",function()
  local h=fixture();local nav=h:mount();nav.focus("map:b")
  local records=table.clone(h.records);records[2]={key="map:new",button=records[2].button};nav.setControls(records)
  eq(h.gui.SelectedObject,h.records[3].button)
 end)
 test("navigation stable key moves selection to its replacement instance",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");local records=table.clone(h.records)
  records[5]=h:button("ready",5);nav.setControls(records);eq(h.gui.SelectedObject,records[5].button)
 end)
 test("navigation all disabled clears focus and recovers when a control returns",function()
  local h=fixture();local nav=h:mount();nav.focus("ready")
  for _,r in h.records do r.button.Active=false end;eq(h.gui.SelectedObject,nil)
  h.records[8].button.Active=true;eq(h.gui.SelectedObject,h.records[8].button)
 end)
 test("navigation pointer input relinquishes highlight without blocking Activated",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");h:inputType("Touch");eq(h.gui.SelectedObject,nil)
  h.records[8].button.Activated:fire();eq(h.activations,1);nav.refresh();eq(h.gui.SelectedObject,nil)
  h:inputType("Gamepad1");eq(h.gui.SelectedObject,h.records[5].button)
  h:inputType("MouseMovement");eq(h.gui.SelectedObject,nil)
 end)
 test("navigation arrow DPad and Tab use one event step and leave activation unbound",function()
  local h=fixture();local nav=h:mount();nav.focus("map:a")
  eq(h:press("Down"),"Sink");eq(h.gui.SelectedObject,h.records[2].button)
  h:press("Down","End");eq(h.gui.SelectedObject,h.records[2].button)
  h:press("DPadDown");eq(h.gui.SelectedObject,h.records[3].button)
  h:press("Up");eq(h.gui.SelectedObject,h.records[2].button)
  local _,binding=next(h.bindings);eq(binding.touch,false);assert(not table.find(binding.keys,"ButtonA"));eq(h.activations,0)
 end)
 test("navigation typing inactive or hidden screens pass input through",function()
  local h=fixture();local nav=h:mount();h.input.textbox={};eq(h:press("Tab"),"Pass");eq(h.gui.SelectedObject,h.prior)
  h:inputType("Gamepad1");eq(h.gui.SelectedObject,h.prior);h.input.textbox=nil
  nav.focus();nav.setActive(false);eq(h:press("Down"),"Pass");eq(h.gui.SelectedObject,h.prior)
  nav.setActive(true);h.root.Enabled=false;eq(h:press("Tab"),"Pass")
 end)
 test("navigation external modal selection is not stolen by refresh or teardown",function()
  local h=fixture();local nav=h:mount();nav.focus();local external=h:button("other").button;external.Parent=h.prior.Parent
  h.gui.SelectedObject=external;nav.setControls(h.records);nav.refresh();eq(h.gui.SelectedObject,external)
  nav.destroy();eq(h.gui.SelectedObject,external)
 end)
 test("navigation teardown restores prior selection and all managed properties",function()
  local h=fixture();h.records[1].button.Selectable=false;h.records[1].button.NextSelectionDown=h.prior
  local baseline=h:watchCount();local nav=h:mount();nav.focus();nav.destroy();nav.destroy()
  eq(h.gui.SelectedObject,h.prior);eq(h.records[1].button.Selectable,false);eq(h.records[1].button.NextSelectionDown,h.prior)
  eq(next(h.bindings),nil);eq(h:watchCount(),baseline)
 end)
 test("navigation root destruction does not restore an invalid previous selection",function()
  local h=fixture();local nav=h:mount();nav.focus();h.prior.Parent=nil;h.root.Destroying:fire()
  eq(h.gui.SelectedObject,nil);eq(next(h.bindings),nil)
 end)
 test("navigation selection removal by destruction recovers without polling",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");h.records[5].button.Parent=nil
  eq(h.gui.SelectedObject,h.records[6].button)
 end)
 test("navigation reveal clamps scrolling and handles controls larger than viewport",function()
  local h=fixture();local nav=h:mount();h.records[8].button.AbsolutePosition={X=10,Y=5000};nav.focus("leave")
  eq(h.panel.CanvasPosition.Y,800);h.records[8].button.AbsolutePosition={X=10,Y=-200};h.records[8].button.AbsoluteSize={X=100,Y=600};nav.refresh()
  assert(h.panel.CanvasPosition.Y>=0 and h.panel.CanvasPosition.Y<=800);eq(h.panel.CanvasPosition.X,7)
 end)
 test("navigation cannot register duplicate keys or buttons and bounds the registry",function()
  local h=fixture();local nav=h:mount()
  eq(pcall(nav.setControls,{h.records[1],h.records[1]}),false)
  eq(pcall(nav.setControls,{{key="x",button=h.records[1].button},{key="y",button=h.records[1].button}}),false)
  nav.focus("ready");eq(h.gui.SelectedObject,h.records[5].button)
 end)
 test("navigation watches are replaced rather than accumulated on repeated redraws",function()
  local h=fixture();local nav=h:mount();local count=h:watchCount()
  for _=1,40 do nav.setControls(h.records) end
  eq(h:watchCount(),count);nav.destroy()
 end)
 test("navigation scrolling is minimal idempotent and responds to native stick selection",function()
  local h=fixture();local nav=h:mount();nav.focus("ready")
  eq(h.panel.CanvasPosition.Y,162);local y=h.panel.CanvasPosition.Y
  nav.refresh();eq(h.panel.CanvasPosition.Y,y)
  h.gui.SelectedObject=h.records[8].button;assert(h.panel.CanvasPosition.Y>y)
  nav.refresh();local b=h.records[8].button
  assert(b.AbsolutePosition.Y>=h.panel.AbsolutePosition.Y)
  assert(b.AbsolutePosition.Y+b.AbsoluteSize.Y<=h.panel.AbsolutePosition.Y+h.panel.AbsoluteWindowSize.Y)
 end)
 test("navigation initial gamepad selection skips disabled controls without activating them",function()
  local h=fixture();h.input.last=h.enum.UserInputType.Gamepad1;h.records[1].button.Active=false
  local nav=h:mount();eq(h.gui.SelectedObject,h.records[2].button);eq(h.activations,0);nav.destroy()
 end)
 test("navigation never restores selection into the closing root or a hidden prior screen",function()
  local h=fixture();h.gui.SelectedObject=h.records[1].button
  local nav=h:mount();nav.focus("ready");nav.destroy();eq(h.gui.SelectedObject,nil)
  local h2=fixture();local nav2=h2:mount();nav2.focus();h2.prior.Parent.Enabled=false;nav2.destroy();eq(h2.gui.SelectedObject,nil)
 end)
 test("navigation new ancestor visibility is observed after a control is reparented",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");local group=h:button("group").button
  h.records[5].button.Parent=group;group.Visible=false;eq(h.gui.SelectedObject,h.records[6].button)
 end)
 test("navigation invalid initial registries do not leak action bindings or connections",function()
  local h=fixture();local n=h:watchCount();eq(pcall(function() h:mount({controls={h.records[1],h.records[1]}}) end),false)
  eq(h:watchCount(),n);eq(next(h.bindings),nil)
 end)

 test("navigation mouse wheel can scroll freely after gamepad selection",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");h:inputType("MouseWheel")
  eq(h.gui.SelectedObject,nil);h.panel.CanvasPosition={X=7,Y=0};nav.refresh();eq(h.panel.CanvasPosition.Y,0)
  h:press("Tab");eq(h.gui.SelectedObject,h.records[5].button)
 end)
 test("navigation zero-size viewport waits for geometry and hidden root recovers without activation",function()
  local h=fixture();local nav=h:mount();h.panel.AbsoluteWindowSize={X=0,Y=0};nav.focus("leave");eq(h.panel.CanvasPosition.Y,0)
  h.panel.AbsoluteWindowSize={X=350,Y=200};assert(h.panel.CanvasPosition.Y>0)
  h.root.Enabled=false;eq(h.gui.SelectedObject,nil);h.root.Enabled=true;eq(h.gui.SelectedObject,h.records[8].button);eq(h.activations,0)
 end)
 test("navigation removed controls restore their prior properties and stop receiving watches",function()
  local h=fixture();local nav=h:mount();local b=h.records[1].button;local rest=table.clone(h.records);table.remove(rest,1)
  nav.setControls(rest);eq(b.NextSelectionDown,nil);eq(b.Selectable,true)
  nav.focus("ready");b.Active=false;eq(h.gui.SelectedObject,h.records[5].button)
 end)

 test("navigation native selection of an unavailable registered control is repaired",function()
  local h=fixture();h.records[2].button.Active=false;local nav=h:mount()
  h.gui.SelectedObject=h.records[2].button;eq(h.gui.SelectedObject,h.records[3].button)
 end)

 test("navigation yields to the Roblox core menu and does not restore behind it",function()
  local h=fixture();local nav=h:mount();nav.focus("ready");h.gui.MenuIsOpen=true
  eq(h:press("Down"),"Pass");eq(nav.focus("leave"),false);eq(nav.step(1),false)
  h:inputType("Gamepad1");eq(h.gui.SelectedObject,h.records[5].button)
  nav.destroy();eq(h.gui.SelectedObject,h.records[5].button);eq(next(h.bindings),nil)
 end)

end
