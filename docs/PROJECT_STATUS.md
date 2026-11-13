# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-12

Latest feature and verification results are in the dated entries at the end. The early phase and
validation sections below are historical checkpoints.

## Locations
- Original game (read-only): `A:\SteamLibrary\steamapps\common\WarFront Demo`
- Project / local repo: `C:\Users\thato\OneDrive\Desktop\RobloxianFront`
- GitHub: https://github.com/thisisforfreeAI/RobloxianFront (public; first commit 4142c4e pushed 2026-11-09)

## Phase
Phase 1. Milestone 1A done (Studio tests 1–7 pass). Pilot sprite REQ-0001 approved. Milestone 1B (gameplay loop) rewritten for WarFront parity and tested outside Studio; Studio tests B1–B9 pending.

## Verified outside Studio (actually run, Linux container)
- Lune 0.11.1 `tests/run`: 146 passed, 0 failed (latest run) (including the 2 that read the GameData generated from your install).
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
enemy rig's road home, 30-70% of the way along it. APPROX: the bot knows who owns each rig. Since
2026-11-10 (the game's _me / VZe): with fog on, a side whose rig route the charge would cut is warned
once ("saboteurs spotted") when it sees one of the crew while they plant; when the charge blows, each
victim sees 7.5 cells round the cut and round every other cell of its rig routes for 42 cells either
side of it, for 25 s. Bot-vs-bot
after this: warlord v balanced about 15 min, balanced v turtle about 27 min.

Traffic (2026-11-09), traced from the game's FWe / UWe / NWe: a truck on a road with a tracked or
wheeled unit on the road within 3.6 cells drives at 55% pace; a tracked or wheeled unit on a road with
a truck that close keeps only 40% of its road bonus. Foot units don't cause jams. Not in the slice:
convoy spacing and merging. Road signs came later (below).

Road signs (2026-11-10), traced from the game's G7e / GWe / ZWe / WWe / qWe / jWe / $g / iat: = with the
cursor on a road puts up a sign (or takes yours down there). It shuts the road cells within 7.5 cells to
your own trucks (their route costs treat them as blocked); rig routes through it re-plan. At most 8
signs; a sign that would leave one of your rigs with no way home is refused. A beaten side's signs go.
The bot signs the road 9 cells ahead of a truck the enemy has held for 12 s (one a think) and takes it
down after 150 s.

Refineries (2026-11-10), traced from the game's TX / Ape / _pe / _Ge / X_ / k4 / J_ / EGe / PGe / Rpe / Ppe
/ LD / Ist: [ with the cursor on a village, town or city you hold builds a refinery there (145 oil,
30 s, 900 hp). It goes on the best free 3x3 spot round the town: off and clear of roads but within 3
cells of one, away from rigs, buildings and other refineries, preferring the town's edge. While it is
finished and you hold the town, each of your rigs picks the shortest route among the HQ and your
working refineries (re-picked when that set changes), and its trucks unload there; new trucks for
such a rig start at the refinery. Losing the town stops it (rigs go back to the HQ, with a notice);
retaking it starts it again; a ruined town or shells (blasts within reach of its footprint) destroy
it. The bot, every 20 s with 145 + 250 oil and none going up, builds one in the held town the most of
its trucking rigs would reach 30% and 24 cells closer than its HQ. Hand-picked haul routes: see Cut
supply routes below (Alt+T). Not ported: power (power plants are off in the game's match rules). Bot-vs-bot: the
winning side built two. Bot-vs-bot after this: about 15 min and 23 min.

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

Command truck (2026-11-10), traced from the game's Z7e / QY / rk / D9 / j7e / hqOnOrder / mayRehouse /
checkHeadless / Fst: the factory builds a Command Truck (650, key 6 in its panel). Select it and press
R: it stops and after 10 s becomes an HQ on a free cell within 12 cells, preferring one by a road that
reaches the rigs, with the truck's share of hp. Moving cancels it. The new HQ is your HQ. A side with
a command truck is never headless, and the grace clock waits while one is being built. The bot, once
its HQ is gone, deploys its truck where it stands if a road there reaches the rigs, otherwise drives
it back to the old HQ's site; with no truck it orders one at a working factory, first calling off the
last unit of a full queue to make room (the game's cancelQueued). Bot-vs-bot after this: about 15, 24 and 19 min.

Opening drop (2026-11-10), traced from the game's u9e / lk / cD / f9e / p9e / nq / vqe / G_ / bqe / hX /
g9e: a match now starts with no HQs or squads. The war clock waits while each side picks where to
land (68 s, or until both are ready): click the map, Enter when ready. A pick must be 18 cells off the
edge, on open ground with room for an HQ within 12 cells and at least 36 cells from the enemy's
start point; otherwise you land on your own start point. The ring is amber where no road there reaches
the rigs (the truck would have to drive before it can set up). Then each side's plane flies in (14 s)
and drops its command truck and three squads under chutes (5 s); once all are down the war starts
and each truck sets up its HQ at once if a road there reaches the rigs. The bot picks with its
persona's shares: near home, by one of the 3 rigs farthest from every start, or 45 cells in from
the enemy's start; if its truck lands away from a road it drives home and sets up there. Not ported:
the opening deck (the game's random arrival scenes and conditions). The server flag OPENING_DROP in
MatchService turns it off. Tests still build the old start (HQs on the start points) unless they ask
for the drop. Bot-vs-bot with the drop: about 13, 17 and 20 min.

Cancel and demolish (2026-11-10), traced from the game's cancelQueued / cancelBuilding / ert / trt /
Qbe / ort: Backspace calls off the last unit queued at the picked producer (the HQ if none) and gives
back exactly what was paid for it; the one in training starts over. Click one of your buildings,
then Delete: if it is still going up it is cancelled at once for the unfinished share of its price
(and kill cost); if it is finished it comes down over 6 s, its queue refunded first, and gives back
60% of its price and kill cost. It does nothing while it comes down. The HQ can't be pulled down.
APPROX: the game shows the countdown on the building and a cancel button; here a notice says when it
is down.

Armies and minefields (2026-11-10), traced from the game's allows / N$ / armyUnits and Tk / Tet / Aet /
Cve / kve / layMinefield / LA / Pet / Ret / vle / Yq / Lve / EI: each side fights as the coalition
(the game's default) or the republic, set by ARMIES in MatchService. Only the coalition fields
mortars (the bot trains infantry instead); only the republic lays minefields. Press - (or the HUD
button, shown to the republic) and drag a line: every cell within 30 m (one cell either side) of the
line, up to 400 m long, that is open buildable ground off a rig pad, clear of buildings and other
minefields and away from enemy buildings takes mines (roads included). It costs 1 oil a metre and
gets a charge every 10 m, counting only the metres that take mines, and is laid along the line at
0.08 s a metre; it needs 40 m. Any unit but an engineer (yours too) stepping on a laid cell sets one
off: 70 to soft targets, 150 to armour, 40% of that on everyone within 2.7 cells, then 0.7 s before
the next; a truck on it is lost. The enemy doesn't see it until one goes off under them or one of
their engineers comes within 4.5 cells; an engineer standing on it clears a charge every 4 s and
never sets it off. It is spent when the charges run out, can be shot at once found (200 hp), never
blocks the way and claims no ground. APPROX: placing a building over a minefield is refused (the
game clears the mines under it); the bot doesn't lay mines (the game's bot doesn't either). Not
ported: its sea units (no sea on Saddle).

Republic missile launcher (2026-11-10), traced from the game's armyDef / ufe / lS / launchMissile: a
republic side's artillery reads its stats from armyUnits.republic.artillery (the rest from the
howitzer): range 144 cells, one heavy missile on a barrage order (like the rocket launcher: Period
at the cursor), 100 damage over 4.5 cells, 40 s reload, nothing closer than 24 cells, flying at the
game's missile speed. The bot fires it like the rocket launcher. APPROX: alerts and unit labels
still call it artillery (the HUD's train button uses the republic name).

Night vision switch and opening deck (2026-11-10). Press N to switch your night operations towers
off or on (the game's nvOff; with bomb trucks selected N still blows them up); the HUD shows which. The opening deck (the game's hqe / sqe / uqe / Pg):
each match draws the hour the drop arrives from its own seed, day 40 : dawn 18 : dusk 14 : night 8
(storm and sandstorm need the weather, off in skirmish), and the day clock starts at that hour; the
drop banner says which. Not ported: the opening scene (a picture only), the operation name and intel
tip (game text), and the opening conditions (they need the events system, off in skirmish).

Trenches, part 1 (2026-11-10), traced from the game's digTrench / qY / ZY / Uie / sD / GY / lI / MWe / LWe /
SWe / F7e / wWe / vWe / bWe: select engineers, press 7 and drag a line. The line is simplified and
smoothed (up to 102 cells); its ends are trimmed to ground they may dig (open, no building or trench,
not enemy ground, off rigs); it needs 6 good cells. Up to 3 engineers within reach of the next cells
dig it at 0.53 s a cell for 0.73 oil (cells by a road get barbed wire: 1.33 s, 2 oil); without oil the
work stops with a notice. Each dug cell blocks the way for every unit and building (wire on a road
cuts it; oil routes are redone). With the cursor on a trench, 8 sends selected engineers to fill a
9-cell gap (0.8 s a cell, wire 1.67 s). A line nobody is digging any more is cut back to what was dug,
and an existing line can be carried on from its far end. Diggers stand 3.6 cells to one side of the
line, level with the cell 6 ahead, on a route that does not cross the cells still to dig (the game's
mWe). Seal (the game's zie): an end that stops within 6 cells short of water, other ground nobody can
cross or the map edge (ahead of the line, along a straight run of cells that may be dug) is carried on
to it. Not ported
yet: nothing (see parts 2-4).

Trenches, part 2 (2026-11-10), traced from the game's FY / zY / k7e / _Ue / _We / zUe: key 9 picks the kind
dug next. A ditch blocks every unit; a fire trench (0.37 s, 0.5 oil a cell) lets infantry cross at half
pace; vehicle traps (0.23 s, 0.33 oil) let infantry through at 0.85 and stop vehicles; a wire belt
(0.17 s, 0.27 oil) slows infantry to 0.25, stops wheels and lets tracks cross, and a tracked unit on a
belt cell flattens it. Routes weigh these cells by the slowdown. Lines only join lines of their own kind.
A ditch or fire trench cell next to impassable water, or next to a flooded cell, floods (0.12 s a
cell): it then blocks the way, fills in 3x slower, and the owner gets one notice per trench. A caved
ditch cell (damage 1) is crossed like a fire trench; damage itself comes with part 3 (shelling).

Trenches, part 3 (2026-11-10), traced from the game's NUe / FM / UUe / XUe / _7e / VUe / Tf / iI / EUe /
FUe / OUe / DUe / lv / L7e / S7e / P7e / ZUe / GUe:
- Shelling: every blast that wears roads also wears dug cells within 3.6 cells by damage / 150; at 1
  a cell caves in (a ditch becomes crossable like a fire trench, traps and wire are gone) and the
  owner is told (at most every 30 s a trench). A hit of 40 or more smashes dug and wired cells within
  its splash (at least 1.2 cells) flat. APPROX: for direct artillery hits on units the size check uses
  the hit's damage after armour and cover (the game passes the shell's own damage).
- Mending (key 0 with engineers, cursor on the trench): up to 3 engineers mend everything within 9
  cells either side; each works alone, re-digging a smashed cell in 0.83 s or taking 1.2 damage a
  second off a worn one; "Trench mended" when done.
- Manning (key 0 with infantry selected): foot units spread along the fire trench at or near the
  cursor, one to a cell within 21 cells, nearest unit to each cell. Foot units on an intact fire-trench
  cell (or on open ground round a finished bunker or AT gun that touches one) are in the trench: they
  take 0.4 of bullet hits and 0.5 of shell or splash hits, and are hidden from an enemy side (fog,
  intel and target picking) unless it has a unit or building within 7.5 cells or they fired in the
  last 3 s. APPROX: they walk there on normal routes (the game routes ones already in the trench along
  it); separation can nudge one off its cell.
- Breaching (V with engineers on a dug or wired trench cell): planting takes 6 s within 6.1 cells; when
  it blows, 4 cells either side are smashed open (wire on a road reopens it), the owner sees 12 cells
  round the spot for 20 s, and both sides are told. A ditch or fire trench with water within 7.5 cells
  that has not flooded yet floods there instead ("bank broken"). A flooded cell can't be breached.
- A cell turning into a trench some units can't cross (a fire trench for vehicles, say) moves those
  standing on it to the nearest cell round it they can stand on, and those routed through it stop
  (if it was their goal) or plan again (the game's RUe / PUe).

Trenches, part 4: the bot (2026-11-10), traced from the game's JUe / oWe / nWe / tWe / eWe / QUe / C7e /
rI, run at the end of each bot think:
- Digging: with fewer than 2 own trenches, all of them dug, and at least 300 oil (trenchWorks.bots.
  digFrom is oil, not seconds), the nearest idle engineers dig fire trench lines 42 cells out from the
  HQ towards the nearest enemy HQ, 48 cells long across that way, clear of roads (tried at 1, 0.8, 1.2
  and 0.65 of the distance and turned 0, +0.35 and -0.35 rad; the longest one or two stretches that
  lay out without wire and with at least 6 good cells). APPROX: with one engineer the game queues the
  second line; here it is dug on a later think.
- Manning: idle armed foot units (not artillery) within 48 cells of an own fire trench man it.
- Clearing the way: when trenches split the ground a tank could cross between the HQ and an enemy HQ,
  the first trench on the straight line between them is breached by the nearest engineer (an enemy
  trench that is not flooded) or filled in, unless own engineers already work on it.

Rally points (2026-11-10), traced from the game's rallyOf / doorEdge / doorOf / setRally / clearRally /
sendToRally; replaces the APPROX "appear towards the map centre":
- A producer with no rally sends new units production.rallyCells x cellScale beyond its footprint
  (+0.5), towards the nearest road cell within rallyRoadCells x cellScale outside the footprint, else
  the map centre (production.rallyToRoad), clamped to the map.
- The unit appears just outside the footprint edge that faces the rally, offset along the edge by up to
  doorSpan of the half-width, then walks to the next of 8 ring slots round the rally (one slot per unit
  made, in turn). With no path it stays where it appeared.
- ] at the cursor sets the rally of the last own producer clicked (the HQ when none); Shift+] clears it.
  Refused on enemy buildings, buildings that train nothing, and ground units can't stand on. Your set
  rallies show as small green posts.
- APPROX: when the door cell is blocked the game picks random points 1-4 x cellScale out; here the
  nearest free cell is used. Naval yards' rallies are not in the slice.

Releasing trucks (2026-11-10), traced from the game's releaseTruck / WX / yme / gme: Shift+T over your
rig takes one truck off it: the one least along (loading, then heading out, then unloading, then the
rest; then the least oil aboard; the back of the loading queue first). It drives home with what it
carries, unloads, and joins the idle trucks the next T uses. Refused with no trucks on the rig.

Retreat and waypoints (2026-11-10), traced from the game's orderRetreat / queueMove / arrive:
- \ sends the selected units back to their nearest finished HQ: each to its own ring slot at least
  ceil(footprint) + 1 cells from the HQ's centre. While walking there they move at movement.retreatPace
  (1.25x), hold fire and don't stop for enemies in the way. Any new order ends it; refused with no HQ.
- Alt + right click adds a stop after the current move (one ring slot per unit round the point, up to
  movement.waypointCap = 8); units not under a move order go there at once. On arrival a unit walks on
  to its next stop. (This was Shift + right click until the direct-move batch below; the game uses Alt.)
- APPROX: the game's waypoint line drawing is not ported; ships are not in the slice.

Straight moves (2026-11-10), traced from the game's direct move (orderMove(.., direct), moveTable(..,
true), straightWay, lineCells): Shift + right click sends the selection "straight over the land", the
game's Shift modifier. If the straight line to a unit's slot is open it walks that line cell by cell.
Otherwise it routes on a table with no off-road bias where a road costs what the land under it costs
(1 where that land can't be walked, as on a bridge), then pulls the route straight: from each corner it
looks up to movement.directLookCells (24) x cell scale cells ahead (halving) for the farthest cell it
can reach in a line. Direct units don't join a shared group route. Alt + Shift + right click queues a
straight stop; each stop keeps its own flag. Any other order ends it.
- APPROX: the game also tries the group's shared route and a path guide before its plain search here.
- Bot fall-back (the game's rat) now also counts the bot's held towns as safe points, not only its HQ
  and rigs (the game's zV list). Bot demolition trucks, airfield calls, paratroopers and the demo power
  were checked against the game's pat / w0e / y0e and already matched.

Control groups (2026-11-10), traced from the game's QV / xxe / b5t / k5t / Cxe / $ee / eF (client only,
like the game): Ctrl + 1-5 makes a group from the selected units (or, with no units selected, the
building you last clicked; with nothing selected it clears the group), Shift + number adds the
selection to it (units replace a building group and the other way round), the number alone selects
the group (a building group picks its first building, as the producer if it trains), and pressing the
number twice within 400 ms also moves the camera to the group's centre. Dead units and lost buildings
drop out. A notice says "Group n: count" or "Group n cleared".
- APPROX: only groups 1-5 have keys (the game has 1-9), because 6 trains the sixth unit and 7-0 are
  the trench keys here. The game's group chips on the HUD are not ported.
- Bot: when it loses its HQ with a full factory queue, it now calls off the last unit to fit the
  command truck (the game's Fst).

Click selecting (2026-11-10), traced from the game's selectAt / unitsInView / addSameTypeInView: a
second click on the same unit within 350 ms picks every unit of yours of that kind on screen (with
Ctrl held, every unit of yours on screen). Shift + click now adds the unit (it used to toggle it), and
when its kind is already in the selection it adds every unit of that kind on screen too.
- APPROX: the game's M (select everything on screen) has no key here, as M trains a unit.

Rig upgrades for players (2026-11-10), traced from the game's upgradeRig (qX / wme): the Sim (and the
bot) already had them; now a player can buy them. Ctrl+T over your rig upgrades its pump (120 oil,
pumps 1.5x), Ctrl+Shift+T its tank (60 oil, holds 2x). Each once per rig, paid up front; refused with
"Already upgraded" or "Not enough oil". The keys stay as shortcuts; the rig card below has the buttons.

Rig card (2026-11-10), after the game's RigCard: left click one of your rigs and a panel opens at the
bottom right with its tank ("Tank full, needs trucks" when full), pump (most and now, oil a minute),
trucks n / 4, about how much oil they bring home a minute (the game's Yke: each truck capacity / round
trip of 2 x route cells / truck speed + load + unload; shown in orange under 85% of the pump), where
they haul to and the one-way trip time, damage, a cut route or a fight over it. Buttons: send an idle
truck (or buy one, 40), release a truck, second pump (120), bigger tank (60) ("Done" once bought), and
reroute (next way on offer; shows the wait). Greyed buttons say why on hover. X, Esc or a click
elsewhere closes it. The server sends your rigs' figures with the side state.
- APPROX: placeholder look (text and buttons, no truck pips or pictures); no repair button (select
  engineers and right click the rig instead).

Withdrawing a garrison (2026-11-10), traced from the game's withdraw ($I / Bwe / _m): Shift+H on a
town you hold brings everyone inside out (the Sim also takes a count, last in first out, or one unit
by id). Each steps out at a random point on the rim (radius + 0.5), or the nearest free spot to it.
APPROX: the random angle is not the game's sequence.

Cut supply routes and rerouting (2026-11-10), traced from the game's wh / OGe / jm / BGe / FGe / EGe;
replaces "a cut redoes the rig routes at once":
- A road cut no longer wipes the rig routes over it. The next route check finds the route crosses a cell
  trucks can't use: it is marked cut, no trucks leave on it (loading trucks wait, Ordering trucks says
  no route), and it can't be changed for convoys.rerouteCutSec (45 s). Trucks already on the road find
  their own way round as before.
- After that a bot's rig re-routes by itself (then locked convoys.rerouteAgainSec, 8 s). A player's
  route stays cut until they pick a new one: Alt+T over the rig switches to the next of up to
  convoys.routeChoices (3) different ways home (each further search costs cells already used x
  routePenalty 4, and a way sharing more than routeOverlap 0.8 of its cells with a listed one is
  dropped). Alt+T also works on an uncut route to pick another way (hand-picked; kept when the depots
  change unless a new depot is nearer than it). An alert says when a route is cut.
- Alt+T steps through every way on offer, like the game's haulChoices list: each route to the HQ,
  then the best route to each working refinery of yours (the game's haulTo); a notice names the town.
- Bots are marked when Bot.new runs (the game's !isPlayer); a player taking over side 2 clears it.

Rig damage (2026-11-10), traced from the game's uD / dX / Lqe / Sqe / Tqe / Aqe and the bot's kat:
- Rigs have rigs.damage.hp (800). A shell, rocket or bomb landing within rigs.damage.hitCells hits them
  for its damage x blastShare; a rocket's splash reaches rigs out to its radius beyond that at 1 down to
  a half; a bomb truck hits enemy rigs within its blast past hitCells with the building falloff. A side's
  own blasts spare its own rigs (neutral rigs can be hit).
- At 0 hp the rig is wrecked: its tank empties, it pumps nothing, its trucks drive home and no trucks
  can be sent ("not working"). The owner gets an alert while it is shelled (every 30 s at most), when
  it is wrecked and when it is repaired; the attacker hears it was knocked out.
- Engineers repair rigs (right click it with engineers selected): rigs.damage.hp x crew / repairSec
  (60 s for one engineer) from rigs.radius + engineers.reach away; a wreck works again once whole.
- The bot sends its nearest idle engineer to its damaged rigs (wrecked first, then the lowest hp) after
  its other repairs, and its rocket launchers no longer target an enemy wreck it has seen lately.
- Rigs show DAMAGED with a bar, or DESTROYED. Not ported: blowouts (map events, off in a skirmish).
- Stopping a unit now also ends its repair or road job (the game's clearOrders).

Bot: mending and escorts (2026-11-10), traced from the game's hat and the end of sat:
- Every bots.mendEverySec (6 s) hurt units below mendBelow (75%) of their hp, idle or moving and armed,
  quiet for mendQuietSec, with no armed enemy in sight and not on the job their order sent them to,
  walk to the nearest of the bot's secured towns that heals their kind (repairMen / repairVehicles),
  with no known enemy within twice its radius, within mendReach x cellScale; at most mendShare (35%) of
  the army at once. One that comes under fire or can't get there is left alone for mendRetrySec (45 s);
  healed ones go back to the pool. Units being mended are not used for other orders.
- A truck of the bot held up by the enemy for bots.truckHeldSec (6 s) (the one from the rig with the
  most trucks) gets enough units sent to it to beat what the bot knows is near (convoys.lookAhead x 1.5).

Bot: bridges (2026-11-10), traced from the game's _h / v7e / kUe / nat / Yst / Xst / Kst / YQ:
- Bridge spans are the 4-way groups of road (or cut road) cells on ground units can't stand on; a span
  with a cut cell is blown. The bot's bridges are those on its rig routes or within bridgeNearCells x
  cellScale (+ sqrt of the span size) of its territory.
- Guards: with at least bridgeGuardMinArmy (6) units, the bridgeGuardSpans (2) nearest the HQ each get
  bridgeGuards (1) unit posted at the span's end nearest the HQ (at most bridgeGuardShare of the army);
  an idle guard more than 3 x cellScale off its post walks back. Guards are kept out of other orders.
- Blowing: before its other engineer jobs, a bot with persona defence >= bridgeBlowMinDefence (balanced
  and turtle), at most every bridgeBlowEverySec (240 s) and with chance defence x bridgeBlowChance,
  sends its nearest idle engineer to blow a span of its own when a known enemy force worth
  bridgeThreatWorth (300) is within bridgeThreatCells x cellScale and further from the HQ than the span:
  the charge goes on the span's road cell nearest the HQ.
- It leaves a bridge it blew itself unmended for bridgeHoldSec (150 s), then while such a force is still
  near, and mends it after bridgeHoldMaxSec (480 s) in any case.
- Stopping a unit now also ends a sabotage job.

## Next
1. You run Studio tests B18–B90 (defences, mortar, artillery, scout) and commit.
2. Done since: engineers' repair, vehicle steering, the bot's HQ push, shared group routes,
   separation, the 100/250/500-unit performance check (`lune run tools/perf.luau 250`) and the
   convoy rules (spacing, town/bridge/off-road pace, held and stranded trucks), airfield drops and
   the capital's paratroopers and bomb truck, the recon drone and SAM sites, rocket artillery, the artillery base, the night operations tower, veterancy, IFV transport, the command truck, the opening drop, cancel and demolish, armies and minefields, the republic missile launcher, the opening deck, trenches parts 1-4.
3. Next: more of the game's land units and buildings that the slice still passes over.

## Original art (2026-11-10)
BIGJOHN says WarFront's original creator has given permission to use the game's art, and the finished
game will be handed over to that creator. So the original sprite sheets are used, not new art. They
stay local: the extraction (assets/original/, see its CLAUDE_HANDOFF.md) and everything cut from it
(assets/sprites/source/original/, runtime atlases) are git-ignored and are not pushed or uploaded.
Cut so far, each with a source.json (sheet, SHA-256, rectangles, layers), traced from the game's
renderer tables (units sheet: 120 px frames, 16 facings a row, column 0 east then clockwise; 3 rows a
look: colour, paint (multiplied by the side's colour and drawn over), shape (rims and shadows); a
turreted unit has 3 more rows for the turret; men sheet: 48 px, same 3 rows a pose; buildings:
8 frames: colour, paint, 5 height bands, night lights):
- scout car (body, wreck, 2 mast looks), oil truck (full, empty, wreck), tank (hull and turret
  layers, and their wrecks), artillery (moving, 2 set-up looks, wreck), the infantry icon row, and
  the rifleman and squad leader figures with all 21 poses each (walk 4 frames, stand, kneel, prone,
  fallen, crouched and aimed walks, ...);
- HQ (8 frames + its 16-heading dish), refinery (4 facings x 8 frames).
- Not in the building sheet: town buildings. The game draws towns from its city data (cityWorker),
  so REQ-0008 stays open.
- Drawn in game now: tank (hull and turret), oil truck, scout car, artillery and the infantry icon.
  `tools/asset_pipeline/pack_original.py <spec.json>` packs the strips, unresized, into local modules
  `src/client/DevAssets/Orig*.luau` (8 x 2 facings a strip, each page at most 1024 px; git-ignored, the
  spec is in docs/private/). `SpriteBank` loads them into EditableImages; `UnitRenderer` draws the
  colour layer, then the paint layer tinted with the side's colour (Roblox multiplies like the game's
  paint pass), frame = 16-step facing, the rest of the heading turns the quad, drawn width =
  cells / art.w from the game's unit table. Missing modules (a fresh clone) fall back to the blocks.
- Sizes: every unit is drawn at the game's unit scale 1.3 (za.scale), so a tank's frame is
  1 x 1.3 / 0.492 = 2.6 cells wide.
- Infantry squads draw each soldier on his own (`SquadMen`, traced from the game's squad drawer): the
  leader and two riflemen, 0.55 cells each, 0.6 cells apart in a wedge when moving (a file on roads),
  a line when firing, loosely spread otherwise; they walk to their places with the game's gain and
  catch-up limits, the walk frame changing every 0.17 cells walked; kneel when firing or in a trench.
  Losing health drops riflemen first (ceil(hp share x 3) stand). The server now sends each unit's
  firing, road and contact flags and its aim point for this.
- Crews drawn man by man too: AT (gunner and loader), mortar (mortarman and bearer), paratroopers
  (three; their figures have no paint layer in the sheet). A mortar that is setting up, set or packing
  puts its tube down with the crew kneeling beside it, the tube kicking on each shot and the bearer
  turning away for 0.7 s (the game's e7t). The server sends seconds since the last shot for this.
- Oil trucks show their empty look while driving out or carrying nothing (the game's truck_empty).
- Not yet: the turret turns with the hull (no turret angle in the snapshot), no dark rim or shadow
  (the shape row), wrecks, bodies left behind, flinching from blasts, the mortar bearer's loading
  pose, buildings.

## Towns, forests and ground like the game (2026-11-10)
- The game ships every designed map's towns pre-drawn: dist/cities/<id>.city ("WFCT", a JSON header,
  raw DEFLATE parts: a sheet of 14 px tiles (alpha = surface code: 150 green, 200 street, 201 lamp,
  224+ roofs), an index of which tile each map cell uses, height/light data for the roof shading, and
  the trees inside towns). Saddle: 11,008 town tiles on 384 x 240 cells.
- `tools/asset_pipeline/pack_city.py <file.city>` lays the tiles out into 64 x 64-cell chunks (896 px)
  and writes them, raw DEFLATE + base64, to local modules src/client/DevAssets/City_<id>*.luau
  (git-ignored). `Shared.Utilities.Inflate` decodes raw DEFLATE in Luau (tested against zlib; a
  chunk inflates in about 0.04 s). `TownRenderer` puts each chunk on a flat part between the ground
  and the roads; the placeholder town discs go clear when the art is drawn.
- Roads now use the city painter's widths and colours (major 1.56 cells asphalt #4d5357, minor 0.92
  cells #70777a; APPROX: rank 2+ = major) so they fill the gaps the town art leaves for them.
- Trees: `tools/conversion/export_trees.cjs` runs the game's own tree placement (loaded from the
  local install, nothing copied) for a map: forests (denser and bigger deep inside), scattered trees
  on plains and hills, a bushy fringe round forests, and the town yard trees. Saddle: 13,110 trees,
  12,445 kept after the game's load-time clearing (town, urban and road cells). pack_city.py draws
  them into the same chunks from trees-top.png at the forest layer's scale (0.013 cells a px), each
  with its 30% shadow shifted (0.12, 0.16) x its width, in the game's draw order. Saddle is now 24
  chunks, 4.7 MB. Not baked: the sun-angle shadow shift, day/night tint, swaying, burning, felling.
- Ground: the game bakes a "fine" ground texture on the CPU (its oUt, 3 px a cell: grass tones and
  clumps, dirt, trails, forest canopy, rock, sand and water edges, hill light and shade) that its
  ground shader then samples. `tools/conversion/export_ground.cjs` pulls that baker and everything it
  uses out of the local install's bundle at run time (acorn; nothing copied) and runs it for a map;
  `tools/asset_pipeline/pack_ground.py` stores it as Ground_<id>.luau (Saddle: 1152 x 720 px, 100 KB).
  MapRenderer draws it instead of the placeholder colours. Not reproduced: the shader's per-pixel work
  on top (animated water and foam, day/night light, fog, territory wash).
- Town light: pack_city.py now bakes the ground shader's close-up town lighting (its "towns at real
  size" pass, traced): each town pixel darkened by what the buildings round it shut out of the sky
  (aux green x 0.3), and roof shadows: every roof toward the sun shades a pixel by
  smoothstep(-soft, soft, (roof height - pixel height) x px a level - distance), soft 0.6 + 0.06 x
  distance, strength 0.58; heights from aux red (/8 = storeys); px a level from the sun as the game
  works it out (us.city shadowPx 2.8, at most 4.6). APPROX: one fixed sun, noon (shadows due south);
  the game turns the sun through a 480 s day starting at a low morning sun, and darkens at night.
- Forest floor (fixed): the first ground bake drew every forest cell as deep-water blue-black with
  stray wave specks, hidden under the trees. The baker's colour and mask tables are filled by loose
  top-level statements in the bundle (A2[...] = ..., a for loop over rh), which the extractor skipped.
  export_ground.cjs now keeps every top-level statement that fills a table it needs. On top it lays
  the shader's close-up forest floor: forest texels (fine mask 11) x (1 - 0.34 x heart), heart being
  each cell's depth into its wood (the game's ZLe then jLe: 0 at the edge, 1 five cells in), sampled
  bilinearly per texel and cut to 48 steps. The canopy colour the game blends in when zoomed far out
  is left out (trees are always drawn here). Saddle re-baked: 119 KB.
- Next: the water (shallows, foam, rivers), which Saddle barely has.

## Turrets like the game (2026-11-10)
- The sim now has turrets, traced from the game (r7e / Tie): a unit with turretDegSec (tank 70, IFV 80),
  not at sea, not air, not garrisoned, turns its turret at that rate towards what it shoots at and holds
  fire until it is within movement.drive.turretOnDeg (4) of the aim; its reload keeps counting meanwhile.
  Not shooting, the turret turns to the enemy its standing hull faces (steer.face, within sight x 1.25),
  else back over the hull. The hull no longer has to face the target for a tank to fire.
- The unit row carries the turret angle (index 16); UnitRenderer draws the turret layer at its own
  facing and eases it after the sim's at the game's turretFollowPerSec (20 a second).
- Gameplay effect: a tank caught from behind now pauses up to about 2.5 s before its first shot. The
  bot-vs-bot check run (d5r) now ends "winner 1" instead of "winner 2".
- Test: "a tank turns its turret at turretDegSec ..." (150 pass). Studio: B84.

## Unit rims, shadows and glow like the game (2026-11-10)
- Traced from the game's unit drawer (S9 with ree, kke, xke and Of). Under every sprite unit, bottom to
  top: a glow in the side colour (1.7 sizes wide, 0.7 as deep, alpha 0.6; hidden while selected), the
  shadow (the shape row at 1/3 size, alpha 0.34, the turret's at x 0.55, moved half its reach away from
  the sun and stretched along that line by (l + reach) / l, reach = size x za.shadow.tall x the sun's
  length), the dark rim (the shape round a 3 px circle, #06080b, alpha 0.78; a 6 px one halved when the
  unit is drawn under 72 px), the body, the turret's shadow on the hull (alpha 0.42, 0.035 sizes south),
  the turret.
- pack_original.py bakes the rim, half rim, plain shape and shadow from the shape strips (new strip
  operations); docs/private/sprite_spec_fx.json lists the 15 modules (Orig*Rim, Orig*RimHalf,
  Orig*Shade), all local only. SpriteBank returns them as look.fx; UnitRenderer draws them.
- APPROX: the same fixed noon sun as the town bake (shadow 0.74 south); the game turns the sun and
  fades shadows at night. The stretch is applied after the facing's small leftover turn.
- Studio: B85. Not yet: soot on damaged vehicles, wrecks, men's shadows.

## Wrecks like the game (2026-11-10)
- The sim's "destroyed" and "convoyLost" events now carry where the unit died, its hull and turret.
  MatchService collects vehicle deaths and sends each player those it could see, with the next
  snapshot (a new last argument). UnitRenderer leaves the game's wreck there (wMe.leave, paintWrecks,
  Mke, traced): the <kind>_wreck rows (colour only), its rim and shadow (shadow reach x 0.75), held
  120 s then faded over 25 s, at most 48, hidden under fog. The turret is spun by up to 0.8 rad and slid
  back up to 0.08 x cells, from the game's kc hash of the spot (src/shared/Utilities/Hash.luau, checked
  against the game's values in a test). A tank may lose its turret in a toss instead (weights per
  class: tank blast 3, cook 2, toss 2, brew 2, quiet 1): it flies 1.6-2.3 cells over 1.25-1.6 s, up
  2.8-3.8, turning 5-11 rad and flipping 1.5-2.5 times, drawn at 12 frames a second.
- Art: Orig*Wreck, Orig*WreckRim, Orig*WreckRimHalf, Orig*WreckShade (tank, truck, scout, artillery),
  local only, listed in docs/private/sprite_spec_fx.json.
- Not yet: the death looks other than the toss (blast, cook-off, brew-up fire and smoke, debris),
  soot on damaged vehicles, the crew bailing out. Studio: B86.
- Fixed: UnitRenderer stored the unit's status number in the same field as its status label, so the
  second snapshot after any unit appeared threw "attempt to index number with 'Text'" and stopped
  every later unit and all buildings from updating (the HQ truck seemed never to deploy, paratroopers
  never showed after landing).

## Image memory budget (2026-11-10)
- Studio refused the unit art ("Failed to create empty EditableImage ... memory budget limits"): the
  24 full town chunks (896 px each, about 77 MB) were made first and used up the device's image
  budget. Now the fog and unit art load before the map, and TownRenderer draws the towns from one
  small overview (2 px a cell, sampled from the chunks once) with the full chunks streaming in near
  the camera only when zoomed in (at most 9, one per 0.4 s, destroyed when off screen). If the budget
  refuses a chunk it waits 10 s and keeps the overview. SpriteBank prints a one-line summary of the
  art it loaded at start.

## More unit sprites (2026-11-10)
- tools/asset_pipeline/cut_units.py cuts a unit's rows out of the local units-top.png (colour, paint,
  shape; turret rows + 3 to + 5; wreck rows; extra state rows) into the strip layout pack_original.py
  reads. docs/private/cut_spec.json (local) lists the IFV (row 12), rocket launcher (21, raised 63 and
  66), engineer (27), demo truck (48) and HQ truck (78, setting up 84 to 93), with their wrecks.
- SpriteBank draws them (cells, art and shadow reach from the game's tables). The HQ truck's mast turns
  about its pivot (-0.1278 frames along the hull) at 0.07 turns a second while it stands (za.radarTurns).
- Vehicle looks now load when the first unit of a kind appears, to keep within the image budget.
- Deploy looks (the game's lgt, tI and Ai.stages, traced): the unit row carries a stage (index 17).
  Artillery shows set1 / set2 once raised 0.4 / 0.999 (setting up over setupSec, folding over
  packSec); rocket launchers up1 to up3 at 0.25 / 0.6 / 0.95 (raising over raiseSec on a barrage in
  range, lowering over lowerSec after it); the HQ truck command_1 to _4 by its deploy progress x 5;
  the scout's mast eases up over 1.5 s while on recon (client side, as the game), mast1 / mast2 at
  0.35 / 0.95. Art: Orig<kind>_<state> modules with their own rim and shadow, from
  docs/private/sprite_spec_states.json. Not yet: the empty rocket rack after a missile (rep_ only).

## Soot on damaged vehicles (2026-11-10)

The game blackens a hurt vehicle: soot = clamp((0.6 - hp/maxHp) / (0.6 - 0.15), 0, 1), drawn as the
paint rows of the kind's wreck look (untinted) over the body at that alpha, and the wreck turret's paint
row over the turret. The Orig*Wreck modules now carry those paint rows (OrigDemoWreck is new: the game
leaves no demo wreck but still blackens a demo truck from it). UnitRenderer adds the soot layers the first
time a vehicle drops under 60%, so healthy units never load wreck art. Re-pack the wreck modules with
docs/private/sprite_spec_fx.json; with the old modules vehicles simply stay clean.

Crews running from wrecks: the game's crew count table is empty, so only "hands" bolt from a wreck, and
hands are the engineer truck's two dismounted workers. Now done: UnitRenderer puts out the engineer
and sapper (the game's wMe.work: Ai.workers door, spots, paces) once the truck has stood at a repair,
sabotage or trench job for 0.6 s; the server sends the job's position in the unit row's aim slots when
the unit is not firing (MatchService jobAt, the game's ugt). When the truck dies they bolt (bolt /
drawCrews: Ai.crew). Figures: tools/asset_pipeline/cut_men.py, modules OrigMenCrew/Engineer/Sapper.

## Open questions
1. Rights scope: answered for the art (see Original art above). Still open: audio and voice, and
   public redistribution of extracted data (kept out of the public repo meanwhile).
2. Git is run by you (`docs/GIT_SETUP.md`), since this connection can't grant narrower delete rights.

## Vehicle death variants and particles (2026-11-10)

Implemented the generic land-vehicle death variants in Shared.Presentation.DeathEffects and
client Rendering.DeathRenderer, traced from the installed main bundle's variant selector and its
separate effects bundle (death, longDeath, wreckBlast, cookOff/cookPop/cookEnd, brewUp, quietKill,
wreckBurn, turretToss/turretThud, puff, sparks and embers). In this install the old Kv table is named
zv. Tanks, IFVs, artillery, rocket launchers, scouts, engineers and HQ trucks now have particles.

- Blast: layered fireball/flash, ring, sparks and flying debris, then an 8-second wreck burn and
  4-second smoke tail. Cook-off: a smaller initial hit, accelerating ammunition pops with occasional
  flying rounds, a final blast after its randomized delay, and continued wreck fire.
- Brew-up: a short rising flame jet with sparks and high smoke, with wreck fire starting before the
  jet ends. Quiet: dust and sparks without a blast, thinning smoke, and a chance of delayed small fire.
- IFVs and launchers use their own source weight tables (the prior wreck-only choice treated both
  as light). One selection and trajectory now drive both the wreck and the effects. The existing
  turret toss gains pillar flames, a smoke trail and a landing dust ring. At most 8 simultaneous
  cook/brew sequences; extra ones fall back to blast, as in the source.
- Effects still play when unit/wreck sprite modules are absent. Missing effect data or a refused
  EditableImage prints one warning and retains the earlier wreck-only fallback. No vehicle art is
  preloaded. The particle atlas loads on the first visible supported death: one 96x96 image (36 KiB
  raw). Quads are reused, created only for visible, on-screen particles, up to the particle cap;
  simulation, timers and expiry continue while particles are hidden. Both spawn/current particle
  positions are tested against fog. The existing stale-snapshot rejection prevents duplicate effects.

Local generation (already run for this batch):

~~~powershell
node tools/conversion/export_death_fx.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo"
~~~

The exporter requires @napi-rs/canvas to be available to Node (NODE_PATH may point at its containing
node_modules directory). It reads app.asar directly without extracting into or changing the install,
follows the effects bundle's imports to the literal configuration, and runs the game's own procedural
atlas painter in a sandbox using a local Canvas. It fails on unexpected bundle structure. Outputs:
src/shared/GameData/DeathFx.luau and src/client/DevAssets/OrigDeathFx.luau, both covered by existing
git-ignore rules. No original source, generated tables or pixels are added to tracked files.
This exporter is a separate step; generate_all.py does not invoke it.

APPROX / still pending: Roblox flat quads and continuous transparency replace the additive light,
screen-space dither/erosion and exact particle stepping. Physics uses bounded 0.05-second slices;
the fireball pop curve is approximate. The Roblox cap is 512 particles rather than the game's 4000.
Dust/debris are terrain-neutral; terrain-specific thrown clods, fragment smoke trails, scorch/crater
painting, dynamic lighting and camera shake are not ported. Turret landing lacks its extra chunks
and its special water splash. These are visual differences; the effects do not add gameplay damage.
Oil convoy losses and demolition trucks use separate routines in the source, so they retain their
existing wreck behavior here instead of receiving generic light-vehicle effects. Port those separately.

Verification actually run on Windows for this batch:
- lune run tests/run: **160 passed, 0 failed** (151 existing + 9 new checks).
- Rojo 7.4.4 build succeeded; output was written to this chat's staging folder.
- @lune/luau compiled DeathEffects, DeathRenderer, UnitRenderer and the new test module (syntax only).
- The local exporter generated the configuration/atlas; an added test decoded and checked the atlas.
- Confirmed the existing localhost:34872 server reports project RobloxianFront, version 7.4.4.
- Studio play, Script Analysis, visual parity and renderer performance have **not** been tested here.
  Existing B78-B90 remain unrun; new Studio checks B91-B94 are also unrun.

## Faster town streaming (2026-11-10)

The blurry stretch after panning came from TownRenderer loading one chunk every 0.4 s, inflating it
from scratch every time, dropping chunks the moment they left the view, and waiting 10 s after any
image-budget refusal. Now it checks every 0.1 s, keeps the compressed bytes cached, shows every chunk
whose pixels are ready (up to 6 ms a check) and inflates one new chunk a check, nearest first. When a
chunk leaves the view, its pixels are copied back out of the image and kept (up to 6 chunks), and its
image is kept for reuse (up to 2) instead of being handed back to the budget. Shown chunks stay until 1.6x
the view distance, idle checks pre-inflate the next chunk just outside the view, and a budget refusal
retries after 1.5 s. Studio test B95.

## Soldier shadows and rims (2026-11-10)

Soldier figures now draw their original shape-row shadows and near-black rims through the new
Rendering.ManEffects component. Shared.Presentation.MenShadows holds the pure projection math.
Traced from the installed bundle's soldier style table, jht/XF/Kht mask construction, iV pose-height
selector, T8 drawing and F7 shadow projection. Standing/walking/digging figures use the up height;
kneeling/planting and the set/kick mortar tube use the kneel height; prone/fallen/base use the low
height. Pose-specific lengths and the source art aspect ratio control shadow stretch.

The normal rim is 1.5 source pixels at alpha 0.78; below a drawn frame width of 0.6 x 48 pixels it
switches to the source's 3-pixel rim baked at half size. Shadows use alpha 0.34, the full shape near
the camera and a half-size shape farther away. They use the same current fixed noon sun vector as
the vehicle renderer. The shadow's stretch is applied along the sun direction before the remaining
heading rotation, using a full-frame UI container so trimmed images rotate about their original pivot.

Infantry, paratroopers, AT/mortar crews and tube, engineer/sapper workers and fleeing workers all
use the same component. The rim sits below body and paint. Shadow parts belong to the existing
figure Part, so casualty/removal/worker destruction also removes their shadows. The owning GUI's
visibility and body alpha drive shadow visibility and both effect alphas; fleeing-worker fades do
not leave opaque silhouettes behind. Missing private mask modules retain existing body/paint drawing;
a refused image allocation logs one warning per figure and retains its body.

tools/asset_pipeline/pack_men_fx.py reads the style/length tables from the read-only game install
at runtime and reads the existing local shape strips selected by the private sprite spec. It writes
MenFx.luau under src/shared/GameData and OrigMen*Fx.luau under src/client/DevAssets, all covered by
existing git-ignore rules. Every facing/mask is cropped with its pivot retained, packed with a clear
gutter into one atlas per figure. All 11 figure atlases total 8.52 MiB raw; rifleman and leader together
use about 1.97 MiB. Only the first drawn instance of a figure loads its one atlas; instances reuse it.
No vehicle preload, SpriteBank, map loading or town streaming code was changed in this batch.
Claude's concurrent faster town streaming changes and Studio test B95 were preserved.

Generation (already run for this batch; Python needs Pillow/numpy and Node on PATH):

~~~powershell
python tools/asset_pipeline/pack_men_fx.py "A:\SteamLibrary\steamapps\common\WarFront Demo" docs/private/sprite_spec.json
~~~

APPROX: the existing fixed noon sun does not turn or fade at night. Like the unit asset pipeline,
fractional mask offsets use Pillow bilinear sampling and half-size masks use BOX sampling; edge
alpha may differ slightly from the game's Canvas sampling. Body half-resolution swaps, airborne
men and their lifted shadows, blast flinches and persistent fallen bodies remain outside this batch.

Verification actually run on Windows:
- lune run tests/run: **166 passed, 0 failed**, including 6 new pose/projection/atlas checks.
- Python tests/test_men_fx.py: **2 passed**, using synthetic pixels to check rim expansion and exact
  full/half shape reconstruction across all 16 facings, including empty frames and edge pixels.
- Rojo build succeeded with the current project, including Claude's town-streaming edits. Output
  was written to this chat's staging folder; no Git operation or original-install modification ran.
- @lune/luau compiled ManEffects, MenShadows, UnitRenderer and the new Luau tests (syntax only).
- Studio visuals, Script Analysis and device image-budget/performance checks are **not run**.
  New manual tests: B96-B98. The owner's earlier "looking good" was informal feedback on the death
  effects; no individual Studio result row was marked passed on that basis.

## Admin panel (2026-11-10)

An owner-only test panel (not part of WarFront). Server: `src/server/Match/Admin.luau`. It allows
Studio, the place owner (game.CreatorId, or rank 255 in the owning group) and user ids listed in EXTRA,
and checks every command. Commands arrive as `{kind = "admin"}` intents, which MatchService handles
before Protocol.parse. `time` sets `sim.dayOffset`, which the sim's day/night (nightAmount, and so
sight at night) already used, and can freeze it. `weather` stores the weather name. `oil` sets or adds
to the sender's oil. The private state now carries `day = {phase, night}`, `weather` and `admin`.
Client: `UI/AdminPanel.luau` (Admin button or F2) and `Rendering/Atmosphere.luau`. Atmosphere darkens
and cools the view at night (a ColorCorrectionEffect; strengths picked by eye, APPROX) and draws weather
haze and streaks. Weather only changes the look: its gameplay effects (sight, reach, pace) aren't
ported. The clock face puts 06:00 at the game's day phase 0. Studio test B99.

## Republic empty missile rack (2026-11-10)

The source's mte/gte uses rep_artillery_empty for a missile-equipped artillery unit that has a defined
firedAt and a positive shotTimer. This overrides its raised/packing appearance, even while moving;
the loaded appearance returns when the authoritative timer reaches zero. A never-fired launcher is
not empty merely because its shot timer is positive. This applies to the Republic single-missile
artillery, not the Coalition rocket launcher. The existing reload jitter/veterancy timing is preserved;
there is no new client timer or fixed 40-second visual countdown.

Shared.Presentation.UnitStages computes the presentation code. MatchService uses the current unit
definition's missile.splash field, as the sim does for the missile weapon, and places the result in
the existing snapshot unit[17]: artillery 0/1/2 keep their old meaning, 3 is Republic loaded, 4/5 its
raised looks, 6 empty. Rocket, scout and HQ-truck stages retain their existing behavior and codes.
No gameplay rules, prices, damage or reload mechanics were changed.

tools/asset_pipeline/pack_missile_rack.py reads the source unit metadata and units-top-republic.png
directly from the read-only app.asar. It generates the four original looks (loaded, set1, set2, empty),
with paint, full/half rims and shadows, using the existing unit packer. The local modules are named
OrigArtillery_rep_loaded / rep_set1 / rep_set2 / rep_empty and their Rim/RimHalf/Shade counterparts.
The source-derived cells/size/artH metadata travels with each body atlas; SpriteBank.state reads it,
and UnitRenderer resizes body quads and halo when changing looks so the raised state is not stretched
to the generic howitzer's dimensions. Every state still loads only when first needed.

Missing state art retains the existing base look. If a state body fits but its optional rim/shadow
does not fit the device image budget (or its local module is missing), placeFx now hides that layer
instead of indexing a missing sheet; the body continues drawing and masks can return with a later
state that has them. Studio/device verification of those fallback paths is still required.

Generation (already run; needs Python with Pillow/numpy and Node):

~~~powershell
python tools/asset_pipeline/pack_missile_rack.py "A:\SteamLibrary\steamapps\common\WarFront Demo"
~~~

Generated art remains under git-ignored DevAssets and assets/sprites/source/original/unit_rep_artillery;
source metadata and the local packing spec are under docs/private/missile_rack_source.json and
sprite_spec_missile.json. No original rows, extracted tables or pixels are added to tracked files.
This generator is a separate step; generate_all.py does not invoke it.

Scope / APPROX inherited from earlier renderer work: other Republic unit sprites and faction-specific
wreck/soot selection are not migrated in this batch (those still use generic kind banks). Fixed-noon
shadows and the existing unit rim/half/shadow resampling approximations remain. The empty-rack
selection and its reset condition are confirmed in the source, not approximated.

Claude's concurrent Admin.luau, AdminPanel, Atmosphere, MatchService admin hooks, town streaming and
Studio test B99 are preserved. No admin permission, clock, weather or oil behavior was changed here.
The owner's report of an admin panel is context; its permission/security behavior was not tested here.

Verification actually run on Windows:
- Full lune run tests/run: **169 passed, 0 failed** (3 new presentation/atlas tests). The existing
  Republic missile sim test also now checks empty-after-firing, empty-while-moving and loaded-after-
  reload against the real simulation timer.
- Rojo build succeeded, including the current admin-panel files and final optional-mask guard.
- @lune/luau syntax compilation passed for UnitStages, MatchService, SpriteBank, UnitRenderer, new
  tests, and the current Admin/AdminPanel/Atmosphere modules. This is not Studio type checking.
- The local generator ran and all 16 generated state/mask atlases decoded in the test.
- Studio tests **B100-B102 remain not run**; no admin or visual Studio result was marked passed.

## Shared EditableImage memory budget (2026-11-10)

Owner reported a repeated EditableImage memory-budget warning loop and SpriteBank's subsequent
attempt to index nil with WritePixelsBuffer. The nil image is the documented result of a refused
device allocation, not a missing source PNG. Reference:
https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateEditableImage

Two existing policies compounded the extra sprite/mask pages: SpriteBank preloaded every soldier
role plus an infantry icon even when separate men were used, and town detail could retain nine
896px images plus two pooled images (about 35 MB raw for full-sized chunks). Cached vehicle/state,
wreck and figure pages also held their native images indefinitely after nobody used them.

New Shared.Presentation.ImageBudget (pure, injected allocator) and Rendering.ImageMemory coordinate
the rendering consumers. Each created native image is accounted for and explicitly released through
Destroy. Unit art, fog, ground and the small particle/halo images have priority over town detail.
The initial streaming policy is a 48 MiB tracked working target, 16 MiB detail allowance including
pooled images, and 8 MiB of headroom before admitting detail. These are conservative PORT POLICIES,
not claimed Roblox/device limits or original-game constants. Active core images can exceed the soft
working target; a real native refusal learns a lower conservative ceiling and prevents repeated
identical futile native calls. On a core refusal the manager reclaims all eligible detail/unused
pages and retries once only if storage was actually released.

Town reclamation drains the spare image pool first, then releases farthest detail images while
keeping the overview. SpriteBank and ManEffects can then release unused cached pages. UnitRenderer
supplies an active-Content guard covering current/base looks, masks, soot, men, mortar tube, engineer
workers, fleeing workers and wrecks including fog-hidden wrecks. Pages being retrieved for a new
view also get a one-second construction grace period. Evicting an unused page invalidates cached
wrappers so a later request reloads it safely; failed look caches may retry after storage is freed.
The guard is conservative: it does not evict a page merely because its unit is off screen.

Startup now warms just leader/rifle figures. Other crew/vehicle pages and the infantry icon fallback
load on first use. Allocation failure is checked before WritePixelsBuffer; partial failed ground
bakes and sprite loads release their allocated images rather than leaking them. Repeated SpriteBank
and figure warnings are rate-limited per asset. A client already using old cached modules/images
must be stopped and started again after Rojo sync; respawning alone does not clear those caches.

The fast town-streaming work remains: 0.1 s checks, nearest-first loading, compressed-byte and decoded
pixel caches, pre-inflation, view-distance hysteresis and image reuse. The spare native image pool
is reduced to one and counts toward the detail allowance. Detail can use 7 px/cell half-size images
when that meets the on-screen density or full-size allocation does not fit. Each half-size image uses
one quarter of the native pixel storage of its 14 px/cell source. Full source pixels are retained in
the bounded CPU cache for later upgrades; alpha-weighted filtering avoids dark transparent fringes.
Full detail upgrades when zoom/headroom allow. Unused art can also be reclaimed for those upgrades,
without evicting one visible town chunk to allocate another. Budget refusal no longer triggers a
warning every 1.5 seconds: admission suppresses known failures, with one town pressure notice.
Map teardown unregisters its reclaimer, disconnects streaming and releases overview/detail/pool images.

APPROX / limits: resolution fallback and all memory thresholds are display policies, not traced game
behavior. Raw RGBA accounting does not measure native GPU overhead. Actual limits vary by device;
one initial native warning can still occur when discovering an unknown device ceiling. A device
that cannot hold even the currently required art must keep the existing safe fallback. This fixes
allocation handling and avoidable retention; it does not raise Roblox's limit. The synthetic atlas
test board and DevFlags.ATLAS_TEST_BOARD were left untouched (reserved headroom covers unmanaged work).
No original art/data was generated or changed. Admin, clock, weather, gameplay, source install and
Git were not changed. Day/night parity remains the next feature after this memory retest.

Verification actually run on Windows:
- Final full lune run tests/run: **181 passed, 0 failed**, including 12 new allocation/reclamation,
  retry suppression, priority, cleanup, upgrade-recovery and alpha-filter tests with simulated limits.
- Rojo build succeeded after the final policy change.
- @lune/luau syntax compilation passed for all changed Luau modules and tests; not Studio type checking.
- Real-device memory pressure, live-Content retention, visual quality and camera responsiveness still
  require the owner's fresh Studio/client pass: **B103-B105 not run**. No screenshot issue is marked
  Studio-verified from unit tests alone.

## Source daylight model and moving sprite shadows (2026-11-10)

Shared.Presentation.Daylight now ports the source's clear-skirmish palette interpolation (Sqt),
sun/moon geometry (xH), night transition (Oh), sprite shadow fade (H0), and clock mapping (CW/Lqt).
The local exporter tools/conversion/export_daylight.cjs reads app.asar without changing the install,
loads the current daylight tables including active dusk/night key overrides and the before-dawn
override, and runs the original numerical functions for 21 reference phases. Output settings and
reference vectors are src/shared/GameData/Daylight.luau and DaylightVectors.luau (git-ignored).
No original functions or extracted tables are written into tracked files.

The shared client Rendering.DaylightController receives the existing server day phase through
Atmosphere.apply. Source direction and elevation determine the current shadow vector; UnitRenderer
uses it for vehicle bodies, turrets and wrecks (including tossed-turret shadow throw), and passes it
to ManEffects for infantry/crews, mortar tube, engineer workers and fleeing workers. All sprite
ground shadows fade by the source factor 1 - nightFade x night, multiplying their existing opacity
and any wreck/worker lifetime fade. Turret-on-hull shading retains its separate source behavior.
Shadow stretch now follows the current sun axis with the residual facing rotation inside it rather
than retaining the fixed-noon stretch axis. The sun/moon path resets at the source day/night boundary;
that geometric transition is intentional, not client clock extrapolation.

Atmosphere now refreshes when phase changes during daytime too, replacing its guessed fixed NIGHT
brightness/contrast/saturation/tint constants with a source-palette-derived ColorCorrectionEffect
adapter. The pure sample contains the source RGB multipliers and additive vector. The Roblox adapter
uses a common gain/offset fit plus multiplicative tint; it does not claim pixel-identical shader
output. Existing weather haze, streaks, lightning and estimated weather grading remain intact.
Roblox post-effect capability reference:
https://create.roblox.com/docs/reference/engine/classes/ColorCorrectionEffect

The admin clock had mapped 24 hours uniformly across the phase, while the source maps 06:00-18:00
onto its 62% daylight segment and 18:00-06:00 onto the remaining 38%. The panel now uses that source
mapping for display, Noon/Morning/Evening/Midnight presets and +/-1-hour controls. Dawn/Dusk are
admin UX choices derived from the middle of the source fade-out/fade-in windows, so both select
half-night transitions rather than a misleading fixed uniform hour. Server permissions, Oil,
weather handling, freeze behavior, sim time, night sight rules and unit reload timers are unchanged.
The existing day payload now retains its numeric precision instead of truncating phase/night to
three/two decimals. The sim still floors its own day clock as before, so labels can land within a
few game minutes of a preset when one real second spans several game minutes.

Generation (already run for this batch, Node only):

~~~powershell
node tools/conversion/export_daylight.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo"
~~~

This is a separate local-generation step; generate_all.py does not invoke it. Missing private
settings warn once and retain a static noon fallback. The feature creates no EditableImages,
generates no new pixel assets, and preserves the shared image-memory admission/reclamation fix.

APPROX / next: baked town roofs, ground relief and tree cast shadows still contain the existing
fixed-noon lighting. Their pixels receive global colour grading but their baked shadow direction
does not move/fade independently. Roblox ColorCorrectionEffect has a common brightness/contrast
and RGB multiplication, unlike the original per-channel additive shader and rendering passes, so
its transfer/tonemapping, per-pixel night contrast/posterization/dither, emissive lamps/reflections,
night-vision rendering and special visual themes are not ported here. Those remain needed for full
visual parity. Palette and sprite-shadow numerical calculations are confirmed for the active
clear-skirmish source settings; weather graphics still carry their existing estimates.

Verification actually run on Windows:
- Full lune run tests/run: **188 passed, 0 failed**, including 7 new numerical/clock/preset/adapter
  checks. Palette, sun, moon and night samples match the original functions at 21 reference phases
  within the tests' numerical tolerance, including phase wrap and transition points.
- Rojo build succeeded; @lune/luau compiled the changed modules and tests (syntax only).
- The local exporter generated both private modules successfully. No pixel allocation was added.
- Studio visuals, colour-transfer parity and Script Analysis are **not run**. New Studio checks
  **B106-B108** remain unrun. The owner's "looking good" on the memory batch is informal feedback;
  individual earlier memory test rows were not marked passed without their results.

## Zoom detail, roof-shadow direction and road visibility (2026-11-10)

The owner reported that town-building shadows stayed fixed while units' shadows moved, suggested
camera-dependent detail, and reported roads becoming visible only near maximum zoom without their
road textures. This batch addresses all three through the existing renderers; no simulation or
admin permissions changed. HQ/facility blocks remain the existing placeholders.

TownDetail is an APPROX screen-space rendering policy: full 14 px/cell, half 7 px/cell, quarter
3.5 px/cell and the persistent 2 px/cell overview. It transitions in both directions, with separate
enter/exit thresholds to avoid oscillation while scrolling. Larger images are released before a
downsize; upgrades still need ImageMemory headroom, and allocation refusal can fall back two levels.
The nine-chunk maximum, nearest-first loading, compressed/CPU caches, pressure reclamation and
live-unit image protection remain. These thresholds are port policy, not extracted game rules.

pack_city.py --lighting 16 generates local-only sparse XOR patches for 17 sun-path directions,
using its existing traced aux-height/sky-occlusion/roof-ray shading and identical tree compositing.
The same geometric path is reused for the source's separate sun and moon segments. All 24 noon
base chunks match the owner's existing RGBA bytes exactly; existing base art was not replaced.
TownPatch validates whole runs before mutation and reverses the previous patch in-place before
applying the next. TownRenderer rewrites the existing image, refreshing at most one nearest shown
chunk per 0.1-second check. Cached pixels retain their current patch until evicted, then reload the
known noon base. Missing/corrupt patch assets retain the last valid appearance and warn once, without
blocking other chunks. Overview sections are cleared while a detail chunk covers them, and restored
on unload; otherwise the old noon ground shadows could show through the relit transparent pixels.
408 patch modules total about 16.45 MiB of base64/module text on disk, loaded as needed; they do not
create EditableImages. Only the current decoded patch per cached chunk is retained by this renderer.
Roblox require can retain the compressed strings of previously visited patches.

APPROX: roof-shadow direction is sampled (steps are visible) rather than a continuous GPU ray walk.
The far overview, tree cast shadows and ground relief retain fixed lighting. Roof-shadow strength
retains the existing daytime bake; the source's separate city shadowNight strength (0.3 versus 0.58
day) and continuous transition are not yet ported. Global day/night colour grading still applies.

RoadRenderer/RoadPixels replace normal plain road Parts with persistent far roads composited into
the existing ground pixel buffers, plus three shared 128x128 procedural textures for close detail
(192 KiB total managed image storage). The far network no longer relies on the visibility of thin
Parts or streamed town chunks. Detail fades over the source's 3-to-9 screen-pixels/cell range; the
far network stays beneath it. Road depth stays below town/tree/roof-shadow pixels and above ground,
with highway/minor/track depth priority at overlaps. SurfaceGui.MaxDistance is explicitly unlimited.
No image is created per road segment. Road wear/cuts/repair overlays remain above these surfaces.
Missing RoadLook retains the former plain-Part fallback; every new image write checks allocation.

export_roads.cjs reads the local original bundle's road widths (ET), real-size look (Qr) and road
settings (me), writing git-ignored GameData/RoadLook.luau. Source IT confirms highway rank >=2
before the track flag, replacing the earlier unconfirmed classification for these new renderers.
Widths, colours, shoulder widths, barrier, lane/edge/dash locations and track-rut dimensions derive
from those tables. Grain uses the source hash21 arithmetic on repeating strip coordinates.
APPROX: this is a first straight-road texture pass; original world-space noise, junction distance
fields/fillets, town medians, roundabouts, crossing markings, bridge geometry, road lamps and
damage/pothole shader effects are not reproduced. It is not a claim of full road-rendering parity.
The source draws these details procedurally, rather than shipping a separate road sprite sheet.
The tree exporter also supports the current bundle's renamed functions, retaining its older path.

Generation: node tools/conversion/export_roads.cjs <original-install>. Repack towns with the same
city, map, placement JSON and tree sheet inputs as before, adding --lighting 16 to pack_city.py.
An optional --output directory allows review before replacing any local art. Private art/settings
remain git-ignored. The original install was only read.

API references: https://create.roblox.com/docs/reference/engine/classes/SurfaceGui and
https://create.roblox.com/docs/reference/engine/classes/ImageLabel (MaxDistance, TileSize/ScaleType).

Verification: nine new pure Luau checks cover hysteresis, zoom jumps, source sun/moon resets,
reversible patches, corrupt-input atomicity, road-strip seams, clipping, class precedence and
generated strip bounds/detail. Two Python checks cover RGBA XOR reconstruction and roof-shadow
direction. All 408 generated patches were structurally validated; all noon patches preserve the
original base. The generated road strips were inspected as a local PNG; Studio rendering is unrun.
Full suite/build results are recorded after installation below. New Studio checks B109-B112 are
unrun; no earlier checklist rows were marked passed from general visual feedback.

Installed-batch verification actually run:
- Full lune run tests/run: **197 passed, 0 failed**.
- Both Python city-lighting tests passed.
- Rojo build succeeded with all local lighting patches and RoadLook present.
- Changed Luau modules/tests compiled with @lune/luau; both JS exporters passed node --check.
- Source base-art comparison and all 408 patch-structure validations passed.
- Studio visuals, Script Analysis and B109-B112 remain **not run**. Fresh Play is required after sync.

## Connected roads, building visibility and smooth fog (2026-11-10)

The owner supplied screenshots of square road fringes, disconnected junctions, town-yard pixels
covering roads and trees in the road, then requested building-blocked sight, smooth fog and whole-city
visibility while garrisoned. The former road strips and coarse ground-road bake were replaced on
the generated Saddle map by one connected road raster inside the existing town chunks/overview.
No new EditableImages are used; the former three road images are no longer allocated.

road_layer.py uses the locally exported source widths/look tables, world-coordinate grain and
capsule distance fields. Crossing directions suppress kerb/lane/barrier lines across mouths.
Roads composite above gardens/streets and below roofs, then receive the same roof-shadow lighting
as the town. True fractional opacity preserves road-edge antialiasing through shading. Overview
masking prevents a second coarse road peeking beneath close detail. RoadPixels retains only the
legacy far-raster fallback for maps without integrated art; obsolete strip generation was removed.
Worker road points wrapped in {data: ...} are now decoded correctly for tree clearing. All trees,
including yard trees, are additionally omitted if their actual canopy alpha overlaps pavement.
Saddle tree count changed from 12,445 to 12,222 after the combined clearance fixes. All 24 base
chunks and 408 matching roof-lighting patches were regenerated together. Generation adds
--roads docs/private/road-look.json to pack_city.py with the existing --lighting 16 and tree inputs.
export_roads.cjs now produces that private JSON alongside its existing private Luau look table.

APPROX: road unions and crossing masks replace the original GPU fillet/junction shader. Roundabouts,
town medians, bridge structures, lamps, damage, world shader transfer and full crossing markings
remain incomplete. Canopy-overlap clearance is a requested presentation policy, beyond the source
centre-cell clearing. Art still streams at the existing 14/7/3.5/2 pixels per cell. No original
install files or Git state were modified; generated original material remains in ignored paths.

Simulation.Visibility ports source k6/hN ground-sight ray traversal with a summed-area lookup.
export_visibility.py reads the original .city townCells part (3,508 Saddle footprint cells), not
the much larger all-town-tile mask. MatchService loads the private Visibility_saddle module and
injects this into Sim. Source track-cell exemptions, visible origin/destination cells and the ray
corner tie rule are preserved. Ground sight is occluded, air/drone/flare/reveal exceptions remain,
and source grouping of nearby observers is disabled when blockers exist so a unit across a wall
cannot lose its separate sight. Already-visible cells skip redundant rays. Server Fog uses this
grid for snapshots and intel; clients never receive hidden enemy units simply because of a blur.
Ground direct fire also checks the same obstruction; artillery, air targets and rooftop troops
retain their bypass. Full attack-order navigation around a blocking building is not added here.

Per the owner's explicit rule, a live garrison bypasses roof blockers and reveals at least the
settlement radius plus every urban cell assigned to that settlement, including at night, in
addition to its normal night-scaled outside sight. Empty/dead/withdrawn garrisons lose that reveal.
The whole-urban-footprint extension is a requested rule change beyond the source's garrison circle.
Only original static settlement building footprints block sight; placeholder HQ/facility blocks
are not new blockers, and movement collision/pathing has not changed. The source's extra enclosed
small-pocket filling is not ported (APPROX mask preparation).

FogPixels approximates the source Canvas fog blur using a separable Gaussian at the traced minimum
2.4-cell feather radius. FogOverlay uses bilinear sampling in its existing image. Display pixels
and the authoritative binary visibility mask are separate, so feathered edges cannot hide visible
units or reveal an enemy through a wall. Existing fog darkness is retained. APPROX: the source's
zoom-adaptive feather, explored-terrain tones/noise, transitions and chart colouring are pending.
There is no facing-locked cone: buildings carve sectors out of surrounding ground sight.

Verification actually run:
- Full lune run tests/run: **200 passed, 0 failed**.
- Six Python pipeline tests passed (typed points, connected seams, canopy alpha, roof preservation,
  fractional opacity and prior lighting/XOR checks).
- 1,000 synthetic rays matched the original k6 function evaluated directly from the local bundle.
- Changed Luau compiled, including the near-limit Sim constructor; Rojo build succeeded.
- Regenerated town/road crops were inspected locally. Studio visuals and Script Analysis remain
  unrun. Tests B113-B116 below are new; earlier B111/B112 road architecture notes are superseded.

## Source fog colour correction (2026-11-10)

The owner compared screenshots and reported a flatter/greyer Roblox view. One confirmed mismatch
was the black fog overlay. export_fog.cjs now extracts the original N0 terrain chart, shroud colour
and opacity, explored-region colour and opacity, and feather radius to private GameData/FogLook.
FogOverlay receives the decoded terrain and remembers explored cells locally for presentation.
FogPixels.colour uses the supplied chart on unexplored ground and the distinct explored tint after
sight leaves. Premultiplied RGBA is blurred together, avoiding black fringes along clear areas.
Detection remains the separate unfiltered server-fed mask. Fog-disabled/spectator display stays
clear; missing generated look data retains the prior black-overlay fallback.

Incremental colour blur tracks changed raw pixels and refreshes only the affected bounds expanded
by the blur radius. No new EditableImages or larger image allocation were added. Local Lune timing
was about 153 ms for an initial full 384x240 rebuild and 2.8 ms for a one-cell incremental change;
these are CPU measurements, not Studio frame-rate results. Wide changes can still require a full
rebuild. Cached output was tested against full recomputation after movement and exploration.

This is the first source-colour correction, not a claim of matched overall vibrancy. Visible-area
daylight/post-processing still uses the prior APPROX Roblox adapter. Source fog murk/noise,
hatching, zoom-adaptive feather and sweep transitions remain pending. Finite Gaussian blur and
RGBA quantization approximate Canvas filtering. The screenshots differ in visible area and may
also differ in time/weather; compare matched Clear/Noon conditions before further grading changes.

Verification: full lune run tests/run **202 passed, 0 failed**; Rojo build succeeded; changed Luau
compiled. New tests cover unexplored/explored/clear colour states, unmodified detection and cached
versus fresh output. Original install was read only, and extracted settings remain git-ignored.
Studio appearance, Script Analysis and new B117 remain unrun. Restart Play after Rojo sync.

## Living-world milestone: planned scope (owner additions, 2026-11-10)

These features are PLANNED, not implemented or verified by the fog-colour batch:
1. Civilian road traffic and pedestrians, followed by evacuation/reactions to fighting.
2. Moving clouds and ground shadows.
3. Night-time city/building lights, street lamp posts and traffic lights, coordinated with the
   existing day/night clock; source placement/behaviour to be traced before implementation.
4. Visible power lines/poles. A functioning power-grid simulation remains a separate later system;
   visual power lines alone must not be presented as working electricity rules.
5. Buildings igniting from nearby explosions: burning, smoke and fire progression, with source
   ignition/damage/extinguishing behaviour traced first and unconfirmed values marked explicitly.
6. Forest ignition and spreading fires, smoke and burned vegetation. Trace source spread,
   weather interaction and end conditions before choosing gameplay rules. Bound simulation and
   particle/rendering work so many simultaneous fires cannot exhaust the client image/effect budget.

Lighting/infrastructure and fire are separate implementation batches. Preserve the owner's
building-blocked sight and whole-city garrison reveal when vegetation/building state changes.
Water integration, full colour calibration and the remaining road/building artwork stay on the
broader roadmap. No implementation-completion percentage is claimed from the stale Phase-0 matrix.

## Final milestone: cosmetic skins and microtransactions (2026-11-10)

Owner-requested roadmap addition: make cosmetic skins/monetization the LAST milestone, after
core feature parity, living-world visuals, multiplayer, performance work and release readiness.
Status: PLANNED ONLY. No purchases, pricing, products or shop UI were implemented by this update.

Planned scope:
- Cosmetic unit/vehicle skins and paint schemes; retain default appearances for every unit.
- Skin previews, a cosmetic shop, an owned-skins collection and equip/unequip controls.
- Persistent ownership/equipment and server-verified purchase/entitlement handling, with recovery
  for interrupted purchases and rejoining. Select the appropriate Roblox purchase products during
  implementation after checking the current official documentation.
- Replicate equipped cosmetics consistently for other players, retaining faction colours,
  recognisable silhouettes, damage/deploy states and visibility/fog readability.
- Keep gameplay statistics, combat capabilities and progression independent of paid cosmetics.
- Set prices, launch selection and purchase flow later; test persistence, purchase handling and
  texture-memory impact before enabling sales. Skins must fit the shared image budget.

This is a Roblox-specific addition after the faithful gameplay/visual port, not an original-game
feature being claimed as ported. It does not move ahead of the previously requested milestones.

## World lighting, territory, wet ground and original city forts (2026-11-10)

Owner requests in this batch: closer original lighting/vibrancy, source-style territory, storm
puddles drying to darker mud, and full-garrison fortifications with gates. All are first visual
passes, not a claim of exact GPU-shader parity. Existing authoritative build/combat/capture rules
remain; paid cosmetics remain the final planned milestone.

Lighting: Daylight.sample now includes the original night ground contrast gain and pivot; the
post-effect adapter composes this after the source palette transform. WorldLight adds source-based
sun-side colour wash, shade-side falloff and the day/night vignette behind the HUD/weather UI.
Its existing 192x128 managed image also carries drifting ground cloud shadows, sampled from the
source three-octave noise/threshold formula with source scale, drift, zoom cutoff and night fade.
WorldLook is extracted locally by export_world_look.cjs. Phase/camera/cloud-clock stamps throttle
uploads. APPROX: the source adds light in a ground fragment shader; this uses a blended ScreenGui
wash affecting the world view, with finite screen resolution/refresh, no source cloud cast offset,
shafts, dusk-side cooling or separate cloud-body pass. Ground-only contrast is approximated by the
existing global ColorCorrectionEffect. Exact colour transfer/tonemapping is still unverified.
Night windows, street lamps, city emissive glow/reflections and full night vision remain pending;
the supplied night-city screenshot is NOT claimed reproduced exactly by this batch.

TerritoryPixels smooths authoritative owners with the source sigma/radius and computes edge
distance, inner wash, outside border and dashed rival front using locally exported source look
settings and nation palettes. MatchService sends a separate territoryView packet: complete own
claims, currently visible enemy claims, all claims for spectators. Existing territory/build ghost
packets and server placement checks are preserved. Unseen enemy holdings are not exposed as a new
information channel. TerritoryRenderer uses one 2 px/cell managed image below fog and units.
Static building footprints suppress paint. The placeholder blue ownership discs in CityOverlay
are now hidden, leaving settlement labels and original fortifications. APPROX: cell-raster edge
gradients, fixed near-view wash, footprint-level built masking and default source nation colours
replace the original screen-pixel shader/masks and configurable palettes. Claim reveal waves,
front emissive glow and remembered enemy claims are not yet ported. Territory repaint yields after
about 3 ms and coalesces pending packets; visual updates may trail authoritative permission changes.

GroundWetness and WeatherGround add a whole-map visual wetness layer for admin Storm/Downpour.
Source weather-ground colours, darkening, two-frequency puddle noise and drying thresholds come
from WorldLook. A storm builds wetness over the original front edge duration; clearing the weather
lets puddles shrink over the source dry period (90 s), leaving mud that fades more slowly.
APPROX/user adaptation: uniform admin weather instead of moving fronts, both storm/rain saturating
the map, and residual mud lasting two dry periods (180 s). These are visual states, not new movement
penalties. Roof footprints/permanent water are excluded; roads can darken but do not receive soil
puddles. Coarse terrain/urban/road masks approximate the source fine mask. No rain-ring animation,
exact reflective film or puddle-edge glints yet. The weather image is allocated only while wet/muddy,
retries after refusal with a cooldown, and is released once dry. Repaints yield within a 3 ms budget.

FortRenderer uses the ORIGINAL gJt settlement outline/gate layout, evaluated locally by
export_forts.cjs against the port's map/match inputs plus the original .city cells. The output for
Saddle contains 23 settlement layouts, 1,267 pieces including 67 gates. pack_forts.py packs all
21 fort-wall/gate/tower/nest/tank/bag frames and their paint masks from buildings-top.png into
private OrigForts_saddle. Two shared 384x144 images are loaded on demand and released when no
fortifications are shown. Full garrisons show the original full layout; partial garrisons show the
source gate sandbags. Ownership change, empty garrisons, unknown/hidden garrison state and ruins
remove the prior display. Source rise/stagger timings fade pieces in; source zoom cutoff hides
them at a distance. Gates are placed at the original road crossings, not guessed on a circle.
Existing garrison combat bonuses stay authoritative; these visual walls do not add collision or
new visibility blockers. APPROX: simplified shadow offset versus original projected extrusion,
fade-only rise without source drop/scale animation, and removing unseen forts rather than retaining
an intel memory. Settlement sprites beyond forts (HQ/factories/etc.) remain placeholders.

Local generation: export_world_look.cjs <install>; lune run tools/conversion/export_fort_input;
export_forts.cjs <local-main-bundle> docs/private/fort-input_saddle.json <city> <private-layout.json>;
pack_forts.py <private-layout.json> <buildings-top.png> src/client/DevAssets/OrigForts_saddle.luau.
WorldLook and fort art/layout data stay git-ignored. Original install was only read. Native image
cost at maximum simultaneous use is about 3.33 MiB across territory, screen light, wet ground and
the two fort sheets, all admitted through ImageMemory. No per-fort images are allocated.

Verification actually run: full lune run tests/run **209 passed, 0 failed**; Rojo build succeeded;
changed Luau compiled; the installed fort-input exporter ran successfully. Seven new tests cover
fort states/gate bags, wetness/drying, fog-safe owner packets, night contrast parameters, territory
roof/neutral masking, bounded screen-light pixels and excluded/dry wet-ground pixels. All 21
original sprite crops were checked for visible pixels. Source gJt itself generated the layouts.
Local CPU measurements before cooperative scheduling were ~137 ms for a full two-side territory
raster, 28 ms for initial puddle noise and 21 ms for a weather repaint; these are Lune timings, not
Studio frame times. Studio appearance, Script Analysis and new B118-B122 remain unrun. Fresh Play
after Rojo sync is required. Source numerical inputs do not establish an exact visual match.

Roadmap update: first ground cloud shadows, territory presentation, wet-ground visuals and city
fortification art now exist. Civilian traffic/evacuation, cloud bodies, city/street lighting, power
lines, building ignition and forest fires remain planned. Water remains separately prepared for
integration; this batch did not overwrite WaterRenderer or its integration guide.

## Studio confirmation (2026-11-10)
The owner explicitly reported that the current batch's Studio check passed. B118-B122 are recorded
as passed (owner reported): lighting, territory, storm drying, city forts and combined image budget.
This records the owner's runtime verification; no additional automated checks or independent
Script Analysis were run for this documentation update. Earlier checklist rows retain their status.
Next feature: night-time city lighting (windows, street lamps and city glow).

## Night-time city lighting (2026-11-10)

NightLightRenderer now starts with the map. It adds warm window lights, highway glow, near-view
street/highway lamp pools and a dithered city halo, fading with the existing authoritative night
fraction. The original .city material codes determine eligible window/lamp locations; unrelated
ground does not receive random windows. Local source settings come from Nn, me, ET and active Y8.
NightLightPixels uses the source window occupancy hash and staggered real-time flicker intervals.
Freezing the admin day clock holds the daylight fade but does not freeze window activity. Zoom
controls the road/pool transition using projected pixels per cell. The source lamp presentation
is light pools, not a line of bright point dots. Physical lamp posts and traffic lights are still
future infrastructure work.

pack_night_lights.py samples the original material atlas at the source fine-grid density, traces
the map roads and creates the urban glow through the source double box blur and Bayer dithering.
Saddle has 822 candidate window/lamp texels before occupancy selection and 9,954 road/pool texels.
The four-channel field is private generated data; the original install was read only. The public
tools contain the conversion logic, not embedded artwork or extracted settings. WorldLook,
NightLights_saddle and the private input/settings JSON remain covered by existing ignore rules.

APPROX: Roblox world-space HDR alpha compositing replaces the source additive GPU shader. A
linear inverse of the existing tint/contrast adapter preserves intended emission channel ratios
numerically; actual engine blending, colour space and tone mapping require a Studio comparison.
This is not a claim of an exact visual match. The field quantizes lamp strengths and samples capsule
road geometry rather than the original complete road/junction shader. Road seeds and interpolation,
CPU hash precision, lower-resolution averaging, and at-most-two-per-second flicker repaints are
also adapters. Lights sit below forts, units and fog, so illumination does not bypass fog or change
server vision/detection. There is no new night-vision bonus. The source default has power simulation
disabled; no ownership-based blackout rule was invented. Power networks/outages, water reflections,
front emission, and further building/ground night grading are outstanding.

All native images go through ImageMemory. Full resolution uses two 576x720 pages, about 3.16 MiB
total; a refused allocation releases partial pages and falls back to one 576x360 page, about
0.79 MiB. Further refusal has a retry cooldown. The reduced resolution is retained for that session
to avoid repeated full-size probes. Native images release during full daylight and map destruction;
decoded fields stay cached for the next night. Sparse preparation/painting yields between frames,
and session epochs prevent a dawn or destroyed-map repaint from uploading to released images.

Local regeneration from the project root:

1. node tools/conversion/export_world_look.cjs "<original install>"
2. lune run tools/conversion/export_night_input
3. python tools/asset_pipeline/pack_night_lights.py "<local original saddle.city>" docs/private/night-input_saddle.json docs/private/night-look.json src/client/DevAssets/NightLights_saddle.luau

Verification actually run: full Lune suite **216 passed, 0 failed**; five Python synthetic asset
tests passed; changed Luau compiled; exporter JavaScript syntax check and Rojo build succeeded.
The generated fields decoded at their declared dimensions. Tests cover material eligibility,
occupancy/flicker, near/far road behavior, reduced-resolution coverage, empty/malformed fields,
cooperative callbacks, compensation across source day phases, urban glow and road/pool placement.
Local Lune CPU timings were about 16 ms initial inflate, 6 ms sparse preparation and 4.2 ms per
paint before cooperative yielding (140,307 active texels). These exclude Studio uploads and are
not frame-time measurements. New B123-B125 and Studio Script Analysis remain unrun. Restart Play
after Rojo sync for the new renderer.

Next: owner visual comparison of the night lights, then civilian traffic/evacuation. Cloud bodies,
traffic-light/pole/powerline infrastructure, building ignition/forest fires and separate water
integration remain on the roadmap; paid skins remain the final milestone. Claude's water files
and integration guide were preserved.

## Building-integrated window light correction (2026-11-10)

Owner Studio feedback: the first lighting pass was too dim, with visible square patches rather
than light integrated into the original buildings. The coarse 3 px/cell eligibility sampling was
the cause: it enlarged a sampled material pixel to a whole lighting texel and missed many small
window strips between sample centres. That representation has been replaced for close views.

pack_night_lights.py now retains ALL eligible pixels from the original 14 px/cell material art.
It divides these silhouettes by the original fine-cell occupancy/flicker coordinates and packs
repeated fragments into one shared atlas. NightWindowRenderer draws those fragments at their
original pixel coordinates over the buildings. Bright cores follow the window/roof-light shapes;
transparent soft halos spread out from them. NightWindows shares the source occupancy and
staggered real-time flicker with the broad layer. Original Nn.city nearFrom/nearTo values are now
exported, allowing a gradual close-view transition. Coarse windows use actual material coverage
instead of solid eligible squares and fade out as the detailed windows become available. Broad
city/road glow now uses smooth resampling. Ground and building base colours are not globally raised.

APPROX / owner-requested rendering calibration: core opacity is 0.96, halo uses a 1.1-art-pixel
Gaussian with 0.8 strength and three-pixel padding, and detailed SurfaceGui brightness has a 1.4
gain over the previous compensation. These are port rendering choices, not claimed source values.
The padded halo atlas uses filtered sampling; the full-resolution cores retain original placement.
Roblox alpha/HDR blending still differs from the source additive shader and needs visual approval.
SurfaceGui LightInfluence=0 and AlwaysOnTop=false retain world occlusion while enabling Brightness;
see https://create.roblox.com/docs/reference/engine/classes/SurfaceGui. No global bloom or physical
light objects were added. Window geometry stays below forts, troops and the existing fog layer.

Saddle now has 9,361 fine-cell fragments across the original lit material pixels, with 3,674
selected by the source occupancy hash. Its 1,102 shared shapes fit in ONE 384x420 image, about
0.62 MiB. At most 768 nearby, onscreen fragments draw, nearest first, with a deterministic tie
order and a 3 ms creation budget per update. This is a rendering cap, not a gameplay rule. The
coarse layer remains until selected detailed fragments finish creating. A refused atlas allocation
keeps the coverage fallback and retries with a cooldown; no native image is allocated per window.
The atlas releases at full daylight/map destruction. Existing broad-light fallback and private
asset ignore rules remain; original install, unrelated renderers and Claude's work were preserved.
Regenerate using the same three commands in the preceding entry.

Verification actually run: full Lune suite **219 passed, 0 failed**; **7 Python asset checks passed**;
changed Luau compiled; exporter JavaScript syntax and Rojo build passed. New regression checks
reconstruct a tiny window at its exact original pixel, preserve dark roofs, verify shared atlas
shapes/bright cores/soft halo/transparency, occupancy and independent clocks, nearest-view cap,
material coverage and suppression of coarse windows without suppressing city glow. The real
generated atlas decodes at declared dimensions and fits native image limits. Local Lune CPU
measurements were about 2.4 ms for initial occupancy selection and 1.6 ms per view selection in a
sample city view; these exclude Roblox instance creation/drawing and are not Studio frame times.
Studio recheck B123 and new B126-B127 remain pending; no exact brightness match is claimed.

## Civilian road traffic (2026-11-10)

First moving-world traffic pass: CivilianRenderer now adds the original ambient cars and pickups,
including moving town-to-town trips and parked cars on internal town streets. The source fQt
layout and mQt street scan run locally against the port's settlement positions/radii and original
.city material art. Saddle produces 40 moving cars and 22 parked cars across 23 settlements, with
five vehicle looks. The original cQt procedural baker generates all 16 facings, shaded bodies and
silhouettes; these are the actual ambient sprites, not military scout-car substitutes. Original
material, layouts, settings and reference vectors remain in existing ignored directories. No
original code is emitted by the tools; the original install is read only.

CivilianTraffic ports source polyline sampling, trip/parking cycles, pull-over offsets, opposite
travel lanes, directional facings, yielding, speed and alpha fades. Traffic density uses the source
zoom thresholds, night reduction, integrity bands and garrison multiplier. Cars flee toward their
trip endpoint when their settlement is hit, disappear there, wait through the source calm period,
and gradually return. MatchService includes lastHitAt only in the already visible/own settlement
row; unknown rows still omit that field. No hidden town damage/garrison state is sent to drive
ambient behavior. Displayed cars additionally require their own current cell to be visible, so
they do not remain moving in explored fog. Unknown/ruined settlements emit no cars.

The dedicated civilianTime packet carries actual sim.time and whether the war is advancing. This
avoids treating the opening-drop clock or total server tick count as elapsed war time. Opening
picks/flight and victory pause cars; admin day-clock freezing does not pause them. Clock jumps
resnap the trip schedule. Currently visible/own ground unit positions are traffic obstacles;
INSIDE troops are excluded. Civilian cars are decorative, unselectable, noncolliding and absent
from authoritative unit/combat/economy lists. They do not obstruct military movement or change oil.

Civilian car art uses TWO shared 704x220 EditableImages (body/shadow), about 1.18 MiB total at any
actor count. Both allocations go through ImageMemory; partial refusal releases storage and waits
before retry. Images load only for visible nearby traffic, release at far zoom/after idle and on
map destruction, and cached CPU pixels avoid repeated inflate work. No per-car image is allocated.
The quads draw below fog and military units; shadows follow the existing day/night sun controller.

APPROX: global Roblox daylight grading replaces the source ambient renderer's discrete dusk/dark
sprite variants. The visible road-cut radius is a conservative substitute for the unavailable exact
cut-cell list. Road presence is rasterized from the map; this batch does not reproduce later
bridge widening, trench detours or server road-cell edits beyond visible cut circles. A town must
have current known health before its cars appear, which is stricter than the original renderer's
canonical world state. Only actual town hits trigger retreat here; the original ambient blast hook
for nearby explosions outside a town is still outstanding. Local half-second clock extrapolation,
three-second idle image release and native allocation cooldown are port policies. This is the
car-traffic slice: pedestrians, fleeing civilians/refugee columns, animals, smoke and other ambient
systems remain planned; no audio was added. Claude's water preparation and existing lighting files
were preserved. B123/B126-B127 lighting approval remains pending, not inferred from "continue".

Local generation from the project root:

1. lune run tools/conversion/export_civilian_input
2. node tools/conversion/export_civilian_traffic.cjs "<original install>" docs/private/civilian-input_saddle.json "<local original saddle.city>"

Verification actually run: full Lune suite **227 passed, 0 failed**; changed Luau compiled and Rojo
build passed. Eight new tests cover bends/end clamps, yielding and cuts, parking/return lanes,
panic speed/endpoint fade, hidden/ruined towns, night/damage/garrison/calm density, original motion
reference agreement, and both complete sprite sheets. The original class generated independent
reference runs of 180 seconds each for normal/night/panic/blocked conditions. All sampled distance,
direction, alpha and pull-over values agree to 1e-10. Both sheets decoded at their declared size
and the generated vehicle facings were visually inspected as an atlas. Studio appearance, movement
at intersections, Script Analysis, combined memory pressure and B128-B130 remain unrun. Restart
Play after Rojo sync for the new client module and server packet fields.

Next moving-world slice: town pedestrians and civilians evacuating from fighting. Street furniture,
powerlines, cloud bodies, building ignition/forest fires and separate water integration remain on
the roadmap; paid cosmetics remain the final milestone.

## Civilian lane and queue correction (2026-11-10)

Owner feedback: cars occupied the middle of roads and accumulated there. CivilianDriving now
uses the same RoadLook widths/markings as the rendered pavement. Highway traffic uses the outer
lane on its own side of the median; minor roads/tracks use their own width. Narrow-road cars scale
slightly to fit. Standing/arrival bays are staggered, parked vehicles near mapped roads move to
the curb, and trip endpoints move clear of intersections. Lane normals blend at bends instead of
jumping across the pavement. A car can merge toward its departure lane while still stationary,
avoiding a lock after its return trip.

These are OWNER-REQUESTED APPROX behavior changes from the original small fixed lane offset:
front clearance/headway with acceleration/braking, prevention of coincident spawns, curb bay
assignment and FIFO junction reservations. An approach blocked outside the junction yields its
reservation to a clear approach; cars wait for an exit to clear before entering. Traffic uses
current known civilian poses and already filtered unit positions, never hidden enemy units.
Current-cell fog and town intel gating remain. Crossing roads are geometrically detected from
map polylines (60 junction nodes on Saddle). This is not a full road-law or traffic-light system;
routes still follow the original town-to-town polylines, and shoulder/turnaround behaviour is
approximate. RoadLook missing retains the earlier source driver. No new native images, physics
collisions, combat entities or economy rules are introduced.

Verification: eight new tests cover lane placement, following/clearance, opposing traffic,
intersection turns and starvation, staggered bays/spawn suppression, bend continuity, departure
from a returning curb bay and a unit-blocked approach yielding the junction. A ten-minute local
Saddle simulation had no car remain stuck with a drive target for over 40 seconds (parking waits
excluded). Local Lune costs were about 1 ms junction setup and 0.44 ms per fleet step, excluding
Roblox drawing and instance work; these are not Studio frame times. The original eight traffic
tests/reference vectors still pass when the upgrade is absent. Full suite **235 passed, 0 failed**;
changed Luau compiled and Rojo build passed. B131-B132 and prior pending checks require Studio.
The owner did not report B128-B130 passed; their traffic screenshot prompted this correction.

Pedestrians and town evacuation remain the next in-progress slice after this traffic fix.

## Town pedestrians and evacuation (2026-11-10)

The pedestrian slice is now installed after the owner's traffic-lane correction. The original
fQt layout provides 98 town walkers/standing civilians on Saddle; original oQt supplies road exits
at all 23 settlements. export_civilian_traffic.cjs now exports those paths and bakes the actual
ambient personA/B/C standing and two walking poses with cQt, across all 16 facings. No substitute
military men or newly invented civilian artwork was used. Original-derived art/layout/settings
and numerical references remain in the existing ignored DevAssets/GameData directories.

CivilianPeople ports the original short out-and-back strolls, sidewalk offsets, stance/stride
selection and density fades. Ordinary town pedestrians thin out with damage/garrisons and go
indoors at night. Town hits and nearby current combat start staggered groups that leave via the
source road exits, fade in, walk beyond the settlement and fade out. The original per-kind counts,
timings, speed, spread and visible fleeing cap come from the local source profile. Ruined/unknown
towns emit none. The already filtered unit snapshot now appends capped time-since-hit (field 18)
so being hit, as well as firing (existing field 15), can trigger a nearby visible evacuation. No
hidden enemy unit is sent. Both the fight trigger and each displayed person require current cell
visibility. A stale combat observation does not start a new wave.

PeopleRenderer has its own shared body/shadow pair and uses the same war clock as civilian cars.
Opening deployment/victory pause animation; the admin daylight freeze does not pause walks. Nine
poses fit in two 832x468 images, about 2.97 MiB combined, with an offline alpha-weighted half-size
416x234 pair (about 0.74 MiB) on allocation refusal. Frame/px ratios keep identical world scale.
Every allocation uses ImageMemory, releases partial failures, retains reduced resolution for the
session and retries with a cooldown. No image is created per pedestrian. Far zoom, idle scenes
and map destruction release native images; CPU pixels stay cached for reuse. Pedestrian quads are
unselectable/noncolliding and draw below fog/troops, with sun/night-dependent shadows. The vehicle
lane/spacing/junction fix remains enabled and does not share pedestrian sprite frames.

APPROX: global Roblox night grading replaces the source discrete ambient dusk/dark atlases, as
with cars. The reduced-resolution fallback, half-second clock extrapolation and three-second idle
release are port policies. Town unknown-state gating is stricter than the source canonical world.
Pedestrians are decorative and do not obstruct traffic or become combat targets; there are no
new casualty/economy rules. This implements local town fleeing, not the separate random-event
long-distance refugee-column system. That event/column system and carts remain outstanding,
alongside animals, smoke, street furniture/powerlines, cloud bodies and building/forest fires.
Paid skins remain the final milestone. Existing lighting/water work was preserved; no pending
Studio test was marked passed solely from the owner's "continue".

Regenerate with the same export_civilian_input/export_civilian_traffic commands in the earlier
traffic entry; the second command now also generates OrigCivilianPeople_saddle and richer private
reference vectors.

Verification actually run: full Lune suite **242 passed, 0 failed**; changed Luau compiled;
exporter JavaScript syntax check and Rojo build passed. Seven new tests compare ambient seed hash,
walking/standing/fading poses and town-hit/fight/ruin evacuation against independent original
class runs, plus hidden/stale combat, unknown towns, night density, wave cap/clock rewind and
complete full/half sprite sheets with matching world scale. Original runs cover 60-second walks
and 20-second evacuation scenarios; sampled model, position, heading and alpha agree to 1e-9.
The generated standing/walking atlas was visually inspected. These are CPU/data checks, not
Studio appearance or Script Analysis. New B133-B135 and lane checks B131-B132 remain pending;
restart Play after Rojo sync to load the new modules and extended unit packet.

## Side-window city lights; roof emitters removed (2026-11-10)

Owner clarification: lights should come from windows on the sides of buildings; glowing roof
patches look bad. The original .city artwork is flat roof art, so this is an explicitly requested
APPROX facade treatment rather than a claim about original wall textures or actual 3D buildings.
The packer now derives a thin projected wall rim at the south/east (lower/right) edges of raised
source roof footprints, with paired warm window panes on the outer rim. All roof material codes,
including formerly emissive even codes, are excluded from the facade, bright core and its halo.
Flat ground-level roof/terrace codes do not extrude new walls. Existing lamp pixels remain eligible.
Materials are assembled in world coordinates before edge extraction, so a roof crossing source
tile boundaries does not grow a false wall or line of windows through its interior.

Window masks and dark masonry-rim masks share one atlas. A separate dark layer keeps the facade
visible when occupancy/flicker switches a pane off. Core opacity is 0.98; the existing 1.4 brightness
gain and outward soft halo remain. The facade depth (two art pixels), paired-pane pattern/spacing,
dark neutral masonry tint, lower/right projection and glow clipping are owner-requested port
design choices, not traced source values. RGB/HDR/tone-mapping remains approximate and needs a
Studio comparison. This does not rotate the camera or convert the towns into 3D geometry.

Coarse roof windows are now entirely disabled (field R is zero); zooming out cannot restore the
old roof spots. Broad road/city emission is also excluded from fine blocks touching roof pixels.
Facade detail still follows the existing near-view fade. At far zoom the separate road/city
ambience remains, without individual window patches. The full-resolution atlas and facade masks
were checked against the actual map: 37,413 light/face fragment checks found no alpha on roofs.
That checks raster data, not the engine's filtered pixel boundaries or final Studio colour.

Saddle has 18,724 facade/light fragments using 2,258 shared frame patterns. ONE 768x600 image
costs about 1.76 MiB; a prepacked 384x300 fallback costs about 0.44 MiB. It retains identical world
position/size and texture-rectangle mapping. Reduced-resolution filtering can soften the rim.
ImageMemory admission, retry cooldown, daytime release, fog/world depth and map cleanup remain.
No image is allocated per facade. The existing 768-visible-fragment cap is retained. A bounded
nearest-first heap avoids sorting/allocating entries for every visible candidate; it produces the
same selected IDs/order as a full sort. Local Lune measurements were roughly 4-5 ms preparation
and 2.3 ms per cull, excluding engine creation/drawing; these are not Studio frame-time claims.

Verification actually run: full Lune suite **244 passed, 0 failed**; **10 Python asset checks passed**;
changed Luau compiled and Rojo build passed. Regression checks cover side-face placement, former
roof light suppression, clipped halos/facades, continuous roofs across tile seams, no edge wrap,
flat terraces, shared masks/bright cores, non-flickering wall geometry, bounded selection parity,
zero coarse-window channel and decoded full/half atlases. An offline asset-layout preview was
visually inspected; it is not a Studio screenshot. New B136-B137 and previous pending checks
remain unrun. Restart Play after Rojo sync. Existing civilian traffic/pedestrians, lighting clock,
weather, visibility and Claude's water preparation were preserved.

Regeneration uses the same pack_night_lights.py command from the night-lighting entry; local
source city/map/profile inputs and the generated module remain ignored. No original-install or
Git operations were performed.

## Refugee road columns (2026-11-10)

The separate long-distance refugee-column system is now integrated. Shared.Simulation.Refugees
ports the source tAt eight-neighbour road search, zN per-town cooldown, WN moving head/tail span,
expiry/linger and i2t truck-crawl footprint. Shelling a live town records an attempt, finds its
nearest road and chooses an outward endpoint among distant reachable road cells. A failed route
still consumes the original cooldown. A fatal hit can launch a column before the town is marked
destroyed; existing columns keep travelling independently afterward. Old columns expire on war
time. This is separate from the short local evacuation groups already implemented.

RefugeeColumn ports original Dtt/tQt formation sampling: walkers, hand carts with their accompanying
person, and occasional cars/pickups, using source appearance settings and deterministic ambient
hashes. Source counts/spread/stride and all original procedural sprite looks come from local
generation. The cart is one extra row in the existing pedestrian body/shadow pair, not new images
per cart or person. Full people/cart sheets are now 832x520 (about 3.30 MiB for both), with the
416x260 fallback (about 0.83 MiB); the existing car sheets are reused unchanged. Local walking,
vehicle lanes/queues, facade window lights and other ambient visuals remain.

OWNER-REQUESTED / APPROX adaptation: original skirmish RulesMatch has events.on=false. Public
Config.WorldLife.REFUGEE_COLUMNS defaults true to enable the lively-world visuals on shelling
without enabling all random map events. The original truck penalty remains gated by events.on,
so current skirmish columns do NOT slow oil trucks or change economy/combat. Visual-only path
selection uses a separate seeded stream, preserving combat RNG. With original map events enabled,
the source truckShare/width rule is implemented and tested. This is not an implementation of the
other random blowout/gusher/washout/airdrop event systems.

Networking deliberately sends only currently visible actors, not full routes, hidden town origins
or destinations. A fog-enabled viewer with no visibility object receives no actors. The actor
animation phase is wrapped, rather than transmitting its full route progress. Each client also
checks current fog before drawing. Visible actor rows are capped at 256 per private packet
(port policy). No client command can spawn a column. Short tangent prediction, bounded at half a
second, animates between private packets; stopped/lingering columns have zero prediction velocity.
The separate war clock pauses them during deployment/victory and keeps admin day freeze independent.
Stale actor packets stop displaying after two seconds (port policy). Near-zoom population uses a
client alpha fade instead of the source renderer's zoom-dependent re-spacing/count calculation;
this is another APPROX adapter. Model/position formation at full detail matches the source.

Local generation uses the existing two civilian export commands. export_civilian_input now includes
match refugee rules. export_civilian_traffic also writes private RefugeeLook/RefugeeVectors and the
cart row. Art, settings and route/pose references stay ignored; the original install was read only.
Simulation hooks use fields on self rather than new constructor locals, preserving the register
limit. Existing unrelated files and Claude's water preparation were preserved.

Verification actually run: full Lune suite **252 passed, 0 failed**; changed Luau compiled and Rojo
build passed. Eight new tests cover cooldown/no-route/disabled/ruined cases, span/linger/expiry,
visual-only truck gating, 15 original road-search reference cases, original person/cart/car poses,
original truck-crawl footprints, fog-safe actor data and prediction after route completion. A
simulation integration test shells a town and verifies a column appears while combat entity HP,
positions, shot timers and oil remain identical to a run without visual columns. Source pose
agreement uses 1e-9 tolerance. Cart art and full/half rectangles decode through the existing atlas
test. These are CPU/data checks, not Studio rendering or Script Analysis. B138-B140 remain unrun;
restart Play after Rojo sync for updated client/server modules and local art.

Parallel-work suggestion given to the owner: Claude can implement lamp posts/traffic lights in a
new StreetFurnitureRenderer with separate packing tools/tests and integration notes, leaving the
shared entry point, civilian renderers, Sim, MatchService and shared status docs alone until merge.

## Ambient town chimney smoke (2026-11-10)

Added original procedural puff art and chimney layout as another living-world layer. The local
exporter evaluates the installed game's pQt and fQt.draw/smoke rather than embedding original
functions or tables in tracked files. Saddle has 56 source chimney sites across 23 settlements.
Source placement chooses seeded urban cells off the road raster; it does not identify a chimney
pixel in the roof art. Roof/chimney alignment beyond that source placement remains UNCONFIRMED
until the owner compares it in Studio. No new roof geometry is claimed.

Puffs follow the source wind, staggered lifetime, sideways variation, size growth, thinning,
rotation, opacity and 12 fps animation clock. Health band and garrison reduce active chimneys;
destroyed or unknown towns emit none. Recent shelling does not suppress smoke during the street
population's calm period, matching the original draw path. Daylight fade is also source-based;
this ambient smoke disappears at night. Burning buildings and forest-fire smoke are separate,
still-pending systems. No combat, economy, collision or simulation rules changed here.

The renderer shares the civilian war clock, including deployment/victory pause and independence
from admin day freeze. It uses one 704x44 RGBA atlas (123,904 bytes, about 0.118 MiB), allocated
through ImageMemory only when visible near-zoom smoke needs it. All puffs share that image.
Allocation refusal is nil-safe with a retry delay; missing/corrupt local art skips this layer.
Native storage releases at far zoom/full night, after idle, and on map cleanup. There are no
per-puff EditableImages. APPROX adapters: flat layer above town art/below troops and fog, global
grading instead of separate source day/dusk tint sheets, checking fog at both chimney and drifting
puff centres, minimum native part size, and the existing five-second retry/three-second idle policy.

Regenerate locally from the project root:
```
lune run tools/conversion/export_smoke_input
node tools/conversion/export_chimney_smoke.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" docs/private/smoke-input_saddle.json "assets/original/warfront-demo-assets-20261110-104215/dist/cities/saddle.city"
```
The input, chimney settings/layout, original art and original pose vectors remain in ignored
docs/private, GameData and DevAssets. The install was read only. Only two integration lines were
added to CivilianRenderer; existing traffic/refugee/people behaviour and Claude's separate street
furniture/water work were preserved.

Verification: changed Luau compiles, the focused five smoke tests pass, and Rojo build passes.
Full Lune suite actually run: **257 passed, 0 failed** (five new smoke tests).
The independent source comparison covers 210 cases across day/dusk/night, healthy/damaged/critical
towns, garrison state, lifetime wraps and long-running time, with 1e-9 pose tolerance. Other checks
cover origin/puff fog, unknown/destroyed towns, off-screen culling, frozen quantized time, no state
mutation, all source sites off road in urban cells, and every atlas facing's decoded transparency.
These are CPU/data checks, not a Studio rendering or Script Analysis pass. New B141-B143 are not
run; B138-B140 also remain pending. Restart Play after Rojo sync to load the new modules and art.

## Smoke roof placement correction and lamp-post integration (2026-11-10)

Owner reported smoke coming from the wrong place. The earlier source urban-cell placement was
not enough: 48 of 56 guesses fail a one-texel raised-roof-interior margin in the actual Saddle
town art. APPROX owner correction: the exporter now reads the matching .city material atlas and
index, then anchors each guess to the nearest eligible roof-texel centre within three cells.
Eligible roofs have a full 3x3 patch of raised-roof material (226+), are urban/off-road, remain
inside the settlement's radius-plus-one box, and keep at least 0.75 cell from other emitters.
The search is deterministic. A site with no eligible position is omitted, with no empty-ground
fallback. The resulting Saddle layout has 48 roof anchors and eight omitted sites. This is a
port placement correction, not a claim that the original game has those exact chimney pixels.
Animation, art, wind, war clock and image allocation are unchanged. The independent original
draw/smoke reference still uses the original sites, so it continues to test the puff algorithm
without treating our corrected positions as original placement.

New chimney_roofs.cjs and its synthetic tests keep the placement policy separate from original
runtime extraction. The exporter now requires the .city path (see updated command above). The
roof audit and its JSON diagnostics remain ignored in GameData/docs/private, and the corrected
sprite/layout module remains ignored in DevAssets. An independent Python assembly of the city
materials checked all 48 retained origins and their full 3x3 raised-roof patch. Before/after
diagnostic crops were also inspected locally; actual Studio appearance still needs owner review.

Connected Claude's StreetFurnitureRenderer with its require/start lines in init.client and its
test module in tests/run. It uses the existing generated lamp lists for all nine maps; Saddle has
36 posts. This adds visible posts at original lamp texels. Post geometry, orientation, height,
shadow and zoom treatment are port additions. It does not add traffic signals or intersection
furniture. Existing NightLightRenderer supplies the lamp lights. Map-folder destruction handles
cleanup. No server or civilian code changes were needed for this integration.

Review also corrected the post renderer's idle allocation: it now requests its shared detail
image only for an in-view, non-fogged post and updates its idle timer only while posts are drawn.
Previously any close-zoom camera reset idle and allocated the atlas, even when no posts were in
view. The existing reclaimer, refusal retry and three-second release policy remain. Claude's
scratch files and unrelated work were preserved; nothing was committed or pushed.

Verification actually run: full Lune suite **267 passed, 0 failed** (includes all nine furniture
tests and six smoke tests); five Node synthetic roof-placement tests passed; eight existing Python
street-furniture packer tests passed. Python's initial run hit a sandbox temp-folder write denial;
rerunning with a writable staging temp directory passed. The changed Luau compiles (syntax only)
and Rojo build passes. Source smoke pose references still match to 1e-9. New B144-B146 are not run
in Studio. B141's misplaced-origin feedback is recorded as corrected pending recheck, not a pass.

## Moving cloud bodies and shared cloud/shadow field (2026-11-10)

Added the original clear-skirmish sky field above the world and below the HUD/weather overlay.
It uses the source integer-cell cloud grid with empty/half/full thickness, three noise octaves,
wind drift, camera-centred parallax, cloud colour, golden-hour lift, night thinning and zoom fade.
Clouds are translucent, not opaque scenery. The source body persists in thinner form at night;
its ground shadow fades out at full night. Weather/front simulation is not part of this batch:
the existing approximate admin rain/storm haze and streaks remain over this layer.

The existing ground cloud shadow now samples the same CloudField helper and the same presentation
clock as the sky. Added the source sun/moon-vector shadow offset, capped by its original maximum.
The two screen projections intentionally differ: cloud bodies have source sky parallax, ground
shadows sample ground coordinates with the sun offset. No second shadow overlay was added.
WorldLight owns the shared visual clock/view math. Clouds keep drifting when the admin daylight
clock is frozen and during war/deployment pauses, matching the independent source visual clock.
APPROX: wall time replaces the original per-frame hitch-clamped clock.

CloudRenderer uses one shared detail image: 256x160 (160 KiB) close up, 128x80 (40 KiB) at wider
zoom, with hysteresis around the switch. Native storage is allocated only if a painted cloud is
in view, releases at far zoom/after three cloud-free seconds/map cleanup, and yields via the shared
ImageMemory reclaimer. Allocation refusal is nil-safe with a five-second retry delay. Missing
CloudLook skips the sky and preserves the older local shadow settings. Missing daylight data skips
sky painting rather than indexing an absent palette. No cloud uses a per-object image/part.
The sky does not consume hidden units, cities or combat data; its field is independent scenery
above fog, not an additional reveal mask.

APPROX rendering adapters: source GPU noise is evaluated in CPU doubles (the GPU's 32-bit hash
can put individual cells in different places), fixed small screen images with default filtering,
sky repaints every 0.15 seconds instead of every frame, and the existing lower-resolution screen
lighting/shadow cadence remains. Shadow darkening stays a screen-wide adapter rather than the
source ground-only shader. Exact source sampling at CPU precision is tested; full GPU/Roblox image
identity is not claimed. Normal-skirmish colour is implemented; special survive/dead-mode cloud
palettes and the source night-vision tube's alternate cloud treatment remain unported.

Generate local settings and independent reference data from the project root:
```
node tools/conversion/export_clouds.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo"
```
The exporter reads the installed shader and sky-class methods at runtime. shader_reference.cjs is
a limited straight-line scalar/vector evaluator for those local shader functions; unsupported
syntax fails. CloudLook and CloudVectors stay ignored in GameData. No original shader functions,
settings tables or art were copied into public output; the original install was read only.
Existing water preparation, smoke roof anchors, civilian traffic/refugees and lamp work remain.

Verification: five focused cloud tests passed and changed Luau compiled (syntax only); Rojo build
passed. Full Lune suite actually run: **272 passed, 0 failed**, including the five new cloud tests.
Tests compare 720 evaluated source noise/density cases, 20 source-class colour/opacity cases and
308 actual extracted sky-projection pixel samples. Further checks cover source shadow direction
and cap, night/far suppression, translated wind/world coordinates and near-zoom cell caching.
Representative 1280x800-view Lune paint measurements: about 3.4 ms at 4 px/cell (128x80 image),
2.6 ms at 10 px/cell and 1.5 ms at 20 px/cell (256x160 image). These are CPU measurements on this
machine, not Studio frame-time guarantees. B147-B149 are added and not run in Studio. Restart Play
after Rojo sync. The owner's general "looking good" feedback was not recorded as a specific pass
for B144-B146; those detailed checks still need confirmation.

## Cloud camera anchoring and stronger city-light glow (2026-11-10)

Owner reported clouds moving with the camera, then requested more noticeable city-light glow.
Both are corrected in this batch. No Studio pass is inferred from the reports.

The cloud symptom had two causes: the source eye-centred parallax moves apparent cloud positions
relative to map landmarks, and the throttled ScreenGui image stayed fixed on screen between CPU
repaints. APPROX owner-requested override: runtime cloud painting now passes zero parallax, while
the original private profile and default sampler remain intact for source-reference comparison.
The image is painted over padded world bounds (1.75 times each view half-extent), then reprojected
after the camera every rendered frame using the last painted world bounds. Camera pan/zoom moves
the cached image to its map position; only elapsed wind changes its world position. Expensive
noise still repaints every 0.15 seconds. If a teleport or large zoom outruns the padded region,
the stale cache is hidden until the next paint rather than exposing an image edge.

The additional render binding is removed on map teardown/restart. Padding increases noise work,
so the existing smaller 128x80 image now persists until 18 px/cell and the larger 256x160 image
returns to small below 14 px/cell (port hysteresis policy). A local padded-view benchmark measured
about 3.5 ms at 4/10 px/cell with the small image, 4.3 ms at 20 px/cell and 3.3 ms at 32 px/cell
with the large image. These are Lune CPU samples, not Studio frame-time guarantees. The same
single-image budget/reclamation policy is retained. Padding can include offscreen cloud samples;
it does not add native images per cloud or evaluate noise every frame.

For city lights, the original side-window/lamplight cores remain on the facades and original lamp
texels. APPROX owner tuning: combine a stronger near halo with a wider soft skirt, feather the
frame boundary to transparent, and retain the exact source-roof exclusion mask. Window/lamp-fragment
emission gain rises from 1.4 to 2.4; the dark masonry colour is inversely compensated so that this
does not brighten the facade itself. Broad local city/road light emission is multiplied by 1.5.
These are visual port choices, not original-game light intensities. No global brightness, bloom
effect, new light instances or whole-map tint was added.

Repacked Saddle's existing shared window atlas: 768x732 (about 2.14 MiB), with a 384x366 fallback
(about 0.54 MiB). The new masks contain about 3.18 times the previous integrated outer-halo alpha;
this is mask energy, not a claim about final Roblox display luminance. All 37,413 actual packed
light/facade fragments were checked against the city material map: no roof pixel receives alpha,
and light-frame edges are transparent. Coarse rooftop window coverage remains zero. Window
occupancy/flicker, fog/depth ordering, facade placement and shared-image count are unchanged.
The packer contains the new halo policy, so local regeneration keeps the correction. Original
art/layout remains ignored; the original install and Claude's unrelated files were preserved.

Verification: eight focused cloud tests pass, including three new regressions for overlapping
world pixels across a pan, cached world positions across camera translation/zoom/wind, and hiding
out-of-cache edges. The original 720 shader/20 tone/308 pixel references still pass in source mode.
Eleven Python packer tests pass, including a new halo spill/transparent-edge check and existing
roof exclusion/seam checks. Changed Luau compiles and Rojo build passes. Full Lune suite actually
run: **275 passed, 0 failed**.
Manual checks B150-B152 are new and not run. Restart Play after Rojo sync for both renderer changes
and the regenerated local light atlas.

## Cloud renderer runtime correction after repeated camera feedback (2026-11-10)

Owner reported the cloud attachment problem still occurring after the prior correction. The
previous math-only tests missed a concrete renderer bug: the local pcall success flag named
painted shadowed the outer painted-view cache, so the render callback never received that cache.
The flag is now named success, and the cache is published only after a successful image write.
The old WorldLight image also still baked cloud shadows into a screen-fixed overlay; it now
renders only the intended screen-space light wash and vignette, with no cloud sampling.

CloudRenderer now owns both cloud bodies and shadows. One neutral density EditableImage supplies
two GUI layers: a tinted sky above the scene and a black shadow below the screen wash. The body
uses source colour/night/zoom strength; the shadow uses source shadow strength, daylight fade and
sun-dependent offset. Both cached labels reproject after the camera every frame and move only
with elapsed wind in world space. The sun offset is applied to the shadow label, not another
screen-fixed noise image. Two GUI labels share the same single native image; no second shadow
image is allocated. Image refusal/retry, reclamation, idle release and teardown cover both layers.

APPROX cache policy: the padded world bounds include both the sky view and the view displaced by
the shadow offset. Sampling spacing is quantized in quarter-cell increments, and the cache origin
snaps to a global lattice advected by wind. Small camera pans therefore cannot shift the sample
grid at each 0.15-second repaint. Existing small/full texture resolution and hysteresis remain.
Cloud parallax remains disabled in the runtime per the owner's request; the source-reference
projection is still retained for numerical comparisons. Source half thickness is quantized to
128/255 in the neutral image. Native filtering/tonemapping and exact final appearance still need
Studio comparison. The brighter city-light/facade work and unrelated files were preserved.

Added tests/cloud_renderer.luau, which executes the actual CloudRenderer and WorldLight module
source using Lune's loader with mocked Roblox service/image boundaries. Four targeted tests were
first run against the pre-fix renderer and all failed, including cache publication and the old
seven-argument world-light call retaining screen-fixed cloud sampling. After the correction,
five actual-renderer tests pass: paint-to-render cache publication; camera pan/zoom/wind movement
without another image write; shared body/shadow texture and night fade; image refusal/retry/
reclamation/teardown; no cloud sampling in WorldLight; and stable repaint texel-grid alignment
(some checks are combined in a single test). Another pure test covers white-mask half coverage.
These tests exercise renderer control flow, not Roblox's native GUI rasterizer.

Verification actually run: full Lune suite **281 passed, 0 failed**; changed Luau compiles; Rojo
build passes. Independent original cloud shader/colour/projection references still pass. Studio
inspection was attempted with the Windows computer-use skill, but a game-view pan test was not
completed: the UI input guard detected user activity and the subsequent capture was not a usable
Studio game view. No successful local restart or visual pass is claimed. B153-B154 remain pending.
Restart Play after sync to load the corrected renderer rather than its cached ModuleScript.

## Cloud confirmation and visual power infrastructure (2026-11-11)

Owner confirmed the repeated cloud/camera problem is now fixed after the runtime correction.
Recorded as an owner-confirmed camera-anchoring result for B153. The broader night/lifecycle/
memory checks in B154 are not inferred to have passed from that confirmation.

Added a separate PowerLineRenderer and source-derived local art/layout for Saddle. The original
power planner and BJt power drawing code were traced. Saddle's authored map has no power grid;
APPROX owner-requested presentation addition: apply only the original procedural power planning
pass to the designed Saddle map, using its map seed for the sub-seed. This yields two neutral
plant sites, 159 poles/pylons and 159 connected spans. These are source-generated placements,
not positions claimed to exist in the authored original Saddle layout. Other maps without a
generated power module remain unchanged.

This is a VISUAL layer. It adds no electrical supply, power ownership, blackout rules, capture,
repair, sabotage, extra blocking cells, combat targets or unit collisions. Existing gameplay and
city-light rules remain. Static neutral plant art terminates the lines; it is unselectable scenery.
The original default skirmish power setting is off. A later authoritative electricity batch must
connect the topology and all source rules before any live power simulation is claimed.

Steel lattice pylons, wooden poles and feed-pole variants are baked by executing the original
rectangle-drawing methods, with sixteen orientations. Neutral plant body/paint comes from the
original building sheet. One shared 768x432 atlas (about 1.27 MiB) contains all source pole art and
plant pixels; the 384x216 fallback uses about 0.32 MiB. Wire segments are GUI geometry and allocate
no EditableImages. Atlas storage is lazy, budgeted as detail, reclaimable, and released when no
sprite detail uses it or the map is destroyed. Refusal tries the smaller atlas and then backs off;
no nil writes or per-pole images. Node/plant parts are non-collidable and non-queryable.

Wire attachment points, two/three conductors, sway phases, source effect clock, zoom width/alpha,
and the sun-projected sag of wire shadows follow the original renderer. Source red pylon beacons
blink at night. Far wood wires simplify and steel towers become dots. Visible wire portions check
current fog at endpoints and segment midpoints; poles/plants require current visibility. The layer
uses the shared visual clock and fixed world positions, independent of camera panning.

APPROX rendering policies: 96 nearby node/plant views and 64 spans maximum; three milliseconds
for constructing new views per update; 0.1-second update cadence; source 16-facing baked tower art
with residual rotation; rotated GUI bars instead of Canvas strokes; translated tower sprite shadows
instead of the original height-varying tower shadow lines; stricter fog suppression; and common
daylight grading instead of the source power palette's separate stepped night-darkening. Plant
cast shadows, steam, destruction/fall/arcs and the wire highlight stroke remain unported. Power
planner reserve/terrain checks are used, but the existing baked vegetation is not rebuilt around
the newly added layout. Report visual intersections during Studio review; no unrelated map art
was silently regenerated.

Generate locally from the project root:
```
node tools/conversion/export_power_lines.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo"
python tools/asset_pipeline/pack_power_lines.py docs/private/power-art_saddle.json assets/original/warfront-demo-assets-20261110-104215/dist/tiles/buildings-top.png src/client/DevAssets/OrigPowerLines_saddle.luau
```
The exporter reads the original main/worker bundles in memory, evaluates the original planner,
geometry and drawing, and writes only ignored original-derived data/art under GameData,
DevAssets and docs/private. Original code/settings are not embedded in tracked files. The source
install was read only. The original atlas preview was inspected locally. Claude's water and street
furniture work, the cloud correction and stronger city-light halo were preserved.

Verification: six pure/data tests and two actual-renderer tests pass; changed Luau compiles and
Rojo build passes. Full Lune suite actually run: **289 passed, 0 failed**, including eight new
power presentation/renderer tests.
Wire curves were compared across every Saddle span at four wind times to captured original
drawSky output. Ground-wire shadows agree with original drawGround at three sun vectors; source
zoom width/alpha agrees at six zoom levels (1e-8 tolerance). Other checks cover valid rooted plan
topology, all atlas facings/full/half decoding, no plan mutation, real renderer startup/fog culling,
one shared atlas, full-size refusal/half fallback, reclamation, idle release and map teardown.
The renderer tests mock Roblox boundaries; native visuals and frame cost remain for Studio.
New B155-B157 are not run. Restart Play after sync for the new renderer and local art.

## Power continuity and wet-weather motion correction (2026-11-11)

Owner reported missing wire segments and lines ending in empty space, and requested sway only in
rain/storms. Removed the independently chosen 96-node/64-span limits and the shared creation timer
that could omit connections after drawing nearby poles. All visible members of the finite generated
network now participate. Plants remain visible at wire zoom; small pole anchors remain when detail
is reduced, and image-allocation refusal keeps simple anchors instead of leaving naked wire ends.

Replaced overlapping per-span SurfaceGui planes with disjoint eight-cell world tiles. Conductors
and their shadows reuse native Frames within these tiles; wires still allocate no EditableImages.
APPROX port policy: native strokes are at least one GUI pixel wide, adjacent pieces overlap by half
a stroke, and curve subdivisions reduce to two/four below 8/14 px per cell. Source attachment
coordinates and full-detail curves remain intact. Fog clipping splits at cell boundaries and keeps
visible portions of a span even if both distant endpoints are hidden. Fogged cells stay hidden.

APPROX owner override of the original always-on wind: runtime sway is enabled only for downpour
(the admin Rain setting) and storm. Clear, fog and sandstorm wires remain still. Day-only state
packets retain the last weather. The original curve sampler default still supports source-reference
comparisons; only the actual renderer supplies the owner-requested motion gate.

Verification: fourteen focused tests pass, including actual-renderer coverage for every Saddle
span and all 161 anchors, disjoint tile placement, full/half/all-refused image paths, wet/dry motion,
partial snapshots, visible midspans between hidden endpoints, reclamation and teardown. Original
wire/shadow/style references still pass. Changed Luau compiles; Rojo build passes. Full Lune suite
actually run: **295 passed, 0 failed**. Native rasterization and frame pacing still require Studio.
B158-B160 are new and not run. Restart Play after sync. B156's dry-weather sway expectation and
B157's independent cap/fill behavior are superseded by these correction checks.

## Prepared water renderer connected and lifecycle hardened (2026-11-11)

Connected Claude's prepared WaterRenderer after MapRenderer.build and added its tests to the main
runner. Missing water data and the current dry Saddle map skip the layer without resources. The
selected match map is unchanged. Existing generated Shoals/Fjords data stays local and ignored.
The source depth/swell/surf/crest/tide/river/glint formulas and coefficients are preserved; the
earlier documented GPU hash, repaint cadence and chunk-edge tide approximations still apply.

Review found that destroying a map's parent did not disconnect the water heartbeat/render callbacks
or release images, and that already-painted static far water did not update when daylight changed.
Added parent teardown with restart-safe disconnection/release, shared camera view bounds and a
quantized daylight invalidation for still water. Memory reclaim now backs off before refilling;
malformed chunks and failed image writes are disabled after one warning rather than retried forever.
APPROX CPU cache policy: discard the deterministic noise cache every ten seconds so it cannot grow
through an indefinitely long match. This changes no sampled noise values. The existing 12-image,
3 ms repaint and progressive-load policies remain. Water is still below towns/roads/fog and has no
colliders or gameplay state. New storm sea, reflections, blast ripples and dam flooding are not claimed.

Verification: ten existing water tests and six new actual-renderer tests pass. New tests cover dry/
missing maps, world chunk placement, clear land texels, streaming/eviction, far-daylight updates,
allocation refusal/retry, reclamation, parent teardown/map replacement, invalid chunks and failed
writes without warning loops. These execute the real renderer with mocked Roblox image/services
and small synthetic chunks using locally generated settings. Changed Luau compiles; Rojo build
passes. Full Lune suite actually run: **311 passed, 0 failed**. B161-B163 are new and not run; a water map must be
selected in Studio to see this layer. No water visual pass is inferred from dry Saddle tests.

## Fire source tracing and pure behavior foundation (2026-11-11)

Started the next living-world fire work. This batch is a tested behavior foundation, **not live
forest/building fires**: it is not connected to match blasts, state replication or native art.
The existing playable match remains unchanged by these new pure modules.

Traced original forest controller Ihe and house controller Ohe, separate from generic structure
destruction/wreck flames. Added export_fire_rules.cjs, which reads the installed bundle in memory
and generates ignored FireRules and forest/house reference trajectories. Original coefficient
tables, terrain definitions, motion vectors and captured outputs remain under ignored GameData;
no source tables or extracted bundle code are embedded in tracked files. Read-only original install.

ForestFire ports ignition life scaled by tree size, char stages, wind/downwind/crosswind/upwind
spread, deterministic patch dryness, water/major-road firebreaks, rare one-cell gap jumps, soft/
hard fire caps, hot wreck ignition, per-cell scars and gradual timed regrowth. Context callbacks
provide stable tree queries and future visual mutation without modifying the input map data.
HouseFire ports the bounded four-neighbor roof flood fill across cell seams, tiny-fragment rollback,
burn stages/lifetimes, wind spread with generation falloff/limit, rain acceleration and suppression,
caps, ruin marks and explicit restoration. It uses world-pixel IDs through an adapter instead of
original atlas indices. This coordinate adaptation is tested against an equivalent original atlas.

Eight focused tests pass. Four original forest trajectories cover 36 checkpoints through 1,600
seconds each, including dry/rain/firebreak/gap conditions, burn ages/lifetimes/char, ordered fates,
scar order, regrowth and exact RNG draw counts. Two original house trajectories cover fourteen
checkpoints with ordered roof pixel claims, centroids/radii, generations, stages, ruin marks and
RNG counts. Other tests cover signed hashes, caps/duplicates, immutable inputs, water barriers,
hot-source expiry, seam claims/max/min pixel budgets, forbidden roots, restoration and reset.
All comparison tolerances are 1e-8 or exact IDs/counts. Changed Luau compiles; Rojo build passes.
Full Lune suite actually run: **319 passed, 0 failed**. The repository's existing GameData ignore
rule covers all three generated modules. A Git check-ignore probe was unavailable in this tool
environment (reported no work tree), so ignore coverage was checked against the read .gitignore;
no Git settings, index, commits or branches were changed.

Next fire integration work: source weapon blast ignition/felling, dynamic char/ruin/tree artwork,
source flame/smoke/light emission with a shared particle budget, settlement rebuild gates, original
regrowth visuals, fog-safe authoritative triggers/state and visibility/blocker updates where needed.
Nuclear/windthrow/crushing and field fires are not implemented by this foundation. No new fire
Studio check is marked ready while no live integration exists. Existing B158-B163 remain pending.

## Source fire blast response and char-pixel foundation (2026-11-11)

Extended the pure fire foundation with common weapon blast responses. Forest blasts follow the
source's scaled splinter/fell/ignite rings, stump/fall shares, fall angles and hot-wreck/razed heat.
House blasts follow source ignition chance, bounded radial roof sampling, first-hit treatment and
one/two-house early exit. Bullets/flares retain their zero-ignition source behavior. No live blast
event or fire rendering is connected yet, and no extra gameplay damage is invented.

Added FirePixels.house: original per-pixel soot/char/ruin colors, remaining wall/floor material
heights and source hash IDs. A repacked city must provide the ORIGINAL atlas pixel ID through an
adapter to preserve that pattern. Source-derived palettes/salts stay in ignored FireRules. Factored
the generic original To/Ui hash into Hash.seed; ambient Do mapping remains mathematically identical.
Fixed the new forest/pixel modules' dependency loading for both Roblox ModuleScripts and Lune.

Verification: twelve focused fire tests pass, including 168 original forest weapon cases, 168
original house weapon cases and 384 original soot/ruin pixel samples, byte for byte. Existing long
forest/house trajectories and RNG counts still match. Added an actual module-loader check for the
Roblox dependency branch. Full Lune suite actually run: **323 passed, 0 failed**; Rojo build passes.
Original art/coefficients/reference output remain local/ignored; no Git mutation or original-install
write. Native char/ruin painting, tree replacement, flames/smoke/lights, settlement rebuild gates
and fog-safe live triggers/state are still required before fires appear in the playable match.

## Real city-to-fire adapter prepared (2026-11-11)

Added pure FireMap and a read-only export_fire_map.cjs pipeline. It evaluates the original worker
for map identity/rigs, reads the matching original .city file and emits ignored source atlas/index/
cell data and the original oil-site no-fire reservation. The adapter maps world roof texels to
ORIGINAL atlas pixel IDs and RGBA, so HouseFire can find actual connected roofs and FirePixels can
retain the original char pattern after the port repacks towns into map chunks.

Saddle has 11,008 source tiles. Its no-fire mask reserves 1,134 cells around the source rig pads.
Atlas storage is split into seventeen compressed 512 KiB raw pages instead of a single large
ModuleScript literal (APPROX port storage policy). Decoding is explicitly requested by a caller;
this batch does not load it during the live match and allocates no EditableImages. A future loaded
sampler needs about 9.2 MB of decoded CPU buffers, separate from native image memory; dispose its
owning session on teardown. Only static map data is exposed by this adapter, no hidden live state.

Four focused tests pass: swapped tile coordinates/bounds/malformed storage; ordered/complete page
validation; 1,200 original coordinate/RGBA samples and rig reservations; and actual connected roof
claims using generated Saddle data, compared to original Ohe.claim. These exercise the real city
mapping rather than only a synthetic identity atlas. Existing house/forest behavior is unchanged.
Changed Luau compiles; Rojo build passes. Full Lune suite actually run: **327 passed, 0 failed**. Fires remain
unwired: native painting/tree replacement, bounded flames/smoke/light, rebuild gates, live triggers
and fog-safe state integration are still required. No fire Studio pass or live feature is claimed.

## Source fire emission requests prepared (2026-11-11)

Added pure FireEffects, traced against original Ihe.draw/Ohe.draw. It requests flame particles,
smoke puffs and embers with source lifetime/size/rise, age-dependent catching/dying intensity,
per-source and total emission rates, roof-pixel house origins, zoom minimum sizes/ember thresholds,
and night-vision flame palette substitution. Source appearance tables are generated privately as
FireEffectsRules; the public module holds formulas only. It accepts visibility/view and roof-point
callbacks, and leaves offscreen/hidden sources' cosmetic accumulators alone.

APPROX port policy: one combined 512-command emission cap per frame, for future routing into the
existing shared bounded particle pool. Source per-actor catch-up caps and discarded overdue bursts
are retained. Cosmetic RNG can be supplied independently from authoritative fire progression;
original draw-reference comparisons use the same supplied stream at the emission-request boundary.
This batch does not yet connect the native particle atlas/pool, lighting, map paint or live events.

Three focused tests pass: thirty-two original combined emission frames across four frame deltas,
four zooms and both normal/night-vision palettes, including exact RNG counts and retained actor
accumulators; combined 200-tree/32-house hitch stress staying at the request cap without a delayed
burst; and hidden-source suppression without cosmetic RNG consumption. Changed Luau compiles.
Full Lune suite actually run: **330 passed, 0 failed**; Rojo build passes. Native visual/cost checks are still
pending live integration; no Studio result is claimed.

## Source house reconstruction gates prepared (2026-11-11)

HouseFire now includes original Ohe.rebuildShells timing: wait for the ruin age threshold, require
no nearby active house fire, then for a town require the source quiet period since last hit and
its next reconstruction slot. Slot spacing comes from the town's integrity deficit, original
full-rebuild duration and count of its remaining ruins, clamped to source min/max. Lone buildings
use the longer source delay. The check cadence, pending timers and reset behavior are ported.
Source B4t was traced: this gate checks quiet time, not ownership or garrison. Context callbacks
provide town membership, live integrity/hit time, game time and the already-exported settlement
rebuild rules. Restoration still delegates actual artwork to a future adapter.

Two new tests pass, including four original reconstruction trajectories with 36 checkpoints,
ordered restored IDs/times, remaining ruins and per-town next slots under quiet/recent-hit/nearby-
fire/lone conditions. Existing house blast/claim/burn/spread/restoration tests still pass. Changed
Luau compiles; Rojo build passes. Full Lune suite actually run: **332 passed, 0 failed**. Live native fire,
char/ruin painting, forest art replacement and fog-safe trigger/state integration remain pending.

## Native house char/ruin renderer prepared (2026-11-11)

Added FireScorch and FireScorchRenderer. The prepared API accepts world roof-pixel stage changes
and restoration, uses FireMap's original atlas IDs/RGBA, and paints only those pixels into disjoint
eight-cell image tiles. Other pixels stay transparent over existing town art. TownRenderer.sample
exposes its already-decoded, currently shaded CPU pixels without allocating images; the char layer
uses that baked shade rather than displaying raw bright source colors. Restoring a stage removes
the overlay and exposes the unchanged underlying town image.

APPROX renderer policies: 24 nearest tiles, two new small images per 0.2-second update, shared
detail priority with five-second refusal/reclaim backoff, and a scalar town-shade estimate. At
current source resolution each full tile is 112x112 (~49 KiB), rather than one image per house.
Collapsed-height shadows/sky occlusion are not recomputed; absent cached town pixels use unshaded
source color until available. Only currently visible changed roof texels paint. Native memory
pressure can temporarily omit this detail while the base map remains. The static city sampler is
decoded lazily, over yielding source pages, only after a visible patch exists. Wholly hidden or
empty views allocate nothing. Teardown cancels pending publication, disconnects and releases images.

Corrected the initial quad height during review: town detail's top face is .105 studs above ground,
so the char part now centres at .12 (top .125), above it. Source roof filtering keeps it off unrelated
ground. Missing/malformed local source, failed page decode or paint skip only this layer and avoid
warning loops. No selectable/colliding objects or gameplay changes were introduced.

Six focused tests pass: tile seam/world-pixel identities; real Saddle roof/noise/shade painting and
clear non-roof texels; actual renderer lazy startup/unchanged-image reuse/restoration; individual
fog clipping and no hidden-source decode; native refusal/retry/reclamation; parent teardown while
loads are pending; and failed paint/missing data isolation (some checks combined). Tests mock native
Roblox image/services and do not prove native appearance. Changed Luau compiles; Rojo build passes.
Full Lune suite actually run: **338 passed, 0 failed**. The renderer is **not yet started in init**: live
fire triggers/state and the shared flame/smoke renderer still need to connect as one coherent batch.
No live char/fire feature or Studio pass is claimed by this preparation.

## Shared native fire particle bridge prepared (2026-11-11)

DeathEffects now accepts source flame/puff/ember requests into its existing 512-particle pool;
DeathRenderer exposes that bridge using the same 96x96 native atlas already used for vehicle
deaths. Added the original generic ember primitive and exact fire puff request flags. A local
map/session tag permits removing its world particles without removing unrelated death particles.
Cleared native views are hidden immediately, and an empty tagged pool drops its Parts. The small
shared core atlas remains available for later vehicle effects; no per-fire image is introduced.

Fixed an existing refusal path during integration: DeathRenderer formerly marked loading as tried
forever after one failed allocation. It now backs off five seconds and retries; one warning remains
until a successful load, while missing local data disables this layer without a warning loop.
Hidden requests are refused before allocation, and rendering still checks both birth and current
particle positions, including smoke crossing a fog boundary. APPROX port CPU/storage cap: skip
ember work beyond remaining particle capacity as well as bounding the stored pool. Existing flat
quad rendering, continuous alpha/tint and approximate particle physics remain as documented for
death effects; this does not claim original additive/erosion shader parity or new ground lighting.

Added a read-only export_fire_particles.cjs for six original puff/ember primitive reference cases;
generated output stays ignored. Five new tests pass: original primitive spawn fields; one shared
cap/tag cleanup/input immutability; actual native-renderer atlas sharing and view cleanup; refusal/
write failure/retry behavior; and hidden births/drifting plumes/missing data. Nine existing death
effect tests still pass, including vehicle death variants, long-effects budget and cleanup.
Changed Luau compiles; Rojo build passes. Full Lune suite actually run: **343 passed, 0 failed**. Live fire
state still needs to connect the prepared progression, char layer and this bridge from the match.


## Live authoritative house fires connected (2026-11-11)

HouseWorld now runs the prepared source roof-fire controller on the server, at its fixed quarter-
second cadence on the simulation clock. Ordinary ground hits, salvo/missile landings and artillery-
base barrages report their weapon and impact point once. Non-foot vehicle deaths also provide the
source hot-wreck ignition request. House fires catch, spread over connected roof pixels, change
through soot/char/ruin stages and rebuild on the original quiet-time/town pacing rules. Opening
picks/flight and victory stop progression because the simulation clock stops. The day-clock Freeze
button still freezes the sun only. Rain/Storm suppress spreading and accelerate burnout.

The fire-map exporter now evaluates the original nearest-town membership function with the
original runtime settlement centres and separately exported scaled RulesMatch radii. Its ignored
Uint16 town map and 2,000 original sample references let the server link each roof shell to the live
settlement's integrity/last-hit time. No original atlas pages were changed by this batch. Public
conversion scripts contain extraction/adaptation logic; original pixels, tables and references stay
under ignored GameData. Only Saddle has the prepared source house-fire city data at this checkpoint;
other maps keep their existing view until matching fire data is generated.

MatchService sends per-player visible fire actors and visible changed roof texels over the existing
reliable state event. Hidden changes are withheld, including hidden rebuilding; cached roof state
is refreshed when visible again. New visible actors send their roof-point buffer once. Transport
budgets (port policies, not source gameplay) are 2,048 char texels and 16 KiB of new roof points per
state update. Only sent entries become known, so excess work retries on later updates. Reset epochs
clear old client actors/char. Current full actor lists remove actors that leave visibility. Buffers
use the native RemoteEvent transport; native bandwidth/latency has not been measured.

HouseFireRenderer is now started in init and feeds the shared native DeathRenderer atlas/pool via
FireEffects. Flames originate at the source roof pixels; smoke uses the source house centre. The
prepared FireScorchRenderer is now live. Birth/current-position fog checks still apply to shared
particles. A separate cosmetic RNG preserves server progression. Map teardown disconnects this
controller, clears its tagged particles and destroys its char layer. No second particle step was
added: UnitRenderer remains the shared pool's sole per-frame step caller.

The owner/Studio admin panel has **Ignite view centre** (pan closely onto a roof) and **Rebuild fire
damage**. The server checks ownership, finite map coordinates, missing local data and opening/victory
state; ordinary clients cannot ignite/reset the world with those commands. These are port testing
tools, not player abilities. Reset restores fire roof damage only; it does not repair combat HP.

APPROX/remaining: source random behavior is authoritative here but uses a separate map-seeded stream;
admin rain covers the whole map instead of original spatial fronts. Existing direct projectiles
follow live targets; a missing target uses the recorded launch aim. Wreck heat starts at the death
event rather than the source visual sequence's possible delay. Source visual-only ground scarring,
razed-structure/demolition/mine/other unsupported blast subtypes, dynamic collapsed-height shadows/
LOS, ruined-window light suppression and source fire light pools remain pending. Existing native
alpha quads/particle physics are not additive/erosion shader parity. Char uses the already documented
near-tile/image budget and current-visibility gate; paused particles already emitted into the shared
pool retain its existing real-time lifetime behavior. No electricity or new combat damage rules
were enabled by the roof-fire presentation layer.

Validation actually run: **356 passed, 0 failed** in the full Lune suite; changed Luau compiles (syntax
only); `rojo build default.project.json` succeeds. Thirteen new tests cover direct/rocket impact
routing; compact packet bounds; fixed clocks/rain; visibility transitions/hidden restoration;
transport overflow retry; reset epochs; client phase/age/input immutability; actual renderer emission,
fog/pause/teardown and missing-data replacement; admin authority/bounds; original town decoding.
Existing original house/forest trajectories, char and shared particle tests remain passing. Native
Roblox services are mocked in renderer tests. **Studio B164-B168 have not been run.**

## Live forest fires and reversible tree damage connected (2026-11-11)

ForestWorld now advances the original forest controller on the server's fixed quarter-second war
clock. The existing common ground-impact/wreck callback feeds both roof and forest controllers.
Tree ignition, wind/dryness spread, rain suppression, source caps, splinter/fallen/stump fates,
burnout and staged regrowth use the already verified original rules. Source rank-2-and-up sampled
road cells form firebreaks; deep/shallow/river terrain also stops spread. The complete Saddle road
mask matches an evaluation of the original G4 function. This is visual world state, with no invented
unit damage, tree collision, forest cover or pathing changes.

The local tree-damage exporter evaluates the game's own standing/fallen/stump/burnt atlas builder
and tree-pose function. No original procedural functions or color tables are embedded in public
scripts. Its PNG, settings and reference outputs stay in ignored docs/private; packed data/art stays
in ignored GameData and DevAssets. The same build-only @napi-rs/canvas dependency used by the existing
particle exporter was installed only in the isolated Codex staging folder for this conversion.

The packer retains exactly the current road/canopy clearance result: **12,222 trees**, with original
quantized root positions, source keys, sizes and cell-query insertion order. It preserves the old
baked draw alignment. The source artist's damaged shapes and char palette become 218 resized CPU
sprite families, **300,488 raw sprite bytes**, in one ignored page. Original pose checks cover 60
standing/charred/fallen/stump/burnt cases; 2,000 generated samples check tree-record storage. The
server decodes tree records only; sprite pixels decode lazily on the client after visible damage.

New tree-free town/road chunks and their matching roof-lighting patches support replacing canopies,
not drawing fire over permanently green art. All **432 existing town/base-lighting modules** produced
by this conversion match the installed versions byte for byte and were not replaced. The existing
City metadata changed only to reference Forest_saddle. The 432 new tree-free base/light modules,
three Forest data/reference modules and private conversion inputs are ignored original-derived
art/data. Public source, tests and conversion logic remain separate from those generated outputs.

TownRenderer recomposes an affected chunk over its tree-free city/road layer, with original-style
layer order: fallen/stumps, upright shadows, then canopies/burned branches. Roads/buildings beneath
removed foliage and overlapping surviving trees remain. Reset/regrowth restores intact trees. The
same native chunk images are rewritten; the far overview's cached pixels also update, including
when detail images are refused or reclaimed. Untouched chunks retain the existing fast static path.
At most one dirty chunk repaints per 0.1-second check. Missing art/failed repaint is isolated and
warns once; existing art remains. Teardown removes the map's CPU-state callbacks/references.

Forest state uses visibility-filtered per-player deltas, capped at 512 tree fates per update, with
unsent changes retried. Float64 source keys preserve large values; fates/char and float32 fall angle
use 14 bytes per row. Visible active actors carry age/life/rate, using public map-tree positions on
the client. Hidden fate changes and regrowth are withheld until seen. Source sight uses the original
cell, before subpixel root quantization. Reset epochs discard stale state. Trees and houses now use
one combined FireEffects emitter/request budget and the existing shared native death-particle atlas
and 512-particle pool; no new tree/fire EditableImage is allocated.

Added a presentation **viewReady** handshake after both client listeners attach. Map loading can
outlast early state events; fire deltas now wait for readiness, and the first readiness signal resets
only that player's cached fog/cities/territory/wear/fire view. This also permits spectators to receive
fresh visual state after loading. Repeated readiness messages do not force repeated full resends or
grant gameplay/admin privileges. The native late-join scenario still needs B173; mocked renderer and
pure cache tests do not prove Roblox event delivery.

Admin now offers **Ignite roofs**, **Ignite trees**, and **Rebuild fire damage**, all at the view centre.
The reset clears both roof and tree fire damage. Server ownership, opening/victory and finite-map
coordinate checks remain; ordinary players cannot issue those testing actions. The earlier house-
only tests now skip generated-data cases correctly when private fire data is absent from a clone.

APPROX/remaining: the existing 14px/cell bake, CPU alpha rounding (observed maximum 2/255 channel
variance against five intact baked chunks), resized sprite/fall resampling and fixed tree shadows
replace continuous GPU drawing, wind/gusts and lighting. Forest progression uses a separate map-
seeded RNG stream and map-wide admin rain rather than original shared visual RNG/spatial fronts.
One changed chunk per check bounds repaint work but may delay a large multi-chunk update. No native
CPU, bandwidth or GPU benchmark is claimed. Original grass-only/wild/nuclear/windthrow/crushing
paths, leaf/splinter debris, fire light pools and ground scorch remain pending. Dynamic collapsed-
roof height/LOS, ruined-window light suppression, and roof-char ordering under overlapping canopies
also need further integration. Unsupported blast subtypes listed in the house-fire entry remain
pending. Existing native alpha/particle physics and real-time lifetime of already emitted paused
particles retain their documented approximations. Only Saddle has this full generated forest/tree-
free data at this checkpoint. Other maps keep their existing baked views without it.

Regeneration uses existing exported map/tree JSON and source .city/sheet inputs. First evaluate:
`node tools/conversion/export_tree_damage.cjs <install> <trees-top.png> docs/private <map.json>`.
Then run pack_city with its existing trees/sheet/map/roads/lighting arguments plus
`--forest-damage docs/private/tree-damage.json --forest-data src/shared/GameData`. Its ordinary
non-forest output path remains supported. Generated data must remain ignored.

Validation actually run on installed files: **370 Lune tests passed, 0 failed**; **9 Python tests
passed** (new deterministic packing/bounds tests plus existing city-lighting and road tests); changed
Luau compiles (syntax only), Node exporter syntax checks pass, and `rojo build` succeeds. New checks
cover bounded forest packets; fixed clocks/rain; hidden updates/restoration and retry; client epochs/
phase/age; canopy removal/overlap/regrowth; original tree records/poses/road barriers; approximate
bake parity; actual combined emitter; admin authority; and actual TownRenderer repaint, overview,
lighting, image reuse/refusal, missing-art isolation and teardown. Roblox services/images are mocked
in native-renderer tests. **Studio B169-B173 have not been run.**

## Power network visible through fog of war (2026-11-11)

Owner-requested APPROX override: the static power-line network, including its poles/pylons and
neutral plant anchors, now remains visible in both unexplored and currently fogged cells. Fog no
longer removes nodes or conductor sections. Its mask selects rendering depth only: revealed art
keeps its original .22/.225 map-layer heights below unit sprites, while fogged art draws above the
fog overlay's .40 top face. Per-cell runs still use disjoint tiled GUI canvases, including mixed
fog/revealed cells inside one tile. The existing camera/zoom culling and image-budget fallbacks stay.

Lifted art is reprojected along the same camera rays as its original plane, so its screen placement
and scale match the revealed portions. A camera-position render callback updates only raised
surfaces and disconnects with the map. This prevents a new perspective offset at fog boundaries
and keeps the network attached to map locations during pan/zoom. It adds no EditableImages. Wires
still sway only in Rain/Storm; this visual change does not reveal enemy units or other hidden state.
Earlier power fog-clipping expectations in B156/B160 are superseded by B174.

Verified on installed files: **371 Lune tests passed, 0 failed**; changed Luau compiles (syntax only);
Rojo build passes. Actual renderer tests now cover wholly fogged networks, fog/reveal transitions,
full spans through mixed/alternating cells, ordinary unit-layer ordering, shared atlas refusal/
reclamation/idle release, existing weather behavior, camera-ray alignment through pan/zoom, and
projection cleanup. Native services are mocked. **Studio B174 has not been run.**

## Visual power network removed at owner's request (2026-11-11)

Removed PowerLineRenderer from client initialization: its require, map-start call and weather hook
are no longer present. New Play sessions therefore create no power wires, poles, pylons or neutral
power-station models, and allocate no power atlas or power-renderer update callbacks. This removal
supersedes the previous power visibility/fog-color requests and B155-B160/B174's enabled-network
expectations. Existing renderer/converter files and ignored source data are dormant; they were not
deleted. Lamp posts, city lights and the other world layers keep their existing startup hooks.

Verification actually run: the changed client entry point compiles (syntax only), startup-source
inspection finds no power renderer references, and Rojo build succeeds. No new tests were added or
full-suite pass claimed for this three-line wiring removal. **Studio B175 has not been run.** A new
Play session is required to discard power objects created by the previous running client.

## Live forest and house fire glow (2026-11-11)

Burning trees and roofs now feed the original grouped ground-light behavior through the existing
combined fire controller. Nearby actors share light pools. Group selection, stable tie order, caps,
refresh timers, height attenuation, timed rise/flicker/fade, Bayer distance lookup, overlap, soft knee
and night-vision gains are traced from the original forest/house models and effect/light layers.
The new exporter evaluates those functions from the owner's installed game at runtime and writes
only git-ignored FireLightRules/FireLightVectors; it embeds no original functions or tables publicly.
Generated coefficients/reference data are local only. Regenerate from the project root with:
`node tools/conversion/export_fire_lighting.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" .`

Native FireLightRenderer paints the combined pools on disjoint world-aligned 16-cell tiles below
fog and units, with source adaptive texel resolution/zoom cutoff. Sources and illuminated texels
are visibility-filtered; hidden source removal also hides the previous cached texture immediately.
Images use the shared detail budget, admit at most two per 0.1-second check, yield under pressure,
and back off five seconds after refusal/reclaim. No visible fire/night glow means no native images.
Missing local light settings skip glow alone. Epoch reset/rebuild/map teardown clear light state,
images and callbacks. Night vision is forwarded from the existing controller. Fire light ages use
the paused/running war-clock delta rather than wall time; no second death-particle step was added.

APPROX: native HDR alpha and inverse post-effect compensation replace the original CSS color-dodge
blend, so exact native color/intensity still requires Studio comparison. Rendering uses tiled
images, a 3ms repaint budget and progressive admission instead of the original full-canvas draw;
dense fire views may take longer to refresh. The quarter-second grouping check is client frame-
sampled from the existing replicated actor views, with independent cosmetic RNG and previously
documented bounded interpolation. Light centers plus texels are fog-filtered, stricter than the
original center-only light admission. Source daylight suppression/refresh behavior remains: changing
to night can wait for the next group refresh rather than instantly creating every light. This adds
fire glow only; ground burn scorch, ruined-window suppression and remaining fire paths are pending.
The owner-requested power-network removal remains in place.

Verified on installed files: **381 Lune tests passed, 0 failed**; changed/new Luau compiles (syntax
only); exporter syntax and generation pass; Rojo build passes. New tests compare original grouping,
refresh schedules, burn envelopes and six complete raster frames, and cover tile phase/seams,
fog clipping, actual native-controller wiring, anchored views, zoom/NV, war pause, reset, image
refusal/reclaim/retry, optional settings and cleanup. Native services/images are mocked; no native
frame-rate or visual parity result is claimed. **Studio B176-B177 have not been run.**

## Ground scorch after roof and forest fires (2026-11-11)

Actual roof/tree burnout now feeds a shared authoritative ground-scar model through the existing
once-per-source-cell callbacks. The original burn raster's wind direction, stretched/wobbled shape,
overlapping stain accumulation, float32 state, fade-to-settle behavior and quiet-town recovery are
ported. Rural stains remain at their settled strength; no automatic rural ground regrowth is
invented. Settlement catchments use the original normalized-distance rule and live last-hit quiet
time. Admin Rebuild fire damage resets the shared ground epoch along with roofs/trees; it grants no
HP repair. New source settings/references are generated locally by
`node tools/conversion/export_ground_scorch.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" .`.
Only ignored GroundScorchRules/Vector modules contain extracted coefficients/reference results.

Transport sends at most 1024 changed cell/strength records (5 KiB) per ready viewer's private state.
Hidden creation and restoration stay server-side until visible; unsent overflow retries. Late joins
and view-ready resets receive current visible stains. Client epochs reject older updates. Optional
data failure disables ground scorch only, leaving fire damage and other match systems available.
There are no unit damage, movement, territory or terrain-type changes in this feature.

The native layer uses world-aligned, disjoint 32-cell images below city roofs/canopies, roads,
weather and fog, reusing images as strengths change. It allocates nothing for absent/hidden/offscreen
stains, admits two images per check, rotates up to eight tile repaints per 0.2-second check with a
3ms CPU budget, and yields/retries shared detail after five seconds under image pressure. Reset and
map cleanup release images and callbacks. Source cell tint/darken is retained, with 8-bit transport/
native alpha rounding replacing continuous source values. Existing baked city pavement and road
art can cover these lower ground stains; full dynamic urban-surface staining remains pending. This
layer ordering intentionally avoids darkening intact roof/tree sprites. No native visual result is
claimed for the alpha/color-space or batch latency. Fixed one-second war-clock updates replace the
source wall-clock scheduler/hitch cap. Engineer ground repair/structure grading, snow behavior,
craters/rubble/wreck/rust/nuclear scorch kinds and other blast types remain pending. The new model
accepts fire burns only; explosion-triggered fire can eventually leave a burn stain on burnout.

Verified on installed files: **395 Lune tests passed, 0 failed**, changed/new Luau compiles (syntax
only), original-data exporter generation/syntax pass, and Rojo build passes. Fourteen added tests
cover nine original burn/overlap/fade/heal scenes, original town catchments, rural persistence,
fog/late-join/restoration, bounded retry and epochs, clock pause/quiet time, tint/transactional
validation, actual renderer anchoring/reuse/culling/refusal/reclaim/cleanup, actual burnout callbacks
and owner-only shared reset. Native services are mocked. **Studio B178-B179 have not been run.**

## Fire damage and projected window lighting (2026-11-11)

The owner's projected side facades/windows now consult the existing visible roof-fire state.
Active fire actors suppress related fragments even before the first soot stage; lasting roof
char/ruins keep them suppressed after the flames end. Source restoration or fire reset brings them
back. The shared mask consumes the same accepted, fog-filtered pixel/actor packets as roof painting;
older epochs cannot restore stale lights. Teardown clears the mask. No new original art, extracted
data, native images, server packets or gameplay permissions are added by this batch.

APPROX: projected south/east facades remain an owner-requested port addition, not original game
geometry. Reverse projection conservatively checks the roof pixels that could produce each wall
fragment, including across source-tile boundaries. If a shared fragment includes panes from two
nearby roofs, a damaged parent can hide some intact neighboring panes or a mixed lamp fragment
until restoration. Fragment-level suppression replaces per-pixel facade material regeneration.
The source fire model's burning/char/ruin states and restore timing remain unchanged. Broad urban
ambient glow and street-lamp fields are unchanged; current generated coarse roof-window fields
are already zero. Exact source night-shader parity is not claimed for these added facades.

Empty masks bypass geometry checks. Damage revisions preserve a cached fragment decision across
camera updates and unchanged snapshots; intact candidates fill the nearest-visible cap before
rendering. Existing atlas images are reused on extinguish/rebuild. Fire light pools moved to a
distinct .23 ground-layer height below city emission (.24) and side windows (.245), fixing a
coplanar canvas conflict found during integration review. This supersedes the fire-glow layer's
previous .245 placement without changing source grouping/curve/raster coefficients.

Verified on installed files: **402 Lune tests passed, 0 failed**; changed/new Luau compiles (syntax
only); Rojo build passes. Seven new checks cover burning/lasting damage/restore masks, unchanged
revision caching, cross-cell facade provenance, intact-fragment cap selection, actual side-window
removal/recreation with the same atlas, deferred city-light mask forwarding and actual house-fire
epochs/cleanup. Existing fire-light native tests verify the separated pool plane. Native services
are mocked. **Studio B180-B181 have not been run.**

## Tree foreground above damaged roofs (2026-11-11)

Roof-char tiles now reuse the current forest compositor's foreground instead of painting over
overlapping canopies. Opaque trees retain their color over every roof char/ruin stage; translucent
canopy edges and tree shadows composite over the damaged roof. The existing town-shade scalar is
estimated after removing that known foreground contribution, avoiding double-darkening the roof.
Tree burning/felling/regrowth changes invalidate affected foreground regions; source restoration
removes the char overlay normally. Fog still gates the complete changed roof pixel.

No extra EditableImages, original art, server state or gameplay changes are introduced. The town
renderer keeps at most 24 CPU-only cover regions, matching the roof-char renderer's view cap, and
clears them on teardown. Unrelated tree changes preserve cached regions. Missing/corrupt local tree
cover warns once, disables this optional cover adapter and keeps the existing town/char behavior.

APPROX: the existing 14px/cell raster, fixed tree shadows and resized sprite/CPU alpha differences
remain. Foreground-aware shade recovery is still a scalar, rather than the original full dynamic
town shader; existing bake/resampling differences can shift edge colors slightly. Cover generation
adds CPU work after relevant tree fates change, but no native memory. Collapsed-height shadows/LOS
and full urban ground-scar composition remain pending. Native visual/performance parity is untested.

Verified on installed files: **408 Lune tests passed, 0 failed**, changed Luau compiles (syntax only),
and Rojo build passes. Six added checks cover opaque/partial/empty foreground, fog and dimensions,
actual CPU cache reuse/fate invalidation/eviction/cleanup, once-only missing-art isolation and actual
roof-char image reuse while foreground changes. **Studio B182-B183 have not been run.**

## Town ground surfaces retain fire scorch (2026-11-11)

Ground-scar state now also repaints the matching tree-free town bake before forest sprites are
composited. Courtyards and opaque town ground can show the source burn tint rather than hiding
the lower ground-scar plane. Original roof pixels are excluded and keep their separate char/ruin
treatment; tree crowns/shadows remain above scars. The original pixel alpha is preserved. Near
detail and far overview both update, and restoring/resetting starts from the clean original bake,
so recoloring cannot accumulate through relighting or image reuse.

This reuses the existing lazy CPU FireMap sampler for exact source roof exclusion, with no second
atlas decode or extra native images. Ground state retries the town bridge until the sampler is
ready. A failed native char image does not discard the CPU roof map. Reset epochs, map replacement
and teardown clear town ground state. The existing one-dirty-chunk-per-check policy, original
visibility-filtered scar packets and terrain-plane image-budget behavior are unchanged.

APPROX/limits: the existing 14px/cell alpha/color-space, source-shade sampling and overview
resampling remain; town rebuilding may lag under many changed chunks. This bridge requires a
matching dynamic forest/tree-free bake and source roof map, currently complete on Saddle. Other
maps or missing optional data keep the lower ground-plane fallback. Native road overlays can still
cover road scorch; full road-surface and original material-shader parity remain pending. This
supersedes the initial ground-scar entry's opaque town-pavement limitation where this bridge is
available. No terrain gameplay, new art, extra server fields or new purchase features are added.

Verified on installed files: **413 Lune tests passed, 0 failed**; changed/new Luau compiles (syntax
only); Rojo build passes. Five added checks cover source tint/roof exclusion/alpha, chunk boundary
mapping, actual town ground/overview restoration with relighting and image reclaim, delayed sampler
retry/epoch clearing, and one-time lazy roof-map sharing without native allocation. Existing
failure tests verify CPU map availability after native char-write failure. Native services are
mocked. **Studio B184-B185 have not been run.**

## Mine, demolition and razed-structure fire triggers (2026-11-11)

Additional authoritative match events now reach the existing house/forest fire models using the
original effect hooks. Mine detonations and destroyed minefields use the source shell-hit effect
settings, rather than inventing an ignition radius from combat splash damage. A demolition truck
feeds its original primary missile-type impact and visual blast size. Destroyed player structures
feed the original razed heat size, including the larger HQ scale. Rig loss, unit death, cancelled
construction and voluntary building recycling do not duplicate these extra hooks; existing vehicle
wreck heat remains on its prior path. Combat damage, production/refunds and targeting are unchanged.

Structure destruction now records category and cell-centre position in its event before the dead
entity is compacted. MatchService therefore does not depend on a removed entity to find the fire
origin. All direct/event fire impacts share the original water guard: open deep/shallow/river
impacts produce no land fire hooks, while a live road/bridge on that cell receives a ground impact.
Invalid/out-of-map positions or non-finite sizes are ignored. Fire state remains authoritative and
its existing visibility-filtered packets/native budgets are unchanged.

The new exporter resolves source effect imports, evaluates razed/demolition hook methods and the
original water predicate, and writes only ignored FireImpactRules/FireImpactVectors:
`node tools/conversion/export_fire_impacts.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" .`.
Absent/invalid optional impact settings skip extra event hooks while retaining guarded direct
weapon hits. Malformed settings warn once on startup. No original functions or tables are embedded
in public output, and no new native images are allocated.

APPROX/remaining: event hooks run on authoritative simulation time using existing independent fire
RNG, rather than the source client's visibility-gated visual RNG. The demolition truck's later
secondary shell pops, full collapse/demolition effects and immediate crater/rubble/ruin ground
scorch are not included in this batch. Existing immediate wreck-heat timing remains approximate.
Fire burnout can still create the previously ported burn scars; no new terrain damage is claimed.

Verified on installed files: **421 Lune tests passed, 0 failed**; changed/new Luau including Sim
compiles (syntax only); exporter generation/syntax and Rojo build pass. Eight new checks cover
actual post-compaction destruction metadata, original razed/demolition callbacks and eight water/
bridge cases, mine settings, duplicate exclusions, shared water gating and invalid/missing optional
data. **Studio B186-B187 have not been run.**

## Delayed demolition fire impacts (2026-11-11)

Demolition-truck fire ignition now includes the original delayed secondary shell impacts. The
exporter reads the source pop count, delay range, radial range/reach and weapon, and executes the
original pop loop to generate private position/timing references. Each landing checks water and
bridge state separately: a water-covered blast centre can still have a secondary land impact, and
an individual water pop does not ignite land. Pending impacts are consumed once and allocate no
native images or new server-to-client fields.

The queue advances on the authoritative war clock before the house/forest fire tick. Match pause
holds its timers; admin sun freeze alone does not. Rebuild fire damage clears pending fire impacts
along with the other fire state so they do not re-ignite repaired ground after that reset. Owner
authorization remains unchanged. Older primary-only generated profiles still work without the pop
extension; malformed pop settings disable the optional event hooks safely. Regenerate with the
existing `export_fire_impacts.cjs` command to include this extension.

APPROX: an independent map-seeded presentation RNG and authoritative war time replace the original
visual RNG/timers. Reference comparisons use the same source draw stream for the pop geometry,
not the source's complete particle draw order. These are fire-model impacts; full demolition
explosion/secondary-pop visuals, sounds, collapse particles and immediate crater/rubble/ruin
scorch remain pending. Existing combat damage is unchanged and is not applied again by this queue.
This supersedes the prior impact batch's missing-secondary-ignition limitation.

Verified on installed files: **426 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only); updated exporter generation/syntax and Rojo build pass. Five new checks cover original pop
positions/delays and exact-once consumption, war pause/reset, independent landing-surface gating,
owner-only queue reset, malformed data and legacy primary-only compatibility.
**Studio B188-B189 have not been run.**

## Fire runtime correction and persistent ruins (2026-11-11)

Owner reported a repeated NightWindowRenderer Color3 multiplication error, fire stutter and
unwanted automatic rebuilding. Window colors now scale channels explicitly instead of multiplying
a Color3 by a number. The renderer also cleans partially created instances and disconnects the
optional window layer after an unexpected failure, warning once instead of throwing every frame.
The regression mock rejects Color3 arithmetic, matching the reported Studio boundary that Lune's
Color3 arithmetic support had masked.

OWNER OVERRIDE: live HouseWorld disables automatic rebuilding after roof burnout. Burned map
buildings retain their char/ruins past both original rebuild timers until the owner explicitly uses
Rebuild fire damage (or starts a fresh world). The pure source model retains opt-in/default original
timer behavior for reference tests. This supersedes earlier automatic roof rebuild expectations;
forest regrowth, ground stain recovery and structure combat HP/engineer repairs are unchanged.

Fire char no longer rebuilds buckets for identical/empty deltas or repaints static tiles every
check. Bounded CPU results invalidate on actual damage, town appearance or fog changes. At most two
dirty roof tiles paint per 0.2-second check with a time check between tiles; oldest invalid results
refresh first so continuously changing fog/light does not starve more distant tiles. Existing
images remain while their refresh is queued. The nearest 24 tile CPU results are retained (about
1.2 MB at the current scale), using the existing native image admission/reclaim policy.

Town forest/scar updates compose once at current lighting instead of composing then immediately
relighting the whole chunk. Up to two immutable tree-free CPU bases are cached (about 6.4 MB for
two full 896-square chunks). Raster blend and fire light loops no longer allocate temporary RGB
tables per affected pixel. No new native images, network fields or extracted source data were
added. Power lines and power stations remain disabled.

A local Lune microbenchmark checked identical forest blend output for all 256 alpha values, then
measured three runs of 200,000 blends: prior loop 0.317 s, scalar loop 0.049 s (84.7% lower time).
This is not a Studio FPS result. Dense scenes still update progressively; native fire stutter,
memory and visual quality require B190-B192. Stop Play and start Play again after sync to reload
required modules and connections.

Verified on installed files: **431 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only) and Rojo build passes. Five added regressions cover real window cleanup/strict colors,
persistent live ruins/manual reset, unchanged roof paint reuse, bounded fair refresh under repeated
lighting changes and single-compose clean town base reuse. **Studio B190-B192 have not been run.**

## Explosion craters and collapsed-structure ground marks (2026-11-11)

Ground impact presentation now includes the source crater footprint (earth floor, charred rim and
scattered thrown earth) and rubble footprint (mixed ash/burn tones). Each cell follows the original
strongest-impulse tone selection, Float32 strength/settlement accumulation, fade and quiet-town
ground recovery. These are flat ground marks, not terrain deformation, physical debris or restored
buildings. The owner override keeping burned map buildings ruined remains active; stain recovery
does not rebuild roofs or restore combat HP.

The common authoritative impact callback now feeds the ground model as well as house/forest
ignition. Cannon/rocket/shell/mortar/salvo/bomb/barrage/tbm and normal missile impacts use their
original individual scorch radius/strength, independent of combat splash radius. Mines use the
existing source shell impact. Demolition trucks select their dedicated source primary crater
profile, and each delayed shell pop uses its own landing/profile. Razed structures use source
rubble strength and the existing scaled collapse reach, including HQ scaling. Bullets, flares,
unknown weapons, excluded recycle/cancel events and unsupported wreck marks add no new stains.
The existing open-water/road-bridge guard runs before all of these callbacks; air-hit exclusions
are unchanged. No combat damage or terrain/pathing rules are added.

Fog-filtered scorch packets carry an optional one-byte tone aligned with each existing row. The
1024-cell cap remains: at most 5 KiB rows plus 1 KiB tones per snapshot. Tone-only changes are
withheld while hidden and sent on reveal, reset clears them, and malformed tone buffers/palette
indices are rejected before mutating client state. Old packets without tones remain burn-colored;
old local profiles without palette/impact data retain the fire-burn layer and skip the new marks.
Town and lower-ground images reuse their existing allocation/reclaim policy. Matching town ground
is tinted below roofs and canopy; tone-only changes invalidate it even at unchanged strength.
No extra native image or particle atlas is allocated by this extension.

`export_ground_scorch.cjs` now evaluates 18 additional original mixed crater/rubble/burn overlap
scenes and exports the original palette, persistence shares, weapon scorch settings and guarded
collapse/demo hook profiles. It reads app.asar without modifying the original installation; its
generated settings/reference tables remain in ignored GameData. Regenerate locally with:
`node tools/conversion/export_ground_scorch.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" .`

APPROX/remaining: authoritative visibility-filtered persistence replaces the source client's
presentation-gated impulses; existing native alpha/8-bit strength, one-second fading clock and
progressive town/ground refresh remain. Opaque road overlays can still cover marks. Full collapse
and demolition particles/sounds, wreck/hulk/rust, ruin/scour/nuclear footprints and construction/
engineer ground restoration are not included. This supersedes the prior missing immediate crater
and razed-rubble mark limitation only. Power lines/stations remain removed; paid cosmetics remain
the final milestone.

Verified on installed files: **439 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only), exporter generation/JavaScript syntax and Rojo build pass. Eight added checks cover all 18
mixed reference scenes, hidden tone-only updates/deletions, atomic malformed transport rejection,
per-weapon/legacy behavior, the actual MatchService callback (primary/demo/HQ/delayed pops/water),
matching town/plane colors, town tone-only repaint with canopy preservation and native tile image
reuse/reset. Native appearance/frame time still requires Studio. **B193-B195 have not been run.**

## Transient structure-collapse particles (2026-11-11)

Combat-destroyed player structures now produce the source outward dust ring, delayed dust wall,
falling rubble, short flames/embers and lingering smoke, with the source larger HQ scale. The
requests share DeathRenderer's existing atlas, physics and 512-particle pool; no new native image
or per-collapse atlas is allocated. This concerns player-structure destruction; ordinary roof
burnout retains its separate persistent char/ruin system. Combat HP, existing authoritative fire
ignition and crater/rubble ground marks are not applied a second time by these cosmetic effects.

The optional seventh snapshot payload contains at most 32 transient structure losses. Events are
filtered by each side's current sight, sent only after client view readiness and cleared after the
snapshot. Late joins/reveals do not replay old collapses. Unit losses, rigs, minefields, voluntary
recycle and cancellation do not enter this collapse sequence. Client rows validate finite map
coordinates/IDs, deduplicate IDs/ticks and apply the snapshot's fog before new births. Continued
emission checks source visibility and camera reach; shared particles also check their own fog cells.

APPROX port budgets cap eight active sequences, 128 delayed dust requests and 96 requests per
check. A hitch advances at most 0.1 s rather than emitting a large catch-up burst. Independent
cosmetic RNG, real-time sequence aging, fixed camera padding and existing native alpha/particle
physics replace the source full visual scheduler/culling/shaders. Sound, collapse light/shake,
demolition-specific effects and convoy deaths remain pending. These limits can omit particles in
busy scenes. Map cleanup disconnects callbacks/cancels delayed requests and clears only this map's
shared-pool tag; the existing Rebuild fire damage reset also clears transient collapse effects.
Missing/malformed optional settings or a failing effect disable this layer once without a repeated
frame error; other match layers continue.

`node tools/conversion/export_collapse_fx.cjs "A:\SteamLibrary\steamapps\common\WarFront Demo" .`
reads the original razed/burner routines and generates ignored CollapseFx/CollapseVectors only.
Four reference sequences cover factory/HQ and two seeded draw streams, comparing each request
through the complete smoke lifetime. No original functions, art or coefficient tables are embedded
in the public output; the original installation is read-only. Power infrastructure remains removed
and paid skins remain the last milestone.

Verified on installed files: **450 Lune tests passed, 0 failed**; changed/new Luau compiles (syntax
only), exporter JavaScript syntax/generation and Rojo build pass. Eleven new regressions cover
original particle requests, queue bounds/exclusions/validation, hidden emission aging, shared pool
caps/hitches, optional data rejection, actual server snapshot visibility/readiness/exact-once
delivery, actual client fog order, renderer laziness/tick deduplication/reset/teardown/culling and
once-only failures. **Studio B196-B198 have not been run.**

## Town detail coverage under fire and image pressure (2026-11-11)

Owner screenshots show a blurry town overview beside sharp chunks, then a broadly blurry city
with many player structures/labels. The screenshots alone do not establish the exact native cause.
Code inspection identified two independent contributors: continuous forest/ground dirty chunks
returned before the streaming pass every check, and full-resolution admission for individual
chunks could exhaust the shared detail allowance before the selected view had coverage.

TownRenderer now reserves alternating streaming turns while nearby detail is missing, retaining
the one full CPU decode/composition per pass policy. With no missing nearby detail, dirty repaint
continues normally. Selected chunks choose an affordable common native stride from the existing
zoom tier and aggregate image allowance; nine full 896-square chunks would exceed the existing
16 MiB detail limit, so the planner chooses a smaller shared tier before those allocations. Own
replaceable images are credited while still preserving core reserve, other consumers, detail cap
and any learned native ceiling. Unused overscan/spare native images yield when needed. Oversized
images are reduced before missing coverage, and missing chunks load before shade-only refreshes.
No native memory limits are raised; no original data/art changed. The bounded CPU pixel cache,
cooperative reclaim/backoff and minimum-resolution overview fallback remain.

This is a first coverage correction, not a guarantee that all map detail stays full-resolution.
Native refusal, exceptionally low headroom, finite upload bandwidth, the selected nine-chunk cap
and rapid camera travel can still expose the overview. The new read-only ImageMemory headroom
query performs no allocation or reclamation itself. Priority and budget behavior are APPROX port
rendering policy, not original gameplay rules. Existing fire ruins/collapse effects remain active.

### Next proposed rendering/readability milestone (not implemented by this batch)

- A shared versioned image-upload scheduler across fog/towns/fire/weather, with fair aging,
  visible-coverage priority, coalesced writes and map-session cancellation. Roblox documents that
  only one displayed EditableImage updates per frame and that EditableImages have strict client
  memory limits: https://create.roblox.com/docs/reference/engine/classes/EditableImage . Repeated
  writes across many independent renderers therefore need native profiling and shared scheduling.
- Benchmark smaller independently streamed tiles, ready-to-use CPU LODs, camera-direction prefetch
  and retaining an old valid view while replacements prepare. Evaluate published static base-map
  image assets with dynamic overlays, rather than putting all static art in runtime editable images.
  These are architecture candidates, not a claim that an upload queue or new tile pipeline exists.
- Replace placeholder player-building blocks with traced original structure art and proper
  construction/damage/faction/shadow states. Add zoom-dependent labels, selection/hover priority,
  overlap avoidance and grouped distant markers, preserving fog filtering and selection behavior.
  The owner has requested ideas; the exact artwork/layout should be compared with the source.
- Measure visible detail coverage, oldest pending upload, image bytes and frame times in the
  reported scene, including fires, many unit types and crowded buildings. Native evidence should
  choose the architecture, rather than assuming that preloading everything fixes device limits.

The owner also requested a current full roadmap. Prioritize this rendering/readability work,
remaining original art/destruction effects (including an audit for separate crater sprites),
living-world/environment completion, gameplay parity audit, original UI/audio, multiplayer/session
flows and native release testing. Paid cosmetic skins stay LAST. Power lines/stations stay removed.
Stale early "Next" and placeholder comments are not evidence that their now-tested gameplay
systems are still absent; use current modules/tests before assigning remaining scope.

Verified on installed files: **454 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only) and Rojo build passes. Four new regressions cover aggregate nine-chunk LOD selection,
reserve-aware replacement headroom without native probes, continuous fire dirtiness versus missing
detail and equal affordable detail across two actual renderer chunks. **B199-B200 are not run.**

## Shared displayed-image upload scheduler (2026-11-11)

Owner selected blurry map/detail loading as the priority over building labels. Repeated live
image writes now share one client RenderStepped lane: town arrivals/updates and overview regions,
fog, cloud masks, fire glow, roof char, ground scars, water bands, wet ground, territory, world
wash and city-light pages. This follows Roblox's documented single displayed EditableImage update
per frame. Existing first-time static atlas and bootstrap ground/overview writes remain synchronous;
the scheduler is not a replacement for every image-loading path.

Priority favors fog and first town coverage, then terrain/damage, then ambient effects. Pending
images age from their first request, including when continuously replaced, so lower-priority
effects cannot be postponed forever. Full updates coalesce to the latest snapshot; independent
partial regions remain ordered and batch only for the same selected image. A new full snapshot
supersedes older partial history. Copied pixel buffers prevent subsequent CPU mutations from
changing an already queued frame.

APPROX port limits: 64 pending images (four slots reserved from ordinary admission), 16 MiB queued
CPU snapshots plus a 4 MiB critical reserve, 64 regions/image, and at most 32 writes / 4 MiB for one
image each render turn. Producers retry or coalesce under backpressure. These are CPU-queue limits,
not increased native image budgets. Memory.release cancels pending work before destroying storage;
pooled town images also cancel pending writes before reuse. Idle upload callbacks disconnect.
An individual write failure drops that image's queued batch and reports once while other images
continue. Metadata-sensitive cloud projection and fire-light signatures commit with actual writes.

New town images stay unbound while waiting. The current overview remains visible until the
detail write succeeds; only then is its part published and the corresponding overview region
queued for masking. Later coalesced writes preserve the publication callback. Map cleanup cannot
resurrect unpublished parts. Native reclamation/resizing can still briefly expose the fallback;
the queue does not guarantee that every replacement is seamless on a real device.

ImageMemory.uploadStats() exposes queued images/bytes, oldest wait and submit/coalesce/complete/
reject/failure counts for native profiling. This batch changes scheduling only: source art,
simulation, visibility authority, persistent ruins and removed power infrastructure are preserved.
Smaller map tiles, camera-predicted loading and static published base-map assets remain separate
work. No Studio FPS, screenshot comparison or elimination of all blur is claimed.

Verified: **465 Lune tests passed, 0 failed**; changed Luau compiles (syntax only) and Rojo build
passes. Eleven added regressions cover snapshot ownership/coalescing, fairness under perpetual
foreground updates, single-image/partial batch bounds, ordered full/partial replacement, critical
reserve/backpressure, cancellation/reuse/reentrancy/failure isolation, the actual ImageMemory
render-step adapter and actual town deferred publication/cleanup. **B201-B203 have not been run.**

## Camera-rectangle coverage and bounded town source retention (2026-11-11)

The native candidate selection now follows the actual ground-view rectangle before overscan,
rather than a large circular area capped at nine chunks. Up to 32 visible candidates can share
the same native image allowance at an affordable common LOD. The native byte limits are unchanged;
an oversized view can still exceed the candidate cap or available memory. Camera motion predicts
0.35 s ahead, clamped to one view radius, and prioritizes CPU prefetch in that direction. Four
overscan candidates retain the existing reuse opportunity; no native images are created solely
for predicted prefetch. These are APPROX rendering policies, independent of game rules.

Broader coarse views do not pin full 896-square CPU sources for every shown tile. The existing
six-entry spare CPU cache now includes coarse shown chunks, preserving their smaller displayed
pixel buffers for lighting/roof sampling. Eviction retains native lighting state; a later lighting
change rehydrates/composes a fresh source once and updates the existing image. Native-size preview
buffers are released with their tiles. Full-resolution live source storage is bounded by the
native detail policy, with six additional full source buffers retained for reuse; the existing two
clean bare bases and roof-cover caches remain separately bounded.

TownRenderer.stats() now reports viewport/selected/ready/shown/pending counts, selected stride,
native bytes and retained full-source/preview bytes. It is a read-only diagnostic, not new UI.
Source visibility, fire progression/ruins, shared upload cancellation and native admission remain.

Actual local Saddle geometry at 1280x720/FOV30: a central height-900 view selects all 12 intersecting
chunks (the old cap admitted at most nine). Their native image payload is 9.1875 MiB at half detail,
or 2.296875 MiB at quarter detail. A height-220 central view selects four, costing 12.25 MiB full or
3.0625 MiB half. These are arithmetic/native-payload estimates, not measured Roblox allocation or
FPS. A local Lune cold 896-square source profile measured 0.106 s inflate, 0.109 s half and 0.028 s
quarter preparation; this motivates a separate optional precomputed-LOD pipeline, not a claim that
CPU cold-load stalls have been eliminated.

Verified on installed files: **468 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only) and Rojo build passes. Three new checks cover viewport priority/directional prediction,
broader bounded selection and the actual renderer loading ten coarse chunks with bounded full
CPU retention, displayed-pixel sampling, later lighting changes and cleanup. **B204-B205 not run.**

