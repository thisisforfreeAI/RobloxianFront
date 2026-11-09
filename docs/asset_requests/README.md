# Asset requests and manifest

Roles: **ChatGPT** draws the artwork from a request. **Deterministic tools** (`tools/asset_pipeline/`)
package it. **Claude** validates and integrates it. The developer carries files between the two chats.

Nothing is requested yet. The first (pilot) request goes out only after the Studio atlas test board passes
(docs/STUDIO_TESTS.md, test 6), and only for an asset that really needs new artwork.

## Folders

| Folder | Holds | Git |
|---|---|---|
| `assets/sprites/incoming/` | Deliveries exactly as received from ChatGPT | ignored until approved |
| `assets/sprites/source/<origin>/<assetId>/r<rev>/` | Source frames, one PNG per direction/frame, plus `source.json`. Never edited by tools | synthetic and approved new art only |
| `assets/sprites/runtime/<assetId>/r<rev>/p<padding>/` | Generated atlas pages + `atlas.json` (frame rectangles) | synthetic and approved new art only |
| `src/shared/Assets/Atlases/<Name>.luau` | Generated metadata the game reads | yes |
| `assets/original/`, `extracted/` | Anything taken from the WarFront install | **never** |

Earlier revisions stay in their `r<rev>` folders; an approved revision is never overwritten.

## Status flow

requested → in production → delivered → validated → approved → integrated (or rejected / superseded).
`validated` means the offline validator passed; `approved` needs the developer's yes after the Studio check.

## Request file: `docs/asset_requests/REQ-nnnn.md`

Copy `TEMPLATE.md`. Unknown values are written as `null`, not guessed.

## Manifest: `assets/manifests/assets.json`

Schema: `assets/manifests/assets.schema.json` (version 2). Every key is required; unknown values are `null`.

| Key | Meaning |
|---|---|
| `assetId` | Stable snake_case id, never reused (e.g. `unit_tank_coalition`) |
| `requestId` | `REQ-nnnn`, or null for synthetic assets |
| `revision` | Integer, bumped on every delivered change |
| `kind`, `status` | Asset family; position in the status flow |
| `source` | `type` (synthetic / chatgpt / original-game / other), `reference` (prompt or request), `originalAsset` (local path it replaces, never committed), `path` (source frames) |
| `rights` | `status` (unresolved / cleared-synthetic / cleared-new-art / cleared-original / denied), `notes`, `publicRepoAllowed` |
| `frame` | `width`, `height` in pixels. Set by the art, never by the atlas |
| `directions` | `count`, `order` (`east-clockwise`: 0 faces east, clockwise on screen), `stepDegrees` |
| `animations` | `name`, `frames`, `frameMs`, `loop` |
| `pivot` | `x`, `y` in frame pixels from the top-left, y down |
| `atlas` | `chosenLayout`, `layouts[]` with columns, rows, padding, extruded, page size, `pages[]` (`path`, `robloxAssetId`), `frameRects` (atlas.json) |
| `outputs` | `sourceDir`, `runtimeDir`, `luauModule` |
| `approval` | `state`, `approvedBy`, `approvedAt`, `studioCheck` |
| `roblox` | `uploaded`, `assetIds` (one per page), `moderation` |

A local PNG is not a Roblox asset: ids stay null until uploaded.

## Packaging rules

* Vehicles keep WarFront's 120×120 frames and all 16 directions in WarFront order. Infantry 48×48, buildings 48 px per cell.
* Default layout: 8 columns × 2 rows per animation frame, no padding (960×240 for one vehicle frame set).
  Every frame keeps a ≥2 px fully transparent gutter, and sprites render with `ResampleMode.Pixelated`, so
  unpadded neighbours can't bleed. `--padding 2 --extrude` is available if filtering ever changes.
* More animation frames add rows (2 per frame set); pages split at 1024 px (4 frame sets per page for vehicles).

## Commands

```
python tools/asset_pipeline/synth_frames.py                       # synthetic test frames only
python tools/asset_pipeline/pack_atlas.py <source_dir> --luau-name <Name> [--padding N --extrude] [--dev-pixels]
python tools/asset_pipeline/validate_atlas.py assets/sprites/runtime/<assetId>/r<rev>/p<padding>
```
Requires Python 3 with Pillow (`pip install pillow`).
