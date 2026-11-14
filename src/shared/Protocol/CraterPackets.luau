--!strict
-- Private source colours/geometry, never target/damage authority. Entire packet validates first.
local P={LIMIT=64,MAX_KNOWN=512}
local function finite(n:any):boolean return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function integer(n:any):boolean return finite(n)and n>=1 and n%1==0 and n<2147483648 end
local function colour(s:any):boolean return type(s)=='string'and s:match('^#%x%x%x%x%x%x$')~=nil end
function P.row(h:any,id:number,steps:number):any
 local function rounded(n)return math.floor(n*1000+.5)/1000 end
 return {id,rounded(h.x),rounded(h.y),rounded(h.r),math.floor(h.fill*steps+.5),h.ground,h.paved or ''}
end
function P.key(row:any):string return table.concat(row,'|')end
function P.decode(packet:any,w:number,h:number,config:any):{any}?
 if type(packet)~='table'or not integer(packet.epoch)or not integer(packet.sequence)or type(packet.reset)~='boolean'or type(packet.rows)~='table'or #packet.rows>P.LIMIT then return nil end
 local rows,seen={},{}
 for _,r in packet.rows do
  if type(r)~='table'or not integer(r[1])or seen[r[1]]then return nil end;seen[r[1]]=true
  if #r==2 and r[2]==0 then table.insert(rows,{r[1],0});continue end
  if #r~=7 or not finite(r[2])or not finite(r[3])or r[2]<0 or r[3]<0 or r[2]>=w or r[3]>=h or not finite(r[4])or r[4]<=0 or r[4]>config.model.maxCells+.001 or not finite(r[5])or r[5]%1~=0 or r[5]<0 or r[5]>config.paint.steps or not colour(r[6])or r[7]~=''and not colour(r[7])then return nil end
  table.insert(rows,table.clone(r))
 end
 return rows
end
return P
