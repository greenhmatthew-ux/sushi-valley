# Credits and Asset Licenses

Sushi Valley (the Godot build) uses curated third-party art from the owner's local
`D:\Asset Library`. This page lists every source pack actually rendered in the current game,
verified against the running scenes — not an aspirational or inherited list.

## Art in use

- **Ninja Adventure - Asset Pack** by Pixel-boy & AAA — **CC0 1.0**. The player, all enemies
  (mushroom/kappa/lantern-ghost/slime/snake/raccoon/owl), NPCs (villager, quest-giver,
  merchant), hearts HUD icon, Forge anvil, Workshop hammer, and the seven rendered Talent
  icons (Blade Sweep, Kunai Toss, Kana Bolt, Iron Brace, Ki Focus, Rune Ward, Riposte).
  Ki Focus, Rune Ward, and Riposte are the unmodified `Ui/Skill Icon/Spell/AttackUpgrade.png`,
  `Ui/Skill Icon/Spell/DefenseUpgrade.png`, and `Ui/Skill Icon/Spell/Counter.png` sources.
  No restrictions of any kind;
  safe for any use including AI-assisted development.
- **Serene Village Revamped** by LimeZu — commercial-use entitlement previously confirmed by
  the owner; no license file ships in the pack folder itself, so that confirmation is the
  only record. Village/wilds terrain, all props (trees, rocks, barrels, crates, berry bush),
  and the building exteriors. **Re-confirm entitlement before any commercial release.**
- **Sprout Lands - Sprites - Basic pack** by Cup Nooble — the pack's own `read_me.txt`
  states **non-commercial projects only**, credit required ("Assets - From: Sprout Lands -
  By: Cup Nooble"), no AI-training use, no redistribution of the raw pack. Used for the
  meadow ground-detail decals (grass tufts, wildflowers, mushrooms) in both the village and
  the wilds, plus interior furniture and the door sprite. **This conflicts with an earlier
  version of this file that claimed "commercial use" — that claim could not be verified
  against the actual license text and should not be relied on. Confirm a separate/commercial
  license before any commercial release; non-commercial/dev use is fine as-is.**
- **Kyrise's 16x16 RPG Icon Pack V1.3** by Kyrise — **CC BY 4.0**, attribution required
  ("Icons by Kyrise, https://kyrise.itch.io/"). Item icons in `assets/icons/items/`, including
  the Bamboo Breeze Tonic added from `icons/16x16/potion_01h.png`.

## Not currently verified

- The 26 ability icons not named `sweep`, `kunai`, `kana_bolt`, `brace`, `ki_focus`,
  `rune_ward`, or `riposte` remain unwired and
  provenance-unverified. Verify or replace each before rendering it in the Skills UI.

## Removed for licensing (2026-07)

- **Mana Seed RPG Starter Pack** (`home_interiors_timber_roof.png`) was used for one
  interior room's floor/wall tiles. Its license explicitly states the art **must not be used
  alongside any generative AI content** — including AI-assisted code — and asks that the
  assets be deleted from any project that doesn't comply. Since this project is built with
  Claude Code, the file was removed and the room rebuilt from an already-used Serene Village
  tile (same texture, floor at full brightness / walls darker via modulate). Do not
  reintroduce any Mana Seed asset into this project.

## Audio and voices

### Music

- **Ninja Adventure - Asset Pack** by Pixel-boy & AAA — **CC0 1.0**. Six
  unmodified Ogg tracks are bundled for the current title, exploration, interior,
  and combat music:

  | Local asset | Original pack filename |
  | --- | --- |
  | `assets/audio/music/title.ogg` | `Audio/Musics/1 - Adventure Begin.ogg` |
  | `assets/audio/music/village.ogg` | `Audio/Musics/33 - Calm Village.ogg` |
  | `assets/audio/music/forest.ogg` | `Audio/Musics/37 - Dark Forest.ogg` |
  | `assets/audio/music/interior.ogg` | `Audio/Musics/27 - Chill.ogg` |
  | `assets/audio/music/battle.ogg` | `Audio/Musics/17 - Fight.ogg` |
  | `assets/audio/music/mountain.ogg` | `Audio/Musics/19 - Ascension.ogg` |

  Source: <https://pixel-boy.itch.io/ninja-adventure-asset-pack>. The pack's
  included `README.md` and `LICENSE.txt` release the assets under CC0 1.0;
  attribution is appreciated but not required.

This verifies the six music files above only. It does not establish provenance
for the separate files under `assets/audio/sfx/`.

### Japanese pronunciation

- **Kanji alive** — human recordings by male and female native Japanese speakers,
  **CC BY 4.0**. Sushi Valley bundles 366 unmodified Ogg recordings and maps them by
  explicit card id to 459 current vocabulary cards whose written form and reading both
  match the source catalog.
  - Attribution: **Audio from Kanji alive (kanjialive.com), licensed CC BY 4.0.**
  - Source: <https://github.com/kanjialive/kanji-data-media>
  - Pinned source revision: `2d2a4931eec6e0cb532d5102766273c2323f96db`
  - License: <https://creativecommons.org/licenses/by/4.0/>
  - Import details and per-file checksums:
    `assets/audio/japanese/kanji_alive/NOTICE.md` and
    `data/learning/pronunciation-audio.json`

Every imported Anki deck remains `mediaPolicy: excluded`. Its audio was not copied into
this project: availability inside an `.apkg` is not evidence of redistribution rights.
Kanji alive is an independently licensed pronunciation source joined to approved cards
only after written-form and reading validation. A card stays silent when that validation
is ambiguous or fails.

An earlier build synthesised pronunciation with the OS text-to-speech engine. That was
removed: a synthesised voice is not a real voice, and in a game whose purpose is teaching a
language, an approximation of native pronunciation is a liability rather than a feature.

Do not reintroduce text-to-speech or any generated voice.

## Code

Project code license: see `LICENSE`.

---

This file replaces an earlier version that described the frozen TypeScript/Phaser build's
asset inventory (Kenney, CraftPix, PunyMonsters, sushi_pixel_set, Helton Yan SFX, an
`npm run reboot:audit-assets` tracking script, JSON registries under `assets/licenses/`,
etc.) — none of which exist in or apply to this Godot project. If any of those packs get
imported into the Godot game later, add them here at that time, verified the same way as
the packs above: confirm the actual file is rendered in a real scene, then read that pack's
real license file in `D:\Asset Library`.
