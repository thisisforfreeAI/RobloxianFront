--!strict
--[[
	SelectionController: RTS selection and orders.
	Left click: select own unit (Shift adds/toggles). Left drag: box select (Shift adds).
	Left click on one of your buildings (HQ, barracks, factory): pick it as the producer for the HUD.
	Left click inside one of your towns or cities: pick it for forward training.
	Right click on an enemy unit or building: attack order. Right click on the ground: move order. X: stop. Esc: clear.
	Right click on your IFV with infantry or AT selected: they get in. / unloads selected IFVs.
	T with the cursor on one of your rigs: send a truck to it.
	R: selected scout cars deploy for recon (PROVISIONAL key).
	H with the cursor on a town you hold: selected infantry / AT garrison it (PROVISIONAL key).
	Right click on one of your damaged buildings with engineers selected: they repair it (PROVISIONAL).
	Right click on a road cut or worn road with engineers selected: they mend it (PROVISIONAL).
	V with engineers selected and the cursor on a road: they sabotage it (PROVISIONAL key).
	P / J / L at the cursor: the capital's paratroopers / bomb truck, or a drop from your nearest ready
	airfield town; O sends the recon drone there. N: selected bomb trucks blow up. I: selected rocket
	artillery fires a barrage at the cursor. (PROVISIONAL keys)
	Trucks drive themselves and cannot be selected.
	The client only proposes; the server re-checks ownership and the target.
	Key choices (X, Esc) are PROVISIONAL until WarFront's bindings are confirmed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Protocol = require(Shared.Protocol.Protocol)
local UnitRenderer = require(script.Parent.Parent.Rendering.UnitRenderer)
local StructureRenderer = require(script.Parent.Parent.Rendering.StructureRenderer)
local CityOverlay = require(script.Parent.Parent.Rendering.CityOverlay)
local RoadOverlay = require(script.Parent.Parent.Rendering.RoadOverlay)

local SelectionController = {}

local CLICK_PIXELS = 6
local PICK_PIXELS = 22

local selected: { [number]: boolean } = {}

local function groundPoint(screen: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	local map = workspace:FindFirstChild("WarFrontMap")
	if not map then
		return nil
	end
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map:FindFirstChild("Ground") :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	return if hit then hit.Position else nil
end

local function screenOf(v: UnitRenderer.View): (Vector2, boolean)
	local p, onScreen = workspace.CurrentCamera:WorldToViewportPoint(v.body.Position)
	return Vector2.new(p.X, p.Y), onScreen
end

local function send(sendIntent: (any) -> (), kind: string, extra: { [string]: any }?)
	local ids = {}
	for id in selected do
		table.insert(ids, id)
	end
	-- Large selections go out in chunks the server accepts.
	for i = 1, #ids, Protocol.MAX_UNITS_PER_ORDER do
		local chunk = table.move(ids, i, math.min(i + Protocol.MAX_UNITS_PER_ORDER - 1, #ids), 1, {})
		local payload: { [string]: any } = { kind = kind, unitIds = chunk }
		if extra then
			for k, v in extra do
				payload[k] = v
			end
		end
		sendIntent(payload)
	end
end

local PRODUCERS = { hq = true, barracks = true, factory = true }
local picked: number? = nil -- the last own building clicked (Delete cancels or demolishes it)
local producerId: number? = nil -- the last own producer clicked (Backspace cancels its last queued unit)

local function structureUnder(mouse: Vector2, accept: (StructureRenderer.View) -> boolean): StructureRenderer.View?
	local best, bestDist = nil, 40
	for _, v in StructureRenderer.each() do
		if accept(v) then
			local p, on = workspace.CurrentCamera:WorldToViewportPoint(World.toWorld(v.x, v.y, 1))
			local d = (Vector2.new(p.X, p.Y) - mouse).Magnitude
			if on and d < bestDist then
				best, bestDist = v, d
			end
		end
	end
	return best
end

-- opts.busy(): true while a building is being placed (clicks belong to the placement);
-- opts.onProducer(id, kind): a building was picked as the producer (nil = back to the HQ).
function SelectionController.start(mySide: number, sendIntent: (any) -> (), opts: { busy: () -> boolean, onProducer: (number?, string?) -> () })
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarFrontSelection"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local box = Instance.new("Frame")
	box.BackgroundColor3 = Color3.fromRGB(120, 255, 120)
	box.BackgroundTransparency = 0.85
	box.BorderSizePixel = 0
	box.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 255, 120)
	stroke.Parent = box
	box.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local dragStart: Vector2? = nil

	local function refresh()
		for id in selected do
			if not UnitRenderer.each()[id] then
				selected[id] = nil -- unit is gone
			end
		end
		UnitRenderer.setSelected(selected)
	end

	local function finishSelect(a: Vector2, b: Vector2, additive: boolean)
		if not additive then
			table.clear(selected)
		end
		if (a - b).Magnitude < CLICK_PIXELS then
			local best, bestDist = nil, PICK_PIXELS
			for id, v in UnitRenderer.each() do
				if v.side == mySide and v.kind ~= "truck" then
					local s, on = screenOf(v)
					local d = (s - b).Magnitude
					if on and d < bestDist then
						best, bestDist = id, d
					end
				end
			end
			if best then
				selected[best] = if additive then not selected[best] or nil else true
			else
				local own = structureUnder(b, function(v)
					return v.side == mySide
				end)
				picked = if own then own.id else nil
				local st = structureUnder(b, function(v)
					return v.side == mySide and PRODUCERS[v.kind] == true
				end)
				if st then
					producerId = st.id
					opts.onProducer(st.id, st.kind)
				else
					-- one of your towns: train there (forward training)
					local city = CityOverlay.pick(b, mySide)
					if city then
						opts.onProducer(city, "town")
					end
				end
			end
		else
			local minV, maxV = a:Min(b), a:Max(b)
			for id, v in UnitRenderer.each() do
				if v.side == mySide and v.kind ~= "truck" then
					local s, on = screenOf(v)
					if on and s.X >= minV.X and s.X <= maxV.X and s.Y >= minV.Y and s.Y <= maxV.Y then
						selected[id] = true
					end
				end
			end
		end
		refresh()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2
		if isMouse and opts.busy() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragStart = UserInputService:GetMouseLocation()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if not next(selected) then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			-- engineers selected and one of your damaged buildings under the cursor: repair it
			local engineers = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "engineer" then
					table.insert(engineers, id)
				end
			end
			if #engineers > 0 then
				local own = structureUnder(mouse, function(v)
					return v.kind ~= "rig" and v.side == mySide and v.built >= 1 and v.hp ~= nil and v.maxHp ~= nil and v.hp < v.maxHp
				end)
				if own then
					sendIntent({ kind = "repair", unitIds = engineers, targetId = own.id })
					return
				end
				-- a road cut or worn road under the cursor: mend it
				local spot = groundPoint(mouse)
				if spot then
					local x, y = World.toCell(spot)
					if RoadOverlay.repairableAt(x, y) then
						sendIntent({ kind = "roadRepair", unitIds = engineers, x = x, y = y })
						return
					end
				end
			end
			-- infantry or AT selected and one of your IFVs under the cursor: get in
			local riders = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and (v.kind == "infantry" or v.kind == "at") then
					table.insert(riders, id)
				end
			end
			if #riders > 0 then
				local ifv, bd = nil, PICK_PIXELS
				for id, v in UnitRenderer.each() do
					if v.side == mySide and v.kind == "ifv" and not selected[id] then
						local sp, on = screenOf(v)
						local d = (sp - mouse).Magnitude
						if on and d < bd then
							ifv, bd = id, d
						end
					end
				end
				if ifv then
					sendIntent({ kind = "board", carrierId = ifv, unitIds = riders })
					return
				end
			end
			-- enemy under the cursor? attack it; otherwise move
			local best, bestDist = nil, PICK_PIXELS
			for id, v in UnitRenderer.each() do
				if v.side ~= mySide and v.side ~= 0 then
					local sp, on = screenOf(v)
					local d = (sp - mouse).Magnitude
					if on and d < bestDist then
						best, bestDist = id, d
					end
				end
			end
			for id, v in StructureRenderer.each() do
				if v.kind ~= "rig" and v.side ~= mySide and v.side ~= 0 then
					local p, on = workspace.CurrentCamera:WorldToViewportPoint(World.toWorld(v.x, v.y, 1))
					local d = (Vector2.new(p.X, p.Y) - mouse).Magnitude
					if on and d < math.max(bestDist, 40) then
						best, bestDist = id, d
					end
				end
			end
			if best then
				send(sendIntent, "attack", { targetId = best })
				return
			end
			local hit = groundPoint(mouse)
			if hit then
				local x, y = World.toCell(hit)
				send(sendIntent, "move", { x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.T then
			-- T over one of your rigs: send a truck there (an idle one first, otherwise buy one)
			local mouse = UserInputService:GetMouseLocation()
			local best, bestDist = nil, 48
			for id, v in StructureRenderer.each() do
				if v.kind == "rig" and v.side == mySide then
					local p, on = workspace.CurrentCamera:WorldToViewportPoint(World.toWorld(v.x, v.y, 1))
					local d = (Vector2.new(p.X, p.Y) - mouse).Magnitude
					if on and d < bestDist then
						best, bestDist = id, d
					end
				end
			end
			if best then
				sendIntent({ kind = "truck", rigId = best })
			end
		elseif input.KeyCode == Enum.KeyCode.H and next(selected) then
			-- H with the cursor on a town you hold: selected infantry / AT go in (PROVISIONAL key)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				send(sendIntent, "garrison", { x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.R and next(selected) then
			-- R: selected scout cars deploy for recon, command trucks set up an HQ (PROVISIONAL key)
			local ids = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and (v.kind == "scout" or v.kind == "command") then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				sendIntent({ kind = "recon", unitIds = ids })
			end
		elseif input.KeyCode == Enum.KeyCode.V and next(selected) then
			-- V with the cursor on a road: selected engineers plant a charge there (PROVISIONAL key)
			local ids = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "engineer" then
					table.insert(ids, id)
				end
			end
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if #ids > 0 and hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "sabotage", unitIds = ids, x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.P or input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.O then
			-- the capital's powers and airfield drops at the cursor (PROVISIONAL keys)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				local power = if input.KeyCode == Enum.KeyCode.P then "para" elseif input.KeyCode == Enum.KeyCode.J then "demo"
					elseif input.KeyCode == Enum.KeyCode.O then "drone" else "airfield"
				sendIntent({ kind = "power", power = power, x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.Slash and next(selected) then
			-- / unloads the selected IFVs (PROVISIONAL key)
			local ids = {}
			for id in selected do
				table.insert(ids, id)
			end
			sendIntent({ kind = "unload", unitIds = ids })
		elseif input.KeyCode == Enum.KeyCode.Period or input.KeyCode == Enum.KeyCode.Comma then
			-- artillery base at the cursor: . barrage, , flares (PROVISIONAL keys)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "power", power = if input.KeyCode == Enum.KeyCode.Period then "barrage" else "flare", x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.I and next(selected) then
			local ids = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "rocket" then
					table.insert(ids, id)
				end
			end
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if #ids > 0 and hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "barrage", unitIds = ids, x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.N and next(selected) then
			local ids = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "demo" then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				sendIntent({ kind = "detonate", unitIds = ids })
			end
		elseif input.KeyCode == Enum.KeyCode.Delete and picked then
			-- cancel the picked building if it is still going up, else pull it down
			sendIntent({ kind = "demolish", structureId = picked })
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			-- call off the last unit queued at the picked producer (the HQ when none)
			sendIntent({ kind = "cancelQueue", structureId = producerId, index = 0 })
		elseif input.KeyCode == Enum.KeyCode.X and next(selected) then
			send(sendIntent, "stop")
		elseif input.KeyCode == Enum.KeyCode.Escape then
			table.clear(selected)
			refresh()
			picked, producerId = nil, nil
			opts.onProducer(nil, nil)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
			local now = UserInputService:GetMouseLocation()
			local minV, maxV = dragStart:Min(now), dragStart:Max(now)
			box.Position = UDim2.fromOffset(minV.X, minV.Y)
			box.Size = UDim2.fromOffset(maxV.X - minV.X, maxV.Y - minV.Y)
			box.Visible = (now - dragStart).Magnitude >= CLICK_PIXELS
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and dragStart then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			finishSelect(dragStart, UserInputService:GetMouseLocation(), shift)
			dragStart = nil
			box.Visible = false
		end
	end)
end

return SelectionController
