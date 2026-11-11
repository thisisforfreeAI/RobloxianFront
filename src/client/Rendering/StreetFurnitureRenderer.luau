--!strict
--[[
	StreetFurnitureRenderer: lamp posts at the game's street lamp spots.

	PORT ADDITION. The game marks its street lamps as single texels (invisible by day, lit at night,
	both already drawn by TownRenderer and NightLightRenderer) and draws no post. This stands a post
	at each of those spots, with the head over the lamp texel so the night layer's light falls on it.
	The post, its art and shadow are this port's (Shared.Presentation.StreetFurniture); the spots come
	from the git-ignored DevAssets/StreetFurniture_<id>.luau (tools/asset_pipeline/pack_street_furniture.py).

	- One small atlas (16 facings, two rows) drawn in code into one "detail" image from the shared
	  ImageMemory budget; a reclaimer at priority 10 (as town detail) gives it back under pressure, and
	  it is released after 3 s with no posts on screen.
	- Posts show only zoomed in (StreetFurniture.FROM to FULL screen px a cell), only in the camera's
	  view, and not on fogged cells.
	- The shadow follows DaylightController (sun or moon direction, fading at night). The day/night
	  grade comes from the shared post effect, as for every other part in the world.
	- They sit at GROUND_Y + 0.2: over the town art (0.08) and roads (0.15), under the night lights
	  (0.24), cars (0.29) and units.
	APPROX: posts stay up when their town is ruined or shelled (the game has none to knock down).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local SF = require(Shared.Presentation.StreetFurniture)
local Memory = require(script.Parent.ImageMemory)
local Fog = require(script.Parent.FogOverlay)
local Daylight = require(script.Parent.DaylightController)

local Renderer = {}

local HEIGHT = 0.2
local MAX_VIEWS = 300
local FRAME = SF.FRAME
local CANVAS = 3 * FRAME -- room round the post for its shadow
local S = World.STUDS_PER_CELL

local current: any = nil

function Renderer.destroy()
	if current then
		current.folder:Destroy()
	end
end

-- map: the client's map ({ width, height, data = { id } }); returns true when posts will be drawn
function Renderer.start(map: any, parent: Instance?): boolean
	Renderer.destroy()
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local module = assets and assets:FindFirstChild("StreetFurniture_" .. map.data.id)
	if not module then
		warn("[StreetFurniture] Generate DevAssets/StreetFurniture_" .. map.data.id .. " with pack_street_furniture.py to show lamp posts")
		return false
	end
	local ok, data = pcall(require, module :: ModuleScript)
	if not ok or type(data) ~= "table" or type(data.lamps) ~= "table" then
		warn("[StreetFurniture] Lamp data unavailable:", data)
		return false
	end
	local lamps: { number } = data.lamps
	if #lamps < 3 then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "StreetFurniture"
	folder.Parent = parent or workspace
	local session: any = { folder = folder }
	current = session

	local grid = SF.grid(lamps)
	local pxPerCell = SF.SCALE * (data.cellPx or 14)
	local partStuds = CANVAS / pxPerCell * S
	local aw, ah = SF.atlasSize()
	local atlas: EditableImage? = nil
	local pixels: buffer? = nil
	local retry, idle = 0, os.clock()
	local disabled = false
	local views: { [number]: any } = {}
	local lastShadow = ""

	local function clearViews()
		for _, v in views do
			v.part:Destroy()
		end
		table.clear(views)
	end
	local function clear()
		clearViews()
		if atlas then
			Memory.release(atlas)
			atlas = nil
		end
	end
	local unregister = Memory.register(10, function()
		if atlas then
			clear()
			retry = os.clock() + 5
		end
	end)

	local function image(): boolean
		if atlas then
			return true
		end
		if os.clock() < retry then
			return false
		end
		local size = Vector2.new(aw, ah)
		atlas = Memory.create(size, "detail")
		if not atlas then
			retry = os.clock() + 5
			return false
		end
		local written, err = pcall(function()
			pixels = pixels or SF.drawAtlas()
			local target = atlas :: EditableImage
			target:WritePixelsBuffer(Vector2.zero, size, pixels :: buffer)
		end)
		if not written then
			clear()
			disabled = true
			warn("[StreetFurniture] Atlas unavailable:", err)
			return false
		end
		lastShadow = ""
		return true
	end

	local function create(i: number): any
		local x, y, angle = lamps[i], lamps[i + 1], lamps[i + 2]
		local f = SF.facing(angle)
		local a = SF.facingAngle(f)
		local part = Instance.new("Part")
		part.Name = "LampPost"
		part.Anchored = true
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Size = Vector3.new(partStuds, 0.01, partStuds)
		part.CFrame = CFrame.new(World.toWorld(x, y, HEIGHT)) * CFrame.Angles(0, World.TOP_GUI_YAW, 0)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(CANVAS, CANVAS)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = 0
		gui.ClipsDescendants = false
		local pole = Instance.new("Frame")
		pole.Name = "PoleShadow"
		pole.AnchorPoint = Vector2.new(0.5, 0.5)
		pole.BorderSizePixel = 0
		pole.BackgroundColor3 = Color3.new(0, 0, 0)
		pole.Parent = gui
		local function label(row: number, name: string): ImageLabel
			local l = Instance.new("ImageLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Size = UDim2.fromOffset(FRAME, FRAME)
			l.Position = UDim2.fromOffset(CANVAS / 2, CANVAS / 2)
			l.ImageContent = Content.fromObject(atlas :: EditableImage)
			l.ImageRectSize = Vector2.new(FRAME, FRAME)
			l.ImageRectOffset = Vector2.new(f * FRAME, row * FRAME)
			l.ResampleMode = Enum.ResamplerMode.Default
			l.Parent = gui
			return l
		end
		local shadow = label(1, "Shadow")
		shadow.ImageColor3 = Color3.new(0, 0, 0)
		local body = label(0, "Post")
		gui.Parent = part
		part.Parent = folder
		local reach = SF.ARM * SF.SCALE
		return { part = part, pole = pole, shadow = shadow, body = body,
			footX = CANVAS / 2 - math.cos(a) * reach, footY = CANVAS / 2 - math.sin(a) * reach }
	end

	local function place(v: any, share: number, sdx: number, sdy: number, alpha: number)
		v.body.ImageTransparency = 1 - share
		local ox, oy = sdx * pxPerCell, sdy * pxPerCell
		v.shadow.Position = UDim2.fromOffset(CANVAS / 2 + ox, CANVAS / 2 + oy)
		v.shadow.ImageTransparency = 1 - alpha * share
		local len = math.sqrt(ox * ox + oy * oy)
		v.pole.Visible = len > 0.5
		v.pole.Size = UDim2.fromOffset(len, 1.6)
		v.pole.Position = UDim2.fromOffset(v.footX + ox / 2, v.footY + oy / 2)
		v.pole.Rotation = math.deg(math.atan2(oy, ox))
		v.pole.BackgroundTransparency = 1 - alpha * share
	end

	local connection = RunService.RenderStepped:Connect(function()
		if disabled then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local distance = math.max(1, camera.CFrame.Position.Y - World.GROUND_Y)
		local ry = distance * math.tan(math.rad(camera.FieldOfView / 2)) / S
		local rx = ry * camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
		local share = SF.share(camera.ViewportSize.Y / (2 * ry))
		if share <= 0 then
			if next(views) then
				clearViews()
			end
			if atlas and os.clock() - idle > 3 then
				clear() -- APPROX idle storage policy, as the car atlas
			end
			return
		end
		local sdx, sdy, alpha = SF.shadow(Daylight.get())
		local stamp = string.format("%.3f,%.3f,%.3f,%.3f", sdx, sdy, alpha, share)
		local changed = stamp ~= lastShadow
		lastShadow = stamp
		local cx, cy = camera.CFrame.Position.X / S, camera.CFrame.Position.Z / S
		local wanted: { [number]: boolean } = {}
		local count = 0
		for _, i in SF.query(grid, cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1) do
			if count >= MAX_VIEWS then
				break
			end
			if Fog.hidden(lamps[i], lamps[i + 1]) then
				continue
			end
			-- Allocate only for an in-view, visible post; an empty/fogged camera must stay idle.
			if not image() then
				break
			end
			count += 1
			wanted[i] = true
			local v = views[i]
			if not v then
				v = create(i)
				views[i] = v
				place(v, share, sdx, sdy, alpha)
			elseif changed then
				place(v, share, sdx, sdy, alpha)
			end
		end
		for i, v in views do
			if not wanted[i] then
				v.part:Destroy()
				views[i] = nil
			end
		end
		if next(views) then
			idle = os.clock()
		elseif atlas and os.clock() - idle > 3 then
			clear()
		end
	end)

	folder.Destroying:Connect(function()
		connection:Disconnect()
		unregister()
		clear()
		if current == session then
			current = nil
		end
	end)
	print(`[StreetFurniture] {map.data.id}: {#lamps // 3} lamp posts`)
	return true
end

return Renderer
