# Cross-server match browser

The directory is connected to server startup, match seating and the client **Matches** button. It discovers available skirmishes across the experience's live servers and joins the selected server. Each server continues its current match. Host creation, ready/start controls, map selection and reserved-server provisioning remain future session work.

**Verification:** offline rule/service tests, API-shaped adapter tests, actual match-Join tests and browser state/UI stand-ins pass. Rojo builds. No native Studio visual pass or published two-server test has run. The API-shaped tests exercise our actual adapter but do not establish real Roblox service behavior.

## Using it

- Restart Play after syncing. **Matches**, near the upper right, opens the browser. In Roblox Player it shows map, human seats/capacity, stage and join availability.
- Filter by open seats, host friendships/friends-only lobbies, waiting stage or map name. Refresh manually or leave it open for automatic refresh. Polling stops when closed. Ordinary public skirmishes currently have hostUserId=0; hosted visibility controls are not exposed by this UI.
- A join stays pending while travel starts. Full, gone, unavailable and teleport-failure responses remain visible with refresh/retry. Old browse responses cannot replace a newer filter. Closing during an active join is disabled until failure/timeout or travel.
- Opening cancels placement/strokes and blocks match orders until the browser closes. The skirmish itself continues. This UI allocates no EditableImages.
- Studio keeps local play working and displays that cross-server matches are available in Roblox Player. It makes no lobby reads, writes or teleports in Studio.

## Integration and status policy

The server entry point enables the admission gate before publishing match remotes, starts the existing Saddle match, then supplies the directory service:

```lua
MatchService.enableLobby()
MatchService.start("Saddle")
MatchService.setLobby(LobbyServer.start(MatchService.lobbyState))
```

MatchService.lobbyState is a read-only description built by Shared.Lobby.MatchLobby. It returns map, human seat count, capacity=2, actual seated userIds, status, joinInProgress and public visibility. Bots and spectators do not consume directory match seats. Keep a custom state provider non-yielding and valid before admitting players: UpdateAsync retries read current local state inside their transform.

**APPROX port policy:** waiting means the opening deployment is unfinished; inProgress means deployment is done; a winner/draw closes the listing. Available sides remain joinable during play, preserving the existing replacement of an unclaimed side's bot. This labels existing behavior rather than tracing an original multiplayer lobby/start rule. It does not add a pre-match ready phase or change match clocks.

Join waits for the arrival check before assigning a side, rechecks sideOf after yielding, and never enrolls denied/disconnected players into snapshot membership. Admission that cannot complete times out with a reconnect message. Admitted full/finished arrivals spectate. Seating and departures request a fresh heartbeat.

Arrival claims are atomic too: an arriving player holds a seat until the client's match Join actually seats them. The state provider's userIds must identify players represented in its players count. PlayerAdded alone does not consume a hold. A heartbeat cannot erase an outstanding teleport hold simply because that player is loading.

## Files

| File | Role |
|---|---|
| src/shared/Lobby/LobbyDirectory.luau | Pure listing, visibility, reservation and arrival rules. |
| src/shared/Lobby/LobbyProtocol.luau | Separate lobby remote names and cooldowns. |
| src/shared/Lobby/MatchLobby.luau | Port status/seat policy, independent of Roblox services. |
| src/shared/Lobby/LobbyBrowserState.luau | Request lifecycle, filtering, join feedback and stale-reply cancellation. |
| src/server/Lobby/LobbyDirectoryService.luau | Publishing, browsing, atomic joins/arrivals and failure handling with injected dependencies. |
| src/server/Lobby/LobbyServer.luau | Real service/remotes adapter, PlayerAdded/Removing and close handling. |
| src/client/Lobby/LobbyClient.luau | Thin remote wrapper. |
| src/client/UI/LobbyBrowser.luau | Responsive match list and modal input flow; APPROX port UI. |

## Directory and routing

