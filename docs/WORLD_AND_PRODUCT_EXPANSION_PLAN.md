# Sushi Valley World and Product Expansion Master Plan

**Status:** active roadmap

**Audit date:** 2026-07-11

**Execution rule:** this is a large destination plan, but implementation stays in small,
tested, separately committed vertical slices.

This document is the current authority for level design, visual direction, asset variety,
UI/UX, gameplay-system hardening, feature growth, and world expansion. Existing design docs
remain useful constraints and history, but their old status lists are not the current backlog.

## Execution update - 2026-07-19

The audit findings below remain useful history and quality constraints, not a claim about today's
runtime. M0-M11 foundations, Frostpine Ridge, the social/home proof, Sushi Prep Raid, Forest Lunchbox
Expedition, and the bounded Eastern/Southern production spokes have shipped. Current gates show:

- LDtk validation, warps, encounters, progression, and asset audits report zero errors/warnings;
- North, East, and South are playable through bidirectional Frontier Nexus links;
- Woods, South, and East satisfy the authored-water contract: shore, collision, dock, dry arrival,
  visible boat, exact casts, and usable return all come from semantic LDtk data;
- East now uses a 173-cell marsh basin and has no permanent runtime-placement branch; South uses a
  172-cell desert lagoon and likewise has full semantic authority;
- typecheck, content, assets, production build, reload-aware gameplay smoke, and desktop/touch quality
  gates pass with no console or travel errors.

The active M11 handoff is Valley's Sakura Lake, then Mountain's glacial tarn. Their current advertised
boat arrivals still sit in wet collision and do not yet meet the shared destination contract.

## Outcome

Turn the current broad prototype into a deliberate, visually rich single-player life RPG where:

- every map has a readable route, memorable landmarks, purposeful side pockets, and honest collision;
- every region has its own coherent visual kit instead of sharing the same grass, road, tree, and rock;
- gathering, farming, fishing, crafting, combat, quests, shops, learning, and travel form complete saved loops;
- the HUD and menus stay readable at desktop and mobile sizes without clipped controls or permanent label clutter;
- new world areas ship one complete region at a time, never as empty procedural spokes marked playable;
- Japanese learning is naturally attached to people, places, items, shortcuts, and rewards instead of feeling like a separate interruption.

## Non-negotiable build rules

1. Preserve the Vite + TypeScript + Phaser + LDtk reboot. This is not another reboot.
2. LDtk owns terrain, paths, collision, spawn points, exits, landmarks, and placement.
3. Runtime systems own behavior and data. Scene classes should not keep accumulating map coordinates.
4. Use real, license-tracked art sourced from `D:\Asset Library`; runtime paths stay repo-relative.
5. Keep one coherent art kit per screen/region. A different region may use a radically different kit.
6. No region is `playable` until it passes the region definition of done in this document.
7. No new feature counts as shipped until action -> feedback -> reward -> save -> next reason to act works.
8. Do not add another major system while a visible shipped loop is broken or visually placeholder-quality.
9. Do not build all eight Frontier Nexus spokes at once. Finish one production spoke, learn from it, then repeat.
10. Every implementation slice ends with focused automated checks, manual visual checks, roadmap updates, and a readable commit.

## Baseline audit snapshot (2026-07-11; historical)

This section preserves the evidence that set the original execution order. It is not current project
status; use the execution update above and `PROGRESS.md` for resolved blockers and current next work.

### What the latest work successfully established

The 2026-07-11 commits added a strong breadth foundation:

- scalable Bag controls and a radial world graph (`307f0eea5`);
- a playable Frontier Nexus with eight outward gates and hub services (`96de3850d`);
- a level-60 content foundation with 102 item records, 33 abilities, 49 enemies, and 63 recipes;
- regional shops, renewable resource nodes, crafting services, and Grand Exchange depth;
- Northern Reach and Eastern Reach prototype maps (`82dd9ea00`);
- farming, fishing, day/season state, weather, and interior furnishing (`e360ef712` through `e79bcad40`);
- green TypeScript, production build, content-scale checks, and full existing smoke coverage.

These are useful systems and data seams. The problem is no longer lack of breadth. The problem is
that map quality, visual coverage, authored placement, interaction depth, and UX verification have
not caught up with the new breadth.

### Baseline blockers at audit time

At that baseline:

- `npm.cmd run game:build`, `npm.cmd run test:game-content`, and `npm.cmd run test:game` pass.
- `npm.cmd run ldtk:all -- --dry-run --verbose` fails with **1 error and 25 warnings**.
- `gate_north` is duplicated; Northern/Eastern Reach are reported unreachable from Valley Hub;
  new reach return links are one-way; the Frontier Exchange Hall targets a missing `default` spawn.
- New reach encounters have no biome, difficulty, or Japanese prompt tags.
- All current maps report zero `Path` layer tiles. The new generators stamp road tiles into `Ground`.
- Northern and Eastern Reach are 960x640 maps with only 21 distinct tile IDs, six props, two prop
  textures, five enemies, and no production-quality regional identity.
