--!strict
-- Net: creates the remotes and wraps sending. Server only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Protocol = require(ReplicatedStorage:WaitForChild("Shared").Protocol.Protocol)

local Net = {}

local folder: Folder
local intent: RemoteEvent
local snapshot: RemoteEvent
local join: RemoteFunction
local state: RemoteEvent

function Net.init(onIntent: (Player, any) -> (), onJoin: (Player) -> { [string]: any })
	folder = Instance.new("Folder")
	folder.Name = Protocol.FOLDER
	intent = Instance.new("RemoteEvent")
	intent.Name = Protocol.INTENT
	intent.Parent = folder
	snapshot = Instance.new("RemoteEvent") -- reliable: unreliable events cap payloads near 1 KB
	snapshot.Name = Protocol.SNAPSHOT
	snapshot.Parent = folder
	state = Instance.new("RemoteEvent")
	state.Name = Protocol.STATE
	state.Parent = folder
	join = Instance.new("RemoteFunction")
	join.Name = Protocol.JOIN
	join.Parent = folder
	join.OnServerInvoke = onJoin
	folder.Parent = ReplicatedStorage
	intent.OnServerEvent:Connect(onIntent)
end

-- units: { id, kind, side, x, y, heading, hp, maxHp };
-- structures: { id, kind, side, x, y, hp, maxHp, capSide, capProgress, store, built, stale };
-- vision: row runs { y, x0, x1, ... } of cells the player's side sees, sent only when it changed
-- (nil = unchanged); seeAll: true when there is no fog for this player; deaths: vehicles destroyed
-- since the last snapshot where this player could see them, { id, kind, x, y, hull, turret } (wrecks).
-- collapses: optional bounded visible structure losses { id, kind, x, y }; transient, never replayed.
function Net.sendSnapshot(player: Player, tick: number, units: { any }, structures: { any }, vision: { number }?, seeAll: boolean, deaths: { any }?, collapses: { any }?)
	snapshot:FireClient(player, tick, units, structures, vision, seeAll, deaths, collapses)
end

function Net.sendState(player: Player, payload: { [string]: any })
	state:FireClient(player, payload)
end

return Net
