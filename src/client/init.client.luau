--!strict
-- Client entry point: asks the server to join (gets map + side), then builds the view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Protocol.Protocol)
local MapCodec = require(Shared.Maps.MapCodec)

local MapRenderer = require(script.Rendering.MapRenderer)
local UnitRenderer = require(script.Rendering.UnitRenderer)
local StructureRenderer = require(script.Rendering.StructureRenderer)
local FogOverlay = require(script.Rendering.FogOverlay)
local CityOverlay = require(script.Rendering.CityOverlay)
local CameraController = require(script.Camera.CameraController)
local SelectionController = require(script.Input.SelectionController)
local BuildController = require(script.Input.BuildController)
local Hud = require(script.UI.Hud)
local DevFlags = require(script.Dev.DevFlags)

local net = ReplicatedStorage:WaitForChild(Protocol.FOLDER)
local join = net:WaitForChild(Protocol.JOIN) :: RemoteFunction
local snapshot = net:WaitForChild(Protocol.SNAPSHOT) :: RemoteEvent
local intent = net:WaitForChild(Protocol.INTENT) :: RemoteEvent
local stateEvent = net:WaitForChild(Protocol.STATE) :: RemoteEvent

do
	local info = join:InvokeServer()
	local mapModule = Shared:WaitForChild("GameData").Maps:FindFirstChild(string.upper(string.sub(info.map, 1, 1)) .. string.sub(info.map, 2))
	assert(mapModule, `no map module for {info.map}`)
	local map = MapCodec.decode(require(mapModule) :: any)

	MapRenderer.build(map)
	FogOverlay.start(map.width, map.height)
	CameraController.start(map.width, map.height, map.data.starts[info.side] or map.data.starts[1])
	UnitRenderer.start()
	StructureRenderer.start()
	CityOverlay.start((map.data :: any).settlements or {})
	local function send(payload: any)
		intent:FireServer(payload)
	end
	BuildController.start(map.width, send)
	Hud.start(info, {
		produce = function(item: string, structureId: number?)
			send({ kind = "produce", item = item, structureId = structureId })
		end,
		build = BuildController.begin,
	})
	stateEvent.OnClientEvent:Connect(function(state)
		Hud.update(state, info.side)
		if state.territory then
			BuildController.setTerritory(state.territory)
		end
		if state.cities then
			CityOverlay.apply(state.cities)
		end
	end)
	SelectionController.start(info.side, send, {
		busy = BuildController.busy,
		onProducer = Hud.selectProducer,
	})
	if DevFlags.OWNERSHIP_PROBE then
		require(script.Dev.OwnershipProbe).start(info.side, UnitRenderer.each, function(payload)
			intent:FireServer(payload)
		end)
	end
	if DevFlags.ATLAS_TEST_BOARD then
		local start = map.data.starts[info.side] or map.data.starts[1]
		local cy = math.max(16, start.y - 30) -- north of the start, inside the map
		local board = require(script.Dev.AtlasTestBoard)
		local cx = math.clamp(start.x, 16, map.width - 46)
		task.spawn(board.start, Vector2.new(cx, cy), "SynVehicleArrow", true)
		task.spawn(board.start, Vector2.new(cx + 30, cy), "ScoutCar", false) -- REQ-0001 pilot, east of the arrows
	end

	snapshot.OnClientEvent:Connect(function(tick, units, structures, vision, seeAll)
		UnitRenderer.apply(tick, units)
		StructureRenderer.apply(tick, structures or {})
		if vision then
			FogOverlay.apply(vision, seeAll == true)
		end
	end)
end
