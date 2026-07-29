# Credits and Asset Licenses

Sushi Valley (the Godot build) uses curated third-party art from the owner's local
`D:\Asset Library`. This page lists every source pack actually rendered in the current game,
verified against the running scenes — not an aspirational or inherited list.

## Art in use

- **Ninja Adventure - Asset Pack** by Pixel-boy & AAA — **CC0 1.0**. The player, all enemies
  (mushroom/kappa/lantern-ghost/slime), NPCs (villager, quest-giver, merchant), and the
  hearts HUD icon. No restrictions of any kind; safe for any use including AI-assisted
  development.
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
  ("Icons by Kyrise, https://kyrise.itch.io/"). Item icons in `assets/icons/items/`.

## Not currently verified

- `assets/icons/abilities/` (33 files, id-matched to `data/game/abilities.json` but not yet
  wired into any UI) — provenance not traced this pass. Verify before building the
  combat-skills panel that would put these on screen.

## Removed for licensing (2026-07)

- **Mana Seed RPG Starter Pack** (`home_interiors_timber_roof.png`) was used for one
  interior room's floor/wall tiles. Its license explicitly states the art **must not be used
  alongside any generative AI content** — including AI-assisted code — and asks that the
  assets be deleted from any project that doesn't comply. Since this project is built with
  Claude Code, the file was removed and the room rebuilt from an already-used Serene Village
  tile (same texture, floor at full brightness / walls darker via modulate). Do not
  reintroduce any Mana Seed asset into this project.

## Audio and voices

**There is no Japanese audio in this game, and NPCs have no voices.** Every imported deck
is `mediaPolicy: excluded`, so no recorded pronunciation was ever brought into the project.

An earlier build synthesised pronunciation with the OS text-to-speech engine. That was
removed: a synthesised voice is not a real voice, and in a game whose purpose is teaching a
language, an approximation of native pronunciation is a liability rather than a feature.
Japanese is presented as text only until genuine recorded audio with clear rights exists.

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
