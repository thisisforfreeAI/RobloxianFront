--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau")
	local Motion=require("../src/shared/Presentation/ArtilleryMotion")
	local function fixture():any
		local h:any={time=0,parts={},calls=0,callbacks={}}
		local gui={Destroying={Connect=function(_,fn) table.insert(h.callbacks,fn) end}}
		local gun={attach=function(_,meta,core) local part={cfg=meta.gun,core=core};table.insert(h.parts,part);return part end,
			sync=function(part,built,stale,_,id,base,tint,alpha,light,bank,pose) h.calls+=1;part.pose=pose;part.bank=bank;part.built=built;part.stale=stale end}
		local cfg={rest=-.4,turn=2,raiseSec=.5,holdSec=3,recoilSec=.8,recoilShare=.25,kick=.2,cells=4,gun={-.5,-.25},pod={.5,.25},parts={gun={"g0","g1","g2"},pod={"p0","p1"}},slots={{part="g0"},{part="p0"}}}
		local env=setmetatable({game={GetService=function() return {WaitForChild=function() return {Presentation={ArtilleryMotion="motion"}} end} end},script={Parent={GunRenderer="gun"}},require=function(key) return if key=="motion" then Motion else gun end,os={clock=function() return h.time end}},{__index=getfenv()})
		h.renderer=luau.load(fs.readFile("src/client/Rendering/ArtilleryRenderer.luau"),{environment=env})();h.gui=gui;h.cfg=cfg;h.bank={image={}}
		function h:attach() self.view=self.renderer.attach(self.gui,{frame=32,artillery=self.cfg},{image={}},{0,0,4});return self.view end
		function h:sync(sample,built,stale,bank) self.renderer.sync(self.view,built or 1,stale or false,sample,7,{}, {},0,{},bank) end
		return h
	end
	test("artillery owns two independent mechanisms with shared optional art and no native allocations",function()
		local h=fixture();h:attach();eq(#h.parts,2);eq(h.parts[1].cfg.part,"g0");eq(h.parts[2].cfg.part,"p0")
		h:sync({1,1,1,{0,0,0,0,{}},{0,0,0,0,{}}},1,false,h.bank)
		h.time=.1;h:sync({1,2,1,{1,10,10,2,{2}},{0,0,0,0,{}}},1,false,h.bank)
		eq(h.parts[1].pose.part,"g2");eq(h.parts[2].pose.part,"p0");eq(h.parts[1].bank,h.bank);eq(h.parts[2].bank,h.bank)
		h.time=.15;h.renderer.step();assert(h.parts[1].pose.kick>0);eq(#h.parts,2)
		eq(h.renderer.attach(h.gui,{frame=32},{},{}),nil)
	end)
	test("artillery fog and offscreen expiry clear observed schedules before reveal",function()
		local h=fixture();local view=h:attach();local idle={1,1,1,{0,0,0,0,{}},{0,0,0,0,{}}};local shot={1,2,1,{1,10,10,2,{2}},{0,0,0,0,{}}}
		h:sync(idle,1,false,h.bank);h.time=.1;h:sync(shot,1,false,h.bank);assert(h.parts[1].pose.kick>0)
		h:sync(shot,1,true,nil);eq(h.parts[1].pose.kick,0);eq(view.state.slots[1].sequence,nil);eq(h.parts[1].stale,true)
		h:sync(shot,1,false,h.bank);eq(h.parts[1].pose.kick,0)
		h.time=1;local before=h.calls;h.renderer.step();eq(view.at,nil);eq(view.state.slots[1].sequence,nil);eq(h.calls,before)
		h:sync(shot,.5,false,h.bank);eq(view.state.slots[1].sequence,nil);eq(h.parts[1].built,.5)
	end)
	test("artillery does not rebind a reclaimed page and releases clock owners on teardown",function()
		local h=fixture();h:attach();h:sync({1,1,1,{0,0,0,0,{}},{0,0,0,0,{}}},1,false,h.bank)
		h.renderer.forgetSheet(h.bank.image);h.time=.1;h.renderer.step();eq(h.parts[1].bank,nil);eq(h.parts[2].bank,nil)
		for _,fn in h.callbacks do fn() end;eq(h.renderer.count(),0)
		h:attach();h:sync(nil,1,false,nil);eq(h.renderer.count(),1);h.renderer.reset();eq(h.renderer.count(),0)
		local before=h.calls;h.time=.2;h.renderer.step();eq(h.calls,before)
	end)
end
