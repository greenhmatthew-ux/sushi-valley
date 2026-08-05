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
| Sprout Lands - Sprites - Basic pack (Cup Nooble) | **Non-commercial only** per the pack's own `read_me.txt`; no AI-training use; credit required | **Reimported 2026-08-04** for `assets/tilesets/tilled_dirt.png` (farm plot soil), by project decision (see `CLAUDE.md` -> Licensing). Non-commercial terms unchanged and unresolved; recorded for accuracy, not as a gate. |
| Farm RPG FREE 16x16 - Tiny Asset Pack | **Unstated in the pack** | In use 2026-08-04 for `assets/props/crop_stages.png` (four crops x five growth stages on the farm plots). No license file ships with the pack; recorded as unknown. |
| Kyrise's 16x16 RPG Icon Pack V1.3 | CC BY 4.0 | In use (item icons). Attribution required. |
| Free Pixel Food 16x16 (Alex) | CC BY 4.0 per the pack's `Note from the artist.txt` | In use 2026-08-05 for `herb_tea` and `matcha_latte`. Attribution required. |
| 16x16 RPG Item Pack | **Unstated in the pack** | In use 2026-08-05 for 11 weapon/armour icons Kyrise has no equivalent of. No license file ships with the pack; recorded as unknown. |
| `Assets 2/items` (1,244 icons) | **Unstated in the folder** | In use 2026-08-05 for ~35 organic-drop, ore, dish and cloak icons no other pack covers. No license file ships alongside it; recorded as unknown. |
| Kanji alive pronunciation audio | CC BY 4.0 | In use. 366 unmodified human-recorded Ogg clips mapped to 459 cards; attribution required. |
| Imported Anki deck audio | **Unstated by every source deck** | In use by project decision (see `CLAUDE.md` → Licensing). 1,087 clips voicing 1,365 cards, lifted from the `.apkg` files the cards came from and matched by Anki note id. Believed to originate from published courses (Nihongo Fun & Easy, JapanesePod101); no permission granted or verified. Recorded here for accuracy, not as a gate. |
| Mana Seed RPG Starter Pack | Free, but explicitly **forbids any use alongside generative AI** (including AI-assisted code) | **Removed 2026-07** — incompatible with an AI-assisted dev workflow. Do not reimport. |

The Bamboo Breeze Tonic icon is the unmodified 16x16 source
`icons/16x16/potion_01h.png` from the licensed Kyrise pack, copied to
`assets/icons/items/bamboo_tonic.png` for the repo-local runtime path.

The Ki Focus Talent icon is the unmodified Ninja Adventure source
`Ui/Skill Icon/Spell/AttackUpgrade.png`, copied to
`assets/icons/abilities/ki_focus.png`. The pack's local `LICENSE.txt` is CC0 1.0.

The Rune Ward Talent icon is the unmodified Ninja Adventure source
`Ui/Skill Icon/Spell/DefenseUpgrade.png`, copied to
`assets/icons/abilities/rune_ward.png` under the same CC0 1.0 license.

The Riposte Talent icon is the unmodified Ninja Adventure source
`Ui/Skill Icon/Spell/Counter.png`, copied to
`assets/icons/abilities/riposte.png` under the same CC0 1.0 license.

The Blood Blade Talent icon is the unmodified Ninja Adventure source
`Ui/Skill Icon/Spell/Cut.png`, copied to
`assets/icons/abilities/blood_blade.png` under the same CC0 1.0 license.

The first follow-up Talent tier uses four more unmodified Ninja Adventure sources:

| Talent | Runtime asset | Original source |
| --- | --- | --- |
| Iaido Cut | `assets/icons/abilities/iaido.png` | `Ui/Skill Icon/Spell/MagicWeapon.png` |
| Pinning Shot | `assets/icons/abilities/pinning_shot.png` | `Ui/Skill Icon/Items & Weapon/Arrow.png` |
| Glyph Storm | `assets/icons/abilities/glyph_storm.png` | `Ui/Skill Icon/Spell/BookThunder.png` |
| Fortress Wall | `assets/icons/abilities/fortress.png` | `Ui/Skill Icon/Items & Weapon/Guard.png` |

The Mountain Pass region uses six more unmodified Ninja Adventure sources, all CC0 1.0:

| Runtime asset | Original source |
| --- | --- |
| `assets/tilesets/ninja_relief.png` | `Backgrounds/Tilesets/TilesetRelief.png` |
| `assets/tilesets/ninja_relief_detail.png` | `Backgrounds/Tilesets/TilesetReliefDetail.png` |
| `assets/sprites/enemy_lizard.png` | `Actor/Monster/Lizard/Lizard.png` |
| `assets/sprites/enemy_mole.png` | `Actor/Monster/Mole/Mole.png` |
| `assets/sprites/enemy_bear.png` | `Actor/Monster/Bear/SpriteSheet.png` |
| `assets/sprites/enemy_bat.png` | `Actor/Monster/BlueBat/SpriteSheet.png` |
| `assets/sprites/enemy_tengu.png` | `Actor/Character/Tengu/SpriteSheet.png` |

The ingredient-cache sprite is the unmodified two-frame Ninja Adventure source
`Items/Treasure/LittleTreasureChest.png`, copied to
`assets/objects/ninja_little_treasure_chest.png`. Runtime uses its closed 16x16 frame.

The Garden Compost icon is the unmodified Ninja Adventure source `Items/Object/Bag.png`,
copied to `assets/icons/items/compost.png` at its native 16x16 size.

The permanent gathering tools use three more unmodified, native-size Ninja Adventure
CC0 sources:

| Runtime asset | Original source |
| --- | --- |
| `assets/icons/items/copper_pick.png` | `Items/Tool/Pickaxe.png` |
| `assets/icons/items/trail_hatchet.png` | `Items/Tool/Axe.png` |
| `assets/icons/items/herb_sickle.png` | `Items/Tool/Sickle.png` |

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
- ~~Imported Anki deck media remains excluded.~~ **Superseded 2026-07-30.** Deck audio is
  now in use by project decision (see the table above and `CLAUDE.md` → Licensing). A deck
  file containing audio still grants no redistribution rights, and that is recorded rather
  than resolved. Kanji alive remains separately sourced, validated, and attributed.

## Before a commercial release

1. Re-confirm the Serene Village Revamped entitlement (no license file ships with the pack;
   the only record is the owner's prior confirmation).
2. Scan for any newly-imported pack the same way: confirm it's actually rendered (grep for
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
