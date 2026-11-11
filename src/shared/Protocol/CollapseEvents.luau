--!strict
-- Transient presentation only: bounded rows, no history for a late join/reveal.
local Events={LIMIT=32}
local function valid(row:any,w:number,h:number):boolean
	if type(row)~="table" then return false end
	local id,kind,x,y=row[1],row[2],row[3],row[4]
	return type(id)=="number" and id>0 and id<math.huge and id%1==0 and type(kind)=="string" and #kind>0 and #kind<=64
		and kind~="rig" and kind~="minefield" and type(x)=="number" and type(y)=="number" and x>=0 and y>=0 and x<w and y<h
end
function Events.push(queue:{any},event:any,w:number,h:number):boolean
	if event.type~="destroyed" or event.cat~="structure" or #queue>=Events.LIMIT then return false end
	local row={event.id,event.kind,event.x,event.y};if not valid(row,w,h) then return false end
	for _,old in queue do if old[1]==row[1] then return false end end
	table.insert(queue,row);return true
end
function Events.read(rows:any,w:number,h:number):{any}
	if type(rows)~="table" or #rows>Events.LIMIT then return {} end
	local out,seen={},{}
	local count=0;for index,row in rows do
		if type(index)~="number" or index%1~=0 or index<1 or index>#rows then return {} end;count+=1
		if not valid(row,w,h) then return {} end
		if not seen[row[1]] then table.insert(out,{row[1],row[2],row[3],row[4]});seen[row[1]]=true end
	end;return if count==#rows then out else {}
end
function Events.visible(queue:{any},visible:(number,number)->boolean):{any}
	local rows={};for _,row in queue do if visible(row[3],row[4]) then table.insert(rows,row) end end;return rows
end
return Events
