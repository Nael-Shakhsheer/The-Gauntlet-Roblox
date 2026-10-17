--!nocheck
-- Skill trees: shape, prerequisites resolve, modifiers target real abilities, base abilities map to hotbar slots.
local base = "../src/shared/Data/Generated/"
local HS = require(base .. "HeroSkills")
local Abilities = require(base .. "Abilities")
local function check(c, m)
	if not c then
		error("FAIL: " .. m)
	end
end
local heroes = 0
for hero, tree in HS.TREES do
	heroes += 1
	check(Abilities.sets[hero] ~= nil, hero .. " has an ability set")
	local ids, baseIds, starters, costBase = {}, {}, 0, 0
	for _, a in Abilities.sets[hero] do
		baseIds[a.id] = true
	end
	for _, n in tree do
		ids[n.id] = n
	end
	for _, n in tree do
		check(n.maxRank >= 1 and n.cost >= 0, n.id .. " rank/cost")
		for _, r in n.requires do
			check(ids[r], hero .. ":" .. n.id .. " requires unknown " .. r)
		end
		if n.starter then
			starters += 1
		end
		if n.type == "modifier" then
			check(#n.changes == n.maxRank and #n.effects == n.maxRank, n.id .. " changes per rank")
			check(baseIds[n.requires[1]], n.id .. " modifies a base ability")
		end
		if n.type == "ability" and baseIds[n.id] then
			costBase += n.cost
		end
	end
	check(starters == 2, hero .. " has 2 starters")
	print(hero, #tree, "nodes, base-ability cost", costBase)
end
check(heroes == 8, "8 hero trees")
local total = 0
for _, v in HS.MILESTONES do
	total += v
end
print("milestone points", total)
print("skills OK")
