--!nonstrict
-- Gear model (pure logic, no Roblox APIs besides Random). A gear instance is a small plain table:
--   base item:  { b = "iron_sword" }                      (shop / quest items, stats from D().Items)
--   generated:  { s = "w"|"a"|"t", h = hero?, t = tier 1-6, r = rarity 1-5, l = ilvl 1-20,
--                 q = quality 0-99, n = name seed, a = { {id, q}, ... } }
-- Names and stats are DERIVED from those numbers, so saves never store free text and a tampered
-- profile can only produce items the generator could have produced.
-- Data is required lazily; offline tests inject a table with Gear._inject (Luau CLI has no `script`).
local Data = nil
local function D()
	if not Data then
		Data = require(script.Parent.Data)
	end
	return Data
end

local Gear = {}

Gear.RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
Gear.RARITY_RGB = { { 230, 226, 205 }, { 150, 220, 120 }, { 110, 170, 255 }, { 200, 140, 255 }, { 255, 184, 70 } }
Gear.SLOTS = { w = "weapon", a = "armor", t = "trinket" }
Gear.MAX_ILVL = 20

local WEAPON_MULT = { 1, 1.12, 1.25, 1.4, 1.6 }
local ARMOR_MULT = { 1, 1.15, 1.3, 1.5, 1.7 }
local AFFIX_COUNT = { w = { 0, 1, 2, 3, 3 }, a = { 0, 1, 2, 3, 3 }, t = { 1, 1, 2, 3, 3 } }
local SELL_MULT = { 1, 2, 4, 8, 16 }

-- id = { min, max, label, prefix, suffix, unit }  (values are percent unless unit = "flat")
Gear.AFFIXES = {
	dmg = { 2, 8, "Damage", "Savage", "of Power", "%" },
	crit = { 2, 7, "Crit chance", "Keen", "of Precision", "%" },
	leech = { 1, 3, "Life leech", "Vampiric", "of Thirst", "%" },
	ult = { 5, 15, "Ultimate charge", "Surging", "of the Storm", "%" },
	hp = { 3, 10, "Max health", "Sturdy", "of Vitality", "%" },
	speed = { 2, 6, "Move speed", "Swift", "of the Gale", "%" },
	mana = { 8, 30, "Max mana", "Arcane", "of the Mind", "flat" },
	xp = { 3, 10, "XP gain", "Scholar's", "of Insight", "%" },
}
local POOLS = {
	w = { "dmg", "crit", "leech", "ult" },
	a = { "hp", "speed", "mana", "xp" },
	t = { "dmg", "crit", "leech", "ult", "hp", "speed", "mana", "xp" },
}
local AFFIX_ORDER = { "dmg", "crit", "leech", "ult", "hp", "speed", "mana", "xp" }

local WEAPON_NAMES = {
	Knight = { "Rusty Blade", "Iron Sword", "Steel Sword", "Knight's Blade", "Runed Greatsword", "Dragonbane" },
	Wizard = { "Gnarled Wand", "Sage's Wand", "Crystal Staff", "Arcane Focus", "Runed Scepter", "Starfall Staff" },
	Archer = { "Short Bow", "Wind Bow", "Longbow", "Hunter's Bow", "Runed Bow", "Skyrender" },
	Cleric = { "Tin Censer", "Sun Censer", "Brass Censer", "Hallowed Censer", "Runed Thurible", "Dawnfire Censer" },
	Rogue = { "Rusty Knives", "Shadow Blades", "Twin Daggers", "Night Fangs", "Runed Stilettos", "Voidreavers" },
	Druid = { "Twig Staff", "Thorn Staff", "Oak Staff", "Heartwood Staff", "Runed Branch", "World-Tree Bough" },
	Bard = { "Worn Lute", "Travel Lute", "Silver Lute", "Minstrel's Lute", "Runed Lyre", "Songweaver" },
	Healer = { "Wooden Rod", "Mercy Rod", "Silver Rod", "Saint's Rod", "Runed Scepter", "Lifebloom Rod" },
}
local ARMOR_NAMES = { "Padded Vest", "Leather Jerkin", "Ringmail", "Brigandine", "Plate Cuirass", "Dragonscale Mail" }
local TRINKET_NAMES = {
	{ "Copper Ring", "Silver Ring", "Gold Ring", "Moonstone Ring", "Runed Ring", "Starlit Ring" },
	{ "Bone Amulet", "Jade Amulet", "Amber Amulet", "Sapphire Amulet", "Runed Amulet", "Heartstone Amulet" },
	{ "Lucky Charm", "Wolf Charm", "Oak Charm", "Raven Charm", "Runed Charm", "Phoenix Charm" },
}
local TIER_RGB = { { 150, 140, 130 }, { 190, 190, 185 }, { 150, 175, 200 }, { 110, 150, 190 }, { 170, 130, 210 }, { 240, 190, 90 } }

