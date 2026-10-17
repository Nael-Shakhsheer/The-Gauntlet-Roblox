--!nonstrict
-- Fills one Adventure area (a rectangle of the continuous world) with blocky 3D
-- scenery, features and landmarks from the exported 2D data.
-- Visual direction: the 2D game's palette, flat-shaded voxel props, tile-based
-- ground that echoes the pixel-art atlases.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Coord = require(Shared.Coord)
local Data = require(Shared.Data)
local Make = require(Shared.Make)
local Rig = require(Shared.Rig)
local Palette = require(Shared.Palette)
local Villages = require(Shared.Villages)
local Sizes = require(Shared.Sizes)
local VillageBuilder = require(script.Parent.VillageBuilder)
local Scenic = require(script.Parent.Scenic)

local Adventure = Data.Adventure
local Dungeons = Data.Dungeons
local RegionContent = Data.RegionContent

local AreaBuilder = {}

function AreaBuilder.sizePx(areaId: string): (number, number)
	local size = Sizes.get(areaId, Adventure.LARGE_AREAS, Config.DEFAULT_AREA_PX)
	return size[1], size[2]
end

-- Every feature (NPC, clue, chest...) for an area, in area px.
function AreaBuilder.features(areaId: string, widthPx: number, heightPx: number)
	local list = {}
	local function add(source)
		for _, f in source[areaId] or {} do
			local x, y = Coord.scaleToArea(f[3], f[4], widthPx, heightPx)
			table.insert(list, { key = f[1], name = f[2], x = x, y = y, kind = f[5], area = areaId })
		end
	end
	add(Adventure.FEATURES)
	add(RegionContent.FEATURES)
	add(Dungeons.FEATURES)
	add(Villages.FEATURES)
	for _, f in VillageBuilder.features(areaId) do
		table.insert(list, f)
	end
	-- Hub services live inside their buildings (Store stall, Inn bed).
	for _, f in list do
		if f.key == "shop" or f.key == "inn" then
			local x, y = VillageBuilder.serviceSpot(areaId, f.key)
			if x then
				f.x, f.y = x, y
			end
		end
	end
	-- Travel shrines (region_content.SHRINES) become attunable waystones.
	for key, spec in RegionContent.SHRINES do
		if spec.area == areaId then
			local x, y = Coord.scaleToArea(spec.x, spec.y, widthPx, heightPx)
			table.insert(list, { key = "attune_" .. key, name = spec.name, x = x, y = y, kind = "travel_shrine", shrine = key, area = areaId })
		end
	end
	return list
end

-- ---------------------------------------------------------------- props

-- Trees are grown to a random scale so forests have giants and saplings; props are decor where
-- possible (canopies never need collision), only trunks collide.
local function treeScale(rng: Random): number
	local k = 1.9 + rng:NextNumber() * 0.9
	if rng:NextNumber() < 0.08 then
		k *= 1.35 -- the occasional ancient giant
	end
	return k
end

local function canopy(parent, pos: Vector3, size: number, color: Color3, shadow: boolean?)
	local ball = Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 0.82, size), Position = pos, Color = color, Material = Enum.Material.Grass }, parent)
	ball.CastShadow = shadow == true
	return ball
end

local function trunkOf(parent, pos: Vector3, width: number, h: number, color: Color3, material: Enum.Material?)
	local trunk = Make.part({ Size = Vector3.new(width, h, width), Position = pos + Vector3.new(0, h / 2, 0), Color = color, Material = material or Enum.Material.Wood }, parent)
	trunk.CastShadow = true
	return trunk
end

-- Flared roots: short angled stubs around the base.
local function roots(parent, pos: Vector3, width: number, rng: Random, color: Color3)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber()
		local len = width * (0.9 + rng:NextNumber() * 0.5)
		Make.decor({
			Size = Vector3.new(width * 0.38, width * 0.38, len),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * width * 0.55, width * 0.18, math.sin(a) * width * 0.55)) * CFrame.Angles(0, -a + math.pi / 2, math.rad(-18)),
			Color = Make.shade(color, -0.04),
			Material = Enum.Material.Wood,
		}, parent)
	end
end

local function oak(parent, pos: Vector3, rng: Random)
	local k = treeScale(rng)
	local h = (5 + rng:NextInteger(0, 3)) * k * 0.95
	local width = 1.8 * k * 0.8
	trunkOf(parent, pos, width, h, Palette.Wood)
	roots(parent, pos, width, rng, Palette.Wood)
	local leaf = Palette.Leaf[rng:NextInteger(1, #Palette.Leaf)]
	local crown = 8.5 * k * 0.9
	canopy(parent, pos + Vector3.new(0, h + crown * 0.22, 0), crown, leaf, true)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + rng:NextNumber() * 0.8
		local r = crown * (0.28 + rng:NextNumber() * 0.12)
		canopy(parent, pos + Vector3.new(math.cos(a) * r, h + crown * (0.02 + rng:NextNumber() * 0.2), math.sin(a) * r), crown * (0.5 + rng:NextNumber() * 0.15), Make.shade(leaf, (rng:NextNumber() - 0.5) * 0.12))
	end
	-- a limb under the crown
	local a = rng:NextNumber() * math.pi * 2
	Make.decor({
		Size = Vector3.new(width * 0.35, width * 0.35, crown * 0.5),
		CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * crown * 0.22, h * 0.82, math.sin(a) * crown * 0.22)) * CFrame.Angles(0, -a + math.pi / 2, math.rad(-32)),
		Color = Palette.Wood,
		Material = Enum.Material.Wood,
	}, parent)
