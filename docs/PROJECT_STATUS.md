# PROJECT_STATUS: WarFront Roblox port

Last updated: 2026-11-10

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

