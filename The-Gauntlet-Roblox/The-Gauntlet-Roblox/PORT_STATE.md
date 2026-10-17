# Port state — The Gauntlet → Roblox (Adventure mode only)

Source repo: https://github.com/Nael-Shakhsheer/The-Gauntlet
**Last synced commit: `16d35ec`** (2026-10-16, "Update Adventure systems, Ascension, artwork, audio and performance")

Layout: `WorldLayout.luau` places areas from 2D `pos` on a grid (cell `WORLD_CELL_PX`); `caravan` (opening only) is skipped.

Scope: Adventure mode only (Gauntlet mode is out of scope). Full 3D, 1-4 player co-op.
Art: blocky "voxel" style built from Parts, using the 2D game's palettes.

## How updates work
1. Claude fetches the GitHub repo and diffs it against the commit above.
2. `python tools/export_data.py <checkout>` regenerates `src/shared/Data/Generated/` (data only).
3. Claude ports changed *logic* by hand into `src/server`, `src/client`.
4. This file is updated with the new commit hash and what changed.

## Ported (data — auto-synced by the exporter)
Heroes, ability records, items, enemy stats/affinities, Adventure areas / exits / groups / features / dialogue pages,
region content (woodland expansion, Dunmere), dungeon specs/walls/packs, hero skill trees, progression, Ascension,
Magic Runes, Soul Crystal, awareness/respawn constants, tactical rules (+ 20 more modules in `Data/Generated/`).

## Ported (logic) — playable slice
| System | Status | Notes |
|---|---|---|
| Connected world (27 areas) | Partial | One continuous map: trails + signposts between areas, cave underground via ramps, 3-floor tower with stairs/roof exit. No bridge river, shrine hazards, interiors |
| Area tracking / lighting | Done | Per-player area banner + mood (client lighting) |
| Quest-gated passages | Not yet | Trails open; needs blockers on trails |
| Hero select (8 classes) | Done | HP / speed / colour / weapon applied |
| Abilities (all 6 per hero) | Partial | Lights, Specials, Ultimates, mana (100; +6/s peace, +2/s combat), cooldowns, hotbar. Stun/root/bleed/ward/boost/taunt/invisible/heal/revive/blink/dash/rain of arrows done. Instant hits (no projectile travel), no skill-tree/rune modifiers |
| Druid summons | Partial | Bird/Wolf/Bear/Golem follow + attack; timed (25 s), enemies ignore them |
| Fallen / revive | Partial | 15 s down, ally revive abilities work, party wipe returns everyone |
| Outdoor enemies (5 families) | Partial | Wake/sleep by player distance (`ACTIVE_STUDS`). Aggro, leash, return, melee + ranged. No `!`/`?` awareness, roles, terrain avoidance |
| Quests (hunter, bridge, shrine, ruins) | Partial | Chain works; shrine puzzle skipped (altar wakes Stone Guardian), Minotaur King boss, rewards. Not saved |
| Villages | Partial | Runner dialogue, Outfitter shop, inn beds (heal + respawn), waystones/travel shrines (attune by clearing guards) |
| Grind system (PORT ADDITION) | Done | XP, levels 1-20, runes, level-gated areas, gear shop, enemy respawns. See `Config.luau` + `tests/check_progression.luau` |
| Dialogue pages | Done | 2D text via PAGES / RegionContent.TEXT |
| HUD | Partial | HP, area name, dialogue, damage numbers |

## Not ported yet
- Inventory/consumables (draughts, tonics), item loot drops, Magic Runes, Soul Crystal
- Last Caravan opening, Dunmere chapter (chapter_flow), shrine rune puzzle, sealed boss encounters
- Dungeons (Rootwater cave troll, Briarwatch tower waves), puzzles (shrine rune puzzle)
- Skills / Ascension / Magic Runes (data only), Soul Transport Crystal
- Wipe penalty (40% runes), cottage recovery, guild class change
- Saving (DataStore), audio (needs asset uploads), sprite portraits/icons (needs uploads)
- Dash

## Next up (suggested)
1. DataStore saving (levels, runes, gear, quests, attunements) - needed now that progress is a grind
2. Dungeons: Rootwater cave troll, Briarwatch tower waves, dungeon mechanisms/treasure
3. Dunmere chapter chain (fields, mill, cellar), consumables + inventory
4. Skills / Ascension / Magic Runes, shrine puzzle, awareness cues
5. Audio, portraits/icons, polish


