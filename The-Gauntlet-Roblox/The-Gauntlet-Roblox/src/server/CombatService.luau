--!nonstrict
-- All six abilities of a hero (slots 1-6 = 2 Lights, 2 Specials, 2 Ultimates), ported
-- from game.py `_cast_ability`: damage = base * power where
-- base = (hero damage * level bonus + weapon damage) * active damage boost.
-- Mana: 100 max, +6/s at peace, +2/s in combat; Lights cost 0.
-- Simplified vs 2D: hits are instant (no projectile travel), no line-of-sight checks,
-- skill-tree/rune modifiers not applied yet, Druid companions are timed (Companions).
-- TODO(port): hero_skills.py / skill_casts.py upgrades, tactical_rules.py, equipment effects.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local Fallen = require(script.Parent.Fallen)
local EnemyService = require(script.Parent.EnemyService)
local Companions = require(script.Parent.Companions)
local Skills = require(script.Parent.Skills)

local CombatService = {}

local SAME_FLOOR = 14 -- studs of height difference that still counts as the same floor
local OFFENSIVE = {
	damage = true, stun = true, bleed = true, dash_strike = true, pierce = true, area = true, target_area = true,
}

-- -------------------------------------------------------------- visuals

local LEGACY_FX = false -- client/AbilityFx.luau draws every ability now

local function beam(from: Vector3, to: Vector3, color: Color3)
	if not LEGACY_FX then
		return
	end
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	-- Hits stay instant (server authoritative); the visual is a fast orb with a fading trail.
	local flight = math.clamp(dist / 140, 0.05, 0.22)
	local orb = Make.decor({
		Size = Vector3.new(1, 1, 1),
		Shape = Enum.PartType.Ball,
		Position = from,
		Color = color,
		Material = Enum.Material.Neon,
	}, workspace)
	TweenService:Create(orb, TweenInfo.new(flight, Enum.EasingStyle.Linear), { Position = to }):Play()
	Debris:AddItem(orb, flight + 0.05)
	local trail = Make.decor({
		Size = Vector3.new(0.25, 0.25, dist),
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	}, workspace)
	TweenService:Create(trail, TweenInfo.new(flight + 0.12), { Transparency = 1 }):Play()
	Debris:AddItem(trail, flight + 0.15)
end

local function ring(center: Vector3, radius: number, color: Color3, seconds: number?)
	if not LEGACY_FX then
		return
	end
	local p = Make.decor({
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, center.Y - 2.6, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	}, workspace)
	Debris:AddItem(p, seconds or 0.25)
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

-- ---------------------------------------------------------------- helpers

