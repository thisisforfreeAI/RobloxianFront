--!strict
-- Admin "kills" command: owner only, adds to or sets the side's kills to spend (kills - killsSpent).
return function(test: any, eq: any)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local function make(): any
		local h: any = { studio = false }
		local env: any = setmetatable({
			game = { CreatorType = "user", CreatorId = 1, GetService = function(_, key)
				return if key == "RunService" then { IsStudio = function() return h.studio end } else { PlayerRemoving = { Connect = function() end } }
			end },
			Enum = { CreatorType = { User = "user", Group = "group" } },
			task = { spawn = function(fn) fn() end },
			warn = function() end,
		}, { __index = getfenv() })
		h.admin = luau.load(fs.readFile("src/server/Match/Admin.luau"), { environment = env })()
		h.sim = { time = 0, sides = { { kills = 12, killsSpent = 5, oil = 0 } } }
		h.owner = { UserId = 1, Name = "owner" }
		h.other = { UserId = 2, Name = "other" }
		h.spendable = function() local s = h.sim.sides[1]; return s.kills - s.killsSpent end
		return h
	end
	test("admin kills adds to the side's kills to spend, owner only", function()
		local h = make()
		eq(h.admin.handle(h.sim, h.other, 1, { op = "kills", amount = 100, add = true }), "Admin commands are for the place owner")
		eq(h.spendable(), 7)
		eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = 10, add = true }), "Kills: 17")
		eq(h.spendable(), 17)
		eq(h.sim.sides[1].killsSpent, 5) -- spending history is kept
		h.studio = true -- anyone in Studio (a player not yet checked; admin rights are cached per player)
		eq(h.admin.handle(h.sim, { UserId = 3, Name = "tester" }, 1, { op = "kills", amount = 100, add = true }), "Kills: 117")
	end)
	test("admin kills set, clamps and rejects bad amounts", function()
		local h = make()
		eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = 40 }), "Kills: 40")
		eq(h.spendable(), 40)
		eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = -1000, add = true }), "Kills: 0")
		eq(h.sim.sides[1].kills, 5)
		eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = 1e12 }), "Kills: 100000")
		eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = 2.7 }), "Kills: 2")
		for _, bad in { "x", 0 / 0, math.huge } do
			eq(h.admin.handle(h.sim, h.owner, 1, { op = "kills", amount = bad }), "Bad kill amount")
		end
		eq(h.admin.handle(h.sim, h.owner, 2, { op = "kills", amount = 5 }), "Bad kill amount") -- no such side
		eq(h.spendable(), 2)
	end)
end
