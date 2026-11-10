--!strict
local State={}
function State.mode(row:any):string
	if row[2]<=0 or row[11]==1 or row[7]<=0 or row[6]<=0 then return "none" end
	return if row[6]>=row[7] then "secured" else "fortified"
end
function State.sprite(id:string,mode:string):string?
	if mode=="secured" then return id end
	if mode=="fortified" and string.sub(id,1,10)=="fort-gate-" then return "fort-bags-"..string.sub(id,11) end
	return nil
end
return State
