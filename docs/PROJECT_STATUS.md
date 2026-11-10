# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-09

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public; first commit 4142c4e pushed 2026-11-09)

## Phase
Phase 1. Milestone 1A done (Studio tests 1–7 pass). Pilot sprite REQ-0001 approved. Milestone 1B (gameplay loop) rewritten for WarFront parity and tested outside Studio; Studio tests B1–B9 pending.

## Verified outside Studio (actually run, Linux container)
- Lune 0.11.1 `tests/run`: 108 passed, 0 failed (latest run) (including the 2 that read the GameData generated from your install).
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
- Not in the slice then: rocket artillery, SAM, radar, drones, veterancy (rocket artillery, SAM and drones came later).

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

Engineer repair (2026-11-09), traced from the game's repair order, task think and updateRepairs: select
engineers and right-click one of your damaged buildings (PROVISIONAL control). They walk to within
footprint + 4.5 cells of it, stop and mend it at 2.5% of its full hp per engineer per second (up to 3
engineers), then go idle when it is whole. Any other order ends the job; a building that is lost or
already whole ends it too. The tag reads REPAIR. The bot sends its first idle engineer to any of its
buildings under 70% hp, as the game's bot does. Not in the slice: road wear and cuts, rig blowouts,
rail, sabotage and trenches.

City traits and discounts (2026-11-09), traced from the game's trait assignment, eA, Ewe, tZe and
unitCost: at the start every town and city gets a trait. Each side's towns, nearest first, take rail,
hospital, factory, radio, airfield in turn; a town about equally far from both starts begins at factory.
On Saddle that gives Slavany/Velika rail, Bogivka/Bogopil hospital, Pokrar/Rosany factory
(UNCONFIRMED: compare with the town panel in WarFront). A trait works only while its town is held and
secured: hospital heals your foot units within 18 cells of it 5% a second, rail makes your trucks within
90 cells 1.3x faster, factory takes 15% off vehicles. Every secured settlement also takes
village 4% / town 9% / city 15% off unit prices, 30% at most; the HUD shows the discounted price. The
town tag shows the trait ("Rail ON" when working). The bot values towns with a trait 25% more, as the
game's bot does. Not in the slice: the radio trait's radar and the airfield's air drop (no radar or
aircraft yet). Bot-vs-bot after this: balanced v warlord ends (warlord, about 13 min); turtle v balanced
reached the 30-minute cap with no winner (6/11 towns held), where it used to end.

Forward training and workforce (2026-11-09), traced from the game's queueForward, rZe, productionSpeed
and the bot's Nst: click inside one of your towns or cities and the HUD shows Infantry / AT buttons for
it (Q / E). It trains only while the town is secured (full garrison); paid at once, up to 6 queued,
counted against the unit cap. New men appear just outside the town's edge. If the town is lost the queue
is refunded. Every secured settlement also speeds up all training: village 6%, town 12%, city 20%, at
most 60%. The bot trains in its secured towns that are nearer the enemy than its barracks when it is
short of foot units or garrison men. Bot-vs-bot after this: balanced v warlord ends (warlord, about
13-15 min); turtle v balanced ends again (balanced, about 20-22 min).

Vehicle driving (2026-11-09), traced from the game's Uat drive model: tanks, IFVs, artillery (tracks)
and scout cars and engineers (wheels) now drive instead of sliding. They speed up at top speed /
accelSec and brake at top / brakeSec, steer toward a point 1-4.5 cells ahead on their path, slow for
corners up to 70%, and brake to stop on their goal. Tracked vehicles pivot on the spot when the way
ahead is more than 50 degrees off; wheeled ones turn no tighter than their turning radius and do
three-point turns. A goal close behind (6 cells, 12 when shooting forward) is reached in reverse at
45% pace. A vehicle that makes no progress re-plans after 6 s and gives up after 20 s. A standing
vehicle without a turret turns its hull toward its target. APPROX: no formations or shared lanes, no
overtaking or dodging round blockers, no traffic slowdown next to trucks. Bot-vs-bot after this:
both matchups still end (warlord about 13-15 min; balanced v turtle about 18-20 min).