## Villages (added)
- `server/VillageBuilder.luau`: Oakvale (crescent layout) + Dunmere (western_common) from TownLayout export: enterable 20x16 houses (inn/store/lab/guild/cottage/lodge) w/ door, windows, stepped roof, sign, furniture, service NPC (decor only); dirt roads + cobble plaza; ambient villagers. Store stall + Inn bed features moved inside buildings (`AreaBuilder.features`). 2D re-rolls layout per run; port fixed.
- TODO: NPC dialogue for innkeeper/merchant/alchemist/guildmaster, lab/guild/lodge/cottage services (not ported), exit-road alignment check in Studio.

## Saving (added)
- `server/Persistence.luau`: DataStore `GauntletProfiles_v1`, key `p_<UserId>`. Saves level/xp/runes/weapon/armor/hero. Load on join (spawn waits via `Persistence.waitLoaded` in Fallen), autosave 60 s, save on leave (`Progress.onDrop`) + `BindToClose`. Load failure => saving disabled for that session (never overwrites).
- Studio: Game Settings > Security > "Enable Studio Access to API Services" must be ON (and game published/saved to Roblox) or saving is skipped with a warning.
- NOT saved: quests, attuned shrines, discovered areas, claimed chests (per-server, party-level). TODO.

## Open-world pass + village services (2026-10-17)
World
- `shared/Sizes.luau`: wilderness areas enlarged (road 1.3, crossroads/clearing/fields 1.5, hollow/brook/eastern 1.4, ...). Hubs/camp/ruins/dungeons keep 2D size (absolute px walls/landmarks).
- `WorldLayout.compute`: after grid placement, surface areas are *compacted* (constraint relaxation): linked pairs sit 190-415 studs apart (hash per pair), `Config.OPEN_LINKS` pairs touch and flow into each other with no trail (home|road, camp|yard, hollow|watch, dunmere|border, fields|mill, mill|cellar). Caves follow the surface they hang under; tower is placed after compaction. `WorldLayout.curve` = Chaikin-smoothed route + fading sine meander => winding trails (`trail.curve`).
- `server/Scenic.luau`: dirt strip with grass verge, roadside trees/rocks/flowers, benches+lanterns, wayside shrines, cairns, logs, ponds; `openSpace` adds ponds/meadows/groves/boulders/standing stones to large areas.
- tests/check_layout: open pairs flush, trails don't cross unrelated areas, tunnels don't cut chambers, curve ends match.
Villages
- `server/Services.luau` + `VillageBuilder.features`: NPCs inside buildings. Innkeeper (goal + next gate advice), Merchant (shop), Alchemist (potion shop -> pouch, Z X C V B N M), Guildmaster (repeatable bounty: slay N foes of danger>=X for runes+XP, shown in tracker), Guild registry board (hero change; changing hero now requires it, first pick free), Mara cottage (5 runes full heal+mana), Lodge hunter (where to hunt at your level), 5 plaza villagers with tips.
- Potions drop from kills (5%+1.5%/danger, bosses always). Pouch saved in DataStore.
- Port UX: sprint (Shift, x1.4 outside combat), HUD gold-arrow objective compass (`Quests.target`), controls help (H).

## Dev audit - what the game needs next (priority order)
1. **Verify in Studio** (nothing has been playtested): world loads, trails, villages, abilities, quests, shop. Biggest risk = part count/perf: crossroads etc. have ~800 props; check Microprofiler, consider merging scenery (UnionOperation/MeshPart or fewer parts per tree) and CollectionService LOD.
2. **Combat feel**: instant-hit abilities with no projectiles/VFX/sound; no enemy wind-up telegraphs (2D backlog item 1/2). Add projectile tweens, hit sparks, telegraph rings, SFX. Highest fun-per-effort.
3. **Enemies pass through walls/props**: use PathfindingService or simple steering + collisions on scenery; leash resets.
4. **Quest/world persistence**: only personal progress saves; quests/attuned shrines/chests reset per server. Needs party-level save (or per-player quest state) + reserved servers.
5. **Remaining 2D content**: Rootwater cave troll + Briarwatch wave dungeons, Dunmere chain (fields/mill/cellar), shrine rune puzzle, Last Caravan opening, skills/ascension/magic runes, soul crystal, wipe penalty.
6. **Navigation**: add a world map (M) + minimap; compass only covers the main quest.
7. **Economy balance**: playtest the grind curve (tests/check_progression has the numbers); bounty reward vs kill reward; potion prices (x2 of 2D).
8. **Onboarding**: help panel done; add first-quest NPC marker (!), tooltips on level-gate barriers.
9. **Mobile/controller**: hotbar + potion bar are tappable; add sprint button and thumbstick-aim friendly interact.
10. **Audio/art**: music per region, portraits, nicer NPC models (uploaded meshes), day/night.

