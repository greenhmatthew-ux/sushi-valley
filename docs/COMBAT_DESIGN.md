# Reboot Combat System

**Status:** implemented. This document covers regular one-on-one combat in the Vite/Phaser
reboot. It does not describe the preserved legacy combat/activity code or the separate Raid
deckbuilder direction.

## Current loop

1. A world scene pauses and launches `Combat` with an enemy definition or rolled instance.
2. Speed decides who acts first; ties favor the player.
3. Each player turn refreshes to five Energy.
4. The player may repeat affordable Basic Attacks and equipped abilities, use one consumable,
   flee, or end the turn.
5. Recall-gated actions open a shared Notebook prompt. Due cards are preferred; unlocked
   practice cards are the fallback.
6. Correct recall gives the move its full/enhanced effect. A wrong answer reveals the answer,
   updates the shared SRS, and resolves a weaker result rather than cancelling the action.
7. In Speed mode, a player at least four Speed faster receives one extra full turn before the
   enemy responds.
8. The enemy attacks or uses an implemented signature behavior, then the loop repeats.

Victory awards learning XP and coins, saves progression/bestiary flags, rolls drops, and resumes
the launching world scene. Fleeing resumes without victory rewards. Defeat restores HP and returns
the player to the House. There is no separate victory reward screen.

## Builds and actions

- Player stats derive from learning XP level, vitality/power/agility allocation, and equipped gear.
- Basic Attack is always available; the Skills menu supports up to six equipped abilities.
- `src/game/data/abilities.json` owns authored ability data.
- Supported effects include attacks, multi-hit attacks, block, healing, buffs, debuffs, counters,
  parries, lifesteal, cooldowns, and per-turn use limits.
- Samurai, Ranger, Scholar, and Guardian provide role-specific abilities and passives.
- Most role abilities require the matching weapon type.
- The default build equips Strike, Guard, and Focus.

## Learning contract

Combat uses the same `LearningProgressionSystem`, `LearnPrompt`, profile, and `SrsSystem` as the
rest of Sushi Valley. Correct and incorrect answers update the real schedule and profile stats.
There is no combat-only card deck or SRS.

Recall is attached to individual abilities, so more than one prompt can occur in a turn. A wrong
answer currently shows the correct reading/meaning and resolves the move; it does not trigger a
simpler immediate re-ask. Regular combat has no separate Study action.

## Enemies, scaling, and persistence

- `src/game/data/enemies.json` owns enemy definitions.
- World encounters can roll per-instance level and rarity: normal, elite, boss, or world boss.
- `EnemyScaling.ts` scales stats, XP, coins, and rarity.
- Some enemy/boss signatures are implemented in `CombatScene.ts`; they are not all data-driven yet.
- Met/beaten flags and current world HP persist through the shared profile/save systems.
- Raid and Expedition bosses hand completion to their respective systems; Expedition boss drops
  are banked before the instance closes.

## Source map

| Area | Authority |
| --- | --- |
| Turn flow, UI, enemy actions, outcomes | `src/game/scenes/CombatScene.ts` |
| Renderer-independent math and enemy lookup | `src/game/systems/CombatSystem.ts` |
| Shared types | `src/game/combat/CombatTypes.ts` |
| Ability unlock/equip/role/weapon rules | `src/game/systems/Abilities.ts` |
| Level, rarity, stats, and rewards | `src/game/systems/EnemyScaling.ts` |
| Drops, gear, consumables, persistent HP | `CombatDrops.ts`, `Inventory.ts`, `WorldHp.ts` |
| Authored abilities/enemies | `src/game/data/abilities.json`, `src/game/data/enemies.json` |
| Recall and SRS | `src/game/ui/LearnPrompt.ts`, `src/shared/learning/` |

## Coverage and remaining gaps

- `test/game-smoke.mjs` covers repeatable Energy actions, a real final-hit victory and return,
  plus Raid/Expedition boss completion and reload persistence.
- `test/game-quality-gates.mjs` covers boss presentation on touch viewports and flee return.
- `test/game-content-scale.mjs` checks ability/enemy scale, role tiers, drops, and boss data.

Focused coverage is still desirable for damage math, Speed bonus turns, cooldown/use caps,
consumables, role passives, boss specials, defeat persistence, and a real recall response updating
both SRS state and combat effect.
