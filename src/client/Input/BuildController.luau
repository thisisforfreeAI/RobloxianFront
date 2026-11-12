--!strict
--[[
	BuildController: placing a barracks, factory, bunker or AT gun.
	Start placing from the HUD (or B / F / K / G, PROVISIONAL keys until WarFront's bindings are confirmed); a
	3 x 3 cell ghost follows the cursor, snapped to cells. Its source-style art and local checks use
	public terrain/roads, own resources/territory and known structure snapshots. Left click asks the server to build there
	(Shift keeps placing); right click or Esc cancels. The server runs the game's full placement check
	(roads, rigs, spacing, territory, enemy gap, requirements, oil) and answers with a notice if refused.
	Minefield (Republic only, - key or the HUD): hold the left button and drag a line across the map
	(the game's drawMineStroke: a point every cell, at most 600); letting go asks the server to lay it.
	The server works out which cells take mines and the price. Right click or Esc cancels.
	Placement visuals share the source building atlas. Local validity is advisory; the server decides.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)
local Hint=require(ReplicatedStorage.Shared.Presentation.PlacementHint)
local Roads=require(ReplicatedStorage.Shared.Simulation.Roads)
local Preview=require(script.Parent.Parent.Rendering.BuildPreview)
local Coverage=require(script.Parent.Parent.Rendering.CoverageRenderer)

local BuildController = {}

local S = World.STUDS_PER_CELL
local FOOT = 1 -- production.footprint.facility and .defence
local KEYS = { [Enum.KeyCode.B] = "barracks", [Enum.KeyCode.F] = "factory", [Enum.KeyCode.K] = "bunker", [Enum.KeyCode.G] = "atgun", [Enum.KeyCode.Y] = "radar", [Enum.KeyCode.U] = "sam", [Enum.KeyCode.Semicolon] = "artybase", [Enum.KeyCode.Quote] = "nightops", [Enum.KeyCode.Minus] = "minefield" }
local stroke: { { x: number, y: number } } = {}
local drawing = false
local strokeParts: { Part } = {}
local trenchIds: { number } = {} -- engineers digging the line being drawn (placing == "trench")
local TRENCH_KINDS = { "ditch", "fire", "traps", "wire" }
local trenchKind = 1 -- which of TRENCH_KINDS key 9 picked
local placing: string? = nil
local lastPlaced = -1
local ghost: Part
local inside: { [number]: boolean } = {}
local width = 0
local height=0
local connections:{any}={}
local model:any=nil
local preparing:any=nil
local side=0
local army="coalition"
local privateState:any=nil
local structures:any=function() return {} end
local placementRules:any=nil
local sendIntent: (any) -> () = function(_p: any) end

local function groundPoint(screen: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y) -- Preserve the existing raw mouse/viewport coordinates.
	local map = workspace:FindFirstChild("WarFrontMap")
	if not map then
		return nil
	end
	local ground=map:FindFirstChild("Ground");if not ground then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	return if hit then hit.Position else nil
end

local function cursorCell(): (number?, number?)
	local hit = groundPoint(UserInputService:GetMouseLocation())
	if not hit then
		return nil, nil
	end
	local x, y = World.toCell(hit)
	return math.floor(x), math.floor(y)
end

local function allInside(cx: number, cy: number): boolean
	for y = cy - FOOT, cy + FOOT do
		for x = cx - FOOT, cx + FOOT do
			if x<0 or y<0 or x>=width or height>0 and y>=height then return false end
			if not inside[y * width + x] then
				return false
			end
		end
	end
	return true
end

local function connect(signal:any,fn:any) table.insert(connections,signal:Connect(fn)) end
function BuildController.destroy()
	for _,connection in connections do connection:Disconnect() end;table.clear(connections)
	Preview.destroy();Coverage.destroy();if ghost then ghost:Destroy();ghost=nil :: any end
	for _,part in strokeParts do part:Destroy() end;table.clear(strokeParts);table.clear(stroke);table.clear(inside)
	placing=nil;drawing=false;model=nil;preparing=nil;privateState=nil;placementRules=nil;structures=function() return {} end;trenchIds={};lastPlaced=-1
end
function BuildController.start(mapWidth: number, send: (any) -> (),options:any?)
	BuildController.destroy()
	width = mapWidth
	height=if options and options.map then options.map.height else 0;side=if options then options.side or 0 else 0;army="coalition"
	if options and options.structures then structures=options.structures end
	placementRules=options and options.rules
	if options and options.map and options.rules then
		preparing=coroutine.create(function()
			local count=0;local deadline=os.clock()+.002
			model=Hint.prepare(options.map,options.rules,Roads.line,function()
				count+=1;if count%64==0 and os.clock()>=deadline then coroutine.yield();deadline=os.clock()+.002 end
			end)
		end)
	end
	sendIntent = send
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch, ghost.CastShadow = true, false, false, false, false
	ghost.Size = Vector3.new((FOOT * 2 + 1) * S, .02, (FOOT * 2 + 1) * S)
	ghost.Material = Enum.Material.Neon
	ghost.Transparency = 1
	ghost.Parent = workspace

	connect(RunService.RenderStepped,function()
		if options and options.blocked and options.blocked() then
			if placing or drawing then BuildController.cancel() end
			return
		end
		if preparing then
			local ok,err=coroutine.resume(preparing)
			if not ok then warn("[BuildController] Local preview checks unavailable:",err) end
			if not ok or coroutine.status(preparing)=="dead" then preparing=nil end
		end
		if placing == "minefield" or placing == "trench" then
			Preview.hide()
			Coverage.hide()
			ghost.Transparency = 1
			if drawing then
				local hit = groundPoint(UserInputService:GetMouseLocation())
				if hit then
					local x, y = World.toCell(hit)
					local last = stroke[#stroke]
					if (not last or (x - last.x) ^ 2 + (y - last.y) ^ 2 >= 1) and #stroke < 600 then
						table.insert(stroke, { x = x, y = y })
						local p = strokeParts[#stroke]
						if not p then
							p = Instance.new("Part")
							p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
							p.Size = Vector3.new(S * 0.6, 0.4, S * 0.6)
							p.Material = Enum.Material.Neon
							p.Color = Color3.fromRGB(235, 200, 90)
							p.Parent = workspace
							strokeParts[#stroke] = p
						end
						p.Transparency = 0.3
						p.CFrame = CFrame.new(World.toWorld(x, y, 0.5))
					end
				end
			end
			return
		end
		for _, p in strokeParts do
			p.Transparency = 1
		end
		if not placing then
			Preview.hide()
			Coverage.hide()
			ghost.Transparency = 1
			return
		end
		local cx, cy = cursorCell()
		if not cx or not cy then
			Preview.hide()
			Coverage.hide()
			ghost.Transparency = 1
			return
		end
		ghost.CFrame = CFrame.new(World.toWorld(cx + 0.5, cy + 0.5, 0.7))*CFrame.Angles(0,World.TOP_GUI_YAW,0)
		local known=structures()
		local hint=if model then Hint.check(model,cx,cy,FOOT,inside,known,side,placing,privateState) else {ok=allInside(cx,cy),blocked={},clashes={}}
		local camera=workspace.CurrentCamera
		local pixels=math.max(1,(FOOT*2+1)*S*camera.ViewportSize.Y/(2*math.max(1,camera.CFrame.Position.Y-World.GROUND_Y)*math.tan(math.rad(camera.FieldOfView/2))))
		local rendered=Preview.update(ghost,placing,army,side,hint,pixels,placementRules)
		Coverage.update(placing,cx,cy,side,placementRules,known,pixels/(FOOT*2+1))
		ghost.Color = if hint.ok then Color3.fromRGB(110, 230, 120) else Color3.fromRGB(235, 90, 80)
		ghost.Transparency = if rendered then 1 else .45
	end)

	connect(UserInputService.InputBegan,function(input, processed)
		if options and options.blocked and options.blocked() then return end
		if not placing then
			if not processed and KEYS[input.KeyCode] then
				BuildController.begin(KEYS[input.KeyCode])
			end
			return
		end
		if (placing == "minefield" or placing == "trench") and input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			table.clear(stroke)
			drawing = true
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			local cx, cy = cursorCell()
			if cx and cy then
				sendIntent({ kind = "build", structure = placing, x = cx, y = cy })
			end
			lastPlaced = os.clock()
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if not shift then
				placing = nil
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Escape then
			placing = nil
			drawing = false
			lastPlaced = os.clock()
		end
	end)

	connect(UserInputService.InputEnded,function(input)
		if options and options.blocked and options.blocked() then BuildController.cancel();return end
		if (placing == "minefield" or placing == "trench") and drawing and input.UserInputType == Enum.UserInputType.MouseButton1 then
			drawing = false
			local pts = {}
			for _, p in stroke do
				table.insert(pts, math.floor(p.x * 10 + 0.5) / 10)
				table.insert(pts, math.floor(p.y * 10 + 0.5) / 10)
			end
			if #pts > 0 then
				if placing == "trench" then
					sendIntent({ kind = "dig", unitIds = trenchIds, pts = pts, trench = TRENCH_KINDS[trenchKind] })
				else
					sendIntent({ kind = "layMines", pts = pts })
				end
			end
			lastPlaced = os.clock()
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if not shift then
				placing = nil
			end
		end
	end)
end

function BuildController.begin(kind: string)
	drawing=false
	placing = kind
end

function BuildController.cancel()
	placing=nil;drawing=false;Preview.hide();Coverage.hide();lastPlaced=os.clock()
	if ghost then ghost.Transparency=1 end
	for _,part in strokeParts do part.Transparency=1 end
end

-- engineers dig a trench along the line dragged next
function BuildController.beginTrench(ids: { number })
	Preview.hide()
	drawing=false
	trenchIds = ids
	placing = "trench"
end
function BuildController.update(state:any)
	privateState=privateState or {}
	for _,key in {"oil","kills","lost","winner"} do if state[key]~=nil then privateState[key]=state[key] end end
	if state.army=="coalition" or state.army=="republic" then army=state.army end
end

-- the next trench kind (key 9); returns its name
function BuildController.cycleTrenchKind(): string
	trenchKind = trenchKind % #TRENCH_KINDS + 1
	return TRENCH_KINDS[trenchKind]
end

-- True while placing, and just after, so the click that placed or cancelled does not also select or order.
function BuildController.busy(): boolean
	return placing ~= nil or os.clock() - lastPlaced < 0.2
end

-- runs from the server: { y, x0, x1, y, x0, x1, ... } of cells inside your territory
function BuildController.setTerritory(runs: { number })
	table.clear(inside)
	for i = 1, #runs, 3 do
		local y, x0, x1 = runs[i], runs[i + 1], runs[i + 2]
		for x = x0, x1 do
			inside[y * width + x] = true
		end
	end
end

return BuildController
