--!strict
--[[
	SquadMen: places the soldiers of one infantry squad, after the game's squad drawer (its Ml table and
	place()). Plain data, no Roblox, so the tests can run it.

	From the game:
	  * roster: infantry = leader, rifle, rifle. Men standing = ceil(hp / maxHp * men), at least 1; when
	    one goes down the game picks a rifleman (never the leader) by a hash of the unit id.
	  * formation slots (in spacings, x forward, y right): moving = wedge (file on a road), firing = line,
	    otherwise loose with a hashed jitter (looseJitter); spacing 0.6 cells (x1.15 when stopped in
	    contact); slots are centred on their mean and turned with the squad heading.
	  * the squad heading eases to the move direction (or the aim) at rate 4/s; a new squad faces a
	    hashed direction when it isn't moving.
	  * each man steers to his slot: wanted velocity = squad velocity + offset * gain (3.5), capped at
	    max(pace, speed) * 1.3 + 0.2, eased at rate 9/s; more than 3 cells off snaps him there.
	  * pose: walking (faster than 0.06 cells/s) = walk frame floor(walked / 0.17) % 4, facing his own
	    velocity; firing = kneel facing the aim point; else kneel in cover, stand otherwise, a loose squad
	    turning each man by a hashed amount (idleTurn 0.45 rad); headings ease at rate 10/s.
	  * a man is drawn Ml.cells * scale = 0.42 * 1.3 cells, his frame that / art.w (0.333) wide.
	  * crews: AT = gunner and loader, mortar = mortarman and bearer, para = three paratroopers (two-man
	    crews use the two-man slots). A mortar that is setting up, set or packing puts its tube down
	    (e7t): tube 0.15 man-sizes ahead of the squad point, the mortarman at (-0.3, -0.62) kneeling, the
	    bearer at (0.1, 0.72) kneeling, turning away (duckTurn 2.3 rad) for 0.7 s after each shot; the
	    tube shows "base" for the first half of setting up and the last half of packing, "kick" for
	    0.16 s after a shot, "set" otherwise.
	AT loaders face the surviving gunner while firing with more than 0.7 seconds left to reload.
	Setup/packing progress and reload timing come from visible authoritative crew samples when available.
	Older packets keep the local setup/packing estimate and omit the new reload actions.
	Visible blasts temporarily hold each soldier prone, then kneeling, without changing the squad order.
	APPROX: speed is the fastest observed squad movement; thrown casualties and other actions remain unported.

]]

local SquadMen = {}
local Reaction=if script then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Presentation.SquadReaction)else require("../../shared/Presentation/SquadReaction")

