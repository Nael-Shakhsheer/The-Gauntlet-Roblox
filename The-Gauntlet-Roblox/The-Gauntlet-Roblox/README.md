# The Gauntlet — Roblox port (Adventure mode)

3D, up-to-4-player co-op port of the browser game
[The-Gauntlet](https://github.com/Nael-Shakhsheer/The-Gauntlet), synced into Roblox Studio with Rojo.
Current sync status: see `PORT_STATE.md`.

## One-time setup
1. Tools: `rokit install` (installs Rojo from `rokit.toml`), then `rojo plugin install`. Restart Studio.
2. Studio: create a new place from the **Baseplate** template and save it anywhere
   (the server deletes the Baseplate at runtime; areas build themselves).
3. Studio → Home → Game Settings → Players → **Max Players = 4**.

## Run it
1. In this folder: `rojo serve`
2. Studio → Plugins → Rojo → **Connect**
3. Press **Play**. Multiplayer test: Test tab → Clients and Servers → 2-4 players → **Start**.

Controls: **E** talk / inspect / shop / rest / travel. **1-6** (or click the hotbar) cast your six abilities:
1-2 Lights (also **left / right click**, hold to repeat), 3-4 Specials, 5-6 Ultimates; Specials and Ultimates cost mana.
**Hero** button re-opens class select.

Grind loop (port-only, not in the 2D game): kill enemies for **XP + runes**; levels raise health and damage and unlock
harder areas (red barriers show "Requires level N"); spend runes at the **Outfitter** in Oakvale/Dunmere on weapons
and armour (level-locked by rarity). Enemies respawn after 90 s, so farming works. Rest at an **inn bed** to heal and
set your respawn. **Waystones** (villages + attuned travel shrines) fast-travel between visited villages and shrines.
Quest chain (hunter -> bridge -> shrine guardian -> Minotaur King) is tracked top-left.
The world is one continuous map: just walk. Trails link every area (signposts name the destination);
the Rootwater cave is underground (ramps down from the road east end and the clearing west edge);
Briarwatch tower has 3 floors (door from the camp, stairs inside, ramp down from the roof to the bridge east bank).

## Layout
```
src/shared/   Config, Palette, Coord (px<->studs), Make, Remotes, WorldLayout (pure-Luau world plan), Data/
src/shared/Data/Generated/   AUTO-GENERATED from the 2D game's Python. Do not edit.
src/server/   Progress (xp/levels/runes/shop), Quests, Interactions, Stats, Fallen, Companions, WorldService, WorldBuilder (ground/trails/caves/tower), AreaBuilder (area contents), EnemyService, EnemyModels, CombatService, HeroService, State, Main
src/client/   Main.client (HUD, hero select, dialogue, input)
tools/export_data.py   Python constants -> Luau modules
tests/check_data.luau    Plain-Luau checks of the generated data (`luau tests/check_data.luau`)
tests/check_progression.luau  Prints the grind curve (kills per level gate, gear prices)
tests/check_layout.luau  World layout checks: no overlaps, everything reachable (`luau tests/check_layout.luau`)
```

## Updating from GitHub
Ask Claude: "update the Roblox game from GitHub". It fetches the repo, re-runs the exporter, ports changed logic,
and bumps the commit in `PORT_STATE.md`. Manual data refresh only:
```
git clone https://github.com/Nael-Shakhsheer/The-Gauntlet ../The-Gauntlet     (or git pull)
python tools/export_data.py ../The-Gauntlet
```

## Scale
Two factors in `Config.lua`:
- `STUDS_PER_PX = 0.125` combat/body: Knight 145 px/s = 18 studs/s, bow 300 px = 37.5 studs.
- `WORLD_STUDS_PER_PX = 0.3` world layout: compact area 960x540 px = 288x162 studs, Crossroads 576x324 studs.
  Map grid cell = `WORLD_CELL_PX` (2600x1800 px = 780x540 studs). Whole world is about 2800x3400 studs
  (roughly 2.5-3 minutes to run corner to corner). Retune with those numbers; run `tests/check_layout.luau` after.

## Known limits (see PORT_STATE.md)
Enemies walk through walls (no pathing yet). Level gates are the only passage locks. No saving yet (progress resets
when the server closes). Specials are instant hits (no projectile travel).

## Saving
Enable Studio API access (Game Settings > Security) and publish the place once; progress (level, xp, runes, gear, hero) then persists per player.

## Controls
WASD move, Shift sprint, LMB/RMB Light attacks, 1-6 abilities, E interact, Z X C V B N M potions, H help.