end

local function pine(parent, pos: Vector3, rng: Random, snow: boolean?)
	local k = treeScale(rng) * 0.95
	local h = (7 + rng:NextInteger(0, 4)) * k * 0.8
	local width = 1.4 * k * 0.8
	trunkOf(parent, pos, width, h, Make.shade(Palette.Wood, -0.1))
	local leaf = Make.shade(Palette.Leaf[3], -0.08)
	local tiers = 5
	for i = 1, tiers do
		local s = (11 - (i - 1) * 2.0) * k * 0.62
		local tier = Make.decor({
			Size = Vector3.new(s, 2.6 * k * 0.55, s),
			CFrame = CFrame.new(pos + Vector3.new(0, h * 0.34 + (i - 1) * 2.4 * k * 0.55, 0)) * CFrame.Angles(0, math.rad(45 * (i % 2)) + rng:NextNumber() * 0.2, 0),
			Color = snow and Color3.fromRGB(226, 238, 250) or Make.shade(leaf, (i - 1) * 0.03),
			Material = snow and Enum.Material.Snow or Enum.Material.Grass,
		}, parent)
		tier.CastShadow = i <= 2
	end
	Make.decor({ Size = Vector3.new(1.2 * k * 0.5, 2.2 * k * 0.5, 1.2 * k * 0.5), Position = pos + Vector3.new(0, h * 0.34 + tiers * 2.4 * k * 0.55 + 0.6, 0), Color = snow and Color3.fromRGB(240, 246, 252) or Make.shade(leaf, 0.14), Material = snow and Enum.Material.Snow or Enum.Material.Grass }, parent)
end

local function birch(parent, pos: Vector3, rng: Random)
	local k = treeScale(rng) * 0.9
	local h = (6 + rng:NextInteger(0, 3)) * k * 0.95
	local width = 1.1 * k * 0.8
	trunkOf(parent, pos, width, h, Color3.fromRGB(226, 222, 206), Enum.Material.SmoothPlastic)
	-- dark bark bands
	for i = 1, 4 do
		Make.decor({ Size = Vector3.new(width * 1.04, 0.35, width * 1.04), Position = pos + Vector3.new(0, h * (0.15 + i * 0.19) + rng:NextNumber() * 0.4, 0), Color = Color3.fromRGB(60, 56, 50) }, parent)
	end
	local leaf = Color3.fromRGB(150, 188, 80)
	local crown = 6.4 * k * 0.85
	canopy(parent, pos + Vector3.new(0, h + crown * 0.25, 0), crown, Make.shade(leaf, rng:NextNumber() * 0.08), true)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber()
		canopy(parent, pos + Vector3.new(math.cos(a) * crown * 0.3, h + crown * 0.05, math.sin(a) * crown * 0.3), crown * 0.55, Make.shade(leaf, -0.06 + rng:NextNumber() * 0.1))
	end
end

local function deadTree(parent, pos: Vector3, rng: Random)
	local k = treeScale(rng) * 0.8
	local h = (5 + rng:NextInteger(0, 2)) * k
	local c = Color3.fromRGB(88, 74, 58)
	trunkOf(parent, pos, 1.4 * k * 0.8, h, c)
	for i = 1, 4 do
		local side = i % 2 == 0 and 1 or -1
		local depth = i <= 2 and 0 or 1
		Make.decor({
			Size = Vector3.new(0.6 * k * 0.6, 3.4 * k * 0.8, 0.6 * k * 0.6),
			CFrame = CFrame.new(pos + Vector3.new(side * 1.2 * k * 0.7, h * (0.7 + 0.12 * i), depth * 0.9)) * CFrame.Angles(math.rad(depth * 24), 0, math.rad(-side * (34 + i * 4))),
			Color = c, Material = Enum.Material.Wood,
		}, parent)
	end
end

local function tree(parent, pos: Vector3, rng: Random)
	local roll = rng:NextNumber()
	if roll < 0.45 then
		oak(parent, pos, rng)
	elseif roll < 0.8 then
		pine(parent, pos, rng)
	else
		birch(parent, pos, rng)
	end
end

local function snowPine(parent, pos: Vector3, rng: Random)
	pine(parent, pos, rng, true)
end

-- ---- small ground detail (decor only: no collision, no shadows)
local function bush(parent, pos: Vector3, rng: Random)
	local c = Make.shade(Palette.Leaf[rng:NextInteger(1, #Palette.Leaf)], -0.05)
	local s = 2.2 + rng:NextNumber() * 1.4
	Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.3, s, s * 1.2), Position = pos + Vector3.new(0, s * 0.4, 0), Color = c, Material = Enum.Material.Grass }, parent)
	Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 0.8, s * 0.7, s * 0.8), Position = pos + Vector3.new(s * 0.6, s * 0.3, s * 0.2), Color = Make.shade(c, 0.06), Material = Enum.Material.Grass }, parent)