- Mountain Pass has zero Props-layer entities. Whispering Woods has only five props using two textures.
- Frontier Nexus has eight functional gates, but only five Props-layer entities; most service placement
  and regional content is hardcoded in `WoodsScene.ts`.
- `valley_hub.ldtk` is now about 6 MB / 340,000 lines, so a generated region creates an enormous,
  difficult-to-review serialized diff.
- The current production output is about **137 MB**. A complete Ninja Adventure source archive under
  `public/assets/maps/sushi-valley/assets_lib` contributes about **105 MB** and 2,220 files even though
  the game uses a small curated subset.
- Only 14 of 102 items have real inventory icons. Only eight ability icon files exist for 33 abilities.
  Enemy coverage is healthier: 49 enemies use 38 distinct sprites.
- Recent resource/station/fire assets are not documented in the runtime asset manifest or license audit.
- `TownShopInterior` entities reference `sprout_furniture:*`, while preload registers the sheet as
  `furniture`. The shop interactable therefore renders Phaser's neon missing-texture block.
- The Bag's filters and sort controls exceed the panel bounds. Grand Exchange content/footer controls
  also clip, and a victory toast can cover the GE title.
- Permanent NPC name/duty labels overlap one another and the environment in dense areas.
- `FarmSystem.getPlots()` returns a sliced array, while plant/harvest replace entries in that copy.
  Planting also checks whether a seed definition exists instead of whether the Bag owns a seed.
- Transit routes exist in code but no transit stops are authored; the generic transit interaction
  auto-attempts the first route instead of letting the player choose.
- The smoke suite proves existing flows function, but it does not traverse Northern/Eastern Reach,
  assert UI bounds, detect missing-texture frames, or test the new farming/fishing/day loops.

### Map scorecard

| Map | Current strength | Main problem | Required disposition |
|---|---|---|---|
| Valley Hub | Most visual variety, town/farm landmarks, real route network | Rectangular road stamps, pack/scale mixing, dense label overlap, hardcoded farm/services | Production map, focused remaster |
| Whispering Woods | Working travel/combat/resource route | 17 tile IDs, five props/two textures, sparse interactions, same ground language as Valley | Re-author as a forest journey |
| Mountain Pass | Working progression link and ore/forge loop | No Props entities, same grass road, weak elevation/biome identity | Re-author as a climb with elevation beats |
| Frontier Nexus | Functional eight-way hub and services | Sparse open plaza, repeated buildings/signs, hardcoded content, gates lack strong identities | Recompose as a real capital frontier hub |
| Northern Reach | 960x640 prototype and return concept | Invalid duplicate ID, unreachable, green placeholder biome, ring boundary, no unique loop | Mark `frontier`; do not call playable |
| Eastern Reach | 960x640 prototype and return concept | Unreachable/one-way, same generated template, no ruins despite theme text | Recommended first production spoke |
| Five interiors | Compact boundaries and service hooks | Four tile IDs each, duplicated map/runtime decor, missing texture alias, limited room storytelling | Author each room once in LDtk |

## Product north star

The primary loop remains:

**explore -> notice a need -> gather/fight/learn -> craft or trade -> improve the character/home/world -> unlock a new route -> explore again**

Learning should strengthen the loop in four ways:

- NPC language and signs give local meaning to vocabulary.
- Short recall checks unlock optional shortcuts, better rewards, discounts, clues, or safer routes.
- The Notebook tells the player what was learned in the current place.
- A region reward should improve both the game profile and an attributable learning path.

Avoid turning every door into a test. A player should be able to inhabit the world; recall gates are
high-value moments, not constant toll booths.

## Dependency order

`truth/stability -> visual foundation -> opening-world remaster -> first complete spoke -> life-skill depth -> more regions -> Raids/Expeditions`

UI work runs alongside these phases only when it directly supports the active vertical slice.

## Definition of done

### A map is done when

- [ ] The intended route, optional branch, landmark, exit, and shortcut read without opening the map.
- [ ] Roads live on `Path`/`Path_Detail` and use centers, edges, corners, transitions, and variants.
- [ ] The boundary is landscape-shaped, not a rectangular ring of repeated trees or collision.
- [ ] Every viewport contains a landmark, composition change, interaction, or clear destination cue.
- [ ] Props are clustered intentionally and never randomly block a road, door, spawn, or interaction.
- [ ] Tall art has correct back/front depth behavior and an absolute ground-footprint collision body.
- [ ] Entrances have valid return spawns and every travel edge works in both directions.
- [ ] There are no missing textures, invisible blockers, duplicate IDs, or LDtk validation errors.
- [ ] Desktop and mobile screenshots have been reviewed at the important route beats.

### A gameplay feature is done when

- [ ] The player can discover it naturally in the world.
- [ ] Input, cancellation, failure, and success states are clear.
- [ ] It gives immediate feedback and a meaningful reward/progression change.
- [ ] The change survives reload and old saves receive safe defaults/migration behavior.
- [ ] The feature creates a next reason to act rather than ending as an isolated minigame.
- [ ] A focused automated test and a short manual test cover the complete loop.

