--!strict
--[[
	CameraController: top-down RTS camera. North (cell y = 0) is screen-up.
	Pan: WASD / arrow keys, or hold the middle mouse button and drag. Zoom: mouse wheel.
	Bindings are PROVISIONAL until WarFront's own bindings are confirmed.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage:WaitForChild("Shared").Config.World)

local CameraController = {}

local S = World.STUDS_PER_CELL
local MIN_HEIGHT, MAX_HEIGHT = 40, 900
local FOV = 30

local focus = Vector3.zero
local height = 220
local bounds = { minX = 0, maxX = 0, minZ = 0, maxZ = 0 }
local dragging = false

local function clampFocus()
	focus = Vector3.new(math.clamp(focus.X, bounds.minX, bounds.maxX), 0, math.clamp(focus.Z, bounds.minZ, bounds.maxZ))
end

function CameraController.start(mapWidth: number, mapHeight: number, start: { x: number, y: number })
	local camera = workspace.CurrentCamera
	bounds = { minX = 0, maxX = mapWidth * S, minZ = 0, maxZ = mapHeight * S }
	focus = World.toWorld(start.x, start.y)
	clampFocus()

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			height = math.clamp(height * (1 - input.Position.Z * 0.12), MIN_HEIGHT, MAX_HEIGHT)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			-- World units per pixel at the current height and field of view.
			local perPixel = 2 * height * math.tan(math.rad(FOV / 2)) / camera.ViewportSize.Y
			focus -= Vector3.new(input.Delta.X * perPixel, 0, input.Delta.Y * perPixel)
			clampFocus()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			dragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			dragging = false
		end
	end)

	RunService:BindToRenderStep("WarFrontCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FOV
		if not UserInputService:GetFocusedTextBox() then
			local dir = Vector3.zero
			local down = UserInputService.IsKeyDown
			if down(UserInputService, Enum.KeyCode.W) or down(UserInputService, Enum.KeyCode.Up) then dir -= Vector3.zAxis end
			if down(UserInputService, Enum.KeyCode.S) or down(UserInputService, Enum.KeyCode.Down) then dir += Vector3.zAxis end
			if down(UserInputService, Enum.KeyCode.A) or down(UserInputService, Enum.KeyCode.Left) then dir -= Vector3.xAxis end
			if down(UserInputService, Enum.KeyCode.D) or down(UserInputService, Enum.KeyCode.Right) then dir += Vector3.xAxis end
			if dir.Magnitude > 0 then
				focus += dir.Unit * height * 0.9 * dt
				clampFocus()
			end
		end
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, height, 0.001), focus, -Vector3.zAxis)
	end)
end

return CameraController