Town damage (2026-11-09), traced from the game's lf / OD / RZe: artillery and mortar shells that land in
a settlement, on units or buildings there, take 60% of their damage off its integrity (village 400,
town 1000, city 2400, capital 5000). Under 70% it reads Damaged, under 30% Critical, at 0 it lies in
ruins. After 60 s without hits it mends to full over 10 minutes and stands again at 30%. Direct fire
(rifles, tank guns) does not damage towns. In the game ruins matter to refineries, dams and events,
none of which are in the slice yet, so here they change only the look and the tag.

Capital (2026-11-09), traced from the game's Owe: while you hold the capital secured (full garrison),
all of your own territory counts as seen, so enemy units inside your borders show up even without a
unit nearby. Not in the slice: the capital's paradrop and demolition-team powers (no aircraft or
demolition units yet).

Bot capital assault (2026-11-09), traced from the game's fat: after 300 s (divided by the persona's
appetite: turtle 0.6, balanced 1, warlord 1.6) and with 3 rigs, the bot gathers its idle units 30% of
the way from its HQ to the capital; once their worth reaches the larger of the threat there x margin
and 180 x appetite, all of them go in. A muster that takes over 150 s breaks up and waits 150 s. Once
it holds the capital, idle units go to defend it whenever enemies come near.

Radar (2026-11-09), traced from the game's radars / jJe / wwe and the radar building's rules: a finished
radar (190 oil, Y to place) and a secured radio-trait town each sweep 54 cells. Every enemy unit inside
a sweep that you can't see shows as a contact dot; units within 15 cells of each other form a group
whose strength comes from their capture values (light under 4, medium from 4, heavy from 10). Trucks
are always light. The bot builds a radar near its HQ after 8 minutes and counts each unseen contact at
60 / 180 / 450 worth when it sizes up a target, as the game does. APPROX: no radar boost, no power,
no "radar contact" warnings, no movement arrows on the dots. Bot-vs-bot after this: warlord v balanced
about 16 min; balanced v turtle reached the 30-min cap once (both sides more cautious with contacts)
and ended in about 19 min with the sides swapped. A check with the radar taken out of the build list
ends that match again (turtle wins at about 25 min), so the stall comes from both bots spending 190
oil on a radar at 8 minutes, as the game's build order does.
Bot knowledge (fix): like the game, the bot counts one contact per group of enemy units in its sweep
and out of sight, not one per unit.

Unit intel markers (2026-11-09), traced from the game's unit intel (JJe): an enemy unit you saw and
lost stays marked, faintly, where you last saw it for 45 s; a dead unit's marker goes as soon as its
spot is in sight again.

Match alerts (2026-11-09): match events now show as short alerts at the top right for the side the
game alerts. That covers rigs attacked, being captured, captured or lost, a rig out of trucks, trucks
destroyed, towns attacked, taken, lost or in ruins, buildings and units ready, buildings destroyed or
repaired, road cuts and downed bridges (to the side that cut it and to the sides whose supply route ran
through it), sabotage armed, done or failed, and roads repaired. PLACEHOLDER wording; the game's own
text and sounds are not used.

Phase 2 leftovers (2026-11-09):
- Performance: a per-tick unit grid answers "who is near" for target search, enemy spacing and
  separation, with ties broken exactly as a full scan would (bot matches came out identical). On Lune,
  Saddle, both sides marching into each other for 60 s: 100 units about 3 ms a tick, 250 about 9 ms,
  500 about 23-25 ms (the budget at 20 Hz is 50 ms); single ticks peak at 45-110 ms when many units
  re-plan routes at once. Studio's Luau may differ.
- Bot HQ push: 16 units ordered at an HQ now stop round it and destroy it in about 45 s, and the
  balanced v balanced match that used to stall now ends (about 24 min).