### A region is done when

- [ ] Its theme and licensed region kit are approved before map population begins.
- [ ] Travel in/out, arrival landmark, primary route, optional loop, shortcut, and one interior work.
- [ ] It has a regional enemy set, resource set, shop/trader, crafting/refining use, and reward.
- [ ] It has at least one local NPC need/quest and one natural learning interaction.
- [ ] Its music/ambience/weather treatment and map/world-menu identity are distinct.
- [ ] It has unique visual silhouettes: terrain, trees/relief, landmark, props, resources, and enemies.
- [ ] The world graph marks it `playable` only after all validation and smoke checks pass.

### New content is done when

- [ ] Item/ability/enemy data validates and is actually obtainable at the intended progression band.
- [ ] A visible item or ability has a real icon; a ground drop/resource has an appropriate world sprite.
- [ ] Its source pack, license, source file, runtime file, frames, scale, anchor, and collision are recorded.
- [ ] It has a gameplay reason beyond increasing catalog counts.

## Workstream 0 - Restore truth before expansion

### Slice 0.1 - Frontier graph repair

Target files: `valley_hub.ldtk`, the three frontier build scripts, `world-regions.json`,
`world-transitions.ts`, and frontier smoke coverage.

- Give every gate/entity a unique stable ID.
- Add valid named arrival/return spawns to both sides of every live link.
- Make Mountain Pass <-> Frontier Nexus <-> active spoke traversal bidirectional.
- Fix the Frontier Exchange Hall target spawn.
- Add biome/difficulty/Japanese tags to live encounters or keep them out of production data.
- Mark Northern/Eastern Reach `frontier` until their production passes are complete.
- Make generator scripts scaffold-only or retire them after authored LDtk maps replace their output.
- Acceptance: `ldtk:all` has zero errors; new smoke traverses each advertised playable edge and returns.

### Slice 0.2 - Visible blocker repair

- Resolve `sprout_furniture` versus `furniture` with one canonical asset key/frame contract.
- Remove the green missing-texture block and eliminate duplicated runtime + LDtk furnishing.
- Reflow Bag filter/sort controls inside the 760x552 panel.
- Pin GE footer actions inside its modal, bound scrolling, and keep toasts out of modal title space.
- Hide duty labels until proximity/hover/interaction; keep service icons readable at a distance.
- Acceptance: no missing-texture use, clipped controls, or overlapping labels in the smoke screenshots.

### Slice 0.3 - Life-loop correctness

- Mutate the canonical farm state rather than a sliced copy.
- Require an owned seed quantity and provide an explicit crop picker instead of auto-planting first match.
- Define exactly how watering advances growth and what rain/snow do on day transition.
- Put fishing UI in screen/UI coordinates, add a start grace period and cancellation, and test success/failure.
- Keep one time model: daily reset for common nodes; explicit multi-day rules for rare nodes.
- Acceptance: plant -> save -> sleep -> grow -> reload -> harvest works; fishing can be won and cancelled.

### Slice 0.4 - Quality gates

- Add assertions for advertised world status versus reachable LDtk levels.
- Add a missing-texture detector and UI safe-bounds assertions for every menu/modal.
- Add current-system tests for farming, fishing, weather/day, resource reset, and new-reach travel.
- Capture desktop (800x600) and phone portrait (390x844) screenshot matrices for active surfaces.
- Delete or clearly archive obsolete temporary Playwright scripts that target the legacy runtime.

## Workstream 1 - Level-design and world-composition standard

### Route grammar

Each outdoor map should use this small, repeatable grammar:

1. **Arrival read:** spawn faces a landmark and the first route; no immediate maze.
2. **Primary path:** the safe/obvious route reaches the main destination in roughly 30-60 seconds.
3. **Optional loop:** a branch contains a resource, encounter, story scene, or study shortcut and rejoins.
4. **Risk pocket:** stronger enemies guard a visibly valuable resource/reward, never random empty combat.
5. **Shortcut:** progression, a quest, or recall opens a faster return route.
6. **Exit preview:** the next region is visually foreshadowed before it unlocks.

### Composition rules

- Use large/medium/small forms: one dominant landmark, several route-shaping masses, then detail clusters.
- Change the composition every screen: open -> narrow -> reveal -> pocket -> landmark -> return.
- Use water, cliffs, fences, walls, hedges, buildings, or relief as believable boundaries.
- Reserve negative space around interaction targets. Dense decor belongs at edges and in clusters.
- Build micro-stories from props: abandoned cart + tracks, picnic + basket, shrine + offerings,
  worksite + tools, broken bridge + repair materials. Avoid isolated decorative confetti.
- Keep combat arenas readable: room to move, visible enemy silhouettes, no prop collision traps.
- Place resources where the landscape explains them: ore in exposed rock, herbs in wet clearings,
  fish in visible water, wood at forest margins.