end

local function tuft(parent, pos: Vector3, rng: Random, color: Color3?)
	local base = color or Palette.Leaf[2]
	for i = 1, 3 do
		local h = 1.1 + rng:NextNumber() * 1.1
		Make.decor({
			Size = Vector3.new(0.18, h, 0.5),
			CFrame = CFrame.new(pos + Vector3.new((i - 2) * 0.35, h / 2, rng:NextNumber() * 0.4)) * CFrame.Angles(math.rad(rng:NextInteger(-12, 12)), rng:NextNumber() * math.pi, math.rad(rng:NextInteger(-14, 14))),
			Color = Make.shade(base, (rng:NextNumber() - 0.4) * 0.14),
			Material = Enum.Material.SmoothPlastic,
		}, parent)
	end
end

local FLOWERS = { Color3.fromRGB(240, 220, 120), Color3.fromRGB(230, 130, 150), Color3.fromRGB(170, 150, 235), Color3.fromRGB(250, 250, 240) }
local function flowers(parent, pos: Vector3, rng: Random)
	for i = 1, 3 do
		local o = Vector3.new(rng:NextNumber() * 2 - 1, 0, rng:NextNumber() * 2 - 1)
		Make.decor({ Size = Vector3.new(0.14, 1.1, 0.14), Position = pos + o + Vector3.new(0, 0.55, 0), Color = Palette.Leaf[3] }, parent)
		Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Position = pos + o + Vector3.new(0, 1.15, 0), Color = FLOWERS[rng:NextInteger(1, #FLOWERS)] }, parent)
	end
end

local function mushroom(parent, pos: Vector3, rng: Random, glow: boolean?)
	local h = 0.8 + rng:NextNumber() * 0.8
	Make.decor({ Size = Vector3.new(0.35, h, 0.35), Position = pos + Vector3.new(0, h / 2, 0), Color = Color3.fromRGB(230, 224, 200) }, parent)
	local cap = Make.decor({
		Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 0.9, 1.5), Position = pos + Vector3.new(0, h + 0.1, 0),
		Color = glow and Color3.fromRGB(110, 220, 220) or Color3.fromRGB(190, 70, 60),
		Material = glow and Enum.Material.Neon or Enum.Material.SmoothPlastic,
	}, parent)
	if glow then
		local light = Instance.new("PointLight")
		light.Color = cap.Color
		light.Range = 9
		light.Brightness = 0.9
		light.Parent = cap
	end
end

local function glowMushroom(parent, pos: Vector3, rng: Random)
	mushroom(parent, pos, rng, true)
	mushroom(parent, pos + Vector3.new(1.4, 0, 0.6), rng, true)
end

local function fern(parent, pos: Vector3, rng: Random)
	for i = 1, 4 do
		Make.decor({
			Size = Vector3.new(0.3, 0.12, 2.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(math.rad(-28), math.rad(i * 90 + rng:NextInteger(-15, 15)), 0) * CFrame.new(0, 0, -0.9),
			Color = Make.shade(Palette.Leaf[1], rng:NextNumber() * 0.08),
		}, parent)
	end
end

local function log(parent, pos: Vector3, rng: Random)
	local len = 3 + rng:NextNumber() * 2.5
	Make.decor({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 1.2, 1.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
		Color = Make.shade(Palette.Wood, -0.08), Material = Enum.Material.Wood,
	}, parent)
end

local function stump(parent, pos: Vector3, rng: Random)
	local w = 1.6 + rng:NextNumber() * 1.2
	local h = 1 + rng:NextNumber() * 1.2
	Make.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, w, w), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Palette.Wood, Material = Enum.Material.Wood }, parent).CastShadow = false
	Make.decor({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, w * 0.8, w * 0.8), CFrame = CFrame.new(pos + Vector3.new(0, h + 0.02, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Make.shade(Palette.Wood, 0.16), Material = Enum.Material.Wood }, parent)
	if rng:NextNumber() < 0.5 then
		mushroom(parent, pos + Vector3.new(w * 0.55, 0, 0.2), rng)
	end
end

local function berryBush(parent, pos: Vector3, rng: Random)
	bush(parent, pos, rng)
	for _ = 1, 5 do
		local a, r = rng:NextNumber() * math.pi * 2, 1 + rng:NextNumber() * 1.2
		Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Position = pos + Vector3.new(math.cos(a) * r, 1 + rng:NextNumber(), math.sin(a) * r), Color = Color3.fromRGB(200, 40, 70), Material = Enum.Material.Neon }, parent)
	end
end

