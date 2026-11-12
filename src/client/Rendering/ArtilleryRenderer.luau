--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Motion=require(ReplicatedStorage:WaitForChild("Shared").Presentation.ArtilleryMotion)
local Gun=require(script.Parent.GunRenderer)
local Renderer={}
local views:{[any]:boolean}={}
function Renderer.attach(gui:any,meta:any,core:any,origin:any):any
	local cfg=meta.artillery;if not cfg then return nil end
	local h:any={cfg=cfg,state=Motion.new(cfg),origin=origin,parts={},last=0}
	for _,slot in cfg.slots do table.insert(h.parts,Gun.attach(gui,{frame=meta.frame,gun=slot},core)) end
	views[h]=true;gui.Destroying:Connect(function() h.dead=true;views[h]=nil end)
	return h
end
local function render(h:any,now:number,dt:number)
	Motion.advance(h.state,h.cfg,h.sample,now,dt,not h.stale and h.built>=1,h.id,h.origin)
	for i,part in h.parts do
		Gun.sync(part,h.built,h.stale,nil,h.id,h.base,h.tint,h.alpha,h.light,h.bank,Motion.pose(h.state,h.cfg,i,now))
	end
end
function Renderer.sync(h:any,built:number,stale:boolean,sample:any,id:number,base:any,tint:any,alpha:number,light:any,bank:any)
	if not h or h.dead then return end
	local now=os.clock();local dt=if h.at then math.max(0,now-h.at) else 0
	if h.id~=id then h.state=Motion.new(h.cfg) end
	h.id=id;h.built=built;h.stale=stale;h.sample=sample;h.base=base;h.tint=tint;h.alpha=alpha;h.light=light;h.bank=bank;h.last=now;h.at=now
	render(h,now,dt)
end
function Renderer.step()
	local now=os.clock()
	for h in views do
		if not h.at then continue end
		if now-h.last>.25 then
			Motion.advance(h.state,h.cfg,nil,now,0,false,h.id,h.origin);h.at=nil
		else local dt=now-h.at;h.at=now;render(h,now,dt) end
	end
end
function Renderer.forgetSheet(image:any)
	for h in views do if h.bank and h.bank.image==image then h.bank=nil end end
end
function Renderer.reset() for h in views do h.dead=true end;table.clear(views) end
function Renderer.count():number local n=0;for _ in views do n+=1 end;return n end
return Renderer
