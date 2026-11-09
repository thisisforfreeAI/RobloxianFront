# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-09

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public; first commit 4142c4e pushed 2026-11-09)

## Phase
Phase 1, milestone 1A done: Studio tests 1–7 pass (2b, Part-ground comparison, optional). Pilot sprite request REQ-0001 open.

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
Git-ignored and generated locally: `src/shared/GameData/` (RulesData, UnitCatalog, Locked, Maps).
Git-ignored local docs: `docs/private/` (audit reports with excerpts from the game).
Only synthetic or approved new art is tracked under `assets/sprites/`.

## Temporary items
- TEMP-001 all units replicated to all clients. No fog of war; no protection against seeing enemy units is claimed.
- TEMP-002 straight-line movement, no pathfinding
- TEMP-003 placeholder unit shapes and colours
- Test units: one tank + one scout per side beside the start infantry
- Atlas test board runs in Studio while `DevFlags.ATLAS_TEST_BOARD` is true

## Next
1. REQ-0001: you give the prompt to ChatGPT and drop the PNG in assets/sprites/incoming/REQ-0001/.
2. Claude validates, rotates, packs and shows it on the test board.
3. Milestone 1B (HQ, oil, combat) per `docs/private/FIRST_SLICE.md`.

## Open questions
1. Rights scope: original art, audio, voice; public redistribution of extracted data.
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.
