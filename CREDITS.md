# Credits and Asset Licenses

Sushi Valley uses curated third-party art and audio from the owner's local source library. This
page is the human-facing credit summary; these documents point to runtime authorities and summarize
known provenance/import records:
[`docs/ASSET_MANIFEST.md`](docs/ASSET_MANIFEST.md),
[`docs/LICENSE_AUDIT.md`](docs/LICENSE_AUDIT.md), and
[`assets/licenses/THIRD_PARTY_ASSETS.md`](assets/licenses/THIRD_PARTY_ASSETS.md).

## Current game art and audio

- **Ninja Adventure - Asset Pack** by Pixel-boy & AAA - CC0. Characters, NPCs, enemies,
  bosses, terrain, water, buildings, objects, items, UI/VFX, music, and ambient/UI sounds.
- **Kenney** - CC0. Selected town/dungeon art, characters, UI, interface sounds, props,
  and travel/resource art currently ship; other Kenney processed imports are registry-only.
- **Kyrise's 16x16 RPG Icon Pack V1.3** by Kyrise - CC BY 4.0. Item, gear, and material
  icons. https://creativecommons.org/licenses/by/4.0/ and https://kyrise.itch.io/
- **Serene Village Revamped** by LimeZu - owner-confirmed commercial use. Building and
  animated village art; retained entitlement required.
- **sushi_pixel_set** by Kyukei_dot - commercial game use. Sushi and tea art; optional credit,
  no redistribution/resale, NFT use, or AI training.
- **Sprout Lands Basic** - owner-confirmed commercial use. Furniture, biome, crop, and
  resource-sheet cuts.
- **PunyMonsters** - owner-confirmed commercial use. Selected 32x32 regional enemies.
- **EPIC RPG World Pack - Ancient Ruins demo** - selected Eastern Reach ruins art. Explicit
  release terms must be archived before commercial release.
- **Helton Yan's Pixel Combat SFX** - owner-confirmed commercial use. Combat sound effects.
- **Farm RPG FREE 16x16 - Tiny Asset Pack** - development-only crop art currently tracked
  for commercial purchase or replacement in `docs/ASSET_PURCHASE_BACKLOG.md`.

## Registered processed imports not confirmed in current runtime

- **CraftPix free packs** - CraftPix Free License. Registered trees, forest objects, farm plants,
  minerals, crystals, and RPG UI remain in the processed pool. Raw-pack redistribution and use for
  AI/ML training, testing, validation, or improvement are prohibited.
- **Kenney Animal Pack Remastered, Fish Pack, Foliage Sprites, and Interface Sounds** - CC0
  registered imports; verify a real public runtime reference before calling a specific file in use.

The full `D:\Asset Library` is a candidate pool, not a list of shipped or approved sources.
Development imports must be inspected and rights-tracked; commercial release builds may contain
only license-cleared, repo-local assets with every required credit and restriction honored.

## Speech and learning audio

Japanese pronunciation currently uses the browser/OS Web Speech API. No third-party Japanese
voice corpus is bundled unless it is separately credited and added to the license registry.

## Original and legacy assets

Original SVG art created for the earlier Kana Sprint app remains CC0 1.0. Legacy files are kept
as reference material and are not the current Phaser runtime authority.

## Reference projects

Engine and game repositories under `D:\RPG Game Engine References` are read-only study sources.
No source code, story, characters, maps, music, or sprites are copied from them. See
[`docs/ENGINE_REFERENCE_DEEP_DIVE.md`](docs/ENGINE_REFERENCE_DEEP_DIVE.md).

## Code and libraries

- Project code is MIT-licensed; see `LICENSE`.
- Phaser is used under its MIT license.

When a new asset enters runtime, update its machine-readable registry record and every legally
required human-facing credit in the same working slice.
