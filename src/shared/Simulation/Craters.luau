--!strict
-- Persistent cosmetic holes. Settings are extracted locally, independent of gameplay RNG.
local Craters={}
function Craters.new(config:any,context:any):any
 local C,P=config.model,config.paint
 local self:any={list={},sequence=1,healAcc=0}
 function self.wetAt(hole:any):boolean
  if hole.r>=C.waterFrom then return true end
  local reach=hole.r*P.lip+C.nearWater
  for i=0,7 do local a=i/8*math.pi*2;if context.water(hole.x+math.cos(a)*reach,hole.y+math.sin(a)*reach)then return true end end
  return false
 end
 function self.forget(index:number)table.remove(self.list,index)end
 function self.dropOne()
  local index=1
  for i=2,#self.list do local a,b=self.list[i],self.list[index]
   if (not a.wet and b.wet)or a.wet==b.wet and a.r<b.r then index=i end
  end
  if #self.list>0 then self.forget(index)end
 end
 function self.blast(x:number,y:number,size:number,cause:string):any
  local scale=C.causes[cause];if not scale or context.water(x,y)then return nil end
  local radius=size*C.perBlast*scale;if radius<C.minCells then return nil end
  local nearest,distance=nil,math.huge
  for _,h in self.list do local d=math.sqrt((h.x-x)^2+(h.y-y)^2)
   if d<=math.max(h.r*C.merge,radius)and d<distance then nearest=h;distance=d end
  end
  if nearest then
   local old=nearest.r^2;local added=C.grow*radius^2;local share=added/(old+added)
   nearest.x+=(x-nearest.x)*share;nearest.y+=(y-nearest.y)*share;nearest.r=math.min(C.maxCells,math.sqrt(old+added))
   nearest.wet=nearest.wet or self.wetAt(nearest);nearest.since=0;nearest.mend=0;nearest.fixed=false;return nearest
  end
  local h={x=x,y=y,r=math.min(C.maxCells,radius),fill=0,wet=false,seed=self.sequence,ground=context.ground(x,y),paved=if context.paved then context.paved(x,y)else nil}
  self.sequence+=1;h.wet=self.wetAt(h);table.insert(self.list,h);if #self.list>C.max then self.dropOne()end;return h
 end
 function self.tick(dt:number,quiet:((number,number)->boolean)?):boolean
  if dt<=0 then return false end
  local H=C.heal;self.healAcc+=dt;local check=quiet~=nil and self.healAcc>=H.everySec;local elapsed=if check then self.healAcc else 0
  if check then self.healAcc=0 end;local changed=false
  for i=#self.list,1,-1 do local h=self.list[i];h.since=(h.since or 0)+dt
   if h.healing and not check then continue end
   if check then h.healing=h.fixed or h.since>=H.quietSec and quiet(h.x,h.y)end
   if h.healing then
    changed=true;local pace=if h.fixed then H.fixedPace else 1
    if h.fill>0 then h.fill=math.max(0,h.fill-elapsed*pace/H.drainSec);continue end
    h.mend=(h.mend or 0)+elapsed*pace*H.cellsPerSec
    if h.mend<H.stepCells then continue end
    local steps=math.floor(h.mend/H.stepCells);h.mend-=steps*H.stepCells;h.r-=steps*H.stepCells
    if h.r<H.goneCells then self.forget(i)else h.wet=self.wetAt(h)end
   elseif h.wet and h.fill<1 then h.fill=math.min(1,h.fill+dt/C.fillSec);changed=true end
  end
  return changed
 end
 function self.fix(x:number,y:number,radius:number,allowed:((number,number)->boolean)?)
  for _,h in self.list do if (h.x-x)^2+(h.y-y)^2<=radius^2 and (not allowed or allowed(h.x,h.y))then h.fixed=true;h.healing=true end end
 end
 function self.clear()table.clear(self.list)end
 return self
end
return Craters
