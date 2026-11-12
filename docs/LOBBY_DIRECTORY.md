# Cross-server lobby directory

A server-side directory of public lobbies across every live server of the experience. Each server publishes its own lobby (map, players/capacity, waiting/in-progress, visibility, expiry); any server can list them for its players and route a player to the right server. Nothing here is wired in yet, so it changes no current behaviour until the steps below are done.

**Status: written and unit-tested offline only.** Everything that talks to Roblox services (MemoryStore, MessagingService, TeleportService, friends) still has to be verified in published servers; see [Needs published-server testing](#needs-published-server-testing).

## Files

| File | Role |
|---|---|
| `src/shared/Lobby/LobbyDirectory.luau` | Pure rules, no Roblox services: building and validating listings, staleness and expiry, visibility, filtering and sorting, the join recheck, seat holds, arrival checks, routing. |
| `src/shared/Lobby/LobbyProtocol.luau` | Remote names, cooldowns and the request and response shapes. Kept separate from `Protocol.luau`. |
| `src/server/Lobby/LobbyDirectoryService.luau` | This server's half of the directory: heartbeat, browse cache, join, teleport failure, arrival, close. Roblox services are injected, so tests run it with fakes. |
| `src/server/Lobby/LobbyServer.luau` | The real Roblox wiring: MemoryStore sorted map, MessagingService topic, TeleportService, remotes, PlayerAdded/Removing, BindToClose. **This is the only file that can't be tested offline.** |
| `src/client/Lobby/LobbyClient.luau` | A thin client wrapper over the remotes. It has no UI. |
| `tests/lobby_directory.luau`, `tests/lobby_service.luau`, `tests/run_lobby.luau` | Offline tests: `lune run tests/run_lobby`. |

Untouched: `init.client.luau`, `init.server.luau`, `MatchService.luau`, `Net.luau`, `Protocol.luau`, every HUD and rendering file, and `tests/run.luau`.

## How it works

- **Store.** There is one MemoryStore sorted map, `LobbyDirectory_v1`, keyed by the owning server's `JobId`. The value is the listing record described at the top of `LobbyDirectory.luau`.
- **Heartbeat.** Each server rewrites its listing every 15 s (`HEARTBEAT_SEC`) with `UpdateAsync`. Every write carries a 60 s MemoryStore expiry (`STORE_TTL_SEC`), so a crashed server's listing deletes itself.
- **Stale listings are removed three ways.**
  1. A listing not rewritten for 45 s (`STALE_SEC`) is never shown or joined.
  2. Browsing servers delete up to 5 dead keys per directory read.
  3. MemoryStore expiry deletes everything else.

  On `BindToClose` the server deletes its own key at once and announces it on the MessagingService topic `LobbyDirectory_v1`, so other servers drop it from their cache before their next read.
- **Expiry.** A waiting lobby expires 30 min after it started waiting (`WAITING_EXPIRY_SEC`). The timer restarts whenever the server goes back to waiting, for example after a match ends. Any listing is capped at 4 h (`MAX_LIFETIME_SEC`). The match can also pass its own `expiresAt`. Clients see `expiresIn`.
- **Visibility.**
  - `public`: listed for everyone.
  - `friends`: listed only for the host and the host's Roblox friends.
  - `private`: never listed.

  Only the host (`hostUserId`) can change visibility, through `SetVisibility`. The change is written immediately.
- **Browse.**
  - Each server reads the directory at most once every 3 s and shares that read with all its players. It pages `GetRangeAsync` up to 1000 listings.
  - A player can browse at most once every 2 s. Faster requests get the previous answer.
  - Friendships are looked up with `IsFriendsWith` before filtering and cached for 120 s.
  - Results are sorted waiting first, then fullest, then newest.
  - Clients only ever get `publicView`. It has no JobId, access code or member ids.
- **Join.**
  1. The server re-reads the target listing fresh from the store. It doesn't use the browse cache.
  2. Inside one atomic `UpdateAsync` it rechecks everything: the lobby is live, not expired, not closing, visible to this player, not already joined by them, accepting players in its status, and has a free seat. If so, it holds a seat for 60 s (`RESERVATION_SEC`). Because the hold is atomic, two servers can't both give away the last seat.
  3. It teleports the player with `TeleportAsync` to the lobby's actual server:
     - an ordinary public server by `TeleportOptions.ServerInstanceId = JobId`
     - a reserved server by `ReservedServerAccessCode`
     - the player's own server needs no teleport (`route = "local"`)

  If the teleport fails, immediately or later through `TeleportInitFailed`, the seat is released and the player gets a `Notice`.
- **Arrival.**
  - When a player joins a server, it rechecks them against its own listing in the store (`checkArrival`).
  - A held seat or the host always gets a seat.
  - A stranger arriving at a friends-only or private lobby is refused. By default they are kicked with the reason; pass `onRefused` to send them to a hub instead.
  - Someone arriving at a full or started lobby is admitted without a seat, so the match can make them a spectator.
  - Teleport data is never trusted for permission. Only the hold in the store counts.
  - If the store can't be read, arrival fails open, because the match's own seat rules still apply.
- **Failures.** Every store call is wrapped in `pcall`. A failed read is reported as `unavailable` with `retry = true`, never as `gone`. Browse serves the last good read while the store is down.

## Server integration

`LobbyServer.start` should start after `MatchService.start` so the state function can read the match. MatchService does not expose its seat state yet, so add a small read-only accessor there, for example `MatchService.lobbyState()`, built from `sideOf`, `map` and `sim`.

```lua
-- src/server/init.server.luau
local MatchService = require(script.Match.MatchService)
local LobbyServer = require(script.Lobby.LobbyServer)

MatchService.start("Saddle")
local lobby = LobbyServer.start(function()
	local s = MatchService.lobbyState() -- to add: see below
	return {
		map = s.mapName,          -- e.g. "Saddle"
		players = s.humanSeats,   -- humans holding side 1 or 2 (not spectators, not bots)
		capacity = 2,             -- WarFront skirmish seats; spectators are extra
		status = s.started and "inProgress" or "waiting",
		joinInProgress = false,   -- true if a bot-held side may be taken over mid-match
		-- optional: name, hostUserId (needed for friends/private and SetVisibility), visibility, expiresAt
	}
end)
```

Where to get those values in `MatchService.luau`:

- `humanSeats`: count the entries in `sideOf` whose side is 1 or 2.
- `started`: decide when a lobby stops taking players. A reasonable start is "both seats are human, or the opening drop has finished" (`sim.drop == nil or sim.drop.phase == "done"`). This is a design choice. The original game's lobby rules are not confirmed.
- `mapName`: `map.data.id`.

**Seating.** In `assignSide`, which runs when the client invokes `Join`, wait for the arrival check before giving a side:

```lua
local arrival = lobby.waitArrival(player, 10)
if arrival and arrival.seat == false then
	-- full / started: seat as spectator (side 0)
end
```

`MatchService` would need the `lobby` object passed in, for example with `MatchService.setLobby(lobby)`. Refused players have already been kicked or sent away by `LobbyServer`.

**Reserved servers (for friends or private lobbies).** When code reserves a server for a host, record the access code, because the reserved server can't read its own:

```lua
local code, privateServerId = TeleportService:ReserveServer(game.PlaceId)
LobbyServer.rememberAccessCode(code, privateServerId)
-- then teleport the host there with TeleportOptions.ReservedServerAccessCode = code
-- and make the reserved server's state function return hostUserId = <host>, visibility = "friends"/"private"
```

Player-owned private (VIP) servers are never listed, because other servers can't teleport anyone into them.

## Client integration (no HUD changes required)

```lua
local LobbyClient = require(path.to.Lobby.LobbyClient)
local res = LobbyClient.browse({ hasSpace = true, map = nil, status = nil, friendsOnly = false })
if res.ok then
	-- each entry: lobbyId, name, map, players, capacity, openSeats, status ("waiting"/"inProgress"),
	-- visibility, joinable, expiresIn, ageSec; refresh again after res.refreshAfter seconds
else
	-- show res.message; offer Retry if res.retry
end

local j = LobbyClient.join(entry.lobbyId)
-- j.ok and j.route == "teleport": show "Joining..." (Roblox's teleport screen follows)
-- j.ok and j.route == "local": the lobby is this server; nothing to do
-- not j.ok: show j.message; if j.retry, refresh the list (full/gone/stale/closed/teleportFailed)
LobbyClient.onNotice(function(n) --[[ n.reason == "teleportFailed": show n.message, refresh ]] end)
```

Response and reason codes are listed in `LobbyProtocol.luau` and `LobbyDirectory.REASONS`.

## Tests

`lune run tests/run_lobby` runs 36 tests. They are not added to `tests/run.luau`. To include them in the full suite later, add `require("./lobby_directory")(test, eq)` and `require("./lobby_service")(test, eq)` there.

- **Pure rules:** validation and sanitising, staleness, expiry, visibility, hidden routing data, open seats with holds, browse sort, filters and limit, every join refusal, routing (instance, reserved, local), the last seat going only once, the hold cap, release, heartbeat merge, and arrival (hold, host, friends, private, full, started, fail-open).
- **Multi-server simulation:** several services share one fake MemoryStore with expiry, a fake MessagingService and fake teleports. The tests cover:
  - publish and browse, and the Studio no-JobId case
  - join holding a seat and teleporting, and two servers racing for one seat
  - teleport failure, both immediate and through `TeleportInitFailed`
  - the arrival recheck, and the heartbeat consuming the hold
  - stale servers being removed, and MemoryStore expiry
  - expiry restarting on a new waiting cycle, and close with the cross-server cache drop
  - friends-only and host-only visibility changes
  - store outages reported as unavailable
  - local joins, input validation and rate limits
  - routing by reserved access code, and unroutable servers not being published

The fake store runs every `UpdateAsync` transform twice, to check the transforms are safe to retry.

## Needs published-server testing

None of the following can be checked in Lune or a single Studio session. Studio has no `JobId`, so the server won't publish, and Studio can't teleport. Test in a published place with **Enable Studio Access to API Services** on, and with at least two live servers.

1. **MemoryStore calls really behave as the fakes assume:**
   - `GetSortedMap`, `GetAsync`, `UpdateAsync` (transform may retry; returning nil cancels without error), `RemoveAsync`, and `GetRangeAsync(Ascending, 200, exclusiveLowerBound)` paging.
   - Listings appear within one heartbeat, and a server shut down from the Creator Dashboard disappears at once.
   - A server killed without `BindToClose` disappears within 45–60 s.
2. **MemoryStore quotas** under real player counts. The request budget scales with players, and each browse read costs one unit per item returned. Watch the MemoryStore dashboard and for throttling warnings (`[Lobby] GetRangeAsync`). If it's too much, raise `CACHE_SEC` or lower `MAX_PAGES`.
3. **Cross-server teleports:**
   - `TeleportAsync` with `ServerInstanceId` lands in the exact server listed.
   - With `ReservedServerAccessCode` it lands in the reserved server.
   - `TeleportInitFailed` fires on a full or closed target, and the hold is released and the player is notified.
   - Teleporting to a server that filled up during the teleport puts the player in as a spectator, not stuck.
4. **The last-seat race:** two players on different servers join the last seat at the same moment. One should teleport and the other should get "full".
5. **Arrival recheck:** a teleported player's hold is found on the destination before they are seated (`waitArrival`). The next heartbeat drops the hold and counts the player.
6. **Friends-only and private visibility with real accounts:**
   - `IsFriendsWith` results and the 120 s cache.
   - A stranger can't see or join.
   - A friend can.
   - The host can switch visibility, and nobody else can.
   - A stranger who gets in another way (join-friend, matchmaking) is refused.
   - **Known limit:** a friends-only lobby on an ordinary public server can't stop Roblox matchmaking from sending strangers there, who are then kicked. Friends-only and private lobbies should live in reserved servers.
7. **Reserved servers:**
   - `rememberAccessCode` followed by the reserved server finding its code at startup, and being listed and routable.
   - A reserved server with no recorded code is not listed.
   - Player-owned private servers are not listed.
8. **MessagingService close broadcast:** after a server closes, other servers drop the lobby before their next directory read. Check the message limits too.
9. **Clock agreement:** staleness and expiry compare `os.time()` across servers. Check that a listing written by one server is not judged stale or expired early by another.
10. **Shutdown:** `BindToClose` delists before the server dies, including during a Roblox update ("Shut down all servers" or "Migrate to latest").
11. **MatchService integration** once it's added: the players count and the waiting/in-progress switch are right, and spectators beyond capacity work.
12. **Client flow** in the real UI: refresh, retry messages for full, gone and teleport failure, and the "Joining..." state.

## Known limits and choices to revisit

- At most 1000 listings are read per directory refresh (`MAX_PAGES` × 200). Past that, a sort key or regional maps would be needed.
- `capacity` counts match seats (2 for a skirmish). Spectators are not counted.
- When the directory can't be read, arrivals fail open. Change `checkArrival`'s nil case if a lobby should rather refuse.
- Friend status is checked against the host only, not against everyone in the lobby.
- The original game's lobby rules (when a lobby counts as started, bot seats) are not confirmed. The status mapping above is a suggestion.