-- A big mossy boulder with a smaller one beside it (collides: a landmark you walk around).
local function boulder(parent, pos: Vector3, rng: Random, color: Color3?)
	local c = color or Palette.Regions.woodland.stone
	local s = 3.5 + rng:NextNumber() * 3.5
	local main = Make.part({
		Size = Vector3.new(s * 1.4, s, s * 1.15),
		CFrame = CFrame.new(pos + Vector3.new(0, s * 0.42, 0)) * CFrame.Angles(math.rad(rng:NextInteger(-6, 6)), rng:NextNumber() * math.pi, math.rad(rng:NextInteger(-6, 6))),
		Color = Make.shade(c, (rng:NextNumber() - 0.5) * 0.1),
		Material = Enum.Material.Slate,
	}, parent)
	main.CastShadow = true
	Make.decor({ Size = Vector3.new(s * 1.2, s * 0.25, s * 0.9), CFrame = main.CFrame * CFrame.new(0, s * 0.5, 0), Color = Color3.fromRGB(86, 120, 56), Material = Enum.Material.Grass }, parent)
	local a = rng:NextNumber() * math.pi * 2
	local s2 = s * 0.5
	Make.part({ Size = Vector3.new(s2 * 1.3, s2, s2), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * s * 0.95, s2 * 0.4, math.sin(a) * s * 0.95)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Color = Make.shade(c, -0.05), Material = Enum.Material.Slate }, parent)
end

local function tallGrass(parent, pos: Vector3, rng: Random)
	for _ = 1, 7 do
		local o = Vector3.new((rng:NextNumber() - 0.5) * 3.2, 0, (rng:NextNumber() - 0.5) * 3.2)
		local h = 1.8 + rng:NextNumber() * 1.6
		Make.decor({
			Size = Vector3.new(0.16, h, 0.55),
			CFrame = CFrame.new(pos + o + Vector3.new(0, h / 2, 0)) * CFrame.Angles(math.rad(rng:NextInteger(-14, 14)), rng:NextNumber() * math.pi, math.rad(rng:NextInteger(-16, 16))),
			Color = Make.shade(Palette.Leaf[2], (rng:NextNumber() - 0.4) * 0.16),
		}, parent)
	end
end

local function fallenBranch(parent, pos: Vector3, rng: Random)
	local len = 4 + rng:NextNumber() * 4
	local yaw = rng:NextNumber() * math.pi
	Make.decor({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 0.55, 0.55), CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, yaw, math.rad(rng:NextInteger(-5, 5))), Color = Make.shade(Palette.Wood, -0.12), Material = Enum.Material.Wood }, parent)
	for i = 1, 2 do
		Make.decor({ Size = Vector3.new(0.2, 0.2, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new((i - 1.5) * len * 0.3, 0, 0.5) * CFrame.Angles(0, math.rad(40), 0), Color = Make.shade(Palette.Wood, -0.1), Material = Enum.Material.Wood }, parent)
	end
end

local function rubble(parent, pos: Vector3, rng: Random)
	for _ = 1, 3 do
		local s = 0.6 + rng:NextNumber() * 1.1
		Make.decor({
			Size = Vector3.new(s * 1.4, s, s),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber() * 2 - 1, s / 2, rng:NextNumber() * 2 - 1)) * CFrame.Angles(rng:NextNumber(), rng:NextNumber() * 3, 0),
			Color = Color3.fromRGB(140, 128, 108), Material = Enum.Material.Slate,
		}, parent)
	end
end

local function dryTuft(parent, pos: Vector3, rng: Random)
	tuft(parent, pos, rng, Color3.fromRGB(184, 160, 96))
end

local function snowMound(parent, pos: Vector3, rng: Random)
	local s = 2 + rng:NextNumber() * 2
	Make.decor({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.5, s * 0.8, s * 1.3), Position = pos + Vector3.new(0, s * 0.2, 0), Color = Color3.fromRGB(238, 246, 255), Material = Enum.Material.Snow }, parent)
end

local function stalagmite(parent, pos: Vector3, rng: Random)
	local h = 2 + rng:NextNumber() * 3.5
	local c = Color3.fromRGB(72, 86, 98)
	Make.part({ Size = Vector3.new(1.6, h * 0.5, 1.6), Position = pos + Vector3.new(0, h * 0.25, 0), Color = c, Material = Enum.Material.Slate }, parent)
	Make.part({ Size = Vector3.new(0.9, h * 0.6, 0.9), Position = pos + Vector3.new(0, h * 0.7, 0), Color = Make.shade(c, 0.05), Material = Enum.Material.Slate }, parent)
end

local function icicleCrystal(parent, pos: Vector3, rng: Random)
	local h = 1.6 + rng:NextNumber() * 2.4
	Make.decor({
		Size = Vector3.new(0.9, h, 0.9),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * 3, math.rad(rng:NextInteger(-10, 10))),
		Color = Color3.fromRGB(190, 225, 250), Material = Enum.Material.Ice, Transparency = 0.15,
	}, parent)
end

local function rock(parent, pos: Vector3, rng: Random, color: Color3)
	local s = 1.5 + rng:NextNumber() * 2.5
	Make.part({
		Size = Vector3.new(s * 1.3, s, s),
		CFrame = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
		Color = Make.shade(color, (rng:NextNumber() - 0.5) * 0.1),
		Material = Enum.Material.Slate,
	}, parent)
end

