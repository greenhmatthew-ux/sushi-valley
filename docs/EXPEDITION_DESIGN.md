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

The Godot room keeps the same contract the LDtk original had: named entry/return spawns, a retreat
door, explicit stage placements on a winding trail, and tree-trunk footprint collision (never the
full canopy bounds). The shared profile saves `active`, `encounter-cleared`, `objective-recovered`,
`recall-cleared`, and `complete` stages. A retreat resumes the same stage; a completed repeatable
run starts over while retaining its completion count.

## Biome catalogue (long-term, build one at a time)
Forest, Bamboo Grove, Cave/Mine, Coastal/Pier, Mountain, Snow/Alpine, Shrine/Spirit,
Market/Urban, Farm/Field, Ruins, Festival Night, Kitchen Trial — each with its own
environment tags, learning focus, and enemy theme.

## Current implementation
`src/systems/expedition_logic.gd` owns the small data-driven state machine (ported from the
archived `ExpeditionSystem.ts`). `src/scenes/expedition_forest.tscn` + `.gd` is the handcrafted
staged room, entered through `src/entities/expedition_gate.gd` in Whispering Woods; the lunchbox
and its recall live in `src/entities/expedition_objective.gd`. Encounter and boss victories arrive
as ordinary `enemy_died` Bus signals from the same combat path used everywhere else — the room owns
no combat rules. Static definitions remain in `data/game/expeditions.json`.

The room's ground and forest are generated from a fixed seed rather than hand-placed, because this
workflow has no interactive editor and an enclosing treeline is ~150 props. The seed makes the
layout identical every run, so it can be judged from a screenshot like an authored map — and it
must be: `tests/test_expedition.gd` and `tests/test_expedition_room.gd` cover the stages and the
route geometry, but only a rendered capture catches a treeline that reads as a stamped rectangle.

**ExpeditionDef:** id, displayName, biomeId, entryMap, entrySpawn, mapLevelId, requiredFlags,
requiredRaidIds, lessonFocus, pathTileFrames, encounterIds, bossEncounterId, objectiveId,
rewardIds, reward `{ coins?, items? }`, unlockFlags, placements, returnMap, returnSpawn,
repeatable, estimatedMinutes, status.

First implementation is handcrafted + reliable. No roguelite/procedural until the core loop is fun.
