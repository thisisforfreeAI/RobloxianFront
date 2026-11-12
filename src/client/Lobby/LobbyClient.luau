--!strict
--[[
	LobbyClient: a thin client wrapper over the lobby directory remotes, with no UI. A lobby browser
	screen can call these and render the results; nothing here creates GUI or touches the HUD.

		local LobbyClient = require(path.to.Lobby.LobbyClient)
		local res = LobbyClient.browse({ hasSpace = true })   -- { ok, lobbies, refreshAfter } or { ok = false, message, retry }
		local j = LobbyClient.join(res.lobbies[1].lobbyId)     -- { ok, route } or { ok = false, reason, message, retry }
		LobbyClient.onNotice(function(n) ... end)              -- e.g. a teleport that failed after join returned ok

	When join fails with retry = true (full, gone, stale, closed...), refresh the list and let the player
	pick again; the message is ready to show as-is.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyProtocol = require(ReplicatedStorage:WaitForChild("Shared").Lobby.LobbyProtocol)

local LobbyClient = {}

local function remotes(): Instance?
	return ReplicatedStorage:WaitForChild(LobbyProtocol.FOLDER, 10)
end

local function invoke(name: string, ...: any): { [string]: any }
	local folder = remotes()
	local remote = folder and folder:FindFirstChild(name)
	if not remote or not remote:IsA("RemoteFunction") then
		return { ok = false, reason = "unavailable", message = "The lobby directory is unavailable right now.", retry = true }
	end
	local ok, result = pcall((remote :: RemoteFunction).InvokeServer, remote, ...)
	if not ok or type(result) ~= "table" then
		return { ok = false, reason = "unavailable", message = "The lobby directory is unavailable right now.", retry = true }
	end
	return result
end

function LobbyClient.browse(filter: { [string]: any }?): { [string]: any }
	return invoke(LobbyProtocol.BROWSE, filter)
end

function LobbyClient.join(lobbyId: string): { [string]: any }
	return invoke(LobbyProtocol.JOIN, lobbyId)
end

function LobbyClient.setVisibility(visibility: string): { [string]: any }
	return invoke(LobbyProtocol.SET_VISIBILITY, visibility)
end

function LobbyClient.onNotice(fn: ({ [string]: any }) -> ()): RBXScriptConnection?
	local folder = remotes()
	local remote = folder and folder:FindFirstChild(LobbyProtocol.NOTICE)
	if remote and remote:IsA("RemoteEvent") then
		return remote.OnClientEvent:Connect(fn)
	end
	return nil
end

return LobbyClient