local function pillar(parent, pos: Vector3, rng: Random, color: Color3)
	local h = 3 + rng:NextInteger(0, 5)
	Make.part({ Size = Vector3.new(2.4, h, 2.4), Position = pos + Vector3.new(0, h / 2, 0), Color = color, Material = Enum.Material.Slate }, parent)
	Make.part({ Size = Vector3.new(3, 0.8, 3), Position = pos + Vector3.new(0, h + 0.4, 0), Color = Make.shade(color, 0.05), Material = Enum.Material.Slate }, parent)
end

local function crystal(parent, pos: Vector3, rng: Random)
	local h = 2 + rng:NextNumber() * 3
	local part = Make.part({
		Size = Vector3.new(1.2, h, 1.2),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, math.rad(rng:NextInteger(-12, 12))),
		Color = Color3.fromRGB(110, 190, 240),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	}, parent)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = part
end

local PROPS = {
	woodland = { tree, tree, tree, tree, rock, boulder, bush, berryBush },
	ruins = { pillar, rock, deadTree, rock },
	cavern = { crystal, rock, rock, stalagmite },
	tower = { pillar, rock },
	frost = { rock, snowPine, snowPine, rock },
}
-- Small ground detail scattered on top of the main props (about 2x as many).
local DETAIL = {
	woodland = { tuft, tuft, tallGrass, tallGrass, flowers, flowers, flowers, mushroom, fern, fern, bush, log, stump, fallenBranch, berryBush },
	ruins = { dryTuft, dryTuft, rubble, rubble, rock },
	cavern = { glowMushroom, rubble, stalagmite },
	tower = { rubble },
	frost = { snowMound, snowMound, icicleCrystal, rubble },
}

-- ----------------------------------------------------------- feature visuals

local QUEST_MARKERS = {
	runner = true, hunter = true, kit = true, repair = true, altar = true, seal = true,
	dry_ditch = true, rooted_crop = true, empty_granary = true, channel_west = true, channel_east = true,
	sluice_open = true, cellar_begin = true, additive_ledger = true, field_restored = true,
}

