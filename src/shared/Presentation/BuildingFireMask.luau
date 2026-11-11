--!strict
-- Shared visible roof damage for projected facade windows. Hidden changes never enter this state.
local Mask={}
function Mask.new(width:number,height:number,tile:number):any
	local fineWidth=width*tile;local total=fineWidth*height*tile
	local self:any={char={},active={},revision=0}
	function self.any():boolean return next(self.char)~=nil or next(self.active)~=nil end
	function self.reset() if self.any() then self.revision+=1 end;table.clear(self.char);table.clear(self.active) end
	function self.apply(rows:{any})
		for _,row in rows do
			local p,stage=row[1],row[2]
			assert(type(p)=="number" and p>=0 and p<total and p%1==0 and type(stage)=="number" and stage>=0 and stage<=3 and stage%1==0,"invalid roof damage")
			local value=if stage>0 then stage else nil
			if self.char[p]~=value then self.char[p]=value;self.revision+=1 end
		end
	end
	function self.actors(actors:any)
		local active={};for _,a in actors do for _,p in a.px do active[p]=true end end
		local changed=false;for p in active do if not self.active[p] then changed=true;break end end
		if not changed then for p in self.active do if not active[p] then changed=true;break end end end
		self.active=active;if changed then self.revision+=1 end
	end
	function self.blocked(x:number,y:number):boolean
		if x<0 or y<0 or x>=fineWidth or y>=height*tile then return false end
		local p=math.floor(y)*fineWidth+math.floor(x);return self.char[p]~=nil or self.active[p]==true
	end
	return self
end
return Mask
