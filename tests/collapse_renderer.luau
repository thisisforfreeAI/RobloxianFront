--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local Events=require("../src/shared/Protocol/CollapseEvents")
	test("actual server snapshot filters collapse rows per side and discards them after one send",function()
		local code=fs.readFile("src/server/Match/MatchService.luau");local a=assert(string.find(code,"local function snapshot()",1,true));local b=assert(string.find(code,"-- Own territory",a,true))
		local one,two,spectator={},{},{};local queue={};local sent={};local ready={[one]=true,[spectator]=true}
		Events.push(queue,{type="destroyed",cat="structure",id=1,kind="factory",x=2,y=2},20,16)
		Events.push(queue,{type="destroyed",cat="structure",id=2,kind="hq",x=8,y=2},20,16)
		local env=setmetatable({sideOf={[one]=1,[two]=2,[spectator]=0},viewFor=function() return {},{},{1,2,3} end,tick=10,readyView=ready,
			viewers={[1]={visibleAt=function(x) return x<5 end},[2]={visibleAt=function(x) return x>5 end}},sim={fogOn=function() return true end},
			deaths={},collapses=queue,sentVision={},CollapseEvents=Events,Net={sendSnapshot=function(player,_tick,_units,_structures,_vision,_all,_deaths,rows) sent[player]=rows or false end}},{__index=getfenv()})
		local snapshot=luau.load(string.sub(code,a,b-1).."\nreturn snapshot",{environment=env})()
		snapshot();eq(#sent[one],1);eq(sent[one][1][1],1);eq(sent[two],false);eq(#sent[spectator],2);eq(#queue,0)
		ready[two]=true;snapshot();eq(sent[one],false);eq(sent[two],false);eq(sent[spectator],false)
	end)
	test("actual client snapshot applies current fog before collapse births",function()
		local code=fs.readFile("src/client/init.client.luau");local a=assert(string.find(code,"snapshot.OnClientEvent:Connect",1,true));local b=assert(string.find(code,"-- Both listeners",a,true))
		local callback,updated,received=nil,false,nil
		local env=setmetatable({snapshot={OnClientEvent={Connect=function(_,fn) callback=fn end}},UnitRenderer={apply=function() end},CivilianRenderer={snapshot=function() end},StructureRenderer={apply=function() end},
			FogOverlay={apply=function() updated=true end},CollapseRenderer={apply=function(tick,rows) assert(updated);eq(tick,10);received=rows end}},{__index=getfenv()})
		luau.load(string.sub(code,a,b-1),{environment=env})();local rows={{1,"hq",2,3}};callback(10,{},{},{},false,nil,rows);eq(received,rows)
	end)
	if not fs.isFile("src/shared/GameData/CollapseFx.luau") then return end
	local config=require("../src/shared/GameData/CollapseFx")
	local function make():any
		local h:any={requests={},instances={},warnings=0,loads=0,clears=0,view={cx=10,cy=8,rx=5,ry=5}}
		local function signal()
			local s:any={items={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire(dt) for _,c in table.clone(self.items) do if not c.dead then c.fn(dt) end end end;return s
		end
		local function instance(class)
			local o:any={ClassName=class,Destroying=signal()};function o:Destroy() if self.dead then return end;self.dead=true;self.Destroying:fire();for _,child in h.instances do if child.Parent==self then child:Destroy() end end end
			table.insert(h.instances,o);return o
		end
		local data={FindFirstChild=function() return if h.missing then nil else "config" end}
		local shared={Presentation={CollapseEffects="effects"},Protocol={CollapseEvents="events"},FindFirstChild=function() return data end}
		local modules={effects=require("../src/shared/Presentation/CollapseEffects"),events=Events,death={request=function(kind,p,tag)
			if h.fail then error("synthetic shared particle failure") end;table.insert(h.requests,{kind=kind,p=p,tag=tag});return true end,
			clearTag=function(tag) h.clears+=1;h.lastClear=tag end},fog={hidden=function() return h.hidden==true end},light={view=function() return h.view end}}
		h.heartbeat=signal();h.parent=instance("Folder")
		local env=setmetatable({game={GetService=function(_,name) return if name=="RunService" then {Heartbeat=h.heartbeat} else {WaitForChild=function() return shared end} end},
			script={Parent={DeathRenderer="death",FogOverlay="fog",WorldLight="light"}},Instance={new=instance},workspace={CurrentCamera={}},warn=function() h.warnings+=1 end,
			require=function(key) if key=="config" then h.loads+=1;return if h.badConfig then {} else config end;return assert(modules[key],key) end},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/CollapseRenderer.luau"),{environment=env})()
		function h.start() h.renderer.start({width=20,height=16},h.parent) end
		function h.step() h.heartbeat:fire(.05) end
		return h
	end
	test("actual collapse renderer stays lazy deduplicates snapshot ticks and cancels reset timers",function()
		local h=make();h.start();eq(h.loads,0);h.renderer.apply(1,nil);eq(h.loads,0)
		h.renderer.apply(2,{{1,"factory",10,8}});assert(#h.requests>0);eq(h.loads,1)
		local n=#h.requests;h.renderer.apply(2,{{1,"factory",10,8}});h.renderer.apply(1,{{1,"factory",10,8}});eq(#h.requests,n)
		for _=1,8 do h.step() end;assert(#h.requests>n)
		h.renderer.reset();n=#h.requests;for _=1,100 do h.step() end;eq(#h.requests,n);assert(h.lastClear)
		h.parent:Destroy();for _,c in h.heartbeat.items do assert(c.dead) end
		h.renderer.apply(20,{{2,"hq",10,8}});eq(#h.requests,n);eq(h.warnings,0)
	end)
	test("actual collapse renderer rejects hidden distant malformed and old-map requests",function()
		local h=make();h.start();h.hidden=true;h.renderer.apply(1,{{1,"hq",10,8}});eq(#h.requests,0)
		h.hidden=false;h.view.cx=100;h.renderer.apply(2,{{2,"hq",10,8}});eq(#h.requests,0)
		h.view.cx=10;h.renderer.apply(3,{{3,"factory",10,8}});assert(#h.requests>0)
		h.hidden=true;local n=#h.requests;for _=1,8 do h.step() end;eq(#h.requests,n)
		h.renderer.apply(4,{{4,"factory",0/0,8}});eq(#h.requests,n)
		h.start();h.hidden=false;for _=1,8 do h.step() end;eq(#h.requests,n);h.parent:Destroy()
	end)
	test("missing malformed and failing collapse effects stop once without repeated frame errors",function()
		for _,failure in {"missing","badConfig","fail"} do
			local h=make();h[failure]=true;h.start();h.renderer.apply(1,{{1,"factory",10,8}});eq(h.warnings,1)
			for i=2,20 do h.renderer.apply(i,{{i,"factory",10,8}});h.step() end
			eq(h.warnings,1);assert(h.loads<=1);h.parent:Destroy()
		end
	end)
end
