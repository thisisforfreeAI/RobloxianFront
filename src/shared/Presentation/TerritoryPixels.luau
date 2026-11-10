--!strict
--!native
-- Source ownership smoothing, edge distance, wash and dashed front. APPROX: rasterized at two
-- texels/cell instead of screen pixels; gradient derived inside each bilinear cell; no claim wave yet.
local TerritoryPixels={}
function TerritoryPixels.runs(owners: {number},w: number,h: number,side: number,visible: ((number)->boolean)?): {number}
	local out={}
	for y=0,h-1 do
		local x=0
		while x<w do
			local at=y*w+x
			local owner=owners[at+1] or 0
			if owner<=0 or (side>0 and owner~=side and visible and not visible(at)) then x+=1;continue end
			local first=x
			while x+1<w and owners[y*w+x+2]==owner and (side==0 or owner==side or not visible or visible(y*w+x+1)) do x+=1 end
			table.insert(out,owner);table.insert(out,y);table.insert(out,first);table.insert(out,x)
			x+=1
		end
	end
	return out
end
function TerritoryPixels.render(runs: {number},w: number,h: number,look: any,palette: {{number}},built: buffer?,checkpoint: (() -> ())?): buffer
	local n=w*h
	local count=0
	for i=1,#runs,4 do count=math.max(count,runs[i]) end
	local fields={}
	local weights,total={},0
	for i=-look.radius,look.radius do local v=math.exp(-i*i/(2*look.sigma*look.sigma));weights[i]=v;total+=v end
	for i=-look.radius,look.radius do weights[i]/=total end
	for owner=1,count do
		local mask,tmp,field=buffer.create(n),buffer.create(n*4),buffer.create(n*4)
		for i=1,#runs,4 do if runs[i]==owner then for x=runs[i+2],runs[i+3] do buffer.writeu8(mask,runs[i+1]*w+x,1) end end end
		for y=0,h-1 do if checkpoint and y%8==0 then checkpoint() end;for x=0,w-1 do
			local v=0
			for k=-look.radius,look.radius do v+=buffer.readu8(mask,y*w+math.clamp(x+k,0,w-1))*weights[k] end
			buffer.writef32(tmp,(y*w+x)*4,v)
		end end
		for y=0,h-1 do if checkpoint and y%8==0 then checkpoint() end;for x=0,w-1 do
			local v=0
			for k=-look.radius,look.radius do v+=buffer.readf32(tmp,(math.clamp(y+k,0,h-1)*w+x)*4)*weights[k] end
			buffer.writef32(field,(y*w+x)*4,v)
		end end
		fields[owner]=field
	end
	local function sample(field: buffer,x: number,y: number): (number,number,number)
		local bx,by=math.floor(x-.5),math.floor(y-.5)
		local fx,fy=x-.5-bx,y-.5-by
		local function at(px,py) return buffer.readf32(field,(math.clamp(py,0,h-1)*w+math.clamp(px,0,w-1))*4) end
		local a,b,c,d=at(bx,by),at(bx+1,by),at(bx,by+1),at(bx+1,by+1)
		return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy,(b-a)*(1-fy)+(d-c)*fy,(c-a)*(1-fx)+(d-b)*fx
	end
	local out=buffer.create(w*h*16)
	for y=0,h*2-1 do if checkpoint and y%4==0 then checkpoint() end;for x=0,w*2-1 do
		local px,py=(x+.5)/2,(y+.5)/2
		local top,sum,owner,gx,gy=0,0,0,0,0
		for side,field in fields do
			local value,dx,dy=sample(field,px,py);sum+=value
			if value>top then top,owner,gx,gy=value,side,dx,dy end
		end
		if top<=look.none then continue end
		local gradient=math.max(.001,math.sqrt(gx*gx+gy*gy))
		local distance=if top>=look.whole then 1000 else (top-.5)/gradient
		local facing=sum-top>look.rival
		local cover=if facing then (if distance>=0 then 1 else 0) else math.clamp(distance*2+.5,0,1)
		if cover<=0 then continue end
		local t=math.clamp(distance/look.band,0,1)
		local wash=look.wash*(look.inner+(1-look.inner)*(1-t*t*(3-2*t)))*cover
		local alpha=wash
		local tint=palette[owner] or palette[1]
		local r,g,b=tint[1],tint[2],tint[3]
		if distance<look.line*2 then
			local line=math.clamp((look.line-distance)*2+.5,0,1)*cover
			if facing and distance<=look.line and ((px*(-gy/gradient)+py*(gx/gradient))%look.dashPeriod)<look.dashOn then
				r,g,b=r+(1-r)*look.lift,g+(1-g)*look.lift,b+(1-b)*look.lift;alpha=1
			else alpha=math.max(alpha,look.border*line) end
		end
		if built and buffer.readu8(built,math.min(h-1,math.floor(py))*w+math.min(w-1,math.floor(px)))~=0 then alpha=0 end
		local at=(y*w*2+x)*4
		buffer.writeu8(out,at,math.floor(r*255+.5));buffer.writeu8(out,at+1,math.floor(g*255+.5));buffer.writeu8(out,at+2,math.floor(b*255+.5));buffer.writeu8(out,at+3,math.floor(math.clamp(alpha,0,1)*255+.5))
	end end
	return out
end
return TerritoryPixels
