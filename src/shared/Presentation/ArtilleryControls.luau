--!strict
-- Port UI state only. Strike prices/range/cooldowns and all outcomes remain server-authoritative.
local Controls={}
local REASONS={building="Under construction",damaged="Needs repairs",demolishing="Being demolished",notOperational="Base is not operational",notOwned="Base is unavailable",kills="Not enough kills",cooldown="Reloading",outOfRange="Target is out of range",blocked="Cannot fire now"}
function Controls.new(side:number,rules:any):any return {side=side,rules=rules,status={},kills=0,selected=nil,mode=nil,pending=nil,sequence=0,note=""} end
function Controls.pick(m:any,id:number?,kind:string?)
	local value=if kind=="artybase" then id else nil;if value==m.selected then return end
	m.selected=value;m.mode=nil;m.note=""
end
function Controls.base(m:any,views:any):any
	local v=m.selected and views[m.selected]
	return if v and v.kind=="artybase" and v.side==m.side and m.side>0 and not v.stale and (v.hp or 0)>0 then v else nil
end
function Controls.reason(m:any,views:any,kind:string):string?
	local v=Controls.base(m,views);if not v then return "Base is unavailable" end
	if m.over or m.drop then return "Match is not ready for strikes" end
	if m.pending then return "Sending strike…" end
	if v.built<1 then return REASONS.building end
	local row=m.status[v.id];if not row then return "Loading base status…" end
	if row[4] then return REASONS[row[4]] or "Base is not operational" end
	local wait=row[if kind=="barrage" then 2 else 3] or 0
	if wait>0 then return `Reloading · {wait} s` end
	if m.kills<(m.rules[`artyBase.{kind}.price`] or math.huge) then return REASONS.kills end
	return nil
end
function Controls.arm(m:any,views:any,kind:string):boolean
	if kind~="barrage" and kind~="flare" then return false end
	local why=Controls.reason(m,views,kind);if why then m.note=why;return false end
	m.mode=kind;m.note=if kind=="barrage" then "Click a barrage target · right-click / Esc cancels" else "Click a flare target · right-click / Esc cancels";return true
end
function Controls.cancel(m:any) m.mode=nil;m.note="" end
function Controls.fire(m:any,views:any,x:number,y:number,now:number):any
	local kind=m.mode;if not kind then return nil end
	local why=Controls.reason(m,views,kind);if why then m.note=why;m.mode=nil;return nil end
	local v=Controls.base(m,views);local radius=m.rules['artyBase.range'] or 0
	if (v.x-x)^2+(v.y-y)^2>radius^2 then m.note=REASONS.outOfRange;return nil end
	m.sequence+=1;m.pending={id=v.id,kind=kind,request=m.sequence,at=now};m.mode=nil;m.note="Sending strike…"
	return {kind="power",power=kind,structureId=v.id,requestId=m.sequence,x=x,y=y}
end
function Controls.update(m:any,state:any)
	if state.kills~=nil then m.kills=state.kills end
	if state.artyBases then local rows={};for _,row in state.artyBases do rows[row[1]]=row end;m.status=rows end
	if state.winner~=nil or state.lost then m.over=true;m.mode=nil end
	if state.oil~=nil then m.drop=state.drop~=nil;if m.drop then m.mode=nil end end
	local r=state.artyResult;local pending=m.pending
	if r and pending and r[1]==pending.id and r[2]==pending.kind and r[3]==pending.request then
		m.pending=nil
		if m.selected==r[1] then m.note=if r[4] then (if r[2]=="barrage" then "Barrage launched" else "Flares launched") else REASONS[r[5]] or "Strike refused" end
	end
end
function Controls.expire(m:any,now:number)
	-- APPROX port UX timeout; no simulated cooldown is changed and every retry is revalidated.
	if m.pending and now-m.pending.at>5 then m.pending=nil;m.note="No reply yet · try again" end
end
return Controls
