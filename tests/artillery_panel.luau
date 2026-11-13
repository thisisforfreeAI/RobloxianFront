--!strict
return function(test:any,eq:any)
 local fs=require('@lune/fs');local luau=require('@lune/luau');local rb=require('@lune/roblox');local Model=require('../src/shared/Presentation/ArtilleryControls')
 local function signal() local s:any={cs={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.cs,c);return c end;function s:fire(...) for _,c in table.clone(self.cs) do if not c.dead then c.fn(...) end end end;return s end
 local function uiFixture()
  local h:any={t=0,instances={},sent={},views={[7]={id=7,kind='artybase',side=1,hp=100,built=1,x=10,y=10}}}
  local function instance(class) local o:any={ClassName=class,Activated=signal(),Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end;table.insert(h.instances,o);return o end
  h.playerGui=instance('PlayerGui');h.beat=signal();local shared={Presentation={ArtilleryControls='model'}}
  local env=setmetatable({game={GetService=function(_,key) return if key=='Players' then {LocalPlayer={FindFirstChild=function() return h.playerGui end}} elseif key=='RunService' then {Heartbeat=h.beat} else {WaitForChild=function() return shared end} end},
   require=function() return Model end,Instance={new=instance},Color3=rb.Color3,Vector2=rb.Vector2,UDim2=rb.UDim2,Enum={Font={Gotham=1,GothamBold=2}},os={clock=function() return h.t end}},{__index=getfenv()})
  h.panel=luau.load(fs.readFile('src/client/UI/ArtilleryPanel.luau'),{environment=env})();h.opts={side=1,rules={['artyBase.barrage.price']=15,['artyBase.flare.price']=3,['artyBase.range']=100},views=function() return h.views end,send=function(i) table.insert(h.sent,i) end,blocked=function() return h.blocked==true end}
  function h:start() h.panel.start(h.opts);h.panel.update({oil=100,kills=30,artyBases={{7,0,0,false}}});h.panel.select(7,'artybase') end
  function h:find(name) for _,o in h.instances do if not o.dead and (o.Name==name or o.Text==name) then return o end end;error(name) end
  h:start();return h
 end
 test('actual artillery panel buttons arm a world target with no images and send one selected-base request',function()
  local h=uiFixture();local card;for _,o in h.instances do if o.ClassName=='Frame' then card=o end end;assert(card.Visible);eq(card.Active,true)
  h:find('barrage').Activated:fire();eq(h.panel.targeting(),true);eq(#h.sent,0);h.panel.target(15,16);eq(#h.sent,1);eq(h.sent[1].structureId,7);eq(h.sent[1].x,15);eq(h.panel.targeting(),false)
  h.panel.target(15,16);eq(#h.sent,1);for _,o in h.instances do assert(o.ClassName~='EditableImage') end;h.panel.destroy()
 end)
 test('panel blocks cooldown and modal actions, clears vanished ownership and disconnects on restart/teardown',function()
  local h=uiFixture();h.panel.update({artyBases={{7,4,0,false}}});h:find('barrage').Activated:fire();eq(h.panel.targeting(),false);eq(h:find('barrage').Active,false)
  h:find('flare').Activated:fire();eq(h.panel.targeting(),true);h.blocked=true;eq(h.panel.targeting(),false);h.panel.target(15,15);eq(#h.sent,0);h.blocked=false
  h.panel.select(7,'artybase');h:find('flare').Activated:fire();h.views[7].side=2;h.panel.target(15,15);eq(#h.sent,0)
  h.views[7].side=1;local old=h:find('flare');h:start();eq(old.dead,true);old.Activated:fire();eq(h.panel.targeting(),false);h.panel.destroy();h.beat:fire(.2);eq(h.panel.targeting(),false)
  for _,c in h.beat.cs do eq(c.dead,true) end
 end)
 test('panel timeout and right-click-equivalent cancellation retain useful server result handling',function()
  local h=uiFixture();h:find('flare').Activated:fire();h.panel.cancel();eq(h.panel.targeting(),false);h:find('flare').Activated:fire();h.panel.target(12,12)
  h.t=6;h.beat:fire(.2);h:find('flare').Activated:fire();eq(h.panel.targeting(),true);h.panel.destroy()
 end)
 local function selectionFixture()
  local h:any={mouse=rb.Vector2.new(40,40),units={},structures={[7]={id=7,kind='artybase',side=1,x=10,y=10}},targets={},sent={},picks={}}
  local input={InputBegan=signal(),InputEnded=signal(),InputChanged=signal(),IsKeyDown=function() return false end,GetMouseLocation=function() return h.mouse end};h.input=input
  local render={UnitRenderer='units',StructureRenderer='structures',CityOverlay='city',RoadOverlay='road'}
  local world={STUDS_PER_CELL=4,toWorld=function(x,y,z) return rb.Vector3.new(x*4,z or 0,y*4) end,toCell=function(p) return p.X/4,p.Z/4 end}
  local shared={Config={World='world'},Protocol={Protocol='protocol'}}
  local modules={world=world,protocol={MAX_UNITS_PER_ORDER=256},units={each=function() return h.units end,setSelected=function(s) h.selected=table.clone(s) end},structures={each=function() return h.structures end,setFocus=function(id) h.focus=id end},city={pick=function() end},road={},groups={new=function() return {} end}}
  local camera={WorldToViewportPoint=function(_,p) return rb.Vector3.new(p.X,p.Z,1),true end,ViewportPointToRay=function() return {Origin=rb.Vector3.zero,Direction=rb.Vector3.new(0,-1,0)} end,ViewportSize=rb.Vector2.new(800,600)}
  local workspace={CurrentCamera=camera,FindFirstChild=function() return {FindFirstChild=function() return {} end} end,Raycast=function() return if h.noHit then nil else {Position=rb.Vector3.new(80,0,100)} end};h.workspace=workspace
  local keys=setmetatable({},{__index=function(_,k) return k end});local services={Players={LocalPlayer={WaitForChild=function() return {} end}},ReplicatedStorage={WaitForChild=function() return shared end},UserInputService=input}
  local env=setmetatable({game={GetService=function(_,k) return services[k] end},script={Parent={ControlGroups='groups',Parent={Rendering=render}}},require=function(k) return modules[k] end,Instance={new=function() return {} end},workspace=workspace,RaycastParams={new=function() return {} end},Enum={KeyCode=keys,UserInputType={MouseButton1='left',MouseButton2='right',MouseMovement='move'},RaycastFilterType={Include=1}},Color3=rb.Color3,Vector2=rb.Vector2,UDim2=rb.UDim2},{__index=getfenv()})
  local controller=luau.load(fs.readFile('src/client/Input/SelectionController.luau'),{environment=env})();local noop=function() end
  controller.start(1,function(i) table.insert(h.sent,i) end,{busy=function() return h.blocked end,onProducer=noop,digLine=noop,cycleTrench=noop,note=noop,lookAt=noop,openRig=noop,
   onStructure=function(id,kind) table.insert(h.picks,{id,kind}) end,targeting=function() return h.armed end,target=function(x,y) table.insert(h.targets,{x,y});h.armed=false end,cancelTarget=function() h.armed=false end})
  function h:begin(kind,key,processed) input.InputBegan:fire({UserInputType=kind,KeyCode=key or 'unknown'},processed or false) end
  function h:finish() input.InputEnded:fire({UserInputType='left'}) end
  return h
 end
 test('actual selection opens an owned artillery base while armed left clicks target without selecting or ordering',function()
  local h=selectionFixture();h:begin('left');h:finish();eq(h.picks[1][1],7);eq(h.picks[1][2],'artybase')
  h.armed=true;h:begin('left');h:finish();eq(#h.targets,1);eq(h.targets[1][1],20);eq(h.targets[1][2],25);eq(#h.picks,1);eq(#h.sent,0)
 end)
 test('actual target routing ignores processed and blocked clicks and cancels with right-click or Escape',function()
  local h=selectionFixture();h.armed=true;h:begin('left',nil,true);eq(#h.targets,0);h.blocked=true;h:begin('left');eq(#h.targets,0);h.blocked=false
  h:begin('right');eq(h.armed,false);eq(#h.sent,0);h.armed=true;h:begin('key','Escape');eq(h.armed,false)
  h.armed=true;h.noHit=true;h:begin('left');eq(#h.targets,0);h.workspace.CurrentCamera=nil;h.noHit=false;h:begin('left');eq(#h.targets,0)
 end)
 test('a selection drag begun before a modal or target mode cannot finish as a stray building selection',function()
  local h=selectionFixture();h:begin('left');h.blocked=true;h:finish();eq(#h.picks,0);h.blocked=false
  h:begin('left');h.armed=true;h:finish();eq(#h.picks,0);eq(#h.targets,0)
 end)
 test('close artillery footprint corners open the panel beyond the old forty-pixel centre tolerance',function()
  local h=selectionFixture();h.structures[7].block={Size=rb.Vector3.new(120,.02,120)};h.mouse=rb.Vector2.new(90,90);h:begin('left');h:finish();eq(h.picks[1][1],7)
 end)

end

