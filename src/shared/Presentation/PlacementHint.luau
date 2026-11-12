--!strict
-- Advisory checks from public map data, own state and fog-filtered structure snapshots only.
-- Server-only seal checks, unseen obstacles/mines and state races still require canPlace on click.
local Hint={}
function Hint.prepare(map:any,rules:any,line:any,checkpoint:any?):any
	local w,h=map.width,map.height;local road=buffer.create(w*h);local seeds={}
	local function terrain(c:number):string return map.data.legend[buffer.readu8(map.terrain,c)+1] or "deep" end
	for _,r in map.data.roads or {} do if r.rank>=1 then
		for i=3,#r.pts-1,2 do
			for _,c in line(w,h,r.pts[i-2],r.pts[i-1],r.pts[i],r.pts[i+1]) do
				local t=terrain(c)
				if t~="deep" then buffer.writeu8(road,c,1);if rules[`terrain.{t}.passable`]~=true then seeds[c]=true end end
				if checkpoint then checkpoint() end
			end
		end
	end end
	-- Only original impassable road cells seed widening, matching Roads.build without its route graph.
	local half=rules["movement.bridgeDeck.half"] or 0
	for c in seeds do
		local x,y=c%w,c//w
		for dy=-half,half do for dx=-half,half do
			local gx,gy=x+dx,y+dy
			if gx>=0 and gy>=0 and gx<w and gy<h then local k=gy*w+gx;local t=terrain(k);if t~="deep" and rules[`terrain.{t}.passable`]~=true then buffer.writeu8(road,k,1) end end
		end end
		if checkpoint then checkpoint() end
	end
	return {map=map,rules=rules,road=road}
end
function Hint.check(model:any,cx:number,cy:number,radius:number,inside:any,structures:any,side:number,kind:string,state:any):any
	local map,r=model.map,model.rules;local w,h=map.width,map.height
	local result:any={ok=true,blocked={},clashes={}}
	local function refuse(why:string) if result.ok then result.ok=false;result.reason=why end end
	if cx-radius<0 or cy-radius<0 or cx+radius>=w or cy+radius>=h then refuse("terrain") end
	for dy=-radius,radius do for dx=-radius,radius do
		local x,y=cx+dx,cy+dy
		local terrainBad=x<0 or y<0 or x>=w or y>=h;local roadBad=false
		if not terrainBad then local c=y*w+x;local terrain=map.data.legend[buffer.readu8(map.terrain,c)+1];terrainBad=r[`terrain.{terrain}.buildable`]~=true;roadBad=buffer.readu8(model.road,c)==1 end
		if terrainBad or roadBad then table.insert(result.blocked,{dx=dx,dy=dy}) end
		if terrainBad then refuse("terrain") end
	end end
	local clear=math.max(1,math.floor(radius*(r["production.roadClearShare"] or 1)+.5))+(r["production.roadClearPad"] or 0)
	for y=math.max(0,cy-clear),math.min(h-1,cy+clear) do for x=math.max(0,cx-clear),math.min(w-1,cx+clear) do if buffer.readu8(model.road,y*w+x)==1 then refuse("onRoad") end end end
	local pad=radius+(r["rigs.padCells"] or 0)
	for _,rig in map.data.rigs or {} do
		local x=math.clamp(math.floor(rig.x),0,w-1)+.5;local y=math.clamp(math.floor(rig.y),0,h-1)+.5
		if math.abs(x-cx-.5)<=pad+.5 and math.abs(y-cy-.5)<=pad+.5 then refuse("onRig") end
	end
	for _,st in structures or {} do
		if st.kind=="rig" then continue end
		local foot=if st.kind=="hq" then r["production.footprint.hq"] or 2 else r["production.footprint.facility"] or 1
		local reach=radius+foot+(r["production.spacing"] or 0)
		if math.abs(st.x-cx-.5)<=reach and math.abs(st.y-cy-.5)<=reach then
			refuse("spacing");table.insert(result.clashes,{dx=st.x-cx-.5,dy=st.y-cy-.5,cells=foot*2+1})
		end
	end
	for y=cy-radius,cy+radius do for x=cx-radius,cx+radius do if x<0 or y<0 or x>=w or y>=h or not inside[y*w+x] then refuse("outsideBase") end end end
	if state then
		if state.lost or state.winner~=nil then refuse("blocked") end
		if state.oil~=nil and state.oil<(r[`structures.{kind}.cost`] or 0) then refuse("oil") end
		if state.kills~=nil and state.kills<(r[`structures.{kind}.killCost`] or 0) then refuse("kills") end
		for _,required in r[`structures.{kind}.requires`] or {} do
			local have=false;for _,st in structures or {} do if st.side==side and st.kind==required and st.built>=1 then have=true;break end end
			if not have then refuse("requires") end
		end
	end
	return result
end
return Hint
