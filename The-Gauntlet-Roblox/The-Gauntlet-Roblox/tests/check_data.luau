--!nocheck
-- Plain-Luau sanity check for the generated data (no Roblox needed).
--   luau tests/check_data.luau          (Luau CLI: https://github.com/luau-lang/luau/releases)
-- Verifies the shapes the server code relies on. Re-run after every export.
local base = "../src/shared/Data/Generated/"
local function load(name)
	return require(base .. name)
end

local Adventure = load("Adventure")
local Dungeons = load("Dungeons")
local Region = load("RegionContent")
local Enemies = load("Enemies")
local Heroes = load("Heroes")
local Abilities = load("Abilities")
local Items = load("Items")
local Core = load("GameCore")
local Roles = load("EnemyRoles")

local function check(cond, msg)
	if not cond then
		error("FAIL: " .. msg)
	end
end

check(Adventure.LARGE_AREAS.hollow[1] == 1600, "region sizes merged into LARGE_AREAS")
check(Adventure.AREAS.brook ~= nil, "region areas merged into Adventure.AREAS")
check(Adventure.AREAS.tower_1.dungeon == "tower", "dungeon areas merged into Adventure.AREAS")
check(#Adventure.AREAS.home.exits[1] == 3, "exit = {to, edge, reverseEdge}")
check(Adventure.EXIT_OFFSETS["crossroads|camp"] ~= nil, "EXIT_OFFSETS keys are 'from|to'")
check(#Adventure.GROUPS.road[1] == 5, "group = {id, kind, x, y, number}")
check(#Adventure.FEATURES.home[1] == 5, "feature = {key, name, x, y, kind}")
check(Region.FEATURES.fields ~= nil and Dungeons.FEATURES.cave_heart ~= nil, "feature tables present")
check(Dungeons.SPECS.cave.name ~= nil and Dungeons.WALLS.tower_1 ~= nil and Dungeons.PACKS.cave_entry ~= nil, "dungeon tables")
check(type(Adventure.PAGES.adventure_tracks[1]) == "string" and type(Adventure.PAGES.adventure_tracks[2]) == "table", "PAGES = {title, {pages}}")
check(Core.difficulties.medium.multiplier ~= nil, "difficulties")
check(Roles.ROLES.serpent == "ranged", "enemy roles")
check(Enemies.affinities.Nature ~= nil, "affinities")
check(Heroes.Knight.hp ~= nil, "heroes")
check(Items.classWeapons.Wizard ~= nil, "class weapons")
local wizard = Abilities.sets.Wizard[1]
check(wizard.attackType == "light" and wizard.chainTargets ~= nil, "ability records carry tactical details")
for hero, list in Abilities.sets do
	local lights = 0
	for _, ability in list do
		if ability.attackType == "light" then
			lights += 1
		end
	end
	check(lights == 2, hero .. " has two Light attacks")
end
print("OK: generated data shapes verified")
