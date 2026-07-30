extends SceneTree
## Turn-based recall combat: the rules that make Japanese the input method.
##
##   godot --headless --path . --script res://tests/test_combat_encounter.gd
##
## Pure logic only — no viewport, no autoloads. Variance is pinned (roll = 0.5, the
## unvaried midpoint) so damage assertions are deterministic.

var failures: int = 0
var enemy_def := {"id": "mushroom", "name": "Spore Mushroom", "maxHp": 30,
	"atk": 6, "def": 1, "speed": 3}


func _initialize() -> void:
	_wrong_answer_still_swings()
	_flow_builds_and_breaks()
	_enemy_does_not_counter_when_defeated()
	_defeat_ends_the_fight()
	_equipped_actions_have_distinct_results()
	_energy_delays_the_enemy_response()
	_speed_grants_one_extra_full_turn()
	_speed_decides_the_opening_action()
	_enemy_intent_is_truthful()
	_items_are_limited_per_turn()
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


func _energy_delays_the_enemy_response() -> void:
	var e := _fresh()
	# This test spends multiple actions before End Turn; keep the target alive so it can
	# exercise the delayed response instead of the separate no-parting-shot victory rule.
	e.enemy_max_hp = 200
	e.enemy_hp = 200
	e.begin_player_round()
	check_eq("a full player turn starts with five Energy", e.energy, 5)
	var hp_before := e.player_hp
	var basic := e.spend_and_resolve("mi", "mi")
	check_true("an affordable Basic Attack resolves", basic.action_resolved)
	check_eq("Basic Attack costs one Energy", e.energy, 4)
	check_eq("the enemy does not interrupt an Energy turn", e.player_hp, hp_before)
	var skill := e.spend_and_resolve("mi", "mi",
		{"id": "sweep", "type": "attack", "power": 14, "cost": 3})
	check_true("an affordable skill resolves", skill.action_resolved)
	check_eq("the authored skill cost is spent", e.energy, 1)
	var rejected := e.spend_and_resolve("mi", "mi",
		{"id": "focus", "type": "heal", "power": 9, "cost": 2})
	check_true("an unaffordable action is rejected", not rejected.action_resolved)
	check_eq("a rejected action spends nothing", e.energy, 1)
	var ended := e.end_player_turn()
	check_true("ending the full turn lets the enemy act once", ended.enemy_acted)
	check_true("the enemy response changes player HP", e.player_hp < hp_before)
	check_eq("the next full turn refreshes Energy", e.energy, 5)


func _speed_grants_one_extra_full_turn() -> void:
	var fast_enemy := enemy_def.duplicate(true)
	fast_enemy["speed"] = 2
	var e := CombatEncounter.new(fast_enemy, 20, 20, 6, 2, 6)
	e.roll = 0.5
	e.begin_player_round()
	check_eq("a four-Speed lead schedules two full turns", e.turns_left, 2)
	e.spend_and_resolve("mi", "mi")
	var hp_before := e.player_hp
	var bonus := e.end_player_turn()
	check_true("the first end grants the Speed turn", bonus.bonus_turn_granted)
	check_true("the bonus turn does not let the enemy act", not bonus.enemy_acted)
	check_eq("bonus turn refreshes all Energy", e.energy, 5)
	check_eq("bonus turn preserves player HP", e.player_hp, hp_before)
	var response := e.end_player_turn()
	check_true("the enemy responds after the bonus turn", response.enemy_acted)
	check_eq("Speed bonus remains capped at one turn", e.turns_left,
		CombatEncounter.player_turn_count(e.player_speed, e.enemy_speed))


func _speed_decides_the_opening_action() -> void:
	check_true("ties favour the player", CombatEncounter.player_acts_first(5, 5))
	check_true("a faster enemy acts first", not CombatEncounter.player_acts_first(5, 6))
	var quick_enemy := enemy_def.duplicate(true)
	quick_enemy["speed"] = 6
	var e := CombatEncounter.new(quick_enemy, 12, 12, 6, 2, 5)
	e.roll = 0.5
	var opening := e.enemy_opening_turn()
	check_true("the opening enemy turn deals damage", opening.enemy_acted
		and opening.enemy_damage_dealt > 0)
	check_eq("surviving the opening prepares five Energy", e.energy, 5)


func _enemy_intent_is_truthful() -> void:
	var e := _fresh()
	check_eq("enemy intent previews the full variance range", e.enemy_damage_range(),
		Vector2i(4, 6))
	e.shield = 5
	check_eq("enemy intent includes the current Guard shield", e.enemy_damage_range(),
		Vector2i(0, 1))
	# Intent inspection must not resolve or mutate the encounter.
	check_eq("enemy intent preview preserves player HP", e.player_hp, 12)
	check_eq("enemy intent preview preserves Guard", e.shield, 5)


func _items_are_limited_per_turn() -> void:
	var e := _fresh()
	e.player_hp = 8
	e.begin_player_round()
	var first := e.use_healing_item("rice_ball", 1, false)
	var second := e.use_healing_item("rice_ball", 1, false)
	check_true("the first healing item resolves", first.action_resolved)
	check_true("a second item in one turn is rejected", not second.action_resolved)
	check_eq("items do not spend Energy", e.energy, 5)
	e.end_player_turn()
	check_true("the next full turn restores item access", e.can_use_item())


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
