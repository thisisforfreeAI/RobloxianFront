# Phase 1A Studio tests

Run these before any scope is added. Fill in the **Result** column with what actually happened
(paste Output lines). Results recorded here are kept apart from the checks already run outside Studio.

## Already passed outside Studio (run by Claude in a Linux container, not in Roblox)

| Check | Result |
|---|---|
| Lune unit tests (`lune run tests/run`) | 14 passed, 0 failed, including the 2 that read the GameData generated from your install |
| `rojo build` | builds the place file |
| Luau compile (syntax only, no type check) | 0 errors |
| Atlas validator, 960×240 and 992×248 layouts | all checks pass |

## Before you start

1. In the project folder: `rokit install` (or use the Rojo you already have; the Studio plugin should be 7.4.x).
2. Make sure `src\shared\GameData\` exists (RulesData, UnitCatalog, Locked, Maps\Saddle). If not:
   `python tools/conversion/generate_all.py "A:\SteamLibrary\steamapps\common\WarFront Demo"` (read-only on the game).
3. Studio: **File → New → Baseplate**. In Explorer delete `Workspace.Baseplate` and `Workspace.SpawnLocation`
   (the baseplate sits at the same height as the map and flickers through it). Save as a local test place.
4. **View → Output** open. Clear it before each test.

## Results

| # | Test | Steps | Pass when | Result |
|---|---|---|---|---|
| 1 | Rojo connection | `rojo serve` in the folder, then Studio **Plugins → Rojo → Connect** | Rojo says connected; Explorer shows `ReplicatedStorage.Shared` (with `GameData`, `Assets`), `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client` | **Pass** 2026-11-09. Needed plugin and server on the same version: Studio had plugin 7.7, fixed with `rojo plugin install` (7.4.4) |
| 2 | Ground | **Play** (F5) | Output: `[MapRenderer] EditableImage ground 384x240`; terrain colours fill the map; grey urban patches sit under the settlement discs and labels; roads line up with the terrain | **Pass after fix** 2026-11-09: re-test shows square cells. First run: `EditableImage ground 384x240` printed and the map showed, but the image was turned a quarter turn and stretched (cells about 2.6× wider than tall). Same cause as test 6; ground part now turned by `World.TOP_GUI_YAW` |
| 2a | EditableImage permission | Only if Output shows `[MapRenderer] EditableImage unavailable ... <error>` | Paste the error. Then publish the place privately (**File → Publish to Roblox**), enable **Game Settings → Security → Allow Mesh / Image APIs**, and retry. The game still runs on the Part fallback (`[MapRenderer] fallback ground: N parts`) | Not needed: EditableImage worked in an unpublished local place |
| 2b | Ground orientation | Set `FORCE_PART_GROUND = true` in `src/client/Dev/DevFlags.luau`, Play, compare with test 2, set it back | Both grounds look the same (the Part ground is placed in world coordinates, so it's the reference) | not run (do after the fix) |
| 3 | Camera | WASD / arrows pan, middle-drag pans, wheel zooms | Starts over your HQ with north up; stays inside the map; zoom stops at both limits | **Pass** 2026-11-09 (reported) |
| 4 | Selection and movement | Click a blue unit, shift-click, drag a box; right-click ground; select and press X; Esc | Selection ring shows only your side's units; units drive to the click and stop at water/impassable cells; X stops them; Esc clears | **Pass** 2026-11-09 (reported) |
| 5 | Server/client startup | Look at Output (Server and Client) right after Play | `[Match] side 1 unit ids: ...` and `side 2 ...` printed; no red errors; HUD shows your side | **Pass** 2026-11-09: `side 1 unit ids: 1,2,3,4,5`, `side 2 unit ids: 6,7,8,9,10`; no errors from project scripts (one error and two warnings came from a Studio plugin, Moon Animator, and an unrelated asset id 203785492) |
| 6 | Atlas test board | Same Play session; pan north of your start | Output: `[AtlasTestBoard] read-back identical to packed atlas: true; frame checks: PASS`. On screen: ring of 16 sprites, sprite *i* shows number *i*, every arrow points outward along its white line, 0 → right, 4 → down, 8 → left, 12 → up; magenta cross on the yellow dot; shadow see-through; no slivers from neighbouring frames; centre sprite turns smoothly on the yellow needle. Press R: centre sprite snaps in 16 steps. If every arrow is off by the same quarter turn, press G until right and note how many presses | **Pass after fix** 2026-11-09: re-test shows every arrow pointing outward, 0 right, 4 down, 8 left, 12 up, with the default compensation (G cycles away from it, as expected). First run: read-back identical: true; frame checks PASS (worst 1.47°, partial alpha true). Correct frame and number at every position, pivot and see-through shadow OK. Every arrow was a quarter turn anticlockwise (0 pointed up): on an unrotated part the Top-face GUI x runs along −Z. Fixed with `World.TOP_GUI_YAW = -pi/2` for sprites and ground |
| 7 | Two clients, ownership | **Test → Clients and Servers**, 2 players, **Start**. In Player1 (side 1) select your units and move them; in Player2 do the same. Then click into Player1's game view and press **K** (Studio-only probe that sends a move order for every enemy unit, like a cheating client would). The F9 console's command line runs on the server, so it can't be used for this | Side 2's units do not move; Player1's Output shows `[OwnershipProbe] ...`; the Server Output shows `[Match] refused order from Player1 (side 1) for units it does not own: 6,7,8,9,10`. Repeat with K in Player2 | **Pass** 2026-11-09: K from Player1 → server logged `refused order from Player1 (side 1) for units it does not own: 6,7,8,9,10`; K from Player2 → refused `1,2,3,4,5`. Ownership check only; TEMP-001 (all clients see all units) is unchanged |

## Known temporary limits (do not count as failures)

* **TEMP-001:** every client receives every unit's position. There is no fog of war yet, so these tests
  say nothing about hiding units from the other team.
* TEMP-002 straight-line movement, TEMP-003 placeholder unit shapes; the test tank and scout per side are test units.
* The atlas board uses synthetic arrows, not game art, and runs only in Studio (`DevFlags.ATLAS_TEST_BOARD`).


# Milestone 1B Studio tests

Outside Studio (Claude, Linux container): 24/24 Lune tests pass, including 9 for the 1B simulation
(production cost/time/queue, refused orders, 12 s rig capture, trucks delivering oil, 8-damage shots,
armour facing, truck ambush, HQ destruction ends the match, bot captures and trains). A 20-minute
bot-vs-bot run on Saddle completed with rigs captured, oil delivered and units killed, using 10 s of CPU.

| # | Test | Steps | Pass when | Result |
|---|---|---|---|---|
| B1 | Start | Play (F5) | Output: `[Match] side 1 unit ids: ...` and `side 2 is played by the bot`; HUD shows Oil 600 and the Train button; each HQ shows `HQ 3000/3000` | not run |
| B2 | Production | Press Q (or the button) twice | Oil drops 36 each time; queue shows 2/6 and a countdown; a new infantry appears next to the HQ every 7 s | not run |
| B3 | Capture | Send 2+ infantry onto the nearest rig (black disc) | A "capturing" bar fills in about 12 s; the rig gets a blue ring and shows `oil N`; Output `[Match] rigCaptured side 1`; 3 dark trucks leave your HQ | not run |
| B4 | Trucks | Watch a truck | It drives to the rig, waits, loads, drives back and your oil jumps when it unloads (HQ also adds 0.5 oil/s) | not run |
| B5 | Combat | Right-click an enemy (red) unit with units selected | Your units close in and fire; health bars appear and drop; dead units vanish | not run |
| B6 | Interception | Send units onto a red truck route | Red trucks get shot and disappear | not run |
| B7 | Bot | Wait 2–5 minutes | Red trains infantry, captures rigs, and later sends a group at your HQ | not run |
| B8 | Victory | Select all your infantry and right-click the red HQ (train ~15 first) | Red HQ bar drops; `HQ DESTROYED`; banner VICTORY for you (DEFEAT if yours falls) | not run |
| B9 | Two players | Clients and Servers, 2 players | Output `side 2 handed from the bot to a player`; each player has own oil and Train button; K probe still refused | not run |

Known limits (not failures): no fog (TEMP-001), straight-line movement and trucks drive off-road (TEMP-002),
placeholder shapes (TEMP-003), bot is a simple script, rigs can't be damaged yet, one unit type (infantry).
