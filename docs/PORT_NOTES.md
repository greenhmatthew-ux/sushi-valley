# Port Notes — Phaser/TypeScript → Godot 4.7

The previous build lives at `d:\Downloads\Japanese` (Vite + TypeScript + Phaser, ~39k LOC
under `src/`). It is **frozen reference**: read from it, never write to it. This file
records what came across and what did not, so nobody has to re-derive it.

## Carried over verbatim

| What | Old path | New path |
|---|---|---|
| Art + audio (509 files, 18.6 MB) | `public/assets/{sprites,tilesets,buildings,objects,items,icons,ui,audio,nano}` | `assets/` |
| Content tables | `src/game/data/*.json` | `data/game/` |
| Learning data (1392 cards, 138 lessons) | `src/shared/data/` | `data/learning/` |
| Design docs | `docs/*.md` | `docs/` |
| Supabase schema | `supabase-schema.sql` | `docs/supabase-schema.sql` |

The JSON is byte-identical, so balance and content are preserved exactly. `DB` verifies
the counts on every headless test run (`tests/smoke_db.gd`).

## To be ported ~1:1 (pure logic — port the math exactly, then tune)

From `src/shared/learning/`: `SrsSystem.ts`, `LearningProfile.ts`,
`LearningProgressionSystem.ts`, `LearningTypes.ts`.

From `src/game/systems/`: `Progression.ts`, `CombatSystem.ts`, `EnemyScaling.ts`,
`Inventory.ts`, `CraftingSystem.ts`, `LessonGate.ts`, `Quests.ts`, `Shops.ts`,
`Abilities.ts`, `SaveSystem.ts`, `RaidSystem.ts`, `ExpeditionSystem.ts`,
`GrandExchangeSystem.ts`, `FarmSystem.ts`, `SocialSystem.ts`, `WorldClock.ts`,
`CombatDrops.ts`, `DefeatTracker.ts`.

These carry playtested balance. Notable things worth preserving deliberately:
- `SrsSystem.review()` uses intentionally short early intervals (30s / 10min / 1h / 4h)
  so cards recycle **within one play session** rather than being pushed to tomorrow.
- `CombatSystem` keeps Energy (actions per turn) and Speed (turn order + a chance at a
  second full turn) as two distinct resources, and a Flow streak that grants +10% attack
  damage per consecutive correct recall, capped at +40%.
- `LessonGate.runGateRecallLoop()` runs recall sessions back-to-back until the gate's
  threshold is actually met, instead of stopping after one fixed batch.

## Reimplemented against Godot idioms

| Old | New |
|---|---|
| `systems/EventBus.ts` | `src/autoload/bus.gd` — Godot signals |
| `SaveSystem.ts` + `cloud/CharacterStorage.ts` (`localStorage`) | `user://` JSON |
| `systems/AudioSystem.ts` | `AudioStreamPlayer` + audio buses |
| `systems/InputDevice.ts`, `ui/TouchControls.ts` | InputMap actions |
| `cloud/*` (2113 LOC) | `HTTPRequest` against the same Supabase REST endpoints — deferred until local saves work |
| `WeatherSystem`, `WeatherOverlay`, `WaterSurface` | Godot shaders / particles |

## Rebuilt from scratch

- `src/game/scenes/*.ts` (5310 LOC) — Phaser scenes. Also map-specific, and the map design
  is being redone.
- `src/game/ui/*.ts` (5933 LOC) — DOM panels. `GameMenu.ts` (1867 LOC) becomes the unified
  tabbed menu (Character / Bag / Skills / Quests / Map / Compendium / Notebook).
- `src/game/entities/*.ts` (1313 LOC) — `CharacterBody2D` / `Area2D` scenes.

## Deliberately dropped

- `world-builder/` (5745 LOC) and `src/game/creator/` (1383 LOC) — Godot's editor replaces both.
- `scripts/ldtk-tools/` (15 pipeline scripts), the LDtk MCP server, and all `.ldtk` maps.
- Level-tuning tables keyed to LDtk entity ids: `valleyHubContent.ts`,
  `whisperingWoodsContent.ts`, `easternReachContent.ts`, `southernReachContent.ts`,
  `mountainPassContent.ts`, `hubs.json`, `servicePlacements.json`. Their behavior values
  (cooldowns, seasons, scales) get folded into the new Godot prop scenes.
- Legacy `app.js` and `src/0*.js` — the pre-reboot webapp, already superseded.
- Web build/deploy: `vite.config.mts`, `build.mjs`, `ship.mjs`, `capacitor.config.json`,
  `sw.js`, `netlify.toml`.

## Map/level design

**Not ported.** This was the explicit decision: the world is being redesigned natively in
Godot with TileMapLayer terrains, prop scenes, and collision shapes that match visual
footprints. The map rules in `CLAUDE.md` carry over unchanged.
