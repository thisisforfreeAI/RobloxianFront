# Pre-match keyboard and gamepad navigation handoff

Prepared 2026-11-16. Branch: `prematch-navigation`. Base: `1ed46a43402cf135b652278b90bd45aae9ce330e` from `prematch-lobby`. The user authorized committing/pushing only this helper, its tests/runner and this handoff to the new branch; no merge to main.

Read PREMATCH_LOBBY_HANDOFF.md before implementing. No applicable AGENTS.md was present. The primary agent owns networking, server startup, chosen seats and client screen flow; none of that work is implemented or modified here. This older cloud checkout's test counts do not describe the primary agent's newer local checkout.

## Exact changed files (all new)

| File | Purpose |
| --- | --- |
| `src/client/UI/PrematchNavigation.luau` | Isolated selection, input-navigation and scroll helper. |
| `tests/prematch_navigation.luau` | Actual helper driven by event-based API-shaped stand-ins. |
| `tests/run_prematch_navigation.luau` | Separate focused runner; existing runners unchanged. |
| `docs/PREMATCH_NAVIGATION_HANDOFF.md` | This integration contract and remaining native checks. |

No existing lobby/UI/gameplay/renderer/entry-point/shared-runner files were changed. No networking, images, artwork changes, polling, deferred work, animation or render/heartbeat loop was added.

## Behavior and ownership

- Caller supplies ordered `{key, button, enabled?}` records, bounded to 64 controls. Recommended order: current map choices, current seats, Ready, Start, Retry, Leave. Use `map:<mapId>` and `seat:<seatId>` rather than row indexes, labels or display text. Four action keys are `ready`, `start`, `retry`, `leave`. Roster labels are not controls.
- A record is eligible only when not explicitly disabled, its GuiButton is Active, attached inside the supplied panel, and visible through all GuiObject ancestors and the root ScreenGui.Enabled state. The helper owns Selectable and the four NextSelection properties while a button is registered; it derives Selectable from eligibility rather than treating its own writes as input. Do not have a second navigation helper concurrently own the same buttons/properties.
- Tab/Shift+Tab wrap through the eligible sequence. Arrow keys and gamepad D-pad move one step per press, clamp at endpoints, and are sunk by a uniquely named ContextActionService action at High+1 priority. No touch action button is created. Input End/Change does not repeat movement; no custom hold-repeat loop is installed. Left/up mean previous; right/down mean next in the same linear order.
- The native NextSelectionUp/Left and Down/Right links follow the same eligible order, with self-links at the endpoints. Native stick-driven selection changes update the remembered key and reveal the selected control. There is no custom analog-stick polling.
- **Activation stays native:** Enter/Space (where native GUI navigation supports it), gamepad A, mouse and touch continue through the EXISTING GuiButton.Activated handlers. The helper does not bind activation keys, call presenter commands, synthesize clicks or connect another Activated callback. Tests prove no activation is synthesized, not that Roblox dispatches native keyboard/gamepad activation correctly; that remains a Player check.
- Mouse/touch/mouse-wheel input removes the helper's selection highlight, remembers its semantic key, and stops scroll correction so pointer scrolling remains free. Switching to gamepad restores that key if eligible, otherwise the first eligible control. Keyboard focus starts on the first Tab/arrow navigation press, rather than eagerly selecting a button during mouse/touch mount. With initial controls supplied and gamepad already active, mount selects the first eligible control. It does not activate it.
- A state/layout refresh preserves the selected key and, when the same instance remains selected, does not clear/rewrite GuiService.SelectedObject. If that key moves to a replacement button, selection follows the key. If a pooled button changes semantic id, selection does not accidentally follow the recycled row to a different target.
- When selection becomes hidden, disabled, detached or unregistered, prefer its surviving eligible successor in the previous order, then predecessor, then first eligible control. If none remain, clear owned selection; re-enable can restore a valid control. An unrelated external modal's selection is not stolen by a state/layout refresh or teardown.
- Reveal is vertical and minimal: compare button and panel absolute geometry, allow a six-pixel margin (configurable), preserve CanvasPosition.X, clamp CanvasPosition.Y to the native canvas/window bounds, and avoid repeated writes when already visible. Oversized controls align toward their top; a zero-size viewport waits for geometry events. Position/size/window/canvas signals handle settled layout changes; no per-frame scroll task exists. This is for the current single scrolling panel, not arbitrary nested scroll containers or rotated panels.
- Properties, ancestor visibility, ancestry, root Enabled, selection and geometry are observed with explicit connections. `setControls` replaces watches rather than accumulating them; invalid registries fail before installing initial bindings. `destroy()` unbinds only its unique action, disconnects its watchers/listeners, restores registered button Selectable/NextSelection properties and is idempotent. Unregistering a button restores its properties and drops its watches.
- The previous selection is captured at mount. On close, it is restored only if the helper still owns selection (including its own pointer-cleared nil), and that previous object is attached, selectable, active where applicable, visible through ancestors and outside the closing root. An invalid previous target clears selection. A newer external selection is left alone.

