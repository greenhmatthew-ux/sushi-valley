# Project Instructions — Sushi Valley (Godot)

## Project Identity
A solo-built single-player web-free desktop game inspired by RuneScape, Stardew Valley,
and Terraria, with educational recall-gating: the player learns Japanese by playing.
Godot 4.7, GDScript, desktop-first (Windows). The priority is to ship useful, stable,
understandable features quickly.

This is a port of an earlier Vite + TypeScript + Phaser build. That local copy was
**deleted 2026-07** — this Godot project is now the one and only Sushi Valley. If you ever
need the old source for reference, it is archived at
https://github.com/greenhmatthew-ux/Kana.git (clone it somewhere temporary; do not
reintroduce it into this repo). See `docs/PORT_NOTES.md` for what carried over.

## Builder Style
- Build in small vertical slices. Each slice ends playable and committed.
- Preserve existing functionality. Avoid large rewrites.
- Prefer simple architecture that Matthew can understand and maintain.
- Every feature should improve a real user flow, not just add technical complexity.
- Keep source and docs UTF-8 clean. Do not commit mojibake; verify suspicious `â`, `Ã`,
  `Â`, or `�` output by reading files as UTF-8 before replacing real Japanese or punctuation.

## Porting Rules
The bulk port is done and the TS source is no longer on disk. These still apply to any
remaining port work (clone the archive repo above if you need the original):
- **Port the math exactly, then tune.** The TS systems carry real, playtested balance.
  A silently-changed SRS interval or damage formula is the fastest way to lose the game's
  feel. Carry the explanatory comments across too — they record *why* a number is what it is.
- Already-ported files note their TS origin in a header comment. Treat that as historical
  provenance, not a live path.
- Verify ports with a headless test that asserts against the TS behavior, not by eyeballing.

## Before Making Changes
1. Read relevant files first.
2. Identify the current behavior.
3. State the smallest safe implementation plan.
4. Do not edit unrelated files.
5. Ask only if the task is truly blocked.

## After Making Changes
Always provide: files changed · what changed · how to test manually · risks or follow-up.

## UX Priorities
- Clear navigation. Persistent user progress/state when relevant.
- Avoid huge vertical scrolling. Prefer tabbed/card systems for dense panels.
- Make the game feel intentional, not generic.
- Controller and keyboard should both work. Actions are defined in the InputMap
  (`move_up/down/left/right`, `interact`, `open_menu`) — never hardcode keycodes.

## Godot Conventions
- **GDScript only.** No C#, no build step.
- Files: `snake_case.gd` / `snake_case.tscn`. Classes: `PascalCase`. Signals: `snake_case`.
- Static typing everywhere (`var x: int`, `func f() -> void`). It catches port errors early.
- Autoload singletons carry global state: `Bus` (signals), `DB` (content tables),
  and later `Learning`, `SaveGame`, `Progression`, `Inv`, `Audio`.
- Systems communicate through `Bus` signals, not direct references. This is what kept the
  TS systems layer testable, and it is why the logic ported cleanly.
- Pure logic lives in `src/systems/` and `src/learning/` and must not touch nodes or the
  scene tree, so it stays headless-testable.
- Use `TileMapLayer` (not the removed `TileMap`) and terrain sets for autotiling.

## Licensing (Matthew's call, 2026-07-30)
**Any license may be used for any aspect of this project.** Licensing is Matthew's
decision, not the assistant's. Do not ask for permission, stall a slice, or decline
work on licensing grounds — that includes art, audio, fonts, and imported deck media
whose rights are unclear, unstated, or restrictive.

`CREDITS.md` and `docs/LICENSE_AUDIT.md` stay accurate, but they are a *record of what
was used and where it came from*, not a gate on using it. State provenance honestly,
including "unstated" or "unknown", and move on.

## Art And Map Rules
- 16px native tile art, rendered at zoom 2. Texture filter is Nearest project-wide;
  never override it per-texture.
