# Credits and Asset Licenses

Sushi Valley (the Godot build) uses curated third-party art from the owner's local
`D:\Asset Library`. This page lists every source pack actually rendered in the current game,
verified against the running scenes — not an aspirational or inherited list.

## Art in use

- **Kenney Game Assets All-in-1 (Tiny Town)** by Kenney — **CC0 1.0**. The outdoor ground
  grass, as `assets/tilesets/kenney_ground.png`: four 16px tiles sliced from Tiny Town's
  `tilemap_packed.png` — plain grass (0,0), tufted grass (1,0), flowered grass (2,0) and
  gravel (7,3). Only the first two are painted today; the village, its edge underlay and the
  Wilds re-texture their grass off Serene's flat fill onto these at the end of `_ready`.
  Chosen by scanning both library roots for a 16px, fully opaque, self-tiling green tile
  nearest Serene's own grass colour — it won on palette distance by a wide margin, and was
  checked beside Serene's houses, props and road edge tiles before adoption.
- **Ninja Adventure - Asset Pack** by Pixel-boy & AAA — **CC0 1.0**. The player, all enemies
  (mushroom/kappa/lantern-ghost/slime/snake/raccoon/owl), NPCs (villager, quest-giver,
  merchant, plus the pack's Villager4, Villager5, Villager6, Noble, OldMan, Monk, Master,
  Hunter, Inspector and Shaman sheets, added so no two people in a region share a look,
  plus Village6 as `npc_host.png` for the house Host and Eskimo as `npc_lookout.png` for the
  pass lookout Tomas -- those two had been sharing faces with Hana and the wilds Keeper
  across regions, which `tests/test_npc_faces_differ.gd` now prevents; the pack has ~76 more
  unused sheets at this exact 64x112 size),
  the pack's Spirit monster sheet for the Forest Wraith, hearts HUD icon, Forge anvil, Workshop hammer, the house interior floor,
  furniture and exit door, and the twelve rendered Talent icons (Blade Sweep, Kunai Toss,
  Kana Bolt, Iron Brace, Ki Focus, Rune Ward, Riposte, Blood Blade, Iaido Cut, Pinning Shot,
  Glyph Storm, Fortress Wall), plus the 16px treasure
  chest used for authored ingredient caches, the tied sack used for Garden Compost, and the
  native 16px Pickaxe, Axe, and Sickle icons used by the three permanent gathering tools. The
  Mountain Pass is built from the pack's `TilesetRelief` rock terrain and `TilesetReliefDetail` scree, and its foes use the
  pack's Lizard, Mole, Bear, BlueBat and Tengu sheets.
  `assets/props/building_lake_house.png` is the pack's `Backgrounds/Tilesets/TilesetHouse.png`
  timber house, tiles x25-28 of rows 8, 9, 12 and 13 assembled at the width the art was drawn
  for, giving the lake house a Japanese building of its own instead of a second copy of
  House1's red-roofed cottage.
  Ki Focus, Rune Ward,
  Riposte, and Blood Blade are the unmodified
  `Ui/Skill Icon/Spell/AttackUpgrade.png`, `Ui/Skill Icon/Spell/DefenseUpgrade.png`,
  `Ui/Skill Icon/Spell/Counter.png`, and `Ui/Skill Icon/Spell/Cut.png` sources.
  No restrictions of any kind;
  safe for any use including AI-assisted development.
- **Serene Village Revamped** by LimeZu — commercial-use entitlement previously confirmed by
  the owner; no license file ships in the pack folder itself, so that confirmation is the
  only record. Village/wilds terrain, all props (trees, rocks, barrels, crates, berry bush),
  building exteriors, and village meadow/edge flower details. The Wilds outpost
  (`assets/props/building_outpost.png`) is the pack's wide green-roofed lodge, lifted whole
  from the sheet at 166,464 (69x59) and padded to 80x64 so it aligns to the tile grid without
  any of the art being cut. It replaced a second copy of `building_house.png`, which had the
  frontier outpost rendering as a pixel-identical twin of the village's House 1. The sheet
  carries six distinct complete house designs in three colourways each; only three are used
  so far. **Re-confirm entitlement before any commercial release.**
