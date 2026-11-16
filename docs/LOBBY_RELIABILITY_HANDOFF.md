# Cross-server lobby reliability handoff

Prepared 2026-11-15 on branch `lobby-reliability`. The user subsequently authorized committing and pushing only the ten files below to main; see Git history for the integration commit.

## Source and scope

Inspected the actual cloud checkout at `/workspace/RobloxianFront`, based on commit `e3c328517acb5d19c80c2c1e0eb16a25cb4a955b`. The initial working tree was clean and no applicable AGENTS.md files were found. Read README.md, LOBBY_DIRECTORY.md and the dated entries at the end of PROJECT_STATUS.md. The last available status entries describe November 13 projectile work, not the other agent's later 1,616-test checkout. This task does not have access to that agent's uncommitted Windows files.

`/workspace/WarFront-Reference` is available at `af7838646f86f5484b50df96c62e5fa4d5973142`. It contains shipped code reference material, not a runnable game or an original installation. No original source excerpts, assets or generated GameData were copied into the public project. Lobby reliability fixes use the existing port's policies; no original multiplayer policy or parity is inferred.

The directory was already integrated. This work retains ongoing-skirmish discovery, match status/seating policy, explicit user teleport retry, modal input blocking and existing UI row reuse. No EditableImages or new native UI objects were added. Host creation, ready/start flow, maps and reserved-server provisioning remain separate work.

## Bugs reproduced and fixes

### Outstanding browse calls multiplied after filters or close/reopen

Start a browse and delay its response. Repeatedly change the filter or close/reopen the browser after cooldown. The old code invalidated its reply token and immediately allowed another transport: the regression creates 51 outstanding requests after 50 cycles.

LobbyBrowserState now keeps the transport token until that request completes, separately incrementing a revision to invalidate obsolete replies. Only the latest desired filter is issued afterward, respecting cooldown. Closing still stops polling and destruction ignores callbacks. A transport that never returns remains one outstanding request; this change does not claim to cancel Roblox RemoteFunction transport or server work. Reopening does not bypass that bound.

### Delayed responses offered expired matches

A range read or friendship lookup can yield past a listing's expiry. Browsing previously evaluated records using the time from before the request. It now samples time after those calls. Repeated same-filter requests inside cooldown also re-evaluate cached listings as time advances, without another store read or extending the cooldown. A closure message invalidates the same player's cached response too, so it cannot re-offer the just-closed lobby within that second.

### Old cleanup erased newer reservations

A teleport failure removed `pending[player]`, then yielded on its cleanup write. A new explicit attempt could reserve the same destination before the old cleanup transform ran. Cleanup identified only userId and erased the new hold. A late source failure could similarly erase a hold already claimed by the destination. The old notice was also sent after yielding cleanup, potentially disturbing the next UI attempt.

Reservations retain numeric expiries and gain optional server-only `reservationIds` ownership metadata. Each source attempt receives a unique service request id before reservation. Cleanup compares ownership inside the atomic transform. Arrival rotates ownership to the destination's request id; heartbeats preserve only metadata belonging to retained holds and remove metadata when holds expire or become seated. Destination departures release only their captured arrival ownership. Public views omit the metadata. Failure notices are sent before cleanup yields. No automatic teleport retry was introduced.

Legacy numeric holds remain readable and can be adopted by a new attempt/arrival. Conditional cleanup does not remove a hold with missing or mismatched ownership; it can then expire normally. Older live server code can still perform unconditional cleanup or strip metadata: deploy compatible shared/service/adapter modules together and restart old test servers before claiming ownership protection across a rollout.

### Shutdown and duplicate arrival races

A join paused on a store read could resume after close and reserve/teleport anyway. Join now checks lifecycle/presence before work, inside reservation transforms and after the write. The existing per-player single-flight gate remains. A player disconnecting before reservation cannot start travel.

A close during initial publication could still register a heartbeat loop afterward. Startup now rechecks closure after publication and replaces an existing timer rather than retaining another. Heartbeats run one at a time and restore their gate after exceptions. This does not queue writes; a later heartbeat reads current state.

PlayerAdded and the startup player snapshot can overlap for the same player while arrival is yielding. The adapter now admits/checks that player once. After close, an outstanding arrival cannot invoke admission/refusal callbacks or kick a player through destroyed lobby infrastructure. Service close clears per-player caches; delayed browse/friendship work cannot recreate departed-player response entries. Repeated close remains safe.

Source PlayerRemoving after successful travel is intentionally not treated as a failed teleport: freeing that destination hold then could steal the loading player's seat. Destination arrival owns/relinquishes its own hold; abandoned source holds retain the existing bounded expiry.

### Directory failure recovery

A thrown range dependency left the shared read guard set indefinitely. The guarded range call now releases it and returns unavailable/cached results. Failed slow reads set the three-second backoff from completion, not their old start time. The server still permits one range read at a time, at most five pages of 200 items per refresh, with per-player browse/join gates.

Cached outage responses now explain that they show the last available matches and suggest refresh. Cached records still pass current staleness/expiry checks. The client displays this message. Full, gone, expired, closed, unavailable and failed-travel messages now identify refresh or explicit Join retry as appropriate. Existing privacy checks still apply; outage arrival fallback re-reads current local state after a failed/yielding store write and reuses resolved, non-yielding permission information. A host changed during lookup fails closed when its friendship was not resolved.

## Exact files changed

