# Sprite facing convention

Recovered by reading WarFront's renderer (local analysis; the code itself is not reproduced here).

* 16 directions for vehicles and infantry, 22.5° apart.
* Direction **0 faces east** (screen right, +x). Indices increase **clockwise on screen**: 4 = south (down),
  8 = west, 12 = north (up).
* The angle is `atan2(dy, dx)` in map cells with y pointing down. The game picks the nearest direction
  (round to nearest, half-steps round up) and rotates the sprite by the leftover angle (at most ±11.25°).
* The pivot is the frame centre: (60, 60) in a 120 px vehicle frame. A few units carry a pivot offset in
  their own data; those are recorded per asset in the manifest.
* Roblox mapping: map cell (x, y) → world (X, Z). A unit with heading h is drawn with frame `index(h)` and
  the quad yawed by `CFrame.Angles(0, World.TOP_GUI_YAW - residual, 0)`. `TOP_GUI_YAW` (−90°) is measured in Studio: an unrotated part's Top-face SurfaceGui has its x axis along −Z. The camera keeps north (−Z) at the top of the screen.

Implemented in `src/shared/Assets/Facing.luau`, tested in `tests/run.luau`, and checked visually by the
Studio atlas test board (docs/STUDIO_TESTS.md, test 6).
