# Sushi Valley Level Design Bible

This is the shared spatial-design contract for the Phaser/LDtk reboot. It turns the product
principles in `WORLD_AND_PRODUCT_EXPANSION_PLAN.md` into a repeatable map-authoring checklist.
LDtk owns terrain, paths, water, collision, spawns, exits, landmarks, and permanent placement;
runtime code owns behavior, state, rewards, and restrained ambient motion.

## Route grammar

Every production outdoor route needs six readable beats:

1. **Arrival read** — the spawn faces a landmark and the safe route.
2. **Primary path** — a clear 30–60 second route reaches the main destination.
3. **Optional loop** — a useful branch rejoins instead of ending in empty space.
4. **Risk pocket** — danger visibly protects a reward, resource, or shortcut.
5. **Shortcut** — progress makes repeat travel faster or safer where appropriate.
6. **Exit preview** — the next destination is foreshadowed before the transition.

Use the composition rhythm `open -> narrow -> reveal -> pocket -> landmark -> return`. A viewport
should contain a destination cue, meaningful interaction, composition change, or landmark—not
uniform field fill or decorative confetti.

## Water and fishing contract

- Author the water body and shoreline in LDtk from inspected edge, corner, center, and transition
  frames. Never generate a rectangular field of animated water sprites at runtime.
- Keep shoreline silhouettes static. Add only sparse ripples, fish movement, foam, weather, or
  reflections as runtime ambience.
- Water is solid at the visible wet band. Use partial collision on shoreline cells and full
  collision on interior cells; exclude an authored dock, bridge, ford, or stepping-stone route.
- A fishing site is a destination, not a row of duplicated resource icons. Give it a readable
  approach, negative space, one primary casting point, and at most a few deliberately separated
  alternatives.
- Fishing follows a complete loop: approach -> cast feedback -> bite/control challenge -> catch
  quality -> item and Fishing & Cooking XP -> saved cooldown -> reason to return.
- Boats and tall waterfront props render at their full visual bounds, while collision comes from
  the water or the visible hull/ground-contact band—not the transparent image rectangle.

## First benchmark: Whispering Woods cove

Baseline audit score: **47/100**. Waterfront checkpoint: **58/100**. The cove is a benchmark, not a
claim that the entire forest is production-complete.

```text
Valley gate
    -> arrival clearing -> Bramble/workshop -> narrowing primary trail -> cove reveal
                                                     |                         |
                                                     +-> west-bank branch -----+
                                                         dock + fishing        |
                                                         boat landmark         |
                                                         east-bank risk pocket-+
                                                                                -> Mountain gate preview
```

The cove branch must:

- leave and rejoin the primary trail through two readable entrances;
- use the boat and dock as the dominant southeast landmark;
- expose three authored casting positions: dock, sheltered west bank, and deep east bend;
- keep the dock walkable while making visible water non-walkable;
- stage the River Kappa on dry ground as the risk pocket rather than in the main road;
- preserve the existing fishing reward, save, season, and recall systems;
- use the inspected native 16px Ninja Adventure waterfront kit only.

## Per-slice acceptance

- Run the generator twice and confirm byte-identical LDtk output.
- Run TypeScript, production build, game smoke, quality screenshots, asset coverage, and the full
  LDtk dry-run pipeline.
- Capture the arrival/primary route, landmark reveal, fishing interaction, risk pocket, and mobile
  view. A human approves any new visual baseline.
- Re-score only what is visibly and mechanically implemented. Record remaining weaknesses and the
  next concrete route before committing.

## Benchmark status

The ValleyHub arrival/route/label and Whispering Woods waterfront/journey benchmarks are complete
and covered by deterministic generators, desktop/touch screenshots, content checks, and real
round-trip traversal tests. Their current evidence and scores live in
`LEVEL_DESIGN_OVERHAUL_AUDIT.md` and `PROGRESS.md`.

The active product handoff is UI-A foundation work from `UI_UX_GUIDE.md`. Re-scope any next region
or route benchmark separately; do not fold Mountain, interiors, or frontier expansion into UI-A.
