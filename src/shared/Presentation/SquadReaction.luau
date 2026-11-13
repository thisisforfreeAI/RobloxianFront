--!strict
-- Original living-soldier blast flinch. Grid/pool and bounded clock prediction are port policies.
local Reaction={MIN_SIZE=2,REACH=.5,SLACK=2.2,SEC=.85,JITTER=.35,RISE_SEC=.22,PRONE_BACK=.57}
local CELL=8
local function finite(v:any):boolean return type(v)=='number'and v==v and math.abs(v)<math.huge end
function Reaction.new(hash:(number,number)->number):any
 local s:any={war=nil,running=false,received=0,sequence=0,buckets={},keys={},pool={},entries={},lastChecked=0,lastAffected=0,lastMen=0}
 function s.sync(packet:any,wall:number)
  if type(packet)~='table'or not finite(packet[1])or packet[1]<0 or packet[2]~=0 and packet[2]~=1 then return end
  if s.war and packet[1]<s.war then return end
  local running=packet[2]==1
  if s.war~=packet[1]or s.running~=running then s.war=packet[1];s.received=wall;s.running=running end
 end
 function s.time(wall:number):number return if s.war then s.war+(if s.running then math.clamp(wall-s.received,0,.2)else 0)else 0 end
 function s.apply(squads:{any},rows:{any},wall:number):number
  local now=s.time(wall);local newest=s.sequence;local fresh=false
  for _,row in rows do if row[1]>s.sequence then fresh=true;newest=math.max(newest,row[1])end end
  s.lastChecked,s.lastAffected,s.lastMen=0,0,0;if not fresh then return 0 end
  local count=0
  for _,sq in squads do for index,m in sq.men do if m.up and(m.flatUntil or 0)<=now then
   count+=1;local entry=s.entries[count]or{};s.entries[count]=entry;entry.m,entry.sq,entry.index=m,sq,index
   local key=math.floor(m.x/CELL)..':'..math.floor(m.y/CELL);local bucket=s.buckets[key]
   if not bucket then bucket=table.remove(s.pool)or{};s.buckets[key]=bucket;table.insert(s.keys,key)end
   table.insert(bucket,entry)
  end end end
  s.lastMen=count
  for i=#rows,1,-1 do local row=rows[i]
   if row[1]<=s.sequence or row[4]<Reaction.MIN_SIZE or row[5]>now+.2 or now-row[5]>Reaction.SEC+Reaction.JITTER then continue end
   local radius=row[4]*Reaction.REACH+Reaction.SLACK;local r2=radius*radius
   for gy=math.floor((row[3]-radius)/CELL),math.floor((row[3]+radius)/CELL)do
    for gx=math.floor((row[2]-radius)/CELL),math.floor((row[2]+radius)/CELL)do
     local bucket=s.buckets[gx..':'..gy];if not bucket then continue end
     local at=1
     while at<=#bucket do
      local entry=bucket[at];local m,sq=entry.m,entry.sq;s.lastChecked+=1;local remove=(m.flatUntil or 0)>now
      if not remove and(m.x-row[2])^2+(m.y-row[3])^2<=r2 then
       local untilTime=row[5]+Reaction.SEC+hash(sq.id,69+entry.index)*Reaction.JITTER
       if untilTime>now then m.flatUntil=untilTime;s.lastAffected+=1;remove=true end
      end
      if remove then bucket[at]=bucket[#bucket];bucket[#bucket]=nil else at+=1 end
     end
    end
   end
  end
  s.sequence=newest
  -- Reuse bucket/entry storage without retaining dead or fogged squad owners between packets.
  for _,key in s.keys do local bucket=s.buckets[key];table.clear(bucket);table.insert(s.pool,bucket);s.buckets[key]=nil end;table.clear(s.keys)
  for i=1,count do s.entries[i].m=nil;s.entries[i].sq=nil end
  return s.lastAffected
 end
 function s.stats():any return {men=s.lastMen,checked=s.lastChecked,affected=s.lastAffected,entries=#s.entries,buckets=#s.pool}end
 return s
end
return Reaction
