extends SceneTree
## Turn-based recall combat: the rules that make Japanese the input method.
##
##   godot --headless --path . --script res://tests/test_combat_encounter.gd
##
## Pure logic only — no viewport, no autoloads. Variance is pinned (roll = 0.5, the
## unvaried midpoint) so damage assertions are deterministic.

var failures: int = 0
var enemy_def := {"id": "mushroom", "name": "Spore Mushroom", "maxHp": 30, "atk": 6, "def": 1}


func _initialize() -> void:
	_wrong_answer_still_swings()
	_flow_builds_and_breaks()
	_enemy_does_not_counter_when_defeated()
	_defeat_ends_the_fight()
	_equipped_actions_have_distinct_results()
	_challenge_is_japanese_and_solvable()
	_finish()


## The load-bearing rule: a miss must cost tempo, never agency. CombatLogic halves the
## damage; it never cancels the swing.
func _wrong_answer_still_swings() -> void:
	var right := _fresh()
	var r1 := right.resolve("み", "み")
	var wrong := _fresh()
	var r2 := wrong.resolve("か", "み")

	check_true("correct answer registers", r1.correct)
	check_true("wrong answer registers", not r2.correct)
	check_true("a wrong answer still deals damage", r2.player_damage_dealt > 0)
	check_true("a wrong answer deals LESS than a right one",
		r2.player_damage_dealt < r1.player_damage_dealt)


## Recall Flow: consecutive correct recalls hit harder, one miss resets the streak.
func _flow_builds_and_breaks() -> void:
	var e := _fresh()
	e.resolve("み", "み")
	check_eq("flow after 1 correct", e.flow, 1)
	e.resolve("み", "み")
	check_eq("flow after 2 correct", e.flow, 2)
	var streak_hit: int = e.resolve("み", "み").player_damage_dealt
	check_eq("flow after 3 correct", e.flow, 3)

	e.resolve("か", "み")
	check_eq("a miss resets flow to zero", e.flow, 0)

	# A fresh encounter's first (flow=1) hit should be weaker than a flow=3 hit.
	var fresh := _fresh()
	var first_hit: int = fresh.resolve("み", "み").player_damage_dealt
	check_true("built-up flow hits harder than a first swing", streak_hit > first_hit)


## A dead enemy gets no parting shot — otherwise the winning blow could still kill you.
func _enemy_does_not_counter_when_defeated() -> void:
	var e := _fresh()
	e.enemy_hp = 1
	var r := e.resolve("み", "み")
	check_true("enemy is defeated", r.enemy_defeated)
	check_eq("defeated enemy deals no damage", r.enemy_damage_dealt, 0)
	check_true("player survives the winning blow", not r.player_defeated)
	check_true("encounter reports a win", e.player_won())


func _defeat_ends_the_fight() -> void:
	var e := _fresh()
	e.player_hp = 1
	var r := e.resolve("か", "み")   # miss: enemy counters
	check_true("player is defeated", r.player_defeated)
	check_true("encounter is over", e.is_over())
	check_true("encounter is not a win", not e.player_won())


## The starter loadout is not cosmetic: attack, defense, and recovery each change a
## different piece of encounter state while using the same recall contract.
func _equipped_actions_have_distinct_results() -> void:
	var basic := _fresh()
	var basic_result := basic.resolve("mi", "mi")
	var strike := _fresh()
	var strike_result := strike.resolve("mi", "mi",
		{"id": "strike", "type": "attack", "power": 9})
	check_true("Strike hits harder than Basic Attack",
		strike_result.player_damage_dealt > basic_result.player_damage_dealt)

	var guard := _fresh()
	var guard_result := guard.resolve("mi", "mi",
		{"id": "guard", "type": "block", "power": 10})
	check_true("Guard raises shield", guard_result.shield_gained > 0)
	check_true("Guard absorbs the enemy hit", guard_result.shield_absorbed > 0)
	check_eq("fully blocked hits deal no HP damage", guard_result.enemy_damage_dealt, 0)

	var focus := _fresh()
	focus.player_hp = 3
	var focus_result := focus.resolve("mi", "mi",
		{"id": "focus", "type": "heal", "power": 9})
	check_true("Focus restores missing HP", focus_result.player_healed > 0)
	check_eq("Focus does not damage the enemy", focus_result.player_damage_dealt, 0)


## The menu must be Japanese, contain the answer exactly once, and never repeat a rune.
func _challenge_is_japanese_and_solvable() -> void:
	var card := {"prompt": "み", "answer": "mi", "meaning": "", "type": "kana"}
	var pool := [{"prompt": "か", "type": "kana"}, {"prompt": "す", "type": "kana"},
		{"prompt": "ほ", "type": "kana"}, {"prompt": "み", "type": "kana"},
		{"prompt": "か", "type": "kana"},
		{"prompt": "さかな", "type": "vocab"}]   # dupes, the answer, and a wrong-type lure
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ch := CombatEncounter.build_challenge(card, pool, rng, 4)

	check_eq("challenge offers four runes", ch["choices"].size(), 4)
	check_true("the answer is among them", ch["choices"].has("み"))
	check_eq("guard shows the meaning side", ch["guard"], "mi")

	var counts := {}
	for c in ch["choices"]:
		counts[c] = int(counts.get(c, 0)) + 1
	check_eq("the answer appears exactly once", counts["み"], 1)
	check_eq("no rune is repeated", counts.size(), 4)
	# A vocab word among kana would be ruled out on shape alone — that is not a recall test.
	check_true("distractors match the card's type", not ch["choices"].has("さかな"))


func _fresh() -> CombatEncounter:
	var e := CombatEncounter.new(enemy_def, 12, 12, 6, 2)
	e.roll = 0.5   # unvaried midpoint — deterministic damage
	return e


func _finish() -> void:
	print("")
	print(("PASS — a miss costs tempo not agency, and flow rewards real recall."
		if failures == 0 else "FAIL — %d combat check(s) failed." % failures))
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
