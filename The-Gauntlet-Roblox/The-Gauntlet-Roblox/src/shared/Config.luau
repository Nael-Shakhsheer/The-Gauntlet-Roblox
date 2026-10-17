--!nonstrict
-- Tunable settings for the Roblox port of The Gauntlet (Adventure mode).
local Config = {}

-- The 2D game uses a 960x540 px compact area. 1 px = 0.125 studs keeps ranges
-- and speeds physically consistent: Knight 145 px/s = 18.1 studs/s, Archer
-- bow range 300 px = 37.5 studs, a compact area = 120 x 67.5 studs.
Config.STUDS_PER_PX = 0.125

Config.MAX_PLAYERS = 4 -- set the same value in Studio: Game Settings > Players
Config.DIFFICULTY = "medium" -- "easy" | "medium" | "hard" (see GameCore.difficulties)
Config.SPRINT_FACTOR = 1.4 -- hold Shift outside combat
Config.START_AREA = "home"
Config.DEFAULT_AREA_PX = { 960, 540 }

-- Quest-gated exits are not ported yet. true = every trail is open for testing.
Config.DEV_UNLOCK_ALL = true

-- Connected world. Layout (areas, trails) uses WORLD_STUDS_PER_PX; combat ranges and
-- speeds keep STUDS_PER_PX, so the world is ~2.4x roomier than the fights inside it.
-- Compact area 960x540 px = 288x162 studs; Crossroads 1920x1080 px = 576x324 studs.
-- Map positions (Adventure.AREAS[id].pos) are grid units; one cell = WORLD_CELL_PX.
Config.WORLD_STUDS_PER_PX = 0.3
Config.WORLD_CELL_PX = { 2600, 1800 }
Config.CAVE_DEPTH = 40 -- cave floor sits this far below the surface
Config.FLOOR_HEIGHT = 40 -- tower floors are stacked this far apart
Config.RAMP_SLOPE = 0.5 -- rise/run of ramps and stairs
Config.TRAIL_WIDTH = 16 -- trails, tunnels and ramps (also the wall gap width)
Config.TRAIL_STUB = 30 -- straight run leaving an area edge before a trail turns
-- Compaction: surface areas are pulled together after the grid placement. Linked pairs sit
-- TRAIL_GAP_MIN.. studs apart (a winding scenic trail fills the gap); OPEN_LINKS touch and
-- flow straight into each other with no trail. (road|crossroads and clearing|crossroads must
-- stay trails: cave ramps leave those edges.)
Config.TRAIL_GAP_MIN = 190
Config.TRAIL_GAP_VAR = 6 -- gap = MIN + (hash % VAR) * 45
Config.UNLINKED_GAP = 100
Config.OPEN_LINKS = {
	{ "home", "road" },
	{ "camp", "yard" },
	{ "hollow", "watch" },
	{ "dunmere", "border" },
	{ "fields", "mill" },
	{ "mill", "cellar" },
}

Config.TILE_STUDS = 24 -- ground tile size (pixel-art look)
Config.WALL_HEIGHT = 14
Config.CHUNK_STUDS = 1000 -- wilderness ground is built in slabs of this size
Config.WILDERNESS_PROP_STUDS2 = 5000 -- one scatter prop per this many square studs

-- Enemies wake when a player is within ACTIVE_STUDS of their area, and sleep again
-- (removed) when everyone is farther than ACTIVE_STUDS * 1.3.
Config.ACTIVE_STUDS = 260

-- Enemy behaviour (px values come from adventure.py).
Config.ENEMY = {
	AGGRO_PX = 150,
	LEASH_PX = 245,
	MELEE_RANGE_PX = 38,
	MELEE_INTERVAL = 1.0,
	RANGED_RANGE_PX = 200,
	RANGED_INTERVAL = 1.6,
	TICK = 1 / 20,
}

-- ----------------------------------------------------------------- grind
-- Port-only progression (not in the 2D game): kill enemies for XP + runes, level up to
-- unlock harder areas, spend runes on weapons and armour.
Config.MAX_LEVEL = 20
Config.XP_PER_KILL = { base = 8, perDanger = 5 } -- xp = base + perDanger * area danger
Config.XP_NEXT = { base = 30, scale = 22, power = 1.35 } -- to reach next: base + scale*(level-1)^power
Config.RESPAWN_SECONDS = 90 -- ordinary enemies return this long after dying...
Config.RESPAWN_CLEAR_STUDS = 50 -- ...if no player is this close to their spot (the 2D game waits 10 minutes)
Config.XP_SHARE_STUDS = 160 -- party members this close to a kill share its xp
Config.RUNES_PER_KILL = { min = 1, max = 3, perDanger = 1 }
Config.HP_PER_LEVEL = 0.06 -- +6% max health per level
Config.DAMAGE_PER_LEVEL = 0.04 -- +4% damage per level
-- Minimum level to enter an area, by its danger rating (adventure.AREAS[id].danger).
-- Combat feel (port additions)
Config.HERO_SWAP_ENABLED = false -- later mechanic: re-binding a hero (see claude/LATER_MECHANICS.md)
Config.BASE_MANA = 100
Config.LOOT_BASE_CHANCE = 0.07 -- per kill, personal to each player nearby
Config.LOOT_PER_DANGER = 0.015
Config.LOOT_PITY_KILLS = 18 -- guaranteed Rare+ after this many kills without one
Config.LOOT_PICKUP_STUDS = 7
Config.LOOT_LIFETIME = 120 -- seconds before an unclaimed drop is bagged for you
Config.CRIT_CHANCE = 0.1
Config.CRIT_MULT = 1.75
Config.COMBO_WINDOW = 3 -- seconds to land the next hit before the combo drops
Config.COMBO_STEP = 0.015 -- +1.5% damage per combo hit ...
Config.COMBO_MAX = 10 -- ... up to 10 hits (+15%)
Config.ULT_SHAVE_HIT = 0.3 -- every hit shortens Ultimate cooldowns by this many seconds (crit x2)
Config.DODGE_COOLDOWN = 1.1
Config.DODGE_IFRAMES = 0.4
Config.DODGE_SPEED = 62 -- studs/s during the roll (client)
Config.DODGE_TIME = 0.22
Config.DETAIL_DENSITY = 1.7 -- small ground detail multiplier (grass, flowers...). Lower (0.5) if FPS/part count suffers
Config.LEVEL_POINT_EVERY = 4 -- port addition: +1 skill point per 4 levels (on top of milestone points)
Config.LEVEL_BY_DANGER = { [0] = 1, [1] = 1, [2] = 1, [3] = 3, [4] = 5, [5] = 8, [6] = 11, [7] = 14 }
Config.OVERLEVEL_GRACE = 2 -- xp shrinks (floor 25%) 15% per level beyond area level + this
Config.SHOP_PRICE_MULT = 3 -- 2D prices x this (runes are earned by grinding here)
Config.GEAR_LEVEL = { Common = 1, Uncommon = 3, Rare = 6, Epic = 10, Legendary = 15 }

return Config
