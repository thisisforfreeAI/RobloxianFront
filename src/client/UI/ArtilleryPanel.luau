--!strict
-- Click-selected artillery commands. APPROX port layout; gameplay values come from match rules.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Model=require(Shared.Presentation.ArtilleryControls)
local Panel={}
local current:any=nil
local function text(parent:any,size:number):TextLabel
	local item=Instance.new("TextLabel");item.BackgroundTransparency=1;item.TextColor3=Color3.fromRGB(236,239,242);item.Font=Enum.Font.Gotham;item.TextSize=size;item.TextWrapped=true;item.Parent=parent;return item
end
local function button(parent:any):TextButton
	local item=Instance.new("TextButton");item.BackgroundColor3=Color3.fromRGB(48,73,91);item.TextColor3=Color3.new(1,1,1);item.Font=Enum.Font.GothamBold;item.TextSize=13;item.BorderSizePixel=0;item.Parent=parent;return item
end
local function blocked(h:any):boolean return h.opts.blocked~=nil and h.opts.blocked() end
local function refresh(h:any)
	if h~=current then return end
	Model.expire(h.model,os.clock())
	local v=Model.base(h.model,h.opts.views())
	if not v then Model.pick(h.model,nil,nil) end
	if blocked(h) then Model.cancel(h.model) end
	h.card.Visible=v~=nil and not blocked(h)
	if not v then return end
	h.title.Text="Artillery Base"
	for kind,item in h.buttons do
		local why=Model.reason(h.model,h.opts.views(),kind)
		local name=if kind=="barrage" then "Barrage" else "Flares"
		item.Text=`{name} · {h.opts.rules["artyBase."..kind..".price"]} kills{if why then "\n"..why else ""}`
		item.Active=why==nil;item.AutoButtonColor=why==nil;item.BackgroundColor3=if why then Color3.fromRGB(44,49,54) else Color3.fromRGB(48,73,91)
	end
	h.status.Text=if h.model.note~="" then h.model.note else `Kills available: {h.model.kills} · choose a strike`
	h.cancel.Visible=h.model.mode~=nil
end
function Panel.destroy()
	local h=current;current=nil;if not h then return end
	if h.connection then h.connection:Disconnect() end
	h.gui:Destroy()
end
function Panel.start(opts:any)
	Panel.destroy();local player=Players.LocalPlayer;local parent=player and player:FindFirstChild("PlayerGui");if not parent then return end
	local gui=Instance.new("ScreenGui");gui.Name="ArtilleryCommands";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=2;gui.Parent=parent
	local card=Instance.new("Frame");card.Name="ArtilleryCommands";card.AnchorPoint=Vector2.new(.5,1);card.Position=UDim2.new(.5,0,1,-18);card.Size=UDim2.new(1,-24,0,166);card.BackgroundColor3=Color3.fromRGB(19,26,33);card.BorderSizePixel=0;card.Visible=false;card.Active=true;card.Parent=gui
	local limit=Instance.new("UISizeConstraint");limit.MaxSize=Vector2.new(390,166);limit.Parent=card
	local title=text(card,16);title.Position=UDim2.fromOffset(12,8);title.Size=UDim2.new(1,-54,0,24)
	local close=button(card);close.Text="×";close.Position=UDim2.new(1,-36,0,8);close.Size=UDim2.fromOffset(26,24)
	local status=text(card,12);status.Position=UDim2.fromOffset(12,106);status.Size=UDim2.new(1,-24,0,30)
	local cancel=button(card);cancel.Text="Cancel target";cancel.Position=UDim2.new(.5,-65,1,-27);cancel.Size=UDim2.fromOffset(130,20);cancel.Visible=false
	local h:any={opts=opts,gui=gui,card=card,title=title,status=status,cancel=cancel,buttons={},model=Model.new(opts.side,opts.rules)};current=h
	for i,kind in {"barrage","flare"} do
		local b=button(card);b.Name=kind;b.Position=UDim2.new((i-1)*.5,12,0,40);b.Size=UDim2.new(.5,-18,0,58);h.buttons[kind]=b
		b.Activated:Connect(function()
			if h~=current or blocked(h) then return end
			Model.arm(h.model,opts.views(),kind);refresh(h)
		end)
	end
	close.Activated:Connect(function() if h==current then Model.pick(h.model,nil,nil);refresh(h) end end)
	cancel.Activated:Connect(function() if h==current then Model.cancel(h.model);refresh(h) end end)
	local elapsed=0;h.connection=RunService.Heartbeat:Connect(function(dt) elapsed+=dt;if elapsed>=.1 then elapsed=0;refresh(h) end end)
	gui.Destroying:Connect(function() if h.connection then h.connection:Disconnect();h.connection=nil end;if current==h then current=nil end end)
end
function Panel.select(id:number?,kind:string?) if current then Model.pick(current.model,id,kind);refresh(current) end end
function Panel.update(state:any) if current then Model.update(current.model,state);refresh(current) end end
function Panel.cancel() if current then Model.cancel(current.model);refresh(current) end end
function Panel.targeting():boolean
	local h=current;if not h then return false end
	if blocked(h) then Model.cancel(h.model);return false end
	return h.model.mode~=nil
end
function Panel.target(x:number,y:number)
	local h=current;if not h or blocked(h) then return end
	local payload=Model.fire(h.model,h.opts.views(),x,y,os.clock());if payload then h.opts.send(payload) end;refresh(h)
end
return Panel
