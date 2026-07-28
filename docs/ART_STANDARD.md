# Art Standard — Sushi Valley

One coherent 16px pixel-art standard. Everything in the game must match it so the world
reads as a single place, not a collage. When in doubt, do not import — ask which of these
two packs the asset should come from.

## The canon

| Layer | Source | License | Notes |
|-------|--------|---------|-------|
| Terrain / tileset | **Serene Village Revamped** | see `docs/LICENSE_AUDIT.md` | The village + wilds ground. `assets/tilesets/serene_village.png`. |
| Characters, enemies, props, UI | **Ninja Adventure** (CC0) | CC0 | The player, all monsters, barrels/pots/crates, hearts. |

Both are native **16px** art. That is the whole game's unit:

- 1 tile = 16px. The map renders at **zoom 2**. Project texture filter is **Nearest**,
  set once project-wide — never override per-texture.
- A character/enemy sheet is **64×64** = a 4×4 grid of 16px frames (`SpriteSheets.walk_frames`:
  columns = direction down/up/left/right, rows = frames).
- A single-tile prop is **16×16**. A tree is **32×32** (2 tiles). A small building is on the
  order of **80×64**. If an asset dwarfs the player, it is the wrong asset — do not scale it
  down, replace it.

## Prop rules (enforced in `src/entities/prop.gd`)

Every world object goes through the `Prop` scene, which bakes in the non-negotiables:

- **Whole sprite, always.** No region/atlas cropping — the full asset is drawn or it is not used.
- **Never flipped.** `flip_h`/`flip_v` are never set. A mirrored ninja reads as wrong instantly.
- **Feet origin.** Sprite offset puts the visual base at the node position, so Y-sort and
  placement are predictable.
- **Base-only collision.** The static body matches the solid ground footprint (trunk/base),
  not the canopy or the art bounds. See `foot_size` / `foot_offset`.

## Enemies in play

- **Village (starting area):** sparring slimes — opt-in via interact, never aggro.
- **The Wilds:** aggro foes, one of each for variety — **mushroom**, **kappa**, **lantern-ghost**
  (`enemy_mushroom` / `enemy_kappagreen` / `enemy_lanternred`, all Ninja Adventure 64×64).

## Do not

- Do not use anything from the old `nano` generated-asset folder. It is off-standard and removed.
- Do not import a fresh pack for one-off flavor. Reuse the canon or extend it deliberately,
  and keep `CREDITS.md` + `docs/LICENSE_AUDIT.md` current when you do.
