# Asset License Audit

The art source pool is the full `D:\Asset Library` tree: both `Assets` and `Assets 2`.
Presence in that library means **available for inspection**, not automatically cleared for
use. Learning media may also come from an independently audited official source, as Kanji
alive does below. See [`ASSET_LIBRARY_GUIDE.md`](ASSET_LIBRARY_GUIDE.md) for art-selection
rules and [`ART_STANDARD.md`](ART_STANDARD.md) for the current in-game art canon.

There is no build tooling, JSON registry, or audit script in this project (no `npm`, no
`package.json`). The only reliable way to know what's actually in use is to grep the running
`.tscn`/`.gd` files for `res://assets/...` paths — see `CREDITS.md` for the current result of
doing that.

## Runtime status (verified 2026-07 against the actual game, not a registry)

| Source | License | Status |
| --- | --- | --- |
| Ninja Adventure - Asset Pack | CC0 1.0 | In use for art and six verified music tracks. No restrictions. |
| Serene Village Revamped (LimeZu) | Owner-confirmed commercial, no license file in the pack | In use. Re-confirm before commercial release. |
| Sprout Lands - Sprites - Basic pack (Cup Nooble) | **Non-commercial only** per the pack's own `read_me.txt`; no AI-training use; credit required | In use for dev. **Blocks commercial release** until a commercial license is separately obtained. |
| Kyrise's 16x16 RPG Icon Pack V1.3 | CC BY 4.0 | In use (item icons). Attribution required. |
| Kanji alive pronunciation audio | CC BY 4.0 | In use. 366 unmodified human-recorded Ogg clips mapped to 459 cards; attribution required. |
| Mana Seed RPG Starter Pack | Free, but explicitly **forbids any use alongside generative AI** (including AI-assisted code) | **Removed 2026-07** — incompatible with an AI-assisted dev workflow. Do not reimport. |

### Verified Ninja Adventure music mapping

The following files are byte-identical copies from
`D:\Asset Library\Assets\Ninja Adventure - Asset Pack\Audio\Musics\`. The source
pack's `README.md` names Pixel-boy and AAA as its creators and releases the pack
under CC0; its bundled `LICENSE.txt` contains the CC0 1.0 Universal terms.

| Runtime asset | Original filename |
| --- | --- |
| `assets/audio/music/title.ogg` | `1 - Adventure Begin.ogg` |
| `assets/audio/music/village.ogg` | `33 - Calm Village.ogg` |
| `assets/audio/music/forest.ogg` | `37 - Dark Forest.ogg` |
| `assets/audio/music/interior.ogg` | `27 - Chill.ogg` |
| `assets/audio/music/battle.ogg` | `17 - Fight.ogg` |
| `assets/audio/music/mountain.ogg` | `19 - Ascension.ogg` |

This music audit does not cover or make a provenance claim for
`assets/audio/sfx/`.

## Blocked

- **Mana Seed** (any file, any sub-pack) — see above. The license text ("NO AI, NO
  EXCEPTIONS.txt") is unambiguous: delete the assets if genAI is anywhere in the dev
  pipeline. It is.
- Never ship ripped or fan assets, excluded commercial IP, CC BY-NC/BY-ND, personal-use-only,
  or license-ambiguous content without written clearance.
- Imported Anki deck media remains excluded. A deck file containing audio does not grant
  redistribution rights; approved pronunciation is sourced and attributed independently.

## Before a commercial release

1. Re-confirm the Serene Village Revamped entitlement (no license file ships with the pack;
   the only record is the owner's prior confirmation).
2. Resolve Sprout Lands' non-commercial restriction — either obtain a commercial license from
   Cup Nooble or replace the Sprout Lands-sourced files (`sprout-basic-grass-biome.png`,
   `sprout-basic-furniture.png`, `door.png`, plus the two runtime `Meadow`/`Detail` layers
   built from it in `world.gd`/`wilds.gd`).
3. Scan for any newly-imported pack the same way: confirm it's actually rendered (grep for
   its `res://assets/...` path), then read that pack's real license file in
   `D:\Asset Library` — don't trust an inherited credits list.

---

This file replaces an earlier version written for the frozen TypeScript/Phaser build. It
referenced `npm run reboot:audit-assets`, a `.external-cache/` scan output, and
`assets/licenses/asset-manifest.json` / `THIRD_PARTY_ASSETS.md` — none of which exist in this
Godot project. It also listed several packs (Kenney, CraftPix, PunyMonsters, sushi_pixel_set,
Helton Yan SFX, EPIC RPG World Pack, Farm RPG FREE) that are not actually referenced by any
current `.tscn`/`.gd` file. If a future slice imports one of them for real, verify its license
fresh (packs get relicensed) and add it to the table above.
