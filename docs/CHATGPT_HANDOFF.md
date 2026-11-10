# Handoff: RobloxianFront (WarFront ported to Roblox)

This file is for another assistant picking the project up with no access to the earlier chats. Read it
first, then `docs/PROJECT_STATUS.md` (a running log by feature) and `docs/STUDIO_TESTS.md` (the manual
test list).

## 1. Goal and rights

- The goal is to port WarFront (a top-down RTS) to Roblox, and the owner wants it **exactly like the
  game**. Gameplay numbers, behaviour and drawing are traced from the game's own JavaScript bundle. If you
  can't confirm something there, mark it `APPROX` or `UNCONFIRMED` in a code comment and in
  PROJECT_STATUS. Don't invent values.
- The owner says the creator gave permission for the port and for using the game's original art.
- **The GitHub repo is public** (`thisisforfreeAI/RobloxianFront`). Original game material is never
  committed: no art, no audio, no extracted tables, no quotes from the game's code. Original art may be
  *used locally*, but it stays git-ignored. Tools load the game's code or art from the local install at
  run time, so nothing from the game gets copied into committed files.
- Git-ignored, local only: `src/shared/GameData/`, `docs/private/`, `assets/original/`,
  `assets/sprites/source/*`, `assets/sprites/runtime/*`, `assets/sprites/incoming/*`,
  `src/client/DevAssets/*` (except the synthetic `Syn*` modules).
- Owner's standing rules:
  - Never modify or delete the original game install.
  - Never delete the project folder.
  - The owner runs git themself. Don't reset, clean or force-push.
  - Don't remove `.git/index.lock` while a git process might be running.
  - Don't overwrite files you haven't looked at.
  - Never claim a test ran when it didn't.
- Report format after each batch: a short summary, then the commands for the owner to run:
  ```
  git add -A src tests docs tools
  git commit -m "..."
  ```

## 2. Locations and toolchain

