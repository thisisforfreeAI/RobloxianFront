--!strict
return function(test:any,eq:any)
	local Model=require("../src/shared/Lobby/LobbyBrowserState")
	local function fixture()
		local h:any={t=0,browses={},joins={},draws=0}
		h.model=Model.new({now=function() return h.t end,changed=function() h.draws+=1 end,
			browse=function(f,done) table.insert(h.browses,{filter=f,done=done}) end,join=function(id,done) table.insert(h.joins,{id=id,done=done}) end})
		function h:reply(index,rows) self.browses[index].done({ok=true,lobbies=rows or {{lobbyId="b",joinable=true,expiresIn=60}},refreshAfter=10,currentLobbyId="a"}) end
		return h
	end
	test("browser only refreshes while open and respects shared request cooldowns",function()
		local h=fixture();h.model.tick();eq(#h.browses,0);h.model.setOpen(true);eq(#h.browses,1)
		h.model.refresh();eq(#h.browses,1);h:reply(1);h.t=9;h.model.tick();eq(#h.browses,1)
		h.t=10;h.model.tick();eq(#h.browses,2);h.model.setOpen(false);h.t=30;h.model.tick();eq(#h.browses,2)
	end)
	test("older replies cannot replace a newer filter or reopen a closed browser",function()
		local h=fixture();h.model.setOpen(true);h.model.filter({map="Twin",hasSpace=true});h.model.tick();eq(#h.browses,1)
		h.t=2;h.model.tick();eq(#h.browses,2);eq(h.browses[2].filter.map,"Twin")
		h:reply(2,{{lobbyId="twin"}});h:reply(1);eq(h.model.view.rows[1].lobbyId,"twin")
		h.model.setOpen(false);h:reply(2);eq(h.model.view.open,false)
	end)
	test("missing, expired, full and current-server rows cannot initiate a teleport",function()
		local h=fixture();h.model.setOpen(true);h:reply(1,{{lobbyId="a",joinable=true,expiresIn=60},{lobbyId="full",joinable=false,expiresIn=60},{lobbyId="old",joinable=true,expiresIn=1}})
		eq(h.model.join("a"),false);eq(h.model.join("full"),false);eq(h.model.join("missing"),false);h.t=2;eq(h.model.join("old"),false);eq(#h.joins,0)
	end)
	test("joining is single flight and a failed result leaves a useful message after refresh",function()
		local h=fixture();h.model.setOpen(true);h:reply(1);eq(h.model.join("b"),true);eq(h.model.join("b"),false);eq(h.model.setOpen(false),false)
		h.joins[1].done({ok=false,message="That lobby is full.",retry=true});eq(h.model.view.joining,nil)
		h.t=2;h.model.tick();h:reply(2,{});eq(h.model.view.message,"That lobby is full.");eq(h.model.setOpen(false),true)
	end)
	test("a failure notice beats an earlier outstanding join reply",function()
		local h=fixture();h.model.setOpen(true);h:reply(1);h.model.join("b")
		h.model.notice({reason="teleportFailed",message="Try again."});h.joins[1].done({ok=true,route="teleport"})
		eq(h.model.view.joining,nil);eq(h.model.view.message,"Try again.")
	end)
	test("teleport confirmation waits for travel or failure, with a bounded timeout",function()
		local h=fixture();h.model.setOpen(true);h:reply(1);h.model.join("b");h.joins[1].done({ok=true,route="teleport"})
		h.t=20;h.model.tick();eq(h.model.view.joining,"b");eq(#h.browses,1)
		h.t=66;h.model.tick();eq(h.model.view.joining,nil);eq(#h.browses,2)
	end)
	test("destroy ignores all delayed browse, join and notice callbacks",function()
		local h=fixture();h.model.setOpen(true);h:reply(1);h.model.join("b");h.model.destroy();local n=h.draws
		h.joins[1].done({ok=true,route="teleport"});h:reply(1);h.model.notice({reason="teleportFailed"});h.model.tick();eq(h.draws,n);eq(h.model.view.open,false)
	end)
	local function uiFixture()
		local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
		local h:any={t=0,instances={},joins={},rows={{lobbyId="b",name="Saddle",map="Saddle",players=1,capacity=2,status="waiting",joinable=true,expiresIn=60}},opened=0}
		local function signal() local s:any={cs={}};function s:Connect(fn) local c={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.cs,c);return c end;function s:fire(...) for _,c in self.cs do if not c.dead then c.fn(...) end end end;return s end
		local function instance(class) local o:any={ClassName=class,Activated=signal(),FocusLost=signal(),Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,c in h.instances do if c.Parent==self then c:Destroy() end end end;table.insert(h.instances,o);return o end
		h.gui=instance("PlayerGui");h.beat=signal();h.notice=signal()
		local shared={Lobby={LobbyBrowserState="state",LobbyProtocol="protocol"}}
		local client={browse=function() return {ok=true,lobbies=h.rows,currentLobbyId="a",refreshAfter=10} end,join=function(id) table.insert(h.joins,id);return {ok=false,message="Full. Refresh."} end,onNotice=function(fn) return h.notice:Connect(fn) end}
		local services={Players={LocalPlayer={WaitForChild=function() return h.gui end}},RunService={Heartbeat=h.beat},ReplicatedStorage={WaitForChild=function() return shared end}}
		local env=setmetatable({game={GetService=function(_,k) return services[k] end},script={Parent={Parent={Lobby={LobbyClient="client"}}}},require=function(k) return if k=="state" then Model elseif k=="protocol" then {BROWSE_COOLDOWN_SEC=2} else client end,
			Instance={new=instance},Color3=rb.Color3,UDim2=rb.UDim2,Vector2=rb.Vector2,Enum={Font={Gotham=1,GothamMedium=2},TextXAlignment={Left=1},TextTruncate={AtEnd=1,None=0}},task={spawn=function(fn) fn() end},os={clock=function() return h.t end}},{__index=getfenv()})
		h.ui=luau.load(fs.readFile("src/client/UI/LobbyBrowser.luau"),{environment=env})();h.ui.start({onOpen=function() h.opened+=1 end})
		function h:button(label) for _,o in self.instances do if not o.dead and o.ClassName=="TextButton" and o.Text==label then return o end end;error(label) end
		return h
	end
	test("actual browser row callbacks follow refreshed targets and expose join failure text",function()
		local h=uiFixture();h:button("Matches").Activated:fire();eq(h.ui.isOpen(),true);eq(h.opened,1)
		h.rows={{lobbyId="c",name="Twin",map="Twin",players=1,capacity=2,status="inProgress",joinable=true,expiresIn=60}};h.t=2;h:button("Refresh").Activated:fire()
		h:button("Join").Activated:fire();eq(h.joins[1],"c")
		local found=false;for _,o in h.instances do if o.Text=="Full. Refresh." then found=true end end;assert(found)
	end)
	test("actual browser close and destruction release polling, notices and native UI owners",function()
		local h=uiFixture();h:button("Matches").Activated:fire();h:button("Close").Activated:fire();eq(h.ui.isOpen(),false)
		h.ui.destroy();for _,c in h.beat.cs do eq(c.dead,true) end;for _,c in h.notice.cs do eq(c.dead,true) end
		for _,o in h.instances do if o.ClassName=="ScreenGui" then eq(o.dead,true) end;assert(o.ClassName~="EditableImage") end
		h.t=100;h.beat:fire();h.notice:fire({reason="teleportFailed"});eq(h.ui.isOpen(),false)
	end)
end
