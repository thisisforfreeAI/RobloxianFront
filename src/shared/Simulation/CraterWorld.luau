--!strict
local Model=if script then require(script.Parent.Craters)else require('./Craters')
local Packets=if script then require(script.Parent.Parent.Protocol.CraterPackets)else require('../Protocol/CraterPackets')
local World={}
function World.forMap(config:any,map:any,sim:any):any
 local Codec=if script then require(script.Parent.Parent.Maps.MapCodec)else require('../Maps/MapCodec')
 local function cell(x,y)local cx,cy=math.floor(x),math.floor(y);return if cx>=0 and cy>=0 and cx<map.width and cy<map.height then cy*map.width+cx else nil end
 return World.new(config,map.width,map.height,{time=function()return sim.time end,
  water=function(x,y)local c=cell(x,y);if not c then return true end;if sim.roads.isRoad(c)then return false end;local name=Codec.terrainName(map,x,y);return name=='deep'or name=='shallow'or name=='river'end,
  ground=function(x,y)local name=Codec.terrainName(map,math.clamp(x,0,map.width-1),math.clamp(y,0,map.height-1));return config.palette[name]or config.palette.plains end,
  paved=function(x,y)local c=cell(x,y);if not c or not sim.roads.isRoad(c)then return nil end;local class=sim.roads.classAt(c);return if class>=3 then config.road.asphalt elseif class>=2 then config.road.road else nil end,
  nearRoad=function(x,y)
   local cx,cy=math.floor(x),math.floor(y)
   for yy=math.max(0,cy-1),math.min(map.height-1,cy+1)do for xx=math.max(0,cx-1),math.min(map.width-1,cx+1)do local c=yy*map.width+xx;if sim.roads.isRoad(c)or sim.roads.classAt(c)>0 then return true end end end
   return false
  end,
  quiet=function(x,y)return sim.groundScorch~=nil and sim.groundScorch.quietAt(x,y)end})
end
function World.new(config:any,w:number,h:number,context:any):any
 local self:any={model=Model.new(config,context),epoch=1,time=context.time()}
 function self.blast(x:number,y:number,size:number,cause:string):any
  if not(x>=0 and y>=0 and x<w and y<h and size>0 and size<math.huge)then return nil end
  return self.model.blast(x,y,size,cause)
 end
 function self.advance(time:number)
  local dt=time-self.time;assert(dt>=-1e-8 and dt<math.huge,'invalid crater clock');self.time=time;self.model.tick(math.max(0,dt),context.quiet)
 end
 function self.repaired(x:number,y:number,radius:number)
  if x>=0 and y>=0 and x<w and y<h and radius>0 and radius<math.huge then self.model.fix(x,y,radius,context.nearRoad)end
 end
 function self.reset()self.model.clear();self.epoch+=1;self.time=context.time()end
 function self.view(previous:any?,visible:(number,number)->boolean):(any,any)
  local reset=not previous or previous.epoch~=self.epoch
  local state=if reset then {epoch=self.epoch,sequence=0,nextId=0,known={},cursor=1}else previous
  local rows={};local live={};for _,hole in self.model.list do live[hole.seed]=hole end
  local ids={};for seed in state.known do table.insert(ids,seed)end;table.sort(ids)
  -- Removal is learned only when its last observed position is visible again.
  for _,seed in ids do local old=state.known[seed]
   if not live[seed]and visible(old.row[2],old.row[3])and #rows<Packets.LIMIT then table.insert(rows,{old.id,0});state.known[seed]=nil end
  end
  local count=0;for _ in state.known do count+=1 end
  local length=#self.model.list
  for offset=0,length-1 do
   local index=((state.cursor or 1)-1+offset)%length+1
   local hole=self.model.list[index]
   if #rows>=Packets.LIMIT then state.cursor=index;break end
   if not visible(hole.x,hole.y)then continue end
   local old=state.known[hole.seed]
   if not old then
    if count>=config.model.max then
     if #rows>=Packets.LIMIT-1 then state.cursor=index;break end
     -- Bounded observer cache: retire its oldest hidden observation, independent of hidden events.
     local oldest,key=nil,nil
     for seed,k in state.known do if not visible(k.row[2],k.row[3])and(not oldest or k.id<oldest)then oldest=k.id;key=seed end end
     if not key then continue end;table.insert(rows,{oldest,0});state.known[key]=nil;count-=1
    end
    state.nextId+=1;old={id=state.nextId};count+=1
   end
   local row=Packets.row(hole,old.id,config.paint.steps);local key=Packets.key(row)
   if old.key~=key then table.insert(rows,row);old.row=row;old.key=key;state.known[hole.seed]=old end
  end
  state.sequence+=1
  return {epoch=self.epoch,sequence=state.sequence,reset=reset,rows=rows},state
 end
 return self
end
return World
