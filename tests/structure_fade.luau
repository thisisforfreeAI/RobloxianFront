--!strict
return function(test:any,eq:any)
	local F=require('../src/client/Rendering/StructureFade')
	local function fixture()
		local nodes={};local gui={GetDescendants=function() return nodes end};local h=F.new(gui)
		local function add(class,bg,image) local o={Parent=gui,BackgroundTransparency=bg,ImageTransparency=image,IsA=function(_,k) return k==class end};table.insert(nodes,o);return o end
		return h,add,nodes
	end
	test('LOD alpha restores original values and repeated zoom never accumulates opacity loss',function()
		local h,add=fixture();local img=add('ImageLabel',1,.2);local box=add('Frame',.4)
		for _=1,100 do F.set(h,.5);assert(math.abs(img.ImageTransparency-.6)<1e-9);F.set(h,1);eq(img.ImageTransparency,.2);eq(box.BackgroundTransparency,.4) end
		F.set(h,0);eq(h.gui.Enabled,false);F.set(h,1);eq(h.gui.Enabled,true)
	end)
	test('live poses and newly created labels retain their native alpha during a zoom transition',function()
		local h,add,nodes=fixture();local img=add('ImageLabel',1,.2);F.set(h,.5)
		F.restore(h);img.ImageTransparency=.8;local new=add('Frame',.6);F.apply(h,.5)
		assert(math.abs(img.ImageTransparency-.9)<1e-9);assert(math.abs(new.BackgroundTransparency-.8)<1e-9)
		img.Parent=nil;table.remove(nodes,1);F.restore(h);F.apply(h,.5);eq(h.tracks[img],nil)
		F.restore(h);F.apply(h,1);eq(new.BackgroundTransparency,.6);eq(next(h.tracks),nil)
	end)
end
