--!nonstrict
-- Grind progression (port-only): XP, levels, runes (money), shop gear, and the
-- per-area level requirement. State lives here per player and is mirrored to player
-- attributes (Level, Xp, XpNext, Runes, WeaponName, ArmorName, ArmorValue) so the HUD
-- reads it without remotes.
-- Saved by Persistence.luau (DataStore).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local Progress = {}
local profiles = {}

Progress.onLevelUp = nil -- set by HeroService: function(player, level)
Progress.onDrop = nil -- set by Persistence: final snapshot before the profile is cleared
Progress.onBagChanged = nil -- set by Inventory: function(player) push bag state to the client
Progress.onGearChanged = nil -- set by HeroService: function(player) rebuild visuals / max hp / mana
Progress.BAG_SIZE = 24

local function fresh()
	return { level = 1, xp = 0, runes = 0, weapon = nil, armor = nil, trinket = nil, bag = {}, pouch = {} }
end

function Progress.get(player: Player)
	local p = profiles[player]
	if not p then
		p = fresh()
		profiles[player] = p
	end
	return p
end

function Progress.drop(player: Player)
	if Progress.onDrop and profiles[player] then
		Progress.onDrop(player)
	end
	profiles[player] = nil
end

function Progress.xpNext(level: number): number
	local c = Config.XP_NEXT
	return math.round(c.base + c.scale * (level - 1) ^ c.power)
end

function Progress.requiredLevel(areaId: string): number
	local spec = Data.Adventure.AREAS[areaId]
	return spec and Config.LEVEL_BY_DANGER[spec.danger] or 1
end

-- Summed stats of everything equipped (cached; call Progress.invalidate after any change).
function Progress.bonus(player: Player)
	local p = Progress.get(player)
	local cached = p._bonus
	if cached then
		return cached
	end
	local total = Gear.stats(nil)
	for _, inst in { p.weapon, p.armor, p.trinket } do
		if inst then
			for k, v in Gear.stats(inst) do
				total[k] += v
			end
		end
	end
	p._bonus = total
	return total
end

function Progress.invalidate(player: Player)
	Progress.get(player)._bonus = nil
end

function Progress.hpMultiplier(player: Player): number
	return (1 + Config.HP_PER_LEVEL * (Progress.get(player).level - 1)) * (1 + Progress.bonus(player).hp)
end

function Progress.damageMultiplier(player: Player): number
	return (1 + Config.DAMAGE_PER_LEVEL * (Progress.get(player).level - 1)) * (1 + Progress.bonus(player).dmg)
end

function Progress.weaponDamage(player: Player): number
	return Progress.bonus(player).damage
end

function Progress.armorValue(player: Player): number
	return Progress.bonus(player).armor
end

local function nameOf(inst, fallback: string): string
	return inst and Gear.name(inst) or fallback
end

