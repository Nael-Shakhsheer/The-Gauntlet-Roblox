--!nocheck
-- Gear model: generation, validation (tamper resistance), stats ranges. Run: luau tests/check_gear.luau (from tests/)
local Items = require("../src/shared/Data/Generated/Items")
local Heroes = require("../src/shared/Data/Generated/Heroes")
local Gear = require("../src/shared/Gear")
Gear._inject({ Items = Items, Heroes = Heroes })
local function check(c, m) if not c then error("FAIL: " .. m) end end

-- Luau CLI has no Random: tiny LCG with the same method names.
local rng = {}
local seed = 1234
function rng:NextNumber()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
function rng:NextInteger(lo, hi)
	return lo + math.floor(self:NextNumber() * (hi - lo + 1))
end
local slots = { "w", "a", "t" }
local heroes = {}
for h in Heroes do table.insert(heroes, h) end
local counts, maxDmg, maxArm = { 0, 0, 0, 0, 0 }, 0, 0
for i = 1, 4000 do
	local slot = slots[i % 3 + 1]
	local r = rng:NextInteger(1, 5)
	local inst = Gear.generate(rng, { slot = slot, hero = heroes[i % #heroes + 1], ilvl = rng:NextInteger(1, 20), rarity = r })
	local clean = Gear.valid(inst)
	check(clean, "generated item validates")
	check(#clean.a == #inst.a, "affix count survives validation")
	local d = Gear.describe(clean)
	check(d.name and #d.name > 2, "name")
	check(d.rarityIndex == r, "rarity")
	check(d.sell >= 2, "sell value")
	if slot == "w" then check(d.damage >= 3, "weapon damage") maxDmg = math.max(maxDmg, d.damage) end
	if slot == "a" then check(d.armor >= 0.5, "armor") maxArm = math.max(maxArm, d.armor) end
	if slot == "t" then check(#clean.a >= 1, "trinket has an affix") end
	counts[r] += 1
	-- tampering must be rejected
	local bad = Gear.valid({ s = slot, t = 99, r = r, l = 5, q = 5, n = 5, a = {}, h = "Knight" })
	check(bad == nil, "tier out of range rejected")
	local bad2 = Gear.valid({ s = slot, t = 1, r = 1, l = 5, q = 5, n = 5, a = { { "dmg", 5 }, { "crit", 5 }, { "leech", 5 }, { "ult", 5 } }, h = "Knight" })
	check(bad2 == nil, "too many affixes rejected")
end
check(Gear.valid({ s = "a", t = 1, r = 5, l = 5, q = 5, n = 5, a = { { "dmg", 5 } } }) == nil, "weapon affix on armor rejected")
check(Gear.valid({ s = "w", t = 1, r = 2, l = 5, q = 5, n = 5, a = { { "dmg", 5 } }, h = "Nobody" }) == nil, "unknown hero rejected")
check(Gear.valid({ s = "w", t = 1, r = 2, l = 5, q = 5, n = 5, a = { { "dmg", 5 }, { "dmg", 6 } }, h = "Knight" }) == nil, "duplicate affix rejected")
check(Gear.valid("iron_sword") ~= nil and Gear.valid("iron_sword").b == "iron_sword", "legacy id converts")
check(Gear.valid("healing_draught") == nil, "potion is not gear")
check(Gear.valid({ b = "nope" }) == nil, "unknown base rejected")
check(Gear.valid(12) == nil and Gear.valid(nil) == nil, "garbage rejected")
local starter = Gear.describe(Gear.fromBase("iron_sword"))
check(starter.damage == 6 and starter.slotKey == "w", "base item stats")
check(Gear.usableBy(Gear.fromBase("iron_sword"), "Knight") and not Gear.usableBy(Gear.fromBase("iron_sword"), "Wizard"), "class weapon restriction")
check(Gear.usableBy(Gear.fromBase("moonsteel_sword"), "Wizard"), "generic weapon usable by all")
print("max weapon damage", maxDmg, "max armor", maxArm, "rarity counts", table.concat(counts, ","))
print("gear OK")