## Precomputed town detail levels and progressive camera loading (2026-11-11)

Cold half/quarter town views can now use optional precomputed LOD modules instead of inflating a
full 896-square source and downsampling it during camera travel. The new local packer reproduces
ImagePixels.half's alpha-weighted RGB, Lua rounding and odd-edge behavior exactly. It applies each
original sparse lighting patch before reduction, then stores one reduced base plus reversible
reduced-resolution XOR deltas. Saddle's 24 chunks/17 light samples use 48 ignored Mip modules,
about 14.20 MiB of generated Luau files on disk. All variants embedded in those modules derive
from original art; they remain ignored. The abandoned fully duplicated staging format is not
installed. No source image, map definition or original installation file was modified.

Generate/rebuild locally (requires NumPy):
`python tools/asset_pipeline/pack_town_lods.py src/client/DevAssets src/client/DevAssets --map saddle`
Source modules must already exist from the regular local asset pipeline. The command writes only
the named converted DevAssets output directory; it is not part of the original game installer.

TownLods validates format, dimensions, stride, base frame and Adler signatures of the current
encoded source and original lighting patch before inflating a cached level. Adler is a stale-input
check for trusted local assets, not cryptographic authentication. A missing, corrupt or stale
optional LOD falls back to the existing source path, caching failures per chunk/frame to avoid
repeat attempts. Live forest fates and ground scars bypass static LODs, so precomputed intact art
cannot overwrite burnt/felled trees or damaged ground. Dynamic roof char retains its separate
overlay. Evicted static CPU sources can also refresh lighting from an appropriate small LOD.

