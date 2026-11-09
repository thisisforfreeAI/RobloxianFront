# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-09

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public; first commit 4142c4e pushed 2026-11-09)

## Phase
Phase 1. Milestone 1A done (Studio tests 1–7 pass). Pilot sprite REQ-0001 approved. Milestone 1B (gameplay loop) rewritten for WarFront parity and tested outside Studio; Studio tests B1–B9 pending.

## Verified outside Studio (actually run, Linux container)
- Lune 0.11.1 `tests/run`: 68 passed, 0 failed (latest run) (including the 2 that read the GameData generated from your install).
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
- TEMP-001 closed: fog of war. The server sends each player only what their side sees (`Shared.Simulation.Fog`); enemy units outside vision never reach the client
- TEMP-002 closed: units now plan routes with the game's pathfinding (`Shared.Simulation.Pathing`); `Movement.luau` is no longer used by the match
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
WarFront's bot is ported for the slice (`Shared.Simulation.Bot`): personas balanced/turtle/warlord and
difficulty from the game's data, trucks and rig upgrades, HQ training, influence map, home guard, rig
defence, fall back, rig targets and the HQ assault timer. It skips what the slice lacks (buildings,
cities, recon, naval...).

Unit pathfinding (2026-11-09) is ported from the game (`Shared.Simulation.Pathing`): per-unit move
tables (off-road bias 1.6, foot roughness, road pace), the game's A* with its minimum-cost heuristic and
the "no back" re-search, foot-group ranks (up to 8 wide, 1.8 cells apart, nearest units in front,
left to right as they stand) or ring slots on rigs, exact click spot for a single unit, per-unit offsets
off road, corner cutting within 4 cells when the straight line is no slower, wall sliding, and re-plan
after 6 s stalled (give up after 2 tries). APPROX: each unit plans its own route (the game shares one
route per group and uses a path guide), no separation push, bridge-deck lanes or column pacing, and
vehicle steering is not ported (the slice has foot units only). Attack approach re-plans when the
approach point moves 2 cells or more (APPROX).

Buildings (2026-11-09, `Sim.luau` header lists every rule): barracks and factory are placed with the
game's full placement check (terrain, road clearance, rig pad, spacing, the seal check, territory,
enemy gap, requirements, oil), go up over 15 s / 22 s, block their 3 x 3 footprint (the HQ blocks its
5 x 5 too, trucks may still enter it), repair after 5 s untouched, stop working below half health, and
train from their own queues (barracks: infantry, AT; factory: tank, IFV). Territory
(`Shared.Simulation.Territory`) is the game's painting: structures reach buildRadius x 1.6, rigs 12
cells (30 when a building of theirs stands within 36), wobbly edges from the game's noise, split by deep
water. An HQ lost while an active factory stands gives 120 s before elimination (the command truck that
rebuilds an HQ is not in the slice). The bot follows the game's build order (barracks after 15 s,
factory after 200 s at 3.5 oil/s income, a second barracks after 420 s at 6/s, a second factory after
600 s at 7/s; bunker and radar steps are passed over), places with the game's 120-try search, keeps
the facility's cost in reserve while it saves for one, and trains with the game's producer rules
(barracks: AT 30%, else infantry while foot units are under half the army; factory: tank 45%, IFV 30%,
the artillery/rocket 25% trains nothing in the slice). The client has build buttons (B/F), a placement
ghost tinted by your territory, building blocks with build progress, and per-building training (click
a building, Q/E).

Bot-vs-bot on Saddle now ends: balanced v warlord, warlord wins at 11:52; turtle v warlord, warlord
wins at 11:04; balanced v turtle, balanced wins at 20:42; balanced v balanced, side 1 wins at 26:46.
CPU: about 4–6% of real time. Lune: 48 tests pass (6 new for buildings and territory).

Fog of war (2026-11-09): vision is the game's (own buildings, rigs, units and trucks light circles of
their sight; a building under construction sees footprint + 1; units in the same 1.5 x cell-scale
block with the same sight count once). The game's 480 s day/night cycle runs, and at full night sight
drops to 0.4x (night ops are on in the game's defaults; the night vision tower is not in the slice).
The server keeps a viewer per player side and sends only enemy units on cells seen now, the enemy HQ
(always shown, as in the game), enemy buildings while seen and then as "last seen", and rigs with the
owner last seen. The client darkens ground not seen now. The game's bots also play with fog
(intel.fog and bots.fog), so the bot now uses its own intel like the game: its own vision, enemy units
remembered for 45 s (counted half after 30 s in its influence map), buildings until seen gone, rig
owners as last seen, and an unseen HQ or rig assumed to hold 250 or 150 worth of defence. Not in the
slice: radar contacts, drones, last-known enemy unit markers on the client.

Bot-vs-bot on Saddle with fog: balanced v warlord, warlord wins at 11:26; turtle v warlord, warlord at
11:13; balanced v turtle, balanced at 16:16; balanced v balanced, side 1 at 16:55. CPU about 3–4% of
real time. Lune: 51 tests pass.

Defences and more units (2026-11-09), traced from the game's code:
- Bunker (110 oil, 10 s, 1100 hp, MG 8 dps, 16.5 cells) and AT gun (80 oil, 8 s, 300 hp, cannon 14 dps
  x2 vs armour, 19.5 cells). Placed like other buildings (keys K and G). Every built, working, armed
  building now fires: the nearest enemy unit in range, else a truck. Defences add territory like other
  buildings.
- Shot flight now follows each weapon's speed (cannon 38, rocket 22, shell 13, mortar 6.5 cells/s; bullets
  stay 70). Before, tank and AT shots landed instantly. This is a correction for parity.