## Helper API

```lua
local navigation = PrematchNavigation.mount({
    root = gui,               -- the lobby ScreenGui
    panel = panel,            -- its ScrollingFrame
    controls = orderedRecords,
    scrollMargin = 6,         -- optional
})
navigation.setControls(orderedRecords) -- same keys across renders; enabled flags may change
navigation.refresh()                  -- layout/state changed; does not activate anything
navigation.focus("ready")             -- optional explicit selection; no command/activation
navigation.step(1)                    -- optional discrete next, clamped; step(-1, true) wraps
navigation.setActive(false)           -- before another modal takes input/selection
navigation.setActive(true)            -- resume; request focus explicitly if appropriate
navigation.destroy()                 -- BEFORE destroying the screen
```

Production resolves GuiService, UserInputService and ContextActionService inside mount. `guiService`, `inputService`, `actionService`, `enums`, `vector2` can be injected for tests; production does not need to supply them. `focus`/`step` return booleans and refuse to interfere with a focused TextBox. Navigation input passes through while inactive, hidden, typing, while GuiService.MenuIsOpen, or without eligible controls. Focus/step refuse to select behind an open core menu, and teardown does not restore a previous selection behind it.

The primary screen controller must still gate gameplay input and deactivate this helper before presenting a higher-priority modal. This helper cannot identify every app modal automatically. It deliberately does not change global GUI navigation settings, core menu/chat behavior or bind Back/B to Leave. Showing/hiding the lobby and leaving the room remain the primary agent's screen-flow responsibilities.

## Exact hooks proposed for the existing UI

These are instructions for the primary agent's newer `src/client/UI/PrematchLobby.luau`; **they are not applied on this branch**. Adapt insertion points if its integrated UI has moved. No server/startup/network/chosen-seat changes are needed for this helper.

### 1. Require the helper

Alongside the module's current top-level declarations:

```lua
local PrematchNavigation = require(script.Parent.PrematchNavigation)
```

### 2. Add navigation state and semantic registry after constructing the action buttons

In `UI.mount`, immediately after the existing `local leave=button(...)` declaration, before `enabled` and `render`, add:

```lua
local navigation:any = nil
local function syncNavigation()
    local ordered = {}
    for _, row in maps do
        if row.id then
            table.insert(ordered, {key = "map:" .. row.id, button = row.button})
        end
    end
    for _, row in seats do
        if row.id then
            table.insert(ordered, {key = "seat:" .. row.id, button = row.button})
        end
    end
    table.insert(ordered, {key = "ready", button = ready})
    table.insert(ordered, {key = "start", button = start})
    table.insert(ordered, {key = "retry", button = retry})
    table.insert(ordered, {key = "leave", button = leave})
    if navigation then
        navigation.setControls(ordered)
    else
        navigation = PrematchNavigation.mount({
            root = gui,
            panel = panel,
            controls = ordered,
        })
    end
end
```

Use catalog id order, matching existing map/seat arrays. Do not sort by GuiObject.LayoutOrder globally (subgroups have independent layouts), Text or absolute position. Do not register roster TextLabels, feedback labels or the background. Retired pooled rows must have id=nil and/or be hidden as the existing render already does. Unregister only controls that really leave this screen's navigation; a visible active button deliberately omitted from the registry is outside the helper's contract. A permanently noninteractive control can stay registered with `enabled=false`.

Lazy mount is intentional: the first render has created the actual map/seat buttons, set their enabled states and attached the ScreenGui. It also ensures initial gamepad selection sees the final eligible list.

### 3. Sync once at the end of each render

After the existing enabled calls for Ready, Start, Retry and Leave, and after all map/seat ids, visibility and Active values have been updated, add:

```lua
syncNavigation()
```

Do not call it while assembling a partial roster. Do not add new Activated handlers: keep the existing map, seat, Ready, Start, Retry and Leave callbacks intact. The helper's ordering and highlight never authorize an action; server permission checks remain authoritative.

### 4. Notify at the end of responsive resize

After changing art/panel sizes/positions in `resize`, add:

```lua
if navigation then navigation.refresh() end
```

Settled native absolute geometry and AbsoluteCanvasSize property events subsequently run reveal again if needed. No task.wait, RenderStepped or polling callback is required. This preserves the same selected id across desktop/portrait switches and roster-induced movement instead of choosing a new first button.

