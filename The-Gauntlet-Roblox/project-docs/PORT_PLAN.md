# Gauntlet -> Roblox port plan

Source: github.com/Nael-Shakhsheer/The-Gauntlet (public). Python stdlib server + JS canvas client. ~17k lines.
Last synced commit: 16d35ec (2026-10-16). Live status lives in `PORT_STATE.md` inside the Rojo project folder.
Target: full 3D multiplayer (1-4 players), Rojo-synced. **Adventure mode ONLY** (Gauntlet mode dropped, user decision 2026-10-16).
Art: blocky voxel/Part-built models, palettes sampled from the 2D game ("do as you see fit").

## Local project
`C:\Users\nael_\Documents\Roblox\The-Gauntlet-Roblox` (Rojo 7.7.1 via Rokit; `rojo serve`, Studio plugin Connect).
Verified without Studio: real `rojo build` OK, all Luau compiles, tests pass (`check_data`, `check_layout`, `check_progression`).
In-Studio behaviour of the world, abilities, quests, shops, villages and saving is NOT yet confirmed by the user.

## Architecture
- Data (auto): `tools/export_data.py <gauntlet checkout>` imports the Python modules and writes Luau to `src/shared/Data/Generated/`. Rerun every update.
- Logic (manual port): `src/server` (WorldService, WorldBuilder, AreaBuilder, VillageBuilder, Scenic, Services, EnemyService, CombatService, Companions, Stats, Fallen, HeroService, Progress, Persistence, Quests, Interactions), `src/client` (HUD, hotbar, potion bar, compass, shop/travel panels, level gates, per-player lighting).
- **Connected world**: `src/shared/WorldLayout.luau` (pure Luau) places every area from 2D `pos` on a grid, then COMPACTS it (linked areas 190-415 studs apart, `Config.OPEN_LINKS` pairs touch with no trail). Trails are winding scenic curves (`WorldLayout.curve`, `Scenic.luau`). Cave = underground layer via 2 ramps, Briarwatch = 3 stacked floors. `caravan` skipped. ~3500x2700 studs. Wilderness areas are enlarged by `shared/Sizes.luau`.
- Scales: `STUDS_PER_PX=0.125` combat; `WORLD_STUDS_PER_PX=0.3` layout.
- Enemies wake/sleep by player distance; StreamingEnabled on.
- One Roblox server = one party = one Adventure world.

## PORT ADDITIONS (differ from the 2D game, user decisions)
- **Grind system (2026-10-17)**: kills give XP + runes; levels 1-20 (+6% hp, +4% dmg per level); areas need a minimum level by danger (`Config.LEVEL_BY_DANGER`: 1/1/1/3/5/8/11/14), enforced by client-local barriers + server pushback; Outfitter sells weapons/armour for runes (2D price x3, level-locked by rarity); ordinary enemies respawn after 90 s (2D: 10 min). Tune in `Config.luau`.
- **Villages**: enterable houses (Inn, Store, Alchemy Lab, Guild, Cottage, Lodge) with services: innkeeper advice, merchant shop, alchemist potions (pouch, Z X C V B N M), guildmaster repeatable bounties, Guild board (hero change; first pick free), Mara cottage heal (5 runes), lodge frontier guide, villagers with tips. Potion drops from kills.
- **Open world**: large open areas (ponds/meadows/groves/standing stones), winding trails with roadside scenery, some areas open straight into each other.
- Sprint (Shift), objective compass, controls help (H).
- **Saving**: DataStore `GauntletProfiles_v1` per player (level, xp, runes, gear, hero, pouch) + world progress copy (quests, shrines, claimed, discovered).

## Update workflow (every GitHub change)
1. Fetch repo, `git diff <last synced commit>..HEAD`.
2. Re-run exporter (data) and port changed logic by mapping file -> service.
3. Re-run tests. `rojo serve` -> Studio auto-syncs. Update PORT_STATE.md commit hash.

## Source -> Roblox map
| Python/JS | Roblox |
|---|---|
| game.py constants, `_cast_ability` | Data/Generated (auto), CombatService, client/AbilityFx |
| adventure.py (quests, features), region_content.py | Quests, Dunmere, Interactions, WorldLayout / WorldBuilder / AreaBuilder |
| dungeons.py | DungeonService |
| puzzles.py | ShrinePuzzle |
| opening.py | OpeningService |
| town_layout.py, game.py town NPCs, cottage.py | VillageBuilder, Services |
| village_portals.py, soul_crystal.py | Interactions (waystone travel; crystal not ported) |
| enemy_awareness.py, enemy_roles.py, boss_ai.py | EnemyService (+ future AI modules) |
| companion_ai.py (Druid summons) | Companions |
| hero_skills.py, skill_casts.py, tactical_rules.py | future Skills |
| progression.py, ascension.py, magic_runes.py | future Skills/Runes |
| *_storage.py, save_portability.py | Persistence (personal progress + world copy) |
| static/*.js UI | src/client |
| static/audio, music | needs Roblox asset uploads |

## Dev audit - next priorities
1. Playtest in Studio (nothing verified in-engine); watch part count/perf in big open areas.
2. Combat feel polish (SFX needs uploaded audio; real animations need uploaded assets).
3. Remaining 2D content: skills/ascension/runes, inventory/loot, soul crystal, wipe penalty.
4. World map + minimap.
5. Economy balance pass from playtest data.
6. Onboarding markers; mobile sprint button.
7. Audio, portraits, better NPC models.

## Open questions
- Asset uploads (audio/sprites) - user must upload to Roblox, or provide IDs
- Hosting: reserved servers per party vs public servers