## Phase 1 (F -> D) progress, 2026-10-17
Done (offline-verified only: compile, rojo build, 3 tests):
- Enemies blocked by world geometry (raycast vs Workspace.World, slide along obstacles, knockback respects walls).
- Enemy attacks have a 0.4-0.55 s red telegraph (ground disc + aim line for ranged); stuns interrupt the attack; damage lands only if you are still close.
- Hit flash (Highlight) + small knockback on non-bosses.
- Client feel: camera shake on damage/ultimates/level-up, procedural arm swing on cast, sound hooks (`shared/Sounds.luau`, ids EMPTY - paste ids of audio you upload), HUD UIScale for phones/small windows.
- Perf: decor no longer casts shadows, CanTouch off everywhere, trees 5->3 parts, flowers 2->1 part, ground tiles 16->24 studs, roadside density x0.7. Server prints `[Gauntlet] world built: N parts` at boot - report that number.
- Quest "!" markers over the current objective (QuestMarker billboards toggled by Quests.broadcast).
Still needs YOU in Studio (blocking for exit criteria):
- Play + Local Server (2-4 clients): paste the Output log; report FPS (F9 / MicroProfiler) in Oakvale, Crossroads, Southern road.
- Sounds: upload audio, fill `Sounds.IDS`.
Not done in Phase 1 yet: projectile travel visuals, enemy walk animations, boss-specific telegraphs, proper pathfinding around large obstacles (enemies can still get stuck behind houses until they leash).

Phase 1 follow-ups (same day): enemy bob animation; steering around obstacles (45/90/135 deg turns); boss ground slam (0.9 s telegraph, radius x1.8, hits everyone inside, x1.5 dmg, 40% of boss melee attacks); ranged abilities show a travelling orb + fading trail (hits still instant); client impact sparks on every hit.
Phase 2 start: world progress now persists - each profile stores quests/shrines/discovered/claimed/kit; on join it is MERGED into the server (furthest quest step wins, sets unioned).

Phase 2 · dungeons (DungeonService.luau): cave troll den (bell/seal at cave_heart -> Rootwater Cave Troll, hp 360 boss slam) + Briarwatch tower (floor bells; floors 1-2 two waves w/ 3 s break from FLOOR_PACKS/SPOTS; floor 3 Minotaur Captain + serpent guards). All living hunters must be within 60 studs of the bell. "Seal" = participants pushed back if they leave; attempt resets if all fall/leave 6 s. Floor N+1 closed until N cleared (push-back). Rubble across cave_heart->clearing and barricade at tower_3 exit removed on completion. Cave crates (cave_supplies/cave_survey) give runes+xp+potion. Completion saved in State.claimed (dg:cave, dg:tower:f1..f3) -> persists with profile. Rewards (runes/xp/potion) are port-tuned, not 2D values (class_weapon not ported). Untested in Studio.

Phase 2 · Dunmere chain (Dunmere.luau, hooked in Quests): after woodland done, Dunmere runner gives failed_harvest -> irrigation -> mill_cellar -> outcome (State.quests keys; evidence in State.claimed "ev:*"; both persist). Fields clues, mill channels (need mill approach guards dead) + sluice, cellar_begin (cellar approach dead) -> sealed Blighted Overseer (hp 420 boss via DungeonService "cellar"), ledger, restored field. Report auto-accepts next stage; objective HUD + compass + "!" markers cover it. Rewards port-tuned. Not ported: fields->cellar hatch gating, Journal UI, Magic Rune report rewards. Untested in Studio.

