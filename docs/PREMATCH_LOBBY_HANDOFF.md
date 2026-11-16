# Pre-match lobby handoff

Prepared 2026-11-16 on branch `prematch-lobby`, based on `3d776096901209d476e7b4170b1ca5d09822bfb2`. The user authorized committing and pushing this deliverable to `prematch-lobby` only. No merge into main, gameplay changes, place publication, or Roblox asset upload is included. See branch history for the delivery commit.

## Scope and checkout evidence

Read README.md, LOBBY_DIRECTORY.md and the latest available dated PROJECT_STATUS.md entries (November 13 ballistic/tracer work). No applicable AGENTS.md was present. The cloud checkout is older than the primary agent's local game. Its 705-test result is not the latest reported 1,702-test local result; the newer primary checkout must rerun its own suite during integration. The pre-match modules and runner are new and independent: neither the existing Matches browser nor ongoing-skirmish behavior was changed.

This is a tested UI/state prototype and integration contract, not an installed networked pre-match game flow. No host provisioning, invitations, reserved-server creation, map generation, match startup, native seating or screen-flow policy has been silently installed.

## Changed files (all new)

| File | Purpose |
| --- | --- |
| `src/shared/Lobby/PrematchLobbyState.luau` | Server-owned non-yielding model; injected catalogs/policies, membership, map/seat/Ready commands, host departure, start transaction. |
| `src/shared/Lobby/PrematchLobbyClientState.luau` | Injected asynchronous transport presenter; loading/recovery, request bound, session/revision protection and explicit teardown. |
| `src/client/UI/PrematchLobby.luau` | Responsive static-image UI factory; map/seat controls, roster/roles/readiness, start feedback, retry/leave, pooled controls and event cleanup. |
| `tests/prematch_state.luau` | Authoritative state/policy/permissions/concurrency regressions. |
| `tests/prematch_client.luau` | Delayed/stale/error transport and lifecycle regressions. |
| `tests/prematch_ui.luau` | Actual UI module driven with native-shaped stand-ins, real model and presenter. |
| `tests/run_prematch_lobby.luau` | Separate focused runner; main runner intentionally unchanged. |
| `docs/PREMATCH_LOBBY_HANDOFF.md` | This integration guide and limitations. |
| `assets/prematch/liberty-block-monument.png` | Finished generated transparent blocky military Liberty monument. |
| `assets/prematch/preview-desktop.png` | Desktop composite layout study using the generated artwork. |
| `assets/prematch/preview-portrait.png` | Portrait composite layout study using the generated artwork. |

No existing tracked files were edited. In particular: no combat/rendering, Sim.luau, MatchService.luau, entry points, HUD, main runner, PROJECT_STATUS.md or STUDIO_TESTS.md changes.

## Artwork: finished transparent export, not uploaded to Roblox

The user supplied the Liberty reference directly in chat on November 16. It has been visually inspected: a low-angle monochrome military Liberty statue with a raised ornate torch at viewer-left, seven-spike crown, face covering, tactical carrier/pouches/radio, slung rifle and a tablet at viewer-right. The earlier missing-reference blocker is resolved. The original image is NOT included in this repository or branch.

`assets/prematch/liberty-block-monument.png` is the finished image-tool-generated adaptation. It replaces human anatomy with a blocky avatar face, rectangular arms/hands, broad torso and squared lower body, while retaining the reference's silhouette, pose, crown/torch/tablet, military theme, grayscale weathered monument material and low-angle lighting. A second image-tool pass corrected the top framing so the entire sculpted torch flame remains visible. No original art file, archive, GameData or source excerpt was added. The final generated file was copied without pixel edits from the image tool output.

Export: **941 × 1671, 8-bit RGBA PNG**. SHA-256: `b3440a339339d3f54261d100cd2707b0aba3afac1f44c66a9b0d85071aa1a25a`. PNG decoding and alpha inspection passed: alpha range 0..255, all four corners fully transparent, 722,456 fully transparent pixels, antialiased alpha along the subject, and visible subject pixels at high opacity. The black background shown by some viewers is their transparency display, not an opaque black background embedded in the asset. The bottom is intentionally thigh-cropped like the reference; torch and crown are inside the image boundary. Native import filtering still needs review.

Two committed previews show the generated artwork beside the lobby: `assets/prematch/preview-desktop.png` (1440×1000) and `assets/prematch/preview-portrait.png` (390×844). These are HTML layout studies using a snapshot emitted by the actual Luau model, not Roblox screenshots or a pixel-perfect native UI claim. They use a neutral dark surrounding field, with the image fitted into a left region on desktop or top region on portrait, outside the opaque scrolling text panel. They were visually inspected. The reproducible local HTML and snapshot remain outside the checkout in `/workspace/exports/prematch-lobby/`.