Initial cold tiles may publish a half-detail preview even when the final zoom target is full.
Full-resolution upgrades wait until selected coverage has parts, camera motion/zoom has settled
for 0.35 s and the previous upgrade is at least 0.35 s old. Replacement admission credits the
tile's existing allocation while retaining other consumers and the core reserve. Camera motion
keeps those previews instead of repeatedly decoding full sources. CPU prefetch uses the small
LOD too; prefetched buffers share the six-entry cache and expose prefetchBytes/mipHits/mipMisses
in TownRenderer.stats(). Cleanup explicitly clears source, preview and prefetch references.
These thresholds and policies are APPROX port rendering choices, not original game rules.

Local Lune CPU profile on one actual Saddle chunk, including current source/patch signatures and
the compact LOD module read/parse: original inflate + light + quarter reduction **0.2491 s**;
precomputed quarter path **0.00916 s**, about **96.3% less preparation time**. Output matched byte
for byte. This is one local CPU measurement, not a Roblox FPS or end-to-end streaming guarantee.
Bootstrap overview generation, full-resolution cold upgrades and dynamic fire/scar composition
still use full sources and can cost more. First-time module replication, native upload latency,
low-memory fallback and other maps' absent optional data remain limits for Studio evaluation.
Smaller physical map tiles and fully budgeted/incremental full-source decoding remain possible
next steps if native profiling identifies a remaining bottleneck.