- Use ambient life sparingly: birds, insects, smoke, leaves, water movement, workers, and weather should
  reinforce the biome without covering UI or interaction cues.

### Required LDtk layer intent

`Ground`, `Ground_Detail`, `Path`, `Path_Detail`, `Decor_Back`, `Props`, `Decor_Front`,
`Collision`, `Interactables`, `NPCs`, `SpawnPoints`, `Exits`, `CameraBounds`.

Existing extra layers may remain where useful, but runtime and validation should understand the intent.

### Opening-world remaster order

1. Valley Crossroads route readability and label cleanup.
2. Whispering Woods as a real forest journey with stream, grove, risk pocket, and return loop.
3. Mountain Pass as a climb with relief/elevation, switchback, mine/forge pocket, and summit reveal.
4. Frontier Nexus as a radial city/hub with districts, gate identities, and clear central landmark.

Do not remaster all four in one diff. One map/route slice at a time.

## Workstream 2 - Decor, art, and asset variety

### Region-kit contract

Before authoring a region, create a curated kit with named runtime assets for:

- ground bases plus at least three subtle ground-detail variants;
- complete path/road edge, corner, center, transition, and alternate-center vocabulary;
- water/shore or relief/cliff transitions where the biome needs them;
- at least three major natural silhouettes and three rock/obstacle sizes;
- eight or more small decor pieces and three medium prop clusters;
- two building/structure silhouettes plus one dominant landmark;
- signs, fences, lamps, storage, seating, tools, bridges, and service props as relevant;
- distinct resource nodes and depleted/used states;
- regional NPC silhouettes, enemy silhouettes, ambient critters/FX, and one boss/elite silhouette;
- an interior kit, map icon, UI item/ability icons, ambience, and music where available.

These are quality targets, not a reason to fill space randomly. A small dense kit beats a giant raw pack.

### Asset-pipeline repair

- Remove full source archives from `public/`; keep raw packs in the external library or gitignored raw area.
- Copy only approved runtime files into stable category/region folders.
- Extend the asset manifest with source pack, source file, license record, frame metadata, scale,
  origin, collision footprint, tags, and owning region.
- Add automated checks for missing files, duplicate keys, invalid frames, undocumented runtime assets,
  and unreferenced oversized files.
- Split preload into global essentials and lazy region/interior kits after the first curation pass.
- Initial target: reduce the 137 MB production output below 35 MB without removing visible content.

### Immediate visual coverage targets

- Import real crop stages, tilled-soil/watered states, fishing targets, and resource/station art.
- Expand building cuts from five images to a named, collision-authored set from Serene Village.
- Add fences, bridge pieces, lamps, benches, wells, signs, flowers, weeds, crates, barrels, and tools.
- Give every currently obtainable item a UI icon before adding more item tiers.
- Give every currently selectable ability an icon before exposing additional level bands.
- Add player equipment overlays only after one complete gear set proves anchors for all four directions.
- Use the existing 38 enemy silhouettes through coherent regional encounter tables, not random distribution.

### Recommended pack roles

- **Ninja Adventure:** Valley-adjacent wilderness, Spiritwood, desert, ruins, water, towers, actors, enemies, FX.
- **Serene Village:** Valley/town buildings, bridges, trees, water, and settlement props.
- **Sprout Lands:** dedicated farm map/interiors, crop stages, tools, animals, tilled soil, furniture.
- **GuttyKreum Japanese City:** a later standalone dense/rainy city region; do not mix it into Valley screens.
- **32rogues:** a later isolated Expedition presentation if its 32px scale is adopted for the whole instance;
  do not mix its tiles into the current 16px overworld.
- **Kenney/other CC0:** use only after a screen-level style test proves cohesion.

## Workstream 3 - UI and UX

The destination specification is [`UI_UX_GUIDE.md`](UI_UX_GUIDE.md). It owns presentation,
information architecture, HUD visibility, map views, input/focus, accessibility, and the integrated
Japanese-learning experience; the domain mechanic docs still own saves, progression, combat, Raid,
Expedition, gear, and learning rules. The guide distinguishes `Current`, `Next`, and `Later` so planned
surfaces never masquerade as shipped.

Deliver this work in separate tracks after the active map slice:

- **UI-A - Foundation truth:** tokens, safe areas, modal ownership, Back/focus, device glyphs, and
  responsive reflow.
- **UI-B - Core play shell:** lighter contextual HUD, combat intent/feedback, queued notifications,
  accessibility baseline, and returning-player summary.
- **UI-C - Core information loop:** grouped Pause Hub, Bag/equipment comparison, profession milestones,
  typed Journal records, and remembered filters/favorites.
- **UI-D - LDtk-derived navigation:** local/region/world maps, fog/discovery, semantic filters, learned
  labels, and a deterministic developer mapshot exporter.
- **UI-E - Learning/social depth:** encountered/mastered Japanese records, unified Learning Journal,
  relationship memories, calendar/community surfaces only when backed by real state.
- **UI-Later:** player-facing showcase export, advanced floor/elevation tools, deep customization,
  cross-device sync, companions, and any multiplayer consideration.

