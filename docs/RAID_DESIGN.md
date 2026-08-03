# Raid Design (first vertical slice playable — replaces "Quest")

**Terminology lock:** the old "Quest" concept is renamed **Raid** (player-facing) /
`RaidSystem` (code). A Raid is a structured RPG objective — a short mission, delivery, story
beat, combat objective, learning challenge, or town request — NOT a roguelite run.

## A Raid has
title, description, objective, start condition, completion condition, reward, learning focus,
related NPC, optional combat encounter, optional Expedition unlock, and a link to the shared
learning profile.

## Examples
Lunchbox Raid, Forest Gate Raid, Market Delivery Raid, Shrine Cleanup Raid, **Sushi Prep Raid**
(first), Lost Ingredient Raid.

## First Raid — Sushi Prep
- Start: talk to Hana after the intro recall.
- Objective: clear the focused Food & Drink recall, then defeat the Pantry Oni.
- Reward: 80 coins, one Recipe Stamp, two rice balls, and the discovered Raid recipe.
- Unlocks: saved Raid completion plus the Forest Lunchbox Expedition.

## Structure
`src/systems/raid_logic.gd` owns the small state machine (ported from the archived
`RaidSystem.ts`); authored definitions live in `data/game/raids.json`. Do not split speculative
Raid classes before another mission proves the boundary.

Sushi Prep is live in the Godot build: Hana (`src/entities/raid_teacher.gd`, a teacher_npc that
also runs a Raid) briefs it once her first lesson has been passed, then a focused Food & Drink
recall, the Pantry Oni through the ordinary combat panel, and the Recipe Stamp/coins/food reward
with Raid recipe discovery, Forest Expedition unlock, and saved completion. Stages persist as
`profile.data.raids` in the TS-compatible shape, so an archived save still loads. Covered by
`tests/test_raid.gd`.

**RaidDef:** id, displayName, description, npcId, requiredFlags, learningFocus, encounterId,
reward `{ coins?, items? }`, unlockFlags, unlockExpeditionIds, repeatable.

Keep the system small: one tracker and the existing Journal/Quests surface, not a second journal UI.
Sushi Prep and the first Forest Expedition are already playable; the next Raid slice should improve
status presentation or prove one additional structured mission without reviving the legacy deckbuilder.

## Legacy Quest migration
The legacy webapp's Quest/deckbuilder code is reference material, not the reboot Raid system.
Rebuild a valuable activity later in the shared Vite/Phaser/learning stack only after its own
approved slice; do not patch legacy logic into Raid or delete a legacy learning route without a
tested replacement.