Phase 2 · shrine puzzle (ShrinePuzzle.luau): altar now starts the rune puzzle instead of waking the guardian. 6 neon rune pads + totem (ProximityPrompt) appear in the shrine glade (positions from puzzles.py grid). Each living hunter in the glade has a target rune; totem clue is for the NEXT hunter (solo: own), so parties must share. All standing on their own rune -> pads vanish, Stone Guardian spawns. Differs from 2D: one shared chamber (2D gives each player a private chamber). Untested in Studio.

Phase 2 · Last Caravan opening (OpeningService.luau): new worlds (no quest progress, claimed.opening unset) spawn on a separate caravan road built west of the map (State.areas.caravan registered). arrival 8 s -> road wolves -> flank pack -> dragon message -> gate/muster circle -> all alive at circle -> Oakvale + caravan_aftermath dialogue. No XP/drops (EnemyService noReward/noLeash flags). Guard-arrow support budget 28 dmg. Wipe resets the arena; dead players re-enter via spawn hook. Wagon prompt "Skip the opening" (hold 2 s, for testing). Completion persists (claimed.opening). Mid-opening progress not saved. Untested in Studio.

Playtest fix 1: ground flicker = z-fighting (trail verge top .22 vs area tiles .2, overlapping segments sharing planes) -> verge/trail lifted (.3/.5) and staggered per segment. Attacks: added visible neon slash arc (+ ground ring for special/ultimate) client-side. Opening: HUD objective + compass to muster circle so the walled caravan road is understood; hold E at wagon to skip.

Ability visuals (client/AbilityFx.luau): every one of the 48 abilities now has its own effect matching its 2D description. Server (CombatService) fills ctx.fx (targets hit, radius, allies, from/to, chain, fallen...) and fires Remotes.AbilityFx to all clients after each successful cast; old generic server beams/rings are off (LEGACY_FX=false). Client draws: held props (shield, sword, staff, bow, flask, dagger, lute, wand), arm poses (local player only - joint changes do not replicate), slashes, shockwaves/cracks/debris (Earthshaker), domes/columns (wards/buffs), bolts, chain lightning, ice shards, vines, rain of arrows w/ markers, summon portals, music notes, heal glyphs, revive pillars. Visual-only; needs Studio tuning (prop orientation on R15 hands, sizes). Real animations would need uploaded animation assets.

Phase 2 · Skills v1 (server/Skills.luau, client/SkillsPanel.luau, K or "Skills" button): exporter now exports hero_skills TREES (8 heroes x 15 nodes; re-run exporter). Points = milestone points (arrival 2 at start, road, inn talk, hunter, bridge, shrine, cave crate, cave, tower floors, region = 20 total, derived live from State/claimed/quests) + 1 per 4 levels (port addition, Config.LEVEL_POINT_EVERY). Starters (hotbar slots 1 and 3) free; other base abilities cost 1/1/3/3, ranked modifiers cost 1 per rank and merge their `changes` into the ability record (Skills.ability; only fields the effect reads matter: range/power/cooldown/duration...). Locked abilities cannot be cast (hotbar dimmed "locked"). Train/respec only in hubs (Oakvale/Dunmere); hero change resets ranks. Ranks saved in profile (`skills`, validated by Skills.restore; invalid -> reset). `claimed.inn` set when the innkeeper talks. NOT in v1: 3 new-active nodes + 3 passives per hero (shown "soon", cannot be bought; need the new cast kinds in SkillCasts.KINDS), loadout limits (2D: basic + 3 active + 1 ultimate; here all 6 slots once trained), Ascension, Magic Runes. Test: tests/check_skills.luau. Untested in Studio.

Visual overhaul: plan in VISUAL_PLAN.md (V1-V7). V1 done (untested in Studio): Future lighting (default.project.json), per-region profiles in Palette.Regions (material/atmo/bloom/cc/sun/clouds/particles), client/Atmosphere.luau (Atmosphere, Bloom, ColorCorrection, SunRays, Sky, Clouds, camera-following ambient particles; replaces the old Lighting tween in Main.client), ground tiles + wilderness use real materials, 3 tree species + dead/snow trees, bushes/tufts/flowers/mushrooms/ferns/logs/rubble/stalagmites/glow mushrooms/ice crystals (AreaBuilder DETAIL scatter, Config.DETAIL_DENSITY knob). Watch part count + FPS; lower DETAIL_DENSITY if needed.
