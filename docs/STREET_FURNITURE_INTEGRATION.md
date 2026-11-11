# Street lamp posts: what was built and how to wire it in

Status: built and unit-tested, **not wired in yet**. That is on purpose: init.client.luau, Civilian*,
Sim.luau, MatchService.luau and the shared status docs were being edited by another session. Nothing
has been committed. Not yet run in Studio.

## What the game does, and what this adds

The trace is in `docs/private/STREET_FURNITURE_TRACE.md` (local only). In short: WarFront has no
separate street furniture layer. Its benches, parked cars, zebra crossings and median trees are
painted into the baked town art, which TownRenderer already draws. Each street lamp is a single
texel coloured like the road, so it cannot be seen by day. At night the game lights it and lays light
pools down the street, and NightLightRenderer already does that. The game has no traffic lights,
and it has nothing placed specially at intersections.

**This is a port addition.** It stands a lamp post at each of the game's own lamp spots (only
there), so the street lamps can be seen by day. The spots are the game's. The post's shape, colours,
height, arm and shadow are this port's, drawn in code with no image asset.

| Part | Source |
| --- | --- |
| Where each post stands | The game's lamp texels in the baked towns (generated, git-ignored) |
| Which way the arm points | Port: worked out from the street's asphalt round each lamp (APPROX) |
| The post art, its colours, height and shadow length | Port |
| When posts appear (zoom) | Port: they fade in between 7 and 12 screen px a cell |
| Night | The lamp head sits under the lamp texel that NightLightRenderer lights, so the game's own light (with its share and flicker) falls on it. The shadow fades at night with `DaylightController`'s shadow alpha |
| Day/night colour grade | The shared daylight post effect, as for every part in the world |

### Approximations and limits
- The arm's direction is a guess from the colours round the lamp: toward the texels of the lamp's
  own asphalt colour. Checked by eye on all 36 Saddle lamps against the town art: the foot lands on
  or just past the kerb and the head over the road. A few lamps on bends or at corners may point a
  little off.
- The shadow is the post's raised parts shifted along the sun, plus a thin bar for the pole. Its
  length is capped like the car shadows.
- Posts stay up when their town is ruined or shelled, and when a town loses power (the game has no
  posts to knock down, and the port has no power grid yet).
- Nothing is placed at intersections, because the game places nothing there.

## Files (all new)

- `tools/asset_pipeline/pack_street_furniture.py`: finds the lamp spots in a `.city` file.
- `tools/asset_pipeline/test_pack_street_furniture.py`: 8 synthetic tests (no original data).
- `src/shared/Presentation/StreetFurniture.luau`: the post art (16 facings, two rows: the whole post
  and its raised parts for the shadow), zoom share, shadow and a bucket grid for camera queries. It is
  pure Luau.
- `src/client/Rendering/StreetFurnitureRenderer.luau`:
  - It uses one 512 x 64 "detail" image from the shared `ImageMemory` budget. It registers a
    reclaimer at priority 10 (the same as town detail) and releases the image after 3 s with no posts
    on screen.
  - It draws only posts in view, at most 300 at a time, and skips fogged cells (`FogOverlay.hidden`).
  - Posts sit at `GROUND_Y + 0.2`: above the town art (0.08) and roads (0.15), and below the night
    lights (0.24), cars (0.29) and units.
- `tests/street_furniture.luau` has 8 tests, plus 1 more when `StreetFurniture_saddle.luau` has been
  generated. `tests/run_street_furniture.luau` runs only these.

## Generate the data (local only, never commit)

```
python tools/asset_pipeline/pack_street_furniture.py <install>/dist/cities/saddle.city
```

This writes `src/client/DevAssets/StreetFurniture_saddle.luau`, which git ignores. It has already
been generated in this folder for all nine designed maps (atoll, canal, dam, fen, fjords, line,
saddle, shoals, strait).

## Wiring it in (for whoever owns init.client.luau)

1. In `src/client/init.client.luau`, next to `NightLightRenderer.start(map,mapFolder)`, add:
   ```lua
   local StreetFurnitureRenderer = require(script.Rendering.StreetFurnitureRenderer) -- with the other requires
   StreetFurnitureRenderer.start(map, mapFolder) -- false, and nothing drawn, without lamp data
   ```
   If the map is torn down or changed, call `StreetFurnitureRenderer.destroy()` first. It needs no
   server data. It reads the time of day from `DaylightController`, which init already updates.
2. Add one line to `tests/run.luau` next to the other module tests:
   `require("./street_furniture")(test, eq)`.
3. Optional: add the Studio test below to STUDIO_TESTS.md.

## Proposed Studio test

| Test | Steps | Expected |
| --- | --- | --- |
| Lamp posts | With `StreetFurniture_saddle.luau` generated, start Saddle at Noon and zoom in on a town street. Then use the admin panel to set Evening and then Midnight | Output prints "[StreetFurniture] saddle: 36 lamp posts". Small dark posts stand along the street edges, alternating sides, each with a pale head over the road and its foot on the kerb. Posts fade in as you zoom in and are gone when zoomed out. Their shadows fall the same way as the car shadows and swing with the time of day. At night the game's lamp lights sit on the post heads and the shadows fade. No posts show in fog. |

## Tests actually run (Linux container, Lune 0.11.1; Python on the device)

- `lune run tests/run_street_furniture`: 9 passed with the generated Saddle data.
- `python -m unittest test_pack_street_furniture test_pack_night_lights` in tools/asset_pipeline: 16
  passed. 8 of those are the new packer tests.
- `lune run tests/run`, the full suite, on a copy of the folder's current working tree: 242 passed,
  0 failed. The copy includes the other session's uncommitted changes. The street furniture tests are
  not in it until step 2.
- Every `.luau` file compiles (syntax only). The first check caught an ambiguous-call syntax error in
  the renderer, which is fixed. `rojo build` succeeds.
- The packer was run on all nine designed maps. Its Saddle arm directions were checked by eye against
  the town art.
- Not run: Studio, type checking.
