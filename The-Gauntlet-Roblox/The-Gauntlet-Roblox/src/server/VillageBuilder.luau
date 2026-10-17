--!nonstrict
-- Oakvale (home) and Dunmere hubs: enterable blocky houses (Inn, Store, Alchemy Lab, Guild,
-- Cottage, Lodge), dirt roads to a cobble plaza, villagers.
-- Layout positions + roof colours come from the 2D TownLayout export (px in a 960x540 area);
-- the 2D game re-rolls its layout each run, the port uses one fixed layout per hub.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Coord = require(Shared.Coord)
local Data = require(Shared.Data)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)

local Town = Data.TownLayout
local S = Config.WORLD_STUDS_PER_PX

local VillageBuilder = {}

local HUB_LAYOUT = { home = "crescent", dunmere = "western_common" }
local HUB_EXITS = { home = { "south" }, dunmere = { "north", "east" } }

local W, D, WALL_H = 20, 16, 9 -- house footprint (studs) and wall height
local DOOR = 5
local PATH_W = 5
local _SHIRTS = { "#ba7777", "#8fb583", "#759fbf", "#d0b475", "#b59bcd" }
local _SKINS = { "#f1cda1", "#cc9871", "#94664e" }
local _HAIRS = { "#49352e", "#b88d58", "#ddd0b7" }

local hex = Palette.hex

-- Houses for a hub, in area px. facing = +1: door on the +z (south) side, -1: north.
function VillageBuilder.houses(areaId: string)
	local kind = HUB_LAYOUT[areaId]
	if not kind then
		return nil
	end
	local positions = Town.LAYOUTS[kind]
	local plazaY = Town.PORTAL[2]
	local list = {}
	for i, b in Town.BUILDINGS do
		local p = positions[i]
		list[i] = {
			key = b[1],
			name = b[2],
			role = b[3],
			x = p[1],
			y = p[2],
			facing = (plazaY - p[2]) >= 0 and 1 or -1,
			roof = Town.ROOFS[i],
		}
	end
	return list
end


-- Interactable villagers & service points for a hub (area px). `service` picks the handler in
-- Services.luau (merchant = shop). Positions are inside their buildings.
local SERVICES = {
	inn = { { "innkeeper", "Innkeeper", "innkeeper", 1.5, 5.6 } },
	store = { { "merchant", "Merchant", "merchant", 0, 5.9 } },
	lab = { { "alchemist", "Alchemist · Potions", "alchemist", 0, 4.5 } },
	guild = {
		{ "guildmaster", "Guildmaster · Bounties", "guildmaster", -3, 5.6 },
		{ "guild_board", "Guild registry · Change hero", "guild_board", 6, 6 },
	},
	cottage = { { "caretaker", "Mara · Cottage recovery", "caretaker", 0, 5 } },
	lodge = { { "hunter_lodge", "Hunter · Frontier guide", "lodge", 0, 2.5 } },
}

function VillageBuilder.features(areaId: string)
	local houses = VillageBuilder.houses(areaId)
	local list = {}
	if not houses then
		return list
	end
	for _, h in houses do
		for _, spec in SERVICES[h.key] or {} do
			table.insert(list, {
				key = spec[1] .. "_" .. areaId,
				name = spec[2],
				service = spec[3],
				kind = spec[3] == "guild_board" and "board" or "villager",
				x = h.x + spec[4] / S,
				y = h.y - h.facing * spec[5] / S,
				area = areaId,
			})
		end
	end
	-- Plaza loiterers with tips.
	for i, angle in { 25, 95, 160, 215, 330 } do
		local r = 62 + (i % 2) * 18
		table.insert(list, {
			key = ("villager_%s_%d"):format(areaId, i),
			name = "Villager",
			service = "gossip",
			kind = "villager",
			x = Town.PORTAL[1] + math.cos(math.rad(angle)) * r,
			y = Town.PORTAL[2] + math.sin(math.rad(angle)) * r,
			area = areaId,
		})
	end
	return list
end

-- Where the Inn bed / Store stall feature stands inside its building (area px).
function VillageBuilder.serviceSpot(areaId: string, featureKey: string): (number?, number?)
	local houses = VillageBuilder.houses(areaId)
	if not houses then
		return nil, nil
	end
	for _, h in houses do
		if featureKey == "shop" and h.key == "store" then
			return h.x, h.y - h.facing * 4 / S
		elseif featureKey == "inn" and h.key == "inn" then
			return h.x - 5 / S, h.y - h.facing * 3 / S
		end
	end
	return nil, nil
