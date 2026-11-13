--!strict
-- Multiply original UI alpha without CanvasGroup render textures or a per-building image.
local Fade={}
function Fade.new(gui:any):any return {gui=gui,tracks={},mix=1} end
function Fade.restore(h:any)
	for item,properties in h.tracks do
		if item.Parent then for key,value in properties do item[key]=value end end
	end
	table.clear(h.tracks)
end
function Fade.apply(h:any,mix:number)
	mix=math.clamp(mix,0,1);h.mix=mix;h.gui.Enabled=mix>0
	if mix<=0 or mix>=1 then return end
	for _,item in h.gui:GetDescendants() do
		local keys=if item:IsA("ImageLabel") then {"BackgroundTransparency","ImageTransparency"} elseif item:IsA("Frame") then {"BackgroundTransparency"} else nil
		if not keys then continue end
		local values={};for _,key in keys do local base=item[key];values[key]=base;item[key]=1-(1-base)*mix end
		h.tracks[item]=values
	end
end
function Fade.set(h:any,mix:number)
	if h.mix==mix then return end
	Fade.restore(h);Fade.apply(h,mix)
end
return Fade
