extends SceneTree
## Slice: pin the combat math to the ported TS balance (CombatSystem.ts).
##
##   godot --headless --path . --script res://tests/test_combat.gd
##
## Variance is injected (roll in [0,1]) so every damage number here is exact and
## reproducible — roll 0.5 is the unvaried midpoint (base * 1.0), and roll 0.0 / 1.0
## pin the ±15% band. If a refactor shifts the formula, ATK contribution, DEF halving,
## the min-1 floor, or the HP clamp, these fail loudly. That is the point: the tuned
## numbers are what make combat feel right and are the easiest thing to break silently.

var failures: int = 0


func _initialize() -> void:
	_fresh_enemy_is_alive()
	_hit_reduces_hp_by_formula()
	_wrong_answer_is_half()
	_variance_band()
	_min_one_floor()
	_lethal_sets_zero_and_reports_death()
	_over_damage_clamps()
	_basic_attack_power()
	_flow_multiplier_ladder()
	_enemy_damage_formula()
	_finish()


# A fresh enemy at full HP is alive; only 0-or-below counts as dead.
func _fresh_enemy_is_alive() -> void:
	check_true("fresh 30hp is alive", not CombatLogic.is_dead(30))
	check_true("1hp is alive", not CombatLogic.is_dead(1))
	check_true("0hp is dead", CombatLogic.is_dead(0))
	check_true("negative hp is dead", CombatLogic.is_dead(-5))


# base = (power + atk) * 1 - def*0.5; midpoint roll leaves it unvaried, then it lands on HP.
func _hit_reduces_hp_by_formula() -> void:
	var dmg := CombatLogic.ability_damage(CombatLogic.BASIC_ATTACK_POWER, 6, 4, true, 0.5)
	check_eq("basic hit (4+6)*1 - 4*0.5 = 8", dmg, 8)
	check_eq("30hp - 8 = 22", CombatLogic.apply_damage(30, dmg), 22)

	# DEF really is halved, and ignore_def removes it entirely.
	check_eq("ignore_def -> full 10", CombatLogic.ability_damage(4, 6, 4, true, 0.5, true), 10)


# A wrong recall answer resolves at half power (mult 0.5), not a cancel.
func _wrong_answer_is_half() -> void:
	var dmg := CombatLogic.ability_damage(4, 6, 4, false, 0.5)
	check_eq("wrong: (4+6)*0.5 - 2 = 3", dmg, 3)


# ±15% variance band: roll 0 = base*0.85, roll 1 = base*1.15, around base 8.
func _variance_band() -> void:
	check_eq("roll 0 -> 8*0.85 = 6.8 -> 7", CombatLogic.ability_damage(4, 6, 4, true, 0.0), 7)
	check_eq("roll 1 -> 8*1.15 = 9.2 -> 9", CombatLogic.ability_damage(4, 6, 4, true, 1.0), 9)


# Damage never drops below 1, no matter how much DEF outclasses the hit.
func _min_one_floor() -> void:
	check_eq("huge def clamps to 1", CombatLogic.ability_damage(4, 0, 100, false, 0.5), 1)


# Lethal damage zeroes HP and reports death.
func _lethal_sets_zero_and_reports_death() -> void:
	var hp := CombatLogic.apply_damage(8, 8)
	check_eq("8hp - 8 = 0", hp, 0)
	check_true("0hp reports death", CombatLogic.is_dead(hp))


# Over-damage clamps at 0 — HP is never negative.
func _over_damage_clamps() -> void:
	var hp := CombatLogic.apply_damage(30, 999)
	check_eq("30hp - 999 clamps to 0", hp, 0)
	check_true("clamped hp is not negative", hp >= 0)
	check_true("clamped hp reports death", CombatLogic.is_dead(hp))


func _basic_attack_power() -> void:
	check_eq("BASIC_ATTACK_POWER = 4", CombatLogic.BASIC_ATTACK_POWER, 4)


# Flow: +10% per stack, capped at +40% (4 stacks).
func _flow_multiplier_ladder() -> void:
	check_close("0 stacks -> 1.0", CombatLogic.flow_multiplier(0), 1.0)
	check_close("2 stacks -> 1.2", CombatLogic.flow_multiplier(2), 1.2)
	check_close("4 stacks -> 1.4", CombatLogic.flow_multiplier(4), 1.4)
	check_close("10 stacks -> clamped 1.4", CombatLogic.flow_multiplier(10), 1.4)


# Enemy strike: base = atk - def*0.4, min 1.
func _enemy_damage_formula() -> void:
	check_eq("10atk vs 5def -> 10 - 2 = 8", CombatLogic.enemy_damage(10, 5, 0.5), 8)
	check_eq("weak vs heavy def clamps to 1", CombatLogic.enemy_damage(1, 100, 0.5), 1)


# --- helpers ---------------------------------------------------------------

func _finish() -> void:
	print("")
	print(("PASS — combat math matches the TS." if failures == 0
		else "FAIL — %d combat check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s)" % [label, got], got == want)


func check_close(label: String, got: float, want: float) -> void:
	check_true("%s (got %f, want %f)" % [label, got, want], absf(got - want) < 0.0001)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