Verified on installed files: **473 Lune tests passed, 0 failed**, **5 Python packer tests passed**,
changed/new Luau compiles (syntax only), generation of all 48 modules and Rojo build pass. Five
added Lune checks cover source signatures/stale rejection, byte-exact generated half/quarter pixels
for all 17 source lighting samples on an actual chunk, actual renderer cold fast paths/dynamic
fire bypass, stale fallback and camera-motion previews followed by settled full upgrades. Python
checks cover every alpha/odd dimensions, transparent edges, reversible/invalid sparse runs and
reduced sparse-delta reconstruction. **Studio B206-B208 have not been run.** Restart Play after
Rojo finishes syncing the new local modules; original data and paid-cosmetic priorities are unchanged.

## Cooperative full-resolution town warmup (2026-11-11)

Full-resolution upgrades no longer have to decode their whole static source in the same update
that replaces the half-detail preview. Inflate.raw accepts an optional output checkpoint callback,
retaining its existing synchronous two-argument API for other users. Checkpoints occur around
each additional 4096 output bytes for stored and Huffman/backreference streams; only a completed,
validated buffer is returned. A caller can yield or cancel through that callback.

TownRenderer runs one static full-source warmup coroutine per map, resuming it once per Heartbeat.
The callback yields after a soft 2 ms CPU target. The preview/native allocation stays bound while
the job waits; the ordinary settled-view, coverage and memory checks still govern publication.
A completed base source is lit normally before its queued full-resolution upload. Camera selection
loss, dynamic fire/scar changes or map teardown cancel obsolete jobs. Completed warm buffers share
the six-entry spare source cache; live decode clears an obsolete warm result. A failed static
source keeps the working preview and reports once for that chunk instead of repeatedly retrying.
TownRenderer.stats() adds warming and warmProduced diagnostics.

