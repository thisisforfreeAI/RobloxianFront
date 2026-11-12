--!strict
-- APPROX port UI: global match discovery. Original multiplayer menu styling is not confirmed.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Client=require(script.Parent.Parent.Lobby.LobbyClient)
local Shared=ReplicatedStorage:WaitForChild("Shared")
local State=require(Shared.Lobby.LobbyBrowserState)
local Protocol=require(Shared.Lobby.LobbyProtocol)
local Browser={}
local current:any=nil
function Browser.isOpen():boolean return current~=nil and current.model.view.open end
function Browser.destroy()
	if not current then return end
	local h=current;current=nil;h.model.destroy();for _,c in h.connections do c:Disconnect() end;h.gui:Destroy()
end
function Browser.start(options:any?)
	Browser.destroy();local h:any={connections={},rows={}};current=h
	local gui=Instance.new("ScreenGui");gui.Name="WarFrontMatches";gui.DisplayOrder=60;gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui");h.gui=gui
	local function connect(signal:any,fn:any) local c=signal:Connect(fn);table.insert(h.connections,c);return c end
	local function text(parent:any,label:string,pos:UDim2,size:UDim2,fontSize:number):any
		local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Text=label;t.TextColor3=Color3.fromRGB(229,235,238);t.Font=Enum.Font.Gotham;t.TextSize=fontSize;t.TextXAlignment=Enum.TextXAlignment.Left;t.TextTruncate=Enum.TextTruncate.AtEnd;t.Position=pos;t.Size=size;t.Parent=parent;return t
	end
	local function button(parent:any,label:string,pos:UDim2,size:UDim2,fn:any):any
		local b=Instance.new("TextButton");b.Text=label;b.Font=Enum.Font.GothamMedium;b.TextSize=13;b.TextColor3=Color3.fromRGB(235,241,243);b.BackgroundColor3=Color3.fromRGB(46,62,67);b.BorderSizePixel=0;b.Position=pos;b.Size=size;b.Parent=parent;connect(b.Activated,fn);return b
	end
	local shade=Instance.new("Frame");shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new();shade.BackgroundTransparency=.3;shade.BorderSizePixel=0;shade.Visible=false;shade.Active=true;shade.Parent=gui
	local panel=Instance.new("Frame");panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5);panel.Size=UDim2.fromScale(.92,.8);panel.BackgroundColor3=Color3.fromRGB(20,28,32);panel.BorderSizePixel=0;panel.Active=true;panel.Parent=shade
	local bounds=Instance.new("UISizeConstraint");bounds.MaxSize=Vector2.new(860,620);bounds.Parent=panel
	text(panel,"MULTIPLAYER MATCHES",UDim2.fromOffset(18,12),UDim2.new(1,-110,0,30),20)
	button(panel,"Close",UDim2.new(1,-82,0,14),UDim2.fromOffset(64,28),function() h.model.setOpen(false) end)
	local openButton:any;local friendButton:any;local statusButton:any
	local function filter(key:string,value:any) local f=table.clone(h.model.view.filter);f[key]=value;h.model.filter(f) end
	local filters=Instance.new("Frame");filters.BackgroundTransparency=1;filters.Position=UDim2.fromOffset(18,54);filters.Size=UDim2.new(1,-36,0,28);filters.Parent=panel
	openButton=button(filters,"Open seats",UDim2.fromOffset(0,0),UDim2.new(.25,-6,1,0),function() filter("hasSpace",not h.model.view.filter.hasSpace) end)
	friendButton=button(filters,"Friends",UDim2.fromScale(.25,0),UDim2.new(.25,-6,1,0),function() filter("friendsOnly",not h.model.view.filter.friendsOnly) end)
	statusButton=button(filters,"All stages",UDim2.fromScale(.5,0),UDim2.new(.25,-6,1,0),function() filter("status",if h.model.view.filter.status then nil else "waiting") end)
	button(filters,"Refresh",UDim2.fromScale(.75,0),UDim2.new(.25,-6,1,0),function() h.model.refresh() end)
	local mapBox=Instance.new("TextBox");mapBox.PlaceholderText="Map name (optional)";mapBox.Text="";mapBox.ClearTextOnFocus=false;mapBox.Font=Enum.Font.Gotham;mapBox.TextSize=13;mapBox.TextColor3=Color3.fromRGB(235,241,243);mapBox.BackgroundColor3=Color3.fromRGB(33,43,48);mapBox.BorderSizePixel=0;mapBox.Position=UDim2.fromOffset(18,90);mapBox.Size=UDim2.new(1,-36,0,28);mapBox.Parent=panel;connect(mapBox.FocusLost,function() filter("map",mapBox.Text) end)
	local note=text(panel,"",UDim2.fromOffset(18,124),UDim2.new(1,-36,0,38),13);note.TextWrapped=true;note.TextTruncate=Enum.TextTruncate.None
	local list=Instance.new("ScrollingFrame");list.BackgroundTransparency=1;list.BorderSizePixel=0;list.Position=UDim2.fromOffset(18,168);list.Size=UDim2.new(1,-36,1,-205);list.ScrollBarThickness=6;list.CanvasSize=UDim2.fromOffset(0,0);list.Active=true;list.Parent=panel
	text(panel,"Lists refresh automatically. Some running matches still have player seats.",UDim2.new(0,18,1,-30),UDim2.new(1,-36,0,20),11)
	local function draw(view:any)
		shade.Visible=view.open;note.Text=if view.loading then view.message.."\nRefreshing matches…" else view.message
		openButton.Text=if view.filter.hasSpace then "✓ Open seats" else "All seats";friendButton.Text=if view.filter.friendsOnly then "✓ Friends" else "Friends";statusButton.Text=if view.filter.status then "Waiting only" else "All stages"
		for i,row in view.rows do
			local r=h.rows[i]
			if not r then
				local root=Instance.new("Frame");root.BackgroundColor3=Color3.fromRGB(31,42,47);root.BorderSizePixel=0;root.Size=UDim2.new(1,-8,0,62);root.Parent=list
				r={root=root,title=text(root,"",UDim2.fromOffset(12,7),UDim2.new(1,-125,0,22),15),detail=text(root,"",UDim2.fromOffset(12,32),UDim2.new(1,-125,0,20),12)}
				r.join=button(root,"Join",UDim2.new(1,-96,.5,-16),UDim2.fromOffset(84,32),function() if r.id then h.model.join(r.id) end end);h.rows[i]=r
			end
			r.id=row.lobbyId;r.root.Visible=true;r.root.Position=UDim2.fromOffset(0,(i-1)*68)
			r.title.Text=if row.name==row.map then tostring(row.map) else tostring(row.name or "Match").."  ·  "..tostring(row.map or "")
			local stage=if row.status=="waiting" then "Waiting" else "In progress"
			r.detail.Text=string.format("%d/%d players  ·  %s%s",tonumber(row.players) or 0,tonumber(row.capacity) or 0,stage,if row.visibility=="friends" then "  ·  Friends" else "")
			local here=row.lobbyId==view.currentLobbyId;r.join.Text=if view.joining==row.lobbyId then "Joining…" elseif here then "Here" elseif row.joinable then "Join" else "No seat"
			r.join.Active=not view.joining and not here and row.joinable==true;r.join.AutoButtonColor=r.join.Active;r.join.BackgroundTransparency=if r.join.Active then 0 else .6
		end
		for i=#view.rows+1,#h.rows do h.rows[i].root.Visible=false;h.rows[i].id=nil end
		list.CanvasSize=UDim2.fromOffset(0,#view.rows*68)
	end
	h.model=State.new({now=os.clock,cooldown=Protocol.BROWSE_COOLDOWN_SEC,changed=draw,
		browse=function(f,done) task.spawn(function() done(Client.browse(f)) end) end,
		join=function(id,done) task.spawn(function() done(Client.join(id)) end) end})
	button(gui,"Matches",UDim2.new(1,-102,0,82),UDim2.fromOffset(92,28),function()
		if not h.model.view.open and options and options.onOpen then options.onOpen() end
		h.model.setOpen(not h.model.view.open)
	end)
	connect(RunService.Heartbeat,h.model.tick)
	task.spawn(function()
		local c=Client.onNotice(h.model.notice)
		if c then if current==h then table.insert(h.connections,c) else c:Disconnect() end end
	end)
	connect(gui.Destroying,function() if current==h then current=nil;h.model.destroy();for _,c in h.connections do c:Disconnect() end end end)
	draw(h.model.view)
end
return Browser
