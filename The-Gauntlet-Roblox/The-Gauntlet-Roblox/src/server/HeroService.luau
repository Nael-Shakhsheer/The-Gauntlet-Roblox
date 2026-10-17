--!nonstrict
-- Hero class selection: applies the 2D class stats (hp, speed) to the Roblox
-- character and dresses it in the hero's colour and class weapon.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Gear = require(Shared.Gear)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Stats = require(script.Parent.Stats)
local Progress = require(script.Parent.Progress)

local HeroService = {}

local DEFAULT_HERO = "Knight"

local function attach(character: Model, part: BasePart, toNames: { string }, offset: CFrame)
	for _, name in toNames do
		local target = character:FindFirstChild(name)
		if target then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = target
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part
			part.Parent = character
			return
		end
	end
	part:Destroy()
end

local function dress(player: Player, character: Model, hero: string)
	local info = Data.Heroes[hero]
	local color = Palette.hex(info.color)
	for _, old in { "HeroMantle", "HeroWeapon", "HeroTag", "HeroTrinket" } do
		local found = character:FindFirstChild(old, true)
		if found then
			found:Destroy()
		end
	end

	local mantle = Make.part({ Name = "HeroMantle", Size = Vector3.new(2.2, 2.6, 0.3), Color = color }, nil)
	attach(character, mantle, { "UpperTorso", "Torso" }, CFrame.new(0, -0.1, 0.65))

	local weaponKey = Data.Items.classWeapons[hero]
	local weaponInfo = weaponKey and Data.Items.items[weaponKey]
	local equipped = Progress.get(player).weapon
	local weaponColor = weaponInfo and Palette.hex(weaponInfo.color) or color
	local rarity = equipped and Gear.rarityIndex(equipped) or 1
	if equipped then
		local rgb = Gear.rgb(equipped)
		weaponColor = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	local weapon = Make.part({
		Name = "HeroWeapon",
		Size = Vector3.new(0.35, 3.4 + (rarity - 1) * 0.15, 0.35 + (rarity - 1) * 0.05),
		Color = weaponColor,
		Material = rarity >= 4 and Enum.Material.Neon or Enum.Material.Metal,
	}, nil)
	if rarity >= 3 then
		local light = Instance.new("PointLight")
		light.Color = weaponColor
		light.Range = 5 + rarity
		light.Brightness = 0.6
		light.Parent = weapon
	end
	attach(character, weapon, { "RightHand", "Right Arm" }, CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(90), 0, 0))

	local trinket = Progress.get(player).trinket
	if trinket then
		local rgb = Gear.rgb(trinket)
		local charm = Make.part({
			Name = "HeroTrinket",
			Size = Vector3.new(0.5, 0.5, 0.5),
			Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
		}, nil)
		attach(character, charm, { "LowerTorso", "Torso" }, CFrame.new(0.9, 0, -0.6))
	end

	local head = character:FindFirstChild("Head")
	if head then
		local gui = Make.label(head, hero, color, 2.6, 140, 70)
		gui.Name = "HeroTag"
	end

	-- Body colours echo the hero's palette without replacing the player's avatar.
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		colors.TorsoColor3 = Make.shade(color, -0.2)
	end
end

local function baseSpeed(player: Player): number
	return Data.Heroes[State.heroes[player] or DEFAULT_HERO].speed * Config.STUDS_PER_PX * (1 + Progress.bonus(player).speed)
end

