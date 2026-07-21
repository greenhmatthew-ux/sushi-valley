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

The project has several intentionally different inventories. None should be presented as a
complete replacement for the others.

| Question | Authority |
| --- | --- |
| What may be searched? | Both external roots listed above |
| What does Phaser preload by key? | `src/game/assets/assetManifest.ts` plus scene/system-specific loaders |
| What can the World Builder palette show? | `public/assets/data/asset-catalog.json` |
| What art is actually placed in the world? | LDtk, scene code, and data tables |
| What processed imports are registered? | `assets/licenses/asset-manifest.json` |
| What licenses/attribution are known? | `docs/LICENSE_AUDIT.md`, `assets/licenses/THIRD_PARTY_ASSETS.md`, and `CREDITS.md` |
| What needs purchase or replacement? | `docs/ASSET_PURCHASE_BACKLOG.md` |
| What browser-loadable files ship? | `public/assets/` and the production build |

`public/assets/data/asset-catalog.json` is a curated World Builder palette, not the full
runtime manifest or the full external library. Likewise, the current `reboot:audit-assets`
cache scans only `D:\Asset Library\Assets` by default; its generated score/shortlist is a
search aid and omits `Assets 2`. Never use that cache to declare the full library exhausted.

## Inclusive coverage map

The examples below are navigation hints, not a whitelist.

| Need | Representative source families to inspect |
| --- | --- |
| Terrain, paths, water, buildings, interiors | Ninja Adventure, Serene Village, GuttyKreum Japanese City, Sunnyside World, Super Retro World, EPIC Ancient Ruins, Seasonal Tilesets, Mana Seed, GB Modular Houses, Kenney town/dungeon packs |
| Trees, rocks, crops, resources, props | Ninja Adventure, Sprout Lands, Serene Village, Sunnyside, Kenney foliage/farm packs, CraftPix nature/mineral/crystal packs, Quaternius nature/crops, crafting-material collections |
| Players, NPCs, enemies, bosses, critters | Ninja Adventure, Puny characters/monsters, Forest Monsters, predator plants, Kenney character/animal packs, Tiny Swords, Kings and Pigs, Quaternius characters/animals |
| Items, loot, gear, food, sushi | Kyrise, Ninja Adventure, sushi_pixel_set, Ghostpixxells food, Free Pixel Food, RPG/item/icon collections, potion/key/mineral packs, Shikashi, Raven Fantasy HD |
| UI, inventory, prompts, icons | Ninja Adventure UI, Kenney UI/input packs, Complete UI Essential, Free Basic Pixel Art UI, Retro Inventory, one-bit icons, Dusk Icons, RPG icon collections |
| VFX, particles, magic, weather | Ninja Adventure FX, Foozle Pixel Magic Effects, Kenney effects, animated keys/potions, seasonal and weather-capable sheets |
| Music, ambience, UI and combat sound | Ninja Adventure audio, Kenney audio, Helton Yan combat/Shonen packs, the library Audio folder, and other licensed audio collections |
| 3D render/reference sources | Sushi Restaurant Kit, Kenney 3D kits, Quaternius packs, modular buildings/dungeons/nature; 3D availability does not change the current 2D Phaser direction |

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
7. Record source pack, source path, selected frame/crop, native dimensions, runtime key/path,
   license evidence, required credit, intended use, scale, anchor, and solid footprint.
8. Update the relevant runtime manifest/catalog, license registry, credits, and purchase backlog.
9. Test the asset in context at desktop and touch sizes. Collision uses the visible ground-contact
   footprint, never the full transparent texture rectangle.

## Per-import completion checklist

- Source sheet was visually inspected.
- Perspective, scale, frame layout, and surrounding art match intentionally.
- License status and attribution are recorded.
- Only selected files/crops were copied; raw packs remain external.
- Runtime paths are repo-relative and load without fallback or console errors.
- `assetManifest.ts`, the World Builder catalog, LDtk/data references, and license records were
  updated only where the asset actually participates.
- Ground-contact collision, anchor, depth, and animation were checked in the real scene.
- Relevant typecheck, asset/content test, build, and visual smoke checks pass.

The goal is broad choice with disciplined import—not a narrow shortlist and not an unreviewed
bulk dump.
