--!strict
-- Hud: top bar with match info and control help. PLACEHOLDER visuals (TEMP-003).
local Players = game:GetService("Players")

local Hud = {}

function Hud.start(info: { [string]: any })
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontHud"
	gui.ResetOnSpawn = false
	local bar = Instance.new("TextLabel")
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
	bar.BackgroundTransparency = 0.2
	bar.TextColor3 = Color3.fromRGB(235, 235, 235)
	bar.Font = Enum.Font.GothamMedium
	bar.TextSize = 14
	local sideText = if info.side == 1 then "Side 1 (blue)" elseif info.side == 2 then "Side 2 (red)" else "Spectator"
	bar.Text = `RobloxianFront · {info.map} · {sideText} · WASD/arrows or middle-drag to pan · wheel to zoom · click/drag to select · right-click to move · X stop · PLACEHOLDER ART`
	bar.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return Hud