- **Kyrise's 16x16 RPG Icon Pack V1.3** by Kyrise — **CC BY 4.0**, attribution required
  ("Icons by Kyrise, https://kyrise.itch.io/"). The primary source for `assets/icons/items/`,
  including the Bamboo Breeze Tonic added from `icons/16x16/potion_01h.png`.
- **Free Pixel Food (16x16)** by Alex — **CC BY 4.0** per the pack's own
  `Note from the artist.txt`. Two drinks: `herb_tea` (`coffee_tea.png`) and
  `matcha_latte` (`boba_matcha.png`).
- **16x16 RPG Item Pack** — **no license file ships with the pack; terms unstated.** Used for
  the diagonal polearms, blunt weapons, armour and boots Kyrise has no equivalent of
  (`bamboo_spear`, `storm_ram`, `iron_maul`, `canyon_crusher`, `red_dragon_maul`,
  `hunter_crossbow`, `quilted_armor`, `scale_armor`, `iron_pauldrons`, `iron_sabatons`,
  `bear_greaves`, and the leather-shoulder recolour).
- **`Asset Library/Assets 2/items`** (1,244 16px icons) — **no license file ships with the
  folder; terms unstated.** Used for the organic monster drops, ores, cooked dishes and
  cloaks no other pack covers: pelts, tails, hides, scales, horns, fangs, wings, eyes,
  slime, mushrooms, ore and ingot chunks, the soups/curry/feast bowls, and the two cloaks.

The six dragon scales, the two belts, the leather shoulders, the straw sandals, the
ice-claw boots, and the beast/gold pelts are **hue-and-saturation recolours** of another
icon in this set — the same object in a different material, which is what those items are.
Provenance follows the base icon named above.

## Not currently verified

- The 25 ability icons not named `sweep`, `kunai`, `kana_bolt`, `brace`, `ki_focus`,
  `rune_ward`, `riposte`, `blood_blade`, `iaido`, `pinning_shot`, `glyph_storm`, or
  `fortress` remain unwired and
  provenance-unverified. Verify or replace each before rendering it in the Skills UI.

## Farm and world-object art (2026-08-04)

The farm plots, fishing spots and resource nodes were drawn with coloured `draw_rect` /
`draw_circle` primitives and read as placeholders. They now use real 16px art:

- **Ninja Adventure** (CC0) — `ninja_nature.png` (resource node rocks and plants) and
  `water_ripple.png` (fishing spots). The ripple's flat background colour was made
  transparent on import so it overlays the pond instead of stamping a cyan tile.
- **Farm RPG FREE 16x16 - Tiny Asset Pack** — `crop_stages.png`, four crops with five
  growth stages. No license file ships with the pack; terms are unstated.
- **Sprout Lands - Sprites - Basic pack** (Cup Nooble) — `tilled_dirt.png` for plot soil.
  Reimported after the 2026-07 removal below, by project decision. Its non-commercial
  terms are unchanged; see `docs/LICENSE_AUDIT.md`.

## Removed for licensing (2026-07)

- **Sprout Lands - Sprites - Basic pack** was removed from runtime use after its bundled
  `read_me.txt` proved to be non-commercial-only. Serene Village supplied outdoor meadow
  details and Ninja Adventure the house interior and door. **Partly reverted 2026-08-04** —
  see the farm art section above; the pack is again referenced, deliberately.
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

- **Imported Anki deck audio** — native-speaker recordings that shipped inside the
  `.apkg` files these cards were imported from. 1,087 unmodified clips voice 1,365
  cards: 1,311 matched to their own card by the Anki note id kept at import, and 54
  authored curriculum cards (the kana ladder and the greetings) sharing the recording
  of an identically written imported card, and stored under
  `assets/audio/japanese/decks/` with per-file checksums in
  `data/learning/deck-audio.json`.
  - **License: unstated.** None of the source decks declares one, and the recordings
    are believed to originate from published courses (for example, Nihongo Fun & Easy
    for the travel phrasebook, and JapanesePod101 for the Core 2k/6k vocabulary).
    No permission has been granted or verified. They are used by project decision —
    see the Licensing section of `CLAUDE.md`.
  - Decks used, with their card counts, are listed in `data/learning/deck-audio.json`.
  - Re-importable from the original `.apkg` files with `tools/import_deck_audio.py`.

The packs' card *text* stays `mediaPolicy: excluded` in its metadata, which now records
only that the media is not part of the JSON pack itself.
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