SquadMen.ROSTER = {
	infantry = { "leader", "rifle", "rifle" },
	para = { "para", "para", "para" },
	at = { "gunner", "loader" },
	mortar = { "mortarman", "bearer" },
}
-- the mortar crew around its tube (the game's e7t), in man-sizes
local TUBE = { tube = { 0.15, 0 }, gunner = { -0.3, -0.62 }, bearer = { 0.1, 0.72 }, loadAt = { 0.5, 0.62 }, loadTurn = -math.pi / 2, loadSec = 0.6, baseShare = 0.5, duckSec = 0.7, duckTurn = 2.3, kickSec = 0.16 }
SquadMen.MAN_CELLS = 0.42 * 1.3
SquadMen.FRAME_CELLS = 0.42 * 1.3 / 0.333

local SLOTS = {
	three = {
		wedge = { { 0.62, 0 }, { -0.31, -0.9 }, { -0.31, 0.9 } },
		file = { { 1, 0 }, { 0, 0 }, { -1, 0 } },
		line = { { -0.2, 0 }, { 0, -1.15 }, { 0, 1.15 } },
		loose = { { 0.4, 0.12 }, { -0.3, -0.85 }, { -0.45, 0.8 } },
	},
	two = {
		wedge = { { 0.18, -0.5 }, { -0.18, 0.5 } },
		file = { { 0.55, 0 }, { -0.55, 0 } },
		line = { { 0.18, -0.5 }, { -0.3, 0.5 } },
		loose = { { 0.2, -0.55 }, { -0.25, 0.5 } },
	},
}
local SPACING, CONTACT_SPREAD, LOOSE_JITTER = 0.6, 1.15, 0.32
local GAIN, CATCH_UP, CATCH_UP_BASE, SNAP = 3.5, 1.3, 0.2, 3
local WALK_MIN, STRIDE, IDLE_TURN = 0.06, 0.17, 0.45
local AT_READY_SEC = 0.7
local WALK = { "walk0", "walk1", "walk2", "walk3" }
local TAU = 2 * math.pi

local function imul(a: number, b: number): number
	a, b = a % 4294967296, b % 4294967296
	local al, ah = a % 65536, a // 65536
	local bl, bh = b % 65536, b // 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % 4294967296
end

-- the game's q5(t, e): a hash of two integers to [0, 1)
function SquadMen.hash(t: number, e: number): number
	local o = bit32.bxor(imul(bit32.bxor(t % 4294967296, 2654435769), 2246822507), imul(e + 1663821227, 3266489909))
	o = imul(bit32.bxor(o, bit32.rshift(o, 16)), 2146121005)
	o = imul(bit32.bxor(o, bit32.rshift(o, 15)), 2221713035)
	return bit32.bxor(o, bit32.rshift(o, 16)) / 4294967296
end

local function wrap(a: number): number
	return (a + math.pi) % TAU - math.pi
end

export type Man = { kind: string, x: number, y: number, vx: number, vy: number, heading: number, walked: number, up: boolean, pose: string, flatUntil: number }
export type Tube = { x: number, y: number, heading: number, pose: string }
export type Squad = { id: number, heading: number, men: { Man }, fresh: boolean, topSpeed: number, tube: Tube?, phase: string, phaseAt: number, clock: number }
-- what the renderer knows this frame (cells, cells/s)
export type Input = {
	x: number, y: number, vx: number, vy: number,
	hpFrac: number, firing: boolean, aimX: number, aimY: number,
	road: boolean, contact: boolean, cover: boolean,
	-- mortars only: "travel" | "setting" | "packing" | "set", seconds a phase takes, seconds since the last shot
	mortar: string?, phaseSec: number?, sinceShot: number?, shotLeft: number?, phaseProgress: number?,warTime: number?,
}

function SquadMen.new(id: number, kind: string, inp: Input): Squad
	local roster = SquadMen.ROSTER[kind] or SquadMen.ROSTER.infantry
	local moving = inp.vx * inp.vx + inp.vy * inp.vy > 1e-4
	local heading = if moving then math.atan2(inp.vy, inp.vx)
		elseif inp.firing then math.atan2(inp.aimY - inp.y, inp.aimX - inp.x)
		else SquadMen.hash(id, 1) * TAU
	local men: { Man } = {}
	for i, k in roster do
		table.insert(men, { kind = k, x = inp.x, y = inp.y, vx = 0, vy = 0, heading = heading, walked = SquadMen.hash(id, 10 + i - 1) * STRIDE * 4, up = true, pose = "stand",flatUntil=0 })
	end
	return { id = id, heading = heading, men = men, fresh = true, topSpeed = 0, tube = nil, phase = "travel", phaseAt = 0, clock = 0 }
end

function SquadMen.step(sq: Squad, inp: Input, dt: number)
	local men = sq.men
	local c = #men
	local speed = math.sqrt(inp.vx * inp.vx + inp.vy * inp.vy)
	sq.topSpeed = math.max(sq.topSpeed, speed)
	local moving = speed > 0.01
	local firing = inp.firing and (math.abs(inp.aimX - inp.x) > 0.05 or math.abs(inp.aimY - inp.y) > 0.05)

	-- who is standing
	local want = math.max(1, math.min(c, math.ceil(inp.hpFrac * c - 1e-6)))
	local count = 0
	for _, m in men do
		if m.up then
			count += 1
		end
	end
	while count > want do
		local pool = {}
		for i = 2, c do
			if men[i].up then
				table.insert(pool, men[i])
			end
		end
		local pick: Man? = if #pool > 0 then pool[math.floor(SquadMen.hash(sq.id, 50 + count) * #pool) + 1] else nil
		if not pick then
			for _, m in men do
				if m.up then
					pick = m
					break
				end
			end
		end
		(pick :: Man).up = false
		count -= 1
	end
	while count < want do
		local up, down = nil, nil
		for _, m in men do
			if m.up and not up then
				up = m
			elseif not m.up and not down then
				down = m
			end
		end
		if not down then
			break
		end
		down.up = true;down.flatUntil=0
		down.x, down.y = if up then up.x else inp.x, if up then up.y else inp.y
		down.vx, down.vy = 0, 0
		count += 1
	end

	local now=inp.warTime or (sq.clock+dt)
	local fresh = sq.fresh
	sq.fresh = false
	sq.clock += dt
	-- mortar tube pose (nil when it travels)
	local phase = if moving then "travel" else (inp.mortar or "travel")
	if phase ~= sq.phase then
		sq.phase, sq.phaseAt = phase, sq.clock
	end
	local tubePose: string? = nil
	local since = inp.sinceShot or math.huge
	if phase ~= "travel" then
		local progress = if inp.phaseProgress~=nil then math.clamp(inp.phaseProgress,0,1) else math.clamp((sq.clock - sq.phaseAt) / math.max(0.001, inp.phaseSec or 1), 0, 1)
		local base = if phase == "setting" then progress < TUBE.baseShare elseif phase == "packing" then progress > 1 - TUBE.baseShare else false
		tubePose = if base then "base" elseif since >= 0 and since < TUBE.kickSec then "kick" else "set"
	end
	local loading = tubePose=="set" and firing and inp.shotLeft~=nil and inp.shotLeft<=TUBE.loadSec
	local atReload = firing and inp.shotLeft~=nil and inp.shotLeft>AT_READY_SEC
	local duck = tubePose ~= nil and tubePose ~= "base" and since >= 0 and since < TUBE.duckSec
	local face = if moving then math.atan2(inp.vy, inp.vx) elseif firing then math.atan2(inp.aimY - inp.y, inp.aimX - inp.x) else nil
	if face then
		sq.heading = wrap(sq.heading + wrap(face - sq.heading) * (if fresh then 1 else 1 - math.exp(-4 * dt)))
	end
	local form = if moving then (if inp.road then "file" else "wedge") elseif firing then "line" else "loose"
	local slots = SLOTS[if c >= 3 then "three" else "two"][form]
	local spacing = SPACING * (if not moving and inp.contact then CONTACT_SPREAD else 1)
	local cover = not moving and inp.cover
	local T, I = math.cos(sq.heading), math.sin(sq.heading)
	local mx, my = 0, 0
	for j = 1, count do
		mx += slots[j][1]
		my += slots[j][2]
	end
	mx /= count
	my /= count
	local cap = math.max(speed, sq.topSpeed) * CATCH_UP + CATCH_UP_BASE
	local ease, turn = 1 - math.exp(-9 * dt), 1 - math.exp(-10 * dt)
	local j = 0
	for pe, m in men do
		if not m.up then
			continue
		end
		j += 1
		local kx, ky = slots[j][1] - mx, slots[j][2] - my
		if form == "loose" then
			kx += (SquadMen.hash(sq.id, 20 + pe - 1) - 0.5) * 2 * LOOSE_JITTER
			ky += (SquadMen.hash(sq.id, 30 + pe - 1) - 0.5) * 2 * LOOSE_JITTER
		end
		local tx, ty = inp.x + (T * kx - I * ky) * spacing, inp.y + (I * kx + T * ky) * spacing
		if tubePose then
			local at = if m.kind == "bearer" then (if loading then TUBE.loadAt else TUBE.bearer) else TUBE.gunner
			tx, ty = inp.x + (T * at[1] - I * at[2]) * SquadMen.MAN_CELLS, inp.y + (I * at[1] + T * at[2]) * SquadMen.MAN_CELLS
		end
		local flat=(m.flatUntil or 0)>now
		local dx, dy = tx - m.x, ty - m.y
		if fresh or dx * dx + dy * dy > SNAP * SNAP then
			m.x, m.y, m.vx, m.vy = tx, ty, inp.vx, inp.vy
		elseif flat then
			m.vx,m.vy=0,0
		elseif dt > 0 then
			local wx, wy = inp.vx + dx * GAIN, inp.vy + dy * GAIN
			local w = math.sqrt(wx * wx + wy * wy)
			if w > cap then
				wx, wy = wx * cap / w, wy * cap / w
			end
			m.vx += (wx - m.vx) * ease
			m.vy += (wy - m.vy) * ease
			m.x += m.vx * dt
			m.y += m.vy * dt
			m.walked += math.sqrt(m.vx * m.vx + m.vy * m.vy) * dt
		end
		local target: number? = nil
		if flat then
			m.pose=if m.flatUntil-now>Reaction.RISE_SEC then "prone"else "kneel"
		elseif math.sqrt(m.vx * m.vx + m.vy * m.vy) > WALK_MIN then
			m.pose = WALK[math.floor(m.walked / STRIDE) % 4 + 1]
			target = math.atan2(m.vy, m.vx)
		elseif tubePose then
			m.pose = if m.kind=="bearer" and loading then "load" else "kneel"
			target = sq.heading + (if m.kind=="bearer" then (if loading then TUBE.loadTurn elseif duck then TUBE.duckTurn else 0) else 0)
		elseif firing then
			m.pose = "kneel"
			target = if atReload and m.kind=="loader" and men[1].up and men[1]~=m then math.atan2(men[1].y-m.y,men[1].x-m.x) else math.atan2(inp.aimY - m.y, inp.aimX - m.x)
		else
			m.pose = if cover then "kneel" else "stand"
			if form == "loose" then
				target = sq.heading + (SquadMen.hash(sq.id, 40 + pe - 1) - 0.5) * 2 * IDLE_TURN
			end
		end
		if target then
			m.heading = wrap(m.heading + wrap(target - m.heading) * (if fresh then 1 else turn))
		end
	end
	if tubePose then
		local k = TUBE.tube[1] * SquadMen.MAN_CELLS
		sq.tube = { x = inp.x + T * k, y = inp.y + I * k, heading = sq.heading, pose = tubePose }
	else
		sq.tube = nil
	end
end

return SquadMen