- The candidate art pool is the entire `D:\Asset Library` tree. Search broadly, then
  inspect and import the best-fitting asset. See `docs/ASSET_LIBRARY_GUIDE.md`
  and keep `CREDITS.md` / `docs/LICENSE_AUDIT.md` current.
- Never use full transparent texture bounds as prop collision. Render the full sprite and
  set the collision shape to the absolute solid footprint.
- Tree, rock, building, and prop collision should match the visual footprint the player
  expects: the trunk/base/solid mass, not the canopy, shadow, padding, or art bounds.
- Collision should block every visible part of the asset that touches the ground-contact
  band, plus deliberate foot-space padding when needed so the object feels solid.
- Decorative props must not randomly overlap roads, doors, spawn points, or obvious walkable
  routes. If a prop blocks movement, the visual base must clearly explain the block.
- Paths must not be stamped as large rectangles of one center tile. Use edge, corner,
  transition, and alternate center tiles; vary width and shape enough to feel hand-placed.
- Use Y-sort for anything the player can walk behind.
- **No two interiors may be identical.** Every interior is furnished for what its building
  is for — a forge is not a kitchen is not a home. Reusing one room layout for the second
  building is the same placeholder failure as reusing one NPC sprite.
- Resource nodes are placed for a reason the player can read: ore against rock and cliffs,
  herbs in damp or shaded ground, bamboo in stands. A node dropped on open grass because
  there was space looks unintentional, because it is.
- **Branch out across `D:\Asset Library`.** It holds ~102 packs in TWO roots — `Assets` and
  `Assets 2` (the latter is almost entirely icons and UI). Shipping from three packs is a
  choice, not a limit. Match 16px scale and the village palette; record provenance in
  `CREDITS.md`.

### Placement rules (all learned from Matthew rejecting shipped work)

- **Never cut an asset to fit a space.** If a complete building/prop does not fit, move what
  is in the way, or choose a different *complete* asset. Assembling a sprite from
  non-adjacent tile rows deletes the middle of the object — the lake house lost its whole
  upper storey that way and shipped looking chopped.
- **Feet land on a tile line.** `Prop` draws from the bottom-centre, so a prop whose y is
  mid-tile reads as floating or sunk into the floor. Every prop's y must be a multiple of
  the tile size; x should be a tile centre. An interior placed at y=44/72/104 instead of
  48/64/80/96/112 is the single reason a room reads as "assets scattered on a background".
- **Leave breathing room — no tangents.** An edge that just touches another object, a wall,
  a path or a water line reads as a mistake, not as adjacency. Budget at least a tile of gap.
  Check both sides: a building squeezed exactly between a pond bank and a road touches both.
- **No plain filler.** Do not use a flat unbroken expanse — of roof, floor, ground or UI —
  as a feature. Prefer the variant with detail; a large single-colour rectangle laid over a
  scene reads as an unfinished box.
- **Keep the entry path clear.** Nothing occupies the doorway column or the tiles a player
  first walks through on arriving in a room.
- **Verify with a screenshot every time, and look at the whole thing.** Green tests have
  repeatedly coexisted with broken visuals here. Frame the entire object/room, not a
  close-up: half the failures above are only visible at full extent.

## Testing
- Headless logic tests live in `tests/` and run with:
  `godot --headless --path D:\SushiValleyGodot --script res://tests/<name>.gd`
- Tests instantiate systems directly and call their load/init methods explicitly.
  Do **not** rely on `add_child()` to run `_ready()` — it is deferred and the test will
  assert against empty state.
- Matthew hand-tests gameplay. No browser automation.

## Do Not
- Do not add fake data unless clearly labeled.
- Do not remove features silently.
- Do not introduce new dependencies or addons without explaining why.
- Do not change save schemas without a migration plan.
- Do not build "future multiplayer," "future enterprise," or "future AI automation"
  before the current solo loop works.
- Do not reintroduce LDtk, the world-builder app, or an in-game creator mode. Godot's
  editor is the level tool now.
