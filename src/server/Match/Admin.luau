--!strict
--[[
	Admin: the owner's test panel commands (time of day, weather, oil). Not part of WarFront; a
	development tool for this port.

	Who may use it: anyone in Roblox Studio (play testing), the place's owner (game.CreatorId, or the
	owner of the group that owns the place), and user ids listed in EXTRA. Every command is checked
	here on the server; the client only shows the panel to players the server says are admins.

	Commands (sent as { kind = "admin", op = ..., ... } through the intent remote):
	  time    { phase = 0..1, freeze = bool? }  sets the sim's day phase (the game's 480 s day: night
	          from phase 0.62, full at 0.70, dawn over the last 0.05). freeze holds it there.
	  weather { weather = "clear" | "fog" | "downpour" | "storm" | "sandstorm" }  sets the weather the
	          clients draw. Rain/storm also suppress roof fires; sight and pace do not change.
	  oil     { amount = number, add = bool? }  sets (or adds to) the sender's side's oil.
]]
local RunService = game:GetService("RunService")

local Admin = {}

local EXTRA: { [number]: boolean } = {} -- more admin user ids, if wanted
local WEATHERS = { clear = true, fog = true, downpour = true, storm = true, sandstorm = true }
local MAX_OIL = 1000000

local groupOwner: number? = nil
local known: { [Player]: boolean } = {}

local function check(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if EXTRA[player.UserId] then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if groupOwner == nil then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank == 255
	end
	return player.UserId == groupOwner
end

-- cached per player (the group rank lookup is a web call)
function Admin.isAdmin(player: Player): boolean
	local got = known[player]
	if got == nil then
		got = check(player)
		known[player] = got
	end
	return got
end

local st = { weather = "clear", freezePhase = nil :: number? }

function Admin.weather(): string
	return st.weather
end

-- the day phase now (0..1, as Sim.nightAmount works it out)
function Admin.phaseOf(sim: any): number
	local rate = if sim.rules:has("daylight.rate") then sim.rules:number("daylight.rate") else 1
	local offset = sim.dayOffset or (if sim.rules:has("daylight.offsetSec") then sim.rules:number("daylight.offsetSec") else 0)
	local clock = offset + sim.time * rate
	return ((math.floor(clock) / 480 + 0.08) % 1 + 1) % 1
end

-- the sim clock offset that puts the day at phase now (inverse of Sim.nightAmount's clock)
local function offsetFor(sim: any, phase: number): number
	local rate = if sim.rules:has("daylight.rate") then sim.rules:number("daylight.rate") else 1
	local clock = ((phase - 0.08) % 1) * 480
	return clock - sim.time * rate + 0.5 -- + 0.5: the sim floors the clock
end

-- call every tick: holds a frozen day phase
function Admin.step(sim: any)
	if st.freezePhase then
		sim.dayOffset = offsetFor(sim, st.freezePhase)
	end
end

-- returns a notice for the sender
function Admin.handle(sim: any, player: Player, side: number, raw: any): string
	if not Admin.isAdmin(player) then
		warn(`[Admin] {player.Name} is not an admin; command ignored`)
		return "Admin commands are for the place owner"
	end
	local op = raw.op
	if op == "time" then
		local phase = tonumber(raw.phase)
		if not phase or phase ~= phase then
			return "Bad time"
		end
		phase = phase % 1
		sim.dayOffset = offsetFor(sim, phase)
		st.freezePhase = if raw.freeze == true then phase else nil
		return if st.freezePhase then "Time set and frozen" else "Time set"
	elseif op == "weather" then
		local w = raw.weather
		if type(w) ~= "string" or not WEATHERS[w] then
			return "Unknown weather"
		end
		st.weather = w
		sim.weather = w
		return `Weather: {w}`
	elseif op == "townFire" or op=="forestFire" then
		local world=if op=="townFire" then sim.houseFires else sim.forestFires
		if not world then return if op=="townFire" then "House fire data unavailable on this map" else "Forest fire data unavailable on this map" end
		if sim.winner or (sim.drop and sim.drop.phase~="done") then return "Start the match first" end
		local x,y=raw.x,raw.y
		if type(x)~="number" or type(y)~="number" or x~=x or y~=y or x<0 or y<0 or x>=sim.deps.map.width or y>=sim.deps.map.height then return "Bad fire position" end
		local count=world.igniteAt(x,y)
		return if op=="townFire" then `Ignited {count} nearby roofs` else `Ignited {count} nearby trees`
	elseif op == "rebuildFires" then
		if not sim.houseFires and not sim.forestFires then return "House fire data unavailable on this map" end
		if sim.forestFires then sim.forestFires.reset() end
		if sim.groundScorch then sim.groundScorch.reset() end
		if sim.fireImpacts then sim.fireImpacts.reset() end
		return "Forest and ground reset; houses stay ruined until next match"
	elseif op == "oil" then
		local amount = tonumber(raw.amount)
		local s = sim.sides[side]
		if not amount or amount ~= amount or not s then
			return "Bad oil amount"
		end
		s.oil = math.clamp(if raw.add == true then s.oil + amount else amount, 0, MAX_OIL)
		return `Oil: {math.floor(s.oil)}`
	end
	return "Unknown admin command"
end

-- the group owner's id, looked up once (for group-owned places)
game:GetService("Players").PlayerRemoving:Connect(function(player)
	known[player] = nil
end)

task.spawn(function()
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, info = pcall(function()
			return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId)
		end)
		if ok and info and info.Owner then
			groupOwner = info.Owner.Id
		end
	end
end)

return Admin
