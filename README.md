# Sushi Valley

A single-player RPG where you learn Japanese by playing it. Gather, craft, fight, and
progress — with spaced-repetition recall gating real progress instead of a quiz sitting
next to the game.

Godot 4.7 · GDScript · desktop-first (Windows).

**▶ Play in your browser: https://greenhmatthew-ux.github.io/sushi-valley/**

Every push to `master` re-exports the game and redeploys the site
(`.github/workflows/deploy.yml`), so the live build always matches the repo.

## Running

Requires Godot 4.7.1. This repo assumes it at `C:\Users\curby\Godot\Godot_v4.7.1-stable_win64.exe`.

```sh
# open in the editor
godot --path .

# run the game
godot --path . --quit-after 0

# run headless logic tests
godot --headless --path . --script res://tests/smoke_db.gd
```

## Layout

```
assets/   art + audio (509 files) — 16px pixel art, Nearest filter project-wide
data/     content tables (game/) and learning data (learning/) as plain JSON
src/
  autoload/  global singletons: Bus (signals), DB (content tables)
  learning/  SRS + learning profile — pure logic, headless-testable
  systems/   combat, crafting, quests, shops, farm, expeditions, raids — pure logic
  entities/  player, NPCs, enemies, resource nodes
  ui/        HUD, dialogue, recall prompt, tabbed menu
  scenes/    title, world levels, combat
tests/    headless logic tests
docs/     design docs + PORT_NOTES.md
```

## Content

1392 spaced-repetition cards across 138 lessons, drawn from 11 imported Anki decks plus
hand-authored kana. 167 items, 76 enemies, 68 abilities, 78 recipes, 18 quests.

## History

Ported from a Vite + TypeScript + Phaser build, archived at
[greenhmatthew-ux/Kana](https://github.com/greenhmatthew-ux/Kana). See
[docs/PORT_NOTES.md](docs/PORT_NOTES.md) for what carried over, what was rebuilt, and why.

## Credits

Art and audio licensing is tracked in [CREDITS.md](CREDITS.md) and
[docs/LICENSE_AUDIT.md](docs/LICENSE_AUDIT.md).
