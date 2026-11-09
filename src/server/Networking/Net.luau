--!strict
-- Net: creates the remotes and wraps sending. Server only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Protocol = require(ReplicatedStorage:WaitForChild("Shared").Protocol.Protocol)

local Net = {}

local folder: Folder
local intent: RemoteEvent
local snapshot: RemoteEvent
local join: RemoteFunction

function Net.init(onIntent: (Player, any) -> (), onJoin: (Player) -> { [string]: any })
	folder = Instance.new("Folder")
	folder.Name = Protocol.FOLDER
	intent = Instance.new("RemoteEvent")
	intent.Name = Protocol.INTENT
	intent.Parent = folder
	snapshot = Instance.new("RemoteEvent") -- reliable: unreliable events cap payloads near 1 KB
	snapshot.Name = Protocol.SNAPSHOT
	snapshot.Parent = folder
	join = Instance.new("RemoteFunction")
	join.Name = Protocol.JOIN
	join.Parent = folder
	join.OnServerInvoke = onJoin
	folder.Parent = ReplicatedStorage
	intent.OnServerEvent:Connect(onIntent)
end

function Net.broadcastSnapshot(tick: number, units: { any })
	snapshot:FireAllClients(tick, units)
end

return Net
