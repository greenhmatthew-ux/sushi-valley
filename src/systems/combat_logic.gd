class_name CombatLogic
extends RefCounted
## Pure combat math for the first-pass combat loop. Node-free and headless-testable:
## nothing here touches the scene tree, so tests instantiate the numbers directly.
##
## Ported from d:\Downloads\Japanese\src\game\systems\CombatSystem.ts (the frozen
## Vite/Phaser reference). The formulas below are carried over EXACTLY — the tuned
## balance lives in the constants and the shapes of these expressions, and changing
## them silently would change how combat feels. Explanatory comments come across too.
##
## Only the renderer-independent per-hit math is ported here; the turn/energy/ability
## orchestration (CombatScene.ts) is out of scope for this slice.

## Always-available light attack. Intentionally repeatable in the TS build: energy is
## the action budget there. `power` is the card's base magnitude — see BASIC_ATTACK in
## CombatSystem.ts (`power: 4`).
const BASIC_ATTACK_POWER := 4

## Recall Flow: consecutive correct recalls build momentum that escalates attack damage.
## Accurate recall literally hits harder; a wrong answer breaks the streak. (CombatSystem.ts)
const FLOW_MAX := 4
const FLOW_BONUS_PER_STACK := 0.1   ## +10% attack damage per stack, up to +40%

## Attack-damage multiplier from the current Flow streak (1.0 at 0 stacks).
## Port of flowMultiplier(): 1 + clamp(stacks, 0, FLOW_MAX) * FLOW_BONUS_PER_STACK.
static func flow_multiplier(stacks: int) -> float:
	return 1.0 + clampi(stacks, 0, FLOW_MAX) * FLOW_BONUS_PER_STACK


## Per-hit ability damage: card power + the attacker's ATK, scaled by recall correctness,
## reduced by half the target's DEF, then varied ±15%. Port of abilityDamage():
##
##   const mult = correct ? 1 : 0.5;
##   const defVal = ignoreDef ? 0 : enemy.def * 0.5;
##   const base = (ability.power + player.atk) * mult - defVal;
##   const varied = base * (0.85 + Math.random() * 0.3);
##   return Math.max(1, Math.round(varied));
##
## `roll` is the injected variance sample in [0, 1] standing in for Math.random(). Pass a
## fixed value (0.5 = the unvaried midpoint, base * 1.0) for deterministic tests; leave it
## negative (the default) to draw a fresh randf() at runtime, matching the TS behavior.
static func ability_damage(power: int, atk: int, target_def: int, correct: bool = true, roll: float = -1.0, ignore_def: bool = false) -> int:
	var mult := 1.0 if correct else 0.5
	var def_val := 0.0 if ignore_def else target_def * 0.5
	var base := (power + atk) * mult - def_val
	var r := roll if roll >= 0.0 else randf()
	var varied := base * (0.85 + r * 0.3)
	# roundi rounds half away from zero; Math.round rounds half up. They agree for the
	# positive `varied` values reachable here, and negatives are clamped to the 1 floor.
	return maxi(1, roundi(varied))


## Plain enemy attack damage vs the player's DEF (any shield is applied separately by
## apply_damage). Port of enemyDamage():
##
##   const base = enemy.atk - player.def * 0.4;
##   const varied = base * (0.85 + Math.random() * 0.3);
##   return Math.max(1, Math.round(varied));
##
## `roll` behaves as in ability_damage. Reserved for when enemies strike back; kept here
## so all the tuned combat numbers live in one ported, tested place.
static func enemy_damage(enemy_atk: int, player_def: int, roll: float = -1.0) -> int:
	var base := enemy_atk - player_def * 0.4
	var r := roll if roll >= 0.0 else randf()
	var varied := base * (0.85 + r * 0.3)
	return maxi(1, roundi(varied))


## Apply incoming damage to an HP pool, clamping at 0 so HP never goes negative. Port of
## the HP-clamp core of applyDamage() (`target.hp = Math.max(0, target.hp - hpLoss)`); the
## TS block/shield absorb is omitted in this first pass because enemies have no shield yet.
static func apply_damage(hp: int, dmg: int) -> int:
	return maxi(0, hp - dmg)


## Death check: an HP pool is dead once it hits zero (or below, defensively).
static func is_dead(hp: int) -> bool:
	return hp <= 0