function Progress.sync(player: Player)
	local p = Progress.get(player)
	player:SetAttribute("Level", p.level)
	player:SetAttribute("Xp", p.xp)
	player:SetAttribute("XpNext", p.level >= Config.MAX_LEVEL and 0 or Progress.xpNext(p.level))
	player:SetAttribute("Runes", p.runes)
	player:SetAttribute("WeaponName", nameOf(p.weapon, "Bare hands"))
	player:SetAttribute("ArmorName", nameOf(p.armor, "No armour"))
	player:SetAttribute("ArmorValue", math.round(Progress.armorValue(player) * 10) / 10)
	player:SetAttribute("BagCount", #p.bag)
	-- Pouch as "id:count,id:count" in display order (client builds the potion bar from it).
	local parts = {}
	for _, id in Progress.POTION_ORDER do
		local n = p.pouch[id]
		if n and n > 0 then
			table.insert(parts, id .. ":" .. n)
		end
	end
	player:SetAttribute("Pouch", table.concat(parts, ","))
end

function Progress.addXp(player: Player, amount: number)
	local p = Progress.get(player)
	if p.level >= Config.MAX_LEVEL or amount <= 0 then
		return
	end
	amount = math.max(1, math.round(amount * (1 + Progress.bonus(player).xp)))
	p.xp += amount
	local leveled = false
	while p.level < Config.MAX_LEVEL and p.xp >= Progress.xpNext(p.level) do
		p.xp -= Progress.xpNext(p.level)
		p.level += 1
		leveled = true
	end
	if p.level >= Config.MAX_LEVEL then
		p.xp = 0
	end
	Progress.sync(player)
	if leveled then
		Remotes.get("Notify"):FireClient(player, ("Level up! You are level %d."):format(p.level))
		if Progress.onLevelUp then
			Progress.onLevelUp(player, p.level)
		end
	end
end

function Progress.addRunes(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	Progress.get(player).runes += amount
	Progress.sync(player)
end

-- Rewards for one kill in `areaId`; XP shrinks when the player far outlevels the area.
function Progress.rewardKill(player: Player, areaId: string, rng: Random)
	local danger = Data.Adventure.AREAS[areaId].danger
	local xp = Config.XP_PER_KILL.base + Config.XP_PER_KILL.perDanger * danger
	local over = Progress.get(player).level - (Progress.requiredLevel(areaId) + Config.OVERLEVEL_GRACE)
	if over > 0 then
		xp = xp * math.max(0.25, 1 - 0.15 * over)
	end
	local r = Config.RUNES_PER_KILL
	local runes = rng:NextInteger(r.min, r.max) + r.perDanger * danger
	Progress.addXp(player, math.max(1, math.round(xp)))
	Progress.addRunes(player, runes)
	return xp, runes
end

-- ------------------------------------------------------------------ gear
local FIELD = { w = "weapon", a = "armor", t = "trinket" }

-- Comparison score for "is this an upgrade" (damage/armor first, affixes as a small tiebreaker).
function Progress.score(inst): number
	local st = Gear.stats(inst)
	return st.damage * (1 + st.dmg) + st.armor * 1.5 + (st.crit + st.leech + st.hp + st.speed + st.xp + st.ult) * 20 + st.mana * 0.1
end

local function changed(player: Player)
	Progress.invalidate(player)
	Progress.sync(player)
	if Progress.onBagChanged then
		Progress.onBagChanged(player)
	end
	if Progress.onGearChanged then
		Progress.onGearChanged(player)
	end
end

-- Puts a gear instance in the bag; a full bag sells it instead. Returns "bag"|"sold", runes gained.
function Progress.addToBag(player: Player, inst): (string, number)
	local p = Progress.get(player)
	if #p.bag >= Progress.BAG_SIZE then
		local value = Gear.sellValue(inst)
		p.runes += value
		Progress.sync(player)
		return "sold", value
	end
	table.insert(p.bag, inst)
	Progress.sync(player)
	return "bag", 0
end

-- Equips `inst` if the player may use it and it beats the current piece; otherwise bags it.
-- Returns "equipped"|"bag"|"sold".
function Progress.giveGear(player: Player, inst, hero: string): string
	local p = Progress.get(player)
	local field = FIELD[Gear.slotOf(inst)]
	local current = p[field]
	local usable = p.level >= Gear.levelReq(inst) and Gear.usableBy(inst, hero)
	if usable and (not current or Progress.score(inst) > Progress.score(current)) then
		p[field] = inst
		if current then
			Progress.addToBag(player, current)
		end
		changed(player)
		return "equipped"
	end
	local where = Progress.addToBag(player, inst)
	changed(player)
	return where
end

-- Quest rewards by base item id. Returns true if it ended up equipped.
function Progress.grant(player: Player, id: string, hero: string): boolean
	local inst = Gear.fromBase(id)
	if not inst then
		return false
	end
	return Progress.giveGear(player, inst, hero) == "equipped"
end

-- Bag actions (indices are validated by the caller's remote handler).
function Progress.equipFromBag(player: Player, index: number, hero: string): (boolean, string)
	local p = Progress.get(player)
	local inst = p.bag[index]
	if not inst then
		return false, "Nothing there."
	end
	if p.level < Gear.levelReq(inst) then
		return false, ("%s needs level %d."):format(Gear.name(inst), Gear.levelReq(inst))
	end
	if not Gear.usableBy(inst, hero) then
		return false, ("%s cannot be used by a %s."):format(Gear.name(inst), hero)
	end
	local field = FIELD[Gear.slotOf(inst)]
	local current = p[field]
	p[field] = inst
	if current then
		p.bag[index] = current
	else
		table.remove(p.bag, index)
	end
	changed(player)
	return true, "Equipped " .. Gear.name(inst) .. "."
end

function Progress.unequip(player: Player, slotKey: string): (boolean, string)
	local p = Progress.get(player)
	local field = FIELD[slotKey]
	if not field or not p[field] then
		return false, "Nothing equipped there."
	end
	if #p.bag >= Progress.BAG_SIZE then
		return false, "Your bag is full."
	end
	table.insert(p.bag, p[field])
	p[field] = nil
	changed(player)
	return true, "Unequipped."
end

function Progress.sellFromBag(player: Player, index: number): (boolean, string, number)
	local p = Progress.get(player)
	local inst = p.bag[index]
	if not inst then
		return false, "Nothing there.", 0
	end
	local value = Gear.sellValue(inst)
	table.remove(p.bag, index)
	p.runes += value
	changed(player)
	return true, ("Sold %s for %d runes."):format(Gear.name(inst), value), value
end

-- Sells every bag item at or below `maxRarity` (1-5). Returns count, runes.
function Progress.sellUpTo(player: Player, maxRarity: number): (number, number)
	local p = Progress.get(player)
	local kept, count, total = {}, 0, 0
	for _, inst in p.bag do
		if Gear.rarityIndex(inst) <= maxRarity then
			count += 1
			total += Gear.sellValue(inst)
		else
			table.insert(kept, inst)
		end
	end
	if count > 0 then
		p.bag = kept
		p.runes += total
		changed(player)
	end
	return count, total
end

-- After a hero change: weapons the new hero cannot use go to the bag, and a fitting best weapon is equipped.
function Progress.refit(player: Player, hero: string)
	local p = Progress.get(player)
	if p.weapon and not Gear.usableBy(p.weapon, hero) then
		Progress.addToBag(player, p.weapon)
		p.weapon = nil
	end
	local bestIndex, bestScore
	if not p.weapon then
		for i, inst in p.bag do
			if Gear.slotOf(inst) == "w" and Gear.usableBy(inst, hero) and p.level >= Gear.levelReq(inst) then
				local sc = Progress.score(inst)
				if not bestScore or sc > bestScore then
					bestIndex, bestScore = i, sc
				end
			end
		end
		if bestIndex then
			p.weapon = table.remove(p.bag, bestIndex)
		end
	end
	changed(player)
end

-- ---------------------------------------------------------------- potions

Progress.POTION_ORDER = {
	"healing_draught", "mana_draught", "warding_tonic", "quickstep_elixir", "ember_oil", "phoenix_flask", "stormguard_charm",
}
Progress.POTION_MAX = 9
Progress.POTION_PRICE_MULT = 2

function Progress.potionStock(player: Player)
	local p = Progress.get(player)
	local list = {}
	for index, id in Progress.POTION_ORDER do
		local it = Data.Items.items[id]
		table.insert(list, {
			id = id,
			name = it.name,
			kind = "consumable",
			rarity = it.rarity,
			price = it.price * Progress.POTION_PRICE_MULT,
			level = Config.GEAR_LEVEL[it.rarity] or 1,
			description = it.description,
			owned = p.pouch[id] or 0,
			order = index,
		})
	end
	return list
end

function Progress.isPotion(id): boolean
	return type(id) == "string" and table.find(Progress.POTION_ORDER, id) ~= nil
end

function Progress.buyPotion(player: Player, id: string)
	local entry
	for _, e in Progress.potionStock(player) do
		if e.id == id then
			entry = e
		end
	end
	if not entry then
		return false, "That is not for sale here."
	end
	local p = Progress.get(player)
	if p.level < entry.level then
		return false, ("%s needs level %d."):format(entry.name, entry.level)
	end
	if (p.pouch[id] or 0) >= Progress.POTION_MAX then
		return false, ("Your pouch holds at most %d %s."):format(Progress.POTION_MAX, entry.name)
	end
	if p.runes < entry.price then
		return false, ("Not enough runes (%d needed)."):format(entry.price)
	end
	p.runes -= entry.price
	p.pouch[id] = (p.pouch[id] or 0) + 1
	Progress.sync(player)
	return true, ("Bought %s."):format(entry.name)
end

-- Removes one potion; false if none left.
function Progress.takePotion(player: Player, id: string): boolean
	local p = Progress.get(player)
	if (p.pouch[id] or 0) <= 0 then
		return false
	end
	p.pouch[id] -= 1
	if p.pouch[id] <= 0 then
		p.pouch[id] = nil
	end
	Progress.sync(player)
	return true
end

-- Gives potions (rewards); respects the pouch cap.
function Progress.givePotion(player: Player, id: string, count: number?)
	local p = Progress.get(player)
	p.pouch[id] = math.min(Progress.POTION_MAX, (p.pouch[id] or 0) + (count or 1))
	Progress.sync(player)
end

-- ------------------------------------------------------------------- shop

-- Weapons/armour for `hero`; class starter weapons belong to their own class only.
function Progress.stock(player: Player, hero: string)
	local own = {}
	for _, id in Data.Items.classWeapons do
		own[id] = true
	end
	local list = {}
	for id, it in Data.Items.items do
		if (it.kind == "weapon" or it.kind == "armor") and (not own[id] or Data.Items.classWeapons[hero] == id) then
			table.insert(list, {
				id = id,
				name = it.name,
				kind = it.kind,
				rarity = it.rarity,
				damage = it.damage or 0,
				armor = it.armor or 0,
				price = it.price * Config.SHOP_PRICE_MULT,
				level = Config.GEAR_LEVEL[it.rarity] or 1,
				description = it.description,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return a.price < b.price
	end)
	return list
end

-- Returns ok, message.
function Progress.buy(player: Player, hero: string, id: string)
	local entry
	for _, e in Progress.stock(player, hero) do
		if e.id == id then
			entry = e
		end
	end
	if not entry then
		return false, "That item is not for sale."
	end
	local p = Progress.get(player)
	if p.level < entry.level then
		return false, ("%s needs level %d."):format(entry.name, entry.level)
	end
	local inst = Gear.fromBase(id)
	local current = entry.kind == "weapon" and p.weapon or p.armor
	if current and Progress.score(inst) <= Progress.score(current) and #p.bag >= Progress.BAG_SIZE then
		return false, "You already have better gear and your bag is full."
	end
	if p.runes < entry.price then
		return false, ("Not enough runes (%d needed)."):format(entry.price)
	end
	p.runes -= entry.price
	local result = Progress.giveGear(player, inst, hero)
	if result == "equipped" then
		return true, ("Bought and equipped %s."):format(entry.name)
	end
	return true, ("Bought %s (in your bag)."):format(entry.name)
end

return Progress
