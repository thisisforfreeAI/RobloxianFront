# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-09

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public, empty as of 2026-11-09)

## Phase
Phase 1, milestone 1A (Rojo foundation, interactive renderer, synthetic sprite pipeline). Written and checked
outside Studio. **Waiting on the Studio tests in `docs/STUDIO_TESTS.md` before any new scope.**

## Verified outside Studio (actually run, Linux container)
- Lune 0.11.1 `tests/run`: 14 passed, 0 failed (including the 2 that read the GameData generated from your install).
- Rojo 7.4.4 `rojo build` succeeds. All .luau files compile (syntax only).
- Synthetic atlas: 16 × 120 px frames pack to 960×240 (8×2, no padding); validator passes on dimensions,
  rectangles, direction order, pixel identity, pivot, partial alpha, edge bleed, arrow orientation, manifest.
  A deliberately swapped frame is caught.

## Studio results
None yet. See `docs/STUDIO_TESTS.md`.

## Not verified
- Anything in Roblox Studio. Type checking (no luau-analyze/selene here).
- SurfaceGui Top-face orientation for the ground and sprites (tests 2b and 6).
- `ImageRectOffset` on an EditableImage-backed ImageLabel (test 6).

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
1. You run the Studio tests and paste the results.
2. If the atlas board passes: one pilot sprite request for an asset that needs new artwork.
3. Milestone 1B (HQ, oil, combat) per `docs/private/FIRST_SLICE.md`.

## Open questions
1. Rights scope: original art, audio, voice; public redistribution of extracted data.
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.
