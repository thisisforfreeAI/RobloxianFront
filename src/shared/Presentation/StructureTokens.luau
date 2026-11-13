--!strict
-- Source building LOD/bar poses from generated styles and already-filtered structure views.
local Coverage=require(if script then script.Parent.CoverageMotion else "./CoverageMotion")
local Motion={}
function Motion.plan(style:any,v:any,pixels:number,rules:any,viewer:number,ready:boolean?):any
	if not style or not style.tokens or not style.coverage then return nil end
	local c=style.tokens;local detail=style.preview;local token=style.coverage.token
	local definition=rules[`structures.{v.kind}.kind`] or (if v.kind=="hq" then "hq" else "facility")
	local size=Coverage.token(style.coverage,definition,pixels,rules["production.spacing"] or 0)
	local desired=if v.stale then 0 else math.clamp((pixels-detail.from)/detail.fadePx,0,1)
	-- APPROX admission fallback: keep a complete badge until the shared detailed art is available.
	local mix=if ready==false then 0 else desired
	local full=(v.cells or (if v.kind=="hq" then 5 else 3))*pixels
	local span=size+(full-size)*mix
	local out:any={size=size,mix=mix,detailMix=desired,alpha=(1-mix)*(if (v.built or 1)<1 then c.buildingAlpha else 1),bars={},rects={},stale=v.stale==true}
	if v.stale then
		out.alpha=c.stale.iconAlpha;local reach=size*c.stale.reach;local arm=math.max(4,size*c.stale.arm)
		for _,stroke in {{c.stale.rimPx,c.stale.rim},{c.stale.linePx,c.stale.color}} do
			local w,ink=stroke[1],stroke[2]
			for _,sx in {-1,1} do for _,sy in {-1,1} do
				table.insert(out.rects,{x=if sx<0 then -reach-w/2 else reach-arm-w/2,y=sy*reach-w/2,w=arm+w,h=w,ink=ink,alpha=c.stale.alpha})
				-- Join the L without overlapping alpha at the corner.
				table.insert(out.rects,{x=sx*reach-w/2,y=if sy<0 then -reach+w/2 else reach-arm-w/2,w=w,h=math.max(0,arm),ink=ink,alpha=c.stale.alpha})
			end end
		end
		return out -- No owner colour, health, build state or live operational information in fog.
	end
	if pixels<token.detailFrom then return out end
	local warning=c.status
	if warning and v.side==viewer and (v.built or 1)>=1 and bit32.band(v.markerFlags or 0,1)~=0 then
		local size=math.max(warning.minPx,math.floor(out.size*warning.sizeShare+.5))
		out.warning={x=span*warning.offsetShare,y=-span*warning.offsetShare,size=size,radius=size*warning.discShare,ink=warning.ink,plate=warning.plate}
	end
	local b=c.bar;local width=math.min(b.max,math.floor(span*b.widthShare+.5))
	if (v.built or 1)<1 and v.side==viewer then table.insert(out.bars,{x=-width/2,y=span/2+b.buildGap,w=width,h=b.height,share=math.clamp(v.built,0,1),ink=c.accent}) end
	if v.hp and v.maxHp and v.maxHp>0 and v.hp<v.maxHp-1 then
		local share=math.clamp(v.hp/v.maxHp,0,1)
		table.insert(out.bars,{x=-width/2,y=-span/2-b.hpGap,w=width,h=b.height,share=share,ink=if share>.5 then c.secured else c.contested})
	end
	return out
end
function Motion.ground(style:any,side:number,pixels:number,night:number,stale:boolean,flags:number?,origin:any?):any
	local c=style and style.ground
	if not c or stale or side<=0 or bit32.band(flags or 0,2)~=0 then return nil end
	local fade=math.clamp((pixels-c.from)/c.fadePx,0,1);if fade<=0 then return nil end
	local half=side/2;local width=side*c.share;local size=math.floor(width/c.symbolShare+.5)
	local x=half+c.gapCells*pixels+width/2-size/2;local y=half-width/2-size/2
	local ox,oy=if origin then origin.X else 0,if origin then origin.Y else 0
	return {x=math.floor(ox+x+.5)-ox,y=math.floor(oy+y+.5)-oy,size=size,alpha=fade*c.alpha*(1-c.nightFade*night),shade=c.shadePx}
end
return Motion
