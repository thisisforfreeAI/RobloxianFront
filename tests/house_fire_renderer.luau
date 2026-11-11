--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	if not fs.isFile("src/shared/GameData/FireRules.luau") then return end
	local View=require("../src/shared/Presentation/HouseFireView")
	local ForestView=require("../src/shared/Presentation/ForestFireView")
	local Effects=require("../src/shared/Presentation/FireEffects")
	local Packets=require("../src/shared/Protocol/FirePackets")
	local profile=require("../src/shared/GameData/FireEffectsRules") ::any
	local rules=require("../src/shared/GameData/FireRules") ::any
	local function make():any
		local h:any={time=0,requests={},clears=0,scorchStarts=0,scorchEnds=0,painted={},folders={}}
		local function signal():any
			local s:any={items={}}
			function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.items,c);return c end
			function s:fire() for _,c in self.items do if not c.dead then c.fn() end end end;return s
		end
		h.render=signal()
		local scorch={start=function() h.scorchStarts+=1;return true end,destroy=function() h.scorchEnds+=1 end,apply=function(rows,reset) h.painted=rows;h.reset=reset end}
		local death={request=function(kind,p,tag) table.insert(h.requests,{kind,p,tag}) end,clearTag=function() h.clears+=1 end}
		local modules:any={view=View,forestview=ForestView,effects=Effects,rules=rules,profile=profile,scorch=scorch,death=death,
			town={getForestMap=function() return h.forest end,setForestFates=function(rows,reset) h.treeRows=rows;h.treeReset=reset end},
			fog={hidden=function() return h.hidden==true end},bounds={view=function() return {cx=1,cy=1,rx=10,ry=10,cellPixels=30} end}}
		local data={FindFirstChild=function(_,key) return if h.missing then nil elseif key=="FireRules" then "rules" else "profile" end}
		local shared:any={Presentation={FireEffects="effects",HouseFireView="view",ForestFireView="forestview"},FindFirstChild=function() return data end}
		local env:any=setmetatable({game={GetService=function(_,key) return if key=="RunService" then {RenderStepped=h.render} else {WaitForChild=function() return shared end} end},
			script={Parent={FireScorchRenderer="scorch",DeathRenderer="death",FogOverlay="fog",WorldLight="bounds",TownRenderer="town"}},
			require=function(key) return assert(modules[key],key) end,
			Instance={new=function() local f:any={Destroying=signal()};function f:Destroy() self.Destroying:fire() end;table.insert(h.folders,f);return f end},
			Random={new=function() return {NextNumber=function() return .5 end} end},
			os={clock=function() return h.time end},workspace={CurrentCamera={}}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/HouseFireRenderer.luau"),{environment=env})()
		return h
	end
	test("actual house fire renderer emits roof-anchored shared particles and obeys fog and war pause",function()
		local h=make();assert(h.renderer.start({width=10,height=10,data={id="saddle"}},{}));eq(h.scorchStarts,1)
		h.renderer.syncClock(0,true)
		h.renderer.apply({epoch=1,reset=true,time=0,pixels=Packets.pixels({{141,1}}),actors={{id=1,x=1,y=1,cell=11,r=.3,age=20,life=100,rate=1,points=Packets.points({141})}}})
		eq(h.painted[1][1],141);h.time=.1;h.render:fire();h.time=.4;h.render:fire();assert(#h.requests>0)
		local flames=0;for _,r in h.requests do if r[1]=="spawn" then flames+=1;eq(r[2].x,1.5/14);eq(r[2].y,1.5/14) end end;assert(flames>0)
		h.hidden=true;local before=#h.requests;h.renderer.syncClock(.4,true);h.time=.6;h.render:fire();eq(#h.requests,before)
		h.hidden=false;h.renderer.syncClock(.6,false);h.render:fire();before=#h.requests;h.time=2;h.render:fire();eq(#h.requests,before)
		h.renderer.destroy();eq(h.scorchEnds,1);local clears=h.clears;h.time=3;h.render:fire();eq(h.clears,clears);eq(#h.requests,before)
	end)
	test("house fire renderer skips missing local data and replaces old map sessions without duplicate callbacks",function()
		local h=make();h.missing=true;eq(h.renderer.start({width=10,height=10,data={id="x"}},{}),false);eq(#h.folders,0);eq(h.scorchStarts,0)
		h.missing=false;h.renderer.start({width=10,height=10,data={id="saddle"}},{});h.renderer.start({width=10,height=10,data={id="saddle"}},{});eq(h.scorchEnds,1)
		local active=0;for _,c in h.render.items do if not c.dead then active+=1 end end;eq(active,1)
		h.renderer.destroy();eq(h.scorchEnds,2)
	end)
	test("actual combined fire renderer applies forest fates and emits from tree roots through the shared pool",function()
		local h=make();local t={key=17,x=1,y=1,cell=11,size=.5};h.forest={byKey={[17]=t}}
		h.renderer.start({width=10,height=10,data={id="saddle"}},{});h.renderer.syncClock(0,true)
		h.renderer.applyForest({epoch=1,reset=true,time=0,fates=Packets.trees({{17,{kind="burning",char=1}}}),actors={{key=17,age=20,life=100,rate=1}}})
		eq(h.treeRows[1][1],17);eq(h.treeRows[1][2].char,1);eq(h.treeReset,true)
		h.time=.1;h.render:fire();h.time=.4;h.render:fire();assert(#h.requests>0)
		local n=0;for _,r in h.requests do if r[1]=="spawn" then n+=1;eq(r[2].x,1);eq(r[2].y,1) end end;assert(n>0)
		h.renderer.destroy()
	end)
end
