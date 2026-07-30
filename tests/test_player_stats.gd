extends SceneTree
## Learning level drives combat power — and combat has to actually be winnable.
##
##   godot --headless --path . --script res://tests/test_player_stats.gd
##
## WHY. The enemy roster was ported from a build where the player levelled. The Godot port
## had a flat 12 HP, and simulating the real encounter showed the kappa (55hp/9atk) and
## lantern (60hp/10atk) were winnable 0% of the time even answering every card correctly:
## you die in two rounds and need seven to kill. Nobody would have noticed from a unit test —
## every individual number was "correct" — so this simulates whole fights instead.
##
## The ladder these assertions describe is the intended difficulty curve: slimes at level 1,
## the mushroom once you have studied a little, the tougher wilds foes only after real
## progress. Since XP comes ONLY from learning, that curve IS the learning curve.

const TRIALS := 300
const MAX_ROUNDS := 80

var failures: int = 0
var db: Node


func _initialize() -> void:
	await process_frame
	db = root.get_node("DB")

	_level_curve_is_monotonic()
	_xp_maps_to_levels()
	_attribute_allocations()
	_gear_bonuses_and_scaling()
	_winnable_at_the_right_levels()

	_finish()


func _xp_maps_to_levels() -> void:
	check_eq("0 xp is level 1", PlayerStats.level_from_xp(0), 1)
	check_eq("negative xp still level 1", PlayerStats.level_from_xp(-50), 1)
	check_eq("one level's xp is level 2", PlayerStats.level_from_xp(PlayerStats.XP_PER_LEVEL), 2)
	check_eq("just under is still level 1", PlayerStats.level_from_xp(PlayerStats.XP_PER_LEVEL - 1), 1)
	check_eq("progress within a level", PlayerStats.xp_into_level(PlayerStats.XP_PER_LEVEL + 30), 30)


## Stats must never go backwards as you learn — a level-up that lowered a stat would silently
## punish studying.
func _level_curve_is_monotonic() -> void:
	var ok := true
	for lv in range(1, 20):
		if PlayerStats.max_hp(lv + 1) < PlayerStats.max_hp(lv) \
				or PlayerStats.atk(lv + 1) < PlayerStats.atk(lv) \
				or PlayerStats.def(lv + 1) < PlayerStats.def(lv) \
				or PlayerStats.speed(lv + 1) < PlayerStats.speed(lv):
			ok = false
	check_true("stats never decrease with level", ok)
	check_eq("level 1 keeps the authored baseline", PlayerStats.max_hp(1), PlayerStats.BASE_MAX_HP)


func _attribute_allocations() -> void:
	var xp := PlayerStats.XP_PER_LEVEL * 2
	var allocations := {"vitality": 0, "power": 0, "agility": 0}
	check_eq("one Attribute Point is earned per level gained",
		PlayerStats.attribute_points_earned(xp), 2)
	check_eq("all earned Attribute Points start unspent",
		PlayerStats.unspent_attribute_points(xp, allocations), 2)
	check_true("a point can raise Vitality",
		PlayerStats.adjust_allocation(allocations, "vitality", 1, xp))
	check_true("a point can raise Power",
		PlayerStats.adjust_allocation(allocations, "power", 1, xp))
	var allocated := PlayerStats.from_xp(xp, [], allocations)
	check_eq("Vitality keeps Kana's +6 HP step", allocated["max_hp"],
		PlayerStats.max_hp(3) + PlayerStats.VITALITY_HP)
	check_eq("Power keeps Kana's +1 ATK step", allocated["atk"],
		PlayerStats.atk(3) + PlayerStats.POWER_ATK)
	check_true("spent points cannot be overspent",
		not PlayerStats.adjust_allocation(allocations, "power", 1, xp))
	check_true("earned points cannot be overspent on Agility",
		not PlayerStats.adjust_allocation(allocations, "agility", 1, xp))
	check_true("allocations are freely refundable",
		PlayerStats.adjust_allocation(allocations, "vitality", -1, xp))
	check_true("a refunded point can raise active Agility",
		PlayerStats.adjust_allocation(allocations, "agility", 1, xp))
	allocated = PlayerStats.from_xp(xp, [], allocations)
	check_eq("Agility keeps Kana's +1 SPD step", allocated["speed"],
		PlayerStats.speed(3) + PlayerStats.AGILITY_SPEED)
	check_true("Agility is freely refundable",
		PlayerStats.adjust_allocation(allocations, "agility", -1, xp))
	check_eq("a refund restores the point",
		PlayerStats.unspent_attribute_points(xp, allocations), 1)


