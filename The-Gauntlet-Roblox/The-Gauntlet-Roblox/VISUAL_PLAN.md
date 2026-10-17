# The Gauntlet (Roblox) - World visual overhaul plan

Problem (user, 2026-10-17): no atmosphere, everything non-detailed and unpolished.
Root causes found in code: flat SmoothPlastic ground tiles, one fixed-colour fog/ambient tween, no post-processing, no sky/clouds, no ambient particles, 3-part trees, few prop types, villages are plain boxes, no light sources, no water, characters/enemies are untextured blocks.

Rules: stay readable as a pixel-art-inspired game (2D palette), keep part count + FPS budget (mobile 30+), everything procedural unless the user uploads assets.

## V1 - Atmosphere (DONE in this pass, untested in Studio)
- Future lighting (set in default.project.json), per-region profiles (Palette.Regions): sun angle, ambient, Atmosphere (density/haze/colour), Bloom, ColorCorrection (tint/contrast/saturation), SunRays, Sky + Clouds.
- Client Atmosphere module: tweens all of the above on area change; ambient particles that follow the camera (pollen/fireflies woodland, dust motes ruins, spores cavern, snow frost).
- Ground tiles use real materials per region (Grass / Sand / Slate / Snow) instead of plastic.
- Prop pass: 3 tree species (oak, pine, birch), bushes, grass tufts, flowers, mushrooms, logs, ferns, mossy rocks.

## V2 - Ground, terrain, water
- Replace flat slabs with Roblox Terrain (smooth grass + noise hills, cliffs at area edges, rivers/ponds with real Terrain water, shore sand). Requires ground-height lookup for spawns/enemies (raycast already used).
- Ground colour blending between regions, dirt patches, road cobbles, puddles.
- Wind: sway on foliage (client-side tween on tagged parts, distance-gated).

## V3 - Villages & structures
- Buildings: pitched roofs, windows with warm PointLights at dusk, chimneys + smoke, door frames, shutters, timber framing, fences, wells, carts, barrels, crates, banners, market stalls with goods, lamp posts, hanging signs.
- Per-village identity (Oakvale cosy farm town, Dunmere stone/mill/irrigation, Briarwatch tower).
- Warm light pools at night, lanterns.

## V4 - Dungeons & caves
- Cave: stalactites/stalagmites, glow-mushroom clusters, crystal veins, dripping + dust shafts of light, torches with Fire + PointLight, bone piles, cobwebs.
- Briarwatch tower: banners, braziers, arrow slits, stairs, cracked masonry.
- Cellar/mill interiors: barrels, grain sacks, pipes, sluice gears.
- Boss arenas: dynamic lighting change on fight start (vignette, red tint).

## V5 - Characters, enemies, NPCs
- Hero outfits per class (armour pieces, capes, hats) matching 2D sprites; weapon models with materials.
- Enemy models: more distinctive silhouettes (wolves, trolls, minotaur, serpents, bandits), idle/walk animation via CFrame tweens, death dissolve.
- NPCs: clothing variety, idle animations, name plates styled to UI.

## V6 - Time & weather
- Slow day/night cycle per world (sky + lights), fog banks in the morning, rain/storm events in woodland, snow gusts in frost, lightning near dragons.

## V7 - Polish & assets (needs the user)
- Uploaded textures (grass/stone/wood), meshes (trees, rocks, buildings), skybox, ability/portrait icons, audio (music per region, ambience, SFX).
- Optimisation: StreamingEnabled tuning, part merging/MeshPart instancing, LOD (distance hide of small props), mobile quality tier.

Exit: a stranger shown a screenshot of any area can tell the region/time-of-day; no flat-plastic ground; every area has light sources, depth haze, particles and 6+ prop types; 60 fps PC / 30+ mobile.
