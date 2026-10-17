--!nonstrict
-- Adventure enemies in the continuous world: lazy wake/sleep by player distance,
-- territory spawn, aggro/leash/return AI, melee and
-- ranged attacks. Ports adventure.build_area() stats and the basic behaviour of
-- enemy_awareness.py / enemy_roles.py.
-- Attacks have a red telegraph (stuns interrupt); enemies are blocked by world geometry.
-- TODO(port): awareness cues (! / ?), roles (charger windups, ambusher flanking,
-- support), projectiles that can be dodged, boss-specific mechanics.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Coord = require(Shared.Coord)
local Data = require(Shared.Data)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Stats = require(script.Parent.Stats)
local Progress = require(script.Parent.Progress)
local EnemyModels = require(script.Parent.EnemyModels)
local Loot = require(script.Parent.Loot)

local Adventure = Data.Adventure
local Dungeons = Data.Dungeons

local EnemyService = {}

local NAMES = {
	wolf = "Wolf",
	spider = "Cave Spider",
	serpent = "Serpent Guard",
	troll = "Marsh Troll",
	minotaur = "Forest Charger",
}
local NATURE = Data.Enemies.affinities.Nature
local BASE_COLOR = "#85977a"
local ROLES = Data.EnemyRoles.ROLES
-- Per-kind speed multipliers (spiders felt sluggish).
local SPEED_MULT = { spider = 1.7, wolf = 1.25, serpent = 1.2, troll = 1.1, minotaur = 1.2 }
local WANDER_AREA = 11000 -- studs^2 of area per extra wandering pack
local WANDER_MAX = 16

local function difficultyScale(): number
	return Data.GameCore.difficulties[Config.DIFFICULTY].multiplier / 1.25
end

-- adventure.group_positions() avoids obstacles; this port just rings the group (studs).
local function groupPositions(cx: number, cz: number, number: number)
	local out = {}
	for i = 1, number do
		local angle = (i / number) * math.pi * 2
		local radius = number == 1 and 0 or 5 + 1.6 * number
		out[i] = { cx + math.cos(angle) * radius, cz + math.sin(angle) * radius }
	end
	return out
end

local function enemiesFolder(): Folder
	local f = workspace:FindFirstChild("Enemies")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Enemies"
		f.Parent = workspace
	end
	return f
end

-- Static world geometry (walls, houses, trees, rocks) blocks enemies. Raycast against Workspace.World only.
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Include
local function worldBlocked(from: Vector3, to: Vector3): boolean
	local world = workspace:FindFirstChild("World")
	if not world then
		return false
	end
	worldParams.FilterDescendantsInstances = { world }
	return workspace:Raycast(from, to - from, worldParams) ~= nil
end

-- Red warning shown before an attack lands (stuns interrupt the attack).
local function telegraph(enemy, targetPos: Vector3, seconds: number, ranged: boolean, radiusMult: number?)
	local root = enemy.model.PrimaryPart
	local ground = Vector3.new(root.Position.X, enemy.floorY - (root.Size.Y / 2) + 0.35, root.Position.Z)
	local radius = Coord.studs(Config.ENEMY.MELEE_RANGE_PX) * 1.35 * (radiusMult or 1)
	local disc = Make.decor({
		Size = Vector3.new(0.2, radius * 0.5, radius * 0.5),
		CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2),
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(235, 70, 60),
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	}, workspace)
	TweenService:Create(disc, TweenInfo.new(seconds), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 0.35 }):Play()
	Debris:AddItem(disc, seconds + 0.05)
	if ranged then
		local from = root.Position + Vector3.new(0, 1.5, 0)
		local dist = (targetPos - from).Magnitude
		if dist > 1 then
			local line = Make.decor({
				Size = Vector3.new(0.15, 0.15, dist),
				CFrame = CFrame.lookAt(from, targetPos) * CFrame.new(0, 0, -dist / 2),
				Color = Color3.fromRGB(235, 70, 60),
				Material = Enum.Material.Neon,
				Transparency = 0.5,
			}, workspace)
			TweenService:Create(line, TweenInfo.new(seconds), { Transparency = 0.1 }):Play()
			Debris:AddItem(line, seconds + 0.05)
		end
	end
