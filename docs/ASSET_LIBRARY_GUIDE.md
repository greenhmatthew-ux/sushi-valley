# Sushi Valley Asset Library Guide

This guide replaces the old asset shortlist, frozen inventory, purchase-recommendation,
and gap reports. Those documents described an earlier folder layout and made a small set of
packs look like a whitelist. It was not one.

## Scope

The full external source pool is the entire `D:\Asset Library` tree:

| Source root | Current top-level pack folders | Role |
| --- | ---: | --- |
| `D:\Asset Library\Assets` | 67 | Original art, audio, and 3D source collection |
| `D:\Asset Library\Assets 2` | 34 | Additional icons, UI, effects, tiles, characters, buildings, food, and audio |
| **Combined** | **101** | **All are eligible for inspection; none are automatically approved for release** |

This is a dated structural snapshot, not a quota. New folders may be added. Search both
roots for every art task instead of assuming the most familiar pack is the only option.

Ninja Adventure remains a useful 16x16 base vocabulary for established Valley areas because
its characters, terrain, enemies, objects, UI, effects, and audio are internally coherent.
That preference is not an exclusivity rule. Use another library asset when it fits the area,
mechanic, perspective, scale, silhouette, or visual weight better.

## Asset states

Do not use `available`, `approved`, `imported`, and `in use` as synonyms.

| State | Meaning |
| --- | --- |
| Available | Present somewhere under `D:\Asset Library`; candidate for inspection only |
| License-reviewed | Local terms or owner entitlement have been checked for the intended release |
| Imported | Selected source files were copied or processed into a repo-local path |
| Runtime | Registered or referenced by the game and loadable over HTTP |
| In use | Actually placed in an authored map, scene, interface, or audio flow |
| Blocked | Non-commercial, ripped, excluded IP, or unresolved rights; never ship |

## Sources of truth

This is the Godot build. There is no npm tooling, no Phaser preload manifest, no World
Builder, and no LDtk here — the Godot editor's scenes ARE the level tool (see the project's
`CLAUDE.md`: never reintroduce LDtk or a world-builder app).

| Question | Authority |
| --- | --- |
| What may be searched? | Both external roots listed above |
| What art is actually rendered in the game? | `grep -roh "res://assets/[^\"]*\.png" --include=*.tscn --include=*.gd .` from the repo root — this is ground truth, not a registry |
| What's the current in-game art canon? | [`ART_STANDARD.md`](ART_STANDARD.md) |
| What licenses/attribution are known? | [`LICENSE_AUDIT.md`](LICENSE_AUDIT.md) and `CREDITS.md` |

There is no separate manifest/catalog/registry to keep in sync — the scenes themselves are
the only authority on what's in use. When you import something, the credit/license docs are
the only bookkeeping required.

## Inclusive coverage map

The examples below are navigation hints, not a whitelist.

| Need | Representative source families to inspect |
| --- | --- |
| Terrain, paths, water, buildings, interiors | Ninja Adventure, Serene Village, GuttyKreum Japanese City, Sunnyside World, Super Retro World, EPIC Ancient Ruins, Seasonal Tilesets, GB Modular Houses, Kenney town/dungeon packs — **not Mana Seed, see below** |
| Trees, rocks, crops, resources, props | Ninja Adventure, Sprout Lands, Serene Village, Sunnyside, Kenney foliage/farm packs, CraftPix nature/mineral/crystal packs, Quaternius nature/crops, crafting-material collections |
| Players, NPCs, enemies, bosses, critters | Ninja Adventure, Puny characters/monsters, Forest Monsters, predator plants, Kenney character/animal packs, Tiny Swords, Kings and Pigs, Quaternius characters/animals |
| Items, loot, gear, food, sushi | Kyrise, Ninja Adventure, sushi_pixel_set, Ghostpixxells food, Free Pixel Food, RPG/item/icon collections, potion/key/mineral packs, Shikashi, Raven Fantasy HD |
| UI, inventory, prompts, icons | Ninja Adventure UI, Kenney UI/input packs, Complete UI Essential, Free Basic Pixel Art UI, Retro Inventory, one-bit icons, Dusk Icons, RPG icon collections |
| VFX, particles, magic, weather | Ninja Adventure FX, Foozle Pixel Magic Effects, Kenney effects, animated keys/potions, seasonal and weather-capable sheets |
| Music, ambience, UI and combat sound | Ninja Adventure audio, Kenney audio, Helton Yan combat/Shonen packs, the library Audio folder, and other licensed audio collections |
| 3D render/reference sources | Sushi Restaurant Kit, Kenney 3D kits, Quaternius packs, modular buildings/dungeons/nature; 3D availability does not change the current 2D Godot direction |

**Never use Mana Seed for anything.** Its license explicitly forbids use alongside
generative AI content, including AI-assisted code — see `LICENSE_AUDIT.md`.

## Selection workflow

1. Define the visual role and on-screen size before searching.
2. Search the whole library by role, filename, pack, dimensions, and format.
3. Open the source sheet or animation before choosing a frame. Confirm perspective, grid,
   transparency, top/middle/bottom pieces, direction order, animation layout, and native scale.
4. Compare the candidate beside nearby runtime art. Prefer local coherence, but do not keep a
   weaker asset solely because it comes from the established base pack.
5. Verify commercial rights and attribution. Presence in the library is not license approval.
6. Copy only the selected file or crop into a repo-relative processed/runtime path. External
   absolute paths are never runtime paths.
7. Record source pack, source path, selected frame/crop, native dimensions, runtime path,
   license evidence, required credit, intended use, scale, anchor, and solid footprint.
8. Update `CREDITS.md` and `docs/LICENSE_AUDIT.md` in the same slice.
9. Test the asset in context in the running scene. Collision uses the visible ground-contact
   footprint, never the full transparent texture rectangle (see `ART_STANDARD.md`).

## Per-import completion checklist

- Source sheet was visually inspected.
- Perspective, scale, frame layout, and surrounding art match intentionally (16px native,
  see `ART_STANDARD.md`).
- License status and attribution are recorded in `CREDITS.md` / `docs/LICENSE_AUDIT.md`.
- Only selected files/crops were copied; raw packs remain external.
- Runtime paths are `res://assets/...` and load without missing-texture errors.
- Ground-contact collision, anchor, depth, and animation were checked in the real scene.
- The relevant headless test suite (`tests/run_all.ps1`) still passes.

The goal is broad choice with disciplined import—not a narrow shortlist and not an unreviewed
bulk dump.