Locked content rules:

- A higher-level attack/spell cannot replace an earlier one by being the same action with larger
  numbers. New abilities need distinct geometry, timing, positioning, setup/payoff, defense, resource,
  target, status, or weapon-style decisions; older abilities remain viable sidegrades.
- Potions and food need distinct emergency, sustain, meal, resource, cleanse, resistance, gathering,
  or social roles. Consolidate or redesign redundant numeric healing items in a separate save-safe
  combat/economy slice.
- Player-facing and asset names must describe real purpose, material, region, silhouette, and behavior.
  Keep stable IDs behind aliases where saves/LDtk depend on them; never expose generic sprite/entity
  keys as names.

### UI foundation

- Keep the fixed 800x600 logical canvas, but define safe rectangles, spacing tokens, type scale,
  button sizes, modal header/body/footer zones, and scroll ownership in one small layout module.
- Use the existing input-lock contract, then add a modal stack/counter so nested panels cannot unlock early.
- Make every hover detail available by click/tap/focus. Hover-only information is not mobile-safe.
- Add focus/selected/disabled/loading/error states consistently.
- Use real pixel UI frames selectively for panel borders, tabs, and prompts; retain a readable system font
  where a tiny pixel font would hurt comprehension.

### HUD and world readability

- One compact primary row: level/HP, currency, due reviews.
- One secondary contextual row: location, day/season/weather, tracked objective when relevant.
- Move keyboard hints into a dismissible controls hint/settings surface after onboarding.
- Show NPC name normally; show duty/quest/service detail only near the NPC or on interaction.
- Replace permanent black role labels with small icons plus proximity text.
- Queue toasts and reserve a safe toast lane that never covers modal headers or combat controls.
- Add clear entrance/gate state: open, recall-ready, level-locked, quest-locked, future frontier.

### Menu priorities

- **Bag:** two-row responsive toolbar, clear active filter/sort, grid/list density toggle only if needed,
  item detail/comparison area, quantity/use/equip actions, controller/touch navigation.
- **Character:** readable paper doll, equipment comparison, role summary, derived-stat explanations.
- **Skills:** role filter, tier grouping, prerequisites, weapon requirement, equip cap, visible next unlock.
- **Quests:** list/detail layout, tracked objective, region/distance cue, objective types beyond fetch.
- **Map:** current region route, discovered landmarks, tracked objective, gates, services, fog/unknown areas.
- **World:** show production and known-frontier routes; hide internal placeholder spokes from normal players.
- **Compendium:** filters, regional grouping, useful drops/habitat after discovery, not three giant empty cards.
- **Notebook:** lesson grouping, local-region vocabulary, readable wrapping, review action, provenance detail.
- **Settings:** text scale, world zoom, weather intensity, reduced motion, volume, pronunciation, controls.

### Shop, crafting, and Grand Exchange

- Use a shared panel shell with pinned header/footer and one scrollable body.
- Keep Buy/Sell/quantity/price actions visible; never place primary action below the modal boundary.
- Use empty/loading/error states and clear insufficient-coin/material feedback.
- Separate market simulation depth from the first-time shopping flow through progressive disclosure.
- Add touchscreen-friendly quantity controls and keyboard/controller focus order.

### Mobile acceptance

- Test phone portrait and landscape, not only scaled desktop screenshots.
- Provide a virtual movement control and one obvious context action; hide them on mouse/keyboard.
- Minimum interactive target should be comfortable at the rendered phone scale.
- Menus may use an alternate logical layout on narrow viewports; do not merely shrink unreadable text.

Current input checkpoint (2026-07-14): one lifecycle-owned app tracker now distinguishes current
keyboard/mouse from touch-like input after deliberate input. Semantic world prompts own no device text;
the shared prompt supplies one live `E`/`USE` keycap, while title, dialogue, HUD guidance, and
virtual-control visibility follow the same signal. Controller glyphs remain withheld until controller
actions exist, and static panel/minigame copy remains a named follow-up rather than implied completion.

## Workstream 4 - Logic and function hardening

### Data and scene boundaries

- Move resource, service, NPC, station, farm, encounter, and transit placement out of scene coordinates.
- Add one runtime spawn registry keyed by authored entity `kind`; keep behavior in small system modules.
- Let LDtk entities reference data IDs. Do not duplicate economy/combat/crafting values in map files.
- Extract per-region music, flavor, tables, services, and fallback travel data from `WoodsScene.ts`.
- Keep the current scenes during extraction; only rename/consolidate after duplicated behavior is gone.
- Split `GameMenu.ts` by tab once the layout contract is stable. Avoid a one-shot 1,176-line rewrite.

### Save-state contract

- Add explicit save/profile version migrations for every new persistent field.
- Keep world position/day in game state; keep cross-surface learning and player progression in profile.
- Define ownership for farming, resources, quests, discoveries, NPC state, and world shortcuts.
- Add export/import/reset-debug tools before the save becomes harder to inspect.
- Test old-save load, new-save round trip, malformed-save fallback, and reload after every core action.

