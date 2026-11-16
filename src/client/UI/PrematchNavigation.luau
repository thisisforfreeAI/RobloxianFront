--!strict
-- Selection/scroll ownership only. Existing GuiButton.Activated handlers remain the action path.
local Navigation = {}
local serial = 0
local fields = {"Selectable", "NextSelectionUp", "NextSelectionDown", "NextSelectionLeft", "NextSelectionRight"}

function Navigation.mount(options:any):any
 local root, panel = options.root, options.panel
 assert(root and panel and panel:IsDescendantOf(root), "root and descendant scrolling panel required")
 local gui = options.guiService or game:GetService("GuiService")
 local input = options.inputService or game:GetService("UserInputService")
 local actions = options.actionService or game:GetService("ContextActionService")
 local enum = options.enums or Enum
 local vector = options.vector2 or Vector2.new
 local dead, active, writing, refreshing = false, true, false, false
 local intent, ownsNil = false, false
 local records, byKey, byButton = {}, {}, {}
 local saved, watches, connections = {}, {}, {}
 local remembered:any = nil
 local prior = gui.SelectedObject
 local self = {}
 serial += 1
 local actionName = "PrematchNavigation_" .. tostring(serial)
 local refresh:any

 local function connect(list:any, signal:any, fn:any)
  table.insert(list, signal:Connect(fn))
 end
 local function disconnect(list:any)
  for _,c in list do c:Disconnect() end
  table.clear(list)
 end
 local function showing(object:any):boolean
  local node = object
  while node do
   if node:IsA("GuiObject") and not node.Visible then return false end
   if node:IsA("ScreenGui") and not node.Enabled then return false end
   if node == root then return true end
   node = node.Parent
  end
  return false
 end
 local function eligible(record:any):boolean
  local b = record.button
  return record.enabled ~= false and b.Parent ~= nil and b:IsDescendantOf(panel)
   and b.Active == true and showing(b)
 end
 local function available():any
  local result = {}
  for _,r in records do if eligible(r) then table.insert(result,r) end end
  return result
 end
 local function validPrior(object:any):boolean
  if not object or not object.Parent or object==root or object:IsDescendantOf(root) or not object:IsA("GuiObject") or not object.Visible or not object.Selectable then return false end
  if object:IsA("GuiButton") and not object.Active then return false end
  local node = object.Parent
  while node do
   if node:IsA("GuiObject") and not node.Visible then return false end
   if node:IsA("ScreenGui") and not node.Enabled then return false end
   node = node.Parent
  end
  return true
 end
 local function selectObject(object:any)
  if gui.SelectedObject == object then return end
  writing = true
  gui.SelectedObject = object
  writing = false
 end
 local function release()
  if gui.MenuIsOpen then ownsNil=false;return end
  local selected = gui.SelectedObject
  if byButton[selected] or (selected == nil and ownsNil) then
   selectObject(if validPrior(prior) then prior else nil)
  end
  ownsNil = false
 end
 local function reveal(button:any)
  if not active or not button or not showing(panel) then return end
  local window = panel.AbsoluteWindowSize.Y
  if window <= 0 then return end
  local margin = math.min(options.scrollMargin or 6, window / 4)
  local top = button.AbsolutePosition.Y - panel.AbsolutePosition.Y
  local bottom = top + button.AbsoluteSize.Y
  local y = panel.CanvasPosition.Y
  local target = y
  if button.AbsoluteSize.Y > window - 2 * margin or top < margin then
   target = y + top - margin
  elseif bottom > window - margin then
   target = y + bottom - window + margin
  end
  target = math.clamp(target, 0, math.max(0,panel.AbsoluteCanvasSize.Y-window))
  if math.abs(target-y) > .01 then panel.CanvasPosition = vector(panel.CanvasPosition.X,target) end
 end
 local function choose(record:any)
  remembered = record.key
  ownsNil = false
  selectObject(record.button)
  reveal(record.button)
 end
 local function fallback(oldOrder:any, key:any, candidates:any):any
  local oldIndex = nil
  for i,r in oldOrder do if r.key == key then oldIndex = i; break end end
  if oldIndex then
   -- Prefer a surviving successor, then predecessor, in the old semantic order.
   for i=oldIndex+1,#oldOrder do
    local r=byKey[oldOrder[i].key]; if r and eligible(r) then return r end
   end
   for i=oldIndex-1,1,-1 do
    local r=byKey[oldOrder[i].key]; if r and eligible(r) then return r end
   end
  end
  return candidates[1]
 end
 refresh = function(oldOrder:any?)
  if dead or refreshing then return end
  refreshing = true
  local candidates = available()
  for _,r in records do r.button.Selectable = active and eligible(r) end
  for i,r in candidates do
   local before=candidates[math.max(1,i-1)].button
   local after=candidates[math.min(#candidates,i+1)].button
   r.button.NextSelectionUp=before; r.button.NextSelectionLeft=before
   r.button.NextSelectionDown=after; r.button.NextSelectionRight=after
  end
  if active and intent and not gui.MenuIsOpen then
   local selected = gui.SelectedObject
   -- Never reclaim focus from an unrelated screen during a state/layout refresh.
   if selected == nil or byButton[selected] then
    local current = byKey[remembered]
    if not current or not eligible(current) then current=fallback(oldOrder or records,remembered,candidates) end
    if current then choose(current)
    else ownsNil=true; selectObject(nil) end
   end
  end
  refreshing = false
 end
 local function watchControls()
  disconnect(watches)
  local seen = {}
  local function watch(object:any, property:string)
   local key = seen[object]
   if not key then key={};seen[object]=key end
   if key[property] then return end
   key[property]=true
   connect(watches,object:GetPropertyChangedSignal(property),function() refresh() end)
  end
  for _,r in records do
   local b=r.button
   watch(b,"Active"); watch(b,"AbsolutePosition"); watch(b,"AbsoluteSize")
   connect(watches,b.AncestryChanged,function() watchControls(); refresh() end)
   local node = b
   while node do
    if node:IsA("GuiObject") then watch(node,"Visible") end
    if node:IsA("ScreenGui") then watch(node,"Enabled") end
    if node == root then break end
    node=node.Parent
   end
  end
  for _,property in {"AbsolutePosition","AbsoluteSize","AbsoluteWindowSize","AbsoluteCanvasSize"} do watch(panel,property) end
 end
 local function restoreButton(button:any)
  local values=saved[button]
  if not values then return end
  -- Destroyed Instances may reject assignment; release the helper's strong references regardless.
  for _,field in fields do pcall(function() button[field]=values[field] end) end
  saved[button]=nil
 end
 function self.setControls(nextRecords:any)
  assert(not dead,"navigation is destroyed")
  assert(type(nextRecords)=="table" and #nextRecords<=64,"at most 64 controls")
  local newRecords,newKeys,newButtons={},{},{}
  for _,r in nextRecords do
   assert(type(r.key)=="string" and #r.key>0 and not newKeys[r.key],"unique stable control keys required")
   assert(r.button and r.button:IsA("GuiButton") and not newButtons[r.button],"unique GuiButtons required")
   local record={key=r.key,button=r.button,enabled=r.enabled}
   table.insert(newRecords,record);newKeys[r.key]=record;newButtons[r.button]=record
  end
  local oldOrder=records
  local selected=gui.SelectedObject
  local owned=byButton[selected]
  if owned then remembered=owned.key end
  disconnect(watches)
  for button in saved do if not newButtons[button] then restoreButton(button) end end
  for _,r in newRecords do
   if not saved[r.button] then
    local values={};for _,field in fields do values[field]=r.button[field] end;saved[r.button]=values
   end
  end
  records,byKey,byButton=newRecords,newKeys,newButtons
  -- A removed control is no longer in byButton, but the old selection was still ours.
  if owned and intent and (not newButtons[selected] or newButtons[selected].key~=owned.key) then ownsNil=true;selectObject(nil) end
  watchControls();refresh(oldOrder)
 end
 function self.refresh() refresh() end
 function self.focus(key:string?):boolean
  if dead or not active or gui.MenuIsOpen or input:GetFocusedTextBox() then return false end
  intent=true
  local record=byKey[key or remembered]
  if not record or not eligible(record) then record=available()[1] end
  if not record then
   if byButton[gui.SelectedObject] then ownsNil=true;selectObject(nil) end
   return false
  end
  choose(record);return true
 end
 function self.step(direction:number,wrap:boolean?):boolean
  if dead or not active or gui.MenuIsOpen or input:GetFocusedTextBox() then return false end
  local candidates=available();if #candidates==0 then return false end
  local selected=gui.SelectedObject;local index=nil
  for i,r in candidates do if r.button==selected then index=i;break end end
  if not index then return self.focus() end
  local target=index+(if direction<0 then -1 else 1)
  if wrap then target=(target-1)%#candidates+1 else target=math.clamp(target,1,#candidates) end
  intent=true;choose(candidates[target]);return true
 end
 function self.setActive(value:boolean)
  if dead or active==value then return end
  if not value then release();intent=false end
  active=value;refresh()
 end
 local function pointer()
  if byButton[gui.SelectedObject] then ownsNil=true;selectObject(nil) end
  intent=false
 end
 if options.controls then self.setControls(options.controls) end
 connect(connections,gui:GetPropertyChangedSignal("SelectedObject"),function()
  if dead or writing or not active then return end
  local selected=gui.SelectedObject
  local record=byButton[selected]
  if record and eligible(record) then
   intent=true;ownsNil=false;remembered=record.key;reveal(record.button)
  elseif record then intent=true;remembered=record.key;refresh()
  elseif selected==nil and intent and remembered and byKey[remembered] and not eligible(byKey[remembered]) then refresh()
  else intent=false;ownsNil=false end
 end)
 connect(connections,input.LastInputTypeChanged,function(kind:any)
  if dead or not active then return end
  if kind==enum.UserInputType.Touch or kind==enum.UserInputType.MouseMovement or kind==enum.UserInputType.MouseButton1 or kind==enum.UserInputType.MouseButton2 or kind==enum.UserInputType.MouseButton3 or kind==enum.UserInputType.MouseWheel then pointer()
  elseif kind.Name:match("^Gamepad") then self.focus() end
 end)
 local function navigate(_:string,state:any,event:any):any
  if dead or not active or gui.MenuIsOpen or not showing(panel) or input:GetFocusedTextBox() or #available()==0 then return enum.ContextActionResult.Pass end
  if state==enum.UserInputState.Begin then
   local key=event.KeyCode
   local back=key==enum.KeyCode.Up or key==enum.KeyCode.Left or key==enum.KeyCode.DPadUp or key==enum.KeyCode.DPadLeft
   if key==enum.KeyCode.Tab then back=input:IsKeyDown(enum.KeyCode.LeftShift) or input:IsKeyDown(enum.KeyCode.RightShift) end
   self.step(if back then -1 else 1,key==enum.KeyCode.Tab)
  end
  return enum.ContextActionResult.Sink
 end
 actions:BindActionAtPriority(actionName,navigate,false,enum.ContextActionPriority.High.Value+1,
  enum.KeyCode.Tab,enum.KeyCode.Up,enum.KeyCode.Down,enum.KeyCode.Left,enum.KeyCode.Right,
  enum.KeyCode.DPadUp,enum.KeyCode.DPadDown,enum.KeyCode.DPadLeft,enum.KeyCode.DPadRight)
 function self.destroy()
  if dead then return end
  release();dead=true
  actions:UnbindAction(actionName)
  disconnect(watches);disconnect(connections)
  for button in saved do restoreButton(button) end
  table.clear(records);table.clear(byKey);table.clear(byButton)
 end
 connect(connections,root.Destroying,self.destroy)
 if input:GetLastInputType().Name:match("^Gamepad") then self.focus() end
 return self
end
return Navigation
