--!strict
--[[
	BuildController: placing a barracks or factory.
	Start placing from the HUD (or B / F, PROVISIONAL keys until WarFront's bindings are confirmed); a
	3 x 3 cell ghost follows the cursor, snapped to cells. Green: every footprint cell is inside your
	territory (from the server's state); red: it is not. Left click asks the server to build there
	(Shift keeps placing); right click or Esc cancels. The server runs the game's full placement check
	(roads, rigs, spacing, territory, enemy gap, requirements, oil) and answers with a notice if refused.
	PLACEHOLDER visuals (TEMP-003).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local BuildController = {}

local S = World.STUDS_PER_CELL
local FOOT = 1 -- production.footprint.facility
local placing: string? = nil
local lastPlaced = -1
local ghost: Part
local inside: { [number]: boolean } = {}
local width = 0
local sendIntent: (any) -> () = function(_p: any) end

local function groundPoint(screen: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local map = workspace:FindFirstChild("WarFrontMap")
	if not map then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map:FindFirstChild("Ground") :: Instance }
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
			if not inside[y * width + x] then
				return false
			end
		end
	end
	return true
end

function BuildController.start(mapWidth: number, send: (any) -> ())
	width = mapWidth
	sendIntent = send
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch, ghost.CastShadow = true, false, false, false, false
	ghost.Size = Vector3.new((FOOT * 2 + 1) * S, 1.2, (FOOT * 2 + 1) * S)
	ghost.Material = Enum.Material.Neon
	ghost.Transparency = 1
	ghost.Parent = workspace

	RunService.RenderStepped:Connect(function()
		if not placing then
			ghost.Transparency = 1
			return
		end
		local cx, cy = cursorCell()
		if not cx or not cy then
			ghost.Transparency = 1
			return
		end
		ghost.CFrame = CFrame.new(World.toWorld(cx + 0.5, cy + 0.5, 0.7))
		ghost.Color = if allInside(cx, cy) then Color3.fromRGB(110, 230, 120) else Color3.fromRGB(235, 90, 80)
		ghost.Transparency = 0.45
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not placing then
			if not processed and input.KeyCode == Enum.KeyCode.B then
				BuildController.begin("barracks")
			elseif not processed and input.KeyCode == Enum.KeyCode.F then
				BuildController.begin("factory")
			end
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
			lastPlaced = os.clock()
		end
	end)
end

function BuildController.begin(kind: string)
	placing = kind
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