**No Roblox asset id exists yet.** A Git push does not import a PNG into Roblox. After separate authorization, the primary agent can import this PNG under the appropriate experience/creator permissions, preserve its alpha, and provide the assigned static image id to `backgroundImage`. The same export can serve as `backgroundImagePortrait`; a separate portrait crop is not required to preserve the whole figure. `ImageLabel.ScaleType.Fit` prevents stretching/cropping; it may letterbox. The UI now labels a missing id as “STATIC BACKGROUND NOT CONFIGURED” rather than implying reference artwork is still missing. A portrait-only configured image also hides that label after responsive layout switches.

## Proposed, configurable policies — unconfirmed original design

These are port proposals, not traced WarFront multiplayer rules:

- Inject `maps = {{id, name, seatIds?}, ...}` and `seats = {{id, label, team}, ...}`. Map ids are opaque allowlisted identifiers; the adapter maps them to installed map modules. Optional map `seatIds` restrict usable seats. Catalogs are fixed per session: recreate the session with a NEW session id if they must change. Limits: 32 maps, 16 seats/players; no spectators or auto-seating in this prototype.
- Only the host chooses the map or requests Start. Every member chooses an unoccupied seat. A seat encodes its team; this prototype does not offer arbitrary freeform teams. Guests cannot choose for another player.
- Defaults: `minPlayers=2`, `requireAllReady=true` (including host), `requireDistinctTeams=true`. All members must have a compatible seat even if all-Ready is disabled. Empty map catalogs remain unavailable. Configure a one-player experiment explicitly with minimum 1 and distinct teams disabled.
- `resetReadyOnMapChange`, `resetReadyOnSeatChange`, `resetReadyOnRosterChange` default true. A player changing seats always becomes Not Ready, even if resetting everyone else is disabled. An incompatible seat is removed on map change and its owner always loses Ready. Selecting the same map/seat or duplicate member join is idempotent.
- `hostDeparture="close"` by default; optional `"transfer"` chooses the earliest remaining join, with deterministic join order. Transfer resets readiness. An empty session closes. Host departure during startup cancels it before closing/transferring. Started sessions must be handed off to gameplay and the pre-match controller retired; this module does not manage post-start host migration.
- Start eligibility feedback distinguishes map, unseated players, minimum count, readiness, teams and non-waiting phases. No automatic start/retry. Start enters `starting` and increments `launchId`; only matching `finishStart(launchId, ok, message?)` can finish it. Failure returns to waiting with feedback and reset readiness. Departures during startup cancel it; a late completion cannot revive the old transaction.
- Internal authority `setAvailability("loading"|"unavailable"|"error"|"waiting", message?)` provides recovery states and resets readiness. Client refresh only fetches state; it cannot clear a server error. Server code must restore waiting when its prerequisite is actually usable.

## APIs and wire contract

`PrematchLobbyState.new({sessionId, hostUserId, hostName?, maps, seats, policy?})` adds the host unseated. Use a fresh unpredictable session id for each session. Only trusted server code calls:

- `join(userId, name)`, `leave(userId)`, `snapshot()`.
- `dispatch(authenticatedUserId, {kind, revision, mapId?|seatId?|ready?})`: kinds `map`, `seat`, `ready`, `start`. Returns `{ok, message?, snapshot}`. Rejected stale revisions include current state; do not automatically replay the old intention. Join returns `{ok, snapshot? ,message?}`. A duplicate join does not alter the member.
- `setAvailability(...)`, `finishStart(...)`: internal lifecycle APIs, never client command kinds.

Snapshots are detached copies with `sessionId`, monotonically increasing `revision`, `phase`, `hostUserId`, catalogs, policy, `mapId?`, `players`, `launchId`, `message`, `canStart`, `startFeedback`. `players` uses STRING UserId keys, e.g. `snapshot.players[tostring(player.UserId)]`; records carry numeric `userId`, display name, `seatId?`, `ready`, join `order`. Do not depend on sparse numeric dictionary serialization. The snapshot includes room members only and no directory routing/access-code data.

`PrematchLobbyClientState.new({sessionId, userId, fetch, send, subscribe?})` returns `view`, `refresh()`, `command(kind,value?)`, `receive(snapshot)`, `onChanged(fn)->unsubscribe`, `destroy()`. `fetch(done)` and `send(command,done)` must callback with the response table. `subscribe(receive)` returns an unsubscribe function. Start with `refresh()` after mounting. Map/seat/ready values are passed as the second command argument. The presenter ignores another session and non-increasing revisions, suppresses duplicate completions, permits one request at a time and ignores responses after destruction. Snapshot tables passed into it must not be mutated afterward.

