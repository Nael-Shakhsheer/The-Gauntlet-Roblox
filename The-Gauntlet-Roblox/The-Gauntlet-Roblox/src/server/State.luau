--!nonstrict
-- Shared server state for the single Adventure party (one Roblox server = one party).
-- TODO(persistence): move defeated/claimed/quests into DataStore-backed saves.
local State = {
	layout = nil, -- WorldLayout result (rects, trails, ramps)
	areas = {}, -- id -> { rect, origin, widthPx, heightPx, folder, region, kind }
	spawn = nil, -- Vector3 where players (re)spawn
	playerArea = {}, -- Player -> area id they are standing in (nil = open wilderness)
	discovered = { home = true },
	defeated = {}, -- areaId -> { [enemyId] = true }  (os.clock() time of death; ordinary enemies respawn, see EnemyService)
	sites = {}, -- enemyId -> { group, x, z } spawn spot, for respawns
	awake = {}, -- areaId -> true while its enemies are spawned
	enemies = {}, -- enemyId -> enemy record, awake areas only
	fallen = {}, -- Player -> { pos, at } while waiting to be revived or to return
	reviveAt = {}, -- Player -> { pos, fraction } consumed by the next spawn
	companions = {}, -- Player -> { [abilityId] = companion record } (Druid summons)
	heroes = {}, -- Player -> hero class name
	cooldowns = {}, -- Player -> { [slot] = os.clock() ready time }
	quests = { hunter = "new", bridge = "new", shrine = "new", region = "new", failed_harvest = "new", irrigation = "new", mill_cellar = "new", outcome = "new" }, -- new | active | done
	flags = { kit = false }, -- quest items/switches (repair kit...)
	claimed = {}, -- feature key -> true for one-time chests and discoveries
	respawn = {}, -- Player -> Vector3 inn bed they last rested at
	attuned = {}, -- shrine key -> true once its guards fell and the waystone was attuned
	waystones = {}, -- id -> { id, name, area, pos } (all waystones in the world)
	lastSafe = {}, -- Player -> last position where they were allowed (level-gate pushback)
	waystoneAt = {}, -- Player -> id of the waystone whose menu they opened
	bounty = {}, -- Player -> { need, have, minDanger, runes, xp, done } guild bounty
	shopMode = {}, -- Player -> "gear" | "potions" (which shop is open, for refresh after buying)
	heroChosen = {}, -- Player -> true once a hero was picked (later changes need the Guild)
	guildUntil = {}, -- Player -> os.clock() until which the Guild board allows a hero change
	sprint = {}, -- Player -> true while holding sprint
	featurePos = {}, -- feature key -> world position (quest waypoints)
	featurePosByArea = {}, -- area id -> feature key -> world position (keys repeat across areas)
	useAt = {}, -- Player -> last potion use time
}

return State