- LobbyDirectory_v1 is a MemoryStore sorted map keyed by server JobId. Heartbeats run every 15 seconds; records have a 60-second store TTL and are hidden/join-refused after 45 seconds without a heartbeat. Waiting listings expire after 30 minutes; listing lifetime is capped at four hours.
- Only owners delete their own listing. Browsers hide stale entries and leave physical removal to TTL, avoiding deletion of a live key that refreshed after a cached read. Normal shutdown removes its own key and broadcasts closure through MessagingService.
- Reads share a three-second server cache, including an in-flight-read guard. A refresh reads at most five pages of 200 entries. Native pagination passes {key, sortKey}, not a bare string. See [Roblox sorted-map cursors](https://create.roblox.com/docs/cloud-services/memory-stores/sorted-map).
- Per-player browse cooldown is two seconds. Cached responses are reused only for the same filter. Friend results cache for 120 seconds; transient API errors are not cached as negatives. The adapter uses [IsFriendsWithAsync](https://create.roblox.com/docs/reference/engine/classes/Player/IsFriendsWithAsync).
- Public listings are visible to everyone, friends listings to their host/friends, and private listings never appear. Only a configured host may change visibility. Current permission and stage are checked again on arrival; a prior hold cannot bypass a later privacy restriction. During a store outage, current local privacy still applies; public admission may fall back to match seat limits.
- Join re-reads the target and atomically holds a seat for 60 seconds. It permits one in-flight request per player. Routing data and access codes never enter publicView/client list responses.
- Public destinations use TeleportOptions.ServerInstanceId; reserved destinations use the recorded access code. Player-owned private servers are not listed. The backend retains rememberAccessCode for future reserved-server creation, but this browser does not provision servers.
- Teleport failures release holds and notify the client. Request ids in teleport options correlate failure events with the correct request; late failures cannot free a newer hold. Automatic native retry was removed to avoid mixing attempts. The client offers retry after failure.
- The service subscription, adapter event connections, remotes, browser polling and notice handlers have explicit teardown paths.

## Tests

```powershell
lune run tests/run_lobby
lune run tests/run
rojo build default.project.json -o build/RobloxianFront.rbxlx
```

The focused directory runner covers pure rules/service simulations. The full runner additionally includes lobby_match, lobby_browser and lobby_adapter: actual match Join extraction with fake admission/yielding, browser asynchronous state and actual UI callbacks, plus the real adapter against strict API-shaped stand-ins. Existing admin/rendering tests are preserved.

## Needs published-server testing

Use at least two live servers/accounts. Studio cannot establish teleport behavior; see [Roblox teleport testing](https://create.roblox.com/docs/projects/teleport).

1. Verify actual MemoryStore GetAsync/UpdateAsync/cancellation/RemoveAsync and {key, sortKey} GetRangeAsync cursors, including more than 200 records in a disposable test namespace.
2. Measure actual MemoryStore request/item quotas with concurrent browsers. Confirm shared caching, transient-outage recovery and no per-frame requests.
3. Join a listed public server and verify the exact JobId destination. Exercise a native-full/closed target and both immediate and TeleportInitFailed failures.
4. Race players on two source servers for one final destination seat; only one should hold it. Also race direct matchmaking arrivals against held seats.
5. Delay the destination client's match Join: its arrival hold must remain until seating or expiry. Loading spectators must not consume or free someone else's hold.
6. With a configured hosted lobby, verify real host friendship checks, public/friends/private changes, unauthorized host edits and privacy changes during travel. Ordinary public-server hostUserId=0 has no visibility owner.
7. In a disposable reserved-server integration, record the access code before routing, verify the reserved destination and ensure codes never reach clients. Unknown-code reserved and player-owned private servers stay unlisted.
8. Verify MessagingService closure broadcast and subscription cleanup. An unavailable broadcast must still fall back to TTL/staleness.
9. Check real server clock agreement and listing/reservation expiry. An old or expired lobby must not accept a new directory join.
10. Test graceful shutdown, dashboard shutdown/migration and abrupt termination. In-flight heartbeat writes must not resurrect a closed listing.
11. Verify opening-deployment/winner status, human versus spectator counts, bot takeover, duplicate Join and a player leaving during admission. Timed-out/refused checks must never acquire a side.
12. Exercise the actual Matches UI: filters, responsive layout, join feedback, full/gone/late failures, modal input, refresh/cancellation, cold startup and repeated Stop/Play. Record native memory/frame behavior. Stand-ins do not establish native visuals or performance.

## Remaining session work

Host/ready/start flow, creating new matches, selectable maps/armies, invitations and reserved-server provisioning remain separate work. At most 1000 listings are read per refresh and 100 are returned; larger deployments need a directory paging/regional policy. Match seats and Roblox platform server capacity are separate: a server may have no native player slots even when a match side is free, in which case teleport failure releases the hold.
