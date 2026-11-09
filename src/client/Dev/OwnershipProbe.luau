--!strict
--[[
	OwnershipProbe (Studio only, docs/STUDIO_TESTS.md test 7): press K to send a move order for every
	unit that is NOT on your side, the way a cheating client could. The server must refuse it and log
	"[Match] refused order from <player> ...", and the enemy units must not move.
]]
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local OwnershipProbe = {}

function OwnershipProbe.start(mySide: number, units: () -> { [number]: any }, send: (any) -> ())
	if not RunService:IsStudio() then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.K then
			return
		end
		local ids = {}
		for id, v in units() do
			if v.side ~= mySide then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		print(`[OwnershipProbe] side {mySide} sending a move order for other sides' units: {table.concat(ids, ",")}`)
		send({ kind = "move", unitIds = ids, x = 10, y = 10 })
	end)
end

return OwnershipProbe