### Life skills

- Add dedicated Farming, Fishing, Mining, Foraging/Woodcutting progression only after the base action works.
- Each skill gets one tool/requirement model, one feedback animation, one regional table, and one useful output loop.
- Prefer quality/efficiency unlocks and new routes over pure number inflation.
- Make tools/equipment visually and mechanically relevant; avoid durability until it solves a real loop need.

### World time, weather, and schedules

- First stabilize day/season/weather effects on crops, fish, shops, and ambience.
- Then add a simple dawn/day/dusk visual phase; do not build a complex minute-by-minute simulator first.
- Prove schedules with three important NPCs and two destinations each before expanding to the whole cast.
- Sleeping must preview what advances/resets and must not silently destroy player progress.

### Quests and learning

- Evolve quests from one fetch goal to an objective list supporting talk, visit, defeat, gather, craft,
  study/recall, and return.
- Implemented objective evidence now covers held items plus post-acceptance harvest, gather, fish,
  correct-review, craft, and enemy-defeat counters. Talk, visit, and explicit return rows remain.
- Author chains region-by-region; every quest should teach a route/system or change a world state.
- Tie local vocabulary to signs, NPCs, items, travel, and recipes with attributable source cards.
- Use recall for optional shortcuts/bonuses and a few major gates; show exact progress and a cancel path.

### Transit

- Place real stops, valid destination spawns, and return routes in LDtk.
- Replace first-route auto-selection with a compact route picker showing cost, lock reason, and destination.
- Add a brief transition/fade and persist arrival correctly.
- Ship one Valley <-> Frontier route before adding train/bus/boat networks.

### Combat and encounters

- Preserve current combat math while improving presentation and encounter context.
- Replace isolated static enemies with authored encounter pockets/zones, clear aggro telegraphs, and leashes.
- Give each region a small role-based roster: common pressure, ranged/control, durable elite, signature boss.
- Add biome backdrops/FX and readable hit/reward feedback to CombatScene.
- Keep world bosses rare and authored; do not scatter summon circles into unfinished regions.

## Workstream 5 - Feature roadmap

### Priority feature loops

1. **Farm morning loop:** choose seed -> plant -> water/weather -> sleep -> stage change -> harvest -> cook/sell -> upgrade.
2. **Regional gathering loop:** discover node -> meet skill/tool requirement -> gather -> refine -> craft -> unlock route/gear.
3. **Fishing loop:** choose water -> play readable minigame -> fish table/quality -> cook/request/sell -> unlock harder waters.
4. **NPC request loop:** meet -> learn need -> track objective -> complete -> relationship/service/world change.
5. **Region mastery loop:** map discoveries + enemies + resources + learning + regional quest -> signature reward/shortcut.

### Later, only after the first region mastery loop

- Three-NPC relationship/schedule proof with simple favor levels and useful service changes.
- Home/farm upgrade proof with one visible upgrade and one new function.
- A second structured Raid only after Sushi Prep's objective/reward/journal flow is fully surfaced;
  do not revive the legacy deckbuilder without a separate product decision.
- A second Expedition using hand-authored rooms and the current standard combat system, after the
  Forest Lunchbox route proves its repeat/reward loop.
- Festivals, collections, cosmetics, and deeper housing after the daily/world loop is compelling.

## Workstream 6 - World expansion sequence

### Recommended first production spoke: Eastern Reach - Spiritwood Ruins

Why this first:

- Its existing theme text already says ancient groves and forgotten ruins.
- Ninja Adventure already provides coherent nature, water, relief, abandoned-village, enemy, boss, and FX art.
- It can prove the complete region pipeline without waiting for a new snow kit.

Proposed route:

1. Nexus east gate -> ranger checkpoint/arrival sign.
2. Broad spiritwood trail -> stream crossing with visible optional lower-bank loop.
3. Abandoned hamlet/ruin landmark -> local trader and repair station.
4. Grove encounter pocket -> spirit/forest enemies and moonwood/herb resources.
5. Collapsed shrine shortcut, opened by a regional quest or focused recall.
6. Ruin heart elite/boss -> recipe/resource reward -> fast return route.

Production content target:

- one 60x40 authored outdoor map with three distinct composition beats;
- one compact ruin/shrine interior;
- three common enemies, one elite, one boss;
- three resources with clear refining/crafting uses;
- one shop/trader, one station, two named NPCs;
- a three-step quest chain and one local source-backed learning interaction;
- one signature reward that changes build options or opens the next route.

### Northern Reach - keep as frontier until asset selection

Recommended identity: Frostpine Ridge / highland observatory. It needs a coherent licensed snow/ice,
pine, cliff, building, prop, resource, and FX kit before another layout pass. Do not recolor the current
grass map and call it boreal.

### Candidate long-range region matrix - not locked

