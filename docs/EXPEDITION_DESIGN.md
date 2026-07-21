# Expedition Design (first playable slice — replaces "Dungeon")

**Terminology lock:** dungeons are **Expeditions** (player-facing) / `ExpeditionSystem` (code).
"Instance" may be used internally. Expeditions are literal, handcrafted instances using the
regular Sushi Valley combat — NOT roguelite runs, NOT procedural, NOT a separate combat system.

## An Expedition is
a self-contained map (or short sequence), entered from the overworld, with a clear objective,
biome/theme, learning focus, reward, and a clean return to the hub. Optionally repeatable.

## Structure
Entry point → confirmation UI → load map → short objective → 1–3 encounters → 1 learning focus
→ reward → return to overworld.

## First Expedition — Forest
- Unlock: complete the Sushi Prep Raid.
- Learning: a focused three-card `kana-sushi` recall at the recovered lunchbox.
- Flow: enter from Whispering Woods → confirm → clear the Thornback Bear → retrieve the lost
  lunchbox → clear recall → defeat the Forest Wraith → bank drops/rewards → return to Valley.
- Rewards: 80 coins, Recipe Stamp, 3 Moonwood, `expedition_forest_done`, and discovery of the
  Forest Lunchbox kitchen recipe.
- Biome-themed and reliable; no procedural generation, no meta-progression yet.

`forest_lunchbox` now exists in `src/game/data/expeditions.json` and its unlock contract is wired to
the completed Sushi Prep Raid. Its status is `playable`; `canEnterExpedition()` remains false until
the Raid flag and saved Raid completion both exist.

`ForestLunchboxExpedition` is authored in the canonical LDtk project by the idempotent
`tools/build-forest-expedition.mjs`. It has named entry/resume/completion spawns, an authored retreat
edge for warp-graph truth, explicit stage placements, a winding path-frame contract, and tree-trunk
footprint collision. The shared profile saves `active`, `encounter-cleared`, `objective-recovered`,
`recall-cleared`, and `complete` stages. A retreat resumes the same stage; a completed repeatable run
starts over while retaining its completion count.

Production of that map follows the M9 shared asset/cut/footprint/overlap overhaul so the first
Expedition does not copy known resource, structure-stacking, and interior-placement defects.

## Biome catalogue (long-term, build one at a time)
Forest, Bamboo Grove, Cave/Mine, Coastal/Pier, Mountain, Snow/Alpine, Shrine/Spirit,
Market/Urban, Farm/Field, Ruins, Festival Night, Kitchen Trial — each with its own
environment tags, learning focus, and enemy theme.

## Current implementation
`src/game/systems/ExpeditionSystem.ts` owns the small data-driven state machine. `WoodsScene` renders
the handcrafted staged room and `CombatScene` reports encounter/boss victories through the same regular
combat path used everywhere else. Static definitions remain in `src/game/data/expeditions.json`.

**ExpeditionDef:** id, displayName, biomeId, entryMap, entrySpawn, mapLevelId, requiredFlags,
requiredRaidIds, lessonFocus, pathTileFrames, encounterIds, bossEncounterId, objectiveId,
rewardIds, reward `{ coins?, items? }`, unlockFlags, placements, returnMap, returnSpawn,
repeatable, estimatedMinutes, status.

First implementation is handcrafted + reliable. No roguelite/procedural until the core loop is fun.