local function alive(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

local function flat(v: Vector3): Vector3
	return v * Vector3.new(1, 0, 1)
end

-- Enemies within `studs` of `pos` on the same floor, nearest first.
local function enemiesNear(pos: Vector3, studs: number)
	local list = {}
	for _, enemy in State.enemies do
		local ep = enemy.model.PrimaryPart.Position
		if math.abs(ep.Y - pos.Y) < SAME_FLOOR then
			local d = flat(ep - pos).Magnitude
			if d <= studs then
				table.insert(list, { enemy = enemy, distance = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)
	return list
end

local function baseDamage(player: Player, hero: string, now: number): number
	local base = Data.Heroes[hero].damage * Progress.damageMultiplier(player) + Progress.weaponDamage(player)
	return math.round(base * Stats.damageFactor(player, now) * Stats.comboFactor(player, now))
end

local function setInvisible(player: Player, on: boolean)
	player:SetAttribute("Invisible", on or nil)
	local character = player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = on and 0.7 or 0
			end
		end
	end
end

local function aliveParty()
	local list = {}
	for _, member in Players:GetPlayers() do
		local humanoid, root = alive(member)
		if humanoid then
			table.insert(list, { player = member, humanoid = humanoid, root = root })
		end
	end
	return list
end

local function heal(target, amount: number)
	local humanoid = target.humanoid
	local gained = math.min(humanoid.MaxHealth - humanoid.Health, amount)
	if gained > 0 then
		humanoid.Health += gained
		Remotes.get("Notify"):FireClient(target.player, ("+%d health"):format(math.round(gained)))
	end
	return gained
end

local function raycastLimit(from: Vector3, direction: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace:FindFirstChild("Enemies") }
	local hit = workspace:Raycast(from, direction, params)
	if hit then
		return hit.Position - direction.Unit * 3
	end
	return from + direction
end

-- ----------------------------------------------------------------- casts
-- Each effect gets ctx and returns true when the cast happened (cost + cooldown spent).

local EFFECTS = {}

local critRng = Random.new()
local function strike(ctx, enemy, amount: number)
	local crit = critRng:NextNumber() < Config.CRIT_CHANCE + Progress.bonus(ctx.player).crit
	if crit then
		amount *= Config.CRIT_MULT
	end
	EnemyService.damage(enemy, math.round(amount), ctx.player, { crit = crit })
end

local function hit(ctx, enemy, power: number?)
	strike(ctx, enemy, ctx.base * (power or ctx.ability.power))
end

local function nearestTarget(ctx)
	local list = enemiesNear(ctx.pos, ctx.range)
	return list[1] and list[1].enemy, list
end

local function needEnemy(ctx)
	if ctx.ability.attackType ~= "light" then
		notify(ctx.player, "No enemy is in range.")
	end
	return false
end

function EFFECTS.damage(ctx)
	local ability = ctx.ability
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	local tpos = target.model.PrimaryPart.Position
	ctx.fx.t = { tpos }
	beam(ctx.pos + Vector3.new(0, 1, 0), tpos + Vector3.new(0, 2, 0), ctx.color)
	hit(ctx, target)
	if ability.splashRadius then -- Radiant Flask / Briar Bolt: splash around the target
		local radius = Coord.studs(ability.splashRadius)
		ctx.fx.r = radius
		ring(tpos, radius, ctx.color)
		for _, other in enemiesNear(tpos, radius) do
			if other.enemy ~= target then
				hit(ctx, other.enemy)
			end
		end
		if ability.rootDuration then
			for _, other in enemiesNear(tpos, radius) do
				EnemyService.root(other.enemy, ctx.now, ability.rootDuration)
			end
		end
	end
	if ability.chainTargets then -- Wizard Arc Bolt
		local chained = { [target] = true }
		local last = target
		for _ = 1, ability.chainTargets do
			local best, bestD
			for _, other in State.enemies do
				if not chained[other] then
					local d = flat(other.model.PrimaryPart.Position - last.model.PrimaryPart.Position).Magnitude
					if d <= Coord.studs(ability.chainRange) and (not bestD or d < bestD) then
						best, bestD = other, d
					end
				end
			end
			if not best then
				break
			end
			chained[best] = true
			ctx.fx.chain = ctx.fx.chain or {}
			table.insert(ctx.fx.chain, best.model.PrimaryPart.Position)
			beam(last.model.PrimaryPart.Position + Vector3.new(0, 2, 0), best.model.PrimaryPart.Position + Vector3.new(0, 2, 0), ctx.color)
			hit(ctx, best, ability.power * ability.chainDecay)
			last = best
		end
	end
	return true
end

function EFFECTS.stun(ctx)
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	ctx.fx.t = { target.model.PrimaryPart.Position }
	beam(ctx.pos + Vector3.new(0, 1, 0), target.model.PrimaryPart.Position + Vector3.new(0, 2, 0), ctx.color)
	EnemyService.stun(target, ctx.now)
	hit(ctx, target)
	return true
end

function EFFECTS.bleed(ctx)
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	ctx.fx.t = { target.model.PrimaryPart.Position }
	beam(ctx.pos + Vector3.new(0, 1, 0), target.model.PrimaryPart.Position + Vector3.new(0, 2, 0), ctx.color)
	EnemyService.bleed(target, ctx.player, math.round(ctx.base * 0.45), ctx.now)
	hit(ctx, target)
	return true
end

function EFFECTS.dash_strike(ctx)
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	local tpos = target.model.PrimaryPart.Position
	local away = flat(ctx.pos - tpos)
	local dir = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
	local flatTarget = Vector3.new(tpos.X, ctx.pos.Y, tpos.Z)
	ctx.fx.from, ctx.fx.to, ctx.fx.t = ctx.pos, flatTarget + dir * 3.5, { tpos }
	ctx.character:PivotTo(CFrame.lookAt(flatTarget + dir * 3.5, flatTarget))
	hit(ctx, target)
	return true
end

function EFFECTS.pierce(ctx)
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	local tpos = target.model.PrimaryPart.Position
	local dir = flat(tpos - ctx.pos).Unit
	beam(ctx.pos + Vector3.new(0, 1, 0), ctx.pos + dir * ctx.range + Vector3.new(0, 1, 0), ctx.color)
	ctx.fx.dir, ctx.fx.range, ctx.fx.t = dir, ctx.range, {}
	for _, entry in enemiesNear(ctx.pos, ctx.range) do
		local rel = flat(entry.enemy.model.PrimaryPart.Position - ctx.pos)
		local along = rel:Dot(dir)
		if along > 0 and (rel - dir * along).Magnitude <= 4 then
			table.insert(ctx.fx.t, entry.enemy.model.PrimaryPart.Position)
			hit(ctx, entry.enemy)
		end
	end
	return true
end

function EFFECTS.area(ctx)
	local list = enemiesNear(ctx.pos, ctx.range)
	if #list == 0 then
		return needEnemy(ctx)
	end
	ring(ctx.pos, ctx.range, ctx.color)
	ctx.fx.r, ctx.fx.t = ctx.range, {}
	local bleedAfter = ctx.ability.id == "death_bloom"
	for _, entry in list do
		table.insert(ctx.fx.t, entry.enemy.model.PrimaryPart.Position)
		hit(ctx, entry.enemy)
		if bleedAfter then
			EnemyService.bleed(entry.enemy, ctx.player, math.round(ctx.base * 0.2), ctx.now)
		end
	end
	return true
end

-- Rain of Arrows: aim at the nearest foe, impact after a short delay.
function EFFECTS.target_area(ctx)
	local ability = ctx.ability
	local target = nearestTarget(ctx)
	if not target then
		return needEnemy(ctx)
	end
	local center = target.model.PrimaryPart.Position
	local radius = Coord.studs(ability.blastRadius)
	local damage = math.round(ctx.base * ability.power)
	ctx.fx.c, ctx.fx.r, ctx.fx.delay, ctx.fx.t = center, radius, ability.impactDelay or 0.6, {}
	for _, entry in enemiesNear(center, radius) do
		table.insert(ctx.fx.t, entry.enemy.model.PrimaryPart.Position)
	end
	ring(center, radius, ctx.color, (ability.impactDelay or 0.6) + 0.3)
	task.delay(ability.impactDelay or 0.6, function()
		ring(center, radius, Color3.new(1, 1, 1), 0.2)
		for _, entry in enemiesNear(center, radius) do
			strike(ctx, entry.enemy, damage)
		end
	end)
	return true
end

local function applyWard(stats, ctx)
	if stats.wardUntil <= ctx.now or ctx.ability.power <= stats.wardFactor then
		stats.wardUntil, stats.wardFactor = ctx.now + (ctx.ability.duration or 8), ctx.ability.power
	end
end

function EFFECTS.self_ward(ctx)
	ctx.fx.allies, ctx.fx.duration = { ctx.player.UserId }, ctx.ability.duration or 8
	applyWard(Stats.get(ctx.player), ctx)
	ring(ctx.pos, 5, ctx.color, 0.6)
	return true
end

function EFFECTS.team_ward(ctx)
	local reach = ctx.ability.range > 0 and Coord.studs(ctx.ability.range) or math.huge
	ctx.fx.allies, ctx.fx.duration, ctx.fx.r = {}, ctx.ability.duration or 8, reach < math.huge and reach or 24
	for _, member in aliveParty() do
		if (member.root.Position - ctx.pos).Magnitude <= reach then
			table.insert(ctx.fx.allies, member.player.UserId)
			applyWard(Stats.get(member.player), ctx)
			ring(member.root.Position, 5, ctx.color, 0.6)
		end
	end
	return true
end

function EFFECTS.self_damage(ctx)
	local s = Stats.get(ctx.player)
	ctx.fx.allies, ctx.fx.duration = { ctx.player.UserId }, 8
	s.boostUntil, s.boost = ctx.now + 8, ctx.ability.power
	ring(ctx.pos, 5, ctx.color, 0.6)
	return true
end

function EFFECTS.team_damage(ctx)
	ctx.fx.allies, ctx.fx.duration = {}, 8
	for _, member in aliveParty() do
		table.insert(ctx.fx.allies, member.player.UserId)
		local s = Stats.get(member.player)
		s.boostUntil, s.boost = ctx.now + 8, ctx.ability.power
		ring(member.root.Position, 5, ctx.color, 0.6)
	end
	return true
end

function EFFECTS.team_heal(ctx)
	local ability = ctx.ability
	local reach = ability.range > 0 and Coord.studs(ability.range) or math.huge
	local targets = {}
	for _, member in aliveParty() do
		if member.humanoid.Health < member.humanoid.MaxHealth and (member.root.Position - ctx.pos).Magnitude <= reach then
			table.insert(targets, member)
		end
	end
	if #targets == 0 then
		notify(ctx.player, "No injured ally is in range.")
		return false
	end
	if ability.id == "healing_ray" or ability.id == "major_mend" then -- most injured ally only
		table.sort(targets, function(a, b)
			return a.humanoid.Health / a.humanoid.MaxHealth < b.humanoid.Health / b.humanoid.MaxHealth
		end)
		targets = { targets[1] }
	end
	ctx.fx.allies, ctx.fx.r = {}, reach < math.huge and reach or 24
	for _, member in targets do
		table.insert(ctx.fx.allies, member.player.UserId)
		heal(member, ability.power)
		ring(member.root.Position, 4, ctx.color, 0.6)
	end
	return true
end

function EFFECTS.revive(ctx)
	local reach = Coord.studs(ctx.ability.range)
	local best, bestD
	for player, record in State.fallen do
		local d = flat(record.pos - ctx.pos).Magnitude
		if d <= reach and (not bestD or d < bestD) then
			best, bestD = player, d
		end
	end
	if not best then
		notify(ctx.player, "No downed ally is close enough.")
		return false
	end
	ctx.fx.fallen = { State.fallen[best].pos }
	Fallen.revive(best, State.fallen[best].pos, ctx.ability.reviveFraction or 0.45)
	return true
end

function EFFECTS.team_revive(ctx)
	local list = {}
	for player, record in State.fallen do
		table.insert(list, { player, record.pos })
	end
	if #list == 0 then
		notify(ctx.player, "No fallen allies need reviving.")
		return false
	end
	ctx.fx.fallen = {}
	for _, entry in list do
		table.insert(ctx.fx.fallen, entry[2])
		Fallen.revive(entry[1], entry[2], 0.4)
	end
	return true
end

function EFFECTS.speed(ctx)
	local s = Stats.get(ctx.player)
	ctx.fx.allies, ctx.fx.duration = { ctx.player.UserId }, ctx.ability.duration or 6
	s.speedUntil, s.speedFactor = ctx.now + (ctx.ability.duration or 6), ctx.ability.power
	return true
end

function EFFECTS.team_speed(ctx)
	ctx.fx.allies, ctx.fx.duration = {}, ctx.ability.duration or 6
	for _, member in aliveParty() do
		table.insert(ctx.fx.allies, member.player.UserId)
		local s = Stats.get(member.player)
		s.speedUntil, s.speedFactor = ctx.now + (ctx.ability.duration or 6), ctx.ability.power
	end
	return true
end

function EFFECTS.invisible(ctx)
	Stats.get(ctx.player).invisibleUntil = ctx.now + 5
	setInvisible(ctx.player, true)
	return true
end

function EFFECTS.taunt(ctx)
	Stats.get(ctx.player).tauntUntil = ctx.now + 7
	ctx.fx.r = 12
	ring(ctx.pos, 8, ctx.color, 0.7)
	return true
end

function EFFECTS.summon(ctx)
	-- The summon hits for (light power of your first Light) x power of your light damage.
	local light
	for _, entry in Data.Abilities.sets[ctx.hero] do
		if entry.attackType == "light" then
			light = entry
			break
		end
	end
	local damage = math.max(1, math.round(math.round(ctx.base * light.power) * ctx.ability.power))
	return Companions.summon(ctx.player, ctx.ability.id, ctx.slot, damage)
end

function EFFECTS.blink(ctx)
	local list = enemiesNear(ctx.pos, 40)
	local dir
	if list[1] then
		dir = flat(ctx.pos - list[1].enemy.model.PrimaryPart.Position)
	end
	if not dir or dir.Magnitude < 0.1 then
		dir = flat(ctx.root.CFrame.LookVector)
	end
	local target = raycastLimit(ctx.pos, dir.Unit * ctx.range, ctx.character)
	ring(ctx.pos, 3, ctx.color, 0.3)
	ctx.fx.from, ctx.fx.to = ctx.pos, target
	ctx.character:PivotTo(CFrame.new(target) * (ctx.root.CFrame - ctx.root.CFrame.Position))
	ring(target, 3, ctx.color, 0.3)
	return true
end

-- ------------------------------------------------------------------ cast

function CombatService.cast(player: Player, slot)
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 6 then
		return
	end
	local humanoid, root = alive(player)
	if not humanoid then
		return
	end
	local hero = State.heroes[player]
	local base = Data.Abilities.sets[hero][slot]
	if not base or not EFFECTS[base.kind] then
		return
	end
	if not Skills.slotUnlocked(player, hero, slot) then
		notify(player, base.name .. " is locked. Train it in the skill tree (K).")
		return
	end
	local ability = Skills.ability(player, hero, slot)
	local effect = EFFECTS[ability.kind]
	local now = os.clock()
	local cooldowns = State.cooldowns[player]
	if (cooldowns[slot] or 0) > now then
		return
	end
	if ability.kind == "summon" and Companions.alive(player, ability.id) then
		notify(player, ability.name .. " is still alive.")
		return
	end
	local stats = Stats.get(player)
	if stats.mana < ability.manaCost then
		notify(player, ("%s needs %d mana."):format(ability.name, ability.manaCost))
		return
	end

	local ctx = {
		player = player,
		character = player.Character,
		root = root,
		pos = root.Position,
		hero = hero,
		slot = slot,
		ability = ability,
		range = Coord.studs(ability.range),
		color = Palette.hex(Data.Heroes[hero].color),
		now = now,
		base = baseDamage(player, hero, now),
		fx = {},
	}
	if not effect(ctx) then
		return
	end
	do -- tell every client what to draw
		local fx = ctx.fx
		fx.caster, fx.id, fx.hero, fx.color, fx.o = player.UserId, ability.id, hero, ctx.color, ctx.pos
		Remotes.get("AbilityFx"):FireAllClients(fx)
	end

	stats.mana -= ability.manaCost
	if ability.kind ~= "summon" then
		cooldowns[slot] = now + ability.cooldown
	end
	if OFFENSIVE[ability.kind] then
		stats.lastCombat = now
		if stats.invisibleUntil > now then -- offensive casts break concealment
			stats.invisibleUntil = 0
			setInvisible(player, false)
		end
	end
	if ability.attackType ~= "light" then
		notify(player, ability.name .. "!")
	end
end

-- ----------------------------------------------------- mana + hotbar state

local function vitalsLoop()
	local last = os.clock()
	while true do
		task.wait(0.2)
		local now = os.clock()
		local dt = now - last
		last = now
		local inCombat = false
		for _, enemy in State.enemies do
			if enemy.state == "chase" then
				inCombat = true
				break
			end
		end
		for _, player in Players:GetPlayers() do
			local hero = State.heroes[player]
			if hero and State.cooldowns[player] then
				local stats = Stats.get(player)
				local rate = (inCombat or now - stats.lastCombat < 5) and 2 or 6
				stats.mana = math.min(stats.maxMana, stats.mana + rate * dt)
				if stats.invisibleUntil > 0 and stats.invisibleUntil <= now then
					stats.invisibleUntil = 0
					setInvisible(player, false)
				end
				local cooldowns, summoned = {}, {}
				for slot = 1, 6 do
					cooldowns[slot] = math.max(0, (State.cooldowns[player][slot] or 0) - now)
					local ability = Data.Abilities.sets[hero][slot]
					summoned[slot] = ability.kind == "summon" and Companions.alive(player, ability.id) or false
				end
				Remotes.get("Vitals"):FireClient(player, stats.mana, stats.maxMana, cooldowns, summoned)
			end
		end
	end
end

-- Dodge roll: the client moves the character; the server grants the i-frames and tells everyone to draw it.
function CombatService.dodge(player: Player, dir)
	local humanoid, root = alive(player)
	if not humanoid or State.fallen[player] then
		return
	end
	local stats = Stats.get(player)
	local now = os.clock()
	if stats.dodgeReadyAt > now then
		return
	end
	if typeof(dir) ~= "Vector3" or dir.Magnitude ~= dir.Magnitude or dir.Magnitude < 0.1 or dir.Magnitude > 1.5 then
		dir = flat(root.CFrame.LookVector)
	end
	dir = flat(dir)
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, -1)
	stats.dodgeReadyAt = now + Config.DODGE_COOLDOWN
	stats.iframeUntil = now + Config.DODGE_IFRAMES
	player:SetAttribute("DodgeReadyAt", workspace:GetServerTimeNow() + Config.DODGE_COOLDOWN)
	Remotes.get("Dodge"):FireAllClients(player.UserId, root.Position, dir)
end

function CombatService.start()
	Remotes.get("Cast").OnServerEvent:Connect(CombatService.cast)
	Remotes.get("Dodge").OnServerEvent:Connect(CombatService.dodge)
	task.spawn(vitalsLoop)
end

return CombatService
