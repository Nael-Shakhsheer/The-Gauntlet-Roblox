--!nocheck
-- luau tests/check_progression.luau : prints the grind curve (kills needed per level gate).
local Config = require("../src/shared/Config")
local A = require("../src/shared/Data/Generated/Adventure")
local I = require("../src/shared/Data/Generated/Items")
local function xpNext(l) local c = Config.XP_NEXT return math.round(c.base + c.scale * (l - 1) ^ c.power) end
local total = 0
local totals = { [1] = 0 }
for l = 1, Config.MAX_LEVEL - 1 do total += xpNext(l) totals[l + 1] = total end
local function check(c, m) if not c then error("FAIL: " .. m) end end
for danger = 0, 7 do
	local req = Config.LEVEL_BY_DANGER[danger]
	check(req and req >= 1 and req <= Config.MAX_LEVEL, "level for danger " .. danger)
end
print("gate level -> total xp -> kills at the previous tier (xp/kill)")
for _, step in { { 3, 2 }, { 5, 3 }, { 8, 4 }, { 11, 5 }, { 14, 6 } } do
	local level, danger = step[1], step[2]
	local xp = Config.XP_PER_KILL.base + Config.XP_PER_KILL.perDanger * danger
	print(("Lv %2d needs %5d xp = ~%3d kills of danger-%d foes (%d xp each)"):format(level, totals[level], math.ceil(totals[level] / xp), danger, xp))
end
for _, id in { "iron_sword", "oakguard_vest", "moonsteel_sword", "dragonbone_armor", "aegis_of_dawn", "starfall_blade" } do
	local it = I.items[id]
	local price = it.price * Config.SHOP_PRICE_MULT
	local perKill = (Config.RUNES_PER_KILL.min + Config.RUNES_PER_KILL.max) / 2 + Config.RUNES_PER_KILL.perDanger * 3
	print(("%-18s %-9s %4d runes (~%d kills at danger 3), needs Lv %d"):format(it.name, it.rarity, price, math.ceil(price / perKill), Config.GEAR_LEVEL[it.rarity]))
end
for id, spec in A.AREAS do check(Config.LEVEL_BY_DANGER[spec.danger] ~= nil, "area " .. id .. " danger has a level") end
print("OK: progression tables")
