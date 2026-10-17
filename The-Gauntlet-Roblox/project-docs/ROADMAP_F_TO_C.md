# The Gauntlet (Roblox) - 3-phase plan, F tier -> C tier

Written 2026-10-16. Honest baseline then: lots of systems exist but nothing confirmed in Studio, combat without feedback, content stopping after the Woodland chain, quests not saving.

## Tier definitions
- F: untested, no feel, thin loop.
- D: runs without errors, combat reads as combat, stable FPS, a stranger understands what to do. (end of Phase 1)
- C-: 30-60 min of content with a reason to return, progress persists, 2-4 players play together reliably. (end of Phase 2)
- C: looks/sounds/plays like a finished small indie Roblox game: consistent art, audio, mobile works, safe to publish. (end of Phase 3)

## PHASE 1 - "It runs and it feels like combat" (F -> D)
1. Studio verification pass (blocking): rojo serve, Play + Local Server 2-4 clients, walk the whole path, fix every Output error. Needs Output log + screenshots from you.
2. Performance budget: merge props, CastShadow off on scenery, cap enemy simulation, pool damage GUIs. Targets 60 fps PC / 30+ mobile.
3. Combat feel: projectiles, hit sparks, flash + knockback, camera shake, telegraphs, attack/cast animations, sound (needs your uploaded audio ids).
4. Enemy behaviour: steering around walls, leash/reset, walk/attack tweens.
5. Clarity & onboarding v1: quest markers, level-gate signage, objective compass, controls panel, respawn messaging, HUD scale.
Exit (D): 20 min solo + 2-player run with zero script errors, steady FPS, every ability visibly does something, no wall-clipping, new player reaches first boss unaided.

## PHASE 2 - "Something to do, together, that saves" (D -> C-)
1. Finish the Adventure spine: Rootwater troll dungeon, Briarwatch waves, Dunmere chain, shrine rune puzzle, Last Caravan opening, boss mechanics, wipe penalty + recovery, soul crystal.
2. Character growth: Skills / Ascension / Magic Runes, gear with loot drops, inventory UI, profile schema v2.
3. Persistence and parties: party-level state, schema versioning, session locking, TeleportService party/lobby.
4. Economy and difficulty tuning from playtests.
5. Navigation: world map (M), minimap, fast-travel clarity.
Exit (C-): ~45 min playable (Woodland + Dunmere chain + a dungeon, level ~12), progress survives restart, 3-4 friends complete a boss together.

## PHASE 3 - "Make it look, sound and ship like a game" (C- -> C)
1. Art direction pass (uploaded meshes/textures, lighting, skybox, portraits, ability icons).
2. Audio: music per region/boss, ambience, SFX set, volume menu.
3. UI/UX polish: theme, tooltips, inventory/skills screens, mobile layouts + virtual buttons, gamepad, accessibility.
4. Production readiness: remote validation/rate limits, telemetry, publishing (page, icons, age rating, moderation, monetization decision).
5. QA and soft launch: 4-player soak, low-end device, exploit, profile corruption tests; soft launch to friends.
Exit (C): stable 60/30 fps, consistent art + audio, mobile playable, no data-loss bugs, first-time player completes opening unaided.

## What I need from you
- Phase 1: Studio Output logs/screenshots, FPS, feel notes.
- Phase 2: playtests with friends, party/server model decision.
- Phase 3: uploaded audio/meshes/icons (or IDs), monetization and age rating.

## Order
Studio verification -> perf -> combat feel -> enemy behaviour -> dungeons/Dunmere -> skills/inventory -> persistence/parties -> balance -> art/audio -> mobile -> publish.

---
Progress note (2026-10-17): Phase 1 combat-feel/enemy/perf items largely coded (untested in Studio); Phase 2 done so far: world-progress persistence, Rootwater + Briarwatch dungeons, Dunmere chain, shrine puzzle, Last Caravan opening, per-ability VFX. Remaining: skills/Ascension/Runes, inventory/loot, soul crystal, wipe penalty, map/minimap, parties.
