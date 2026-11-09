--!strict
-- Terrain legend in WarFront's order (index 0..11 as stored in map grids).
-- Colours are PLACEHOLDER (TEMP-003) until the art scope is settled.
local Terrain = {}

Terrain.names = { "deep", "shallow", "beach", "plains", "forest", "hills", "mountain", "snow", "desert", "marsh", "river", "fallout" }

Terrain.placeholderColor = {
	deep = { 28, 52, 84 },
	shallow = { 52, 92, 122 },
	beach = { 196, 182, 128 },
	plains = { 112, 128, 76 },
	forest = { 62, 88, 52 },
	hills = { 128, 120, 84 },
	mountain = { 112, 104, 96 },
	snow = { 222, 226, 230 },
	desert = { 194, 166, 112 },
	marsh = { 84, 102, 80 },
	river = { 60, 104, 136 },
	fallout = { 120, 116, 70 },
}

return Terrain