end

local function house(parent: Instance, base: Vector3, h, rng: Random)
	local model = Instance.new("Model")
	model.Name = "House_" .. h.key
	model.Parent = parent
	local f = h.facing
	local wallColor = Make.shade(hex("#d9caa4"), (rng:NextNumber() - 0.5) * 0.08)
	local trim = hex("#786442")
	local roof = hex(h.roof)

	-- lx across the house, lz from the centre toward the BACK (away from the door).
	local function put(lx, lz, height, sx, sy, sz, color, solid)
		local props = {
			Size = Vector3.new(sx, sy, sz),
			Position = base + Vector3.new(lx, height, -f * lz),
			Color = color,
		}
		if solid == false then
			return Make.decor(props, model)
		end
		return Make.part(props, model)
	end

	-- Floor (decor, ground slab collides).
	put(0, 0, 0.32, W - 2, 0.1, D - 2, hex("#8a6f48"), false)

	-- Walls: front has a door gap, lintel and a sign.
	local seg = (W - DOOR) / 2
	put(-(DOOR / 2 + seg / 2), -(D / 2 - 0.5), WALL_H / 2, seg, WALL_H, 1, wallColor)
	put(DOOR / 2 + seg / 2, -(D / 2 - 0.5), WALL_H / 2, seg, WALL_H, 1, wallColor)
	put(0, -(D / 2 - 0.5), 7.75, DOOR, WALL_H - 6.5, 1, trim)
	put(0, D / 2 - 0.5, WALL_H / 2, W, WALL_H, 1, wallColor)
	for _, side in { -1, 1 } do
		put(side * (W / 2 - 0.5), 0, WALL_H / 2, 1, WALL_H, D - 2, wallColor)
		-- corner posts + windows
		put(side * (W / 2), -(D / 2), WALL_H / 2, 1.4, WALL_H, 1.4, trim)
		put(side * (W / 2), D / 2, WALL_H / 2, 1.4, WALL_H, 1.4, trim)
		local glass = put(side * (W / 2 + 0.1), 0, 5, 0.3, 3, 3.4, hex("#9fd3e6"), false)
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.25
	end
	local back = put(0, D / 2 + 0.1, 5, 3.4, 3, 0.3, hex("#9fd3e6"), false)
	back.Material = Enum.Material.Glass
	back.Transparency = 0.25

	-- Pitched gable roof: two slanted slabs meeting at a ridge, gable ends filled with stepped wall.
	local rise, half = 5.5, (W + 3) / 2
	local slope = math.sqrt(half * half + rise * rise)
	local angle = math.atan2(rise, half)
	local roofDepth = D + 3
	for _, side in { -1, 1 } do
		local slab = Make.decor({
			Size = Vector3.new(slope + 0.4, 0.8, roofDepth),
			CFrame = CFrame.new(base + Vector3.new(side * half / 2, 9.4 + rise / 2, 0)) * CFrame.Angles(0, 0, -side * angle),
			Color = Make.shade(roof, side * 0.03),
			Material = Enum.Material.Slate,
		}, model)
		slab.CastShadow = true
	end
	put(0, 0, 9.4 + rise + 0.25, 1.4, 0.7, roofDepth + 0.2, Make.shade(roof, -0.12), false)
	for _, lz in { -(D / 2 - 0.5), D / 2 - 0.5 } do
		for i = 0, 3 do
			local lift = 0.7 + i * 1.4
			put(0, lz, 9.2 + lift, W * (1 - lift / rise), 1.4, 1, wallColor)
		end
	end
	-- Timber band under the eaves and flower boxes below the side windows.
	put(0, 0, 8.6, W + 0.4, 0.5, D + 0.4, trim, false)
	for _, side in { -1, 1 } do
		put(side * (W / 2 + 0.7), 0, 2.9, 0.9, 0.8, 3.8, hex("#6a4f2e"), false)
		for k = -1, 1 do
			local bloom = put(side * (W / 2 + 0.7), k * 1.2, 3.5, 0.7, 0.6, 0.7, ({ hex("#e07a8a"), hex("#f0d36a"), hex("#c8a0e0") })[(k + 2 + (side > 0 and 1 or 0)) % 3 + 1], false)
			bloom.Shape = Enum.PartType.Ball
		end
	end
	-- Chimney with smoke.
	local chimneyX = 5
	local chimneyZ = 3
	local roofY = 9.4 + rise * (1 - chimneyX / half)
	put(chimneyX, chimneyZ, roofY + 2, 2.2, 6, 2.2, hex("#8d8a7a"))
	put(chimneyX, chimneyZ, roofY + 5.2, 2.8, 0.6, 2.8, hex("#6f6c60"), false)
	local vent = put(chimneyX, chimneyZ, roofY + 5.6, 1, 0.2, 1, hex("#222222"), false)
	vent.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 5
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(0.8, 1.5, 0)
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.LightEmission = 0
	smoke.Parent = vent
	-- Door step + sign.
	put(0, -(D / 2 + 0.8), 0.25, DOOR + 1, 0.5, 1.6, hex("#8d8a7a"))
	local sign = put(0, -(D / 2 + 0.7), 8.2, 7, 1.6, 0.4, hex("#a98c58"), false)
	Make.label(sign, h.name, Palette.UI.ink, 0, 140, 40)
	-- Ceiling lantern.
	local lamp = put(0, 0, 8.4, 1, 0.5, 1, hex("#ffd9a0"), false)
	lamp.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = hex("#ffd9a0")
	light.Range = 26
	light.Brightness = 1.2
	light.Parent = lamp

	-- Furniture + service NPC by building kind.
	local wood = Palette.Wood
	local function table_(lx, lz, sx, sz)
		put(lx, lz, 1.2, sx - 1, 2.4, sz - 1, wood)
		put(lx, lz, 2.6, sx, 0.5, sz, hex("#a98c58"))
	end
	local function bed(lx, lz)
		put(lx, lz, 0.7, 4, 1.4, 7, wood)
		put(lx, lz, 1.6, 3.6, 0.8, 6.2, hex("#d9caa4"))
		put(lx, lz + 2.4, 2.2, 3, 0.6, 1.4, hex("#f0ead7"))
	end
	local function shelf(lx, lz, colors)
		put(lx, lz, 3, 1.2, 6, 6, wood)
		for level = 0, 2 do
			for i = 0, 2 do
				local c = colors[(level * 3 + i) % #colors + 1]
				local goods = put(lx - (lx > 0 and 0.9 or -0.9), lz - 2 + i * 2, 1.3 + level * 2, 0.8, 0.8, 0.8, c, false)
				if c == colors[1] and h.key == "lab" then
					goods.Material = Enum.Material.Neon
				end
			end
		end
	end
	if h.key == "inn" then
		table_(5, 2, 4, 4)
		for _, dz in { -3.2, 3.2 } do
			put(5, 2 + dz, 0.8, 1.4, 1.6, 1.4, wood)
		end
	elseif h.key == "store" then
		shelf(-8.2, 1, { hex("#c0583f"), hex("#d2b36f"), hex("#8fb583") })
		shelf(8.2, 1, { hex("#759fbf"), hex("#d0b475"), hex("#b59bcd") })
	elseif h.key == "lab" then
		shelf(8.2, 2, { hex("#7be0a8"), hex("#ee847d"), hex("#b7d49a") })
		local pot = put(-5, 3, 1.6, 3.2, 3.2, 3.2, hex("#2f3a38"))
		pot.Shape = Enum.PartType.Cylinder
		pot.CFrame = CFrame.new(pot.Position) * CFrame.Angles(0, 0, math.pi / 2)
		local brew = put(-5, 3, 3.2, 0.2, 2.6, 2.6, hex("#7be0a8"), false)
		brew.Shape = Enum.PartType.Cylinder
		brew.Material = Enum.Material.Neon
		brew.CFrame = CFrame.new(brew.Position) * CFrame.Angles(0, 0, math.pi / 2)
	elseif h.key == "guild" then
		table_(0, 2.5, 10, 3)
		put(0, D / 2 - 1.2, 5.5, 4, 5, 0.2, hex("#a94f3d"), false)
		put(0, D / 2 - 1.3, 5.8, 1.6, 1.6, 0.2, Palette.Gold, false)
	elseif h.key == "cottage" then
		bed(-5, 3.3)
		table_(5, 3, 3, 3)
	elseif h.key == "lodge" then
		put(0, D / 2 - 2.5, 2, 6, 4, 2, hex("#8d8a7a"))
		local fire = put(0, D / 2 - 3.6, 1, 2, 1.4, 0.4, hex("#ffa24a"), false)
		fire.Material = Enum.Material.Neon
		for i = 0, 2 do
			put(-6.5, 2.5 + i * 1.2, 0.6, 0.9, 0.9, 5, hex("#6a4f2e"))
		end
		put(6, 3, 0.8, 4, 1.6, 2, wood)
	end
	return model
end

local function strip(parent: Instance, w, ax: number, az: number, bx: number, bz: number)
	-- Axis-aligned dirt strip between two points given in area px.
	local x0, x1 = math.min(ax, bx), math.max(ax, bx)
	local z0, z1 = math.min(az, bz), math.max(az, bz)
	local width = PATH_W
	Make.decor({
		Size = Vector3.new((x1 - x0) * S + width, 0.1, (z1 - z0) * S + width),
		Position = w((x0 + x1) / 2, (z0 + z1) / 2, 0.25),
		Color = hex("#a38a5e"),
		Material = Enum.Material.Ground,
	}, parent)
end

local function lampPost(parent: Instance, at: Vector3, height: number)
	local pole = Make.decor({ Size = Vector3.new(0.5, height, 0.5), Position = at + Vector3.new(0, height / 2, 0), Color = hex("#3a3328"), Material = Enum.Material.Metal }, parent)
	pole.CastShadow = true
	local arm = Make.decor({ Size = Vector3.new(1.4, 0.3, 0.3), Position = at + Vector3.new(0.6, height - 0.2, 0), Color = hex("#3a3328") }, parent)
	local lamp = Make.decor({ Size = Vector3.new(0.9, 1.1, 0.9), Position = at + Vector3.new(1.3, height - 0.9, 0), Color = hex("#ffd9a0"), Material = Enum.Material.Neon }, parent)
	local light = Instance.new("PointLight")
	light.Color = hex("#ffd9a0")
	light.Range = 22
	light.Brightness = 0.9
	light.Parent = lamp
	return arm
end

-- Well, lamp posts and benches around the plaza (decor only: never blocks movement).
function VillageBuilder.plazaDecor(parent: Instance, center: Vector3)
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		lampPost(parent, center + Vector3.new(math.cos(a) * 15, 0.3, math.sin(a) * 15), 8)
	end
	local well = center + Vector3.new(8, 0, -8)
	local ring = Make.decor({ Size = Vector3.new(2.2, 5.2, 5.2), CFrame = CFrame.new(well + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#8d8a7a"), Material = Enum.Material.Cobblestone }, parent)
	ring.Shape = Enum.PartType.Cylinder
	ring.CastShadow = true
	local water = Make.decor({ Size = Vector3.new(0.2, 4, 4), CFrame = CFrame.new(well + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#4f8fcf"), Material = Enum.Material.Glass, Transparency = 0.3 }, parent)
	water.Shape = Enum.PartType.Cylinder
	for _, sx in { -2.4, 2.4 } do
		Make.decor({ Size = Vector3.new(0.5, 6, 0.5), Position = well + Vector3.new(sx, 3.2, 0), Color = hex("#6a4f2e"), Material = Enum.Material.Wood }, parent)
	end
	local cap = Make.decor({ Size = Vector3.new(6.4, 0.6, 4.4), Position = well + Vector3.new(0, 6.4, 0), Color = hex("#a0523d"), Material = Enum.Material.Slate }, parent)
	cap.CastShadow = true
end

-- Per-house yard: lamp by the door, barrels, a crate stack, a hay bale.
function VillageBuilder.yardDecor(parent: Instance, base: Vector3, h, rng: Random)
	local f = h.facing
	local doorZ = f * (D / 2 + 2.5) -- door is on the +f side of the house
	local sideSign = rng:NextInteger(0, 1) == 0 and -1 or 1
	lampPost(parent, base + Vector3.new(-sideSign * (DOOR / 2 + 2.5), 0.3, doorZ), 7)
	local at = base + Vector3.new(sideSign * (DOOR / 2 + 3.5), 0, doorZ)
	for i = 0, 1 do
		local barrel = Make.decor({
			Size = Vector3.new(2.4, 2, 2),
			CFrame = CFrame.new(at + Vector3.new(i * 2.2, 1.2, i * 0.8)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = hex("#7a5a38"),
			Material = Enum.Material.Wood,
		}, parent)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CastShadow = true
	end
	local crate = Make.decor({ Size = Vector3.new(2, 2, 2), Position = at + Vector3.new(0.4, 1.1, -2.2 * f), Color = hex("#9a7a4c"), Material = Enum.Material.WoodPlanks }, parent)
	crate.CastShadow = true
	Make.decor({ Size = Vector3.new(1.5, 1.5, 1.5), Position = at + Vector3.new(0.6, 2.8, -2.2 * f), CFrame = CFrame.new(at + Vector3.new(0.6, 2.8, -2.2 * f)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Color = hex("#b08a56"), Material = Enum.Material.WoodPlanks }, parent)
	if rng:NextNumber() < 0.6 then
		local hay = Make.decor({ Size = Vector3.new(3, 1.8, 2), Position = base + Vector3.new(-sideSign * (W / 2 + 3), 0.9, f * 2), Color = hex("#d2b36f"), Material = Enum.Material.Fabric }, parent)
		hay.CastShadow = true
	end
end

-- Builds the village into `folder`. Returns keep-clear circles {x, y, r} in area px.
function VillageBuilder.build(areaId: string, folder: Instance, w, widthPx: number, heightPx: number, rng: Random)
	local houses = VillageBuilder.houses(areaId)
	if not houses then
		return {}
	end
	local clear = {}
	local village = Instance.new("Model")
	village.Name = "Village"
	village.Parent = folder
	local roads = Instance.new("Model")
	roads.Name = "Roads"
	roads.Parent = village

	local px, pz = Town.PORTAL[1], Town.PORTAL[2]

	-- Roads: house door -> street row -> plaza; plaza -> area exits.
	for _, h in houses do
		local doorZ = h.y + h.facing * (D / 2 + 3) / S
		local rowZ = ((pz - doorZ) * h.facing >= 0) and pz or doorZ
		strip(roads, w, h.x, doorZ, h.x, rowZ)
		strip(roads, w, h.x, rowZ, px, rowZ)
		table.insert(clear, { h.x, h.y, 62 })
		for t = 0, 1, 0.25 do
			table.insert(clear, { h.x + (px - h.x) * t, rowZ, 32 })
		end
	end
	for _, exit in HUB_EXITS[areaId] or {} do
		if exit == "south" then
			strip(roads, w, px, pz, px, heightPx)
		elseif exit == "north" then
			strip(roads, w, px, 0, px, pz)
		elseif exit == "east" then
			strip(roads, w, px, pz, widthPx, pz)
		end
	end

	-- Plaza.
	local rim = Make.decor({
		Size = Vector3.new(0.12, 30, 30),
		Color = hex("#6f6c60"),
		Material = Enum.Material.Slate,
	}, village)
	rim.Shape = Enum.PartType.Cylinder
	rim.CFrame = CFrame.new(w(px, pz, 0.3)) * CFrame.Angles(0, 0, math.pi / 2)
	local plaza = Make.decor({
		Size = Vector3.new(0.14, 26, 26),
		Color = hex("#8d8b84"),
		Material = Enum.Material.Cobblestone,
	}, village)
	plaza.Shape = Enum.PartType.Cylinder
	plaza.CFrame = CFrame.new(w(px, pz, 0.34)) * CFrame.Angles(0, 0, math.pi / 2)
	local inlay = Make.decor({
		Size = Vector3.new(0.16, 9, 9),
		Color = hex("#b8a06a"),
		Material = Enum.Material.Pavement,
	}, village)
	inlay.Shape = Enum.PartType.Cylinder
	inlay.CFrame = CFrame.new(w(px, pz, 0.38)) * CFrame.Angles(0, 0, math.pi / 2)
	table.insert(clear, { px, pz, 85 })

	for _, h in houses do
		house(village, w(h.x, h.y, 0), h, rng)
	end

	local decor = Instance.new("Model")
	decor.Name = "Decor"
	decor.Parent = village
	local center = w(px, pz, 0)
	VillageBuilder.plazaDecor(decor, center)
	for _, h in houses do
		VillageBuilder.yardDecor(decor, w(h.x, h.y, 0), h, rng)
	end

	return clear
end

return VillageBuilder