-- Full (re)apply: class stats scaled by level. Health is refilled.
function HeroService.apply(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local hero = State.heroes[player] or DEFAULT_HERO
	local info = Data.Heroes[hero]
	local maxHp = math.round(info.hp * Progress.hpMultiplier(player))
	humanoid.MaxHealth = maxHp
	humanoid.Health = maxHp
	humanoid.WalkSpeed = baseSpeed(player)
	Stats.get(player).maxMana = Config.BASE_MANA + math.round(Progress.bonus(player).mana)
	player:SetAttribute("Hero", hero)
	dress(player, character, hero)
end

function HeroService.select(player: Player, hero)
	if typeof(hero) ~= "string" or not Data.Heroes[hero] then
		return
	end
	-- The first pick is free. After that the hero is bound: switching is a later mechanic
	-- (Config.HERO_SWAP_ENABLED turns the old Guild-board window back on for testing).
	if State.heroChosen[player] and State.heroes[player] ~= hero then
		if not Config.HERO_SWAP_ENABLED then
			Remotes.get("Notify"):FireClient(player, "Your hero is bound to you.")
			return
		end
		if (State.guildUntil[player] or 0) < os.clock() then
			Remotes.get("Notify"):FireClient(player, "Change your hero at the Guild board in a village.")
			return
		end
	end
	if State.heroChosen[player] and State.heroes[player] ~= hero then
		State.guildUntil[player] = nil
	end
	State.heroChosen[player] = true
	player:SetAttribute("HeroLocked", true)
	local changed = State.heroes[player] ~= hero
	State.heroes[player] = hero
	if changed then
		require(script.Parent.Skills).onHeroChange(player)
		Progress.refit(player, hero)
	end
	State.cooldowns[player] = {}
	HeroService.apply(player)
	Remotes.get("HeroChanged"):FireClient(player, hero)
end

-- Equipment changed: refresh visuals, max health (keeping the health ratio) and max mana.
local function onGearChanged(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local hero = State.heroes[player] or DEFAULT_HERO
	local newMax = math.round(Data.Heroes[hero].hp * Progress.hpMultiplier(player))
	local ratio = humanoid.Health / humanoid.MaxHealth
	humanoid.MaxHealth = newMax
	humanoid.Health = math.clamp(math.round(newMax * ratio), 1, newMax)
	local stats = Stats.get(player)
	stats.maxMana = Config.BASE_MANA + math.round(Progress.bonus(player).mana)
	stats.mana = math.min(stats.mana, stats.maxMana)
	dress(player, character, hero)
end

-- Level-ups raise max health; the gain is added to current health.
local function onLevelUp(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local newMax = math.round(Data.Heroes[State.heroes[player] or DEFAULT_HERO].hp * Progress.hpMultiplier(player))
	local gain = newMax - humanoid.MaxHealth
	humanoid.MaxHealth = newMax
	humanoid.Health = math.min(newMax, humanoid.Health + math.max(gain, 0))
end

local function speedLoop()
	while true do
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local stats = Stats.get(player)
				local want = baseSpeed(player) * (stats.speedUntil > now and stats.speedFactor or 1)
				-- Sprint (hold Shift): +40% outside combat. Makes the big world bearable.
				if State.sprint[player] and now - stats.lastCombat > 4 then
					want *= Config.SPRINT_FACTOR
				end
				if math.abs(humanoid.WalkSpeed - want) > 0.05 then
					humanoid.WalkSpeed = want
				end
			end
		end
		task.wait(0.2)
	end
end

function HeroService.start(spawnPoint: (Player) -> ())
	Progress.onLevelUp = onLevelUp
	Progress.onGearChanged = onGearChanged
	local function onPlayer(player: Player)
		State.heroes[player] = State.heroes[player] or DEFAULT_HERO
		State.cooldowns[player] = {}
		Progress.sync(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			local humanoid = character:WaitForChild("Humanoid")
			task.wait() -- let appearance finish loading
			Stats.reset(player)
			HeroService.apply(player)
			spawnPoint(player)
			local revive = State.reviveAt[player]
			if revive then
				State.reviveAt[player] = nil
				character:PivotTo(CFrame.new(revive.pos + Vector3.new(0, 3, 0)))
				humanoid.Health = math.max(1, math.round(humanoid.MaxHealth * revive.fraction))
			end
		end)
		Remotes.get("HeroChanged"):FireClient(player, State.heroes[player])
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		Progress.drop(player) -- first: Persistence snapshots the hero before it is cleared
		State.heroes[player] = nil
		State.heroChosen[player] = nil
		State.guildUntil[player] = nil
		State.bounty[player] = nil
		State.shopMode[player] = nil
		State.useAt[player] = nil
		State.sprint[player] = nil
		State.cooldowns[player] = nil
		Stats.drop(player)
	end)
	Remotes.get("SelectHero").OnServerEvent:Connect(HeroService.select)
	Remotes.get("Sprint").OnServerEvent:Connect(function(player, held)
		State.sprint[player] = held == true or nil
	end)
	task.spawn(speedLoop)
end

return HeroService