function Gear.tierFor(ilvl: number): number
	return math.clamp(math.ceil(ilvl / 3.4), 1, 6)
end

local function clampInt(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	v = math.floor(v)
	if v < lo or v > hi then
		return nil
	end
	return v
end

-- --------------------------------------------------------------- creation
function Gear.fromBase(id: string)
	local it = D().Items.items[id]
	if it and (it.kind == "weapon" or it.kind == "armor") then
		return { b = id }
	end
	return nil
end

-- opts: slot "w"/"a"/"t", hero (weapons), ilvl, rarity (1-5)
function Gear.generate(rng: Random, opts)
	local slot = opts.slot
	local rarity = math.clamp(opts.rarity or 1, 1, 5)
	local ilvl = math.clamp(opts.ilvl or 1, 1, Gear.MAX_ILVL)
	local inst = {
		s = slot,
		t = Gear.tierFor(ilvl),
		r = rarity,
		l = ilvl,
		q = rng:NextInteger(0, 99),
		n = rng:NextInteger(0, 99),
		a = {},
	}
	if slot == "w" then
		inst.h = D().Heroes[opts.hero] and opts.hero or "Knight"
	end
	local pool = table.clone(POOLS[slot])
	for _ = 1, math.min(AFFIX_COUNT[slot][rarity], #pool) do
		local i = rng:NextInteger(1, #pool)
		table.insert(inst.a, { pool[i], rng:NextInteger(0, 99) })
		table.remove(pool, i)
	end
	return inst
end

-- Validates a raw (possibly tampered / legacy) value; returns a clean instance or nil.
function Gear.valid(raw)
	if type(raw) == "string" then
		return Gear.fromBase(raw) -- legacy saves stored the item id
	end
	if type(raw) ~= "table" then
		return nil
	end
	if raw.b ~= nil then
		return type(raw.b) == "string" and Gear.fromBase(raw.b) or nil
	end
	local slot = raw.s
	if slot ~= "w" and slot ~= "a" and slot ~= "t" then
		return nil
	end
	local inst = {
		s = slot,
		t = clampInt(raw.t, 1, 6),
		r = clampInt(raw.r, 1, 5),
		l = clampInt(raw.l, 1, Gear.MAX_ILVL),
		q = clampInt(raw.q, 0, 99),
		n = clampInt(raw.n, 0, 99),
		a = {},
	}
	if not (inst.t and inst.r and inst.l and inst.q and inst.n) then
		return nil
	end
	if slot == "w" then
		if type(raw.h) ~= "string" or not D().Heroes[raw.h] then
			return nil
		end
		inst.h = raw.h
	end
	if type(raw.a) ~= "table" then
		return nil
	end
	local allowed, seen = {}, {}
	for _, id in POOLS[slot] do
		allowed[id] = true
	end
	for _, entry in raw.a do
		if type(entry) ~= "table" then
			return nil
		end
		local id, q = entry[1], clampInt(entry[2], 0, 99)
		if type(id) ~= "string" or not allowed[id] or seen[id] or not q then
			return nil
		end
		seen[id] = true
		table.insert(inst.a, { id, q })
	end
	if #inst.a > AFFIX_COUNT[slot][inst.r] then
		return nil
	end
	return inst
end

-- --------------------------------------------------------------- derivation
local function affixValue(id: string, q: number, rarity: number, slot: string): number
	local spec = Gear.AFFIXES[id]
	local t = math.clamp(q / 99 * 0.6 + 0.1 * (rarity - 1), 0, 1)
	local v = spec[1] + (spec[2] - spec[1]) * t
	if slot == "t" then
		v *= 1.3
	end
	if spec[6] == "flat" then
		return math.round(v)
	end
	return math.round(v * 10) / 10
end

local function baseDamage(inst): number
	local jitter = 0.9 + inst.q / 99 * 0.2
	return math.round((3 + inst.l) * WEAPON_MULT[inst.r] * jitter)
end

local function baseArmor(inst): number
	local jitter = 0.9 + inst.q / 99 * 0.2
	return math.round((0.6 + inst.l * 0.22) * ARMOR_MULT[inst.r] * jitter * 10) / 10
end

-- Numeric stats. Percent affixes are returned as fractions (0.05 = 5%).
function Gear.stats(inst)
	local out = { damage = 0, armor = 0, dmg = 0, crit = 0, leech = 0, ult = 0, hp = 0, speed = 0, mana = 0, xp = 0 }
	if not inst then
		return out
	end
	if inst.b then
		local it = D().Items.items[inst.b]
		if it then
			out.damage = it.damage or 0
			out.armor = it.armor or 0
		end
		return out
	end
	if inst.s == "w" then
		out.damage = baseDamage(inst)
	elseif inst.s == "a" then
		out.armor = baseArmor(inst)
	end
	for _, entry in inst.a do
		local v = affixValue(entry[1], entry[2], inst.r, inst.s)
		out[entry[1]] += Gear.AFFIXES[entry[1]][6] == "flat" and v or v / 100
	end
	return out
end

function Gear.name(inst): string
	if inst.b then
		return D().Items.items[inst.b].name
	end
	local tier = inst.t
	local base
	if inst.s == "w" then
		base = WEAPON_NAMES[inst.h][tier]
	elseif inst.s == "a" then
		base = ARMOR_NAMES[tier]
	else
		base = TRINKET_NAMES[inst.n % 3 + 1][tier]
	end
	local name = base
	local first, second = inst.a[1], inst.a[2]
	if first then
		name = Gear.AFFIXES[first[1]][4] .. " " .. name
	end
	if second then
		name = name .. " " .. Gear.AFFIXES[second[1]][5]
	end
	return name
end

function Gear.rarityIndex(inst): number
	if inst.b then
		local rarity = D().Items.items[inst.b].rarity
		return table.find(Gear.RARITIES, rarity) or 1
	end
	return inst.r
end

function Gear.slotOf(inst): string -- "w" | "a" | "t"
	if inst.b then
		return D().Items.items[inst.b].kind == "weapon" and "w" or "a"
	end
	return inst.s
end

function Gear.itemLevel(inst): number
	if inst.b then
		local rarity = D().Items.items[inst.b].rarity
		return ({ Common = 1, Uncommon = 3, Rare = 6, Epic = 10, Legendary = 15 })[rarity] or 1
	end
	return inst.l
end

function Gear.levelReq(inst): number
	if inst.b then
		return Gear.itemLevel(inst)
	end
	return math.max(1, inst.l - 1)
end

-- Weapons are class-bound: generated ones by `h`, class starter weapons by their owner.
function Gear.usableBy(inst, hero: string): boolean
	if inst.b then
		for h, id in D().Items.classWeapons do
			if id == inst.b then
				return h == hero
			end
		end
		return true
	end
	if inst.s == "w" then
		return inst.h == hero
	end
	return true
end

function Gear.sellValue(inst): number
	if inst.b then
		return D().Items.items[inst.b].sell
	end
	return math.max(2, math.round((inst.l * 0.8 + 4) * SELL_MULT[inst.r]))
end

-- Body colour as {r,g,b} 0-255.
function Gear.rgb(inst)
	if inst.b then
		local hex = D().Items.items[inst.b].color or "#d8d4c9"
		return {
			tonumber(hex:sub(2, 3), 16) or 200,
			tonumber(hex:sub(4, 5), 16) or 200,
			tonumber(hex:sub(6, 7), 16) or 200,
		}
	end
	return TIER_RGB[inst.t]
end

function Gear._inject(data)
	Data = data
end

-- UI-ready description (plain data, safe to send over a remote).
function Gear.describe(inst)
	if not inst then
		return nil
	end
	local stats = Gear.stats(inst)
	local ri = Gear.rarityIndex(inst)
	local slot = Gear.slotOf(inst)
	local lines = {}
	for _, id in AFFIX_ORDER do
		local v = stats[id]
		if v and v > 0 then
			local spec = Gear.AFFIXES[id]
			table.insert(lines, spec[6] == "flat" and ("+%d %s"):format(v, spec[3]) or ("+%.1f%% %s"):format(v * 100, spec[3]))
		end
	end
	local effect
	if inst.b then
		local it = D().Items.items[inst.b]
		effect = it.effectLabel
	end
	return {
		name = Gear.name(inst),
		slot = Gear.SLOTS[slot],
		slotKey = slot,
		rarity = Gear.RARITIES[ri],
		rarityIndex = ri,
		damage = stats.damage,
		armor = stats.armor,
		lines = lines,
		effect = effect,
		hero = inst.h,
		ilvl = Gear.itemLevel(inst),
		levelReq = Gear.levelReq(inst),
		sell = Gear.sellValue(inst),
		color = Gear.rgb(inst),
		stats = stats,
	}
end

return Gear
