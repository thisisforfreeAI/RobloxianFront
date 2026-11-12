--!strict
--[[
	SelectionController: RTS selection and orders.
	Left click: select own unit (Shift adds it, and all of its kind on screen when that kind is already
	selected; a quick second click picks every unit of its kind on screen, Ctrl + that every unit on
	screen). Left drag: box select (Shift adds).
	Left click on one of your buildings (HQ, barracks, factory): pick it as the producer for the HUD.
	Left click inside one of your towns or cities: pick it for forward training.
	Right click on an enemy unit or building: attack order. Right click on the ground: move order. X: stop. Esc: clear.
	Right click on your IFV with infantry or AT selected: they get in. / unloads selected IFVs.
	1-5: control groups (Ctrl + number makes one, Shift + number adds, the number selects, twice moves the camera).
	Alt + right click: queue a waypoint. Shift + right click: move straight over the land.
	T with the cursor on one of your rigs: send a truck to it.
	R: selected scout cars deploy for recon (PROVISIONAL key).
	H with the cursor on a town you hold: selected infantry / AT garrison it (PROVISIONAL key).
	Right click on one of your damaged buildings with engineers selected: they repair it (PROVISIONAL).
	Right click on a road cut or worn road with engineers selected: they mend it (PROVISIONAL).
	V with engineers selected and the cursor on a road: they sabotage it (PROVISIONAL key).
	7 with engineers selected: drag a line for them to dig a trench; 8 with the cursor on a trench:
	they fill a gap in it; 9 picks the kind of trench to dig (ditch, fire trench, traps, wire belt); 0 with the cursor on a shelled trench:
	they mend it; 0 with infantry selected: they man the fire trench at the cursor (PROVISIONAL keys).
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
local ControlGroups = require(script.Parent.ControlGroups)

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
-- opts.note(text): a short notice; opts.lookAt(x, y): centre the camera on a cell.
local GROUP_KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5 }
function SelectionController.start(mySide: number, sendIntent: (any) -> (), opts: { busy: () -> boolean, onProducer: (number?, string?) -> (), digLine: ({ number }) -> (), cycleTrench: () -> (), note: (string) -> (), lookAt: (number, number) -> (), openRig: (number?) -> () })
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

	local DOUBLE_MS = 350
	local lastPick = { at = 0, id = -1 }
	-- the game's unitsInView: own units whose marker is on screen, optionally of one kind (added to
	-- the selection)
	local function selectInView(kind: string?)
		local size = workspace.CurrentCamera.ViewportSize
		for id, v in UnitRenderer.each() do
			if v.side == mySide and v.kind ~= "truck" and (kind == nil or v.kind == kind) then
				local p, on = screenOf(v)
				if on and p.X >= 0 and p.Y >= 0 and p.X <= size.X and p.Y <= size.Y then
					selected[id] = true
				end
			end
		end
	end
	local function kindSelected(kind: string): boolean
		for id in selected do
			local v = UnitRenderer.each()[id]
			if v and v.kind == kind then
				return true
			end
		end
		return false
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
				-- like the game's selectAt: a second click on the same unit within 350 ms (the game's
				-- doubleMs) picks every unit of its kind on screen (Ctrl: every unit on screen); Shift +
				-- click adds it, and when its kind is already selected adds all of that kind on screen
				opts.openRig(nil)
				local now = os.clock() * 1000
				local double = not additive and now - lastPick.at <= DOUBLE_MS and lastPick.id == best
				lastPick = { at = if double then 0 else now, id = best }
				local kind = UnitRenderer.each()[best].kind
				local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				if double then
					selectInView(if ctrl then nil else kind)
				elseif additive and kindSelected(kind) then
					selected[best] = true
					selectInView(kind)
				else
					selected[best] = true
				end
			else
				local own = structureUnder(b, function(v)
					return v.side == mySide
				end)
				picked = if own then own.id else nil
				StructureRenderer.setFocus(picked)
				-- one of your rigs: open its card (the game's RigCard); a click anywhere else closes it
				opts.openRig(if own and own.kind == "rig" then own.id else nil)
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

	-- control groups (see ControlGroups): Ctrl + number makes one, Shift + number adds to it, the
	-- number selects it, twice quickly also moves the camera there
	local groups = ControlGroups.new()
	local function unitOk(id: number): boolean
		local v = UnitRenderer.each()[id]
		return v ~= nil and v.side == mySide
	end
	local function structureOk(id: number): boolean
		local v = StructureRenderer.each()[id]
		return v ~= nil and v.side == mySide
	end
	local function selection(): ({ number }, number?)
		local ids = {}
		for id in selected do
			if unitOk(id) then
				table.insert(ids, id)
			end
		end
		return ids, if picked and structureOk(picked) then picked else nil
	end
	local function controlGroup(n: number)
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if ctrl then
			local ids, st = selection()
			local count = ControlGroups.set(groups, n, ids, st)
			opts.note(if count > 0 then `Group {n}: {count}` else `Group {n} cleared`)
		elseif shift then
			local ids, st = selection()
			local count = ControlGroups.add(groups, n, ids, st, unitOk, structureOk)
			if count then
				opts.note(`Group {n}: {count}`)
			end
		else
			local ids, st, double = ControlGroups.recall(groups, n, os.clock() * 1000, unitOk, structureOk)
			if #ids > 0 then
				table.clear(selected)
				local sx, sy = 0, 0
				for _, id in ids do
					selected[id] = true
					local x, y = World.toCell(UnitRenderer.each()[id].body.Position)
					sx += x
					sy += y
				end
				refresh()
				if double then
					opts.lookAt(sx / #ids, sy / #ids)
				end
			elseif st then
				local v = StructureRenderer.each()[st]
				table.clear(selected)
				refresh()
				picked = st
				StructureRenderer.setFocus(picked)
				if PRODUCERS[v.kind] then
					producerId = st
					opts.onProducer(st, v.kind)
				end
				if double then
					opts.lookAt(v.x, v.y)
				end
			end
		end
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
			-- engineers selected and one of your damaged buildings or rigs under the cursor: repair it
			local engineers = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "engineer" then
					table.insert(engineers, id)
				end
			end
			if #engineers > 0 then
				local own = structureUnder(mouse, function(v)
					return v.side == mySide and v.built >= 1 and v.hp ~= nil and v.maxHp ~= nil and v.hp < v.maxHp
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
				-- like the game's modifiers: Alt + right click queues a waypoint after the current move,
				-- Shift + right click goes straight over the land (both together: a straight waypoint)
				local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				local alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
				send(sendIntent, if alt then "waypoint" else "move", { x = x, y = y, direct = shift })
			end
		elseif input.KeyCode == Enum.KeyCode.T then
			-- T over one of your rigs: send a truck there (an idle one first, otherwise buy one);
			-- Shift+T takes one off it (it drives home and waits idle); Alt+T switches its trucks to the next
			-- way on offer: each route to the HQ, then each working refinery (the way to pick a new one
			-- when the route is cut)
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
			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if best and ctrl then
				-- Ctrl+T upgrades the rig's pump, Ctrl+Shift+T its tank (the game's upgradeRig; PROVISIONAL keys)
				sendIntent({ kind = "upgradeRig", rigId = best, upgrade = if shift then "tank" else "pump" })
			elseif best then
				local alt = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
				sendIntent({ kind = "truck", rigId = best, release = if shift and not alt then true else nil, reroute = if alt then true else nil })
			end
		elseif input.KeyCode == Enum.KeyCode.H and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
			-- Shift+H with the cursor on a town you hold: everyone inside comes out (PROVISIONAL key)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "withdraw", x = x, y = y })
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
		elseif input.KeyCode == Enum.KeyCode.Nine then
			opts.cycleTrench()
		elseif (input.KeyCode == Enum.KeyCode.Seven or input.KeyCode == Enum.KeyCode.Eight or input.KeyCode == Enum.KeyCode.Zero) and next(selected) then
			local ids = {}
			for id in selected do
				local v = UnitRenderer.each()[id]
				if v and v.kind == "engineer" then
					table.insert(ids, id)
				end
			end
			local man = false
			if #ids == 0 and input.KeyCode == Enum.KeyCode.Zero then
				-- no engineers: selected infantry man the fire trench at the cursor
				for id in selected do
					local v = UnitRenderer.each()[id]
					if v and (v.kind == "infantry" or v.kind == "at" or v.kind == "mortar" or v.kind == "para") then
						table.insert(ids, id)
					end
				end
				man = true
			end
			if #ids == 0 then
				return
			end
			if input.KeyCode == Enum.KeyCode.Seven then
				opts.digLine(ids)
			else
				local hit = groundPoint(UserInputService:GetMouseLocation())
				if hit then
					local x, y = World.toCell(hit)
					sendIntent({ kind = if man then "man" elseif input.KeyCode == Enum.KeyCode.Zero then "mend" else "fill", unitIds = ids, x = x, y = y })
				end
			end
		elseif input.KeyCode == Enum.KeyCode.V and next(selected) then
			-- V with the cursor on a road or a dug trench: selected engineers plant a charge there (PROVISIONAL key)
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
		elseif input.KeyCode == Enum.KeyCode.LeftBracket then
			-- [ on a village, town or city you hold: build a refinery there (PROVISIONAL key)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "refinery", x = x, y = y })
			end
		elseif input.KeyCode == Enum.KeyCode.RightBracket then
			-- ] at the cursor: rally point for the picked producer (the HQ when none); Shift+] clears it (PROVISIONAL key)
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				sendIntent({ kind = "rally", structureId = producerId })
			else
				local hit = groundPoint(UserInputService:GetMouseLocation())
				if hit then
					local x, y = World.toCell(hit)
					sendIntent({ kind = "rally", structureId = producerId, x = x, y = y })
				end
			end
		elseif input.KeyCode == Enum.KeyCode.Equals then
			-- = on a road: put up a road sign shutting it to your trucks, or take yours down (PROVISIONAL key)
			local hit = groundPoint(UserInputService:GetMouseLocation())
			if hit then
				local x, y = World.toCell(hit)
				sendIntent({ kind = "roadSign", x = x, y = y })
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
		elseif input.KeyCode == Enum.KeyCode.BackSlash and next(selected) then
			-- \ : the selected units fall back to the nearest HQ, faster and holding fire (PROVISIONAL key)
			send(sendIntent, "retreat")
		elseif input.KeyCode == Enum.KeyCode.Escape then
			table.clear(selected)
			refresh()
			picked, producerId = nil, nil
			StructureRenderer.setFocus(nil)
			opts.onProducer(nil, nil)
		elseif GROUP_KEYS[input.KeyCode] then
			controlGroup(GROUP_KEYS[input.KeyCode])
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

-- true when any selected unit is a bomb truck (then N detonates instead of switching night vision)
function SelectionController.demoSelected(): boolean
	for id in selected do
		local v = UnitRenderer.each()[id]
		if v and v.kind == "demo" then
			return true
		end
	end
	return false
end

return SelectionController
