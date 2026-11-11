--!strict
--[[
	WaterRenderer: WarFront's moving water (surf, crests, swell, tide, river flow, glints) as a layer
	over the baked ground.

	The data is src/client/DevAssets/Water_<mapId>.luau, written by tools/conversion/export_water.cjs
	from the local install (git-ignored: the game's settings and ground art). It holds the map in chunks
	of 64 x 64 cells: each texel's ground colour and mask code (FINE texels a cell), and the game's water
	map (river direction, speed, distance from the shore). No module, or a map without water (Saddle),
	and nothing is drawn.

	Each chunk near the camera gets a small EditableImage (FINE x 64 px a side) from the shared
	ImageMemory budget, as "detail" art that yields under pressure, on a flat part just above the ground
	and under the towns and roads. Land texels stay clear, so the baked ground shows through. On load,
	the parts of the game's shader that never change are worked out once per texel (the depth bands, and
	each texel's lots for the surf, crests, tide and glints). The moving parts are repainted from
	WaterShade a band of rows at a time, within a frame budget, for the chunks on screen only.
	APPROX: see WaterShade (hash numbers, repaint cadence). Also, a tide texel at a chunk's edge does not
	see water in the next chunk, and river streamlines are worked out at texel centres rather than per
	screen pixel.

	Integration (wired from init.client; see docs/WATER_INTEGRATION.md):
	  WaterRenderer.build(mapId, parent) after the map is built; WaterRenderer.destroy() to drop it.
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local MapCodec = require(Shared.Maps.MapCodec)
local Inflate = require(Shared.Utilities.Inflate)
local WaterShade = require(Shared.Presentation.WaterShade)
local ImageMemory = require(script.Parent.ImageMemory)
-- Legacy injected test backends write immediately; the live memory service queues these writes.
local upload=ImageMemory.upload or function(image,position,size,pixels,options)
	image:WritePixelsBuffer(position,size,pixels);if options and options.done then options.done(true) end;return true
end
local DaylightController = require(script.Parent.DaylightController)
local WorldLight = require(script.Parent.WorldLight)

local WaterRenderer = {}

local S = World.STUDS_PER_CELL
local HEIGHT = 0.03 -- above the ground (0), under the towns (0.07) and the roads (0.15)
local CHECK_SEC = 0.2
local MAX_LOADED = 12
local KEEP_REACH = 1.5 -- loaded chunks stay until this far past the view
local REPAINT_MS = 3 -- per frame, time spent repainting
local ANIMATE_FROM = 2 -- screen pixels a cell below which the water is left still (too small to see move)
local RECLAIM_PRIORITY = 10 -- same as the town detail: unused detail goes first

type Chunk = {
	cx: number, cy: number, cw: number, ch: number, fine: string, wmap: string,
	tw: number, th: number,
	image: any, part: Part?, px: buffer?,
	-- per drawn texel (n of them), parallel: where, and what was worked out once
	n: number, at: buffer?, base: buffer?, info: buffer?, lots: buffer?, river: buffer?,
	row: number, -- next row to repaint
	distance: number, visible: boolean,
	failed: boolean,
}

local state: any = nil

local function imagePart(name: string, cx: number, cy: number, cw: number, ch: number, size: Vector2, parent: Instance): (Part, ImageLabel)
	-- turned like the ground (image x east, y south), as TownRenderer's parts
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(ch * S, 0.05, cw * S)
	part.CFrame = CFrame.new((cx + cw / 2) * S, World.GROUND_Y + HEIGHT, (cy + ch / 2) * S) * CFrame.Angles(0, World.TOP_GUI_YAW, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = size
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.Parent = gui
	part.Parent = parent
	return part, label
end

-- info flags (u8 per texel): low 4 bits the mask code; bit 4 tide one texel off the sea, bit 5 two off,
-- bit 6 ragged, bit 7 open water (glints)
local TIDE1, TIDE2, RAGGED, OPEN = 16, 32, 64, 128

-- the fixed part of every drawn texel of a chunk
local function prepare(c: Chunk, Sx: any)
	local F = Sx.fine
	local codes = Sx.codes
	local tw, th = c.cw * F, c.ch * F
	c.tw, c.th = tw, th
	local raw = Inflate.raw(MapCodec.base64Decode(c.fine), tw * th * 4)
	local mw, mh = c.cw + 2, c.ch + 2
	local wm = Inflate.raw(MapCodec.base64Decode(c.wmap), mw * mh * 4)
	local function code(x: number, y: number): number
		if x < 0 or y < 0 or x >= tw or y >= th then
			return 0
		end
		return buffer.readu8(raw, (y * tw + x) * 4 + 3)
	end
	local function wetKind(x: number, y: number): number
		local m = code(x, y)
		if m == codes.river then
			return 2
		end
		return if m >= codes.shallowNear and m <= codes.crestTail then 1 else 0
	end
	-- the water map, read smoothed between cells as the GPU does (texel centres at cell + 0.5)
	local function wmapAt(p: number, q: number): (number, number, number, number)
		local fx, fy = p - c.cx + 1 - 0.5, q - c.cy + 1 - 0.5
		local x0, y0 = math.floor(fx), math.floor(fy)
		local ax, ay = fx - x0, fy - y0
		local out = { 0, 0, 0, 0 }
		for ch = 0, 3 do
			local function at(x: number, y: number): number
				x, y = math.clamp(x, 0, mw - 1), math.clamp(y, 0, mh - 1)
				return buffer.readu8(wm, (y * mw + x) * 4 + ch) / 255
			end
			local top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * ax
			local bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * ax
			out[ch + 1] = top + (bottom - top) * ay
		end
		return out[1], out[2], out[3], out[4]
	end
	local count = 0
	for i = 0, tw * th - 1 do
		if buffer.readu8(raw, i * 4 + 3) ~= 0 then
			count += 1
		end
	end
	c.n = count
	local at = buffer.create(count * 4)
	local base = buffer.create(count * 12)
	local info = buffer.create(count)
	local lots = buffer.create(count * 8) -- surf / crest / tide lot, glint lot
	local river = buffer.create(count * 16) -- dir x, dir y, speed, shore (cells)
	local D, U, C, T = Sx.depth, Sx.surf, Sx.crest, Sx.tide
	local k = 0
	for ty = 0, th - 1 do
		for tx = 0, tw - 1 do
			local i = ty * tw + tx
			local m = buffer.readu8(raw, i * 4 + 3)
			if m == 0 then
				continue
			end
			local gx, gy = c.cx * F + tx, c.cy * F + ty -- the texel on the whole map's fine grid
			local cellX, cellY = math.floor(gx / F), math.floor(gy / F)
			local r, g, b = buffer.readu8(raw, i * 4) / 255, buffer.readu8(raw, i * 4 + 1) / 255, buffer.readu8(raw, i * 4 + 2) / 255
			local flags = m
			local lot, glintLot = 0, 0
			local wx, wy, wz, ww = 0, 0, 0, 0
			if m == codes.sand then
				local near = math.max(wetKind(tx + 1, ty), wetKind(tx - 1, ty), wetKind(tx, ty + 1), wetKind(tx, ty - 1))
				local nxt = math.max(wetKind(tx + 2, ty), wetKind(tx - 2, ty), wetKind(tx, ty + 2), wetKind(tx, ty - 2),
					wetKind(tx + 1, ty + 1), wetKind(tx - 1, ty - 1), wetKind(tx + 1, ty - 1), wetKind(tx - 1, ty + 1))
				if math.max(near, nxt) == 1 then
					flags += if near > 0 then TIDE1 else TIDE2
					lot = WaterShade.tideLot(cellX, cellY, T.segment)
					if WaterShade.raggedOf(gx, gy, T) then
						flags += RAGGED
					end
				end
			else
				local p, q = (gx + 0.5) / F, (gy + 0.5) / F
				local a, bb, z, w = wmapAt(p, q)
				local dx, dy = a * 2 - 1, bb * 2 - 1
				local len = math.sqrt(dx * dx + dy * dy)
				wx, wy = if len > 0.02 then dx / len else 0, if len > 0.02 then dy / len else 0
				wz, ww = z, w * D.far
				if m ~= codes.river then
					r, g, b = WaterShade.depthBands(r, g, b, gx, gy, ww, D)
				end
				if m == codes.foam then
					lot = WaterShade.surfLot(cellX, cellY, U.segment, false)
				elseif m == codes.foamFar then
					lot = WaterShade.surfLot(cellX, cellY, U.segment, true)
				elseif m == codes.crestHead or m == codes.crestTail then
					lot = WaterShade.crestLot(gx, cellY, C.texels)
				end
				if m == codes.deep or m == codes.shallow or m == codes.shallowNear or m == codes.fleck
					or m == codes.crestHead or m == codes.crestTail or m == codes.foamFar then
					flags += OPEN
					glintLot = WaterShade.glintLot(gx, gy)
				end
			end
			buffer.writeu32(at, k * 4, i)
			buffer.writef32(base, k * 12, r)
			buffer.writef32(base, k * 12 + 4, g)
			buffer.writef32(base, k * 12 + 8, b)
			buffer.writeu8(info, k, flags)
			buffer.writef32(lots, k * 8, lot)
			buffer.writef32(lots, k * 8 + 4, glintLot)
			buffer.writef32(river, k * 16, wx)
			buffer.writef32(river, k * 16 + 4, wy)
			buffer.writef32(river, k * 16 + 8, wz)
			buffer.writef32(river, k * 16 + 12, ww)
			k += 1
		end
	end
	c.at, c.base, c.info, c.lots, c.river = at, base, info, lots, river
	c.px = buffer.create(tw * th * 4) -- clear everywhere until painted
	c.row = 0
end

-- paints texels [from, to) of the chunk's list into its pixel buffer; returns the rows touched
local function paint(c: Chunk, from: number, to: number, now: number, Sx: any, noise: WaterShade.Noise, light: any): (number, number)
	local codes, D, U, C, T, G, Fl = Sx.codes, Sx.depth, Sx.surf, Sx.crest, Sx.tide, Sx.glints, Sx.flow
	local F = Sx.fine
	local px, at, base, info, lots, river = c.px :: buffer, c.at :: buffer, c.base :: buffer, c.info :: buffer, c.lots :: buffer, c.river :: buffer
	local tw = c.tw
	local glintK = light.glintK
	local sun = light.color
	local sea = Sx.sea
	local firstRow, lastRow = math.huge, -1
	for k = from, to - 1 do
		local i = buffer.readu32(at, k * 4)
		local flags = buffer.readu8(info, k)
		local m = flags % 16
		local r, g, b = buffer.readf32(base, k * 12), buffer.readf32(base, k * 12 + 4), buffer.readf32(base, k * 12 + 8)
		local tx, ty = i % tw, i // tw
		local gx, gy = c.cx * F + tx, c.cy * F + ty
		local lot = buffer.readf32(lots, k * 8)
		if m == codes.sand then
			if bit32.btest(flags, TIDE1 + TIDE2) then
				r, g, b = WaterShade.tide(r, g, b, if bit32.btest(flags, TIDE1) then 1 else 2, lot, bit32.btest(flags, RAGGED), now, T, U.color)
			end
		else
			local wz, ww = buffer.readf32(river, k * 16 + 8), buffer.readf32(river, k * 16 + 12)
			if m ~= codes.river then
				local open = WaterShade.openOf(ww, D)
				if open > 0 then
					r, g, b = WaterShade.swell(noise, r, g, b, gx, gy, open, now, D)
				end
			end
			if m == codes.foam then
				r, g, b = WaterShade.surf(r, g, b, lot, false, now, U)
			elseif m == codes.foamFar then
				r, g, b = WaterShade.surf(r, g, b, lot, true, now, U)
			elseif m == codes.crestHead or m == codes.crestTail then
				r, g, b = WaterShade.crest(r, g, b, lot, m == codes.crestHead, now, C, sea)
			elseif wz > 0 then
				local wx, wy = buffer.readf32(river, k * 16), buffer.readf32(river, k * 16 + 4)
				r, g, b = WaterShade.flow(noise, r, g, b, (gx + 0.5) / F, (gy + 0.5) / F, wx, wy, wz, ww, now, Fl, 1 / F)
			end
			if glintK > 0 and bit32.btest(flags, OPEN) and WaterShade.glints(gx, gy, buffer.readf32(lots, k * 8 + 4), now, G) then
				local s = math.min(1, glintK)
				r, g, b = r + (sun[1] - r) * s, g + (sun[2] - g) * s, b + (sun[3] - b) * s
			end
		end
		local o = i * 4
		buffer.writeu8(px, o, math.clamp(math.floor(r * 255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 1, math.clamp(math.floor(g * 255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 2, math.clamp(math.floor(b * 255 + 0.5), 0, 255))
		buffer.writeu8(px, o + 3, 255)
		if ty < firstRow then
			firstRow = ty
		end
		if ty > lastRow then
			lastRow = ty
		end
	end
	return firstRow, lastRow
end

-- returns true when the water was set up (the map has water and its module is there)
function WaterRenderer.build(mapId: string, parent: Instance): boolean
	WaterRenderer.destroy()
	local assets = script.Parent.Parent:FindFirstChild("DevAssets")
	local mod = assets and assets:FindFirstChild("Water_" .. mapId)
	if not mod or not mod:IsA("ModuleScript") then
		return false
	end
	local ok, meta = pcall(require, mod)
	if not ok then
		warn("[WaterRenderer] Water_" .. mapId .. " could not be read:", meta)
		return false
	end
	if not meta.water or not meta.chunks or #meta.chunks == 0 then
		return false
	end
	local Sx = meta.settings
	local folder = Instance.new("Folder")
	folder.Name = "Water"
	folder.Parent = parent
	local chunks: { Chunk } = {}
	for _, e in meta.chunks do
		table.insert(chunks, {
			cx = e[1], cy = e[2], cw = e[3], ch = e[4], fine = e[5], wmap = e[6], tw = 0, th = 0,
			image = nil, part = nil, px = nil, n = 0, at = nil, base = nil, info = nil, lots = nil, river = nil,
			row = 0, distance = math.huge, visible = false,
			failed = false,
		})
	end
	local noise = WaterShade.newNoise()
	local st = { folder = folder, chunks = chunks, connections = {} :: { RBXScriptConnection }, unregister = nil :: (() -> ())?, holdUntil = 0 }
	state = st
	table.insert(st.connections,folder.Destroying:Connect(function()
		if state==st then WaterRenderer.destroy() end
	end))

	local function unload(c: Chunk)
		if c.part then
			c.part:Destroy()
			c.part = nil
		end
		if c.image then
			ImageMemory.release(c.image)
			c.image = nil
		end
		c.px, c.at, c.base, c.info, c.lots, c.river = nil, nil, nil, nil, nil, nil
		c.n = 0
	end
	local function load(c: Chunk): boolean
		local size = Vector2.new(c.cw * Sx.fine, c.ch * Sx.fine)
		if not ImageMemory.canDetail(size) then
			return false
		end
		local okPrep, err = pcall(prepare, c, Sx)
		if not okPrep then
			c.px, c.at, c.base, c.info, c.lots, c.river = nil, nil, nil, nil, nil, nil
			c.failed=true
			warn("[WaterRenderer] a chunk could not be read:", err)
			return true -- skip it, not a budget problem
		end
		local image = ImageMemory.create(size, "detail")
		if not image then
			c.px, c.at, c.base, c.info, c.lots, c.river = nil, nil, nil, nil, nil, nil
			return false
		end
		c.image = image
		local part, label = imagePart(`Water_{c.cx}_{c.cy}`, c.cx, c.cy, c.cw, c.ch, size, folder)
		label.ImageContent = Content.fromObject(image)
		c.part = part
		return true
	end
	st.unregister = ImageMemory.register(RECLAIM_PRIORITY, function(needed: number, _protected: any)
		st.holdUntil=os.clock()+1.5
		local before = ImageMemory.stats()
		local shown = {}
		for _, c in chunks do
			if c.image then
				table.insert(shown, c)
			end
		end
		table.sort(shown, function(a, b)
			return a.distance > b.distance
		end)
		for _, c in shown do
			unload(c)
			if before - ImageMemory.stats() >= needed then
				break
			end
		end
	end)

	local animate = false
	local acc = CHECK_SEC
	local lightStamp = ""
	table.insert(st.connections, RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CHECK_SEC then
			return
		end
		acc = 0
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local view=WorldLight.view(cam)
		animate = view.cellPixels >= ANIMATE_FROM
		local fx, fy = view.cx,view.cy
		local reach = math.max(view.rx,view.ry)*1.4
		-- Still far-zoom water must also update after daylight changes.
		local sample=DaylightController.get();local tint=sample.color or {1,1,1}
		local nextStamp=table.concat({math.floor((sample.night or 0)*32),math.floor((sample.elevation or 1)*32),math.floor(tint[1]*32),math.floor(tint[2]*32),math.floor(tint[3]*32)},":")
		if nextStamp~=lightStamp then
			lightStamp=nextStamp
			for _,c in chunks do if c.row<0 then c.row=0 end end
		end
		for _, c in chunks do
			local nx = math.clamp(fx, c.cx, c.cx + c.cw)
			local ny = math.clamp(fy, c.cy, c.cy + c.ch)
			c.distance = math.sqrt((nx - fx) ^ 2 + (ny - fy) ^ 2)
			c.visible = c.distance <= reach
		end
		local order = table.clone(chunks)
		for i=#order,1,-1 do if order[i].failed then table.remove(order,i) end end
		table.sort(order, function(a, b)
			return a.distance < b.distance
		end)
		local keep: { [Chunk]: boolean } = {}
		for i = 1, math.min(#order, MAX_LOADED) do
			if order[i].distance <= reach * KEEP_REACH then
				keep[order[i]] = true
			end
		end
		for _, c in chunks do
			if c.image and not keep[c] then
				unload(c)
			end
		end
		if os.clock() < st.holdUntil then
			return
		end
		for _, c in order do
			if c.visible and not c.image and keep[c] then
				if not load(c) then
					st.holdUntil = os.clock() + 1.5 -- the budget is full: try again shortly
				end
				break -- one chunk a check: preparing one takes a few milliseconds
			end
		end
	end))

	-- repaint the chunks on screen, a band at a time
	local cursor = 1
	local noiseAt=os.clock()
	table.insert(st.connections, RunService.RenderStepped:Connect(function()
		local sample = DaylightController.get()
		local light = {
			color = sample.color or { 1, 1, 1 },
			glintK = WaterShade.glintStrength(Sx.glints, sample.night or 0, sample.elevation or 1),
		}
		local now = os.clock()
		-- APPROX CPU cache policy: deterministic noise can be regenerated without retaining
		-- every lattice point visited during an indefinitely long match.
		if now-noiseAt>10 then noise=WaterShade.newNoise();noiseAt=now end
		local t0 = now
		local skipped = 0
		while os.clock() - t0 < REPAINT_MS / 1000 and skipped < #chunks do
			local c = chunks[cursor]
			-- not loaded; or off screen or too small to see move, and already painted once: left still
			if not c.image or not c.px or c.n == 0 or ((not c.visible or not animate) and c.row < 0) then
				cursor = cursor % #chunks + 1
				skipped += 1
				continue
			end
			skipped = 0
			local from = math.max(0, c.row)
			local to = math.min(c.n, from + 2048)
			local r0, r1 = paint(c, from, to, now, Sx, noise, light)
			if r1 >= r0 then
				local rows = r1 - r0 + 1
				local band = buffer.create(c.tw * rows * 4)
				buffer.copy(band, 0, c.px :: buffer, r0 * c.tw * 4, c.tw * rows * 4)
				local target=c.image
				local wrote,err=pcall(function() return upload(target,Vector2.new(0,r0),Vector2.new(c.tw,rows),band,{priority=3,key="band:"..r0..":"..r1,done=function(ok)
					if not ok and c.image==target then unload(c);c.failed=true end
				end}) end)
				if not wrote then
					unload(c);c.failed=true;warn("[WaterRenderer] a chunk could not be painted:",err)
					cursor=cursor % #chunks+1;skipped+=1;continue
				end
				if err==false then break end -- retain this row until the bounded queue admits it
			end
			if to >= c.n then
				c.row = if c.visible and animate then 0 else -1
				cursor = cursor % #chunks + 1 -- a full pass done: the next chunk's turn
			else
				c.row = to
			end
		end
	end))
	print(`[WaterRenderer] {mapId}: {#chunks} water chunks; the ones near the camera are drawn and animated`)
	return true
end

function WaterRenderer.destroy()
	local st = state
	if not st then
		return
	end
	state = nil
	for _, conn in st.connections do
		conn:Disconnect()
	end
	if st.unregister then
		st.unregister()
	end
	for _, c in st.chunks do
		if c.part then
			c.part:Destroy()
		end
		if c.image then
			ImageMemory.release(c.image)
		end
	end
	st.folder:Destroy()
end

return WaterRenderer