| Direction | Candidate identity | Likely art lane | Signature loop |
|---|---|---|---|
| East | Spiritwood Ruins | Ninja nature/water/abandoned village | spirits, moonwood, shrine restoration |
| North | Frostpine Ridge | selected licensed snow/ice kit | mining, observatory, cold-route preparation |
| Northeast | Stormglass Coast | coherent coast/harbor kit | fishing, stormglass, boat travel |
| Southeast | Verdant Delta | water/marsh kit | herbs, bridges, flooded ruins |
| South | Serene Farmlands | Sprout Lands or Serene per screen | farming, animals, cooking, village requests |
| Southwest | Ember Caravan | Ninja desert/camp | trade route, heat, ore, caravan services |
| West | Rain City | GuttyKreum as a standalone region | dense shops, transit, urban learning |
| Northwest | Crown Ruins | coherent tower/ruin kit | elites, relic crafting, late-game mastery |

Matthew owns the final creative theme choice. A candidate becomes locked only with an approved kit and
a one-page region brief.

## Workstream 7 - Authoring tools and production pipeline

### Next World Builder vertical slices

Add only the object types required by the active region, in this order:

1. ResourceNode: data ID, unique node ID, skill/tool requirement, cooldown/reset model, sprite/state.
2. CraftingStation/Service: station/shop/service ID and interaction prompt.
3. MapMarker/Sign: icon/category, discovery state, map label, dialogue/sign text.
4. AmbientEmitter: approved asset/frames, bounded density, weather/season conditions.
5. FarmPlot only when the farm is moved to an authored farm map.

Keep LDtk responsible for tile painting and base collision. World Builder should not become a second
full tile editor.

### Map-file scalability

- Before adding several more levels, prove LDtk external levels or a simple map manifest so one region
  does not rewrite a 340,000-line monolith.
- Keep friendly level IDs and stable IIDs; validate duplicate IDs and broken references before write.
- Preview generator output as a scaffold, but final terrain/path/decor placement must be author-reviewed.
- Add per-level summaries: tile vocabulary, path coverage, prop variety, interaction count, collision count,
  warp validity, asset kit, and screenshot links.

## Workstream 8 - Performance, tests, and release discipline

### Automated gates for every world slice

- `npm.cmd run typecheck`
- `npm.cmd run game:build`
- `npm.cmd run test:game-content`
- focused system test for the changed loop
- `npm.cmd run ldtk:all -- --dry-run --verbose`
- focused smoke traversal/screenshots for the changed map and return route

### Visual gates

- 800x600 desktop baseline.
- 1280x720 desktop/windowed scaling.
- 390x844 phone portrait.
- Important panels: HUD, Bag, Character, Skills, Quests, Map, World, Shop, Crafting, GE, Combat,
  Dialogue, Learn, each active interior, and each new region's route beats.
- Check clipping, overlap, missing textures, font size, input target size, contrast, depth, collision,
  entrance readability, and obvious next action.

### Performance budgets

- Production output below 35 MB after raw-asset curation.
- No full external source packs under `public/`.
- Global preload contains only title/HUD/player/common interaction essentials.
- Region art/audio loads on demand and is released or reused intentionally.
- Avoid per-frame polling for systems that can update on events/timers.
- Profile large maps before adding particles; weather/ambient density must have a reduced setting.

## Milestones

### M0 - Truth restored

- Frontier graph valid, statuses honest, missing texture removed, UI blockers contained,
  farming/fishing correctness covered, all core checks green.

### M1 - Visual foundation

- Region-kit/asset metadata contract, raw-public cleanup, layout tokens, label rules, new validation gates.

### M2 - Opening world remaster

- Valley, Woods, Mountain, and Nexus improved one map at a time with authored paths/decor/landmarks.

### M3 - Eastern Reach production vertical slice

- Complete route, interior, enemies, resources, station/shop, quest/learning, reward, save, screenshots.

### M4 - Life-skills pass

- Farm and fishing loops visually complete; mining/foraging data-driven; day/weather effects coherent.

### M5 - UI/UX baseline completion pass (complete)

- The first containment/responsive baseline is complete. The larger destination now proceeds through
  UI-A to UI-E in [`UI_UX_GUIDE.md`](UI_UX_GUIDE.md); do not call the destination plan already shipped.

### M6 - Second region

- Choose Northern Reach only after its kit is approved, or choose the next kit-ready spoke.

### M7 - Social/home proof

- **Complete:** three NPC schedules/favor loops and one visible saved farm irrigation upgrade.

### M8 - First Raid

- **Complete:** one reboot-native Raid using shared learning/profile data and regular combat; legacy
  deckbuilder remains reference material rather than a transplanted subsystem.

### M9 - Asset, sprite-cut, and level-composition overhaul

- **Complete foundation:** representative Valley, interior, Woods, Mountain, Frontier, North, and East
  proofs now enforce exact cuts, environmental resource models, footprint/exclusion data, service/door
  clearances, valid detail tilesets, proximity labels, stable generators, and screenshot QA.
