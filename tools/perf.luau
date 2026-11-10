local process = require("@lune/process")
-- Performance check: N units per side on Saddle march at each other for 60 s; prints ms per tick.
-- Usage from the project folder: lune run tools/perf.luau 250   (needs the generated GameData)
local Rules = require("../src/shared/Config/Rules")
local MapCodec = require("../src/shared/Maps/MapCodec")
local Sim = require("../src/shared/Simulation/Sim")
local Roads = require("../src/shared/Simulation/Roads")
local Movement = require("../src/shared/Simulation/Movement")
local Pathing = require("../src/shared/Simulation/Pathing")
local Territory = require("../src/shared/Simulation/Territory")
local ValueNoise = require("../src/shared/Utilities/ValueNoise")
local RngL = require("../src/shared/Utilities/Rng")
local Bot = require("../src/shared/Simulation/Bot")
local map = MapCodec.decode(require("../src/shared/GameData/Maps/Saddle") :: any)
local w = map.width
local starts, rigs = {}, {}
for _, s in map.data.starts do table.insert(starts, { x = math.floor(s.x) + 0.5, y = math.floor(s.y) + 0.5 }) end
for _, r in map.data.rigs do table.insert(rigs, { x = r.x, y = r.y, name = r.name }) end
local t0 = os.clock()
local R = Rules.new(require("../src/shared/GameData/RulesMatch") :: any)
local sim = Sim.new({ rules = R, movement = Movement, roadsLib = Roads, pathingLib = Pathing, territoryLib = Territory, valueNoise = ValueNoise, rng = RngL,
  map = { width = map.width, height = map.height, terrainAt = function(c) return MapCodec.terrainName(map, c % w, c // w) end, roads = (map.data :: any).roads, urbanAt = function(c) return buffer.readu8(map.urban, c) ~= 0 end },
  starts = starts, rigs = rigs, seed = 1, settlements = map.data.settlements })
local b = { Bot.new(sim, 1, "turtle"), Bot.new(sim, 2, "balanced") }
local minD = {math.huge, math.huge}
local N = tonumber((process and process.args and process.args[1]) or "100") or 100
-- clear start units, then spawn N per side in blocks near each HQ, all ordered at the enemy HQ
for _, e in sim.list do if e.cat == "unit" then e.alive = false end end
local kinds = { "infantry", "infantry", "infantry", "at", "tank", "ifv", "mortar" }
for side = 1, 2 do
  local hq = sim.hqOf(side); local foe = sim.hqOf(3 - side)
  local ids = {}
  local k = 0
  for i = 1, N do
    local ang = (i / N) * math.pi * 2; local r = 8 + (i % 7) * 1.5
    local x, y = hq.x + math.cos(ang) * r, hq.y + math.sin(ang) * r
    local c = sim.roads.cellAt(x, y)
    if c >= 0 and sim.roads.passable(c) then
      k += 1
      local u = sim.spawnUnit(kinds[(i % #kinds) + 1], side, x, y)
      table.insert(ids, u.id)
    end
  end
  sim.orderMove(side, ids, foe.x, foe.y)
end
local alive = 0 for _, e in sim.list do if e.alive and e.cat == "unit" then alive += 1 end end
local t1 = os.clock()
local worst = 0
local ticks = 20 * 60
for i = 1, ticks do
  local a = os.clock()
  sim.step(0.05)
  sim.takeEvents()
  worst = math.max(worst, os.clock() - a)
end
local total = os.clock() - t1
local left = 0 for _, e in sim.list do if e.alive and e.cat == "unit" then left += 1 end end
print(string.format("N/side %d  units %d (left %d)  avg %.2f ms/tick  worst %.1f ms  (budget 50 ms at 20 Hz)", N, alive, left, total / ticks * 1000, worst * 1000))