end

local function healthBar(model: Model, root: BasePart, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(model:GetAttribute("Boss") and 120 or 70, model:GetAttribute("Boss") and 11 or 8)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 80
	gui.Adornee = root
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Palette.UI.bg
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.UI.red
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = root
	return fill
end

local function spawnOne(areaId: string, areaInfo, id: string, kind: string, x: number, z: number, hp: number, damage: number, speed: number, extra)
	local color = Palette.hex(BASE_COLOR)
	local accent = Palette.hex(NATURE)
	local model = EnemyModels.build(kind, color, accent)
	model.Name = extra and extra.name or NAMES[kind] or kind
	local rect = areaInfo.rect
	local rootOffsetY = model.PrimaryPart.Position.Y
	if extra and extra.scale then
		model:ScaleTo(extra.scale)
		rootOffsetY *= extra.scale
	end
	x = math.clamp(x, rect.left + 6, rect.right - 6)
	z = math.clamp(z, rect.top + 6, rect.bottom - 6)
	model:PivotTo(CFrame.new(x, rect.y + rootOffsetY, z))
	local bounds = model:GetExtentsSize()
	model:SetAttribute("Boss", extra and extra.boss or nil)
	local fill = healthBar(model, model.PrimaryPart, bounds.Y + 1.5)
	local boss = extra and extra.boss
	local level = Progress.requiredLevel(areaId) + (boss and 2 or 0)
	Make.label(
		model.PrimaryPart,
		("%s  Lv %d"):format(model.Name, level),
		boss and Color3.fromRGB(255, 190, 90) or Palette.UI.ink,
		bounds.Y + 3,
		boss and 220 or 160,
		boss and 120 or 62
	)
	local flash = Instance.new("Highlight")
	flash.Name = "HitFlash"
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.3
	flash.OutlineTransparency = 1
	flash.Enabled = false
	flash.Parent = model
	model.Parent = enemiesFolder()

	State.enemies[id] = {
		flash = flash,
		windup = nil,
		id = id,
		area = areaId,
		model = model,
		kind = kind,
		role = ROLES[kind] or "bruiser",
		fill = fill,
		hp = hp,
		maxHp = hp,
		damage = damage,
		speed = speed * (SPEED_MULT[kind] or 1.15) * Config.STUDS_PER_PX, -- studs/s
		home = Vector2.new(x, z),
		floorY = rect.y + rootOffsetY,
		rect = rect,
		state = "idle", -- idle | chase | returning
		nextAttack = 0,
		stunUntil = 0,
		stunResistUntil = 0,
		rootUntil = 0,
		bleedUntil = 0,
		bleedDamage = 0,
		nextBleed = 0,
		boss = extra and extra.boss or false,
		bossKey = extra and extra.bossKey,
		noReward = extra and extra.noReward or false, -- scripted story fights pay nothing
		noLeash = extra and extra.noLeash or false,
	}
end

-- Port grind rule: ordinary enemies come back RESPAWN_SECONDS after dying, unless a player
-- stands near their spot. Quest guards (outdoor_respawns.EXCLUDED), shrine guards, bosses
-- and cave packs stay dead.
local NO_RESPAWN_AREAS = { shrine = true, ruins = true, cellar = true, caravan = true }
local function respawnable(areaId: string, site): boolean
	if not site or not site.group or NO_RESPAWN_AREAS[areaId] or Dungeons.AREAS[areaId] then
		return false
	end
	for _, excluded in Data.OutdoorRespawns.EXCLUDED do
		if site.group == excluded then
			return false
		end
	end
	return not site.group:find("shrine")
end

local function expire(areaId: string, now: number)
	local defeated = State.defeated[areaId]
	if not defeated then
		return
	end
	for id, diedAt in defeated do
		local site = State.sites[id]
		if type(diedAt) == "number" and site and respawnable(areaId, site) and now - diedAt >= Config.RESPAWN_SECONDS then
			local blocked = false
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(site.x, site.z)).Magnitude < Config.RESPAWN_CLEAR_STUDS then
					blocked = true
					break
				end
			end
			if not blocked then
				defeated[id] = nil
			end
		end
	end
end

