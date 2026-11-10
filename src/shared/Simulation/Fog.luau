--!strict
--[[
	Fog: what one nation's player may see, following the game's viewer intel (its updateVision).
	The server keeps one viewer per player side and filters every snapshot through it, so a client
	never receives enemy units or buildings its side cannot see (TEMP-001 closed).

	  vision      Sim.visionFor (structures, rigs, units, trucks; night shortens sight).
	  units       own units always; enemy units and trucks only on a cell seen now.
	  buildings   own always; an enemy HQ while it stands (the game always shows it); other enemy
	              buildings while their centre cell is seen, then "stale": the last seen kind stays on
	              the map until the cell is seen again without it.
	  rigs        always on the map; an enemy or neutral rig shows the owner last seen there
	              (unknown, shown neutral, until first seen) and no capture or oil details unless seen.
	  unit intel  the game's unitIntel: every enemy unit seen is remembered where it was last seen;
	              the memory goes after intel.unitIntelSec without a sighting, or sooner when the unit
	              is dead and its last spot is seen again (ghosts()).
	With intel.fog off everything is visible. Radar contacts come from Sim.contactsFor.
	Not in the slice: drones, allies.
]]

local Fog = {}

function Fog.newViewer(sim: any, side: number)
	local W, H = sim.roads.width, sim.roads.height
	local self = {
		side = side,
		grid = table.create(W * H, 0) :: { number },
		lastSeen = {} :: { [number]: { kind: string, side: number, x: number, y: number, cell: number } },
		rigSeen = {} :: { [number]: number },
		unitIntel = {} :: { [number]: { kind: string, side: number, x: number, y: number, t: number, seq: number } },
		seq = 0,
	}

	function self.update()
		local grid = self.grid
		if not sim.fogOn() then
			for i = 1, W * H do
				grid[i] = 2
			end
		else
			sim.visionFor(side, grid)
		end
		-- forget buildings seen gone
		for id, info in self.lastSeen do
			local e = sim.entities[id]
			if (not e or not e.alive) and grid[info.cell + 1] == 2 then
				self.lastSeen[id] = nil
			end
		end
		-- the game's unit intel (JJe): enemy units seen now are remembered with the time
		local now = sim.time
		self.seq = (self.seq or 0) + 1
		local seq = self.seq
		for _, e in sim.list do
			if e.alive and e.cat == "unit" and e.side ~= side and e.side > 0 and not e.inside then
				local c = sim.roads.cellAt(e.x, e.y)
				if c >= 0 and grid[c + 1] == 2 then
					local m = self.unitIntel[e.id]
					if m then
						m.kind, m.side, m.x, m.y, m.t, m.seq = e.kind, e.side, e.x, e.y, now, seq
					else
						self.unitIntel[e.id] = { kind = e.kind, side = e.side, x = e.x, y = e.y, t = now, seq = seq }
					end
				end
			end
		end
		local keep = sim.num("intel.unitIntelSec")
		for id, m in self.unitIntel do
			if m.seq ~= seq then
				if now - m.t > keep then
					self.unitIntel[id] = nil
				else
					local e = sim.entities[id]
					if not (e and e.alive) then
						local c = sim.roads.cellAt(m.x, m.y)
						if c >= 0 and grid[c + 1] == 2 then
							self.unitIntel[id] = nil
						end
					end
				end
			end
		end
		for _, e in sim.list do
			if e.alive and e.cat == "structure" then
				if e.kind == "rig" then
					if grid[e.cell + 1] == 2 then
						self.rigSeen[e.id] = e.side
					end
				elseif e.side ~= side and grid[e.cell + 1] == 2 and not (sim.mineHidden and sim.mineHidden(e, side)) then
					self.lastSeen[e.id] = { kind = e.kind, side = e.side, x = e.x, y = e.y, cell = e.cell }
				end
			end
		end
	end

	function self.visibleAt(x: number, y: number): boolean
		local c = sim.roads.cellAt(x, y)
		return c >= 0 and self.grid[c + 1] == 2
	end

	function self.unitVisible(e: any): boolean
		return e.side == side or self.visibleAt(e.x, e.y)
	end

	-- "seen", "stale" or "hidden"
	function self.structureState(e: any): string
		if e.kind == "minefield" and e.side ~= side then
			-- the game's structureVisibility: hidden until found, then seen while any of its cells is
			if sim.mineHidden(e, side) then
				return "hidden"
			end
			for _, c in e.mineCells or {} do
				if self.grid[c + 1] == 2 then
					return "seen"
				end
			end
		end
		if e.side == side or self.grid[e.cell + 1] == 2 or (e.kind == "hq" and e.alive) then
			return "seen"
		end
		return if self.lastSeen[e.id] then "stale" else "hidden"
	end

	-- owner of a rig as this side knows it (0 = neutral or unknown)
	function self.rigOwner(rig: any): number
		if rig.side == side or self.grid[rig.cell + 1] == 2 then
			return rig.side
		end
		return self.rigSeen[rig.id] or 0
	end

	-- remembered enemy units not in sight now: { id, kind, side, x, y, age in s }
	function self.ghosts(): { { any } }
		local out = {}
		if not sim.fogOn() then
			return out
		end
		for id, m in self.unitIntel do
			if m.seq ~= self.seq then
				table.insert(out, { id, m.kind, m.side, math.floor(m.x * 10 + 0.5) / 10, math.floor(m.y * 10 + 0.5) / 10, math.floor(sim.time - m.t) })
			end
		end
		return out
	end

	-- the cells seen now, as row runs { y, x0, x1, ... }
	function self.runs(): { number }
		local out = {}
		local grid = self.grid
		for y = 0, H - 1 do
			local x = 0
			while x < W do
				if grid[y * W + x + 1] == 2 then
					local x0 = x
					while x + 1 < W and grid[y * W + x + 2] == 2 do
						x += 1
					end
					table.insert(out, y)
					table.insert(out, x0)
					table.insert(out, x)
				end
				x += 1
			end
		end
		return out
	end

	return self
end

return Fog