No polling or timers are installed. A transport that never calls back remains one pending request; Leave remains usable. The eventual adapter must provide bounded completion/error handling without spawning unlimited uncancellable InvokeServer tasks. This prototype does not prove native network timeouts or cancel server work.

`PrematchLobby.mount({parent=PlayerGui, presenter, backgroundImage?, backgroundImagePortrait?, onLeave?})` returns `handle.destroy()`. It owns only its ScreenGui, native event connections and presenter render subscription. It does NOT destroy the presenter or send Leave automatically. On leaving the screen, destroy both handle and presenter, and explicitly disconnect the room through the authority. Mount only once per active screen and retire it before gameplay. External ScreenGui destruction releases UI listeners too.

## Precise integration steps for the primary agent

The following changes are PROPOSED integration work. They are not applied to the protected files and must be adapted to the newer local checkout.

### 1. Add a separate server room adapter

Create a server module, e.g. `src/server/Lobby/PrematchLobbyServer.luau`, with separately named remotes such as `WarFrontPrematch/{Fetch,Command,Changed}`. Do not reuse or change `WarFrontLobby` remotes or `LobbyDirectory_v1` records. The adapter must:

1. Select the host/session and obtain catalogs from authoritative installed map metadata and explicit seat-to-side configuration. Do not accept arbitrary module names, host ids, catalog contents or actors from clients. Validate map modules/dependencies before offering them; private generated data is still required for actual matches.
2. Construct the model, call join for authenticated participants, and connect PlayerRemoving to leave. `Fetch` must verify current session membership. `Command` must use the actual RemoteFunction Player.UserId, membership/session binding, a per-player cooldown and single in-flight gate, then call the NON-YIELDING dispatch. Unknown/unjoined users must not read room rosters.
3. Broadcast snapshots only to members after successful mutations, joins, departures, availability/start changes. Bound requests independently of UI disabled controls. `snapshot()` is copied, so callers cannot mutate the model. Rate-limit fetches too; the presenter is a UX bound, not an authorization boundary.
4. On the transition to starting only, capture session id, launch id, selected installed map and seat mapping, then request primary-owned match preparation once. Check the session/launch is still current before side effects and after every yield. On cancellation, cancel/dispose prepared resources; `finishStart(false)` is not a rollback of an already-started simulation. On failure, finish the same current launch with an actionable error; on success, finish only after gameplay is actually ready and preserve the selected seating for its handshake.
5. Teardown remote callbacks, events, room/session references and transport operations when a room closes or hands over. Session identity must change on recreation to reject old events. Server provisioning/matchmaker/host-selection policies remain a product decision, not code inferred here.

### 2. Preserve existing server startup, then opt in explicitly

Current `src/server/init.server.luau` calls `MatchService.enableLobby()`, `MatchService.start("Saddle")`, then `MatchService.setLobby(LobbyServer.start(MatchService.lobbyState))`. Leave this existing skirmish path unchanged by default. A new, explicit pre-match mode/route can construct the new adapter instead and defer match startup to a successfully validated Start transaction. Do not mount the pre-match UI over an already-started Saddle simulation and call that a real pre-match flow.

The existing directory's "waiting" describes unfinished deployment. Do not reinterpret it as Ready/Start or advertise pre-match rooms as ongoing skirmishes. After a new room actually starts, attach the existing directory service using the existing match state provider and normal admission checks. Until then, discovery/creation of new pre-match rooms needs its own explicit routing policy; it is not provided by this assignment.

### 3. Integrate chosen seats with authoritative gameplay

Current `MatchService.assignSide` calls `MatchLobby.side(sideOf, player, arrival, sim.winner~=nil)`, which chooses the first free side, not a preselected seat. Do not claim pre-match seat selection controls gameplay until this integration is implemented.

Proposed exact insertion point: after `waitArrival` and the post-yield presence/admission recheck in assignSide, resolve an optional primary-owned `prematchSideByUserId[player.UserId]` mapping captured from the accepted start transaction. Existing `sideOf[player]` always wins for duplicate handshakes. Only a member with an authorized arrival and a valid unoccupied side from that mapping may acquire that chosen side. Never let the mapping bypass a denied arrival, finished match or disconnect; never silently fall back to a different side when a chosen side is occupied. Preserve `MatchLobby.side` unchanged for ordinary skirmishes without such a mapping. Update authoritative membership/bots/heartbeat through the existing path after seating. The primary agent owns this protected-file integration and its newer tests.

