# RENDERER_DECISION — recommendation (pending benchmark)

**Recommendation: Option C, hybrid.** Gameplay lives in a flat world-space plane viewed by a locked orthographic-style top-down camera. Units, buildings and effects are drawn as sprite quads, terrain is baked tiles, and the HUD, menus and minimap use ScreenGui. This is a recommendation from the audit. It still needs the Phase 1 benchmark before it becomes a decision.

## What we're matching

WarFront is a top-down 2D game: a 768×480-cell grid, pre-rendered sprites at 16 facings (120 px vehicles, 48 px infantry, 48 px/cell buildings), normal-mapped lighting with day/night, a Pixi.js canvas under a DOM HUD, hundreds of units, and smooth zoom and pan.

## Options

| | A: 2D GUI renderer | B: 2.5D world | C: Hybrid (recommended) |
|---|---|---|---|
| How | Every unit and tile is an ImageLabel in a ScreenGui; camera is a UI transform | Flat Parts/terrain, top-down camera, units as SurfaceGui/Decal quads or simple meshes | World-space plane for terrain and sprite quads (Parts with Decal/SurfaceGui, or EditableImage-baked tiles); GUI for HUD, minimap, selection box, health bars |
| Faithfulness to the 2D look | High | Medium (perspective, lighting differ) | High (orthographic-like camera, FOV ~1–5°, high altitude) |
| Zoom/pan | Manual math on every element | Free (camera) | Free (camera) |
| Performance at 500 units | Poor: thousands of GUI objects re-laid every frame; UI layout is the bottleneck | Good | Good, with culling and pooling |
| Clicking / picking | Manual | Raycast | Raycast against the plane, then a server-agnostic grid lookup |
| Facing sprites | ImageRectOffset on one atlas | Same via SurfaceGui ImageLabel | Same via SurfaceGui ImageLabel `ImageRectOffset` into 1024² atlases |
| Lighting/day-night | Tint only | Roblox lighting | Roblox Lighting/ColorCorrection tint; normal maps dropped |
| Map size (768×480 cells) | Huge GUI canvas | Natural | Natural; terrain baked into chunked textures |

## Why hybrid

1. The camera does zoom, pan and culling for free, and world raycasts make selection reliable.
2. GUI-only rendering hits UI layout costs well before 250 units.
3. Keeping sprites as camera-facing flat quads with 16-facing atlas swaps keeps WarFront's look; Roblox lighting stands in for normal-map lighting (documented deviation).
4. HUD stays in ScreenGui, closest to WarFront's DOM HUD.

## Constraints to design around

* Images ≤ 1024×1024: re-pack atlases. A 16-facing × 120 px row needs 2 sheets, or downscale to 64 px frames (8×8 grid per sheet).
* Asset count and moderation: plan atlases per unit family, not per frame.
* No normal-mapped 2D lighting: deviation D-001, needs rights-holder sign-off.
* Rendering must read only replicated *visible* state. Presentation never decides gameplay.

## Benchmark plan (Phase 1, needs Studio)

Build A and C prototypes with 100, 250 and 500 animated units on a 384×240 map, and measure client frame time, memory, draw calls and instance count. If C misses 60 FPS at 250 units on mid hardware, look at EditableImage composited layers.