-- Spawns every enemy of the area that is neither alive nor dead-and-waiting.
local function populate(areaId: string)
	expire(areaId, os.clock())
	local areaInfo = State.areas[areaId]
	local spec = Adventure.AREAS[areaId]
	local defeated = State.defeated[areaId] or {}
	State.defeated[areaId] = defeated
	local count = math.max(1, #Players:GetPlayers())
	local scale = difficultyScale()
	local danger = spec.danger
	local hp = math.round((32 + danger * 10) * (1 + 0.22 * (count - 1)) * scale)
	local damage = math.max(2, math.round((4 + danger) * scale))
	local speed = 64 + danger * 4
	local S = Config.WORLD_STUDS_PER_PX

	-- Territories from adventure.GROUPS.
	local groups = Adventure.GROUPS[areaId] or {}
	local bonusSites = areaId == "bridge" and 1 or #groups
	for slot, g in groups do
		local name, kind, gx, gy, number = g[1], g[2], g[3], g[4], g[5]
		if slot <= bonusSites then
			number += (count - 1) // bonusSites + ((slot - 1) < (count - 1) % bonusSites and 1 or 0)
		end
		gx, gy = Coord.scaleToArea(gx, gy, areaInfo.widthPx, areaInfo.heightPx)
		local cx, cz = areaInfo.origin.X + gx * S, areaInfo.origin.Z + gy * S
		for i, p in groupPositions(cx, cz, number) do
			local id = areaId .. "-" .. name .. "-" .. (i - 1)
			if not defeated[id] and not State.enemies[id] then
				State.sites[id] = { group = name, x = p[1], z = p[2] }
				spawnOne(areaId, areaInfo, id, kind, p[1], p[2], hp, damage, speed)
			end
		end
	end

	-- Wandering packs: extra spawns scaled to area size, scattered over the open ground.
	if #groups > 0 and danger > 0 then
		local rect = areaInfo.rect
		local w, h = rect.right - rect.left, rect.bottom - rect.top
		local packs = math.clamp(math.floor(w * h / WANDER_AREA), 0, WANDER_MAX)
		local rng = Random.new(#areaId * 7919 + math.floor(w))
		for n = 1, packs do
			local g = groups[(n - 1) % #groups + 1]
			local kind = g[2]
			local cx = rect.left + 30 + rng:NextNumber() * (w - 60)
			local cz = rect.top + 30 + rng:NextNumber() * (h - 60)
			local number = 2 + (n % 2) + ((count - 1) // 2)
			for i, p in groupPositions(cx, cz, number) do
				local id = areaId .. "-wander" .. n .. "-" .. (i - 1)
				if not defeated[id] and not State.enemies[id] then
					State.sites[id] = { group = "wander" .. n, x = p[1], z = p[2] }
					spawnOne(areaId, areaInfo, id, kind, p[1], p[2], hp, damage, speed)
				end
			end
		end
	end

	-- Cave chambers use fixed packs: PACKS[area] = { {x, y, {kinds}} } in area px.
	for packIndex, pack in Dungeons.PACKS[areaId] or {} do
		for i, kind in pack[3] do
			local id = areaId .. "-pack" .. packIndex .. "-" .. (i - 1)
			if not defeated[id] and not State.enemies[id] then
				local x = areaInfo.origin.X + (pack[1] + (i - 2) * 34) * S
				local z = areaInfo.origin.Z + (pack[2] + ((i % 2) * 2 - 1) * 20) * S
				spawnOne(areaId, areaInfo, id, kind, x, z, hp, damage, speed)
			end
		end
	end
end

-- Wakes an area's enemies.
function EnemyService.activate(areaId: string)
	if State.awake[areaId] then
		return
	end
	State.awake[areaId] = true
	populate(areaId)
end

-- Bosses are one-off encounters started by quests (defeated state is permanent).
-- spec: { key, name, kind, hp, damage, speed, scale, xPx, yPx }
function EnemyService.spawnBoss(areaId: string, spec): boolean
	local areaInfo = State.areas[areaId]
	local id = areaId .. "-boss-" .. spec.key
	State.defeated[areaId] = State.defeated[areaId] or {}
	if State.enemies[id] or State.defeated[areaId][id] then
		return false
	end
	local S = Config.WORLD_STUDS_PER_PX
	local count = math.max(1, #Players:GetPlayers())
	local hp = math.round(spec.hp * (1 + 0.65 * (count - 1)) * difficultyScale())
	spawnOne(areaId, areaInfo, id, spec.kind, areaInfo.origin.X + spec.xPx * S, areaInfo.origin.Z + spec.yPx * S, hp,
		math.round(spec.damage * difficultyScale()), spec.speed, { name = spec.name, scale = spec.scale, boss = true, bossKey = spec.key })
	return true
end

-- Fixed dungeon encounter enemy (tower waves, cave troll). id must be unique per attempt.
-- opts: { boss, name, scale, bossKey }. Stats follow dungeons.py enemy(): normal hp 36+7*danger
-- (+16%/extra player), boss hp 360 (+55%/extra player), damage 4+danger / 10, speed 68(+2*danger).
function EnemyService.spawnFixed(areaId: string, id: string, kind: string, xPx: number, yPx: number, opts)
	local areaInfo = State.areas[areaId]
	if not areaInfo or State.enemies[id] then
		return false
	end
	opts = opts or {}
	local S = Config.WORLD_STUDS_PER_PX
	local count = math.max(1, #Players:GetPlayers())
	local danger = Adventure.AREAS[areaId].danger
	local hp, damage, speed
	if opts.boss then
		hp = (opts.hp or 360) * (1 + 0.55 * (count - 1))
		damage = opts.damage or 10
		speed = opts.speed or 68
	else
		hp = (opts.hp or (36 + danger * 7)) * (1 + 0.16 * (count - 1))
		damage = opts.damage or (4 + danger)
		speed = opts.speed or (68 + danger * 2)
	end
	local gx, gy = Coord.scaleToArea(xPx, yPx, areaInfo.widthPx, areaInfo.heightPx)
	State.defeated[areaId] = State.defeated[areaId] or {}
	spawnOne(areaId, areaInfo, id, kind, areaInfo.origin.X + gx * S, areaInfo.origin.Z + gy * S, math.round(hp * difficultyScale()),
		math.max(2, math.round(damage * difficultyScale())), speed, { name = opts.name, scale = opts.scale, boss = opts.boss, bossKey = opts.bossKey, noReward = opts.noReward, noLeash = opts.noLeash })
	return true
end

-- Removes a spawned enemy without death rewards (encounter reset).
function EnemyService.remove(id: string)
	local e = State.enemies[id]
	if e then
		e.dead = true
		e.model:Destroy()
		State.enemies[id] = nil
	end
end

-- True once every enemy of a named territory (adventure.GROUPS / RegionContent.GROUPS) is dead.
function EnemyService.groupCleared(areaId: string, group: string): boolean
	local defeated = State.defeated[areaId] or {}
	local sites = Adventure.GROUPS[areaId] or Data.RegionContent.GROUPS[areaId] or {}
	for _, g in sites do
		if g[1] == group then
			local n = 0
			for id in defeated do
				if id:sub(1, #areaId + #group + 2) == areaId .. "-" .. group .. "-" then
					n += 1
				end
			end
			return n >= g[5]
		end
	end
	return false
end

function EnemyService.deactivate(areaId: string)
	State.awake[areaId] = nil
	for id, e in State.enemies do
		if e.area == areaId then
			e.model:Destroy()
			State.enemies[id] = nil
		end
	end
end

-- Distance (studs) from a point to an area's footprint; huge if on another layer.
local function distanceToArea(info, position: Vector3): number
	local r = info.rect
	if math.abs(position.Y - r.y) > Config.FLOOR_HEIGHT * 1.5 and info.kind ~= "surface" then
		return math.huge
	end
	if info.kind == "surface" and position.Y < -10 then
		return math.huge -- underground player does not wake surface areas overhead
	end
	local dx = math.max(r.left - position.X, 0, position.X - r.right)
	local dz = math.max(r.top - position.Z, 0, position.Z - r.bottom)
	return math.sqrt(dx * dx + dz * dz)
end

-- Wake areas near players, put far-away ones back to sleep (keeps server cost flat).
local function refreshActive()
	local positions = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(positions, root.Position)
		end
	end
	for id, info in State.areas do
		local nearest = math.huge
		for _, position in positions do
			nearest = math.min(nearest, distanceToArea(info, position))
		end
		if not State.awake[id] and nearest <= Config.ACTIVE_STUDS then
			EnemyService.activate(id)
		elseif State.awake[id] and nearest > Config.ACTIVE_STUDS * 1.3 then
			EnemyService.deactivate(id)
		elseif State.awake[id] then
			populate(id) -- brings back enemies whose respawn timer ran out
		end
	end
end

local function livePlayers()
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and not player:GetAttribute("Invisible") then
			table.insert(list, { player = player, humanoid = humanoid, root = root })
		end
	end
	return list
end

-- opts: { crit = bool, dot = bool }. Damage-over-time and companion hits never build combo/charge.
function EnemyService.damage(enemy, amount: number, attacker: Player?, opts)
	if enemy.dead then
		return
	end
	enemy.hp -= amount
	enemy.fill.Size = UDim2.fromScale(math.clamp(enemy.hp / enemy.maxHp, 0, 1), 1)
	enemy.state = "chase" -- being hit always draws the enemy in
	enemy.aggroPlayer = attacker
	local crit = opts ~= nil and opts.crit == true
	local combo = 0
	if attacker and not (opts and opts.dot) then
		combo = Stats.registerHit(attacker, os.clock(), crit)
		local leech = Progress.bonus(attacker).leech
		if leech > 0 then
			local hum = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
				hum.Health = math.min(hum.MaxHealth, hum.Health + math.max(1, amount * leech))
			end
		end
	end
	Remotes.get("EnemyHit"):FireAllClients(enemy.model.PrimaryPart.Position + Vector3.new(0, 4, 0), amount, crit, attacker and attacker.UserId or 0, combo)
	-- Hit flash + small knockback (not on bosses).
	if enemy.flash and enemy.flash.Parent then
		enemy.flash.Enabled = true
		task.delay(0.09, function()
			if enemy.flash and enemy.flash.Parent then
				enemy.flash.Enabled = false
			end
		end)
	end
	local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	if attackerRoot and not enemy.boss and enemy.hp > 0 then
		local from = enemy.model.PrimaryPart.Position
		local away = Vector3.new(from.X - attackerRoot.Position.X, 0, from.Z - attackerRoot.Position.Z)
		if away.Magnitude > 0.1 then
			local target = from + away.Unit * 1.6
			target = Vector3.new(
				math.clamp(target.X, enemy.rect.left + 3, enemy.rect.right - 3),
				from.Y,
				math.clamp(target.Z, enemy.rect.top + 3, enemy.rect.bottom - 3)
			)
			if not worldBlocked(from + Vector3.new(0, 2, 0), target + Vector3.new(0, 2, 0)) then
				enemy.model:PivotTo(CFrame.new(target) * (enemy.model:GetPivot() - enemy.model:GetPivot().Position))
			end
		end
	end
	if enemy.hp > 0 then
		return
	end
	enemy.dead = true
	State.defeated[enemy.area][enemy.id] = os.clock() -- time of death (respawn timer)
	State.enemies[enemy.id] = nil
	for _, part in enemy.model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(enemy.model, 0.6)
	EnemyService.reward(enemy, attacker)
	if EnemyService.onKill then
		EnemyService.onKill(enemy, attacker)
	end
end

-- XP + runes to the killer and every party member close to the kill.
local rewardRng = Random.new()
function EnemyService.reward(enemy, attacker: Player?)
	if enemy.noReward then
		return
	end
	local at = enemy.model.PrimaryPart and enemy.model.PrimaryPart.Position or Vector3.zero
	local share = Config.XP_SHARE_STUDS
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local near = root and humanoid and humanoid.Health > 0 and (root.Position - at).Magnitude <= share
		if near or player == attacker then
			local xp, runes = Progress.rewardKill(player, enemy.area, rewardRng)
			Remotes.get("Reward"):FireClient(player, math.round(xp), runes, at + Vector3.new(0, 5, 0))
			Loot.roll(player, enemy, at)
		end
	end
end

-- Crowd control (stun is shorter on bosses and cannot be chained; roots and bleeds refresh).
function EnemyService.stun(enemy, now: number)
	if enemy.stunResistUntil > now then
		return
	end
	local duration = enemy.boss and 0.25 or 0.6
	enemy.stunUntil = now + duration
	enemy.stunResistUntil = now + 1.8
end

function EnemyService.root(enemy, now: number, duration: number)
	enemy.rootUntil = math.max(enemy.rootUntil, now + (enemy.boss and duration * 0.4 or duration))
end

function EnemyService.bleed(enemy, owner: Player, damage: number, now: number)
	enemy.bleedUntil = now + 5
	enemy.bleedDamage = math.max(1, damage)
	enemy.bleedOwner = owner
	enemy.nextBleed = now + 1
end

-- Anything alive that enemies may target: players and Druid companions use EnemyService.damage.
function EnemyService.nearestTo(position: Vector3, maxStuds: number)
	local best, bestD = nil, maxStuds
	for _, e in State.enemies do
		local d = ((e.model.PrimaryPart.Position - position) * Vector3.new(1, 0, 1)).Magnitude
		if d <= bestD and math.abs(e.model.PrimaryPart.Position.Y - position.Y) < 14 then
			best, bestD = e, d
		end
	end
	return best
end

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	local p = Make.decor({
		Size = Vector3.new(0.25, 0.25, dist),
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2),
		Color = color,
		Material = Enum.Material.Neon,
	}, workspace)
	Debris:AddItem(p, 0.15)
end

local function step(dt: number)
	local now = os.clock()
	local targets = livePlayers()
	local aggro = Coord.studs(Config.ENEMY.AGGRO_PX)
	local leash = Coord.studs(Config.ENEMY.LEASH_PX)
	local melee = Coord.studs(Config.ENEMY.MELEE_RANGE_PX)
	local ranged = Coord.studs(Config.ENEMY.RANGED_RANGE_PX)
	for _, e in State.enemies do
		local rootPart = e.model.PrimaryPart
		local pos = rootPart.Position
		local here = Vector2.new(pos.X, pos.Z)

		-- Bleeding.
		if e.bleedUntil > now and now >= e.nextBleed then
			e.nextBleed = now + 1
			EnemyService.damage(e, e.bleedDamage, e.bleedOwner, { dot = true })
			if e.dead then
				continue
			end
		end
		local stunned = e.stunUntil > now

		-- Nearest player on the same floor (a player in the cave does not pull surface enemies).
		-- A taunting player within twice the aggro radius draws every enemy.
		local nearest, nearestD = nil, math.huge
		local tauntBest, tauntD = nil, aggro * 2
		for _, t in targets do
			local tp = t.root.Position
			if math.abs(tp.Y - pos.Y) < 14 then
				local d = (Vector2.new(tp.X, tp.Z) - here).Magnitude
				if d < nearestD then
					nearest, nearestD = t, d
				end
				if Stats.get(t.player).tauntUntil > now and d < tauntD then
					tauntBest, tauntD = t, d
				end
			end
		end
		if tauntBest then
			nearest, nearestD = tauntBest, tauntD
		end

		local fromHome = (here - e.home).Magnitude
		if e.state == "idle" and nearest and nearestD <= aggro then
			e.state = "chase"
		elseif e.state == "chase" and (not nearest or (fromHome > leash and not e.noLeash)) then
			e.state = "returning"
		elseif e.state == "returning" and fromHome < 1 then
			e.state = "idle"
			e.hp = e.maxHp
			e.fill.Size = UDim2.fromScale(1, 1)
		end

		local goal, stop = nil, 0
		if e.state == "chase" and nearest then
			local tp = nearest.root.Position
			goal = Vector2.new(tp.X, tp.Z)
			stop = ((e.role == "ranged") and ranged or melee) * 0.8
		elseif e.state == "returning" then
			goal = e.home
		end

		if stunned and e.windup then
			e.windup = nil -- stuns interrupt attacks
		end
		if goal and not stunned and e.rootUntil <= now and not e.windup then
			local delta = goal - here
			local dist = delta.Magnitude
			if dist > stop then
				local move = math.min(dist - stop, e.speed * dt)
				local step2 = delta / dist * move
				local eye = Vector3.new(here.X, e.floorY + 2, here.Y)
				local function free(v: Vector2): boolean
					local ahead = v.Unit * (v.Magnitude + 2.5)
					return not worldBlocked(eye, eye + Vector3.new(ahead.X, 0, ahead.Y))
				end
				if free(step2) then
					here += step2
				else
					-- Steer around the obstacle: try turning 45/90/135 degrees, preferring the side that worked last.
					local sign = e.avoidSign or 1
					local moved = false
					for _, deg in { 45, 90, 135 } do
						for _, side in { sign, -sign } do
							local a = math.rad(deg * side)
							local rotated = Vector2.new(step2.X * math.cos(a) - step2.Y * math.sin(a), step2.X * math.sin(a) + step2.Y * math.cos(a))
							if free(rotated) then
								here += rotated
								e.avoidSign = side
								moved = true
								break
							end
						end
						if moved then
							break
						end
					end
				end
				e.moving = true
				here = Vector2.new(
					math.clamp(here.X, e.rect.left + 3, e.rect.right - 3),
					math.clamp(here.Y, e.rect.top + 3, e.rect.bottom - 3)
				)
			end
			local bob = e.moving and math.abs(math.sin(now * 9 + #e.id)) * 0.35 or 0
			e.moving = false
			local newPos = Vector3.new(here.X, e.floorY + bob, here.Y)
			local lookAt = Vector3.new(goal.X, e.floorY, goal.Y)
			if (lookAt - newPos).Magnitude > 0.1 then
				e.model:PivotTo(CFrame.lookAt(newPos, lookAt))
			else
				e.model:PivotTo(CFrame.new(newPos) * (e.model:GetPivot() - e.model:GetPivot().Position))
			end
		end

		-- Attacks: a short red warning (telegraph), then the hit lands if the target is still close.
		if e.windup then
			if now >= e.windup.at then
				local w = e.windup
				e.windup = nil
				if w.slam then
					local radius = Coord.studs(Config.ENEMY.MELEE_RANGE_PX) * 1.35 * 1.8
					for _, t in targets do
						local d = (Vector2.new(t.root.Position.X, t.root.Position.Z) - Vector2.new(rootPart.Position.X, rootPart.Position.Z)).Magnitude
						if d <= radius and math.abs(t.root.Position.Y - rootPart.Position.Y) < 14 then
							Stats.hurt(t.player, t.humanoid, math.round(e.damage * 1.5), now)
						end
					end
					continue
				end
				for _, t in targets do
					if t.player == w.player then
						local d = (Vector2.new(t.root.Position.X, t.root.Position.Z) - Vector2.new(rootPart.Position.X, rootPart.Position.Z)).Magnitude
						if d <= w.range * 1.35 and math.abs(t.root.Position.Y - rootPart.Position.Y) < 14 then
							if w.ranged then
								tracer(rootPart.Position + Vector3.new(0, 2, 0), t.root.Position, Palette.hex(NATURE))
							end
							Stats.hurt(t.player, t.humanoid, e.damage, now)
						end
					end
				end
			end
		elseif e.state == "chase" and nearest and now >= e.nextAttack and not stunned then
			local isRanged = e.role == "ranged"
			local range = isRanged and ranged or melee
			if nearestD <= range then
				local slam = e.boss and not isRanged and math.random() < 0.4 -- bosses: big ground slam you must run out of
				local windup = slam and 0.9 or ((e.boss or isRanged) and 0.55 or 0.4)
				e.nextAttack = now + (isRanged and Config.ENEMY.RANGED_INTERVAL or Config.ENEMY.MELEE_INTERVAL) + windup
				e.windup = { at = now + windup, player = nearest.player, range = range, ranged = isRanged, slam = slam }
				telegraph(e, nearest.root.Position, windup, isRanged, slam and 1.8 or 1)
			end
		end
	end
end

function EnemyService.start()
	task.spawn(function()
		while true do
			refreshActive()
			task.wait(1)
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= Config.ENEMY.TICK then
			step(accumulator)
			accumulator = 0
		end
	end)
end

return EnemyService