This game's current capacity is two sides. Inject only supported seats/teams and map them explicitly to sides 1/2 in production; the model's generic 16-seat bound is not a claim that the simulation supports 16 players or arbitrary teams.

### 4. Install a separate client screen controller

The current `src/client/init.client.luau` waits for match remotes and calls `join:InvokeServer()` before constructing the renderer/HUD. For opt-in pre-match sessions, insert a screen controller BEFORE that wait/join block. It creates the presenter with current room/session identity and bounded transport adapters, mounts the UI into LocalPlayer.PlayerGui, subscribes before fetching, and calls presenter.refresh(). An illustrative mounting snippet:

```lua
local Presenter = require(Shared.Lobby.PrematchLobbyClientState)
local Screen = require(script.UI.PrematchLobby)
local presenter = Presenter.new({
    sessionId = authenticatedRoomId,
    userId = Players.LocalPlayer.UserId,
    fetch = fetchWithCompletion,
    send = sendWithCompletion,
    subscribe = subscribeToRoomSnapshots,
})
local handle = Screen.mount({
    parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
    presenter = presenter,
    backgroundImage = approvedWideImageId, -- omit until an authorized upload exists; do not invent an asset id
    backgroundImagePortrait = approvedPortraitImageId,
    onLeave = leaveAuthenticatedRoomAndCloseScreen,
})
presenter.refresh()
-- At screen retirement: handle.destroy(); presenter.destroy()
```

The names in the snippet are adapter dependencies, not existing project functions. Start the ordinary match Join/render setup only after the server confirms the CURRENT session's accepted launch has started. Error/closed/leave must not fall through into a match automatically. Keep combat/camera/controller work absent while the pre-match screen is active; an Active Frame alone is not an adequate input gate for global gameplay listeners. On accidental overlap, extend the existing send/controller input guards with an explicit pre-match-open predicate owned by that screen controller. Do not modify the main HUD merely to display this screen. The existing Matches UI and its ongoing-game Join path remain unchanged.

## Validation actually run

From `/workspace/RobloxianFront`, with `/workspace/.cloud-tools/bin` on PATH:

- `lune run tests/run_prematch_lobby`: 35 passed, zero failed. Includes policy/permissions, competing and stale seat commands, minimum/Ready/team eligibility, map incompatibility, host close/transfer, start cancellation/failure, sparse UserIds, snapshot isolation, presenter ordering/errors/teardown, actual native-shaped UI callbacks/guest controls/reuse/portrait resize/destruction, and portrait-only static-image configuration.
- `lune run tests/run_lobby_reliability`: 81 passed, zero failed; existing ongoing browser unaffected.
- `lune run tests/run`: 705 passed, zero failed. Does NOT include the new pre-match suites; run both commands. It still skips absent private RulesData, Saddle, RulesMatch, DeathFx, MenFx, missile-rack art, daylight vectors, street-furniture Saddle data and Water_shoals sections. These are unrun, not passing.
- `rojo build default.project.json -o build/RobloxianFront.rbxlx`: successful place build.
- Chromium/Playwright HTML preview capture at 1440×1000 and 390×844: succeeded; desktop/portrait images visually inspected. This verifies only the layout study, not native UI.

No generated data was fabricated. State/UI stand-ins do not establish real transport, friendship, MemoryStore, teleport, Roblox font/layout/touch, native memory or game startup behavior. No native Studio/Player session was run.

## Remaining native/integration checks

- Test the new authenticated/rate-limited adapter with two clients, stale commands, last-seat competition, delayed/reordered messages, disconnects, repeated join/leave, host close/transfer, startup cancellation, duplicate Start and late load completion. Confirm no unauthorized reads or actions.
- Verify map ids resolve only installed map modules and selected seats map to actual sides without admission bypass. Confirm start is once-only and clocks/gameplay do not run in pre-match; preserve ordinary deployment labels and skirmish joins.
- Test native wide/portrait/small-screen UI, safe areas, scrolling to every control, long names/map labels, keyboard/touch/gamepad access, disabled buttons, readability, scene composition and repeated mount/destroy. The prototype uses Activated and normal scrolling; explicit controller focus navigation is not implemented yet.
- Review the finished generated Liberty PNG and composite previews, obtain separate asset-upload authorization, then test the actual imported alpha/edges and wide/portrait Fit imagery in Roblox. No Roblox image id is assigned by this branch.
- Profile native allocations/frame time and image residency; no EditableImages, heartbeat listeners, polling, render loops or animations are introduced here, but native cost is not proven by stand-ins.
- Run the primary checkout's newer full suite and the new runner after integration. Add integration coverage for the actual room adapter, map startup and native seating; none is claimed by these independent modules.
