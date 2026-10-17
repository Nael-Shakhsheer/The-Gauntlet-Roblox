--!nonstrict
-- Builds the whole connected Adventure world from a WorldLayout:
--   * surface ground (chunked slabs, holes for cave mouths), trails, signposts
--   * cave chambers + tunnels under the surface, reached by descending ramps
--   * Briarwatch tower floors with stairs, door and roof-exit ramp
--   * area contents (AreaBuilder.populate) and wilderness scatter
-- Everything is parented to Workspace.World in one go at the end (fast).
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local WorldLayout = require(Shared.WorldLayout)

local AreaBuilder = require(script.Parent.AreaBuilder)
local Scenic = require(script.Parent.Scenic)

local Adventure = Data.Adventure

local WorldBuilder = {}

local TRAIL_COLOR = Color3.fromRGB(148, 122, 84)
local TUNNEL_COLOR = Color3.fromRGB(70, 80, 88)
local WALL_COLOR = Color3.fromRGB(86, 96, 104)

-- rect = { minX, maxX, minZ, maxZ }; the slab's top face sits at topY.
local function slab(parent, r, topY: number, thickness: number, color: Color3, material, name)
	local sx, sz = r[2] - r[1], r[4] - r[3]
	if sx < 0.05 or sz < 0.05 then
		return nil
	end
	return Make.part({
		Name = name or "Slab",
		Size = Vector3.new(sx, thickness, sz),
		Position = Vector3.new((r[1] + r[2]) / 2, topY - thickness / 2, (r[3] + r[4]) / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, parent)
end

-- Axis-aligned wall between two points (thickness 2), rising from y0.
local function wall(parent, x1, z1, x2, z2, y0: number, height: number, color: Color3, name)
	local sx, sz = math.abs(x2 - x1), math.abs(z2 - z1)
	if sx < 0.1 and sz < 0.1 then
		return nil
	end
	return Make.part({
		Name = name or "Wall",
		Size = Vector3.new(math.max(sx, 2), height, math.max(sz, 2)),
		Position = Vector3.new((x1 + x2) / 2, y0 + height / 2, (z1 + z2) / 2),
		Color = color,
		Material = Enum.Material.Slate,
	}, parent)
end

local function sgn(v: number): number
	if v > 0.01 then
		return 1
	elseif v < -0.01 then
		return -1
	end
	return 0
end

-- ------------------------------------------------------------- chambers

-- Rectangle walls with openings (layout.gaps) where tunnels/ramps/doors enter.
local function chamberWalls(parent, rect, gaps, y0: number, height: number, color: Color3, hw: number)
	local edges = {
		north = { rect.left, rect.right, rect.top, true },
		south = { rect.left, rect.right, rect.bottom, true },
		west = { rect.top, rect.bottom, rect.left, false },
		east = { rect.top, rect.bottom, rect.right, false },
	}
	for name, e in edges do
		local from, to, fixed, horizontal = e[1], e[2], e[3], e[4]
		local spans = {}
		for _, g in gaps or {} do
			if g.edge == name then
				table.insert(spans, { g.along - hw, g.along + hw })
			end
		end
		table.sort(spans, function(a, b)
			return a[1] < b[1]
		end)
		local cursor = from - 1
		local function piece(a, b)
			if b - a < 0.1 then
				return
			end
			if horizontal then
				wall(parent, a, fixed, b, fixed, y0, height, color, "ChamberWall")
			else
				wall(parent, fixed, a, fixed, b, y0, height, color, "ChamberWall")
			end
		end
		for _, span in spans do
			piece(cursor, span[1])
			cursor = span[2]
		end
		piece(cursor, to + 1)
	end
end

-- Walled, roofed corridor along an axis-aligned polyline at floor height y.
-- Interior vertices become corner squares whose closed sides are walled.
local function tunnel(parent, points, y: number, hw: number, height: number)
	local n = #points
	local dirs = {}
	for i = 1, n - 1 do
		dirs[i] = { sgn(points[i + 1][1] - points[i][1]), sgn(points[i + 1][2] - points[i][2]) }
	end
	local ext = hw + 1
	for i = 1, n - 1 do
		local a, b = points[i], points[i + 1]
		local r = { math.min(a[1], b[1]) - ext, math.max(a[1], b[1]) + ext, math.min(a[2], b[2]) - ext, math.max(a[2], b[2]) + ext }
		slab(parent, r, y, 2, TUNNEL_COLOR, Enum.Material.Slate, "TunnelFloor")
		slab(parent, r, y + height + 0.3, 0.3, Color3.fromRGB(46, 54, 60), Enum.Material.Slate, "TunnelCeiling").CanCollide = false
		local d = dirs[i]
		local trimStart = i > 1 and ext or 0
		local trimEnd = i < n - 1 and ext or 0
		for _, side in { -1, 1 } do
			local ox, oz = -d[2] * side * ext, d[1] * side * ext
			local sx, sz = a[1] + d[1] * trimStart + ox, a[2] + d[2] * trimStart + oz
			local ex, ez = b[1] - d[1] * trimEnd + ox, b[2] - d[2] * trimEnd + oz
			local along = (ex - sx) * d[1] + (ez - sz) * d[2]
			if along > 0.5 then
				wall(parent, sx, sz, ex, ez, y, height, WALL_COLOR, "TunnelWall")
			end
		end
	end
	for i = 2, n - 1 do
		local p = points[i]
		local din, dout = dirs[i - 1], dirs[i]
		for _, sd in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			local open = (sd[1] == -din[1] and sd[2] == -din[2]) or (sd[1] == dout[1] and sd[2] == dout[2])
			if not open then
				local cx, cz = p[1] + sd[1] * ext, p[2] + sd[2] * ext
				local half = ext + 1
				if sd[1] == 0 then
					wall(parent, cx - half, cz, cx + half, cz, y, height, WALL_COLOR, "TunnelCorner")
				else
					wall(parent, cx, cz - half, cx, cz + half, y, height, WALL_COLOR, "TunnelCorner")
				end
			end
		end
	end
end

local function signpost(parent, x: number, z: number, text: string)
	local model = Instance.new("Model")
	model.Name = "Signpost"
	Make.part({ Size = Vector3.new(0.8, 7, 0.8), Position = Vector3.new(x, 3.5, z), Color = Palette.Wood }, model)
	local board = Make.part({ Size = Vector3.new(5, 1.6, 0.5), Position = Vector3.new(x, 6, z), Color = Palette.hex("#a98c58") }, model)
	Make.label(board, text, Palette.UI.gold, 2.5, 260, 90)
	model.Parent = parent
end

-- A ramp/stair slab from a to b with low rails.
local function ramp(parent, r, color: Color3)
	local a = Vector3.new(r.x1, r.y1, r.z1)
	local b = Vector3.new(r.x2, r.y2, r.z2)
	local len = (b - a).Magnitude
	local base = CFrame.lookAt((a + b) / 2, b)
	Make.part({
		Name = "Ramp_" .. r.name,
		Size = Vector3.new(r.width, 2, len),
		CFrame = base * CFrame.new(0, -1, 0),
		Color = color,
		Material = Enum.Material.Slate,
	}, parent)
	for _, side in { -1, 1 } do
		Make.part({
			Name = "RampRail",
			Size = Vector3.new(1.4, 6, len),
			CFrame = base * CFrame.new(side * (r.width / 2 + 0.7), 2, 0),
			Color = WALL_COLOR,
			Material = Enum.Material.Slate,
		}, parent)
	end
end

-- ------------------------------------------------------------ level gates
-- Port-only grind rule: harder areas need a minimum level (Config.LEVEL_BY_DANGER). Each
-- gated area gets an invisible barrier ring + "Requires level N" labels at its trail
-- entrances. The server never collides with them; each client turns collision/visibility on
-- locally for players below the level (see client LevelGates). WorldService also pushes
-- under-level players back as a backup.
local function gatePart(parent, rect, x1, z1, x2, z2, height, level)
	local sx, sz = math.max(math.abs(x2 - x1), 2), math.max(math.abs(z2 - z1), 2)
	local part = Make.part({
		Name = "LevelGate",
		Size = Vector3.new(sx, height, sz),
		Position = Vector3.new((x1 + x2) / 2, rect.y + height / 2, (z1 + z2) / 2),
		Color = Color3.fromRGB(240, 110, 90),
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, parent)
	part:SetAttribute("ReqLevel", level)
	CollectionService:AddTag(part, "LevelGate")
	return part
end

local function levelGates(parent, layout)
	local gates = Instance.new("Folder")
	gates.Name = "LevelGates"
	gates.Parent = parent
	for _, id in layout.order do
		local rect = layout.areas[id]
		local level = Config.LEVEL_BY_DANGER[Adventure.AREAS[id].danger] or 1
		if level > 1 then
			local height = rect.kind == "surface" and 40 or rect.kind == "cave" and Config.CAVE_DEPTH - 4 or (rect.floor == 3 and 26 or Config.FLOOR_HEIGHT - 4)
			gatePart(gates, rect, rect.left - 1, rect.top - 1, rect.right + 1, rect.top - 1, height, level)
			gatePart(gates, rect, rect.left - 1, rect.bottom + 1, rect.right + 1, rect.bottom + 1, height, level)
			gatePart(gates, rect, rect.left - 1, rect.top, rect.left - 1, rect.bottom, height, level)
			gatePart(gates, rect, rect.right + 1, rect.top, rect.right + 1, rect.bottom, height, level)
			-- Labels where trails/ramps meet the area.
			for _, trail in layout.trails do
				local point
				if trail.a == id and not trail.underground then
					point = trail.points[1]
				elseif trail.b == id then
					point = trail.points[#trail.points]
				end
				if point then
					local label = Make.decor({ Name = "LevelGateLabel", Size = Vector3.one, Position = Vector3.new(point[1], rect.y + 9, point[2]), Transparency = 1 }, gates)
					label:SetAttribute("ReqLevel", level)
					label:SetAttribute("Label", true)
					local gui = Make.label(label, ("%s\nRequires level %d"):format(Adventure.AREAS[id].name, level), Color3.fromRGB(255, 160, 140), 0, 300, 140)
					gui.Size = UDim2.fromOffset(300, 48)
					gui.MaxDistance = 160
					gui.Enabled = false
					local text = gui:FindFirstChild("Text")
					text.Size = UDim2.fromScale(1, 1)
					text.TextWrapped = true
					CollectionService:AddTag(label, "LevelGate")
				end
			end
		end
	end
	-- Tower stairs: a lid across the top of each flight so you cannot climb into a locked floor.
	for _, r in layout.ramps do
		if r.kind == "stairs" then
			local upperId = r.name:match("%->(.+)$")
			local upper = layout.areas[upperId]
			local level = Config.LEVEL_BY_DANGER[Adventure.AREAS[upperId].danger] or 1
			if level > 1 then
				local dir = r.x2 > r.x1 and 1 or -1
				local x = r.x2 - dir * 3
				gatePart(gates, upper, x, r.z1 - r.width / 2 - 1, x, r.z1 + r.width / 2 + 1, 16, level)
			end
		end
	end
end

-- ------------------------------------------------------------------- build

-- handlers.onFeature(player, feature). Returns infos[areaId] = {rect, origin, widthPx, heightPx, folder, region, kind}.
function WorldBuilder.build(layout, handlers)
	local root = Instance.new("Folder")
	root.Name = "World"
	local terrain = Instance.new("Folder")
	terrain.Name = "Terrain"
	terrain.Parent = root
	local areasFolder = Instance.new("Folder")
	areasFolder.Name = "Areas"
	areasFolder.Parent = root

	local hw = Config.TRAIL_WIDTH / 2
	local B = layout.bounds
	local pad = 220
	local wilderness = Palette.Regions.woodland.ground
	local groundColor = Make.shade(wilderness, -0.1)

	-- Surface ground: chunked, with holes where cave ramps descend.
	local chunk = Config.CHUNK_STUDS
	local x0, z0 = math.floor((B.minX - pad) / chunk) * chunk, math.floor((B.minZ - pad) / chunk) * chunk
	for cx = x0, B.maxX + pad, chunk do
		for cz = z0, B.maxZ + pad, chunk do
			for _, piece in WorldLayout.subtractAll({ cx, cx + chunk, cz, cz + chunk }, layout.surfaceHoles) do
				slab(terrain, piece, 0, 4, groundColor, Enum.Material.Grass, "Ground")
			end
		end
	end

	-- Trails and tunnels.
	local trailsFolder = Instance.new("Folder")
	trailsFolder.Name = "Trails"
	trailsFolder.Parent = root
	local avoid = {} -- surface rects (minX, maxX, minZ, maxZ) the wilderness scatter must keep clear
	local function avoidRect(minX, maxX, minZ, maxZ, margin)
		table.insert(avoid, { minX - margin, maxX + margin, minZ - margin, maxZ + margin })
	end
	local surfaceRects = {}
	for _, r in layout.areas do
		if r.kind == "surface" then
			table.insert(surfaceRects, r)
		end
	end
	for _, trail in layout.trails do
		if trail.underground then
			tunnel(terrain, trail.points, trail.y, hw, Config.CAVE_DEPTH - 4)
		else
			local curve = trail.curve or trail.points
			local trailRng = Random.new(#trail.a * 131 + #trail.b * 17 + math.floor(curve[1][1]))
			Scenic.strip(trailsFolder, curve, hw, trailRng)
			Scenic.roadside(trailsFolder, curve, hw, trailRng, AreaBuilder.props, function(x, z)
				for _, r in surfaceRects do
					if x > r.left - 6 and x < r.right + 6 and z > r.top - 6 and z < r.bottom + 6 then
						return true
					end
				end
				return false
			end)
			for i = 1, #curve - 1, 4 do
				local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
				for j = i, math.min(i + 4, #curve) do
					minX, maxX = math.min(minX, curve[j][1]), math.max(maxX, curve[j][1])
					minZ, maxZ = math.min(minZ, curve[j][2]), math.max(maxZ, curve[j][2])
				end
				avoidRect(minX, maxX, minZ, maxZ, hw + 22)
			end
			-- Signposts just outside each end, naming where the trail leads.
			local pts = trail.points
			local function post(from, nextPoint, destination)
				local spec = Adventure.AREAS[destination]
				if not spec then
					return
				end
				local dx, dz = sgn(nextPoint[1] - from[1]), sgn(nextPoint[2] - from[2])
				signpost(trailsFolder, from[1] + dx * 14 - dz * (hw + 4), from[2] + dz * 14 + dx * (hw + 4), spec.name)
			end
			if layout.areas[trail.a] and layout.areas[trail.a].kind == "surface" then
				post(pts[1], pts[2], trail.b)
			end
			if layout.areas[trail.b] and layout.areas[trail.b].kind == "surface" then
				post(pts[#pts], pts[#pts - 1], trail.a)
			end
		end
	end

	-- Ramps and stairs.
	local structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = root
	for _, r in layout.ramps do
		ramp(structures, r, r.kind == "stairs" and Palette.hex("#8c8374") or TUNNEL_COLOR)
		avoidRect(math.min(r.x1, r.x2), math.max(r.x1, r.x2), math.min(r.z1, r.z2), math.max(r.z1, r.z2), r.width + 10)
	end
	for _, hole in layout.surfaceHoles do
		avoidRect(hole[1], hole[2], hole[3], hole[4], 14)
	end

	-- Areas.
	local infos = {}
	local floorHeight = Config.FLOOR_HEIGHT
	for _, id in layout.order do
		local rect = layout.areas[id]
		local spec = Adventure.AREAS[id]
		local region = Palette.Regions[spec.region] or Palette.Regions.woodland
		local folder = Instance.new("Folder")
		folder.Name = id
		folder.Parent = areasFolder
		local bounds = { rect.left, rect.right, rect.top, rect.bottom }

		if rect.kind == "surface" then
			avoidRect(rect.left, rect.right, rect.top, rect.bottom, 14)
		elseif rect.kind == "cave" then
			slab(folder, bounds, rect.y, 2, region.ground, Enum.Material.Slate, "CaveFloor")
			local ceiling = slab(folder, bounds, rect.y + Config.CAVE_DEPTH - 4 + 0.3, 0.3, Color3.fromRGB(46, 54, 60), Enum.Material.Slate, "CaveCeiling")
			ceiling.CanCollide = false
			chamberWalls(folder, rect, layout.gaps[id], rect.y, Config.CAVE_DEPTH - 4, WALL_COLOR, hw)
		else -- tower
			local top = rect.floor == 3
			local height = top and 26 or floorHeight - 4
			if rect.floor ~= 1 then
				for _, piece in WorldLayout.subtractAll(bounds, layout.floorHoles[id] or {}) do
					slab(folder, piece, rect.y, 2, region.stone, Enum.Material.Slate, "TowerFloor")
				end
			end
			chamberWalls(folder, rect, layout.gaps[id], rect.y, height, Make.shade(region.stone, -0.05), hw)
			avoidRect(rect.left, rect.right, rect.top, rect.bottom, 14)
		end

		AreaBuilder.populate(id, rect, folder, handlers, layout.floorHoles[id])
		local widthPx, heightPx = AreaBuilder.sizePx(id)
		infos[id] = {
			id = id,
			rect = rect,
			origin = Vector3.new(rect.left, rect.y, rect.top),
			widthPx = widthPx,
			heightPx = heightPx,
			folder = folder,
			region = spec.region,
			kind = rect.kind,
		}
	end

	levelGates(root, layout)

	-- Wilderness scatter on the open ground between areas.
	local scatter = Instance.new("Folder")
	scatter.Name = "Wilderness"
	scatter.Parent = root
	local rng = Random.new(20261016)
	local cell = math.sqrt(Config.WILDERNESS_PROP_STUDS2)
	local rockColor = Palette.Regions.woodland.stone
	for gx = B.minX - pad, B.maxX + pad, cell do
		for gz = B.minZ - pad, B.maxZ + pad, cell do
			if rng:NextNumber() < 0.75 then
				local x, z = gx + rng:NextNumber() * cell, gz + rng:NextNumber() * cell
				local ok = true
				for _, r in avoid do
					if x > r[1] and x < r[2] and z > r[3] and z < r[4] then
						ok = false
						break
					end
				end
				if ok then
					local pos = Vector3.new(x, 0, z)
					if rng:NextNumber() < 0.8 then
						AreaBuilder.props.tree(scatter, pos, rng)
					else
						AreaBuilder.props.rock(scatter, pos, rng, rockColor)
					end
				end
			end
		end
	end

	root.Parent = Workspace
	return infos
end

return WorldBuilder