### 5. Destroy before the ScreenGui

In the existing idempotent handle.destroy path, after marking it dead and before `gui:Destroy()`:

```lua
if navigation then
    navigation.destroy()
    navigation = nil
end
```

Keep the UI's existing presenter unbind/event disconnections and screen controller's presenter.destroy calls. The helper also listens to root.Destroying as an external-destruction fallback; calling both paths is safe. Each registration's original navigation properties are restored. Do not clear GuiService.SelectedObject unconditionally afterward, because that would erase a restored or newer modal selection.

### 6. Suspend for other modals

Where the primary screen controller presents another modal over the pre-match screen, call navigation.setActive(false) BEFORE the other modal selects its own control. Resume with setActive(true) when it closes. If last input is gamepad or the user explicitly requests keyboard navigation, call navigation.focus() after resume. Do not automatically force keyboard highlight on every mouse/touch click. If the controller owns this transition outside UI.mount, expose a narrow handle method for suspension in the UI integration; do not install global singleton state in the helper.

## Validation

All commands ran from `/workspace/RobloxianFront` with Lune 0.11.1 / Rojo 7.4.4 on PATH:

| Command | Result |
| --- | --- |
| `lune run tests/run_prematch_navigation` | **29 passed, 0 failed**. |
| `lune run tests/run_prematch_lobby` | **35 passed, 0 failed**. |
| `lune run tests/run_lobby_reliability` | **81 passed, 0 failed**. |
| `lune run tests/run` | **705 passed, 0 failed**, older cloud suite. |
| `rojo build default.project.json -o build/RobloxianFront.rbxlx` | Successful build. |

The new tests execute the actual helper source with synchronous property signals, ContextActionService-shaped registration, native-shaped selection objects and scrolling geometry. They cover forward/back/wrapped order, hidden/disabled ancestors, stable ids, replaced instances, removed controls, pooled ids, empty/zero-size cases, gamepad mode, native-shaped stick selection changes, pointer/wheel coexistence, TextBox input, modal suspension/external ownership, prior-selection validation, property restoration, external screen destruction, invalid registration, connection bounds, and minimal/idempotent/clamped scrolling.

Stand-ins do **not** establish real Roblox event order, automatic stick movement, native activation, core input priority, visuals, safe areas or performance. No native Studio/Player session or published game was run. No screenshots or artwork were changed. The older main runner does not include these new navigation tests, so run the dedicated command. Existing pre-match/lobby suites overlap the main runner; do not add counts together. Private generated-data sections remain skipped in the old full suite, not passed.

## Required native checks after the primary agent adds the hooks

1. In Studio/Player, Tab/Shift+Tab, every arrow, D-pad and analog stick through the actual current map/seat/action controls. Confirm endpoints, native selection indication, gamepad initial focus and no double movement from native routing plus the ContextAction binding.
2. Verify Enter/Space where supported and gamepad A invoke each existing Activated exactly once; mouse/touch still invoke once. The helper never synthesizes activation, so native activation support must be checked with the experience's actual GUI navigation settings before claiming keyboard/gamepad completion. Preserve core menus/chat and typing; do not add a second presenter-command path as a workaround.
3. Change map availability, occupied seats, roster, host role, Ready state and pending/error/start phases while selected. Check safe successor selection and no accidental action when a pooled row changes target. Test every control disabled and re-enable without activating it.
4. Resize desktop/portrait and shorten the scrolling viewport, including safe areas, scrollbar width and high UI scale. Confirm selection remains visible after settled layout, does not jitter at edges and does not fight manual wheel/touch scrolling. Oversized controls can only be partially visible; their top is preferred.
5. Open/close a different modal and core menu, disconnect/reconnect a gamepad, alternate pointer and pad, close/destroy/reopen the screen repeatedly. Verify correct suspension, selection restoration, no stale bindings/listeners and no selection restored into a destroyed/hidden lobby.
6. Profile native allocations/connection counts while roster updates and layouts settle. No loops are introduced, but stand-ins are not native cost evidence. Run the primary checkout's newer full suite and this new isolated runner after hooking up the UI. Keep the primary agent's startup, networking, selected-side and rendering work intact.

## Integration from Git

Fetch `prematch-navigation` and review/cherry-pick its single commit into the primary agent's integration branch after preserving its local work. The commit adds only the four files above; it does not include changes to PrematchLobby.luau. Then apply the six UI hooks above in the primary checkout, test its newer UI/transport together, run the isolated runner and the newer full suite, and perform native checks. Do not merge this older branch into main as a shortcut for resolving unrelated local rendering changes.