APPROX: this is cooperative scheduling, not a worker thread or a hard frame-time guarantee.
Huffman table construction, individual output intervals, initial module/base64 preparation and
buffer allocation can exceed the soft target. Bootstrap overview decoding, damaged forest/ground
composition and other consumers' synchronous decoder calls are unchanged. The same actual Saddle
source profiled locally in Lune completed across eight resumes with a maximum measured resume of
0.00202 s; machine/warm-cache conditions differ from earlier samples, so no total-time speedup or
native FPS comparison is inferred. Native frame spikes and time to full clarity need B209-B210.

Verified on installed files: **477 Lune tests passed, 0 failed**; changed Luau compiles (syntax
only), and Rojo build passes. Four new regressions cover yielding without partial publication,
cancellation/error propagation and strict size validation, exact output across actual source
Huffman/backreferences, and the actual town retaining its preview through yielded warmup then
cancelling cleanly on map teardown. **Studio B209-B210 have not been run.**

## Town replacement continuity and batched city windows (2026-11-11)

The owner's next report was a brief flash during detail loading, occasional slow transitions and
odd lighting in large cities. Funded town LOD changes now retain the existing visible Part and
ImageLabel while the new native image waits for its queued upload. After a successful write,
the same label binds the replacement and releases the old image. Failed allocation/submission/
write rolls back to the old preview. Both images count toward the budget during a transition;
upgrades require enough headroom to retain the old one. This supersedes the earlier replacement
credit policy: full detail can wait when the device cannot hold both images. Funded downgrades
use the same handoff; an unfunded downgrade first waits for its overview fallback upload before
dropping the old detail. Forced reclaim may still reduce quality. No native memory limit rose.