func _gear_bonuses_and_scaling() -> void:
	var starter_gear: Array[Dictionary] = [{
		"kind": "gear", "stats": {"hp": 6, "atk": 2, "def": 1, "spd": -1},
	}]
	var equipped := PlayerStats.from_xp(0, starter_gear)
	check_eq("gear adds max HP", equipped["max_hp"], PlayerStats.BASE_MAX_HP + 6)
	check_eq("gear adds attack", equipped["atk"], PlayerStats.BASE_ATK + 2)
	check_eq("gear adds defense", equipped["def"], PlayerStats.BASE_DEF + 1)
	check_eq("negative speed penalties reduce the real base stat", equipped["speed"],
		PlayerStats.BASE_SPEED - 1)

	var rare_gear := {
		"kind": "gear", "requiredLevel": 12, "rarity": "rare",
		"stats": {"hp": 10},
	}
	check_eq("rare positive stats grow after their equip floor",
		PlayerStats.scaled_item_stats(rare_gear, 20)["hp"], 11)
	check_eq("gear never scales before its equip floor",
		PlayerStats.scaled_item_stats(rare_gear, 5)["hp"], 10)


## Simulate real fights with a perfect player and assert the ladder.
func _winnable_at_the_right_levels() -> void:
	# Level 1: the village sparring slime must be beatable, or a new player can do nothing.
	check_true("slime is winnable at level 1", _win_rate("slime", 1) > 0.9)

	# The wilds mushroom is the first real fight. A player who has talked to a couple of
	# teachers is level 2+, and it must be reliably winnable by then.
	check_true("mushroom is winnable by level 2", _win_rate("mushroom", 2) > 0.9)

	# The mid-tier wilds foes slot between the mushroom and the kappa.
	check_true("snake is winnable by level 3", _win_rate("snake", 3) > 0.9)
	check_true("racoon is winnable by level 3", _win_rate("racoon", 3) > 0.9)

	# The tough wilds foes must be gated behind real study, not impossible.
	check_true("kappa is NOT a pushover at level 2", _win_rate("kappa", 2) < 0.5)
	check_true("kappa becomes winnable with study", _win_rate("kappa", 5) > 0.9)
	check_true("owl becomes winnable with study", _win_rate("owl", 5) > 0.9)
	check_true("lantern becomes winnable with study", _win_rate("lantern", 5) > 0.9)

	# The regression that started this: nothing in the roster may be unwinnable forever.
	for eid in ["slime", "mushroom", "snake", "racoon", "kappa", "owl", "lantern"]:
		check_true("%s is winnable at a high level" % eid, _win_rate(eid, 10) > 0.9)


## Fraction of simulated fights a perfect player wins at `level`.
func _win_rate(enemy_id: String, level: int) -> float:
	var e: Dictionary = db.enemy(enemy_id)
	var hp := PlayerStats.max_hp(level)
	var wins := 0
	for t in TRIALS:
		var enc := CombatEncounter.new(e, hp, hp, PlayerStats.atk(level), PlayerStats.def(level))
		var rounds := 0
		while not enc.is_over() and rounds < MAX_ROUNDS:
			enc.resolve("same", "same")   # every recall correct
			rounds += 1
		if enc.player_won():
			wins += 1
	return float(wins) / float(TRIALS)


func _finish() -> void:
	print("")
	print(("PASS — learning raises stats, and every foe is winnable at the right level."
		if failures == 0 else "FAIL — %d stat/balance check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + label + ("" if ok else "  (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1
