--!strict
-- Pure presentation state, traced from the game's effects death/cookOff/brewUp/quietKill/wreckBurn.
-- Config comes from the local install via export_death_fx.cjs; no derived tables are stored here.
-- APPROX: bounded Roblox particle count (512 versus the game's 4000); continuous alpha instead of
-- its screen-space dither/erosion and additive lighting. Terrain scorch, light and shake are pending.
-- APPROX: 0.05s physics slices and continuous transforms replace the original particle stepping;
-- terrain-neutral dust, no extra thrown ground clods or smoke trails on hot blast fragments yet.
local DeathEffects = {}
local ORDER = { "blast", "cook", "toss", "brew", "quiet" }
local CLASSES = { tank = "tank", ifv = "ifv", artillery = "gun", rocket = "launcher" }

function DeathEffects.new(config: any, random: (() -> number)?)
	local rng = random or math.random
	local self: any = { time = 0, particles = {}, emitters = {}, later = {}, long = {}, config = config, maxParticles = 512 }
	local D, V, C, N, M = config.death, config.death.variants, config.colors, config.sparks, config.motion
	local function range(a: number, b: number): number return a + rng() * (b - a) end
	local function pick(r: { number }): number return range(r[1], r[2]) end
	local function blob(): string return "blob" .. ({ "A", "B", "C" })[math.min(3, math.floor(rng() * 3) + 1)] end
	local function mix(a: number, b: number, k: number): number
		local function channel(shift: number): number
			local x, y = bit32.extract(a, shift, 8), bit32.extract(b, shift, 8)
			return math.floor(x + (y - x) * k + 0.5)
		end
		return channel(16) * 65536 + channel(8) * 256 + channel(0)
	end
	function self:spawn(p: any)
		if #self.particles >= self.maxParticles then return end
		p.age, p.x0, p.y0 = 0, p.x, p.y
		p.h, p.vx, p.vy, p.vh = p.h or 0, p.vx or 0, p.vy or 0, p.vh or 0
		p.rot, p.len, p.a0, p.a1 = p.rot or 0, p.len or 1, p.a0 or 1, if p.a1 == nil then 1 else p.a1
		table.insert(self.particles, p)
	end
	function self:after(sec: number, fn: () -> ())
		table.insert(self.later, { at = self.time + sec, fn = fn })
	end
	function self:emitter(sec: number, fn: (any, number, number) -> ())
		table.insert(self.emitters, { at = self.time, sec = sec, fn = fn, acc = {} })
	end
	function self:puff(x: number, y: number, h: number, size: number, life: number, color: number?, rise: number?, vx: number?, vy: number?, ground: boolean?)
		local c = color or C.smoke
		self:spawn({ tex = "puff" .. ({ "A", "B", "C" })[math.min(3, math.floor(rng() * 3) + 1)], x = x, y = y, h = h,
			size = size, life = life, color = c, color1 = if c == C.smoke then C.smokeLight elseif c == C.dust then C.dustLight else mix(c, C.smokeLight, 0.4),
			vh = if ground then M.rise * 0.15 else M.rise * (rise or 1) * range(0.7, 1.3),
			vx = vx or 0, vy = vy or 0, grow = size * M.grow / life, wind = not ground, drag = if ground then 1.3 else 1.2,
			rot = range(0, 2 * math.pi), a1 = 0, ground = ground })
	end
	function self:sparks(x: number, y: number, h: number, count: number, speed: { number }, rise: { number }, life: { number })
		for _ = 1, count do
			local a, v = range(-math.pi, math.pi), pick(speed)
			self:spawn({ tex = "spark", x = x, y = y, h = h, vx = math.cos(a) * v, vy = math.sin(a) * v, vh = pick(rise),
				falls = true, drag = 0.6, size = pick(N.size), life = pick(life), color = C.hot, color1 = C.ember, align = true })
		end
	end
	function self:blast(x: number, y: number, spec: any)
		local B, F, n = config.blast, config.look.flash, spec.blast
		self:spawn({ tex = "disc", x = x, y = y, h = 0.1, size = n * F.share, life = F.sec, color = C.fire, a0 = 0.6, a1 = 0 })
		self:spawn({ tex = "disc", x = x, y = y, h = 0.1, size = n * F.share * F.core, life = F.sec, color = C.hot, a1 = 0 })
		for _, band in B.bands do
			self:spawn({ tex = blob(), x = x, y = y, h = n * 0.12, size = n * band.share, life = band.sec,
				color = C[band.color], color1 = if band.color == "ember" then C.coal else nil, rot = range(0, 2 * math.pi), pop = true })
		end
		self:spawn({ tex = "disc", x = x, y = y, h = n * 0.15, size = n * B.coreShare, life = B.coreSec, color = C.hot, pop = true })
		self:sparks(x, y, n * 0.15, math.floor(N.blast * n / 4 + 0.5), { N.blastSpeed[1], N.blastSpeed[2] * math.sqrt(n / 4) }, N.blastRise, N.blastLife)
		self:spawn({ tex = "ring", x = x, y = y, size = n * F.ringShare, life = F.ringSec, grow = n * F.ringGrow / F.ringSec, color = C.dustLight, a0 = 0.9, a1 = 0, ground = true })
		-- APPROX: neutral dust/debris until the client exposes the ground painter's surface classes.
		for i = 1, math.clamp(math.floor(F.puffs * n / 4 + 0.5), F.minPuffs, F.maxPuffs) do
			local a, v = range(0, 2 * math.pi), F.kick * math.sqrt(n / 4) * range(0.8, 1.1)
			self:puff(x + math.cos(a) * n * 0.15, y + math.sin(a) * n * 0.15, 0.05, n * F.puffShare * range(0.8, 1.2), F.puffSec * range(0.85, 1.15), C.dust, 1, math.cos(a) * v, math.sin(a) * v, true)
		end
		for i = 1, spec.debris do
			local a, v = range(0, 2 * math.pi), range(0.2, 1) * M.debrisSpeed * n / 3.5
			self:spawn({ tex = if i % 2 == 0 then "shard" else "chunk", x = x, y = y, h = 0.2, vx = math.cos(a) * v, vy = math.sin(a) * v,
				vh = range(3, 10) * n / 3.5, falls = true, size = range(0.3, 0.55), len = range(1, 1.6), life = range(0.5, 1.3),
				color = if i % 4 == 1 then C.ember else C.debris, spin = range(-8, 8) })
		end
		for i = 0, spec.smoke - 1 do
			local dx, dy = range(-0.35, B.smokeSpread) * n * 0.4, range(-0.35, B.smokeSpread) * n * 0.4
			self:after(B.smokeDelay + i * 0.05, function()
				self:puff(x + dx, y + dy, B.smokeFrom + i * 0.2, spec.smokeSize * range(0.75, 1.1), spec.smokeLife * range(0.8, 1.25), nil, 1, range(-0.5, 0.5), range(-0.5, 0.5))
			end)
		end
	end
	local function emit(acc: any, key: string, rate: number, dt: number, fn: () -> ())
		acc[key] = (acc[key] or 0) + rate * dt
		while acc[key] >= 1 do acc[key] -= 1; fn() end
	end
	function self:burn(x: number, y: number, sec: number, scale: number)
		local root = math.sqrt(scale)
		self:emitter(sec + D.wreckSmokeSec, function(acc: any, age: number, dt: number)
			local fire = if age < sec then math.min(1, (sec - age) / (sec * D.wreckDieShare)) else 0
			local tail = if age < sec then 0 else math.min(1, (age - sec) / D.wreckSmokeSec)
			emit(acc, "smoke", D.wreckSmokePerSec * root * (1 - tail) ^ 1.5, dt, function()
				self:puff(x + range(-0.4, 0.4), y + range(-0.4, 0.4), 0.6, D.wreckSmokeSize * (1 - 0.45 * tail) * range(0.85, 1.1),
					D.wreckSmokeLife * range(0.9, 1.15), mix(C.smoke, D.wreckSmoulder, tail), D.wreckSmokeRise * (1 - 0.4 * tail))
			end)
			emit(acc, "fire", D.wreckFirePerSec * fire * scale, dt, function()
				local size = D.wreckFireSize * root * (0.45 + 0.55 * fire) * range(0.7, 1.2)
				self:spawn({ tex = blob(), x = x + range(-0.5, 0.5) * root, y = y + range(-0.5, 0.5) * root, h = 0.2, vh = 2.4,
					size = size, grow = -size / D.wreckFireLife, life = D.wreckFireLife, color = ({ C.fire, C.hot, C.ember })[math.min(3, math.floor(rng() * 3) + 1)], rot = range(0, 2 * math.pi) })
			end)
			emit(acc, "embers", N.embersPerSec * fire * scale, dt, function()
				self:spawn({ tex = "glint", x = x + range(-0.5, 0.5) * root, y = y + range(-0.5, 0.5) * root, h = 0.4,
					vx = range(-0.6, 0.6), vy = range(-0.3, 0.3), vh = pick(N.emberRise), wind = true, drag = 0.5,
					size = pick(N.emberSize), life = pick(N.emberLife), spin = range(-3, 3), color = C.fire, color1 = C.coal })
			end)
		end)
	end
	function self:cookPop(x: number, y: number)
		local c, px, py = V.cook, x + range(-0.3, 0.3), y + range(-0.3, 0.3)
		local flash = pick(c.flash)
		self:spawn({ tex = "star", x = px, y = py, h = 0.4, size = flash, life = c.flashSec, rot = range(0, math.pi), color = C.fire })
		self:spawn({ tex = "disc", x = px, y = py, h = 0.4, size = flash * 0.4, life = c.flashSec * 0.8, color = C.hot })
		self:sparks(px, py, 0.4, math.floor(pick(c.sparks) + 0.5), c.speed, c.rise, c.life)
		if rng() < c.roundChance then
			local a, v = range(0, 2 * math.pi), pick(c.roundSpeed)
			self:spawn({ tex = "spark", x = px, y = py, h = 0.4, vx = math.cos(a) * v, vy = math.sin(a) * v, vh = pick(c.roundRise),
				falls = true, drag = 0.3, size = 0.3, life = pick(c.roundLife), color = C.hot, color1 = C.spark, align = true })
		end
		self:puff(px, py, 0.5, c.smoke, 0.7)
	end
	function self:kill(kind: string, x: number, y: number, forced: string?): any
		local weights, total = V.weights[CLASSES[kind] or "light"], 0
		for _, key in ORDER do total += weights[key] end
		local n, variant = rng() * total, "blast"
		for _, key in ORDER do n -= weights[key]; if n < 0 and weights[key] > 0 then variant = key; break end end
		variant = forced or variant -- deterministic Studio/test harness; production never supplies this
		if variant == "cook" or variant == "brew" then
			local keep = {}
			for _, untilAt in self.long do if untilAt > self.time then table.insert(keep, untilAt) end end
			self.long = keep
			if #keep >= V.maxLong then variant = "blast" else table.insert(keep, self.time + V[variant].sec[2]) end
		end
		local toss: any = { variant = variant }
		if variant == "cook" then
			local c, sec = V.cook, pick(V.cook.sec)
			self:blast(x, y, c.hit); self:burn(x, y, sec + D.wreckBurnSec, 1)
			local gap = pick(c.every)
			self:emitter(sec, function(acc: any, age: number, dt: number)
				acc.pop = (acc.pop or 0) + dt
				if acc.pop >= gap then acc.pop = 0; gap = pick(c.every) * (1.3 - 0.6 * age / sec); self:cookPop(x, y) end
			end)
			self:after(sec, function() self:blast(x, y, c["end"]); self:sparks(x, y, 0.5, c.endSparks, { 3, 10 }, { 6, 15 }, { 0.6, 1.3 }) end)
		elseif variant == "brew" then
			local b, sec = V.brew, pick(V.brew.sec)
			local height = b.rise[2] * b.life[2]
			self:spawn({ tex = "star", x = x, y = y, h = 0.4, size = 1.6, life = 0.08, color = C.hot })
			self:sparks(x, y, 0.4, 6, { 2, 6 }, { 4, 10 }, { 0.3, 0.7 })
			self:emitter(sec, function(acc: any, age: number, dt: number)
				local fade = math.min(1, (1 - age / sec) / b.dieShare)
				emit(acc, "jet", b.perSec, dt, function()
					local life, size, hot = pick(b.life), b.size * range(0.75, 1.15) * (0.6 + 0.4 * fade), rng() < 0.3
					self:spawn({ tex = blob(), x = x + range(-0.12, b.spread), y = y + range(-0.12, b.spread), h = 0.3,
						vh = pick(b.rise) * (0.35 + 0.65 * fade), vx = range(-0.35, 0.35), vy = range(-0.2, 0.2), size = if hot then size * 0.6 else size,
						len = b.stretch, rot = -math.pi / 2 + range(-0.2, 0.2), life = life, grow = -size * 0.6 / life,
						color = if hot then C.hot else C.fire, color1 = if hot then C.fire else C.ember })
				end)
				emit(acc, "spark", b.sparks * fade, dt, function() self:sparks(x, y, height * 0.7 * fade, 1, { 1, 4 }, { 2, 6 }, { 0.4, 0.8 }) end)
				emit(acc, "smoke", b.smoke, dt, function() self:puff(x + range(-0.2, 0.2), y + range(-0.2, 0.2), height * 0.8 * fade, b.smokeSize * range(0.8, 1.2), b.smokeLife * range(0.85, 1.15), nil, 1.6) end)
			end)
			self:after(sec * b.burnFrom, function() self:burn(x, y, D.wreckBurnSec, 1) end)
		elseif variant == "quiet" then
			local q = V.quiet
			self:puff(x, y, 0.05, q.dust, 0.9, C.dust, 1, 0, 0, true)
			self:sparks(x, y, 0.3, 3, N.impactSpeed, { 2, 5 }, N.impactLife)
			self:emitter(q.smokeSec, function(acc: any, age: number, dt: number)
				if acc.smoke == nil then acc.smoke = 0.6 end
				emit(acc, "smoke", q.smokePerSec * (1 - 0.7 * age / q.smokeSec), dt, function()
					self:puff(x + range(-0.2, 0.2), y + range(-0.2, 0.2), 0.4, q.smokeSize * range(0.8, 1.2), q.smokeLife * range(0.85, 1.15), D.wreckSmoulder, q.smokeRise)
				end)
			end)
			if rng() < q.fireChance then self:after(pick(q.fireAfter), function() self:burn(x, y, q.fireSec, q.fireScale) end) end
		elseif variant == "toss" then
			local t, a, reach = V.toss, range(0, 2 * math.pi), pick(V.toss.reach)
			toss.x, toss.y = math.cos(a) * reach, math.sin(a) * reach
			toss.sec, toss.height, toss.turn, toss.flips = pick(t.sec), pick(t.height), pick(t.turn) * (if rng() < 0.5 then -1 else 1), pick(t.flips)
			self:blast(x, y, t.blast); self:burn(x, y, D.wreckBurnSec, 1)
			for i = 0, t.pillar - 1 do self:after(i / t.pillar * t.pillarSec, function()
				local size = range(0.6, 0.95)
				self:spawn({ tex = blob(), x = x + range(-0.12, 0.12), y = y + range(-0.12, 0.12), h = 0.3, vh = range(6, 9), size = size,
					life = 0.32, grow = -size / 0.5, color = if i % 2 == 0 then C.hot else C.fire, color1 = C.ember })
			end) end
			self:emitter(toss.sec * t.trailShare, function(acc: any, age: number, dt: number)
				emit(acc, "trail", t.trail, dt, function()
					local k = age / toss.sec
					self:puff(x + toss.x * k + range(-0.1, 0.1), y + toss.y * k + range(-0.1, 0.1), 0.3 + 4 * toss.height * k * (1 - k), t.trailSize * range(0.8, 1.2), t.trailLife * range(0.8, 1.2), nil, 0.4)
				end)
			end)
			self:after(toss.sec, function()
				local tx, ty = x + toss.x, y + toss.y
				self:spawn({ tex = "ring", x = tx, y = ty, size = t.ring, grow = (t.ringTo - t.ring) / t.ringSec, life = t.ringSec, color = C.dustLight, a1 = 0, ground = true })
				for i = 0, t.dust - 1 do
					local a, v = i / t.dust * 2 * math.pi + range(-0.3, 0.3), t.dustKick * range(0.7, 1.1)
					self:puff(tx + math.cos(a) * 0.3, ty + math.sin(a) * 0.3, 0.05, t.dustSize * range(0.8, 1.2), t.dustLife * range(0.85, 1.15), C.dust, 1, math.cos(a) * v, math.sin(a) * v, true)
				end
			end)
		else
			self:blast(x, y, { blast = D.vehicleBlast, debris = D.vehicleDebris, smoke = 3, smokeSize = 1.4, smokeLife = 1.8 })
			self:burn(x, y, D.wreckBurnSec, 1)
		end
		return toss
	end
	function self:step(dt: number)
		-- Advance in bounded slices so a slow frame cannot skip the cook finale or delayed ignition.
		while dt > 1e-6 do
			local delta = math.min(dt, 0.05); dt -= delta; self.time += delta
			local later = self.later; self.later = {}
			for _, e in later do if e.at <= self.time then e.fn() else table.insert(self.later, e) end end
			local emitters = self.emitters; self.emitters = {}
			for _, e in emitters do
				local age = math.min(e.sec, self.time - e.at)
				e.fn(e.acc, age, math.min(delta, math.max(0, e.sec - (self.time - delta - e.at))))
				if self.time - e.at < e.sec then table.insert(self.emitters, e) end
			end
			local keep = {}
			for _, p in self.particles do
				p.age += delta
				if p.age >= p.life then continue end
				p.x += p.vx * delta; p.y += p.vy * delta; p.h = math.max(0, p.h + p.vh * delta)
				if p.falls then p.vh -= M.gravity * delta; if p.h <= 0 then p.vh, p.vx, p.vy = 0, 0, 0 end end
				if p.wind then p.vx += M.windX * delta; p.vy += M.windY * delta end
				local drag = math.exp(-(p.drag or 0) * delta); p.vx *= drag; p.vy *= drag
				p.rot += (p.spin or 0) * delta
				if p.align then p.rot = math.atan2(p.vy - p.vh * math.cos(math.rad(62)), p.vx) end
				p.drawSize = math.max(0.001, p.size + (p.grow or 0) * p.age)
				if p.pop then p.drawSize *= math.min(1, p.age / 0.1) end -- APPROX: game's pop/swell curve
				p.alpha = p.a0 + (p.a1 - p.a0) * p.age / p.life
				p.tint = mix(p.color, p.color1 or p.color, p.age / p.life)
				table.insert(keep, p)
			end
			self.particles = keep
		end
	end
	return self
end
return DeathEffects
