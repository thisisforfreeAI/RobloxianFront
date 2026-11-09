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
| 1 | Rojo connection | `rojo serve` in the folder, then Studio **Plugins → Rojo → Connect** | Rojo says connected; Explorer shows `ReplicatedStorage.Shared` (with `GameData`, `Assets`), `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client` | not run |
| 2 | Ground | **Play** (F5) | Output: `[MapRenderer] EditableImage ground 384x240`; terrain colours fill the map; grey urban patches sit under the settlement discs and labels; roads line up with the terrain | not run |
| 2a | EditableImage permission | Only if Output shows `[MapRenderer] EditableImage unavailable ... <error>` | Paste the error. Then publish the place privately (**File → Publish to Roblox**), enable **Game Settings → Security → Allow Mesh / Image APIs**, and retry. The game still runs on the Part fallback (`[MapRenderer] fallback ground: N parts`) | not run |
| 2b | Ground orientation | Set `FORCE_PART_GROUND = true` in `src/client/Dev/DevFlags.luau`, Play, compare with test 2, set it back | Both grounds look the same (the Part ground is placed in world coordinates, so it's the reference) | not run |
| 3 | Camera | WASD / arrows pan, middle-drag pans, wheel zooms | Starts over your HQ with north up; stays inside the map; zoom stops at both limits | not run |
| 4 | Selection and movement | Click a blue unit, shift-click, drag a box; right-click ground; select and press X; Esc | Selection ring shows only your side's units; units drive to the click and stop at water/impassable cells; X stops them; Esc clears | not run |
| 5 | Server/client startup | Look at Output (Server and Client) right after Play | `[Match] side 1 unit ids: ...` and `side 2 ...` printed; no red errors; HUD shows your side | not run |
| 6 | Atlas test board | Same Play session; pan north of your start | Output: `[AtlasTestBoard] read-back identical to packed atlas: true; frame checks: PASS`. On screen: ring of 16 sprites, sprite *i* shows number *i*, every arrow points outward along its white line, 0 → right, 4 → down, 8 → left, 12 → up; magenta cross on the yellow dot; shadow see-through; no slivers from neighbouring frames; centre sprite turns smoothly on the yellow needle. Press R: centre sprite snaps in 16 steps. If every arrow is off by the same quarter turn, press G until right and note how many presses | not run |
| 7 | Two clients, ownership | **Test → Clients and Servers**, 2 players, **Start**. In Player1 (side 1) select your units and move them; in Player2 do the same. Then in Player1's window, command bar: `game.ReplicatedStorage.WarFrontNet.Intent:FireServer({kind="move", unitIds={6,7,8,9,10}, x=10, y=10})` (use the side 2 ids from test 5) | Side 2's units do not move; the Server Output shows `[Match] refused order from Player1 (side 1) for units it does not own: 6,7,8,9,10`. Repeat from Player2 with side 1's ids | not run |

## Known temporary limits (do not count as failures)

* **TEMP-001:** every client receives every unit's position. There is no fog of war yet, so these tests
  say nothing about hiding units from the other team.
* TEMP-002 straight-line movement, TEMP-003 placeholder unit shapes; the test tank and scout per side are test units.
* The atlas board uses synthetic arrows, not game art, and runs only in Studio (`DevFlags.ATLAS_TEST_BOARD`).
