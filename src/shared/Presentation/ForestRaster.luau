--!strict
-- Recompose an affected town chunk from its tree-free city/road layer and source tree sprites.
-- APPROX: the existing 14px/cell bake, fixed tree shadows and CPU alpha rounding replace GPU drawing.
local Raster={}
local function round(x:number):number return math.floor(x+.5) end
function Raster.pose(frame:any,x:number,y:number,scale:number,fate:any,settings:any):any
	local char=if fate and (fate.kind=="burning" or fate.kind=="fallen") then fate.char else nil
	local tint=if char~=nil then settings.charColors[math.min(#settings.charColors,char+1)] else 16777215
	if fate and fate.kind=="fallen" then return {x=x,y=y,anchorX=settings.fallenAnchor,anchorY=.5,rotation=fate.rot,tint=tint} end
	local left,top=x-round(frame.w*scale/2),y-round(frame.h*scale/2)
	return {x=left,y=top,anchorX=0,anchorY=0,rotation=0,tint=tint,
		shadowX=left+round(frame.w*scale*settings.shadow.dx),shadowY=top+round(frame.w*scale*settings.shadow.dy)}
end
function Raster.over(out:buffer,at:number,r:number,g:number,b:number,a:number)
	if a<=0 then return end
	if a>=255 then buffer.writeu8(out,at,r);buffer.writeu8(out,at+1,g);buffer.writeu8(out,at+2,b);buffer.writeu8(out,at+3,255);return end
	local prior=buffer.readu8(out,at+3);local den=a*255+prior*(255-a)
	for ch,value in {r,g,b} do
		buffer.writeu8(out,at+ch-1,math.clamp(round((value*a*255+buffer.readu8(out,at+ch-1)*prior*(255-a))/den),0,255))
	end
	buffer.writeu8(out,at+3,math.clamp(round(den/255),0,255))
end
local function blit(out:buffer,w:number,h:number,source:buffer,frame:any,x:number,y:number,tint:number,shadow:number?)
	local red,green,blue=bit32.extract(tint,16,8)/255,bit32.extract(tint,8,8)/255,bit32.extract(tint,0,8)/255
	for py=math.max(0,-y),math.min(frame.h-1,h-y-1) do for px=math.max(0,-x),math.min(frame.w-1,w-x-1) do
		local at=frame.offset+(py*frame.w+px)*4;local a=buffer.readu8(source,at+3);if a==0 then continue end
		if shadow then Raster.over(out,((y+py)*w+x+px)*4,0,0,0,round(a*shadow))
		else Raster.over(out,((y+py)*w+x+px)*4,round(buffer.readu8(source,at)*red),round(buffer.readu8(source,at+1)*green),round(buffer.readu8(source,at+2)*blue),a) end
	end end
end
local function fallen(out:buffer,w:number,h:number,source:buffer,frame:any,pose:any)
	local c,s=math.cos(pose.rotation),math.sin(pose.rotation);local radius=math.sqrt(frame.w^2+frame.h^2)
	local tint=pose.tint;local red,green,blue=bit32.extract(tint,16,8)/255,bit32.extract(tint,8,8)/255,bit32.extract(tint,0,8)/255
	for y=math.max(0,math.floor(pose.y-radius)),math.min(h-1,math.ceil(pose.y+radius)) do
		for x=math.max(0,math.floor(pose.x-radius)),math.min(w-1,math.ceil(pose.x+radius)) do
			local dx,dy=x+.5-pose.x,y+.5-pose.y
			local u,v=c*dx+s*dy+pose.anchorX*frame.w-.5,-s*dx+c*dy+pose.anchorY*frame.h-.5
			local ix,iy=math.floor(u),math.floor(v);local a,r,g,b=0,0,0,0
			for oy=0,1 do for ox=0,1 do
				local sx,sy=ix+ox,iy+oy;if sx<0 or sy<0 or sx>=frame.w or sy>=frame.h then continue end
				local weight=(if ox==0 then 1-(u-ix) else u-ix)*(if oy==0 then 1-(v-iy) else v-iy)
				local at=frame.offset+(sy*frame.w+sx)*4;local alpha=buffer.readu8(source,at+3)*weight
				a+=alpha;r+=buffer.readu8(source,at)*alpha;g+=buffer.readu8(source,at+1)*alpha;b+=buffer.readu8(source,at+2)*alpha
			end end
			if a>0 then Raster.over(out,(y*w+x)*4,round(r/a*red),round(g/a*green),round(b/a*blue),round(a)) end
		end
	end
end
function Raster.paint(map:any,base:buffer,cx:number,cy:number,cw:number,ch:number,fates:any):buffer
	local data=map.data;local tile=data.tileSize;local w,h=cw*tile,ch*tile
	assert(buffer.len(base)==w*h*4,"invalid forest base dimensions")
	local out=buffer.create(buffer.len(base));buffer.copy(out,0,base)
	local list=map.inWindow(cx,cy,cw,ch);if #list==0 then return out end
	local source=map.pixels()
	-- Original layer order: fallen/stumps below standing-tree shadows, then upright crowns/branches.
	for layer=1,3 do for _,t in list do
		local fate=fates[t.key];local kind=if fate and fate.kind~="burning" then fate.kind else "standing"
		local down=kind=="fallen" or kind=="stump";if (layer==1)~=down then continue end
		local family=data.families[t.sprite];local frame=assert(family[kind],"invalid forest fate")
		local pose=Raster.pose(frame,t.x*tile-cx*tile,t.y*tile-cy*tile,1,fate,data)
		if down then
			if kind=="fallen" then fallen(out,w,h,source,frame,pose)
			else blit(out,w,h,source,frame,round(pose.x),round(pose.y),pose.tint) end
		elseif layer==2 then
			blit(out,w,h,source,frame,t.drawX-cx*tile+family.shadowX,t.drawY-cy*tile+family.shadowY,0,data.shadow.alpha)
		else blit(out,w,h,source,frame,t.drawX-cx*tile,t.drawY-cy*tile,pose.tint) end
	end end
	return out
end
function Raster.overview(px:buffer,w:number,h:number,tile:number,perCell:number):buffer
	local ow,oh=w/tile*perCell,h/tile*perCell;local out=buffer.create(ow*oh*4);local step=tile/perCell
	for oy=0,oh-1 do for ox=0,ow-1 do
		local r,g,b,a=0,0,0,0
		for sy=0,1 do for sx=0,1 do
			local x=math.min(w-1,math.floor((ox+.25+sx*.5)*step));local y=math.min(h-1,math.floor((oy+.25+sy*.5)*step));local at=(y*w+x)*4
			local alpha=buffer.readu8(px,at+3);r+=buffer.readu8(px,at)*alpha;g+=buffer.readu8(px,at+1)*alpha;b+=buffer.readu8(px,at+2)*alpha;a+=alpha
		end end
		if a>0 then local at=(oy*ow+ox)*4;buffer.writeu8(out,at,round(r/a));buffer.writeu8(out,at+1,round(g/a));buffer.writeu8(out,at+2,round(b/a));buffer.writeu8(out,at+3,round(a/4)) end
	end end
	return out
end
return Raster
