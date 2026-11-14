--!strict
local Packets=if script then require(script.Parent.Parent.Protocol.CraterPackets)else require('../Protocol/CraterPackets')
local View={}
function View.new(w:number,h:number,config:any):any
 local self:any={epoch=0,sequence=0,items={},count=0,serial=0}
 function self.apply(packet:any):boolean
  local rows=Packets.decode(packet,w,h,config);if not rows then return false end
  if packet.epoch<self.epoch or packet.epoch==self.epoch and packet.sequence<=self.sequence then return false end
  if packet.epoch>self.epoch and not packet.reset then return false end
  local reset=packet.reset or packet.epoch~=self.epoch
  local count=if reset then 0 else self.count
  for _,row in rows do
   local exists=not reset and self.items[row[1]]~=nil
   if #row==2 then if exists then count-=1 end elseif not exists then count+=1 end
  end
  if count>config.model.max then return false end
  if reset then table.clear(self.items)end
  for _,row in rows do
   local id=row[1]
   if #row==2 then self.items[id]=nil else
    local old=self.items[id];local key=Packets.key(row)
    if not old or old.key~=key then self.serial+=1;self.items[id]={id=id,seed=id,x=row[2],y=row[3],r=row[4],fill=row[5]/config.paint.steps,ground=row[6],paved=if row[7]~=''then row[7]else nil,key=key,version=self.serial}end
   end
  end
  self.count=count;self.epoch=packet.epoch;self.sequence=packet.sequence;return true
 end
 return self
end
return View
