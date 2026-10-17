--!nonstrict
-- Personal loot: each player near a kill rolls their own drop (no ninja-looting, no fights over items).
-- The server owns the gear instance; clients only get a visual (LootDrop) and pick up by walking over it.
-- Also the Inventory remote: equip / unequip / sell / bulk-sell, all validated here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)

local Loot = {}

local rng = Random.new()
local drops = {} -- [player] = { [id] = { inst, pos, expires } }
local pity = {} -- [player] = kills since last Rare+
local nextId = 0
local lastAction = {} -- [player] = os.clock of the last inventory action

local MAX_DROPS = 40 -- per player, so a long fight cannot flood the client

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function weightedRarity(danger: number, minimum: number): number
	local weights = Data.Items.lootRarities
	local total = 0
	local adjusted = {}
	for i, entry in weights do
		-- Higher danger shifts weight from Common toward the top tiers.
		local w = entry[2] * (1 + (i - 1) * 0.12 * danger)
		if i < minimum then
			w = 0
		end
		adjusted[i] = w
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in adjusted do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return math.max(minimum, 1)
end

local function pushState(player: Player)
	local p = Progress.get(player)
	Remotes.get("Inventory"):FireClient(player, {
		weapon = p.weapon,
		armor = p.armor,
		trinket = p.trinket,
		bag = p.bag,
		runes = p.runes,
		level = p.level,
		hero = State.heroes[player],
		size = Progress.BAG_SIZE,
	})
end

-- Moves a drop into the player's possession (equips upgrades, bags the rest, sells if the bag is full).
local function collect(player: Player, id: number, drop)
	local list = drops[player]
	if not list or list[id] ~= drop then
		return
	end
	list[id] = nil
	Remotes.get("LootTaken"):FireClient(player, id)
	local result = Progress.giveGear(player, drop.inst, State.heroes[player])
	local name = Gear.name(drop.inst)
	if result == "equipped" then
		notify(player, "Equipped upgrade: " .. name)
	elseif result == "bag" then
		notify(player, "Looted: " .. name)
	else
		notify(player, ("Bag full - sold %s for %d runes."):format(name, Gear.sellValue(drop.inst)))
	end
end

function Loot.roll(player: Player, enemy, at: Vector3)
	local areaId = enemy.area
	local spec = Data.Adventure.AREAS[areaId]
	if not spec then
		return
	end
	local danger = spec.danger
	local kills = (pity[player] or 0) + 1
	local chance = enemy.boss and 1 or (Config.LOOT_BASE_CHANCE + Config.LOOT_PER_DANGER * danger)
	local guaranteed = kills >= Config.LOOT_PITY_KILLS
	if not guaranteed and rng:NextNumber() >= chance then
		pity[player] = kills
		return
	end
	local list = drops[player]
	if not list then
		list = {}
		drops[player] = list
	end
	local count = 0
	for _ in list do
		count += 1
	end
	if count >= MAX_DROPS then
		pity[player] = kills
		return
	end
	local minimum = (enemy.boss or guaranteed) and 3 or 1
	local rarity = weightedRarity(danger, minimum)
	if rarity >= 3 then
		pity[player] = 0
	else
		pity[player] = kills
	end
	local slotRoll = rng:NextNumber()
	local slot = slotRoll < 0.4 and "w" or slotRoll < 0.8 and "a" or "t"
	local heroes = {}
	for name in Data.Heroes do
		table.insert(heroes, name)
	end
	table.sort(heroes)
	local hero = (rng:NextNumber() < 0.75 and State.heroes[player]) or heroes[rng:NextInteger(1, #heroes)]
	local ilvl = math.clamp(Progress.requiredLevel(areaId) + rng:NextInteger(0, 2) + (enemy.boss and 2 or 0), 1, Gear.MAX_ILVL)
	local inst = Gear.generate(rng, { slot = slot, hero = hero, ilvl = ilvl, rarity = rarity })

	nextId += 1
	local id = nextId
	local scatter = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
	local drop = { inst = inst, pos = at + scatter, expires = os.clock() + Config.LOOT_LIFETIME }
	list[id] = drop
	Remotes.get("LootDrop"):FireClient(player, id, drop.pos, inst)
end

local function pickupLoop()
	local radius = Config.LOOT_PICKUP_STUDS
	while true do
		local now = os.clock()
		for player, list in drops do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local alive = root and player.Character:FindFirstChildOfClass("Humanoid").Health > 0
			for id, drop in list do
				if now >= drop.expires then
					collect(player, id, drop)
				elseif alive and (root.Position - drop.pos).Magnitude <= radius then
					collect(player, id, drop)
				end
			end
		end
		task.wait(0.25)
	end
end

local function onAction(player: Player, action, arg)
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.08 then
		return
	end
	lastAction[player] = now
	if action == "sync" then
		pushState(player)
		return
	end
	local hero = State.heroes[player]
	if action == "equip" and type(arg) == "number" then
		local ok, message = Progress.equipFromBag(player, math.floor(arg), hero)
		if not ok then
			notify(player, message)
		end
	elseif action == "unequip" and type(arg) == "string" then
		local ok, message = Progress.unequip(player, arg)
		if not ok then
			notify(player, message)
		end
	elseif action == "sell" and type(arg) == "number" then
		local ok, message = Progress.sellFromBag(player, math.floor(arg))
		notify(player, message)
		if not ok then
			pushState(player)
		end
	elseif action == "sellcommon" and type(arg) == "number" then
		local maxRarity = math.clamp(math.floor(arg), 1, 2) -- never bulk-sells Rare or better
		local count, total = Progress.sellUpTo(player, maxRarity)
		notify(player, count > 0 and ("Sold %d items for %d runes."):format(count, total) or "Nothing to sell.")
	end
end

function Loot.start()
	Progress.onBagChanged = pushState
	Remotes.get("Inventory").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		drops[player] = nil
		pity[player] = nil
		lastAction[player] = nil
	end)
	task.spawn(pickupLoop)
end

return Loot