local function featureModel(parent: Instance, feature, pos: Vector3, region)
	local model = Instance.new("Model")
	model.Name = "Feature_" .. feature.key
	model.Parent = parent
	local kind = feature.kind
	local root

	local isFigure = false
	if kind == "talk" or kind == "hunter" or kind == "witness" or kind == "villager" then
		isFigure = true
		local shirt, skin, hair, hat = "#c68b52", "#f0cd9a", "#49352e", nil
		if kind == "hunter" then
			shirt = "#8a9d61"
		elseif kind == "villager" then
			local rng = Random.new(#feature.key * 977 + string.byte(feature.key, #feature.key))
			local shirts = { "#ba7777", "#8fb583", "#759fbf", "#d0b475", "#b59bcd" }
			local skins = { "#f0cd9a", "#cc9871", "#94664e" }
			local hairs = { "#49352e", "#b88d58", "#ddd0b7" }
			shirt = feature.service == "guildmaster" and "#a94f3d" or feature.service == "alchemist" and "#6aa889" or feature.service == "merchant" and "#c68b52" or shirts[rng:NextInteger(1, #shirts)]
			skin = skins[rng:NextInteger(1, #skins)]
			hair = hairs[rng:NextInteger(1, #hairs)]
			if feature.service == "alchemist" or feature.service == "guildmaster" then
				hat = shirt
			end
		end
		local function limb(name, size, offset, color)
			Make.part({ Name = name, Size = size, Position = pos + offset, Color = Palette.hex(color) }, model)
		end
		limb("Leg_A", Vector3.new(0.7, 2, 0.9), Vector3.new(-0.38, 1, 0), "#3c3548")
		limb("Leg_B", Vector3.new(0.7, 2, 0.9), Vector3.new(0.38, 1, 0), "#3c3548")
		root = Make.part({ Name = "Torso", Size = Vector3.new(2, 2.4, 1.2), Position = pos + Vector3.new(0, 3.2, 0), Color = Palette.hex(shirt) }, model)
		limb("Arm_A", Vector3.new(0.6, 2.2, 0.7), Vector3.new(1.35, 3.2, 0), shirt)
		limb("Arm_B", Vector3.new(0.6, 2.2, 0.7), Vector3.new(-1.35, 3.2, 0), shirt)
		limb("Head", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 5.2, 0), skin)
		Make.decor({ Size = Vector3.new(0.25, 0.25, 0.1), Position = pos + Vector3.new(-0.38, 5.3, -0.82), Color = Palette.hex("#2a2420") }, model)
		Make.decor({ Size = Vector3.new(0.25, 0.25, 0.1), Position = pos + Vector3.new(0.38, 5.3, -0.82), Color = Palette.hex("#2a2420") }, model)
		Make.decor({ Size = Vector3.new(0.5, 0.12, 0.1), Position = pos + Vector3.new(0, 4.75, -0.82), Color = Palette.hex("#8a5a48") }, model)
		Make.part({ Name = "Hair", Size = Vector3.new(1.7, 0.6, 1.7), Position = pos + Vector3.new(0, 6.2, 0), Color = Palette.hex(hair) }, model)
		if hat then
			Make.part({ Name = "Hat", Size = Vector3.new(2.2, 0.4, 2.2), Position = pos + Vector3.new(0, 6.7, 0), Color = Palette.hex(hat) }, model)
			Make.part({ Name = "Hat", Size = Vector3.new(1.3, 1, 1.3), Position = pos + Vector3.new(0, 7.3, 0), Color = Palette.hex(hat) }, model)
		end
	elseif kind == "board" then
		root = Make.part({ Size = Vector3.new(0.7, 6, 0.7), Position = pos + Vector3.new(-2, 3, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(0.7, 6, 0.7), Position = pos + Vector3.new(2, 3, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(5.6, 3.4, 0.4), Position = pos + Vector3.new(0, 4.6, 0), Color = Palette.hex("#a98c58") }, model)
		for i, c in { "#f0ead7", "#d9caa4", "#f5a08b", "#9fd3e6" } do
			Make.decor({ Size = Vector3.new(1, 1.2, 0.1), Position = pos + Vector3.new(-1.9 + (i - 1) * 1.25, 4.8 + (i % 2) * 0.5, -0.25), Color = Palette.hex(c) }, model)
		end
	elseif kind == "chest" or kind == "dungeon_treasure" or kind == "discovery" then
		root = Make.part({ Size = Vector3.new(3, 2, 2), Position = pos + Vector3.new(0, 1, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(3.2, 0.5, 2.2), Position = pos + Vector3.new(0, 2.2, 0), Color = Palette.hex("#d2b36f") }, model)
	elseif kind == "signpost" then
		root = Make.part({ Size = Vector3.new(0.7, 6, 0.7), Position = pos + Vector3.new(0, 3, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(4, 1.2, 0.4), Position = pos + Vector3.new(0.6, 5.4, 0), Color = Palette.hex("#a98c58") }, model)
		Make.part({ Size = Vector3.new(3.4, 1.1, 0.4), Position = pos + Vector3.new(-0.4, 3.9, 0), Color = Palette.hex("#a98c58") }, model)
	elseif kind == "shop" then
		-- Market stall: counter, awning and a hanging sign.
		root = Make.part({ Size = Vector3.new(7, 2.4, 2.6), Position = pos + Vector3.new(0, 1.2, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(8, 0.5, 4), Position = pos + Vector3.new(0, 6, -0.6), Color = Palette.hex("#c0583f") }, model)
		for _, x in { -3.4, 3.4 } do
			Make.part({ Size = Vector3.new(0.6, 6, 0.6), Position = pos + Vector3.new(x, 3, -1.8), Color = Palette.Wood }, model)
		end
		Make.decor({ Size = Vector3.new(1.2, 1.2, 1.2), Position = pos + Vector3.new(0, 3, 0), Color = Palette.Gold, Material = Enum.Material.Neon }, model)
	elseif kind == "inn" then
		-- Bed: frame, mattress, pillow.
		root = Make.part({ Size = Vector3.new(4, 1.4, 7), Position = pos + Vector3.new(0, 0.7, 0), Color = Palette.Wood }, model)
		Make.part({ Size = Vector3.new(3.6, 0.8, 6.2), Position = pos + Vector3.new(0, 1.6, 0), Color = Palette.hex("#d9caa4") }, model)
		Make.part({ Size = Vector3.new(3, 0.6, 1.4), Position = pos + Vector3.new(0, 2.2, -2.4), Color = Palette.hex("#f0ead7") }, model)
	elseif kind == "waystone" or kind == "travel_shrine" then
		-- Standing stone with a glowing rune; dim until attuned (client colours via attribute).
		root = Make.part({ Size = Vector3.new(3, 7, 3), Position = pos + Vector3.new(0, 3.5, 0), Color = region.stone, Material = Enum.Material.Slate }, model)
		Make.part({ Size = Vector3.new(5, 1, 5), Position = pos + Vector3.new(0, 0.5, 0), Color = Make.shade(region.stone, -0.08), Material = Enum.Material.Slate }, model)
		local rune = Make.part({ Name = "Rune", Size = Vector3.new(1.6, 2.4, 0.4), Position = pos + Vector3.new(0, 4, -1.6), Color = Palette.Mint, Material = Enum.Material.Neon }, model)
		local light = Instance.new("PointLight")
		light.Color = Palette.Mint
		light.Range = 20
		light.Parent = rune
		model:SetAttribute("Waystone", feature.key)
	elseif kind == "shrine" or kind == "portal" then
		root = Make.part({ Size = Vector3.new(4, 2, 4), Position = pos + Vector3.new(0, 1, 0), Color = region.stone, Material = Enum.Material.Slate }, model)
		local orb = Make.part({ Size = Vector3.new(1.6, 1.6, 1.6), Position = pos + Vector3.new(0, 3.4, 0), Color = Palette.Mint, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball }, model)
		local light = Instance.new("PointLight")
		light.Color = Palette.Mint
		light.Range = 18
		light.Parent = orb
	elseif kind == "boss" or kind == "dungeon_begin" or kind == "mechanism" or kind == "bridge" then
		root = Make.part({ Size = Vector3.new(6, 0.6, 6), Position = pos + Vector3.new(0, 0.3, 0), Color = region.stone, Material = Enum.Material.Slate }, model)
		Make.part({ Size = Vector3.new(4.4, 0.7, 4.4), Position = pos + Vector3.new(0, 0.4, 0), Color = Palette.hex("#ee847d"), Material = Enum.Material.Neon, Transparency = 0.35 }, model)
	else -- clue / dungeon_story / anything new: a small cairn with a mint spark.
		root = Make.part({ Size = Vector3.new(2.2, 1.2, 2.2), Position = pos + Vector3.new(0, 0.6, 0), Color = region.stone, Material = Enum.Material.Slate }, model)
		Make.part({ Size = Vector3.new(1.4, 1, 1.4), Position = pos + Vector3.new(0, 1.7, 0), Color = Make.shade(region.stone, 0.05), Material = Enum.Material.Slate }, model)
		Make.decor({ Size = Vector3.new(0.6, 0.6, 0.6), Position = pos + Vector3.new(0, 3, 0), Color = Palette.Mint, Material = Enum.Material.Neon }, model)
	end

	if isFigure then
		Rig.weld(model, root)
		CollectionService:AddTag(model, "Npc")
	end
	Make.label(root, feature.name, Palette.UI.gold, 5, 240)

	-- Gold "!" above whatever the current quest step points at (Quests toggles Enabled).
	if QUEST_MARKERS[feature.key] then
		local gui = Instance.new("BillboardGui")
		gui.Name = "QuestMarker"
		gui.Size = UDim2.fromOffset(40, 40)
		gui.StudsOffset = Vector3.new(0, 11, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 400
		gui.Enabled = false
		gui:SetAttribute("Key", feature.key)
		local mark = Instance.new("TextLabel")
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Text = "!"
		mark.Font = Enum.Font.GothamBlack
		mark.TextSize = 40
		mark.TextColor3 = Palette.Gold
		mark.TextStrokeTransparency = 0
		mark.Parent = gui
		gui.Adornee = root
		gui.Parent = root
		CollectionService:AddTag(gui, "QuestMarker")
	end
	return model, root
end

-- ------------------------------------------------------------------ populate

-- rect: WorldLayout rect. handlers.onFeature(player, featureTable). holes: world rects to keep clear.
-- Ground slabs, walls around chambers and trails are built by WorldBuilder.
function AreaBuilder.populate(areaId: string, rect, folder: Folder, handlers, holes)
	local spec = Adventure.AREAS[areaId]
	local region = Palette.Regions[spec.region] or Palette.Regions.woodland
	local widthPx, heightPx = AreaBuilder.sizePx(areaId)
	local S = Config.WORLD_STUDS_PER_PX
	local origin = Vector3.new(rect.left, rect.y, rect.top)
	local rng = Random.new(rect.cx * 31 + rect.cz * 17 + 13)

	local function w(x, y, h)
		return Coord.toWorld(origin, x, y, h)
	end
	local widthS, heightS = rect.w, rect.h
	local H = Config.WALL_HEIGHT

	-- Pixel-art ground tiles (decor only: collision comes from the slabs).
	local tiles = Instance.new("Model")
	tiles.Name = "Tiles"
	tiles.Parent = folder
	local t = Config.TILE_STUDS
	for tx = 0, math.ceil(widthS / t) - 1 do
		for tz = 0, math.ceil(heightS / t) - 1 do
			local tw, th = math.min(t, widthS - tx * t), math.min(t, heightS - tz * t)
			-- Smooth large-scale colour drift (ground <-> accent) instead of per-tile dice rolls, so the
			-- ground reads as meadow patches rather than a checkerboard.
			local wx, wz = origin.X + tx * t + tw / 2, origin.Z + tz * t + th / 2
			local n1 = math.noise(wx / 110, wz / 110, 3.7) * 1.6
			local n2 = math.noise(wx / 37, wz / 37, 9.1) * 0.8
			local blend = math.clamp(0.5 + n1, 0, 1)
			local base = region.ground:Lerp(region.accent, blend * 0.7)
			Make.decor({
				Size = Vector3.new(tw, 0.2, th),
				Position = origin + Vector3.new(tx * t + tw / 2, 0.1, tz * t + th / 2),
				Color = Make.shade(base, n2 * 0.05 + (rng:NextNumber() - 0.5) * 0.015),
				Material = region.material,
			}, tiles)
		end
	end

	-- Authored obstacles: dungeon walls and camp/ruin landmarks. Rects are (x, y, w, h) px.
	local function block(r, color: Color3, height: number)
		local p = w(r[1] + r[3] / 2, r[2] + r[4] / 2, height / 2)
		Make.part({
			Size = Vector3.new(r[3] * S, height, r[4] * S),
			Position = p,
			Color = color,
			Material = Enum.Material.Slate,
		}, folder)
	end
	local wallHeight = rect.kind == "surface" and H or math.min(H, 22)
	for _, r in Dungeons.WALLS[areaId] or {} do
		block(r, region.stone, wallHeight)
	end
	for _, r in Adventure.SOLID_LANDMARKS[areaId] or {} do
		block(r, areaId == "camp" and Palette.hex("#b8a06a") or region.stone, areaId == "camp" and 5 or 9)
	end

	-- Keep-clear zones (px) so scenery never sits on an NPC or enemy territory.
	local clear = {}
	local function keepClear(x, y, radiusPx)
		table.insert(clear, { x, y, radiusPx })
	end

	-- Villages: houses, roads, plaza.
	for _, c in VillageBuilder.build(areaId, folder, w, widthPx, heightPx, rng) do
		table.insert(clear, c)
	end

	-- Features.
	for _, feature in AreaBuilder.features(areaId, widthPx, heightPx) do
		keepClear(feature.x, feature.y, 90)
		local pos = w(feature.x, feature.y, 0)
		local _, root = featureModel(folder, feature, pos, region)
		local prompt = Instance.new("ProximityPrompt")
		local verbs = {
			talk = "Talk", hunter = "Talk", witness = "Talk", shop = "Shop", inn = "Rest", board = "Change hero",
			waystone = "Travel", travel_shrine = "Attune / Travel", chest = "Open", dungeon_treasure = "Open", boss = "Break the seal",
		}
		local serviceVerbs = {
			innkeeper = "Talk", merchant = "Shop", alchemist = "Browse potions", guildmaster = "Bounty board",
			caretaker = "Treatment (5 runes)", lodge = "Ask for advice", gossip = "Talk", guild_board = "Change hero",
		}
		prompt.ActionText = serviceVerbs[feature.service] or verbs[feature.kind] or "Inspect"
		prompt.ObjectText = feature.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function(player)
			handlers.onFeature(player, feature)
		end)
	end
	for _, group in Adventure.GROUPS[areaId] or {} do
		local x, y = Coord.scaleToArea(group[3], group[4], widthPx, heightPx)
		keepClear(x, y, 140)
	end
	for _, pack in Dungeons.PACKS[areaId] or {} do
		keepClear(pack[1], pack[2], 140)
	end

	-- Large open areas: ponds, meadows, groves, boulders, standing stones.
	if Sizes.MULT[areaId] and rect.kind == "surface" then
		Scenic.openSpace(folder, widthPx, heightPx, w, clear, rng, AreaBuilder.props, holes, rect)
	end

	-- Scenery scatter. Density follows area size; stays off the walls.
	local props = Instance.new("Model")
	props.Name = "Scenery"
	props.Parent = folder
	local makers = PROPS[rect.kind == "tower" and "tower" or spec.region] or PROPS.woodland
	local count = math.floor(widthPx * heightPx / 6000)
	local margin = rect.kind == "surface" and 40 or 120 -- px
	local placed = 0
	for _ = 1, count * 3 do
		if placed >= count then
			break
		end
		local x = margin + rng:NextNumber() * (widthPx - 2 * margin)
		local y = margin + rng:NextNumber() * (heightPx - 2 * margin)
		local ok = true
		for _, c in clear do
			if (c[1] - x) ^ 2 + (c[2] - y) ^ 2 < c[3] ^ 2 then
				ok = false
				break
			end
		end
		for _, hole in holes or {} do
			local wx, wz = rect.left + x * S, rect.top + y * S
			if wx > hole[1] - 8 and wx < hole[2] + 8 and wz > hole[3] - 8 and wz < hole[4] + 8 then
				ok = false
			end
		end
		if ok then
			placed += 1
			local maker = makers[rng:NextInteger(1, #makers)]
			if maker == tree or maker == rock or maker == pillar then
				maker(props, w(x, y, 0), rng, region.stone)
			else
				maker(props, w(x, y, 0), rng)
			end
		end
	end

	-- Small ground detail (grass, flowers, mushrooms, rubble...). Same clearances, ~2x as many.
	local details = DETAIL[rect.kind == "tower" and "tower" or spec.region] or DETAIL.woodland
	local detailCount = math.min(math.floor(count * 2 * Config.DETAIL_DENSITY), 1600)
	local dPlaced = 0
	for _ = 1, detailCount * 2 do
		if dPlaced >= detailCount then
			break
		end
		local x = margin + rng:NextNumber() * (widthPx - 2 * margin)
		local y = margin + rng:NextNumber() * (heightPx - 2 * margin)
		local ok = true
		for _, c in clear do
			if (c[1] - x) ^ 2 + (c[2] - y) ^ 2 < (c[3] * 0.8) ^ 2 then
				ok = false
				break
			end
		end
		for _, hole in holes or {} do
			local wx, wz = rect.left + x * S, rect.top + y * S
			if wx > hole[1] - 4 and wx < hole[2] + 4 and wz > hole[3] - 4 and wz < hole[4] + 4 then
				ok = false
			end
		end
		if ok then
			dPlaced += 1
			local maker = details[rng:NextInteger(1, #details)]
			if maker == rock then
				maker(props, w(x, y, 0), rng, region.stone)
			else
				maker(props, w(x, y, 0), rng)
			end
		end
	end
end

-- Exposed so WorldBuilder can scatter wilderness props with the same look.
AreaBuilder.props = { tree = tree, rock = rock, bush = bush, tuft = tuft, flowers = flowers, mushroom = mushroom, fern = fern, log = log, boulder = boulder, tallGrass = tallGrass, stump = stump, berryBush = berryBush }

return AreaBuilder
