--!strict
-- Client entry point: asks the server to join (gets map + side), then builds the view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Protocol.Protocol)
local MapCodec = require(Shared.Maps.MapCodec)

local MapRenderer = require(script.Rendering.MapRenderer)
local UnitRenderer = require(script.Rendering.UnitRenderer)
local CameraController = require(script.Camera.CameraController)
local SelectionController = require(script.Input.SelectionController)
local Hud = require(script.UI.Hud)
local DevFlags = require(script.Dev.DevFlags)

local net = ReplicatedStorage:WaitForChild(Protocol.FOLDER)
local join = net:WaitForChild(Protocol.JOIN) :: RemoteFunction
local snapshot = net:WaitForChild(Protocol.SNAPSHOT) :: RemoteEvent
local intent = net:WaitForChild(Protocol.INTENT) :: RemoteEvent

do
	local info = join:InvokeServer()
	local mapModule = Shared:WaitForChild("GameData").Maps:FindFirstChild(string.upper(string.sub(info.map, 1, 1)) .. string.sub(info.map, 2))
	assert(mapModule, `no map module for {info.map}`)
	local map = MapCodec.decode(require(mapModule) :: any)

	MapRenderer.build(map)
	CameraController.start(map.width, map.height, map.data.starts[info.side] or map.data.starts[1])
	UnitRenderer.start()
	Hud.start(info)
	SelectionController.start(info.side, function(payload)
		intent:FireServer(payload)
	end)
	if DevFlags.ATLAS_TEST_BOARD then
		local start = map.data.starts[info.side] or map.data.starts[1]
		local cy = math.max(16, start.y - 30) -- north of the start, inside the map
		task.spawn(require(script.Dev.AtlasTestBoard).start, Vector2.new(math.clamp(start.x, 16, map.width - 16), cy))
	end

	snapshot.OnClientEvent:Connect(function(tick, units)
		UnitRenderer.apply(tick, units)
	end)
end
