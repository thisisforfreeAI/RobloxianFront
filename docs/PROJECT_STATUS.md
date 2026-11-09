# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-09

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public; first commit 4142c4e pushed 2026-11-09)

## Phase
Phase 1. Milestone 1A done (Studio tests 1–7 pass). Pilot sprite REQ-0001 approved. Milestone 1B (gameplay loop) rewritten for WarFront parity and tested outside Studio; Studio tests B1–B9 pending.

## Verified outside Studio (actually run, Linux container)
- Lune 0.11.1 `tests/run`: 14 passed, 0 failed (including the 2 that read the GameData generated from your install).
- Rojo 7.4.4 `rojo build` succeeds. All .luau files compile (syntax only).
- Synthetic atlas: 16 × 120 px frames pack to 960×240 (8×2, no padding); validator passes on dimensions,
  rectangles, direction order, pixel identity, pivot, partial alpha, edge bleed, arrow orientation, manifest.
  A deliberately swapped frame is caught.

## Studio results (2026-11-09, see docs/STUDIO_TESTS.md)
- Pass: Rojo connect (after matching plugin 7.4.4), camera, selection/movement, server/client startup.
- Atlas board: pixels, frame rectangles, direction order, pivot, transparency pass in Roblox.
- Found and fixed: Top-face SurfaceGui drawings were a quarter turn anticlockwise (sprites) and the ground
  was turned and stretched. Fix: `World.TOP_GUI_YAW`; re-test passed.
- Two clients: the server refuses orders for the other side's units (test 7). No fog of war yet (TEMP-001).

## Not verified
- Test 2b (optional). Type checking. Performance at 100/250/500 units (renderer benchmark).

## Public repo boundary
Git-ignored and generated locally: `src/shared/GameData/` (RulesMatch, RulesData, UnitCatalog, Locked, Maps).
Git-ignored local docs: `docs/private/` (audit reports with excerpts from the game).
Only synthetic or approved new art is tracked under `assets/sprites/`.

## Temporary items
- TEMP-001 all units replicated to all clients. No fog of war; no protection against seeing enemy units is claimed.
- TEMP-002 straight-line unit movement, no pathfinding (trucks already route on roads)
- TEMP-003 placeholder unit shapes and colours
- Atlas test board runs in Studio while `DevFlags.ATLAS_TEST_BOARD` is true

## Milestone 1B (2026-11-09), parity pass
WarFront's modding guide table is not what a match runs with. The game builds its config from runtime
defaults (63 values differ from the guide, e.g. rigs pump 2.4/s into 440, trucks carry 160) and then
rescales distances and speeds by a match cell scale of 3 before building the world (maps are not
upscaled). `tools/conversion/export_rules.cjs` exports exactly those values to `GameData/RulesMatch`,
and the simulation now uses them.

Traced from the game's code and rebuilt: rig capture (weight, minPace, contest freeze, decay, HQ guard,
direct takeover of enemy rigs), 6 s takeover before pumping, rich rigs, HQ oil trickle, the nation's idle
truck pool (3 at start), automatic first truck per capture, buying trucks (40 oil, 4 per rig), loading
queue and leave rules, road raster and road networks, rig connection, truck routing on roads
(`Shared.Simulation.Roads`, the game's A*), combat targeting order, shot timer with jitter, bullet
flight, damage with cover, flanking and armour facing, truck damage, HQ loss elimination and the
annihilation verdict. Every remaining simplification is labelled APPROX or UNCONFIRMED at the top of
`Sim.luau` (unit pathfinding, truck curve-following and column spacing, spawn spots, RNG sequence).
The bot is still PROVISIONAL (the game's bot personas are next).

## Next
1. You run Studio tests B1–B9.
2. Then: the game's bot (balanced / turtle / warlord), unit pathfinding, fog of war (server-filtered), more units.

## Open questions
1. Rights scope: original art, audio, voice; public redistribution of extracted data.
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.
