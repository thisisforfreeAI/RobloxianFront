--!strict
-- Server entry point: starts one match on the Saddle map.
local MatchService = require(script.Match.MatchService)
local LobbyServer = require(script.Lobby.LobbyServer)

MatchService.enableLobby() -- Gate client Join before publishing the match remotes.
MatchService.start("Saddle")
MatchService.setLobby(LobbyServer.start(MatchService.lobbyState))
