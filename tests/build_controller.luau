--!strict
return function(test:any,eq:any)
	local fs=require("@lune/fs");local luau=require("@lune/luau");local rb=require("@lune/roblox")
	local H=require("../src/shared/Presentation/PlacementHint");local Roads=require("../src/shared/Simulation/Roads")
	local function fixture():any
		local h:any={time=0,instances={},sent={},hit=rb.Vector3.new(10,0,10),down={},previewEnabled=true}
		local function signal() local s:any={callbacks={}};function s:Connect(fn) local c:any={fn=fn};function c:Disconnect() self.dead=true end;table.insert(self.callbacks,c);return c end;function s:fire(...) for _,c in table.clone(self.callbacks) do if not c.dead then c.fn(...) end end end;return s end
		local input={InputBegan=signal(),InputEnded=signal(),GetMouseLocation=function() return rb.Vector2.new(200,100) end,IsKeyDown=function(_,key) return h.down[key]==true end};h.input=input;h.render=signal()
		local keys={};for _,key in {"B","F","K","G","Y","U","Semicolon","Quote","Minus","Escape","LeftShift","RightShift"} do keys[key]=key end;h.keys=keys
		local function instance(class) local o:any={ClassName=class};function o:Destroy() self.dead=true end;table.insert(h.instances,o);return o end
		local world={STUDS_PER_CELL=4,GROUND_Y=0,TOP_GUI_YAW=-math.pi/2,toWorld=function(x,y,z) return rb.Vector3.new(x*4,z or 0,y*4) end,toCell=function(p) return p.X/4,p.Z/4 end}
		local shared={Config={World="world"},Presentation={PlacementHint="hint"},Simulation={Roads="roads"}}
		local modules={world=world,hint=H,roads=Roads,coverage={update=function(kind,cx,cy,side,rules,views,pixels) h.coverage={kind=kind,cx=cx,cy=cy,side=side,rules=rules,views=views,pixels=pixels} end,hide=function() h.coverageHidden=(h.coverageHidden or 0)+1 end,destroy=function() h.coverageDestroyed=(h.coverageDestroyed or 0)+1 end},preview={update=function(part,kind,army,side,hint,pixels,rules) h.preview={part=part,kind=kind,army=army,side=side,hint=hint,pixels=pixels,rules=rules};return h.previewEnabled end,hide=function() h.hidden=(h.hidden or 0)+1 end,destroy=function() h.destroyed=(h.destroyed or 0)+1 end}}
		local camera={CFrame=rb.CFrame.new(0,100,0),ViewportSize=rb.Vector2.new(800,600),FieldOfView=30,ViewportPointToRay=function(_,x,y) h.ray={x,y};return {Origin=rb.Vector3.zero,Direction=rb.Vector3.new(0,-1,0)} end}
		local workspace={CurrentCamera=camera,FindFirstChild=function() return if h.noMap then nil else {FindFirstChild=function() return if h.noGround then nil else {} end} end,Raycast=function() return if h.hit then {Position=h.hit} else nil end}
		local services={UserInputService=input,RunService={RenderStepped=h.render},ReplicatedStorage={Shared=shared,WaitForChild=function() return shared end}}
		local env=setmetatable({game={GetService=function(_,key) return services[key] end},script={Parent={Parent={Rendering={BuildPreview="preview",CoverageRenderer="coverage"}}}},require=function(key) return modules[key] end,workspace=workspace,
			Instance={new=instance},Vector3=rb.Vector3,Vector2=rb.Vector2,CFrame=rb.CFrame,Color3=rb.Color3,RaycastParams={new=function() return {} end},Enum={KeyCode=keys,UserInputType={MouseButton1="left",MouseButton2="right"},RaycastFilterType={Include=1},Material={Neon=1}},os={clock=function() local at=h.time;h.time+=h.work or 0;return at end},warn=function() h.warnings=(h.warnings or 0)+1 end},{__index=getfenv()})
		h.controller=luau.load(fs.readFile("src/client/Input/BuildController.luau"),{environment=env})()
		h.options={map={width=10,height=10,terrain=buffer.create(100),data={legend={"plains"},roads={},rigs={}}},rules={["terrain.plains.passable"]=true,["terrain.plains.buildable"]=true,["structures.barracks.cost"]=50},side=1,structures=function() return {} end}
		function h:start() self.controller.start(10,function(payload) table.insert(self.sent,payload) end,self.options);local runs={};for y=0,9 do table.insert(runs,y);table.insert(runs,0);table.insert(runs,9) end;self.controller.setTerritory(runs) end
		function h:click(kind,processed) self.input.InputBegan:fire({UserInputType=kind,KeyCode="unknown"},processed or false) end
		h:start();return h
	end
	test("placement controller preserves cursor rays and sends exactly one server build even when locally refused",function()
		local h=fixture();h.controller.update({army="republic",oil=0});h.input.InputBegan:fire({KeyCode="B"},false);h.render:fire()
		eq(h.ray[1],200);eq(h.ray[2],100);eq(h.preview.kind,"barracks");eq(h.preview.army,"republic");eq(h.preview.hint.ok,false)
		eq(h.preview.rules,h.options.rules);eq(h.coverage.kind,"barracks");eq(h.coverage.rules,h.options.rules);eq(h.coverage.cx,2);eq(h.coverage.cy,2)
		h:click("left");eq(#h.sent,1);eq(h.sent[1].kind,"build");eq(h.sent[1].x,2);eq(h.sent[1].y,2)
		h:click("left");eq(#h.sent,1);h.render:fire();assert(h.hidden>0);assert(h.coverageHidden>0)
	end)
	test("shift placement, processed UI clicks and cancellation keep existing intent behavior",function()
		local h=fixture();h.controller.begin("factory");h.down.LeftShift=true;h:click("left",true);eq(#h.sent,0)
		h:click("left");h:click("left");eq(#h.sent,2);eq(h.controller.busy(),true)
		h:click("right");h.render:fire();h:click("left");eq(#h.sent,2);h.time=1;eq(h.controller.busy(),false)
	end)
	test("mine and trench strokes retain their server commands while the building preview hides",function()
		local h=fixture();h.controller.begin("minefield");h:click("left");h.render:fire();h.input.InputEnded:fire({UserInputType="left"});eq(h.sent[1].kind,"layMines");eq(#h.sent[1].pts,2)
		h.controller.beginTrench({7,8});h:click("left");h.render:fire();h.input.InputEnded:fire({UserInputType="left"});eq(h.sent[2].kind,"dig");eq(h.sent[2].unitIds[1],7);eq(h.sent[2].trench,"ditch");assert(h.hidden>0)
	end)
	test("partial private state and missing map/camera hits preserve safe preview fallbacks",function()
		local h=fixture();h.controller.update({oil=0,army="republic"});h.controller.update({houseFires={}});h.controller.begin("barracks");h.render:fire();eq(h.preview.hint.reason,"oil")
		h.noGround=true;h.render:fire();local part=h.preview.part;eq(part.Transparency,1)
		h.noGround=false;h.previewEnabled=false;h.render:fire();eq(part.Transparency,.45)
		h.hit=rb.Vector3.new(-2,0,10);h.render:fire();eq(h.preview.hint.ok,false)
	end)
	test("road preparation yields across frames and publishes only a finished local model",function()
		local h=fixture();h.options.map.data.roads={};for _=1,100 do table.insert(h.options.map.data.roads,{rank=1,pts={.5,.5,9.5,.5}}) end
		h.work=.01;h:start();h.hit=rb.Vector3.new(10,0,30);h.controller.update({oil=0});h.controller.begin("barracks")
		h.render:fire();eq(h.preview.hint.ok,true)
		for _=1,30 do h.render:fire() end;eq(h.preview.hint.reason,"oil");eq(h.warnings,nil)
	end)
	test("a failed optional local map check warns once and keeps the existing territory preview",function()
		local h=fixture();h.options.map.terrain=buffer.create(0);h.options.map.data.roads={{rank=1,pts={.5,.5,9.5,.5}}};h:start();h.controller.begin("barracks")
		for _=1,10 do h.render:fire() end;eq(h.warnings,1);eq(h.preview.hint.ok,true)
	end)
	test("restarting placement disconnects old input/render handlers and destroys old ghosts and strokes",function()
		local h=fixture();h.controller.begin("barracks");h.render:fire();local part=h.preview.part
		h:start();eq(part.dead,true);h.controller.begin("barracks");h:click("left");eq(#h.sent,1)
		h.controller.destroy();h.time=1;eq(h.controller.busy(),false);h.controller.begin("barracks");h:click("left");eq(#h.sent,1)
	end)
	test("opening a modal cancels placement and strokes without leaking intents or new hotkey previews",function()
		local h=fixture();h.options.blocked=function() return h.blocked end;h:start()
		h.controller.begin("minefield");h:click("left");h.render:fire();h.controller.cancel();h.blocked=true
		h.input.InputEnded:fire({UserInputType="left"});h.input.InputBegan:fire({KeyCode="B"},false);h.render:fire();h:click("left");eq(#h.sent,0)
		h.blocked=false;h.controller.begin("barracks");h:click("left");eq(#h.sent,1)
	end)
end

