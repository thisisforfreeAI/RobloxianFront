# Water visuals: what was built and how to wire it in

Status: built and unit-tested, **not wired in yet** (on purpose: MapRenderer, TownRenderer,
RoadRenderer, FogOverlay, Sim and MatchService were being edited by another session). Nothing has been
committed. Not yet run in Studio.

## What it does

It ports the water part of WarFront's ground shader. The game draws its ground in one big fragment
shader. Each fine texel (3 a cell) carries a mask code (sand, near shallows, shallows, deep, river,
fleck, foam, far foam, crest head, crest tail), and a per-cell water map holds a river's direction and
speed and each cell's distance from the shore. On every frame, the shader draws:

| Effect | Game behaviour (traced) | Port |
| --- | --- | --- |
| Depth bands | Shallow tint near the shore fading to a deep tint over `far` cells, in flat steps dithered with a 4x4 Bayer matrix | Same formula, baked once per texel (it never moves) |
| Swell | Past the shelf, two octaves of value noise drift slowly; above one cut a texel lightens, below another it darkens | Same formula, repainted |
| Surf | The foam line and the far foam line, in stretches of `segment` cells, each lit for half its period on its own clock | Same |
| Crests | A crest slides one texel for half its period: its head sinks into the sea and the texel past its tail lights | Same |
| Tide | Sand one or two texels from the sea is wet for part of each stretch's cycle (dry, 1, 2, 2, 1, dry), with a faint foam edge as the water comes in; the second texel is ragged | Same |
| River flow | Swell and meandering streamlines carried downstream along the water map | Same, worked out at texel centres (APPROX: the game does it per screen pixel) |
| Glints | Each open-water texel rolls a die on its own clock; the few that come up take the sun's or moon's colour, stronger with the light's elevation | Same, with the sun colour, night and elevation from `DaylightController` |

All of the game's numbers (periods, tints, shares, noise scales, palette colours) come from
`tools/conversion/export_water.cjs`. It runs the game's own code from the local install and writes
them into the generated, git-ignored `src/client/DevAssets/Water_<map>.luau`. The committed code
holds formulas only.

### Approximations (marked in the code)
- **Hash values:** the game's GPU hashes in 32-bit floats and Luau in 64-bit. So which texels glint,
  and each foam stretch's phase, differ from the game texel for texel. The share, timing and look
  follow the game's rules.
- **Repaint cadence:** the CPU repaints the water a band of rows at a time, 3 ms a frame, chunks on
  screen only. Measured in Lune: about 1.9 million texels a second, so a chunk of open sea fully
  updates in about 6 frames. The animation therefore steps a little coarser than the game's
  every-frame draw. Zoomed out below 2 screen pixels a cell, the water is painted once and left still.
- **Chunk edges:** a tide texel at a chunk's edge does not see water in the neighbouring chunk.

### Not ported yet
- Night reflections of lights and the moon's path (they need the scene's light list and the screen
  position).
- Splash and blast ripples (they need a hook from the shell and blast effects).
- The weather's mud and storm sea.
- A burst dam's flood.
- Haze, the day/night tint and cloud shadows are global. They come from the shared daylight post
  effect, which also covers this layer, since it is a part in the 3D world.

## Files (all new)

- `tools/conversion/export_water.cjs`: the exporter (run below).
- `src/shared/Presentation/WaterShade.luau`: the shader's water functions, pure Luau, testable in Lune.
- `src/client/Rendering/WaterRenderer.luau`: chunk streaming and repaint. Each chunk gets a
  192 x 192 px "detail" image from the shared `ImageMemory` budget, and a reclaimer at priority 10 (the
  same as town detail) drops the farthest water chunks under pressure. The images sit on parts at
  `GROUND_Y + 0.03`: above the baked ground, under the towns (0.07) and roads (0.15). Land texels are
  clear, so the ground shows through.
- `tests/water.luau` (9 tests, plus 1 more when `Water_shoals.luau` has been generated) and
  `tests/run_water.luau` (runs only these).

## Generate the data (local only, never commit)

```
node tools/conversion/export_map.cjs <install>/dist/assets/genWorker-*.js shoals shoals.json
node tools/conversion/export_water.cjs <install>/dist/assets/main-*.js shoals.json src/client/DevAssets/Water_shoals.luau
```

Already generated in this folder: `Water_shoals.luau` (86 chunks, 142 KB), `Water_fjords.luau`
(66 chunks), and `Water_saddle.luau` (Saddle has no water: `water = false`, so nothing is drawn).
The game's designed maps with sea are atoll, canal, dam, fjords and shoals. None of them has a river,
so the river flow is unit-tested but not yet seen on real data.

## Wiring it in (for whoever owns the map code)

1. In `src/client/init.client.luau`, line 45 builds the map with `MapRenderer.build(map)`, which returns
   the map's Folder. Change it to:
   ```lua
   local WaterRenderer = require(script.Rendering.WaterRenderer) -- with the other requires
   local mapFolder = MapRenderer.build(map)
   WaterRenderer.build(map.data.id, mapFolder) -- false, and nothing drawn, without water data
   ```
   `map.data.id` is the id MapRenderer already gives TownRenderer for `City_<id>`. If the map is torn
   down or changed, call `WaterRenderer.destroy()` first.
2. If MapRenderer's ground parts are at a height other than `GROUND_Y + 0` to `0.02`, adjust
   `HEIGHT` in WaterRenderer so the water sits just above the ground and below towns and roads.
3. Add one line to `tests/run.luau` next to the other module tests:
   `require("./water")(test, eq)`.
4. To see it, the match has to run a map with water. Saddle has none, so this needs a water map
   converted into `src/shared/GameData/Maps` (convert_map.py) and started by MatchService. That is
   outside this change.

## Proposed Studio test (add to STUDIO_TESTS.md when wired in)

| Test | Steps | Expected |
| --- | --- | --- |
| Water | With `Water_<map>.luau` generated and a water map running, zoom in over the coast and the open sea, and watch for 20 s | Output prints "[WaterRenderer] <map>: n water chunks". The sea shows depth bands (lighter near the shore), slow drifting light and dark swell patches, foam lines along the beach blinking on and off in stretches, crests flicking, wet sand creeping up and back, and an occasional bright glint. No seams or gaps against the ground, and towns and roads draw over the water. Panning keeps it animated with no long freeze; zoomed far out it goes still. At night the glints dim to the moon's. |

## Tests actually run (Linux container, Lune 0.11.1)

- `lune run tests/run_water`: 10 passed with the generated shoals data present, 9 passed and 1 skipped
  without it.
- `lune run tests/run`, the full suite, on a copy of the folder's current working tree (including the
  other session's uncommitted changes): 177 passed, 0 failed. Water tests are not in it until step 3.
- All `.luau` files compile (syntax only). `rojo build` succeeds.
- Not run: Studio, type checking.