- Group routes, traced from the game's orderMove: a unit within 12 cells of a groupmate that already
  has a route joins that route where a straight walk reaches it, then steps to its own slot, instead
  of planning its own (the game's joinAt / straightPassable). Not ported: the game's group flow field
  and walksPerTick spreading of route searches.
- Separation, traced from the game's separate: units ease apart every tick. Friends closer than 1.2
  cells (3 for a soldier in a firefight) push at up to 1.5 cells/s, enemies closer than 2.1 cells at up
  to 2.4 cells/s; a push off passable ground, or a soldier in a fight stepping to worse cover, is
  dropped; vehicles only slide along their heading. APPROX: no yard clearance.
Bot-vs-bot after these: warlord v balanced about 15 min, turtle v balanced about 17 min, balanced v
balanced about 24 min.

Roads (2026-11-09), traced from the game's uI / N7e / GX / wh / KX / Mme / zst: trucks, tracked and
wheeled units wear the road cells they drive over (dirt tracks wear fastest, highways slowest); above
35% wear traffic slows, down to half pace on a worn-out road. Artillery and mortar shells landing near a
road wear it and leave strike damage that fades after 20 s; 260 damage within the cut radius (3.6
cells) cuts the road there. A cut stops being road (on a bridge it drops the bridge), so rigs can lose
their link home, routes are redone and trucks re-route or wait. Engineers repair a cut for 30 oil
(paid once per side) in 30 s per engineer, up to 3, and mend worn road back to new. The bot sends idle
engineers to cuts near its rigs or HQ or on its rig routes, then to the most worn cell (55%+) on its
routes. Right-click a cut or worn road with engineers selected to send them. APPROX: every side sees
every cut; trucks re-route over the normal truck cost map. Not in the slice: rail,
mountain passes, weather wash-outs.

Sabotage (2026-11-09), traced from the game's XX / _me / DZe / FZe / Jst: engineers sent to a road cell
(V with the cursor on a road) plant a charge for 25 s while standing within reach; a crew member who
dies, is hit or gets another order ends it. Then it is armed, the crew walks off to the nearest own
building, and 6-8 s later it blows and cuts the road like shellfire. Now and then (at most every 180 s
after the first 240 s, more often for the warlord) the bot sends its last idle engineer to sabotage an
enemy rig's road home, 30-70% of the way along it. APPROX: the bot knows who owns each rig; the game's
"saboteurs spotted" warning and the reveal strip it gives the victim are not in the slice. Bot-vs-bot
after this: warlord v balanced about 15 min, balanced v turtle about 27 min.

Traffic (2026-11-09), traced from the game's FWe / UWe / NWe: a truck on a road with a tracked or
wheeled unit on the road within 3.6 cells drives at 55% pace; a tracked or wheeled unit on a road with
a truck that close keeps only 40% of its road bonus. Foot units don't cause jams. Not in the slice:
road signs, convoy spacing and merging. Bot-vs-bot after this: about 15 min and 23 min.

Convoys (2026-11-09), traced from the game's kme / gUe / wUe / SZe / MZe: trucks drive at a quarter
pace off road, 60% on a bridge, 70% in town and slow to 55% into a sharp bend. They pull away over 3 s
and brake ahead of slower stretches and stops. On a road a truck keeps 2.4 cells behind the own truck
ahead; one stuck behind a slow (not stopped) truck for 5 s creeps on at 35% pace. A truck that sees
armed enemy ground units within 4.5 cells of its road up to 18 cells ahead stops 3 cells short and is
"held" until they leave. A truck whose road is cut tries a new route every 2 s; with none it stops
short of the cut, and after 30 s it is "stranded". Both raise an alert for the owner (per rig, at most
every 45 s and 30 s), and the truck's label shows HELD or CUT OFF. APPROX: trucks still drive cell
centre to cell centre (the game smooths corners into curves along the drawn road line) and the bend
check looks one cell ahead, not the game's 1.5-cell window; stopShortCells is unscaled in the match
data, so it is multiplied by the cell scale (like movement.shareCells). Not in the slice: road signs,
the bot's sign-posting of held convoys. Bot-vs-bot after this: warlord v balanced about 15 min,
turtle v balanced about 20 min, balanced v balanced about 20 min.

Air drops and the capital's powers (2026-11-09), traced from the game's $X / G_ / KGe / zpe / qGe /
GGe / XGe / pq / pat: in a land match the game's aircraft are transport planes. A secured airfield town
(key L at the cursor; the server picks your nearest ready one) flies 2 rifle squads to a point within
135 cells, then waits 240 s. Whoever holds the capital (no garrison needed) can call 6 paratroopers
anywhere (P, then 180 s) and send a bomb truck (J, then 180 s). The plane comes in from the map edge on
the heading whose run in is closest to 30% of the map's short side, drops its sticks along its line
centred on the point, and each lands 5 s later; the whole drop is down about 17 s after the call.
Drops can't land within 9 cells of the edge or on water. The bomb truck leaves the capital's edge
toward the point (sent at the enemy unit there unless an enemy building is near it) and blows up
next to an enemy building or its unit, or on N: units within 3 cells die, others within 6 take up
to 380 x the hit table (falling to 60% at the edge, x cover), buildings take up to 1400, and the
nearest road takes strike damage. The bot calls its airfield towns and the capital's paratroopers
onto its own threatened town, a target its groups are sent at, or the nearest rig that is not
its own, and sends bomb trucks at the known enemy building worth most (factory, SAM, barracks
first, armed ones 1.5x, nearer is better). Planes and falling canopies show in the game (blue own,
red enemy); the HUD shows the powers' state. APPROX: every side sees every plane (the game shows
them by sight); rigs can't be damaged in the slice, so the bomb truck doesn't hurt them. Not in the
slice: SAM sites shooting at planes, carrier jets and bombers (naval), weather blocking drops.
Rail and mountain passes are not ported: the Saddle map, the only one in the slice, has neither.
Bot-vs-bot after this: about 14, 20 and 19 min.