City side-window fragments now share world-anchored, 64-source-pixel canvases instead of a
coplanar Part/SurfaceGui for every padded fragment. The canvases do not overlap; any fragment
crossing a boundary is drawn on both sides and clipped to its owning rectangle. All masonry is
ordered below all emission within each canvas, so adjacent dark wall fragments cannot sort over
each other's glow. The existing shared full/half atlas, roof exclusions, source coordinates,
occupancy/flicker selection, damage checks and emission gain remain. Batching permits a bounded
4096-fragment selection instead of 768. It still prioritizes nearby fragments if that cap is
exceeded. Canvas creation retains the existing soft 3 ms selection-update budget. There are
more ImageLabels at the higher cap; actual CPU/GPU/memory cost still needs native profiling.
A synthetic 1024-fragment view uses nine canvases rather than 1024 separate window Parts.

APPROX: pane occupancy switches and entry visibility now approach their targets with a 0.18 s
exponential response. Selection/target updates remain at 10 Hz; active fades advance on every
Heartbeat and settled panes stop receiving redundant transparency writes. Page brightness and
fragment colors update only when their correction changes. Zoom visibility still follows the
existing source-derived near thresholds. Damage removes affected views immediately; projected
masonry remains when a normal occupancy switch turns the pane off.

A spatial coarse-window gain snapshot also prevents a prepared subset of detail from globally
suppressing hypothetical coarse windows elsewhere. It changes only the window channel, keeping
road/pool/city glow intact. Current generated facade maps already have a zero coarse-window
channel, so this compatibility fix is not evidence for the screenshot's current lighting issue.
Zero-energy windows skip the gain lookup. No original art/data was regenerated or changed.

Verified on installed files: **484 Lune tests passed, 0 failed**, changed Luau compiles (syntax
only), and Rojo build passes. Seven new regressions cover retained same-Part town swaps and
failed-write rollback; local window coverage/snapshot ownership; unchanged road/distant energy;
dense canvas sharing and layer order; exact seam coverage; and between-tick fade completion.
The bounded selection regression also compares the 4096 nearest results against a full sort.
**Studio B211-B213 have not been run.** These changes address concrete transition and composition
problems; automated fixtures do not establish native FPS, eliminate every flash, or prove a
pixel-identical night appearance. Restart Play after Rojo sync before comparing the reported view.

## Combat map-detail protection and incremental city population (2026-11-11)

The owner reported that the map becomes blurred during a large battle while unit art stays sharp
(initially typed as "blue", then clarified with the same screenshot). A confirmed pressure path
was terrain's priority-10 reclaimer running before unused sprite art at priority 20. Wreck/soot
sheets also requested core allocations, so a new damaged-unit type could reclaim the detailed map
to load its large cosmetic atlas. This is a reproducible code path, not a measured native trace
of the supplied screenshot; texture/display behavior still needs the checks below.

Town chunks now use a separately accounted "terrain" detail kind. The existing shared 16 MiB
detail pool reserves a 4 MiB allowance for terrain: optional detail cannot spend any missing part
of that allowance, either against the detail limit or learned global/native headroom. Terrain
requests may use it. This is a port policy, not Roblox's reported limit, and does not allocate
4 MiB in advance or increase the 48 MiB soft ceiling, 16 MiB detail limit or 8 MiB core reserve.
Terrain and optional detail still share the same pool. Release decrements both terrain and total
detail accounting, so an empty/reclaimed view cannot leave a phantom allowance in use.

Under core pressure, optional layers at priority 10 and unused sprite images at priority 20 now
yield before town detail at priority 30. Detail admission visits only priority 20; moving terrain
later in the order must not make one detail request evict another visible chunk. Wreck/soot sheets,
including their wreck rims/shadows, now use optional detail admission. Figure rim/shadow masks and
the shared death/fire particle atlas do too. Main live-unit body/paint sheets stay core. Refused
cosmetic art follows the existing absent-art/retry behavior instead of clearing the map. These
changes do not stop simulation deaths, burning, damage, ruins, or explicit rebuild behavior.
SpriteBank also requests image admission before decoding the full pixel buffer. A refused optional
wreck sheet now skips that CPU/allocation cost; a later decode/write failure releases its admitted
native image through the existing guarded cleanup. Original sprite pixels and dimensions stay intact.

ImageMemory.pressureStats() reports used/detail/terrain bytes, terrainReserve, detailLimit and the
effective ceiling for native diagnosis. Core art/fog can still force a last-resort terrain reclaim
when the device cannot fit essential images after other reclamation. A 4 MiB allowance cannot
promise full-resolution coverage for every viewport/device. Optional details, including some wreck
or soot art, may be omitted under pressure. Other causes of native blur or stalls are not excluded.

City windows also continue populating between selection ticks. A nearest-first queue admits up to
24 fragments per Heartbeat under a soft 1 ms creation target, replacing the former 3 ms burst once
each 0.1 s. A single fragment's construction is indivisible and may exceed that target. Existing
parts stay bound; source transitions keep their per-frame fades. Camera/zoom/damage changes replace
obsolete pending work, and zoom-out/daylight/map teardown stops it. Static eight-cell spatial buckets
limit candidate searches to the camera rectangle. Stationary, unchanged views reuse their selection;
source occupancy/color/clock updates still run. Exact clipping, nearest/id tie order and the 4096
cap remain. NightWindowRenderer's returned state.stats() adds pending, selectionQueries and candidates.

Verified on installed files: **493 Lune tests passed, 0 failed**, all changed Luau compiles (syntax
only), and Rojo build passes. Nine new regressions cover spatial/full-scan equivalence with negative
coordinates, ties/caps, filters and empty views; between-tick bounded population and stale-work
cancellation; reserved terrain accounting/admission; idle-art-before-terrain reclamation; native
refusal without map eviction/retry loops; safe terrain admission; actual SpriteBank damage-sheet
refusal while live art/map survive; and actual TownRenderer budget/reclaimer wiring.
**Studio B214-B216 have not been run; Roblox player comparison has not been run.**

Roblox documents that Studio runs client and server together and uses more memory than a normal
player, while EditableImage has strict client-specific memory budgets and one displayed image
update per frame. The player may reduce local Studio overhead but is not a fix for this policy or
a guarantee of more editable-image memory. Native Studio/player/device comparisons remain required:
https://create.roblox.com/docs/performance-optimization/design
https://create.roblox.com/docs/reference/engine/classes/EditableImage

## Terrain detail recovery after battle pressure (2026-11-11)

The next stability pass addresses a recovery stall: cached, expired wreck/soot images can keep the
optional detail pool occupied after their visible wrecks disappear. Aggregate map planning then
chooses a coarse tier without attempting a larger allocation, so the ordinary allocation-triggered
unused-art cleanup may never run. The map can stay coarse even though reclaimable art is available.

When the camera has settled for 0.35 s, TownRenderer now requests headroom for the best zoom tier
that could fit the intrinsic 16 MiB detail limit. ImageMemory throttles recovery to at most one
pass per second. ImageBudget first clears a detail-pool shortage through priority-20 unused-art
reclaimers in detail-only mode. SpriteBank filters that pass to optional detail pages, retaining
core art when freeing it would not relieve the binding detail constraint. If global/native headroom
is the remaining constraint, the pass may then reclaim other unused art. Current unit/wreck Content
objects are protected by the existing guard, and SpriteBank's one-second recent-use grace remains.
Priority-10 optional world layers and priority-30 visible town detail are not visited by recovery.
Bad guards, already affordable plans and plans exceeding the intrinsic detail limit do not trigger
unsafe reclamation or native allocation probes.

APPROX rendering policy: each recovery pass targets at most 4 MiB of releases; one indivisible
image can take the actual release beyond that target. This is not a hard frame-time budget. If the
detail shortage remains, recovery does not also discard core art to solve an unrelated constraint.
The returned headroom feeds ordinary LOD planning. Source warmup, memory admission, queued uploads
and retained-preview swaps still govern when sharper detail appears. Recovery itself allocates no
native images, raises no memory limits and does not remove active wrecks, change gameplay damage or
rebuild burned buildings. Essential core images and device capacity can still prevent full detail.

ImageMemory.pressureStats() adds recoveryPasses and recoveryReleased diagnostics. The owner should
Stop Play/restart after Rojo sync, repeat the battle and let its effects/wrecks clear while the
camera stays over the same area. Compare the current town stride, time to sharper coverage, native
frame spikes and these counters. Successful cleanup is not a measured native FPS improvement.

Verified on installed files: **499 Lune tests passed, 0 failed**, changed Luau compiles (syntax
only), and Rojo build passes. Six new regressions exercise detail-only recovery, global-headroom
recovery, bounded passes/impossible plans/guard failure, actual SpriteBank active-wreck protection
followed by idle release, actual ImageMemory throttling/cancellation without allocation, and actual
TownRenderer upgrades after stationary recovery while panning does not trigger it. **Studio
B217-B218 have not been run.** Earlier Studio/player checks remain pending where not reported.

## Avoid duplicate fire/ground town composition (2026-11-11)

The next smoothness pass removes avoidable full-chunk raster work. If an unchanged tree fate is
delivered again, TownRenderer now compares the final kind/char/rotation against the prior state
before invalidating pixels or cached foreground. Multiple rows for one key are coalesced to their
final value. A reset carrying an identical final state likewise leaves town pixels alone; genuinely
removed/restored, charred, fallen or rotated trees still invalidate their affected chunks. The
renderer owns a copy of the three scalar fields so a caller reusing/mutating its input table cannot
silently alter the retained render state. Particle/actor transport and server rules are unchanged.

Each affected chunk has a content version. Freshly decoded/composed source pixels carry that version.
A pending dirty overview refresh or refused upload can reuse those pixels when the content version
and lighting frame already match. True forest/ground tone/strength changes advance the version, and
CPU eviction still requires fresh preparation. Reusing lit static pixels preserves their frame and
reversible XOR-patch metadata, preventing a retry from applying the same light delta twice.

Cold dynamic chunk loading and source prefetch now request the current lighting frame directly and
record it when accepting the pixels. A changed chunk no longer needs to compose its forest once at
base lighting and immediately compose it again at current time before first publication. The later
overview refresh can use that same completed state. Redundant explicit sparse-patch validation was
removed from forest composition because TownPatch.apply already validates the entire patch before
mutating pixels. Original art, alpha treatment and source light deltas are unchanged.

These are CPU-work reductions, not a new frame-time guarantee. A genuinely changed full forest/ground
composition, downsample or overview refresh can still be synchronous and expensive. Cooperative full
static-source warmup, existing dirty/load fairness, retained previews, shared upload scheduling and
terrain recovery remain. No native image budget increased and no gameplay damage/fire state changed.

Verified on installed files: **503 Lune tests passed, 0 failed**, changed Luau compiles (syntax only),
and Rojo build passes. Four new actual-renderer regressions cover unchanged/coalesced/reset tree
states and input ownership; fallen rotation/char invalidation; one current-light cold composition
followed by overview reuse; and upload refusal/retry without recomposition or duplicate static XOR.
The continuous-fire loading check now changes between two visibly different char stages so it still
exercises genuinely dirty terrain. **Studio B219-B220 have not been run.** Native battle frame times
and the effect of these reductions still need comparison in Studio/player.

## Cooperative tree-free damage-source warmup (2026-11-11)

Cold damage repaints no longer have to inflate their full tree-free town source in one frame.
The existing per-map static warmup slot can also prepare a chunk's _Bare source through Inflate's
output checkpoints. Both kinds share one coroutine resume per Heartbeat and the existing soft
2 ms decoding target. A newly requested small job may finish in its first check; a larger one
yields while the current town image/preview stays bound under normal admission. Source pixels
join the same two-entry immutable CPU bare cache only after decoding and dimensions validate.
Static source compressed bytes are kept separate from the _Bare stream.

Dirty forest/ground repaints, cold dynamic detail and dynamic relighting wait for that source to
be ready. Offscreen prefetch skips dynamic chunks with an unprepared bare source instead of
bypassing the coroutine with a synchronous inflate. Other eligible chunks can continue loading.
The job prepares only immutable source art: current fates/scars and current lighting are applied
after it finishes, so ordinary fire changes do not repeatedly restart a long source decode. A
reset removing the dynamic state cancels an obsolete job; map teardown clears it. Failed source
preparation disables that chunk's optional dynamic repaint with one warning and retains the
available view. Explicit reset can still restore static art even after a failed bare source;
repairing the optional source requires a new map/session. Native detail admission and upload
publication retain their existing safeguards.

TownRenderer.stats() adds warmKind ("static" or "bare") alongside warming/warmProduced. The native
image budgets and two-entry bare cache limit are unchanged. One pending decoded source buffer is
additional temporary CPU storage. APPROX: this is cooperative decoding, not a worker or hard
2 ms frame-time guarantee. Module/base64 preparation, buffer allocation, Huffman construction,
individual checkpoint intervals and the later forest/scar raster, source light-patch work,
downsample/overview steps can still cost more. Explicit static restoration and initial forest
sprite loading are not made incremental by this batch. Preparing over frames also adds arrival
latency, while retaining the existing picture instead of exposing partially decoded pixels.

Local Lune profile of one actual 896x896 Saddle _Bare source, excluding its initial module/base64
preparation: synchronous inflate **0.028669 s**; cooperative decode **15 resumes**, worst measured
resume **0.002063 s**. Completed output matched byte for byte. This demonstrates smaller decoder
slices for that local sample, not a native FPS improvement, hard budget or faster total arrival.

Verified on installed files: **507 Lune tests passed, 0 failed**, changed Luau compiles (syntax
only), Rojo build passes, and the local source profile matches. Four new actual-renderer tests
cover yielded damage preparation retaining its bound image then applying current state; reset
and teardown cancellation; unrelated cold coverage continuing; and failure isolation with explicit
static reset recovery. **Studio B221-B222 have not been run.** Restart Play after sync to measure
the reported battle view, source-arrival latency and remaining native frame spikes.

## Cooperative forest/scar composition and publication (2026-11-11)

Damage preparation now continues beyond _Bare inflation into the actual CPU drawing work.
ForestRaster.paint/overview, GroundScorchPixels.apply, TownPatch.validate/apply and ImagePixels.half
accept optional checkpoint callbacks. Existing synchronous callers retain the same defaults and
pixel math. Tree shadows/crowns, rotated fallen sprites, scar coloring, sparse source light patches,
overview sampling and the current native detail tier can yield inside the one per-map work slot.
The former bare-source job is now the first phase of that same damage job; static upgrades still
share its single resume per Heartbeat and soft 2 ms work target.

A job captures immutable tree-state references and copies the chunk's scar strengths/tones, plus
its source configuration, content version and requested source light frame. All composition happens
in private CPU buffers. The displayed pixels stay bound until a completed result reaches the shared
upload lane. Continuous ordinary fire/scar changes do not restart an in-flight snapshot: it can
complete, publish, retain its actual version and leave the chunk dirty for the newer state. This
allows progress during continuous battles instead of requiring a quiet interval. As a presentation
tradeoff, displayed damage can lag the newest authoritative state while jobs catch up. Simulation,
damage, sight/detection and particle clocks are unchanged.

Explicit tree reset, clearing all ground scars and map teardown invalidate pending snapshots through
a presentation epoch. A source light-frame change cancels obsolete work as well. Display-oriented
and far-overview jobs track their respective current/base frame, including cold chunks without an
image. Finished results are prioritized for publication rather than discarded for a newer nearby
request. If native detail is reclaimed after preparation completes, its finished pixels remain
usable for the replacement instead of briefly rebinding the older CPU view. Failure of the private
raster retains the current image, suppresses repeats for that failed content/frame/epoch and permits
a later changed state to retry. Missing bare-source handling remains isolated as before.

Prepared overview/detail buffers avoid repeating reduction on the main update path. Cold dynamic
jobs target the current planned detail tier; quarter views prepare both reductions cooperatively.
Prepared scaled pixels survive rejected upload admission until a successful write. Uploaded previews
carry the captured pixel version and lighting frame and can be reused for a matching dirty overview
refresh, while stale scale/version/frame buffers are rejected. Retained-preview rollback restores
these tags too. Dynamic offscreen prefetch is skipped so it cannot silently bypass the cooperative
composition path. CPU eviction and teardown clear prepared references. TownRenderer.stats() adds
paintReady/preparedBytes and reports warmKind bare/damage/static; sourceBytes includes a completed
full damage result waiting to publish. These counters are not a complete Lua heap measurement.

The existing native ceiling, detail/core limits and terrain allowance are unchanged. One active job
and at most one completed result can retain private staging buffers; additional memory is CPU-side.
The soft target is not a hard full-frame bound. Initial forest sprite/module loading, source/config
snapshot creation, buffer allocation/copies and an individual row/checkpoint interval can still cost
more. Static restoration is still synchronous; a resolution change or an unprepared fallback tier
can require a synchronous reduction. Native upload/display timing is governed separately. Moving
work across frames can add visible arrival latency even while reducing individual CPU bursts.

Local Lune profile on an actual 896x896 Saddle chunk containing 77 trees, assigned mixed burn/fall/
stump states for the profile: source light patch + forest + overview + half reduction took **0.011896 s**
synchronously. Cooperative execution completed over **7 resumes**, worst **0.002467 s**; full pixels,
overview and half pixels matched byte for byte. Source inflation, module/base64 preparation and
initial forest sprite loading were excluded. This is a local slice measurement, not a Roblox FPS
claim, hard limit, or faster total arrival. Synthetic scar tests separately cover exact roof/tone/
transparency behavior with checkpoints.

Verified on installed files: **519 Lune tests passed, 0 failed**, all changed Luau compiles (syntax
only), and Rojo build passes. Twelve added regressions comprise eight actual-renderer checks for
yielded private drawing/coalescing, reset/teardown, scar reset while forest remains, isolated failure,
prepared coarse/overview reuse, time jumps, native reclaim before publication and rejected coarse
uploads; four pure checks compare synchronous/yielded forest, scaling/overview, scars and reversible
sparse patches, including corruption/cancellation behavior. Existing cold damaged coverage also now
checks quarter-tier preparation without another synchronous resize. **Studio B223-B225 have not
been run.** Restart Play after sync to compare the reported battle and its remaining native spikes.

## Cooperative intact restoration and explicit pixel metadata (2026-11-11)

Restoring a chunk after its last forest/ground fate clears now uses the existing shared preparation
slot. The restore phase inflates the original intact source, validates/applies the requested source
light patch and prepares its overview and matching detail tier through the optional checkpoints.
Available damaged pixels remain visible until completed restoration can publish. A new fire/scar
state, explicit presentation epoch, source-light-frame change or teardown invalidates obsolete work;
an old intact snapshot cannot overwrite a later fire. Ordinary cold intact loading and precomputed
LOD previews keep their existing path. Restoration follows existing reset/state transitions and
adds no gameplay regeneration, health changes or automatic building repair.

Prepared and direct decodes now return the actual pixel frame and reversible patch together with
their dimensions. Cold loading, dirty refresh, relighting and prefetch accept that metadata rather
than guessing the frame from a cached damaged/intact flag. Restored non-base pixels retain their
applied XOR patch, so a later time change first removes it correctly instead of applying light twice.
Intact LOD refresh/cold publication and full-source warm adoption clear stale dynamic-forest flags
and stamp their current content version. This prevents an intact source later taking the unnecessary
forest-composition path after CPU eviction/upgrading. Internal prepared state now uses generic paint
names, and TownRenderer.stats().warmKind can report restore as well as bare/damage/static.

An explicit repeated tree reset also requeues chunks whose displayed/prepared CPU version remains
behind their authoritative content version after a rendering failure. It does not invalidate an
already current intact view or rerender an otherwise identical successful state. Failed restoration
keeps the available image and uses the existing content/frame/epoch failure suppression; a corrected
source plus another explicit reset can retry without first inventing a different tree state.

APPROX: the shared one-resume/Heartbeat, soft 2 ms policy applies to this path too. Module/base64
preparation, allocation/copying, initial art loading and unprepared scale-change fallback remain
possible synchronous costs. Source restoration can now take multiple frames; this is a presentation
latency tradeoff, not a hard frame-time or native FPS guarantee. Native memory limits, upload lane,
terrain reservation/recovery and existing damage persistence are unchanged.

Verified on installed files: **523 Lune tests passed, 0 failed**, changed Luau compiles (syntax
only), and Rojo build passes. Four new actual-renderer regressions cover yielded restoration with
unchanged bound pixels, prepared coarse scaling and a nonempty light patch that later reverses;
new fire canceling an obsolete restore; explicit repeated-reset recovery after a source failure;
and teardown during source preparation without new images or late publication. **Studio B226-B227
have not been run.** Restart Play after sync before testing reset/camera/time transitions.

## Player-building art and readable structure labels (2026-11-11)

- Replaced the large owner-colour player-building blocks with local original HQ, barracks, factory, bunker, AT gun, radar, SAM, artillery-base and night-ops sprites. The extractor follows original faction selection and latest-art fallback. Base/paint layers retain team tint without per-building image copies. Static weapon, cap, factory-door/crane art and source rotating-dish frames are included. Map buildings, oil-rig art and removed power infrastructure are separate.
- Snapshot structure rows append optional army field 13, including remembered owner-side armies. Existing health, location, ownership and fog filtering remain authoritative. Fog memories use grey, dim resting art, unknown health, no window emission and no live dish animation. Minefields remain in their dedicated filtered cell overlay.
- APPROX port UX: healthy idle structures have short names at close zoom; selecting/hovering exposes health. Damaged/unfinished structures keep priority indicators. Deterministic screen-space packing gives selection, hover, construction and damage priority, suppressing lower-priority overlapping labels. Targeting keeps the existing coordinates and structure view API. Old destroyed-HQ slab/anchor retention was removed; the separate collapse effects remain.
- One lazy shared atlas per army: coalition 2,904,064 bytes, republic 2,646,016 bytes, both 5,550,080 bytes (about 5.29 MiB) if loaded. ImageMemory admission, throttled retries, queued uploads and a shared soft 2 ms cooperative atlas-decode slice avoid one image/decode per building. Existing blocks remain a fallback while pixels load or local art is absent/broken. No source pixels are installed into the original game.
- APPROX limitations: build progress fades resting art; shadows offset the original silhouette with the sun. Full source scaffolding/raising, health damage overlays, height-band extruded shadows, production-door/crane activity, weapon aiming/recoil/reload and additional flags/beacons are still pending. Source window masks are drawn with native GUI alpha rather than the original additive canvas blend. This is resting-art/readability coverage, not complete structure animation parity.
- Validation: 13 focused behavioral tests cover atlas sharing, asynchronous publication, optional-module failure, image refusal/retry, fog, cooperative cancellation, screen-space collisions, focus, teardown and minefield routing. All changed Luau compiles (syntax only); exporter JS/Python syntax checks pass. Generated original pixels round-trip through the real Luau inflater with 160 cropped rectangles checked for transparent packing guards; source contact sheet visually inspected. Final full suite: 536 passed, 0 failed. Rojo build succeeds. Native Studio/player visuals and frame times remain unverified; run B228-B230.

Local-only generation (output data/art stay ignored):

```powershell
node tools/conversion/export_structure_art.cjs "A:/SteamLibrary/steamapps/common/WarFront Demo/resources/app.asar" docs/private/player-structures.json
python tools/asset_pipeline/pack_structures.py docs/private/player-structures.json assets/original/warfront-demo-assets-20261110-104215/dist/tiles/buildings-top.png src/client/DevAssets/OrigStructures.luau
```

Next: Studio coverage for both armies, crowded labels, fog and battle memory; then finish source construction/damage and weapon/production animation. Paid cosmetic skins remain LAST.

## Player-building dirt-pad shadow fix (2026-11-11)

- The reported displaced dirt rectangles came from tinting/offsetting the complete body sprite as a shadow. The packer now unions only the original height-band alpha masks; dirt, paved yards and other ground-only body pixels never enter the caster. The visible body/paint art is unchanged.
- APPROX: caster coverage is reduced to half resolution with area filtering to retain thin fence coverage; the existing sun-directed silhouette offset remains. This does not yet implement full source height-band extrusion or animated part shadows.
- The mask uses the existing shared faction atlas, not a new image per building. Updated atlas allocation is 3,182,592 bytes for coalition and 2,887,680 bytes for republic (6,070,272 total; about 5.79 MiB when both are resident). Older local atlases without the new metadata omit the shadow instead of falling back to the dirt-bearing body. Regenerate local art with the existing extraction/packing commands when updating another checkout.
- Validation: three synthetic Python regressions cover excluding dirt/paint, preserving roof/thin-fence coverage, metadata offsets and alpha union. Two new Luau regressions check the dedicated caster rectangle/scale and old-atlas behavior. Original HQ/barracks before/after contact sheet visually inspected; both generated atlases decode with the real Luau inflater and transparent guards validated for all 178 rectangles. Final full suite: 538 passed, 0 failed; three Python packer tests pass; Rojo build succeeds. Native Studio check B231 remains pending.

## Source player-building construction and damage states (2026-11-11)

- Added the source height-map construction sequence: diagonal slab pouring, wet concrete edge, rising walls, height-based original-art reveal, poles and scaffold bands. Raw body/paint pixels are sampled before resting weapon/cap/crane composition, so those finished parts appear at completion. The normal texture preserves the original Canvas2D premultiply/readback at translucent fences, avoiding height-threshold errors.
- Added source procedural damage stages with deterministic id-based soot, char, rimmed holes, rubble, collapsed heaps and beams, clipped to the original body/roof masks. Original entry thresholds and repair hysteresis keep stable stages. These are visual reads of server health/build state: no healing, repair timing, fire rules, damage or construction gameplay was changed. Fog memories suppress live damage/construction updates and use the existing grey resting-art representation.
- StructureEffects uses one optional 768 x 768 atlas (2,359,296 bytes / 2.25 MiB), nine native-resolution 256px slots and a six-source CPU LRU. Selected/hovered sites receive priority; other sites retain the existing static/faded fallback if slots/image memory are unavailable. Static faction atlases remain 6,070,272 bytes total; dynamic art adds no per-building EditableImages. Source decode and pixel work share the existing soft 2 ms per-Heartbeat structure budget, and keyed region writes use ImageMemory uploads. This is a budget policy, not a native frame-time guarantee.
- Construction publication and static-sprite visibility swap in the same upload callback, keeping old valid construction pixels while newer progress prepares. Stage/owner changes, repair, fog, slot reassignment, offscreen expiry, teardown and optional-image reclamation invalidate obsolete results. Reclamation restores static fallback immediately; the optional canvas releases when idle. Queue/native refusal is throttled. Old local source atlases without effect fields retain their previous sprites.
- Reference validation ran the original Dte/vXt functions unchanged under local Canvas2D for 306 cases across both armies, nine kinds, four construction points/two ids, and three damage severities/three ids. Construction alpha and height/low/presence fields match, with RGB differences at most 1/255. Damage alpha differs at most 1/255 and premultiplied RGB at most 2.055/255 from native canvas compositing; straight RGB in nearly transparent edge pixels can differ more. Contact sheets visually inspected. Source reference rasters/harness remain in private staging, not the public repository.
- Validation: 26 focused Luau tests (15 added in this batch) cover construction geometry/tint, deterministic masked damage, hysteresis, cooperative cancellation, shared-image/slot/cache bounds, async publication, repair/fog invalidation, pressure/retries, atomic fallback and teardown. Four Python packer tests pass; all eight changed Luau modules compile (syntax only); exporter syntax passes. Final full suite: 553 passed, 0 failed; Rojo build succeeds. Native Studio/player visuals, memory and performance remain unverified: B232-B234.
- Remaining: source placement/site strings and pegs, deployment scan/drop accents, full projected height-band/animated-part shadows, additional HP-based flame/smoke accents, weapon aiming/recoil/reload and production-door/crane activity. Those are separate from this raster state port. Paid skins remain LAST; power lines/stations remain removed.

## Multiplayer milestone: cross-server lobby browser (owner request, 2026-11-12)

- The lobby browser must list available matches across all live game servers, so players can find an open lobby regardless of which server they first joined. Show map, current/max player count, waiting/in-progress status and a join action; include friends/filtering where practical. Respect each lobby’s visibility and join permissions.
- Keep listings fresh, remove closed/expired/full matches promptly, recheck available slots when joining and show a useful refresh/retry if a lobby fills or disappears. Joining routes the player to that lobby’s actual server; no manual server hopping should be required.
- This is a required part of the future multiplayer/session milestone, not a shipped lobby feature. Add cross-server/private-server join, stale-listing and server-close tests when that milestone is implemented. Paid cosmetic skins remain the final milestone.

## Match-lifetime house ruins and factory production motion (2026-11-12)

- Owner rule: burned-down map houses stay ruined for the rest of the match. HouseWorld now locks permanent ruins in its underlying model. Timed rebuilding, direct raise/rebuild calls and mid-match reset calls cannot erase the roof marks, shells or transport epoch. Only a newly created match/world starts clean. Stock HouseFire fixtures without this world policy still support the original reconstruction behavior for source-parity tests.
- F2’s button is now “Reset forest / ground damage”. It resets forests, ground scars and delayed fire impacts without resetting houses or their active fires. The response explicitly says houses stay ruined until the next match. Earlier roadmap/check descriptions where this button restored houses are superseded by this owner request. This is about map houses; player-built structure repair rules were not changed.
- Factory production now opens/retracts the original doors, holds them briefly after an observed unit completion, moves the Coalition crane while working and draws source-timed welding sparks. Republic uses its own door geometry and has no Coalition crane. Original art/config positions are generated locally; parts share the existing faction atlas. Source atlas size is now 3,223,552 coalition + 2,887,680 republic = 6,111,232 bytes, only 40 KiB above the preceding batch, with no new EditableImages per factory.
- Snapshot field 14 is optional factory animation data: a visible-work bit and per-view completion pulse. No queue contents, queue sizes or total production counts are transmitted for the animation. Per-view completion history is discarded while hidden, so reveal never replays hidden production. Server inactiveReason gates working state. Fogged remembered parts are static, grey and spark-free; construction hides the finished parts. Parts update per Heartbeat, with offscreen expiry and GUI teardown cleanup. Older local atlases remain static.
- APPROX native rendering: integer ImageRect door crops and UI spark rectangles replace fractional Canvas2D crops/additive blending. Factory smoke, animated part shadows and weapon aiming/recoil/reload remain pending. Six closed/half/open factory contact-sheet views made from the actual renderer pose records were visually inspected. Authoritative house tests cover long timers/rain, direct reset/rebuild attempts, the admin boundary, late join and a clean newly-created world. Factory tests cover wire visibility, completion holds, pose bounds, deterministic welds, no per-site images, fog, construction and teardown.
- Validation: 33 focused Luau tests pass (11 additions relative to the preceding full suite), including the updated legacy admin reset expectations; five Python packer tests pass; 15 changed Luau files compile (syntax only); exporter syntax passes. Both private atlases decode through the real Luau inflater with all 184 cropped-rectangle guards validated. Final full suite: 564 passed, 0 failed; Rojo build succeeds. Native Studio checks B235-B237 remain pending. Cross-server lobby browsing is planned in the multiplayer milestone above, not implemented by this visual batch.

