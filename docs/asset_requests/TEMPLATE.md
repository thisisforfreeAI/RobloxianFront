# REQ-nnnn: <short name>

| Field | Value |
|---|---|
| Request ID | REQ-nnnn |
| Asset ID | <snake_case, stable> |
| Revision | 1 |
| Kind | vehicle / infantry / building / effect / ui / icon |
| Purpose | <gameplay role> |
| Why new art | <rights unresolved for the original / Roblox-only UI / other> |
| Reference allowed | null <or what may be shown to ChatGPT, once the rights scope allows> |
| Rights status | unresolved |
| Perspective and style | Top-down, orthographic, matching the game's look |
| Frame size | 120 × 120 px (vehicles), 48 × 48 (infantry) |
| Directions | 16, index 0 faces east (right), then clockwise in 22.5° steps |
| Animations | idle: 1 frame <add name, frame count, ms per frame, loop> |
| Pivot | (60, 60): the vehicle's turning centre at the frame centre |
| Transparency | RGBA PNG, straight alpha, ≥2 px fully transparent border in every frame |
| Delivery | One PNG per direction: `dir_00.png` … `dir_15.png` (or one sheet, 8 columns × 2 rows, no padding) |
| Output folder | assets/sprites/incoming/REQ-nnnn/ |
| Approval | pending |
| Roblox asset ids | null |
