--!strict
-- Roblox port policy, APPROX: directory labels are not a port of an original lobby.
-- Keep existing mid-match bot-side takeover until the authoritative match ends.
local Policy={}
function Policy.state(map:any,sim:any,seats:any):any
	if not map or not sim then return nil end
	local ids={};for player,side in seats do if side==1 or side==2 then table.insert(ids,player.UserId) end end;table.sort(ids)
	local started=not sim.drop or sim.drop.phase=="done"
	return {map=map.data.id,players=#ids,capacity=2,userIds=ids,
		status=if sim.winner then "closing" elseif started then "inProgress" else "waiting",
		joinInProgress=not sim.winner,visibility="public",hostUserId=0}
end
function Policy.side(seats:any,player:any,arrival:any,ended:boolean):number?
	local existing=seats[player];if existing~=nil then return existing end
	if not arrival or not arrival.admit then return nil end
	if arrival.seat==false or ended then return 0 end
	local taken={};for _,side in seats do taken[side]=true end
	return if not taken[1] then 1 elseif not taken[2] then 2 else 0
end
return Policy
