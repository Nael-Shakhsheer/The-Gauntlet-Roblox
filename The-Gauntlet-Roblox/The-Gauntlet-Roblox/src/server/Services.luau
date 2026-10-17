--!nonstrict
-- Village services (port-designed around the 2D game's town buildings):
--   Innkeeper  - advice, current goal, next level gate
--   Merchant   - weapons & armour (also the stall)          [Interactions.openShop]
--   Alchemist  - potions into the pouch (use with Z X C V B N M)
--   Guildmaster- repeatable bounties: slay N foes, get runes + XP
--   Guild board- change hero (2D: the Guild's class change)
--   Mara       - Cottage treatment: full health + mana for 5 runes (free if both are full)
--   Lodge hunter - frontier guide: where to hunt at your level
--   Villagers  - tips and hints
-- Potions: UseItem remote. Bounties: counted from EnemyService.onKill.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)
local EnemyService = require(script.Parent.EnemyService)
local Quests = require(script.Parent.Quests)

local Adventure = Data.Adventure

local Services = {}

local CURE_PRICE = 5

local function tell(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function say(player: Player, title: string, pages)
	Remotes.get("Dialogue"):FireClient(player, title, pages)
end

local function humanoidOf(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- --------------------------------------------------------------- guidance

-- Areas sorted by required level: { {id, name, level, danger} }
local function gatedAreas()
	local list = {}
	for id, spec in Adventure.AREAS do
		if not spec.dungeon and id ~= "caravan" then
			table.insert(list, { id = id, name = spec.name, level = Progress.requiredLevel(id), danger = spec.danger })
		end
	end
	table.sort(list, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.name < b.name
	end)
	return list
end

local function nextGate(level: number)
	for _, a in gatedAreas() do
		if a.level > level then
			return a
		end
	end
	return nil
end

local function huntingGrounds(level: number)
	-- Highest-danger areas the player may enter (not over-levelled, not trivial).
	local list = {}
	for _, a in gatedAreas() do
		if a.level <= level and a.danger >= 1 and level - a.level <= Config.OVERLEVEL_GRACE + 2 then
			table.insert(list, a)
		end
	end
	return list
end

-- ----------------------------------------------------------------- talk

local GOSSIP = {
	"The southern road looks quiet by day. Past the crossroads the wolves get bolder.",
	"Take guild bounties. Hunting tougher foes pays far more than wandering about.",
	"Waystones in the villages and attuned shrines let you travel without the long walk.",
	"Mara in the cottage patches travellers up for a few runes. Cheaper than a potion.",
	"Armour blocks damage on every hit. Buy the best you can afford at the Outfitter.",
	"A potion from the Alchemy Lab can save a boss fight. Keep a few in your pouch.",
	"They say a Minotaur King waits behind the ruins gate. I would level up before knocking.",
	"Dunmere's fields have failed. The roots run deep and no one will say why.",
	"If a trail looks winding, follow it. The scenic way is rarely the dangerous way.",
	"Rest at the inn bed and you'll wake there if you fall.",
}

local function gossip(player: Player, feature)
	local index = 1
	for i = 1, #feature.key do
		index = (index * 31 + string.byte(feature.key, i)) % 9973
	end
	local line = GOSSIP[index % #GOSSIP + 1]
	local line2 = GOSSIP[(index + 3) % #GOSSIP + 1]
	say(player, feature.name, { line, line2 })
end

local function innkeeper(player: Player, feature)
	State.claimed.inn = true -- skill milestone "inn"
	local training = Adventure.PAGES["adventure_training"]
	local level = Progress.get(player).level
	local gate = nextGate(level)
	local advice = {}
	table.insert(advice, "Current goal: " .. (Quests.objective():match("^[^\n]+") or "explore."))
	if gate then
		table.insert(advice, ("You are level %d. The next gate is %s at level %d. Hunt, earn runes, and gear up."):format(level, gate.name, gate.level))
	else
		table.insert(advice, ("You are level %d. No gate stands in your way."):format(level))
	end
	table.insert(advice, "Rest in the inn bed to heal and set where you return if you fall.")
	local pages = {}
	for _, line in advice do
		table.insert(pages, line)
	end
	if training then
		table.insert(pages, training[2][2])
	end
	say(player, "Innkeeper", pages)
end

local function lodge(player: Player, feature)
	local level = Progress.get(player).level
	local grounds = huntingGrounds(level)
	local names = {}
	for i = #grounds, math.max(1, #grounds - 3), -1 do
		table.insert(names, ("%s (Lv %d)"):format(grounds[i].name, grounds[i].level))
	end
	local pages = {
		("Level %d hunter, eh? Good hunting right now: %s."):format(level, #names > 0 and table.concat(names, ", ") or "stay near the villages"),
	}
	local gate = nextGate(level)
	if gate then
		local after = nextGate(gate.level)
		table.insert(pages, ("Next you can unlock %s at level %d%s."):format(gate.name, gate.level, after and (", then " .. after.name .. " at " .. after.level) or ""))
	end
	table.insert(pages, "Rule of thumb: kill things for XP, take bounties at the Guild, buy armour first, then a better weapon. Over-levelled areas give far less XP.")
	say(player, "Hunter · Frontier guide", pages)
end

-- ------------------------------------------------------------------ cottage

local function cottage(player: Player, feature)
	local humanoid = humanoidOf(player)
	if not humanoid then
		return
	end
	local stats = Stats.get(player)
	local full = humanoid.Health >= humanoid.MaxHealth - 0.5 and stats.mana >= stats.maxMana - 0.5
	local cost = full and 0 or CURE_PRICE
	local p = Progress.get(player)
	if p.runes < cost then
		say(player, "Mara · Cottage recovery", { ("Treatment costs %d runes and you have %d."):format(CURE_PRICE, p.runes) })
		return
	end
	if cost > 0 then
		p.runes -= cost
		Progress.sync(player)
	end
	humanoid.Health = humanoid.MaxHealth
	stats.mana = stats.maxMana
	say(player, "Mara · Cottage recovery", {
		cost > 0 and ("Both resources are restored. %d runes paid."):format(cost) or "You are already well. No charge.",
		"This is treatment, not an inn checkpoint. Rest in an inn bed to set where you return.",
	})
end

-- ----------------------------------------------------------------- alchemist

local function alchemist(player: Player, feature)
	State.shopMode[player] = "potions"
	Remotes.get("ShopOpen"):FireClient(player, Progress.potionStock(player), feature.name)
end

-- Called from Interactions.buy after a successful potion purchase.
function Services.refreshShop(player: Player, hero)
	if State.shopMode[player] == "potions" then
		Remotes.get("ShopOpen"):FireClient(player, Progress.potionStock(player), nil)
	else
		Remotes.get("ShopOpen"):FireClient(player, Progress.stock(player, hero), nil)
	end
end

-- ------------------------------------------------------------------- guild

local function bountyLine(player: Player): string
	local b = State.bounty[player]
	if not b then
		return ""
	end
	if b.have >= b.need then
		return ("Bounty complete! Return to the Guildmaster (%d runes, %d XP)."):format(b.runes, b.xp)
	end
	return ("Bounty: slay %d/%d foes of danger %d+."):format(b.have, b.need, b.minDanger)
end

local function pushBounty(player: Player)
	Remotes.get("Bounty"):FireClient(player, bountyLine(player))
end

local function newBounty(player: Player)
	local level = Progress.get(player).level
	local best = 1
	for danger = 1, 7 do
		if (Config.LEVEL_BY_DANGER[danger] or 99) <= level then
			best = danger
		end
	end
	local need = 5 + level // 3
	return {
		need = need,
		have = 0,
		minDanger = math.max(1, best - 1),
		runes = need * (2 + 2 * best),
		xp = need * (3 + 2 * best),
	}
end

local function guildmaster(player: Player, feature)
	local b = State.bounty[player]
	if b and b.have >= b.need then
		Progress.addRunes(player, b.runes)
		Progress.addXp(player, b.xp)
		State.bounty[player] = nil
		pushBounty(player)
		say(player, "Guildmaster", { ("Fine work. %d runes and %d XP, as promised."):format(b.runes, b.xp), "Speak to me again when you want another bounty." })
	elseif b then
		say(player, "Guildmaster", { bountyLine(player), "Foes of that danger roam the regions your level allows. Check the Lodge guide if you're unsure where." })
	else
		State.bounty[player] = newBounty(player)
		local nb = State.bounty[player]
		pushBounty(player)
		say(player, "Guildmaster", {
			("New bounty: slay %d foes of danger %d or higher. Reward: %d runes and %d XP."):format(nb.need, nb.minDanger, nb.runes, nb.xp),
			"Danger rises with the region: check the area's level gate. Bounties are yours alone.",
		})
	end
end

local function guildBoard(player: Player, feature)
	if not Config.HERO_SWAP_ENABLED then
		tell(player, "The registry holds your name. Your hero is bound to you.")
		return
	end
	State.guildUntil[player] = os.clock() + 120
	Remotes.get("GuildOpen"):FireClient(player)
	tell(player, "The registry lets you swap hero class. Pick a new hero.")
end

local dropRng = Random.new()
local DROPS = { "healing_draught", "healing_draught", "healing_draught", "mana_draught", "mana_draught", "warding_tonic" }

function Services.onKill(enemy, attacker)
	if enemy.noReward then
		return
	end
	local spec = Adventure.AREAS[enemy.area]
	local danger = spec and spec.danger or 0
	local at = enemy.model.PrimaryPart and enemy.model.PrimaryPart.Position or Vector3.zero
	for _, player in Players:GetPlayers() do
		-- Potion drops (kill credit goes to the killer and nearby party members).
		local rootNear = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if player == attacker or (rootNear and (rootNear.Position - at).Magnitude <= Config.XP_SHARE_STUDS) then
			if dropRng:NextNumber() < (enemy.boss and 1 or 0.05 + 0.015 * danger) then
				local id = DROPS[dropRng:NextInteger(1, #DROPS)]
				if (Progress.get(player).pouch[id] or 0) < Progress.POTION_MAX then
					Progress.givePotion(player, id)
					tell(player, ("Found a %s."):format(Data.Items.items[id].name))
				end
			end
		end
		local b = State.bounty[player]
		if b and b.have < b.need and danger >= b.minDanger then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player == attacker or (root and (root.Position - at).Magnitude <= Config.XP_SHARE_STUDS) then
				b.have += 1
				pushBounty(player)
				if b.have >= b.need then
					tell(player, "Bounty complete! Report to the Guildmaster.")
				end
			end
		end
	end
end

-- ----------------------------------------------------------------- potions

function Services.use(player: Player, id)
	if not Progress.isPotion(id) then
		return
	end
	local humanoid = humanoidOf(player)
	if not humanoid then
		return
	end
	local now = os.clock()
	if now - (State.useAt[player] or 0) < 0.8 then
		return
	end
	local it = Data.Items.items[id]
	local stats = Stats.get(player)
	-- Do not waste potions that would do nothing.
	if it.kind == "heal" and humanoid.Health >= humanoid.MaxHealth - 0.5 then
		tell(player, "You are already at full health.")
		return
	end
	if it.kind == "mana" and stats.mana >= stats.maxMana - 0.5 then
		tell(player, "Your mana is already full.")
		return
	end
	if not Progress.takePotion(player, id) then
		return
	end
	State.useAt[player] = now
	if it.kind == "heal" then
		local amount = math.round((it.heal or 40) * Progress.hpMultiplier(player))
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		tell(player, ("%s: +%d health."):format(it.name, amount))
	elseif it.kind == "mana" then
		stats.mana = math.min(stats.maxMana, stats.mana + (it.mana or 50))
		tell(player, ("%s: +%d mana."):format(it.name, it.mana or 50))
	elseif it.kind == "ward" then
		local factor, duration = it.factor or 0.6, it.duration or 30
		stats.wardFactor = math.min(stats.wardUntil > now and stats.wardFactor or 1, factor)
		stats.wardUntil = math.max(stats.wardUntil, now + duration)
		tell(player, ("%s: %d%% less damage for %ds."):format(it.name, math.round((1 - factor) * 100), duration))
	elseif it.kind == "speed" then
		stats.speedFactor = it.factor or 1.45
		stats.speedUntil = now + (it.duration or 10)
		tell(player, ("%s: move faster for %ds."):format(it.name, it.duration or 10))
	elseif it.kind == "buff" then
		stats.boost = it.factor or 1.4
		stats.boostUntil = now + (it.duration or 12)
		tell(player, ("%s: +%d%% damage for %ds."):format(it.name, math.round(((it.factor or 1.4) - 1) * 100), it.duration or 12))
	end
end

-- ---------------------------------------------------------------- dispatch

local HANDLERS = {
	innkeeper = innkeeper,
	alchemist = alchemist,
	guildmaster = guildmaster,
	guild_board = guildBoard,
	caretaker = cottage,
	lodge = lodge,
	gossip = gossip,
}

-- Returns true if the feature was a village service. Merchant is handled by Interactions (shop).
function Services.handle(player: Player, feature): boolean
	local handler = feature.service and HANDLERS[feature.service]
	if handler then
		handler(player, feature)
		return true
	end
	return false
end

function Services.start()
	Remotes.get("UseItem").OnServerEvent:Connect(Services.use)
	local previous = EnemyService.onKill
	EnemyService.onKill = function(enemy, attacker)
		if previous then
			previous(enemy, attacker)
		end
		Services.onKill(enemy, attacker)
	end
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			pushBounty(player)
		end)
	end)
end

return Services
