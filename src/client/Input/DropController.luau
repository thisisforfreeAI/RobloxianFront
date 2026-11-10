--!strict
--[[
	DropController: the opening drop (the game's landing pick). While the server says the sides are
	picking, a left click on the map asks to land there (the server checks the spot: off the edge,
	open ground, room for an HQ, apart from the enemy's start) and Enter says you are ready. A ring
	marks your current pick (amber when no road there reaches the rigs, so the truck would have to
	drive before it can set up). PROVISIONAL keys; PLACEHOLDER look (TEMP-003).
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local DropController = {}

local S = World.STUDS_PER_CELL
local picking = false
local marker: Part? = nil
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

function DropController.start(send: (any) -> ())
	sendIntent = send
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not picking then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "dropPick", x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.Return then
			sendIntent({ kind = "dropReady" })
		end
	end)
end

-- drop: { phase, left, x, y, warn } from the server's state, or nil once the war is on
function DropController.apply(drop: any?)
	picking = drop ~= nil and drop.phase == "pick"
	if not drop or drop.phase == "done" then
		if marker then
			marker:Destroy()
			marker = nil
		end
		return
	end
	if not marker then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		p.Transparency = 0.4
		p.Size = Vector3.new(0.2 * S, 8 * S, 8 * S)
		p.Parent = workspace
		marker = p
	end
	local m = marker :: Part
	m.Color = if drop.warn then Color3.fromRGB(240, 180, 60) else Color3.fromRGB(110, 220, 120)
	m.CFrame = CFrame.new(World.toWorld(drop.x, drop.y, 0.2 * S)) * CFrame.Angles(0, 0, math.pi / 2)
end

return DropController