## Battle image-pressure cleanup and opt-in debug boards (2026-11-12)

- The reported console shows image admission refusals plus AtlasTestBoard G-key logs. Both old atlas boards were enabled by default and allocated directly through AssetService outside ImageMemory accounting. The boards and ownership probe are now opt-in, avoiding test bindings during ordinary play. The two boards previously cost 1,843,200 RGBA bytes (about 1.76 MiB), in addition to untracked callbacks/parts.
- AtlasTestBoard now uses optional shared-budget admission before pixel decode, supports replacement/destroyAll, cleans failed image checks, disconnects input/render callbacks on destruction and yields its image first under reclamation. No client EditableImage allocation bypass remains outside ImageMemory. Reclaimer passes use a stable snapshot with active-entry checks, so a board unregistering itself cannot skip the next reclaimer or invoke another cancelled owner.
- SpriteBank now uses the existing compact rim atlas at every zoom for live vehicles, wrecks and deploy states, sharing it for rim/rimHalf. Unit body/paint textures stay at native resolution. Full rim, half rim and shade suffixes are classified optional detail instead of core. Across nine base vehicle kinds, avoiding duplicate full rims saves up to 14,745,600 bytes (14.06 MiB) if all those looks would otherwise be resident; actual savings depend on the scene. Larger outlines and turret-plain masks may be less detailed/omitted at close zoom; this is an explicit port memory tradeoff, not a promise of identical outline pixels.
- Expected SpriteBank/ManEffects admission refusal now returns the existing fallback quietly before decoding; corrupt pixel data/write failures still warn. Failed entries stay cached after their own release notification, avoiding immediate retry churn. ImageMemory.pressureStats adds policy refusal counts by image class, native refusal count and the last refused size/class, so lack of capacity remains diagnosable. Roblox may still log actual native allocation refusals; no platform budget was raised or bypassed.
- Verification: 30 focused tests cover active-image/terrain protection, compact rim classification and sharing, quiet soldier-mask fallback, retained genuine error reporting, refusal counters, reclaimer self-removal, debug readback failure, replacement, key-hook cleanup and pressure release. Nine changed Luau files compile (syntax only). Final full suite: 572 passed, 0 failed; Rojo build succeeds. Native Studio/player stress checks B238-B240 remain pending.
- Official allocation reference: https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateEditableImage describes a device-specific budget and nil on exhaustion; https://create.roblox.com/docs/reference/engine/classes/EditableImage describes shared image references and Destroy reclamation. The project policy ceiling is not a guaranteed Roblox device limit. Weapon-animation art was deferred while fixing this observed pressure, and is the next implementation batch. Permanent house ruins, factory production motion, planned global lobby browsing and skins LAST remain unchanged.

## Original AT-gun and bunker motion (2026-11-12)

- Player-built AT guns and bunkers now use source turn rates, idle sweeps, five-second post-shot aim holds, quadratic recoil and nearest source facing plus smooth residual rotation. Bunker aiming clamps to the original firing slits; its cap stays over the gun. AT-gun part shadows follow the sun; bunker gun shadows are omitted as in the source. Gameplay targeting, damage, reload gates and combat RNG are unchanged.
- The server attaches cosmetic aim/observed-shot data only to currently visible supported structures, in optional snapshot field 15. A false field 14 preserves a dense array when factory data is absent. Per-side observation histories baseline new/revealed sites, discard hidden history and preserve a pulse for multiple viewers without transmitting hidden shots. Fogged remembered guns immediately become static grey resting poses; construction hides finished parts.
- All 32 native facings share one optional 512 x 386 image (790,528 RGBA bytes, 0.754 MiB), with throttled upload/admission and reclaim to an already-loaded core resting pose. No per-gun EditableImages are allocated. Core faction atlases total 6,266,880 bytes, only 155,648 bytes above the preceding static atlas; including the optional gun page adds 946,176 bytes versus that baseline. Packer guards preserve trimmed pivot offsets and the nine-kind faction contract.
- APPROX: cosmetic idle phase and local recoil interpolation use the client clock after the observed server shot age; native UI rotation/blending and part-shadow alpha replace Canvas2D drawing. This is not exact paused-clock synchronization or full source height extrusion. Existing optional structure-damage overlays do not damage separate animated parts independently. SAM reload/launcher poses and artillery-base weapon motion remain next.
- Verification: 25 focused Luau tests pass, seven Python packer tests pass, ten changed Luau modules compile (syntax only), exporter syntax passes, and both actual generated faction atlases plus all 32 guarded weapon facings decode through the real Luau inflater. Eight cardinal/diagonal actual-renderer pose views were visually inspected. Rojo build succeeds; full-suite result recorded after completion below. Native Studio checks B241-B243 remain pending.
- Final full suite: 584 passed, 0 failed. No native Studio/player session was run for this batch.

## Source SAM launcher reload poses (2026-11-12)

- SAMs now use source ready/half/lowered stages after an observed missile launch, return toward the reload bearing while lowered and raise on the source timings before readiness. Cosmetic reload duration comes from the actual match rules in snapshot field 15's seventh item. Normal ground targeting and authoritative SAM missile/reload/interception logic are unchanged. The existing barrage-interception path does not emit the source shot presentation event and does not trigger this launcher animation.
- Coalition retains 16 facings for each of three poses; Republic retains its three fixed-direction vertical-launch poses without a fake UI rotation. Each stage uses its own source shadow height. The two factions have separate optional pages and are admitted only when a currently visible completed SAM uses that faction. Native memory: Coalition 1,396,736 bytes, Republic 102,400 bytes; core faction fallbacks total 6,270,976 bytes, just 4 KiB more than the previous batch. AT/bunker optional art remains separate. Reclaim restores loaded core resting art for every optional weapon bank and throttles re-admission.
- New/revealed views baseline old launches, fog memories stay static/grey, and construction hides finished launcher layers. The existing client-clock interpolation approximation remains; full war-pause synchronization and additive/height-band Canvas2D effects are not established. Artillery-base gun/pod aiming, raising and recoil remain next.
- Verification: 29 focused Luau tests pass, eight Python packer tests pass, ten changed Luau modules compile (syntax only) and exporter syntax passes. Both core atlases, the AT/bunker page, all 48 Coalition SAM facings and three Republic SAM poses decode through the real Luau inflater with transparent crop guards validated. Six actual-renderer SAM contact-sheet views were visually inspected. Rojo build succeeds. Native checks B244-B246 remain pending; final full-suite result follows after completion.
- Final full suite: 588 passed, 0 failed. Native Studio/player checks were not run.

## Separate weapon war clock and real-time scanning (2026-11-12)

- Corrected the previous animation batch's clock approximation. Source recoil age, post-shot hold age and SAM reload stages now use the authoritative match clock; idle scanning and turn integration retain real time, matching the source split. A victory/opening pause no longer ages a launcher through reload solely because wall time passes. F2 freezing daylight remains a separate sun control and does not pause combat.
- Visible weapon packets optionally append match time/running to fields 8/9, with a zero reload placeholder so arrays remain dense for AT guns/bunkers. Hidden structures still receive no live weapon packets. The client predicts at most 0.2 seconds beyond the last source timestamp if snapshots stall; reset/fog discards the clock anchor and observed pulse history. Older packets retain their wall-clock fallback. Network transit delay and correction arrival remain approximations, not an exact synchronized replay.
- Validation: 17 focused motion/renderer tests pass, including dense packets, pause/resume without recoil replay, SAM reload hold, bounded prediction, real-time idle independence and fog filtering. Five changed Luau files compile (syntax only); Rojo build succeeds. No images/art pages or gameplay timing were changed. Native pause/network checks B247-B248 remain pending; final full-suite result follows after completion.
- Final full suite: 592 passed, 0 failed. Native Studio/player tests remain unrun.

## Artillery-base paired weapon motion (2026-11-12)

- Artillery bases now animate their original flare gun and rocket pod independently: source mount origins, shortest-arc turn limits, gradual raising/lowering, idle rest offsets, hold after the final scheduled round, per-round quadratic recoil and the gun's brief recoil sprite. Both armies use the source's common artillery-base mechanism art. The existing gameplay launch/damage, kill costs, cooldowns, targeting, flare jitter and barrage RNG remain unchanged.
- Successful artyStrike calls observe the already-computed barrage/flare fire times without any extra gameplay RNG draws. Cosmetic records are separate for gun/pod. Optional snapshot field 16 includes current visible active/war-clock state and per-view observed schedules. False placeholders at 14/15 keep arrays dense. New/revealed views baseline old launches, hidden view caches are discarded, same-side viewers retain the same observed schedules, and fog/construction/offscreen/teardown clear live animation state. Recoil age follows war time while source turning/raising use real time; extrapolation remains bounded to 0.2 seconds.
- One shared optional 1,937,408-byte atlas (about 1.85 MiB) contains 80 native facings across five mechanism states, with 160 body/paint crops. It loads only for visible completed artillery bases and shares the existing cooperative decode/upload queue, retry limits and detail reclamation. Each faction core keeps ready-to-draw resting fallbacks, adding 147,456 bytes total above the preceding core pages (new core total 6,418,432 bytes). No per-base EditableImages. Reclaim clears both the mechanism owner and drawing handles before image release, so the next heartbeat cannot rebind a destroyed page.
- APPROX: the port records each base's own actual flare schedule; the source renderer scans the owner's whole flare list, which can include simultaneous fire from another base. Native UI blending/rotation, part-shadow alpha, bounded network-clock prediction and static memory fallbacks remain approximations. The existing damage canvas does not independently raster-damage moving mechanisms. Full source height-band projection and placement/deployment accents remain separate work. Power infrastructure stays removed; global lobby browsing remains planned and paid skins remain LAST.
- Verification: 34 focused Luau tests pass; nine Python packer tests pass; changed Luau code compiles (syntax only), exporter syntax passes and all generated core/weapon pixels decode through the real Luau inflater with transparent crop guards verified. A private run of the original JavaScript renderer matches 320 paired mechanism poses (aim/raise/part/recoil coordinates; maximum numeric error 1.12e-15). Six contact-sheet views captured through the actual paired and gun renderers were visually inspected. Rojo build succeeds. Native checks B249-B251 remain pending; final combined suite result follows after completion.
- Concurrent work: preserved the newly added admin_kills test registration. Initial hash guards stopped installation before any file writes; after review the installer additionally verified that every existing runner line survived as an ordered subsequence. No existing tests or admin implementation were removed. No commits/pushes were made.
- Final combined full suite: 607 passed, 0 failed, including concurrent admin-kills tests. Native Studio/player checks were not run.

## Source construction-site accents and yard timing (2026-11-12)

- Corrected a timing gap in the preceding construction raster: the source first surveys/prepares the yard for production.buildYardShare (0.3 in runtime defaults), then passes normalized remaining progress into its slab/wall/roof reveal. The port now observes that split. Yard preparation allocates no optional construction canvas; finished body art remains hidden during the yard and while height pixels are pending/refused, with the site blueprint remaining available. Gameplay construction duration and repair rules are unchanged.
- Added source-layout grid lines, pulsing corner pegs, dashed survey strings/perimeter pegs, a sweeping yard scan, brief placement lift/expanding flash and a diagonal completion sweep/expanding outline. Geometry uses projected screen pixels so line/peg widths stay consistent with camera zoom. Blueprint/grid sit below the rising building; placement/completion accents have a separate upper container above roofs and moving guns. This respects Roblox's default sibling-layer ordering without changing other structure layers (official reference: https://create.roblox.com/docs/reference/engine/classes/LayerCollector#ZIndexBehavior).
- Site birth/completion timestamps are observed on incoming visible snapshots before art is streamed, rather than generated when an image finishes loading. Initial snapshot baselines and hidden/revealed records suppress historical flashes; offscreen completion therefore expires normally instead of replaying when panning back. Fresh later sites below the source's 5% birth threshold get the placement effect; only observed unfinished-to-complete transitions get the completion flash. These are local cosmetic records; no server gameplay, snapshot fields or remote permissions changed.
- Added half-resolution white alpha masks to the existing faction core pages, shared by all sites. Native site accents allocate no EditableImages or per-site pixel buffers. Core pages are now 3,653,632 + 3,330,048 = 6,983,680 RGBA bytes, 565,248 bytes (0.54 MiB) above the previous batch; body and weapon art retain their prior resolution. Native UI rectangles pool during active effects, cache unchanged styles/positions and are destroyed after expiry, fog, offscreen timeout or teardown. Healthy idle structures allocate no site UI objects and do not tick their site handles.
- APPROX native rendering: half-resolution alpha replaces the source's full-size mask; the placement ghost is a uniform silhouette rather than the source tinted/striped body copy. UI gradients/alpha replace Canvas2D's additive/premultiplied glow. At extreme zoom each dashed edge is capped at 48 dashes while keeping its duty ratio. Client snapshot arrival timing, rather than a lockstep original renderer observation, timestamps the brief pulses. Full hover/refusal preview parity, fallback piece-drop accents and projected height-band shadows remain separate work; this batch does not claim all placement/deployment visuals are finished.
- Verification: 39 focused Luau tests pass; nine Python packer tests pass; ten changed Luau files compile (syntax only), exporter syntax passes and all generated core/weapon crops decode through the real Luau inflater with transparent guards verified. A private run of the original renderer matched 64 layouts / 1,232 timing and geometry checks (maximum numerical error 1.14e-13); the bounded native dash segments, mask pixels and additive blending are excluded from exact-equivalence claims. Three views using actual native-UI pose records plus actual construction pixels were visually inspected. Rojo build succeeds. Native Studio checks B252-B254 remain pending; final full-suite result follows after completion.
- Final full suite: 621 passed, 0 failed, including existing admin-kills and artillery tests. Native Studio/player tests were not run. Nothing was committed or pushed.

## Source-style placement preview and defence scale (2026-11-12)

- Replaced the ordinary building cursor's neon slab with original faction body/paint art, hover lift/bob, a shadow, source-timed scan/stripes, marching dashed border, pulsing brackets and refused-site jitter/red wash. Known terrain/road cells receive clipped hatch segments; known overlapping player structures receive pulsing red outlines/brackets above the ghost. Far zoom retains a footprint/bracket view; exact source far-zoom badge icons remain pending. Mine/trench stroke tools keep their existing paths and commands.
- The cursor shares StructureArt's existing core pages and alpha masks, including pending/refused-image fallback to vector footprint graphics. It creates no EditableImages, coloured pixel copies or per-frame Content objects. Body/paint/mask content binds once per changed core image. One reusable GUI holds bounded rectangle/stripe pools; hide/cancel is cheap and teardown releases it. All original atlas compressed pixel strings and dimensions are byte-identical to the preceding batch; core RGBA remains 6,983,680 bytes. The only regenerated asset change is ignored source preview metadata.
- Tracing Nu also found the source's defence sprite scale (0.72 of its visual footprint). The cursor and placed bunker/AT/radar/SAM/night-ops art now use it consistently. Production buildings/HQs keep their prior scale. Gun/dish/height-reveal layers follow the smaller defence quad; site peg counts still use the unscaled three-cell yard and screen widths use the actual projected quad. Server collision/placement/pathing/sight footprints and gameplay numbers are unchanged. Older local art without this metadata keeps its previous scale.
- Local placement checks are advisory: public terrain/road grids including original bridge widening, rig pads, supplied fog-filtered structure overlaps, own territory, current own funds/kills and completed own prerequisites. Road preparation is cooperative and builds a single CPU byte-per-cell grid without a route graph; only a finished model is published. Until ready, or after one preparation failure, the prior territory-only hint remains available. No new remotes or hidden-world queries were added. All clicks still go through the existing server build validation, even when locally red. Seal checks, mines/trenches, unseen enemy restrictions, night-ops rebuild waits, dynamic road cuts/restoration and snapshot/resource races remain server decisions and can differ from the hint. A green hint is not a server guarantee.
- BuildController now disconnects its own render/input handlers and destroys old ghosts/stroke parts when restarted, hides the building preview during strokes/cancel/no-ground, guards missing camera/ground and preserves the existing raw mouse/viewport raycast. Own resource fields merge across partial state messages. Shift repeat placement, processed UI clicks, right/Escape cancellation, click suppression, mine lines and engineer trench commands retain their existing authority and behavior.
- APPROX native rendering: multiplicative ImageColor3/layer alpha replace the source precomposited source-atop ghost tint; shared half-size masks replace full-size shadow/scan masks; native integer UV stripe sampling and UI gradient alpha replace Canvas2D blending. Native pools cap dashed edges at 48 repeats, hatch density at 24 periods/cell, scan stripes at 64 and drawn clashes at eight (all known overlaps still affect the hint). Source radar/coverage preview rings, exact far badges and remaining refusal/hover pixel parity are not claimed complete.
- Verification: 41 focused Luau tests pass; changed Luau files compile (syntax only), exporter syntax passes and every regenerated core/weapon crop decodes with transparent guards verified. Existing native atlas bytes/dimensions are unchanged. Private original-JavaScript comparison matches 48 hover/refusal poses across 1,560 motion/geometry checks (maximum numeric error 3.56e-15; native tint/dash/hatch/UV pixels excluded). The local road bitmap matches the authoritative Roads.build result in a bridge/deep-water fixture. Three actual cursor-renderer contact-sheet views were visually inspected. Full combined suite: 642 passed, 0 failed; Rojo build succeeds. Native Studio/player checks B255-B257 remain pending. No commits/pushes were made.

## Placement coverage guides and screen-space cursor (2026-11-12)

- Added source-style same-type placement guides: existing known structures receive pulsing radial washes, rotating backed dashes and four fixed cardinal ticks. Known same-type radar/defence sites also show nominal coverage circles; a proposed radar site gets its own coverage circle. Ordinary proposed defences do not receive an invented attack-range circle. Guides read the existing fog-filtered structure views, including remembered and unfinished sites as planning references; they perform no hidden-state query or remote call. Hidden/dead live records are omitted. Guides appear while the cursor has a map placement point.
- Range values come from current match rules. In particular, Sim.radarsOf currently uses base radar radii without the original city boost/power system, so the guide also uses base radii. Remembered/unfinished-site circles are nominal planning information, not a promise that those sites are currently operating. No radar, attack, fog, build validation, input payload or server authority changed.
- Coverage uses a single ScreenGui below the placement cursor and HUD, with pooled vector Frames/UICorners. The ordinary building ghost now projects into a separate ScreenGui below the HUD instead of magnifying a fixed world-space SurfaceGui canvas. Existing body/paint/mask content remains shared and cached. Camera movement updates projected centres and size; cancellation, strokes, absent camera/ground, replacement, external GUI teardown and controller restart hide or release the relevant owners/connections. Legacy local art without coverage metadata simply omits guides.
- APPROX native policy: at most twelve intersecting same-type sites, nearest the cursor, receive guides. Range/marker paths use short chord segments, capped at 64/40 dash periods with source duty ratios retained; eight nested discs replace the smooth radial gradient. Native transparency, rasterization and screen-space axis alignment do not claim Canvas2D pixel identity. This policy bounds object counts but is not a native frame-time guarantee. Exact far building badges, full hover/refusal pixel parity, fallback piece-drop accents and height-band shadows remain pending.
- Verification: 42 focused tests pass; changed Luau files compile (syntax only), and exporter syntax passes. An unchanged original-JavaScript reference matches 210 token-size cases and 21 marker poses across 336 numeric checks. All compressed faction/weapon/SAM/artillery pixels and dimensions are byte-identical to the preceding batch; faction cores remain 6,983,680 RGBA bytes total. These guides and the cursor allocate no new EditableImages. Four contact-sheet views rasterized from the actual renderer UI trees were visually inspected; these are mocked UI renders, not native screenshots. Rojo build succeeds. Full combined suite: 651 passed, 0 failed. Native Studio/player checks B258-B260 remain pending. Nothing was committed or pushed. Power infrastructure stays removed; cross-server lobby browsing remains planned and paid skins remain LAST.

## Original far-zoom placement badges (2026-11-12)

- Added the source building tokens to ordinary placement previews below the full-art zoom threshold. HQ/barracks/factory use their source shields; bunker/AT/radar/SAM use their defence badges. Artillery bases reuse the source factory icon and night-ops uses radar. Source C4/My icon selection, 128-pixel SVG raster size, expanded outline view box and painter order are generated from the owner's local install, never copied into public assets. The exporter now requires @napi-rs/canvas, as other local art exporters already do; NODE_PATH can point to its installed node_modules directory.
- Badges remain centred on the ground footprint above the preview's hover/refusal drawing. They use the existing source CoverageMotion token sizing, HQ/facility shares, far/detail scaling and current production spacing. Source valid/refused border/symbol colours are applied to a shared white foreground; dark fill/rim remain a separate shared backing. Default native icon smoothing preserves the anti-aliased vector look while body/weapon sprites retain pixelated sampling. Zooming to the source full-art threshold swaps to the existing detailed ghost without retaining both representations. Preview clicks and all server authority are unchanged.
- Badge layers live inside each existing faction core atlas; identical backings and repeated kind mappings share crops. The offline packer tries guarded free-rectangle layouts as well as its skyline layout and retains the shortest valid result. It never rotates, resamples or reduces existing art. The two core pages are now 1024x1024 and 1024x952: 8,093,696 RGBA bytes total, an increase of 1,110,016 bytes (1.06 MiB). There are no additional native images, per-colour pixel copies or per-site images. Existing optional weapon/SAM/artillery page pixels and sizes remain byte-identical. This is a memory tradeoff for original-resolution badges, not a performance guarantee.
- Pending/refused core uploads and older local art without badge/coverage data retain the vector footprint. Repeated zoom/refusal/kind changes reuse the cursor's two badge labels and cached Content. Missing/partial optional rules retain a safe HQ/facility sizing fallback; the normal controller supplies the actual rules. Cancellation, external teardown and restart keep the existing cursor lifetime handling.
- Verification: 16 focused Luau tests pass, including four new badge cases; changed Luau files compile (syntax only), exporter syntax passes and ten Python packer tests pass. The real Luau inflater decodes both updated pages. All 121 Coalition and 100 Republic prior crops are byte-identical, semantically bound to their prior look fields and surrounded by verified non-overlapping transparent guards. An unchanged original My reference checks fourteen full-colour tokens: split-layer alpha differs by at most 1/255 and premultiplied RGB by at most 1.993/255 from the single SVG raster. Native compositing/filtering remains APPROX. Both valid/refused badge sheets and four mocked renderer-tree contact views were visually inspected; these are not native screenshots. Rojo build succeeds. Final combined suite: 655 passed, 0 failed. Studio/player checks B261-B263 remain pending.
- Remaining: placed-building far counters/badges and broader HUD parity, full hover/refusal pixel compositing, fallback piece-drop accents and projected height-band shadows. No claim is made that every building LOD or UI element is finished. The separate cross-server lobby backend was suggested as an isolated Claude task, with integration left for review. Power infrastructure stays removed, burned map houses remain ruined until the next match, and paid skins remain LAST. Nothing was committed or pushed.

## Cross-server directory integration and match browser (2026-11-12)

- Reviewed and connected Claude's separate LobbyDirectory backend. Server startup enables an admission gate before match remotes appear, starts the existing Saddle match and supplies a read-only live state provider. Match Join waits for arrival, re-reads seating after yielding, counts only human sides 1/2 and leaves full/finished admitted arrivals as spectators. Denied, disconnected or timed-out arrivals never enter snapshot membership. Seats/departures request a new heartbeat; existing bot takeover behavior remains.
- APPROX port status policy: opening deployment is waiting, completed deployment is inProgress, and a winner/draw closes the listing. In-progress matches still accept available sides. This is a directory label on the existing automatically running skirmish, not a traced original lobby/start rule or a new ready phase. Hosting/ready/start controls, creating new matches, map/army selection, invitations and reserved-server provisioning remain future session work; this batch provides discovery/joining.
- Added a Matches button and responsive modal browser with open-seat, host-friendship/friends-only, waiting-stage and map filters, manual/automatic refresh, current-server identification and useful join/failure feedback. Polling stops when closed; old replies cannot overwrite new filters or reopen closed/destroyed UI. Joining is single flight, late failures override pending success feedback and timeouts allow recovery. Native UI owners, notice handlers and polling disconnect on teardown. Opening cancels building/mine/trench placement, blocks match orders and prevents fresh placement hotkeys until closing. The match continues; no EditableImages are allocated by the UI. Menu styling is APPROX port UI rather than original-menu parity.
- Corrected native sorted-map pagination to {key, sortKey} cursors and switched to IsFriendsWithAsync; see the official links in LOBBY_DIRECTORY.md. Destination arrivals now claim seats atomically too, with holds retained until the match handshake actually seats the user. Current local state is read inside heartbeat/arrival UpdateAsync retries. This prevents a mere PlayerAdded or an older captured player count from freeing a held seat. Direct arrivals and teleported arrivals share the same reservation accounting.
- Arrival rechecks current privacy/stage before honoring holds. A later privacy restriction cannot be bypassed by an earlier hold, and valid local privacy still applies during store outages. Public fallback remains playable through match seat limits. Friends filtering resolves public configured hosts too, and transient friendship errors are not cached as negatives. Ordinary skirmishes currently use hostUserId=0/public visibility; hosted controls are not exposed in the browser.
- Added in-flight join/read guards, same-filter-only browse caching and request-id correlation for TeleportInitFailed. Removed automatic native retry so an old attempt cannot release a later hold; immediate/asynchronous failures return seats and retain useful retry feedback. Browsers hide stale keys without deleting someone else's potentially refreshed listing; owner close/TTL perform deletion. Close guards prevent an in-flight heartbeat from republishing a closed listing. Subscription, native connections and remotes have explicit cleanup.
- Studio keeps local admission/play and shows that global matches are available in Roblox Player; the adapter makes no directory reads/writes or teleports there. Published-server API quotas, actual friendships, teleports/reserved routes, last-seat concurrency, clock agreement, shutdown and real UI/performance remain unverified. No native Studio/player session or publish was run. docs/LOBBY_DIRECTORY.md now describes the integrated behavior and preserves a twelve-part published test checklist; B264-B266 are pending.
- Verification: 72 focused tests pass (64 lobby rule/service/match/browser/adapter cases plus eight placement-controller cases). Actual match Join and browser UI callbacks execute against stand-ins; the real adapter runs against strict API-shaped fakes, including a second range page and correlated failure options. Existing admin, art and rendering tests were preserved. Final combined suite: 720 passed, 0 failed; Rojo build succeeds. All installation writes used concurrent-edit hash guards and the runner guard verified every existing line survived. No original assets, simulation numbers or art pages changed in this batch. Nothing was committed or pushed. Paid skins remain LAST; removed power infrastructure and match-lifetime burned-house ruins remain as requested.

## Published-player startup and image-access failures (2026-11-12)