- **Resource foundation done:** every active resource type now uses an environmental cluster or water
  surface instead of an item-only model, with shared render/ground-footprint/exclusion metadata and
  screenshot proofs in Valley, Mountain Pass, Whispering Woods, and the Greenhouse.
- **Reference-driven waterfront proof done:** Whispering Woods now uses LDtk-authored shore/water/dock,
  partial water collision, a coherent 16px waterfront sub-kit, three exact cast anchors, sparse runtime
  ambience, world-space cast feedback, overlap-based catch quality, desktop/touch screenshots, and
  byte-idempotent generation. That proof raised its audit checkpoint from 47 to 58/100; the later
  journey pass below completes the arrival and repeat-travel follow-up without changing the cove.
- **Valley arrival/route/label proof done:** ValleyHub now owns a dedicated 199-cell `Path` plus six
  inspected shoulder accents instead of baking one map-wide road rectangle into `Ground`. All four
  named arrivals connect to the Woods exit; compact travel-tagged wayfinding cues frame the Market and
  East Gate; NPC duties reveal only at interaction distance; edge-gate labels remain inside world bounds.
  Desktop/touch viewport checks and route-connectivity assertions cover the result without moving
  spawns, props, trees, or collision.
- **Whispering Woods journey proof done:** One deterministic 157-cell held route and nine inspected
  accents connect all three named arrivals, both exits, and the three preserved cove approaches.
  Proximity-only cues frame the west arrival and the authored Mountain recall gate; completing Forest
  Lunchbox persistently unlocks the existing cedar boat as a return to ValleyHub's authored
  `woods_gate` spawn. Static, desktop, real-touch, real Woods/Mountain round-trip, and real-reload
  coverage proves the locked/unlocked journey. The audit correction confirms all 17 pre-existing
  Woods semantic placements were already LDtk-owned; the completed checkpoint is 68/100, not a claim
  that the entire regional-art overhaul is finished.
- **Placement foundation done:** Valley big-prop overlap rejection, interior cell/reservation checks,
  wrong decorative crop removal, the first resource/tree relocation, and relocation of the full player
  farm/service loop out of the town doorway corridor into the south farm district.
- **Reusable hub contract done:** Frontier service posts, structure bounds, door approaches, NPC label
  envelopes, and station pairing live in shared data and are enforced by `ldtk:layout`. The Frontier
  generator now preserves return spawns, tileset/frame correctness, stable level ordering, and idempotence.
- Audit every remaining runtime sprite family against its source sheet and provenance metadata.
- Extend collision and placement checks to doors, roads, spawns, NPC duties, all resources, and blocking
  props across every active region.
- Propagate the representative proof map-by-map with screenshots. Non-commercial best-fit art is allowed
  during development but must be added to `ASSET_PURCHASE_BACKLOG.md` for purchase/replacement before
  commercial release.

### M10 - First Expedition

- **Complete:** hand-authored Forest Lunchbox instance, current combat, learning objective, boss, reward,
  saved completion, reload, and safe return. Its completion flag now also earns the Woods cove return
  route. Procedural room assembly follows the proven deterministic loop.

### M11 - Repeatable expansion cadence

- Ship remaining spokes one at a time with the same region definition of done.
- **Production footprint/waterfront/authority complete — Eastern Reach:** the reviewed CC0 vocabulary,
  60x40 footprint, real `Path` layer, western moss gate, full primary route/optional loop, 173-cell
  marsh, native launch, dry dock arrival, exact casts, return, and semantic content authority are
  complete. Preserve this contract and deepen pacing without growing the footprint.

## Historical first executable commit sequence (complete)

1. `fix(ldtk): restore valid bidirectional frontier links`
2. `test(game): traverse advertised frontier routes and returns`
3. `fix(assets): resolve interior furniture keys and missing texture`
4. `fix(ui): contain bag and exchange controls`
5. `fix(farming): persist plot mutations and require owned seeds`
6. `test(game): cover farm fishing weather and reload loops`
7. `chore(assets): remove raw source archive from public build`
8. `feat(world): define the Eastern Reach region kit`
9. `feat(world): author Eastern Reach arrival and primary route`
10. `feat(world): complete Eastern Reach regional loop`

Each commit is independently testable. Do not combine map repair, UI layout, farming state, and asset
cleanup into one large diff.

## Next concrete step

Continue the completed Woods/Southern/Eastern waterfront contract across the advertised boat network:

1. Recompose Valley's undersized 3x3 pond as a credible Sakura Lake landing with a complete dock,
   in-bounds dry arrival, native launch, return interaction, exact casts, and partial wet collision.
2. Replace Mountain's grass-shore crevice with a truthful ice-shore glacial tarn and the same complete
   dock/boat/return contract, or remove it from the destination menu until that route is honest.
3. Add one global `BOAT_DESTINATIONS` gate only after both maps pass, so every future advertised
   destination must prove minimum water size, dry dock arrival, visible boat, shortcut, and casts.

Each slice must regenerate idempotently and prove in-bounds/dry arrival, visible boat clearance,
usable return, exact water casts, and desktop/phone presentation before moving to the next map.

