--!strict
--[[
	LobbyProtocol: names of the lobby directory's remotes. Kept apart from Protocol.luau so the lobby
	feature can be wired in (or left out) without touching the match protocol.

	Browse (RemoteFunction, client -> server)
		args:    filter? = { map: string?, status: "waiting"|"inProgress"?, hasSpace: boolean?,
		                     friendsOnly: boolean?, limit: number? }
		returns: { ok = true, lobbies = { LobbyView }, refreshAfter = seconds }
		       | { ok = false, reason = string, message = string, retry = boolean, refreshAfter = seconds }
		LobbyView = { lobbyId, name, map, players, capacity, openSeats, status, visibility,
		              joinInProgress, joinable, hostUserId, expiresIn, ageSec }

	Join (RemoteFunction, client -> server)
		args:    lobbyId: string
		returns: { ok = true, route = "local" | "teleport" }   ("teleport": the teleport has started)
		       | { ok = false, reason = string, message = string, retry = boolean }
		On ok + "teleport" the client should show a "joining..." state; if the teleport later fails the
		server fires Notice with reason "teleportFailed".

	SetVisibility (RemoteFunction, client -> server)  -- host only
		args:    visibility: "public" | "friends" | "private"
		returns: { ok = boolean, reason = string? }

	Notice (RemoteEvent, server -> client)
		payload: { reason = string, message = string, retry = boolean }
]]

local LobbyProtocol = {}

LobbyProtocol.FOLDER = "WarFrontLobby"
LobbyProtocol.BROWSE = "Browse"
LobbyProtocol.JOIN = "Join"
LobbyProtocol.SET_VISIBILITY = "SetVisibility"
LobbyProtocol.NOTICE = "Notice"

LobbyProtocol.BROWSE_COOLDOWN_SEC = 2 -- per player; faster requests get the cached answer
LobbyProtocol.JOIN_COOLDOWN_SEC = 3
LobbyProtocol.REFRESH_AFTER_SEC = 10 -- suggested client auto-refresh

return LobbyProtocol