- After the owner's reported published-player image-access issue was fixed in settings, reviewed the remaining failure paths. MapRenderer's baked strips were protected, but its simple image fallback could still throw during pixel writes/Content binding and abort client initialization before camera, HUD and snapshot listeners started. Ground image preparation/publication now runs as one guarded operation. Failed strips, failed simple images and partial GUI owners release immediately before the existing queryable Part terrain fallback is built; successful ground images release on map teardown. Original colours/art/layout and gameplay numbers are unchanged.
- ImageMemory now recognizes the reported engine message, "EditableImage is not accessible", on creation, method lookup, direct bootstrap writes and queued writes. It latches that specific permission denial for this client session, explains the creator setting once and stops later native create/write attempts and unnecessary detail reclamation. Already queued jobs still report failure through their normal callbacks; unrelated write failures retain their existing retry behavior. Ordinary memory refusals are not treated as permission denials. The initial engine refusal may still be logged by Roblox; this change prevents repeated native probes, not the first engine diagnostic.
- The shared adapter exposes a safe pre-display write path, access-failure diagnostics/subscriptions and an accessDisabled pressure flag. Startup ground uses this path; normal displayed-image writes retain the existing shared render lane. The HUD gives a short player-facing notice if the creator must update the experience. This is a Roblox port diagnostic, not original-game UI. No new images, atlas pixels, original assets or image-budget limits were introduced.
- Server snapshot and periodic private-state production now wait for the existing per-player viewReady handshake. Slow or failed client setup therefore does not fill unhandled RemoteEvent queues or build unused viewer payloads. Once both client listeners are attached, the ready notification goes directly through the intent remote even if the Matches modal is blocking gameplay orders. The first ready message resets that player's presentation caches; duplicates do not replay initialization. Spectators use the same handshake, unknown players cannot enable streaming, and transient events from before readiness are not replayed as historical effects.
- Configuration remains necessary for original artwork: enable Allow Mesh / Image APIs in Studio Experience Settings > Security (or Enable Mesh / Image APIs in Creator Dashboard Configure > Settings), save/publish as appropriate and rejoin. See [Roblox EditableImage access](https://create.roblox.com/docs/reference/engine/classes/EditableImage). A Part fallback keeps initialization alive but does not reproduce the original textured map or establish acceptable native performance. This batch does not change the experience's settings or publish it.
- Verification: 16 focused tests pass (four changed runtime files compile, syntax only), exercising actual adapters/ground construction/handshake code with native stand-ins. Cases cover blocked create/write/method lookup, one diagnostic, draining queued callbacks, generic retry, partial strip failure, broken pixels/Content, ownership cleanup, 1,000 unready snapshot/state cycles, spectator/unknown-player handshakes and modal-safe readiness. Final combined suite: 733 passed, 0 failed; Rojo build succeeds. Studio/player checks B267-B269 remain pending. No native session or permission toggle was run; no commits/pushes were made.




## Original construction-piece fallback (2026-11-12)

- Added the source shuffled piece assembly when a building's optional height-construction image is pending, refused or reclaimed. The existing yard phase and normalized raising interval remain intact. Piece order is deterministic per structure ID, completed cells stay grounded, and only the next cell drops/fades with the source glow outline and dashed ground scaffold. Shuffle/drop/fade settings are extracted from the owner's local original into ignored metadata; original code, source tables and reference fixtures are not added to public files.
- Every piece samples the existing faction core atlas with separate body/paint layers and current team colour. Integer UV partitions intersect the original trimmed frame without losing or duplicating any source pixel. No EditableImages, atlas pixels, per-colour buffers or native upload work are added. All compressed core/weapon/SAM/artillery bytes and page dimensions match the previous batch; the faction core total remains 8,093,696 RGBA bytes.
- Detailed construction publication clears the fallback within the same upload callback, and image reclamation restores it immediately. The finished body stays hidden during that handoff. Fog, offscreen expiry, completion, GUI destruction and restart release the native owners; unchanged poses reuse their labels. APPROX native policy: at most eight fallback sites, favouring focus/importance, with cells at least two screen pixels wide; others retain the existing blueprint. Scaffold paths cap repeats per edge. These bounds are not a native frame-time guarantee.
- APPROX rendering differences remain: integer UV partitions replace fractional Canvas2D crops, native transparency replaces additive glow, and the shared body/paint view omits moving mechanisms from unfinished pieces (they appear at completion). This is the source piece fallback rather than the preferred height-band construction raster. Native subpixel edges, alpha and painter order still need Studio/Player review.
- Verification: 43 focused tests pass, including nine new cases; four changed Luau modules compile (syntax only) and exporter syntax passes. Unchanged original-JavaScript shuffle/drop functions match 192 cases across 21,936 numeric checks. Six actual fallback-renderer UI poses were captured with stand-ins, rasterized and visually inspected for both armies; these are not native screenshots. Final combined suite: 742 passed, 0 failed. Rojo build succeeds. Native checks B270-B272 remain pending. No native session, commit or push was performed.
- Remaining building presentation includes placed far-zoom badges/counters, broader HUD parity, full hover/refusal compositing and projected height-band shadows. Power infrastructure stays removed, burned map houses remain ruined until the next match, and paid skins remain LAST.

## Original placed-building badges and zoom handoff (2026-11-12)

- Added original placed-building tokens at far zoom, using the source team-filled shields/defence badges, neutral colour, unfinished alpha, token sizing and zoom fade. The source numbered counters belong to unit groups; this batch does not invent building counts or expose production queue contents. Full building art replaces the tokens over the source transition interval. At close zoom remembered buildings remain symbol-only fog markers with source corner brackets, rather than displaying live body/weapon/status information.
- Source construction bars appear only for the viewer's unfinished structures above the source far-detail threshold. Known live damage uses the original health tolerance, bar size, position and healthy/contested colours. Fog memories show neither bar. Current match rules and viewer side are configured from the existing client rules object. Existing focus/hover numeric labels remain an APPROX port aid; idle names/bars no longer crowd the source tokens. Oil rigs keep their existing presentation and input/targeting authority is unchanged.
- Tokens use a ScreenGui below placement guides/cursor/HUD, projecting at render cadence and reusing unchanged poses, labels and one cached Content reference. Live status, ownership, zoom, atlas and detailed-art admission changes invalidate the relevant pose. No per-building or per-colour image is created. Far sites defer detailed body/optional weapon loading; a complete badge remains while body art is pending. Source size/alpha formulas are retained, while this admission fallback is an APPROX port policy. Offscreen/behind-camera/missing-camera owners hide, replacement/removal and external GUI destruction release owners, and restart disconnects both the render and presentation callbacks.
- Building UI alpha is restored before existing animation/presentation code writes its next pose and multiplied afterward. This avoids alpha accumulation and CanvasGroup/per-building render textures. Asynchronous construction publication/reclamation follows the same ownership boundary. Full-opacity and hidden views do not scan descendants for alpha changes; partial transitions still need native frame-time measurement. Site/factory/weapon/dish/night/shadow details continue through their existing shared images and pools.
- The local exporter now extracts placed-token/bar/fog styles and emits filled/foreground/ghost layers alongside placement layers. The packer moves all token layers out of duplicate faction cores into one shared required core page, 512x636 (1,302,528 RGBA bytes). Body cores return to 1024x892 and 1024x813 (6,983,680 bytes total). Combined body/token core storage is 8,286,208 bytes, an increase of 192,512 bytes (188 KiB) versus the previous batch. This adds one shared native image while shrinking both faction images; it is a measured storage tradeoff, not a guarantee that every device admits all images. Placement previews use the same bank and retain compatibility with older embedded badge metadata.
- All existing building art, effects inputs, moving-part metadata and old placement layers retain their exact original pixel crops/offsets after repacking. Optional weapon/SAM/artillery pages remain byte-identical. APPROX native differences include split-layer alpha/filtering versus a single Canvas2D token, rectangular mitered bracket rasterization, per-layer full-art compositing and no original night-vision ghost-retention modifier. Standalone HQ flag poles, operational warning badges, ground symbols, selection/hover parity, projected height-band shadows and numbered unit-group counters remain future work; this is not complete HUD parity.
- Verification: 45 focused Luau tests pass, including thirteen new cases; seven changed runtime/shared Luau files compile (syntax only), exporter syntax passes and ten Python packer tests pass. An unchanged original drawStructures method plus sizing helpers matches 704 cases across 4,976 checks for sizes, fades and bar geometry. All three new core pages decode through the real Luau inflater; 139 Coalition and 118 Republic crop bindings (including relocated placement layers) match prior pixels/offsets, and all atlas guards are verified. Twenty-four original full-token/ghost raster comparisons differ by at most 2/255 alpha and 2.675/255 premultiplied RGB before native filtering. Badge sheets and four actual token-renderer UI tree captures with illustrative shared body art were rasterized and visually inspected; these are mocked previews, not native screenshots. Final combined suite: 755 passed, 0 failed. Rojo build succeeds. Studio/Player checks B273-B275 remain pending. Nothing was committed, pushed or published; no native session ran.
- Power infrastructure stays removed, burned map houses remain ruined for the match, cross-server lobby live-service checks remain pending, and paid skins remain LAST.

## Projected player-building height shadows (2026-11-12)

- Replaced the preferred flat translated silhouette with the original building height-band projection. Source band masks and individual reach values are extracted from the local building sheet; coloured body/paint/yard pixels never enter the shadow input. Source Yd angle/reach quantization, stepped extrusion, symmetric margin, source-in ink, opacity/night fade and downscale-versus-close sampling choice are traced from the original. Taller structures now project farther than low walls as the sun/moon changes. Moving gun/launcher/dish shadows keep their existing adapters; this batch concerns the fixed building height bands, not every shadow in the world.
- Matching source art shares one projected variant across all instances, including faction tables that reference the same original art. Each variant retains its last fully published pose while newer sun geometry prepares. A complete upload changes all attached labels in the same callback; failed/refused uploads never display partial pixels or blank an existing pose. The original raised-only union mask remains the memory/admission fallback. Fog, unfinished sites, far badge-only views, offscreen expiry, destruction and restart hide/detach the relevant shadow owners and reject obsolete work/callbacks. Existing zoom alpha is restored around asynchronous publication before reapplying the current fade.
- APPROX native policy: one optional 768x768 detail image (2.25 MiB), nine shared variants, six decoded CPU mask sources and a stored resolution cap of 252 pixels inside each guarded 256-pixel slot. Full source world extent is retained; large shadow canvases are sampled into the capped raster. Focus/hover/importance can replace lower-priority variants; other sites retain the simple mask. Source-over alpha uses integer CPU rounding and nearest mask samples instead of Canvas2D subpixel rasterization. Native filtering and projected edges are not claimed pixel-identical.
- Shadow decode/raster/padding yields through the existing soft presentation deadline after core preparation and construction/damage work, then uses the shared upload lane at lower priority. The shadow image reclaims before other structure effects under core-art pressure, admission/refusal retries are throttled and no per-building image is allocated. Far representations stop retaining variants immediately; an empty canvas has a 0.5-second idle grace to avoid allocation churn during rapid zoom changes and remains reclaimable under pressure. Source masks stay CPU-only in the ignored local module; every existing body/badge/weapon/SAM/artillery image byte and dimension remains unchanged. Cached older private exports missing projection opacity settings safely retain simple shadows.
- Verification: 37 focused tests pass, including eleven new cases; three changed Luau modules compile (syntax only), exporter syntax passes and eleven Python packer tests pass. The unchanged original Yd function matches 48 canvas geometries across all eight tested source kinds and six sun vectors. Three actual mask projections were rendered and visually compared with original Canvas2D references: opaque-mask overlap is 96.7%-99.4%, with mean absolute alpha difference 0.257-1.233/255 before native display. These three CPU/reference composites are not Studio screenshots. Headless decode/prepare/raster samples took roughly 11-18 ms total per variant and are split across cooperative slices in game; these timings do not establish native frame performance. Final combined suite: 766 passed, 0 failed. Rojo build succeeds. Studio/Player checks B276-B278 remain pending. Nothing was committed, pushed or published, and no native session ran.
- Remaining presentation includes standalone HQ flags, operational/ground symbols, selection/hover fidelity, broader HUD and original numbered unit-group counters. More extensive native shadow quality/performance tuning remains subject to the checks below. Power infrastructure stays removed, burned map houses remain ruined for the match, live cross-server service checks remain pending, and paid skins remain LAST.

## Original building damage warnings and close ground symbols (2026-11-12)

- Added the original damaged-facility status icon on its backed disc for the viewer's own stopped facilities. A small optional snapshot field 17 carries port presentation bits: 1 for the authoritative own damaged-facility reason, 2 for currently visible demolition. Existing production/weapon/artillery positions remain unchanged and missing slots are padded with false only when a marker tail is needed. Enemy operational reasons are never queried by this marker sampler, hidden/stale rows receive no live marker flags, and older server rows clear the client state. This does not expose queues or alter damage/repair/combat rules.
- Added source type symbols beside buildings at close zoom using the existing unoutlined shared glyphs. Original zoom threshold/fade, footprint-relative size, gap, absolute pixel rounding, shade offset and night fade are traced from drawGroundLabels. Remembered or demolishing sites omit ground symbols. An early transparent sibling in the building SurfaceGui keeps the symbols behind later shadow labels; existing input/query parts are unchanged. Symbols reuse two labels and cached Content, without per-building images or coloured buffers.
- The damaged icon is extracted from the local original SVG dictionary and packed into the existing shared token image, now 512x699 (1,431,552 RGBA bytes). Combined body/token core storage is 8,415,232 bytes, an increase of 129,024 bytes (126 KiB) with no additional native image. All 45 existing badge bindings retain byte-identical pixels/offsets after repacking, all 33 crops have verified transparent/non-overlapping guards, and body/weapon/SAM/artillery pages remain unchanged. Ground symbols add no atlas art. Missing/older metadata safely omits the new accents.
- Verification: 42 focused Luau tests pass, including eight additions; seven changed runtime/shared Luau files compile (syntax only), exporter syntax passes and eleven Python packer tests pass. Unchanged original ground/status drawing methods match 540 cases across 1,512 checks, including night, visibility and demolition. Tests exercise the actual server view/row builder and native stand-ins for client ownership/fog clearing, label reuse and shared atlas binding. Four actual renderer UI trees with shared body art were rasterized and visually inspected; these are mocked previews, not Studio screenshots. Final combined suite: 774 passed, 0 failed; Rojo build succeeds. Native checks B279-B281 remain pending. Native circle/filtering/compositing, SurfaceGui axes and sibling/depth order remain APPROX until reviewed in Studio/Player. No commits, pushes or publishing were performed.
- Owner priority update: barrages and flares already work, but clicking an owned artillery base must open its controls and then allow targeting. Fix that selection/action flow before more decoration. Combat animation polish follows: audit existing infantry firing, weapon effects and vehicle/artillery sequences against the original and fill confirmed gaps. Broader milestones remain remaining artwork/world details, gameplay parity audit, UI/audio, multiplayer/session flows and native release testing; cosmetic skins/monetization stays LAST. Power infrastructure stays removed and burned map houses remain ruined for the match.


## Cooperative town loading for Player CPU spikes (2026-11-12)

- Owner reports area-loading lag in Roblox Player with a screenshot showing 113.4 ms current CPU and 50.91 ms average. This identifies a frame-time problem, not a measured attribution. Code review found synchronous cold LOD signature/base64/inflate/lighting and full-source fallback work inside Heartbeat, with the old 6 ms presentation budget checked only after decoding returned.
- Static cold loads, optional LOD validation/decode, full source upgrades, daylight patching and mip resizing now share the existing single cooperative terrain worker. Base64 and Adler loops accept optional checkpoints, and LOD patch validation/application forwards them. Worker loops target 2 ms slices, with at most one resume per Heartbeat. Initial overview decoding/sampling yields as well. Cached intact pixels are cloned and their old reversible patch undone when relighting instead of reinflating the source every time. Existing art, lighting, rules and source resolution remain unchanged.
- Offscreen prefetch can prepare optional LODs through the same worker but never falls back to synchronous full-source decoding. Camera-visible fallback and fire work retain the core overview/last completed image until pixels finish. Cold LODs, damage and light epochs are rechecked before resuming; teardown discards pending work. Downshifts retain prepared pixels before retiring an image, preventing asynchronous preparation from stranding a transition. Lower mip fallbacks are prepared ahead of native admission and coarse CPU caches remain bounded. Diagnostics expose lastSliceMs and maxSliceMs through TownRenderer.stats().
- These are soft CPU budgets: engine image creation/upload, ModuleScript compilation, allocations/GC and other renderers can still cause stalls. One terrain job also means other cold chunks may wait behind a fire update; they retain overview coverage. This batch does not prove the entire reported 113 ms spike was terrain work or establish native Player frame time.
- Verification: 48 focused tests pass, including six new regression cases and updated scheduling expectations. Tests poison presentation-thread decode/resize calls and exercise yielded cold LODs, stale fallbacks, lighting, resizing, memory downshifts and teardown. Real private 896x896 town pixels remain byte-identical: one headless LOD sample took 6.21 ms synchronously versus four cooperative slices with a 2.32 ms maximum (6.42 ms total); full source + light patch + half reduction took fifteen slices, 2.13 ms maximum, 29.45 ms total. These local Lune timings are illustrative, not Roblox measurements. Full suite: 780 passed, 0 failed. Changed modules compile (syntax only); Rojo build succeeds. Native checks B282-B284 remain pending. No native session, publish, commit or push was performed.
- Audio roadmap clarified by owner: eventually port original weapon fire, impacts/explosions, vehicles, building/construction/destruction, weather, ambient and UI sounds. Future work includes tracing event triggers and original mixing/pitch, preparing private source audio plus Roblox asset bindings, spatial/distance/zoom attenuation and bounded voices with priority/stealing/deduplication for large battles. Native published audio permissions, loading, overlap and performance need validation. No sound assets or playback were added in this CPU batch. Audio remains before the final cosmetic skins/monetization milestone.
- Priority remains Player performance, click-selected artillery controls, then source-confirmed combat animation gaps. Removed power infrastructure and match-lifetime burned-house ruins remain as requested.


## Click-selected artillery base commands (2026-11-12)

- Fixed the owner's requested interaction: click an owned artillery base to open a dedicated barrage/flare card. Each action uses the current match rules for kill price, and private per-base readiness/cooldown/reason state. Choose the action, then click a ground target; right-click/Escape or the card cancel button leaves targeting. Out-of-range clicks retain the targeting mode with feedback. Lost ownership, destruction, fog memories, match end, opening deployment and modal/placement interaction disable the relevant actions. Existing provisional comma/period hotkeys remain compatible.
- Armed world clicks do not begin selection drags, issue move/attack orders or select another building. Processed UI clicks stay with the UI, and drags begun before a modal/target mode cannot finish as stray selections. Selecting units/another building or using control-group recalls updates the card. Artillery roof/ground footprint corners also accept clicks at close zoom in addition to the old centre tolerance; this is APPROX port hit testing and needs native screen-axis review.
- Optional power fields structureId/requestId are validated as positive finite integer artillery-only fields; legacy powers without them retain their previous behavior. Explicit base requests call the existing authoritative sim.artyStrike for exactly that id, with no nearest-base substitution. Existing ownership, construction/damage, range, kills, cooldown and outcome rules are unchanged. A correlated private result clears the in-flight action and reports refusals. Old/unrelated acknowledgments cannot finish a later request. APPROX UI policy: a five-second no-reply timeout permits retry; every retry remains server-validated.
- Private state adds own alive artillery rows {id,barrageWait,flareWait,inactiveReasonOrFalse}; enemy/dead bases are omitted. The existing aggregate ready waits remain restricted to working own bases for the HUD/hotkeys. The card uses native text/buttons only, with no image allocation; owners disconnect/destroy on restart/external teardown. Its responsive bottom-centre layout and notices are a port UI, not a traced original-menu replica.
- Verification: fifteen focused tests pass, including pure UI/protocol state, actual server intent dispatch/private-row logic and actual native panel/selection callbacks with stand-ins. Six changed/new runtime modules compile (syntax only). Final combined suite: 795 passed, 0 failed; Rojo build succeeds. Native checks B285-B287 remain pending. No native session, publishing, commit or push was performed.
- Next visual work: audit original infantry weapon/firing and vehicle/artillery action sequences against existing effects and fill confirmed gaps. Original audio remains planned across combat, vehicles, buildings, weather, ambience and UI with bounded overlapping voices; no playback was added here. Skins remain LAST, power infrastructure stays removed and burned map houses remain ruined for the match.


## Original mortar loading and AT crew reload poses (2026-11-13)

- Combat animation audit confirmed two missing source crew actions. Mortar bearers now move to the original loading position, turn toward the tube and use their existing load sprite during the final 0.6 seconds of reload while firing. Tube kick, post-shot duck, setup/packing and movement retain source precedence; moving to the loading spot can use the existing walk cycle before settling. AT loaders face the surviving gunner while firing with more than the source 0.7-second ready threshold left, then face the target again. These are cosmetic changes; fire rates, aim, range, damage and reload rules are unchanged.
- Visible AT/mortar rows optionally append field 19: {reloadRemaining,phaseCode,phaseProgress,matchTime,runningBit}. Existing fields 1-18, including fleeing-civilian combat age, remain unchanged. Hidden units never reach this sampler, dead/other kinds emit no tail, and visible enemy crews show only their observable current action. Current source setup/packing progress is derived from authoritative still/packAt state rather than restarting deployment locally on first sighting.
- Client crew clocks stop predicted reload, shot age and deployment progress while the reported match clock is paused. APPROX prediction is capped at 0.2 seconds if snapshots stall, consistent with other weapon clocks; network transit delay and corrections are not an exact synchronized replay. Older rows clear their previous crew sample and retain existing local phase estimation without the new reload actions. Removed/fogged unit owners discard the state through existing view destruction. No new images, sprite pages, source art, per-shot render owners or native input handlers are introduced.
- Verification: eleven focused regression tests pass. They exercise readiness thresholds, pose precedence, observed deployment progress, bounded/pause prediction, legacy clearing, actual server view privacy/row shape and the actual client snapshot/crew-placement functions. Unchanged original phase code matches 720 samples; original reload conditions/pose branches match 180 actual stationary crew poses. Four changed/new runtime modules compile (syntax only). Five pose views were rendered with real private sprite crops and visually inspected; this is a CPU preview, not a native screenshot. Final combined suite: 806 passed, 0 failed; Rojo build succeeds. Native Studio/Player checks B288-B290 remain pending. No native session, publishing, commit or push was performed.
- Further combat presentation still needs auditing/filling confirmed gaps (including infantry blast reactions/prone movement and vehicle weapon actions) against the source. This batch does not claim complete combat animation parity. Original combat/world/UI audio remains planned with bounded sound overlap; paid skins stay LAST. Power infrastructure stays removed, map houses stay ruined for the rest of the match, and Player terrain-performance comparisons remain pending.


## Zoom-dependent unit sprite image quality (2026-11-13)

- Implemented the owner's proposed memory saving as actual smaller native images, rather than merely shrinking full-resolution sprites on screen. SpriteBank families now choose original, half-width/height or quarter-width/height images from projected camera zoom and source frame size. Vehicle bodies/paint/turrets, soldier figures/poses, deployment states, wreck/soot art and vehicle rim/shadow sheets participate. Town/map detail retains its existing LOD system; separately managed cropped ManEffects masks and building/effect banks are outside this batch.
- All facing/pose/strip coordinates and world footprints remain at original logical resolution. A shared binding owner scales UVs to the resident native sheet and updates every registered body/paint/effect/wreck label together after a complete upload. Cached handles keep their identity, colours, geometry and animation state. Old images release only after successful publication; failed creation/write/Content binding retains the previous complete sprite, with label rollback if publication fails. Destroyed/rebound labels leave their old page; reclamation cancels pending work.
- APPROX quality policy uses projected frame pixels, hysteresis and a 0.3-second stable-tier delay to avoid threshold oscillation. One cooperative replacement worker targets 2 ms slices, and only one replacement native image may await upload globally. CPU pixel buffers are not retained after the upload lane releases them. Close zoom restores original images when admitted; image refusal retains the existing coarse tier and retries later. Far first-use pages directly admit their precomputed smaller sheet. Missing/stale derivatives fall back to an available tier/source instead of blanking art. Screen-space estimates use the ground plane and shared source-kind geometry, not separate textures per unit.
- Added pack_sprite_lods.py and integrated derivative generation into future pack_original.py repacks. All 288 new local modules (two derivatives of 144 existing sheets) stay in ignored DevAssets. Source module contents were preserved and guarded against concurrent repacks. Per-facing frame boundaries remain aligned; alpha-weighted reduction preserves edge colour without introducing black transparent borders. Runtime source signatures reject stale converted sheets. These are trusted local asset consistency checks, not cryptographic authentication. Compressed module strings/metadata can remain in Roblox's require cache; the measured saving below concerns resident RGBA image storage rather than all CPU/process memory.
- A half-size sheet uses 25% of its full RGBA storage; a quarter-size sheet uses 6.25%. An actual SpriteBank headless run with original tank/body masks and rifle art used 6,711,296 bytes at original dimensions versus 419,456 bytes at distant zoom (93.75% less). Zooming in restored all four source-sized images, and zooming back released them again. One-transition peak in that sample was 6,941,696 bytes. This does not predict total device memory. Maximum measured preparation slices were about 7 ms despite the 2 ms soft target: native/VM allocations, module compilation, GC and native upload work are not preemptible by Lua checkpoints. First-use loading still uses the existing synchronous admission path, but can decode a much smaller sheet at far zoom.
- Verification: fifteen focused Luau regression tests and seven Python packer tests pass. They exercise quality hysteresis, complete crop rebinding, stale uploads, failed/refused publication, rollback, pending-image bounds, cancellation/cleanup, RLE checkpoints, real bank cold tiers/zoom restoration and stale-asset fallback. Every generated module decodes with valid dimensions and matches the current source signature. Four changed/new runtime modules compile (syntax only); both Python tools compile. A contact sheet of four real tank facings at three intended display sizes was rendered and visually inspected; this is a CPU preview, not a native screenshot. Final combined suite: 821 passed, 0 failed. Rojo build succeeds. Native checks B291-B293 remain pending. No native session, publishing, commit or push was performed.
- Original combat/world/UI sounds and remaining source animation gaps stay planned; paid skins remain LAST. Removed power infrastructure and match-lifetime burned map houses remain as requested.


## Visible-blast infantry flinch and prone recovery (2026-11-13)

- Added the original living-soldier blast reaction: a nearby qualifying blast makes an existing visible soldier briefly hold prone, then kneel during the source recovery interval before returning to formation/aim. Source minimum size, reach/slack, hold/jitter, rise interval and backward prone anchor are retained. Already reacting soldiers do not extend their reaction on each new explosion, dead men are ignored and restored squad members clear old reaction state. Walking, mortar loading/setup and AT reload poses retain their normal behavior after recovery. Garrisoned/transported squads are excluded from this outdoor reaction. Orders, movement authority, fire rate, hit chance, cover and damage rules do not change.
- The existing authoritative land-impact bridge now emits transient cosmetic blast samples using original FireRules weapon sizes or existing explicit sizes. It remains available when environmental-fire features are disabled, without activating disabled fire/ground systems. Weapon bullets/small profiles, unknown sizes and water-only impacts excluded by that bridge emit no reaction pulse. This covers impacts/demolition/vehicle/structure pulses already routed through sim.worldBlast/WorldFireImpacts; not every unported visual-only delayed cookoff, water/nuclear branch or casualty throw. Projectile/muzzle/impact presentation and thrown bodies remain separate unfinished work.
- Snapshot arguments 8/9 optionally append visible blast rows and the match clock/running pair; previous arguments and unit row fields remain unchanged. Ready-view admission still applies and the queue clears even when nobody is ready, so a slow loader cannot receive a backlog. Server and current client fog both filter blast sources before reactions. Public event IDs count only that viewer's visible rows within the snapshot, preventing hidden explosion counts leaking through global sequence gaps. Old client/server tails remain compatible. Newly revealed views without a prior squad do not replay reactions from earlier unseen soldiers.
- APPROX port budgets: retain at most 64 newest qualifying events per snapshot, accept blast sizes up to 64, and use pooled eight-cell bins with reused entry/bucket tables. Eligible soldiers are removed from the working search after they react, and pooled entries release squad/man references at the end of the packet. No new textures, particle owners, image decoding, native input hooks or extra render callbacks are added. Source poses work through the existing sprite LOD bindings. Excess cosmetic pulses can be dropped in extreme battles; simulation impacts are never dropped by this presentation cap.
- Reaction clocks pause with the authoritative match clock and predict at most 0.2 seconds through missing snapshots. APPROX transport handling anchors expiry to the server impact timestamp and ignores expired/far-future samples rather than restarting an old reaction after a network delay. Transit/correction timing and native interpolation are not an exact original replay. Individual visual men can pause/catch up while the authoritative squad continues its order, as in the source drawer; this is not gameplay suppression.
- Verification: 25 focused tests pass (14 new reaction/transport/renderer cases plus 11 existing crew cases). Tests cover reach boundaries, deterministic expiry, pose precedence/recovery, revive clearing, pause/stall clocks, hidden/unready/duplicate events, public-ID privacy, actual source-size bridge and client/server snapshot functions, prone body/shadow anchoring and garrison exclusion. Seven changed/new runtime modules compile (syntax only). The unchanged original feel method matches 11,520 soldier expiry states across 30 scenes. A headless dense sample with 3,000 soldiers and 64 blasts checked 3,000 entries instead of 192,000 naive pairs and took about 2.65 ms; this does not establish native Player frame time. Four actual private-sprite pose views were rendered and visually inspected; they are CPU previews, not native screenshots. Final combined suite: 835 passed, 0 failed. Rojo build succeeds. Native checks B294-B296 remain pending. No native session, publishing, commit or push was performed.
- Further combat projectile/weapon actions, casualty presentation and original combat/world/UI audio remain on the roadmap. Paid skins stay LAST; power infrastructure remains removed, burned map houses remain ruined for the match and sprite/terrain native performance comparisons remain pending.


## Vehicle recoil translation and turret slide (2026-11-13)

- Added original firing recoil for tanks, IFVs, mobile artillery, rocket launchers and armed scouts. Hull art shifts backward along the observed shot direction, with the source signed damped 12 Hz recovery. Tank/IFV turrets slide along their current drawn bearing. Existing hull/turret shadows, rims and attached soot follow the same motion; selection, health/input anchors and authoritative movement remain fixed. Repeated IFV rounds and rocket salvo offsets retrigger the source pulses. No new textures, image owners, render callbacks, physics forces or gameplay rules were added.
- Optional visible unit field 20 carries an observer sequence, newly observed firing time/direction and bounded salvo offsets. Previous fields 1-19 retain their meanings; absent crew field 19 is padded false only when needed. Each side baselines first sight and reappearance after fog, so old firing does not replay or expose historical shot data. Rocket timing uses the simulation's existing pure seed/pattern helpers once per newly observed salvo without consuming gameplay RNG. The client reuses the shared snapshot war clock, accepts newly observed shots only within the source 0.25-second late window, freezes during match pause and caps missing-snapshot prediction at 0.2 seconds. Network arrival/correction remains APPROX rather than an exactly synchronized replay.
- Verification: 23 focused tests pass (12 new recoil cases plus 11 crew regressions), four runtime/shared modules compile (syntax only), and the full combined suite reports 847 passed, 0 failed. Unchanged original recoil functions match 1,350 poses across 5,400 numeric checks, including source body scaling, directions, signed recovery and uniform/irregular burst timing. Four real private tank-sprite poses were composited and visually inspected in a CPU preview; this is not a native screenshot. Rojo build succeeds. Studio/Player checks B297-B299 remain pending. No native session, publishing, commit or push was performed.
- This batch covers direct hull translation and turret slide. Full vehicle suspension/spring pitch and roll, hit jolts, broader muzzle/projectile/impact effects and remaining combat animation parity still need source auditing and implementation. Native appearance, packet cost and large-battle CPU/memory remain unverified. Original audio is still planned with bounded overlap before paid cosmetic skins/monetization, which remains LAST. Power infrastructure stays removed, map houses remain ruined for the match, and published cross-server service checks remain pending.


## Infantry rifle muzzle bursts (2026-11-13)

- Added rifle muzzle presentation for visible outdoor infantry and paratrooper squads: rotating living shooters, staggered bursts, a source star/hot-core flash, a small barrel wisp, ejected brass and occasional longer gun haze. Weapon-tip positions use the original per-kind/per-pose local offsets, aim slack, standing/kneeling/prone heights and existing backward prone anchor. Burst positions are captured independently of the moving squad, so already emitted smoke stays in the world. Existing figure poses and full/half/quarter SpriteBank bindings remain unchanged. AT backblast, mortar/vehicle muzzle effects, tracers/projectiles, impacts, extra lighting and other combat actions remain separate unfinished work.
- Reuses existing unit field 15 (capped public shot age), firing/aim/status fields and the shared snapshot war clock. No server, snapshot fields, simulation damage/fire/reload rules or gameplay RNG were changed. First sight, reappearance and leaving a garrison baseline previous firing; old/missing clocks clear pending presentation. APPROX observation policy admits only newly observed shots within 0.25 seconds, starts their cosmetic burst when a current pose is available, freezes future burst timing during match pause and caps missing-snapshot prediction at 0.2 seconds. Network timing is not an exact synchronized replay. The existing shared particle engine continues aging emitted particles on its presentation clock.
- Every scheduled muzzle rechecks current fog, the root-view check cancels garrisoned/fogged work, and hidden/removed unit views retain no deferred callbacks. Shared per-frame budgets allow at most 32 burst preparations and 32 muzzle pulses; expired or over-budget pulses are dropped rather than queued for later replay. The source gun-haze cap of 120 is shared across squads, expires in a bounded number list and counts only successful admissions. All primitives use the existing 512-particle pool and 96x96 atlas; there is no new image, per-unit texture, render callback or event listener. Allocation refusal stops optional emission. Added the original solid 4x4 px crop for brass and explicitly restores ordinary atlas crop sizes when a pooled slot changes texture.
- Added tools/conversion/export_rifle_fx.cjs to extract private rifle settings from the installed source, following its effects import/export aliases. Generated src/shared/GameData/RifleFx.luau stays ignored. Regenerate with node tools/conversion/export_rifle_fx.cjs <original-install> <project-root>; its output guard refuses writing inside the original install. The current source import/shape and presentation bounds are checked before writing. Missing local rifle settings omit these optional effects without blocking normal units or commands.
- Verification: 23 focused tests pass (12 new rifle cases plus 11 crew regressions), three runtime/shared modules compile (syntax only), exporter syntax passes, and the full suite reports 859 passed, 0 failed. Unchanged original muzzleOf/rifleBurst/manFlash methods match 336 schedules and particle sets across 30,760 comparisons. Regression cases exercise first-sighting/capped-age baselines, garrisons, delayed/pause/rollback clocks, current fog, independent muzzle captures, dense 3,000-squad budget admission, refusal/haze expiry and actual client/particle-renderer functions. Four actual private rifle-sprite poses were composited and visually inspected with the original shared atlas; these are CPU previews, not native screenshots. Rojo build succeeds. Native Studio/Player checks B300-B302 remain pending. No native session, publishing, commit or push was performed.
- Native filtering, additive glow/dither/erosion and world-height projection retain the existing particle renderer's APPROX behavior; the reference comparisons do not establish native pixel parity or frame performance. Original combat/world/UI sounds remain planned with bounded overlap, paid cosmetic skins/monetization remains LAST, power infrastructure stays removed, burned map houses remain ruined for the match, and published cross-server service testing is still pending.


## Tank and IFV muzzle effects (2026-11-13)

- Added distinct source firing primitives for tanks and IFVs. Tank shots produce the long star/hot core, fireball, expanding dome, directional sparks, immediate smoke and delayed evacuator gas. IFVs emit four smaller flashes at the source burst gap, two smoke components per pulse, side-ejected cases and a delayed post-burst breath. Existing source profiles, faction flash/fireball multipliers, particle colours and timings are retained. Ground/muzzle dust, ground rings/scorch, dynamic muzzle lighting, shake, tracers/projectiles and impacts are separate unfinished work; this batch does not claim the entire source tankBlast routine or combat VFX are ported.
- Muzzle ownership reuses the already accepted visible recoil sample and its sequence/shot time, with no second firing-event stream. Optional entry 5 of tank/IFV unit field 20 carries the public army string for faction-specific fireballs; its previous four entries, all other unit fields and snapshot arguments retain their meanings. Other recoil kinds retain their four-entry sample. Legacy/unknown army strings use coalition, and missing/invalid/revealed/reset recoil state cannot replay an old muzzle event. No damage, fire rate, movement, combat RNG or other simulation rule changed.
- Both recoil and muzzle schedules use the shared match clock. The first newly observed flash can use the existing 0.25-second observation window so a normal 10 Hz snapshot does not silently lose it; subsequent IFV rounds and delayed gas retain source shot-relative times and discard pulses more than 0.1 seconds overdue. Future pulses freeze during match pause and inherit the recoil clock's 0.2-second missing-snapshot prediction cap. These arrival/correction policies are APPROX network handling rather than exact original replay. Already emitted particles retain their existing presentation clock.
- APPROX native placement deliberately uses the currently drawn turret centre/bearing after body recoil and turret slide, with source gun reach and close-target clamping. Later burst/gas emissions follow that current barrel instead of leaving fresh gas at a vehicle's former firing position. The source's captured static event origin is retained only by already emitted world particles. Source and current muzzle fog are checked on every event; hidden roots discard pending work, and removed unit views retain no external callbacks or queue owners. Native depth/height/filtering, glow, erosion and smoke compositing still use the existing particle renderer approximations.
- Infantry and vehicle firing now share the same per-render-frame budget: at most 32 preparations, 32 due muzzle/gas opportunities and 128 native particle-request attempts. The existing 512-particle pool and one shared 96x96 atlas remain unchanged; there is no additional image, per-unit texture, render callback or native listener. Vehicle schedules hold at most five numeric events, refusal stops optional work, and over-budget/expired opportunities drop instead of becoming a backlog. A refused initial tank flash cannot leave an orphaned delayed gas puff. The existing 120-haze infantry cap remains intact.
- Added tools/conversion/export_vehicle_muzzle.cjs to extract private settings by following source import/export aliases; generated src/shared/GameData/VehicleMuzzleFx.luau stays ignored. Regenerate with node tools/conversion/export_vehicle_muzzle.cjs <original-install> <project-root>. Export guards reject output inside the original install and reject changed source method shapes or unreviewed particle-count bounds. Missing private settings omit optional muzzle effects while normal art, recoil and commands remain usable.
- Verification: 35 focused tests pass (11 new muzzle cases plus 12 recoil and 12 rifle cases); four changed/new runtime/shared modules compile (syntax only), exporter syntax passes, and the full suite reports 870 passed, 0 failed. Unchanged original vehicleFire/tankBlast/autocannon/gunFlash/puff/sparks/spentCase/barrelBreath methods match 192 stationary sequences and 672 firing phases across 118,080 checks, including full schedule replay and faction variants. Excluded source dust/scorch/light/projectile calls are explicitly stubbed in that private reference. Regressions also exercise legacy/public faction tails, fog, pause/stall clocks, current barrel placement, failed admissions, 3,000 simultaneous views, shared attempt limits and actual renderer functions. Four actual private sprite/atlas composites were rendered and visually inspected; these are CPU previews, not native screenshots. Rojo build succeeds. Studio/Player checks B303-B305 remain pending. No native session, publishing, commit or push was performed.
- Exporter compatibility follow-up: the current Steam bundle uses different minified aliases and adds unrelated AA-truck constant references. The reader now discovers configuration aliases from the actual method properties, selects only required object members and follows import/export bindings, avoiding evaluation of unrelated dependencies. All 95 baseline muzzle settings are identical in the current install. Six additional private exporter checks pass across the cached/current bundles, changed cadence, unknown method shapes, protected output paths and deterministic regeneration. Current source also exposes a freebrigades IFV variant; its third-faction dispatch remains separate future parity work and does not change the current coalition/republic profiles. The generated metadata reports that distinction.
- Next combat work includes AT backblast and mortar firing dust/smoke, artillery/launcher muzzle effects, projectiles/impacts, further original animation gaps and original audio with bounded overlap. Paid cosmetic skins/monetization stays LAST. Power infrastructure remains removed, map houses stay ruined for the match, and published cross-server service checks remain pending.


## EditableImage residency, pressure response and static-image package (2026-11-13)

- Implemented the five memory workstreams: real smaller soldier-effect atlases, off-camera sprite downshifts, pressure-adaptive quality/optional admission, native refusal suppression until tracked release, and an optional regular Roblox Image backend plus upload/ID import tools. Bodies and masks share one cooperative preparation job and at most one pending replacement image. Complete content rebinds before old images release. Core bodies retain existing art on refusal; optional masks may briefly hide to free the previous allocation. Existing terrain/fog protection remains.
- All 11 figure-effect families total estimated native RGBA storage of 8.52 MiB full / 2.64 MiB half / 0.97 MiB quarter if simultaneously resident. Generated 22 private derivatives and validated 10,112 crop mappings; an 11-family comparison was visually inspected as a CPU preview. These numbers are not total Player memory or measured match savings.
- Prepared the requested private package: 473 bindings share 368 PNGs (~11.7 MiB disk), with a blank ID template. The owner-run Open Cloud uploader defaults to no-network dry-run, saves operation paths before polling, resumes pending uploads without duplicate creation and rejects non-Image responses. No uploads, credentials, real asset IDs or publishing were used. The regular-image backend stays inactive until owner upload/import; regular textures still use ordinary Roblox memory. See docs/IMAGE_MEMORY.md.
- Added owner byte/count diagnostics, quality level, suppressed-attempt/release-epoch counters and external/offscreen residency counts. Unconfigured static lookups do no hashing/preload work; validated sprite variants cache once. No additional render loop is introduced. Policy ceilings are application choices, not Roblox device limits.
- Verification: 65 focused Lune checks pass (including 16 new residency/static-image cases and an adapter regression); 15 new synthetic package/uploader tests plus 9 existing mask/sprite-packer tests pass. All 44 staged runtime/shared/private derivative modules compile (syntax only). The full installed suite reports 887 passed, 0 failed, and the installed Rojo build succeeds. Native Studio/Player checks B306-B308 are not run; warnings, real CPU/frame time and ordinary texture behavior still require Player measurement.
- Power infrastructure stays removed, map houses remain ruined for the match, original audio remains planned and paid cosmetic skins/monetization stays LAST. No commit or push performed.


## Static Image upload and ID activation (2026-11-13)

- Completed the user-authorized Studio upload of all 368 canonical PNGs under jonathan343435, without an API key. Matched exact atlas names and Image types from native metadata, reconciled the full inventory and recent-upload export, and read the last pending-index ID from its completed import row. All 368 unique IDs pass strict validation; all 473 bindings, including canonical aliases, are installed in ignored src/shared/GameData/StaticImageIds.luau and build/static-images/image_ids.json. PNG hashes were checked and stale/conflicting IDs rejected before installation.
- The generated ID module compiles, all resolved entries have the expected dimensions/source signatures, Rojo build succeeds and contains exactly the installed private module. No renderer/simulation code changed in this follow-up. Start a fresh Play session after sync. Place publishing, native preload/visual/Player access and live memory/frame-time comparisons remain unverified; B308 now records upload/import as partial native coverage. No commit, push or place publish performed.


## Hosted Image native activation fixes (2026-11-13)

- Reconnected Studio's stale Rojo plugin connection and verified all 473 imported bindings in the actual place. Native tests identified bare URI-string preloads returning Failure while typed ImageLabel requests for the same uploaded/public control images succeeded. StaticImages now uses one temporary unparented ImageLabel per serialized preload, sets ImageContent, destroys it after success/failure and publishes only successful content. No new EditableImage, render loop or persistent UI is introduced; unavailable assets retain cooldown/fallback.
- Fixed StructureTokens and BuildPreview consumers to use hosted sheet Content directly. Their previous Content.fromObject calls received regular-image metadata proxies and caused repeated nil-content errors once the backend activated. Native fallback content and cached shared layers retain their existing behavior.
- Fresh Studio Play: 10/10 representative image samples loaded; the later live cache had 35 ready assets, zero failures/rejections, and 19 external resident SpriteBank pages with zero native bytes in that bank. Actual barracks previews passed distant/detailed/distant transitions (2/44/2 visible hosted layers), and 3 visible structure-token labels had hosted content. Temporary real client LocalScripts were used because the command-bar module cache is separate; probes were removed on stopping Play. This does not measure total process memory or prove all 368 images/large-battle/Player behavior.
- Verification: 38 focused tests and the full 894-test Lune suite pass; three runtime modules compile (syntax only), and installed Rojo build succeeds. Seven added regressions cover typed preload serialization/cleanup/errors and hosted/native token/preview content. B308 records the sampled native coverage; exhaustive native filtering, published-player permissions and B306-B307 pressure/performance checks remain pending. Legacy place bootstrap waits and unrelated plugin warnings remain outside this change. No place publish, commit or push performed.