| File | Change |
| --- | --- |
| `src/shared/Lobby/LobbyDirectory.luau` | Optional reservation ownership, conditional release, ownership pruning/arrival transfer, recovery text. |
| `src/server/Lobby/LobbyDirectoryService.luau` | Lifecycle checks, owned cleanup, arrival fallback, bounded heartbeat/read work, fresh browse/cache evaluation, outage feedback. |
| `src/server/Lobby/LobbyServer.luau` | Duplicate arrival guard and post-close callback suppression. |
| `src/shared/Lobby/LobbyBrowserState.luau` | Separate browse revision and transport lifetime; display degraded-directory messages. |
| `tests/lobby_directory.luau` | Legacy hold adoption, metadata privacy/pruning and ownership protection. |
| `tests/lobby_service.luau` | Delayed cleanup, arrival transfer, disconnect/close, expiry, privacy, throttle/backoff/cache and heartbeat regressions. |
| `tests/lobby_browser.luau` | Updated stale-response scheduling assertion and repeated filter/close coalescing regression. |
| `tests/lobby_adapter.luau` | Duplicate yielding arrivals, single admission callback and shutdown callback suppression. |
| `tests/run_lobby_reliability.luau` | Focused runner including directory, service, match, browser and adapter suites. |
| `docs/LOBBY_RELIABILITY_HANDOFF.md` | This handoff. |

No combat/rendering, Sim.luau, entry points, MatchService.luau, tests/run.luau, PROJECT_STATUS.md or STUDIO_TESTS.md edits. No place publication or asset uploads. Commit and push of only these ten files were subsequently authorized by the user.

## Tests actually completed

Run from `/workspace/RobloxianFront` with `/workspace/.cloud-tools/bin` on PATH (Lune 0.11.1, Rojo 7.4.4):

| Command | Result |
| --- | --- |
| `lune run tests/run_lobby_reliability` | **81 passed, 0 failed**, all five lobby suites. |
| `lune run tests/run_lobby` | **58 passed, 0 failed**; this runner includes only directory and service suites. |
| `lune run tests/run` | **705 passed, 0 failed**; includes all lobby suites. |
| `rojo build default.project.json -o build/RobloxianFront.rbxlx` | Successful place build. |
| `git diff --check` | Passed. |

These runners overlap; do not add their test counts together. A tracked-source baseline copy at the original commit, supplied only the updated lobby tests/runner, completed with **64 passed, 17 failed**, exit 1. The patched runner completed with 81 passed. One existing browser test intentionally changed its scheduling expectation: obsolete replies remain ignored while old transport must finish. The new disconnect regression also confirms existing correct behavior.

The full suite explicitly skipped absent RulesData, Saddle, RulesMatch, DeathFx, MenFx, local missile-rack art, daylight settings/reference vectors, street-furniture Saddle data and Water_shoals sections. These are unrun checks, not passes. Private generation was not fabricated. The other agent's 1,616-test result does not describe this checkout.

All service, friendship, teleport, match-handshake and UI tests here use pure rules or API-shaped/headless stand-ins. They validate our code's local decisions and interleavings, not Roblox service behavior, native visuals, quotas, timing or performance.

## Primary-agent integration

No integration edits outside lobby ownership are necessary in the inspected checkout. Its main runner already imports these five test modules. Run `lune run tests/run_lobby_reliability` for the standalone coverage; no change to tests/run.luau is needed.

Apply the files above to the newer primary checkout only after inspecting its lobby changes; this branch starts from the older public commit. Keep the primary agent's rendering work and later unrelated changes. Restart Play/rejoin after syncing the shared, client and server lobby modules together. Do not infer a published deployment from the successful local build.

## Remaining published two-server checks

1. With at least two source servers/accounts and a destination with one human match seat remaining, race joins and direct arrivals. Confirm one hold wins, duplicate arrivals admit once, and a loading client's hold survives until seating/expiry.
2. Exercise actual immediate TeleportAsync errors and TeleportInitFailed, including late older callbacks, failure cleanup delayed across explicit retry, and a late source failure after destination arrival. Verify request ownership, correct public JobId/reserved routing, and no automatic retry.
3. Disconnect during reads, reservation writes, travel initiation and delayed destination Join. Check that no disconnected user acquires a side and that legitimate successful travel keeps its destination hold. Source disconnect cannot always be distinguished from completed travel; abandoned holds may remain until expiry.
4. Induce MemoryStore throttling/unavailability and slow reads in a disposable namespace. Verify shared bounded reads, native cancellation behavior, completion-based backoff, current expiry/staleness filtering, correct cached-result feedback and recovery. Check real quota/item-size costs of optional ownership metadata and native pagination beyond 200 listings.
5. Use hosted friends/private listings to test real IsFriendsWithAsync, transient failures and privacy changes while admission is yielding. Public-outage admission still relies on the existing authoritative match seat rules; offline tests cannot prove native admission races.
6. Check MessagingService close delivery/subscription teardown, same-player cached closure, shutdown during publication/join/arrival, failed RemoveAsync, and abrupt termination followed by store TTL expiry. Broadcast/cleanup failures can delay removal until staleness/TTL.
7. Repeatedly change filters, refresh, close/reopen, destroy/restart the real browser and delay remote responses. Verify modal input blocking, no background polling while closed, one outstanding browse per browser lifetime, explicit join recovery and no stale repaint. Native UI/frame/memory behavior remains unmeasured.
8. Repeat reserved-server/unknown-code/player-owned-private-server cases, listing lifetime/clock agreement and actual native server-full errors from LOBBY_DIRECTORY.md. Reserved provisioning and host/ready/map policy remain out of scope.
