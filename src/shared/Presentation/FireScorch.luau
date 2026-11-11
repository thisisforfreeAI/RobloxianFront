--!strict
-- Paint source house char pixels into disjoint world tiles. Transparent elsewhere: native images
-- stay small and the existing town/ground remains visible. Original atlas IDs preserve source noise.
local Pixels=if script then require(script.Parent.FirePixels) else require("./FirePixels")
local Scorch={TILE=8}
function Scorch.bucket(width:number,tileSize:number,patches:{[number]:number}):{[string]:any}
	local out={};local fineWidth=width*tileSize
	for p,stage in patches do
		local x,y=p%fineWidth,math.floor(p/fineWidth)
		local tx,ty=math.floor(x/tileSize/Scorch.TILE),math.floor(y/tileSize/Scorch.TILE)
		local key=tx..":"..ty
		local b=out[key];if not b then b={tx=tx,ty=ty,points={}};out[key]=b end
		table.insert(b.points,{p=p,x=x,y=y,stage=stage})
	end
	for _,b in out do table.sort(b.points,function(a,c) return a.p<c.p end) end
	return out
end
function Scorch.paint(map:any,settings:any,bucket:any,visible:any,lit:any?,cover:buffer?):(buffer,number)
	local tile=map.tileSize;local side=tile*Scorch.TILE;local out=buffer.create(side*side*4);local count=0
	assert(not cover or buffer.len(cover)==buffer.len(out),"invalid forest cover dimensions")
	for _,point in bucket.points do
		local x,y=point.x,point.y
		if not visible((x+.5)/tile,(y+.5)/tile) then continue end
		local id=map.sourceId(x,y);local original=map.original(x,y)
		if id==nil or not original or not map.roof(x,y) then continue end
		local edge=not map.roof(x+1,y) or not map.roof(x-1,y) or not map.roof(x,y+1) or not map.roof(x,y-1)
		local rgba=Pixels.house(settings,id,original,point.stage,edge)
		local at=((y-bucket.ty*side)*side+x-bucket.tx*side)*4
		local alpha=if cover then buffer.readu8(cover,at+3)/255 else 0
		-- APPROX lighting adapter: retain the current baked town shade as a scalar. Recomputed
		-- roof-height/occlusion shadows after collapse remain a later town-shader integration.
		local keep=1
		if lit then
			local color=lit((x+.5)/tile,(y+.5)/tile)
			local base=original[1]+original[2]+original[3]
			if color and base>0 and alpha<1 then
				local sum=color[1]+color[2]+color[3]
				-- Recover the shaded roof under the foreground before compositing the new char.
				-- APPROX: static bake/resampling differences can shift this scalar by a few bytes.
				if cover and alpha>0 then sum=(sum-(buffer.readu8(cover,at)+buffer.readu8(cover,at+1)+buffer.readu8(cover,at+2))*alpha)/(1-alpha) end
				keep=math.clamp(sum/base,0,1)
			end
		end
		for channel=0,2 do
			local color=rgba[channel+1]*keep
			if cover and alpha>0 then color=color*(1-alpha)+buffer.readu8(cover,at+channel)*alpha end
			buffer.writeu8(out,at+channel,math.clamp(math.floor(color+.5),0,255))
		end
		buffer.writeu8(out,at+3,255);count+=1
	end
	return out,count
end
return Scorch
