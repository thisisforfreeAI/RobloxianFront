--!strict
-- Conservative presentation policy, not an estimate of Roblox's undocumented device budget.
local Policy={}
function Policy.new():any return {level=0,native=0,hold=0,calm=nil} end
function Policy.sample(s:any,used:number,detail:number,ceiling:number,detailLimit:number,refusals:number,now:number):number
	local ratio=used/math.max(1,ceiling)
	local crowded=ratio>=.85 or detail/math.max(1,detailLimit)>=.9
	if refusals>s.native then s.native=refusals;s.level=2;s.hold=now+8;s.calm=nil
	elseif crowded then s.level=math.max(1,s.level);s.calm=nil
	elseif now>=s.hold and ratio<.7 and detail/math.max(1,detailLimit)<.75 then
		s.calm=s.calm or now
		if now-s.calm>=5 then s.level=math.max(0,s.level-1);s.calm=now;s.hold=now+3 end
	else s.calm=nil end
	return s.level
end
function Policy.floor(level:number,kind:string,visible:boolean):number
	if not visible then return 4 end
	if kind=="detail" then return if level>=2 then 4 elseif level==1 then 2 else 1 end
	return if level>=2 then 2 else 1
end
return Policy