Recon drone and SAM sites (2026-11-09), traced from the game's NJe / WJe / mwe / UJe / lA / sge / rje /
tat: the drone is bought once for 120 oil (key O at the cursor) and flies from your finished HQ at 18
cells/s. It circles the point for 25 s, showing 49.5 cells round it (less at night) plus 6 cells
round itself all the time, then flies home and refuels for 60 s; later flights cost nothing. A SAM
site (120 oil, key U) fires a missile at an enemy drone within 24 cells every 10 s; the missile flies
30 cells/s and downs the drone if it gets within 1.2 cells inside 8 s. A downed drone can be replaced
(bought again) after 60 s. SAMs never shoot at ground units. After 150 s the bot sends its drone now
and then (20% per think, buying it only with 240 oil in hand) over a target its groups are going for,
a radar contact near home, an enemy rig or an enemy HQ it doesn't see now, skipping spots a known
SAM covers. The bot builds SAMs only after seeing enemy aircraft, which never happens in a land
match. Drones and missiles show in the game; the HUD shows the drone's state. APPROX: every side
sees every drone and missile. Bot-vs-bot after this: about 15, 20 and 19 min.

Rocket artillery (2026-11-09), traced from the game's orderBarrage / salvo / rocketLands / P_ / Xb /
Qze / eUe / Gst / Gbe: the factory trains it (key M, 160, the game's 12% bot pick). It never fires on
its own. Select launchers and press I with the cursor on a point at least 18 cells away; a launcher
out of its 72-cell range drives to 0.9 x range first. Once stopped it raises its rails for 3 s, then
(reloaded, 45 s) fires 8 rockets about 0.75 s apart, each landing within 3.3 cells of the point
(pattern from a seed of its id and the time, as the game). Each rocket deals dps x reload / 8 to
everything in its splash (units x hit table x cover x bunching, buildings, trucks, roads). After the
last rocket it lowers its rails and drives 'scootCells' away from its target. The bot fires each idle,
reloaded launcher at the best target in reach: a known enemy building (cost, +200 if armed), an
enemy unit seen this think, or an enemy rig worth more (pump rate x paySec, not struck again within
againSec). APPROX: a launcher waiting on its barrage is kept out of the bot's attack groups.
Bot-vs-bot after this: about 15, 21 and 28 min; in one match the bots fired 47 barrages.

Artillery base (2026-11-10), traced from the game's killsOf / payKills / killUnit / cA / vI / mJ / mge / gJ /
wge / Dst / Zst / m0e: each enemy unit a side kills (the last hit counts) adds one kill. The base costs
20 kills and no oil (key ; or its button), goes up in 20 s, and reaches 270 cells (the whole Saddle map).
With the cursor on a point, . fires a barrage (15 kills; then 20 s before the next): 18 shells about
0.3 s apart within 7.2 cells, 1600 damage shared, each hitting 3.3 cells round it (soft 1.3, armour 1,
buildings 1.3). Each enemy SAM site that is built, reloaded and in range of where shells land stops up
to 6 of them, then reloads for 20 s. , fires flares (5 kills): 5 flares about 0.9 s apart within 12
cells; each bursts on arrival and lights 40.5 cells round it for your side for 100 s, drifting downwind
at 0.18 cells/s. The bot builds a base once it has a barracks and 20 kills, fires barrages at the
most valuable cluster it knows of when it is worth 260 x (margin / 1.5), and fires flares over what
its groups are attacking (30% a think by night, 8% by day) or the best cluster by night. The HUD shows
kills and the base's waits; only you see your flares. Bot-vs-bot after this: about 15, 19 and 19 min;
in one match the bases fired 3 barrages and 17 flare volleys.

Night operations tower (2026-11-10), traced from the game's wb / vge / nV / xje / wQ / Cje / Mje / m1e /
Lje / Dst: at full night a side sees 0.4 of its sight, or 0.9 while it has a finished Night
Operations Tower that is switched on (160 oil, key ' or its button). By night (from 0.5 dark) a side
without one gets none of the game's quiet alerts (rig attacked or being captured, convoy held, and so
on). A lost tower can only be replaced after 300 s. The bot builds one once it has a barracks and a
factory. The HUD shows night vision on, off, or the wait for a new tower. Not in the client yet: the
on/off switch (the sim has it). Bot-vs-bot after this: about 15, 20 and 17 min; both bots build it.

Veterancy (2026-11-10), traced from the game's $5 / Yat / AN / A0e / TN / PN / Jat / Qat: the unit
whose hit finishes off an enemy unit counts a kill. At 3, 8 and 15 kills it becomes veteran, elite and
hero. Each rank adds 30% damage, takes 9% off its reload (never below half) and makes hits on it do
1 / (1 + 0.45 x rank) of their damage. A hero heals 2.5% of its hp a second while nobody is shooting at
it and it isn't firing. Units show ^ marks per rank and an alert names each promotion. Kills by
buildings promote nobody. Bot-vs-bot after this: about 13, 19 and 18 min; 7 promotions in one match.

IFV transport (2026-11-10), traced from the game's B3 / Pk / Tm / VV / IQ / EQ / OQ / Up / VQ / gbe / uG /
ybe / wbe / jst (land part): an IFV carries 2 infantry or AT. Right click your IFV with them selected
and the nearest ones (as many as there is room for) walk over and get in within 3.6 cells. They give
up if it drives more than 36 cells away first. Riders are out of the world, so nothing sees or hits
them, and they ride along. / sets them down 3.6 cells behind the IFV. If the IFV is destroyed each
rider loses 35% of its full hp and jumps out round the wreck. Units show +N for riders aboard. The
bot fills idle IFVs at home (within 48 cells of its HQ) with idle riders within 18 cells, and
unloads them when an armed enemy is in the IFV's sight or the IFV stands idle away from home. Not
ported: ships, heroes. Bot-vs-bot after this: about 15, 24 and 19 min; up to 14 riders aboard at once.

## Next
1. You run Studio tests B18–B48 (defences, mortar, artillery, scout) and commit.
2. Done since: engineers' repair, vehicle steering, the bot's HQ push, shared group routes,
   separation, the 100/250/500-unit performance check (`lune run tools/perf.luau 250`) and the
   convoy rules (spacing, town/bridge/off-road pace, held and stranded trucks), airfield drops and
   the capital's paratroopers and bomb truck, the recon drone and SAM sites, rocket artillery, the artillery base, the night operations tower, veterancy, IFV transport.
3. Next: more of the game's land units and buildings that the slice still passes over.

## Open questions
1. Rights scope: original art, audio, voice; public redistribution of extracted data.
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.