- Mortar (barracks) and artillery (factory): fire only after standing still 3 s / 4 s, are revealed to the
  enemy for 6 s after firing, and pack 2 s / 3 s before moving again. Splash (3.6 / 4.5 cells): the hit
  grows with bunched foot soldiers and half of it lands on the target's comrades. Artillery fire ignores
  flanking and armour facing. Mortars have a 7.5 cell minimum range and, with fog on, only fire on cells
  their side sees (artillery needs no spotting, as in the game).
- Scout car (factory): R deploys it for recon, seeing 66 cells for 90 s (not shortened by night); any
  order packs it; then a 60 s cooldown.
- Bot: builds the game's bunker step at the nearest rig it does not own, home guards after 300 s and rig
  guards after 180 s; trains mortars, artillery and scouts with the game's shares; sends scouts to deploy
  near enemy HQs.
- Client (placeholder looks): defence blocks are low and grey-textured; units show RECON, PACKING or
  SETTING UP; the producer panel has up to 4 units (Q/E/Z/C).
- Not in the slice: rocket artillery (its 12% factory pick trains nothing), SAM, radar, drones, veterancy.

Bot-vs-bot on Saddle (30 min cap): balanced v warlord, warlord at 13:07; turtle v warlord, warlord at
14:59; balanced v turtle, balanced at 19:44; balanced v balanced had no winner by 30:00 (side 1 had 10
rigs to 4 and was pushing; the bot's push moves units past the HQ rather than attacking it, which needs
a look). CPU about 5% of real time.

Towns and cities (2026-11-09), traced from the game's settlement code: Saddle's 23 settlements start
neutral and are captured like rigs (two infantry take a town in 16 s; village 10, city 22, capital 60).
A held town, city or capital claims territory you can build in: its urban radius plus a margin (town
6 + 12 cells). Villages claim nothing. Enemies alone in a held settlement wear its hold down twice as
fast, then it turns neutral with their capture started; the owner's units there stop that. Captured
rigs already allowed building round them (now covered by a test). Not in the slice yet: garrisons
(units inside, fortified/secured status and its benefits), city traits, forward training, settlement
damage. The bot now goes for towns as the game's does (after 90 s, by value, distance and defence,
capped by bots.cityHeld / maxOccupied; no garrisons, so every held town counts as ungarrisoned).
Bot-vs-bot on Saddle with towns: balanced v warlord, warlord at 15:19 (it held 3 towns); balanced v
balanced, side 1 at 29:18 (4 towns). With fog, a settlement you don't see shows the owner last seen there and no capture progress (as rigs
do; APPROX of the game's viewer).

Garrisons (2026-11-09), traced from the game: select infantry or AT and press H over a town you hold
(PROVISIONAL key). Up to garrisonFull (village 2, town 3, city 4, capital 6) go in; nearby ones enter at
once, others walk there. A town is occupied (nobody inside), fortified, or secured (full). Inside, men
take 0.6x damage (secured town 0.4x) instead of terrain cover; when secured they fire 1.3x harder
(town) from 3 cells further, the town sees 30 cells, hurt own units near it heal slowly, and its owner's
building territory widens 4% (max 30%). A garrisoned town cannot be worn down; any order brings a man
out. The bot garrisons its towns with a share of its army (bots.garrisonShare x (0.5 + defence)), trains
infantry to fill them, and weighs enemy garrisons when choosing towns. Not in the slice: city traits,
forward training, discounts, settlement damage.

Idle units (2026-11-09), traced from the game's idleThink and holdAtEnemy: every unit keeps a post,
which is where it was sent, stopped or arrived. A unit standing idle chases enemies that come within 18
cells (match leashCells) of its post if they are out of range, and stops chasing as soon as it can
shoot. Pushed more than 9 cells from its post with nobody to fight, it walks back. A unit walking
straight into an enemy it can hurt stops 2.1 cells (enemySpaceCells) short instead of walking through.
The bot counts chasing units as idle, as the game does.

Seeking cover (2026-11-09), traced from the game's seekCover: twice a second, an idle armed foot soldier
with an enemy it can hurt in range looks up to 9 cells round it for a free cell with at least 0.08 more
cover (forest 0.25, hills 0.15, town 0.2, ...). The cell must keep the enemy between 2.1 cells and 90% of
its range away and stay within the leash of its post. It takes the best cover, nearest first, skips
cells a comrade already holds, walks there and makes it its new post.

## Next
1. You run Studio tests B18–B27 (defences, mortar, artillery, scout) and commit.
2. Then: engineers' repair work, vehicle steering, a closer look at the bot's HQ push; later shared group
   routes and separation.

## Open questions
1. Rights scope: original art, audio, voice; public redistribution of extracted data.
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.
