--!nonstrict
-- Scenery that makes the open world worth walking: winding dirt trails with roadside
-- trees/flowers/benches/lanterns/wayside shrines, and ponds, meadows, groves and standing
-- stones inside the large open areas. Same blocky flat-shaded look as the rest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)

local Scenic = {}

local TRAIL_COLOR = Color3.fromRGB(196, 168, 118)
local VERGE_COLOR = Color3.fromRGB(70, 84, 38)
local BLOOM = { "#f0ead7", "#f5a08b", "#d2b36f", "#b59bcd", "#ee847d", "#9fd3e6" }

local function hex(c)
	return Palette.hex(c)
end

-- ---------------------------------------------------------------- pieces

local function flowers(parent, pos: Vector3, rng: Random, radius: number?, count: number?)
	-- One part per blossom (no stem) to keep part counts down.
	radius = radius or 3
	for _ = 1, math.max(3, math.ceil((count or 7) * 0.6)) do
		local a, r = rng:NextNumber() * math.pi * 2, rng:NextNumber() * radius
		local p = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		Make.decor({ Size = Vector3.new(0.8, 0.9, 0.8), Position = p + Vector3.new(0, 0.5, 0), Color = hex(BLOOM[rng:NextInteger(1, #BLOOM)]) }, parent)
	end
end

local function bench(parent, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Bench"
	m.Parent = parent
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	Make.part({ Size = Vector3.new(4.4, 0.5, 1.6), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Palette.Wood }, m)
	Make.part({ Size = Vector3.new(4.4, 1.4, 0.4), CFrame = cf * CFrame.new(0, 2.6, -0.7), Color = Palette.Wood }, m)
	for _, x in { -1.8, 1.8 } do
		Make.part({ Size = Vector3.new(0.4, 1.6, 1.2), CFrame = cf * CFrame.new(x, 0.8, 0), Color = hex("#5e4d30") }, m)
	end
end

local function lantern(parent, pos: Vector3)
	Make.part({ Size = Vector3.new(0.5, 7, 0.5), Position = pos + Vector3.new(0, 3.5, 0), Color = hex("#4a4033") }, parent)
	local head = Make.part({ Size = Vector3.new(1.4, 1.4, 1.4), Position = pos + Vector3.new(0, 7.4, 0), Color = hex("#ffd9a0"), Material = Enum.Material.Neon }, parent)
	local light = Instance.new("PointLight")
	light.Color = hex("#ffd9a0")
	light.Range = 26
	light.Brightness = 1.1
	light.Parent = head
end

local function waysideShrine(parent, pos: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "WaysideShrine"
	m.Parent = parent
	local stone = Palette.Regions.woodland.stone
	Make.part({ Size = Vector3.new(4, 0.8, 4), Position = pos + Vector3.new(0, 0.4, 0), Color = Make.shade(stone, -0.06), Material = Enum.Material.Slate }, m)
	Make.part({ Size = Vector3.new(2.2, 4.2, 1.6), Position = pos + Vector3.new(0, 2.9, 0), Color = stone, Material = Enum.Material.Slate }, m)
	Make.part({ Size = Vector3.new(3, 0.6, 2.4), Position = pos + Vector3.new(0, 5.3, 0), Color = Make.shade(stone, 0.05), Material = Enum.Material.Slate }, m)
	local orb = Make.decor({ Size = Vector3.new(1, 1, 1), Position = pos + Vector3.new(0, 3.6, -1), Color = Palette.Mint, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball }, m)
	local light = Instance.new("PointLight")
	light.Color = Palette.Mint
	light.Range = 16
	light.Parent = orb
	flowers(m, pos + Vector3.new(0, 0, -3), rng, 2, 5)
end

local function cairn(parent, pos: Vector3, rng: Random)
	local stone = Palette.Regions.woodland.stone
	for i, size in { 3.2, 2.4, 1.6 } do
		Make.part({
			Size = Vector3.new(size * 1.2, size * 0.7, size),
			CFrame = CFrame.new(pos + Vector3.new((rng:NextNumber() - 0.5) * 0.4, (i - 1) * 1.5 + 0.7, 0)) * CFrame.Angles(0, rng:NextNumber() * 3, 0),
			Color = Make.shade(stone, (i - 2) * 0.04),
			Material = Enum.Material.Slate,
		}, parent)
	end
end

local function log(parent, pos: Vector3, rng: Random)
	local part = Make.part({ Size = Vector3.new(7, 1.6, 1.6), Color = hex("#6a4f2e"), Material = Enum.Material.Wood }, parent)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = CFrame.new(pos + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
end

local function pond(parent, pos: Vector3, rng: Random, diameter: number)
	local squash = 0.7 + rng:NextNumber() * 0.3
	local yaw = rng:NextNumber() * math.pi
	local function disc(d: number, y: number, color: Color3, material: Enum.Material, transparency: number?)
		local p = Make.decor({ Size = Vector3.new(0.2, d, d * squash), Color = color, Material = material, Transparency = transparency or 0 }, parent)
		p.Shape = Enum.PartType.Cylinder
		p.CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw, math.pi / 2)
		return p
	end
	disc(diameter * 1.45, 0.27, hex("#8a7752"), Enum.Material.Mud) -- muddy bank
	disc(diameter * 1.2, 0.29, hex("#a89870"), Enum.Material.Sand) -- sandy rim
	disc(diameter * 1.02, 0.31, hex("#2f5568"), Enum.Material.Slate) -- deep bed
	local water = disc(diameter, 0.36, hex("#5c93a8"), Enum.Material.Glass, 0.28)
	water.Reflectance = 0.12
	disc(diameter * 0.55, 0.38, hex("#74abc0"), Enum.Material.Glass, 0.5) -- lighter centre
	local stone = Palette.Regions.woodland.stone
	for i = 1, 11 do
		local a = i / 11 * math.pi * 2 + rng:NextNumber() * 0.3
		local r = diameter * (0.58 + rng:NextNumber() * 0.08)
		local s = 0.8 + rng:NextNumber() * 1.4
		Make.part({
			Size = Vector3.new(s * 1.3, s * 0.7, s),
			Position = pos + Vector3.new(math.cos(a) * r, s * 0.3, math.sin(a) * r * squash),
			Color = Make.shade(stone, (rng:NextNumber() - 0.5) * 0.1),
			Material = Enum.Material.Slate,
		}, parent)
	end
	-- lily pads with the odd flower
	for _ = 1, 5 do
		local a = rng:NextNumber() * math.pi * 2
		local r = diameter * rng:NextNumber() * 0.38
		local at = pos + Vector3.new(math.cos(a) * r, 0.42, math.sin(a) * r * squash)
		local pad = Make.decor({ Size = Vector3.new(0.1, 1.6, 1.6), Color = hex("#4f8a3a"), Material = Enum.Material.Grass }, parent)
		pad.Shape = Enum.PartType.Cylinder
		pad.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
		if rng:NextNumber() < 0.4 then
			local bloom = Make.decor({ Size = Vector3.new(0.6, 0.6, 0.6), Position = at + Vector3.new(0, 0.3, 0), Color = hex("#f5a8c0"), Shape = Enum.PartType.Ball }, parent)
			bloom.CastShadow = false
		end
	end
	-- cattails
	for _ = 1, 9 do
		local a = rng:NextNumber() * math.pi * 2
		local r = diameter * (0.5 + rng:NextNumber() * 0.12)
		local at = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r * squash)
		local h = 3 + rng:NextNumber() * 1.5
		Make.decor({ Size = Vector3.new(0.2, h, 0.2), Position = at + Vector3.new(0, h / 2, 0), Color = hex("#7a9a45") }, parent)
		Make.decor({ Size = Vector3.new(0.4, 0.9, 0.4), Position = at + Vector3.new(0, h, 0), Color = hex("#6a4a2a") }, parent)
	end
end

local function standingStones(parent, pos: Vector3, rng: Random)
	local stone = Palette.Regions.woodland.stone
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local h = 5 + rng:NextNumber() * 3
		Make.part({
			Size = Vector3.new(2, h, 1.4),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 11, h / 2, math.sin(a) * 11)) * CFrame.Angles(0, -a, math.rad(rng:NextInteger(-5, 5))),
			Color = Make.shade(stone, (rng:NextNumber() - 0.5) * 0.08),
			Material = Enum.Material.Slate,
		}, parent)
	end
	Make.part({ Size = Vector3.new(4, 1, 4), Position = pos + Vector3.new(0, 0.5, 0), Color = Make.shade(stone, -0.05), Material = Enum.Material.Slate }, parent)
	local orb = Make.decor({ Size = Vector3.new(1.2, 1.2, 1.2), Position = pos + Vector3.new(0, 2, 0), Color = Palette.Mint, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball }, parent)
	local light = Instance.new("PointLight")
	light.Color = Palette.Mint
	light.Range = 20
	light.Parent = orb
end

-- ----------------------------------------------------------------- trails

-- Dirt strip following a dense curve, with a darker verge underneath.
function Scenic.strip(parent, curve, hw: number, rng: Random)
	for i = 1, #curve - 1 do
		local a, b = curve[i], curve[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0.05 then
			local mid = Vector3.new((a[1] + b[1]) / 2, 0, (a[2] + b[2]) / 2)
			local look = Vector3.new(b[1], 0, b[2])
			local width = hw * 2 * (0.88 + 0.24 * rng:NextNumber())
			local lift = (i % 3) * 0.06 -- neighbouring segments overlap: stagger heights so they never share a plane
			Make.decor({
				Name = "Verge",
				Size = Vector3.new(width + 8, 0.2, len + 1.2),
				CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.3 + lift, 0), look + Vector3.new(0, 0.3 + lift, 0)),
				Color = Make.shade(VERGE_COLOR, (rng:NextNumber() - 0.5) * 0.05),
				Material = Enum.Material.Grass,
			}, parent)
			Make.decor({
				Name = "Trail",
				Size = Vector3.new(width, 0.3, len + 1.6),
				CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.5 + lift, 0), look + Vector3.new(0, 0.5 + lift, 0)),
				Color = Make.shade(TRAIL_COLOR, (rng:NextNumber() - 0.5) * 0.05),
				Material = Enum.Material.Ground,
			}, parent)
			if i % 2 == 0 then
				for _, side in { -1, 1 } do
					local off = (width / 2 + 0.6) * side
					local sz = 0.6 + rng:NextNumber() * 0.7
					Make.decor({
						Size = Vector3.new(sz * 1.3, sz * 0.7, sz),
						CFrame = CFrame.lookAt(mid, look) * CFrame.new(off, 0.7, 0) * CFrame.Angles(0, rng:NextNumber() * 3, 0),
						Color = Make.shade(Color3.fromRGB(150, 146, 136), (rng:NextNumber() - 0.5) * 0.12),
						Material = Enum.Material.Slate,
					}, parent)
				end
			end
		end
	end
end

-- Roadside life. props = { tree, rock }; inside(x, z) -> true when the spot is in an area.
function Scenic.roadside(parent, curve, hw: number, rng: Random, props, inside)
	local rockColor = Palette.Regions.woodland.stone
	local nextLandmark = rng:NextInteger(5, 9)
	local DENSITY = 0.7 -- roadside prop density multiplier (perf)
	local landmarkCount = rng:NextInteger(1, 5)
	for i = 2, #curve - 1, 2 do
		local a, b = curve[i - 1], curve[i + 1]
		local tx, tz = b[1] - a[1], b[2] - a[2]
		local tl = math.max(math.sqrt(tx * tx + tz * tz), 0.01)
		tx, tz = tx / tl, tz / tl
		local function at(side: number, dist: number)
			return Vector3.new(curve[i][1] - tz * side * dist, 0, curve[i][2] + tx * side * dist)
		end
		for _, side in { -1, 1 } do
			local roll = rng:NextNumber() / DENSITY
			local pos = at(side, hw + 4 + rng:NextNumber() * 16)
			if not inside(pos.X, pos.Z) then
				if roll < 0.5 then
					props.tree(parent, pos, rng)
				elseif roll < 0.62 then
					props.rock(parent, pos, rng, rockColor)
				elseif roll < 0.9 then
					flowers(parent, pos, rng, 3.5, 8)
				end
			end
		end
		nextLandmark -= 1
		if nextLandmark <= 0 then
			nextLandmark = rng:NextInteger(9, 16)
			landmarkCount += 1
			local side = rng:NextInteger(0, 1) * 2 - 1
			local pos = at(side, hw + 5)
			if not inside(pos.X, pos.Z) then
				local kind = landmarkCount % 6
				local yaw = math.atan2(-tx, -tz) + (side > 0 and math.pi or 0)
				if kind == 0 then
					bench(parent, pos, yaw)
					lantern(parent, at(side, hw + 8))
				elseif kind == 1 then
					waysideShrine(parent, pos, rng)
				elseif kind == 2 then
					cairn(parent, pos, rng)
				elseif kind == 3 then
					log(parent, pos, rng)
					flowers(parent, at(side, hw + 11), rng, 4, 10)
				elseif kind == 4 then
					pond(parent, at(side, hw + 18), rng, 14 + rng:NextNumber() * 8)
				else
					lantern(parent, pos)
					flowers(parent, at(side, hw + 7), rng, 3, 8)
				end
			end
		end
	end
end

-- ------------------------------------------------------------- open spaces

-- Big open areas get ponds, flower meadows, groves, boulder fields and a standing-stone ring.
-- `clear` = px circles to avoid; new landmarks are appended to it. w(x, y, h) -> world position.
function Scenic.openSpace(parent, widthPx: number, heightPx: number, w, clear, rng: Random, props, holes, rect)
	local S = 0.3
	local studsArea = widthPx * heightPx * S * S
	local rockColor = Palette.Regions.woodland.stone
	local function free(x, y, r)
		for _, c in clear do
			if (c[1] - x) ^ 2 + (c[2] - y) ^ 2 < (c[3] + r) ^ 2 then
				return false
			end
		end
		for _, hole in holes or {} do
			local wx, wz = rect.left + x * S, rect.top + y * S
			if wx > hole[1] - 12 and wx < hole[2] + 12 and wz > hole[3] - 12 and wz < hole[4] + 12 then
				return false
			end
		end
		return true
	end
	local function pick(radiusPx)
		for _ = 1, 30 do
			local x = 90 + rng:NextNumber() * (widthPx - 180)
			local y = 90 + rng:NextNumber() * (heightPx - 180)
			if free(x, y, radiusPx) then
				return x, y
			end
		end
		return nil, nil
	end
	local folder = Instance.new("Model")
	folder.Name = "OpenSpace"
	folder.Parent = parent
	for _ = 1, math.max(1, math.floor(studsArea / 170000)) do
		local x, y = pick(110)
		if x then
			pond(folder, w(x, y, 0), rng, 22 + rng:NextNumber() * 14)
			table.insert(clear, { x, y, 100 })
		end
	end
	for _ = 1, math.floor(studsArea / 38000) do
		local x, y = pick(60)
		if x then
			for _ = 1, 3 do
				flowers(folder, w(x + (rng:NextNumber() - 0.5) * 80, y + (rng:NextNumber() - 0.5) * 80, 0), rng, 6, 9)
			end
			table.insert(clear, { x, y, 40 })
		end
	end
	for _ = 1, math.floor(studsArea / 110000) do
		local x, y = pick(120)
		if x then
			for _ = 1, 9 do
				local a, r = rng:NextNumber() * math.pi * 2, rng:NextNumber() * 24
				props.tree(folder, w(x, y, 0) + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng)
			end
			table.insert(clear, { x, y, 90 })
		end
	end
	for _ = 1, math.floor(studsArea / 140000) do
		local x, y = pick(90)
		if x then
			for _ = 1, 7 do
				local a, r = rng:NextNumber() * math.pi * 2, rng:NextNumber() * 14
				props.rock(folder, w(x, y, 0) + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng, rockColor)
			end
			table.insert(clear, { x, y, 60 })
		end
	end
	if studsArea > 250000 then
		local x, y = pick(110)
		if x then
			standingStones(folder, w(x, y, 0), rng)
			table.insert(clear, { x, y, 80 })
		end
	end
end

return Scenic
