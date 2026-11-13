--!strict
-- Visible, transient blast presentation only. No damage or hit authority is carried here.
local Events={MAX=64,MIN_SIZE=2,MAX_SIZE=64}
local function finite(v:any):boolean return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function valid(row:any,w:number,h:number):boolean
 return type(row)=='table' and finite(row[1]) and row[1]>0 and row[1]%1==0 and finite(row[2]) and finite(row[3])
  and row[2]>=0 and row[3]>=0 and row[2]<w and row[3]<h and finite(row[4]) and row[4]>=Events.MIN_SIZE and row[4]<=Events.MAX_SIZE and finite(row[5]) and row[5]>=0
end
function Events.push(queue:{any},sequence:number,x:number,y:number,size:number,time:number,w:number,h:number):boolean
 local row={sequence,x,y,size,time};if not valid(row,w,h)then return false end
 if #queue>=Events.MAX then table.remove(queue,1)end;table.insert(queue,row);return true
end
function Events.visible(queue:{any},visible:(number,number)->boolean,tick:number?):{any}
 local out={};for _,row in queue do if visible(row[2],row[3])then
  -- Public ids count only this viewer's visible rows; hidden event counts do not leak through gaps.
  table.insert(out,{if tick then tick*Events.MAX+#out+1 else row[1],row[2],row[3],row[4],row[5]})
 end end;return out
end
function Events.read(rows:any,w:number,h:number):{any}
 local out={};if type(rows)~='table'then return out end
 for i=1,math.min(#rows,Events.MAX)do local row=rows[i];if valid(row,w,h)then table.insert(out,{row[1],row[2],row[3],row[4],row[5]})end end
 return out
end
return Events