- Project folder: `C:\Users\thato\OneDrive\Desktop\RobloxianFront` (Windows).
- Game install (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`. The extracted app
  (asar) holds the bundle, `dist/assets/main-*.js`. It is one long minified file, so search it with a
  short Python script (find the text, print a slice around it); line-based grep is too slow on it.
- Original art sheets, extracted locally: `assets/original/warfront-demo-assets-*/dist/tiles/`
  - `units-top.png`: 120 px frames, 16 facings per row.
  - `men-top.png`: 48 px frames.
  - Plus the city and ground sources.
- Toolchain: `rokit install` installs Rojo 7.4.4 and Lune 0.11.1.
  - Build: `rojo build default.project.json -o build/RobloxianFront.rbxlx`, or `rojo serve` with the
    Studio plugin (plugin version must match, 7.4.4).
  - Tests: `lune run tests/run`. Last run: **151 passed, 0 failed**.
  - Performance check: `lune run tools/perf.luau 250`.
- Game data: `python tools/conversion/generate_all.py "<install>"` writes `src/shared/GameData/`
  (rules, unit catalog, constants, maps).
- `tools/conversion/`: extractors.
  - `extract_asar.py`, `export_rules.cjs`, `export_map.cjs`, `export_trees.cjs`.
  - `export_ground.cjs` runs the game's own ground code in Node and writes the baked ground.
- `tools/asset_pipeline/`: art packing.
  - `cut_units.py` cuts unit rows from units-top.png, driven by a local spec
    (`docs/private/cut_spec.json`).
  - `cut_men.py` cuts soldier poses from men-top.png (`docs/private/men_spec.json`).
  - `pack_original.py <spec.json>` packs strips into DevAssets Luau modules (RLE + base64 pixels).
    It also derives rims, half rims and shades. Its specs are `docs/private/sprite_spec*.json`.
  - `pack_city.py` packs towns and trees. `pack_ground.py` packs the ground.

## 3. Architecture

- **Server** (`src/server`): `Match/MatchService.luau` runs the authoritative loop (20 Hz) and the bots.
  It builds per-player snapshots filtered by fog (`Shared.Simulation.Fog`).
  - Unit row: `{id, kind, side, x, y, heading, hp, maxHp, status, rank, cargo, flags, aimX, aimY,
    sinceShot, turret, stage}`.
  - When a unit isn't firing, aimX/aimY carry an engineer's job position.
  - Vehicle deaths go out as `deaths`: `{id, kind, x, y, hull, turret}`.
- **Simulation** (`src/shared/Simulation/Sim.luau`, about 9k lines): all gameplay, ported from the
  bundle. Pathing is in `Pathing.luau`. **Pitfall:** the Sim constructor is at Luau's 200-local limit,
  so put new helpers on `self.X` tables (see `self.Turret`), not new locals.
- **Protocol / Net**: `src/shared/Protocol`, `src/server/Networking/Net.luau`. Snapshots go out 10/s.
  The client interpolates.
- **Client** (`src/client`): `init.client.luau` starts FogOverlay, then UnitRenderer, then MapRenderer,
  then CameraController.
  - `Rendering/UnitRenderer.luau`: unit quads (SurfaceGui on flat Parts).
    - Draw order: shadow, rim, body, paint (tinted with the side colour), turret, soot.
    - Also: halo, deploy stages, wrecks (including the turret toss), engineer workers, crews bailing out.
  - `Rendering/SpriteBank.luau`: loads the DevAssets modules into EditableImages.
    - Calls: `look(kind)`, `wreck(kind)`, `state(kind, n)`, `soot(kind)`, `figure(name)`.
    - **Pitfall:** EditableImage has a per-device memory budget. Only infantry and men are preloaded.
      Vehicle looks load when a unit of that kind first appears. Keep it that way.
  - `Rendering/SquadMen.luau`: places and poses infantry men one by one.
  - `Rendering/TownRenderer.luau`: draws an overview, then streams town chunks near the camera.
  - `Rendering/MapRenderer.luau`: draws the baked ground.
  - `Rendering/FogOverlay.luau` (`hidden(x, y)`).
- Conventions:
  - Facing: 16 frames. Column 0 is east, going clockwise. `Facing.index`/`residual` choose the frame,
    and the leftover angle turns the quad.
  - Top-face GUIs need `World.TOP_GUI_YAW`.
  - The game's hash `kc` is in `Shared/Utilities/Hash.luau`.
  - Unit rows in the sheet: row is colour, +1 is paint, +2 is shape. Turret rows are +3 to +5.
  - Don't change `DevFlags.ATLAS_TEST_BOARD`.

## 4. Workflow

1. Trace the feature in the bundle and note its constants (the game's tables `Ai`, `za`, `fa`, `Kv`).
2. Port it. Name the source in comments ("the game's work()"), in your own words.
3. Run `lune run tests/run` and `rojo build`. Add a test in `tests/run.luau` for sim logic.
4. Add a Studio test row (B-number) to `docs/STUDIO_TESTS.md` and a section to `PROJECT_STATUS.md`.
5. If the feature needs new art, add entries to the local spec files and run the cut and pack tools.
   The new modules land in `src/client/DevAssets` (git-ignored).
6. The owner runs the Studio tests and commits. Studio tests B78–B90 haven't been run yet.

## 5. Done (summary; details in PROJECT_STATUS)

- Gameplay: the full match loop and the game's rules, including:
  - fog, pathing, convoys, rigs, engineers (repair, sabotage), trenches;
  - artillery, mortars, rockets, airfield drops and paratroopers;
  - veterancy, IFV transport, the HQ truck, minefields, bots.
- Visuals with the original art:
  - unit sprites for tank, truck, scout, artillery, infantry, IFV, rocket, engineer, demo, HQ truck;
  - soldiers one by one, turrets that track targets, rims, shadows and halo;
  - deploy looks;
  - wrecks with turret toss, soot on damaged vehicles, engineer workers and crews bailing out;
  - the game's baked ground, towns and trees.

## 6. Remaining, in priority order

1. **Owner's Studio pass on B78–B90.** Fix whatever they report first. Errors usually show in Output
   with a script and line number.
2. **Death looks other than toss.** The game picks blast, cook, brew or quiet by weights per class
   (`DEATH_WEIGHTS` in UnitRenderer). Fire, smoke and debris are still missing: trace the bundle's
   `Kv.variants` and its drawing.
3. **Men's shadows and rims.** Squads have no rim or shadow yet. Derive them from the men shape rows
   the same way `pack_original.py` does for units.
4. **Rocket launcher "empty" rack** look after firing.
5. **Day/night.** The sun is fixed at noon (`SUN` in UnitRenderer, the town bake). The game turns the
   sun through the day and dims at night.
6. **Water looks** (Saddle has no water, so test on another map).
7. Remaining land units and buildings the port still skips (see PROJECT_STATUS, "Next").
8. Audio is not started; the rights for it are still an open question.

## 7. Known pitfalls

- An earlier crash came from a field name clash: `v.status` is the TextLabel and `v.statusCode` is the
  number. Watch for clashes like this.
- Luau "Out of local registers" in Sim: move code onto `self.X` tables.
- EditableImage budget errors ("Failed to create empty EditableImage"): load less up front.
- The ground looked blue-black in forests because the extractor skipped top-level fill statements in
  the game code. `export_ground.cjs` keeps them now.
- `cc`-style compile checks are syntax only. Type errors show up only in Studio's Script Analysis.
