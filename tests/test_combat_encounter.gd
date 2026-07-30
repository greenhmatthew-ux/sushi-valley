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
	_ability_cadence_is_enforced()
	_immediate_buffs_are_distinct()
	_timed_stat_buffs_last_enemy_rounds()
	_timed_debuffs_change_enemy_math()
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


func _ability_cadence_is_enforced() -> void:
	var focus := {"id": "focus", "type": "heal", "power": 9, "cost": 2,
		"maxUsesPerTurn": 1, "cooldownTurns": 1}
	var full := _fresh()
	full.begin_player_round()
	check_true("healing actions are unavailable at full HP", not full.can_use_ability(focus))
	check_eq("full-HP action state is visible", full.ability_status(focus), "Full HP")

	var e := _fresh()
	e.enemy_max_hp = 200
	e.enemy_hp = 200
	e.player_hp = 6
	e.begin_player_round()
	var first := e.spend_and_resolve("mi", "mi", focus)
	check_true("the first Focus use resolves", first.action_resolved)
	check_eq("Focus starts its authored cooldown", e.ability_status(focus), "CD 1")
	var energy_after := e.energy
	check_true("Focus cannot repeat in the same turn",
		not e.spend_and_resolve("mi", "mi", focus).action_resolved)
	check_eq("a cadence-rejected action spends no Energy", e.energy, energy_after)
	e.end_player_turn()
	check_true("CD 1 skips the next full player turn", not e.can_use_ability(focus))
	e.end_player_turn()
	check_true("Focus returns after one skipped full turn", e.can_use_ability(focus))

	var brace := {"id": "brace", "type": "block", "power": 10, "cost": 1,
		"maxUsesPerTurn": 1}
	var limited := _fresh()
	limited.begin_player_round()
	limited.spend_and_resolve("mi", "mi", brace)
	check_eq("per-turn-only actions expose their used state",
		limited.ability_status(brace), "Used")
	check_true("per-turn-only actions cannot repeat",
		not limited.spend_and_resolve("mi", "mi", brace).action_resolved)


func _immediate_buffs_are_distinct() -> void:
	var tea := {"id": "mana_tea", "type": "buff", "buffType": "energy",
		"buffValue": 3, "cost": 1}
	var e := _fresh()
	e.enemy_max_hp = 200
	e.enemy_hp = 200
	e.begin_player_round()
	e.spend_and_resolve("mi", "mi",
		{"id": "sweep", "type": "attack", "power": 14, "cost": 3})
	var tea_result := e.spend_and_resolve("mi", "mi", tea)
	check_eq("Mana Tea restores its authored Energy after paying its cost",
		tea_result.energy_restored, 3)
	check_eq("Mana Tea has a real net Energy gain", e.energy, 4)
	check_eq("Mana Tea does not fake attack damage", tea_result.player_damage_dealt, 0)

	var bulwark := {"id": "bulwark", "type": "buff", "buffType": "shield",
		"buffValue": 30, "cost": 3}
	var guarded := _fresh()
	guarded.begin_player_round()
	var wall := guarded.spend_and_resolve("mi", "mi", bulwark)
	check_eq("Bulwark raises its authored Shield", wall.shield_gained, 30)
	check_eq("Bulwark changes the enemy intent to zero HP damage",
		guarded.enemy_damage_range(), Vector2i(0, 0))
	check_true("a weaker duplicate shield buff is rejected",
		not guarded.can_use_ability(bulwark))
	check_eq("the shield action exposes why it is unavailable",
		guarded.ability_status(bulwark), "Shielded")


func _timed_stat_buffs_last_enemy_rounds() -> void:
	var ki_focus := {"id": "ki_focus", "type": "buff", "buffType": "atk",
		"buffValue": 4, "buffDuration": 3, "cost": 2}
	var offense := _fresh()
	offense.begin_player_round()
	var focused := offense.spend_and_resolve("mi", "mi", ki_focus)
	check_eq("timed ATK buff reports its real value", focused.buff_value, 4)
	check_eq("timed ATK buff reports its real duration", focused.buff_rounds, 3)
	check_eq("timed ATK buff changes attack math", offense.effective_atk(), 10)
	check_eq("active timed buff has a compact HUD summary",
		offense.timed_buff_summary(), "ATK+4/3r")
	check_true("an identical full-duration buff cannot waste Energy",
		not offense.can_use_ability(ki_focus))

	var rune_ward := {"id": "rune_ward", "type": "buff", "buffType": "def",
		"buffValue": 4, "buffDuration": 3, "cost": 2}
	var defense := CombatEncounter.new(enemy_def, 100, 100, 6, 2, 5)
	defense.roll = 0.5
	defense.begin_player_round()
	defense.spend_and_resolve("mi", "mi", rune_ward)
	check_eq("timed DEF buff changes the intent range", defense.enemy_damage_range(),
		Vector2i(3, 4))
	defense.end_player_turn()
	check_eq("DEF buff ticks only after the first enemy response",
		(defense.timed_buffs["def"] as Dictionary)["rounds"], 2)
	defense.end_player_turn()
	check_eq("DEF buff remains for its third enemy response",
		(defense.timed_buffs["def"] as Dictionary)["rounds"], 1)
	defense.end_player_turn()
	check_true("DEF buff expires after exactly three enemy responses",
		not defense.timed_buffs.has("def"))
	check_eq("expired DEF returns to the base stat", defense.effective_def(), 2)

	var wind_step := {"id": "wind_step", "type": "buff", "buffType": "speed",
		"buffValue": 4, "buffDuration": 3, "cost": 2}
	var even_enemy := enemy_def.duplicate(true)
	even_enemy["speed"] = 5
	var quick := CombatEncounter.new(even_enemy, 30, 30, 6, 2, 5)
	quick.roll = 0.5
	quick.begin_player_round()
	check_eq("setup begins without a Speed bonus turn", quick.turns_left, 1)
	quick.spend_and_resolve("mi", "mi", wind_step)
	check_eq("Speed buff updates the effective stat immediately", quick.effective_speed(), 9)
	check_eq("Speed buff can earn the current round's one bonus turn", quick.turns_left, 2)
	var bonus := quick.end_player_turn()
	check_true("Speed-only bonus does not tick timed buffs", bonus.bonus_turn_granted
		and (quick.timed_buffs["speed"] as Dictionary)["rounds"] == 3)


func _timed_debuffs_change_enemy_math() -> void:
	var shear := {"id": "spirit_shear", "type": "attack", "power": 16, "cost": 3,
		"debuffType": "def", "debuffValue": 4, "debuffDuration": 3}
	var exposed := _fresh()
	exposed.enemy_max_hp = 200
	exposed.enemy_hp = 200
	exposed.enemy_def = 6
	exposed.begin_player_round()
	var opening := exposed.spend_and_resolve("mi", "mi", shear)
	check_eq("debuff attack reports the applied stat", opening.debuff_type, "def")
	check_eq("debuff attack reports value and duration",
		Vector2i(opening.debuff_value, opening.debuff_rounds), Vector2i(4, 3))
	check_eq("DEF debuff changes later attack math", exposed.effective_enemy_def(), 2)
	var exposed_followup := exposed.spend_and_resolve("mi", "mi").player_damage_dealt
	var plain := _fresh()
	plain.enemy_max_hp = 200
	plain.enemy_hp = 200
	plain.enemy_def = 6
	plain.begin_player_round()
	plain.spend_and_resolve("mi", "mi", {"id": "plain_shear", "type": "attack",
		"power": 16, "cost": 3})
	var plain_followup := plain.spend_and_resolve("mi", "mi").player_damage_dealt
	check_true("DEF debuff helps subsequent actions, not its initiating hit",
		exposed_followup > plain_followup)

	var void_cleave := {"id": "void_cleave", "type": "attack", "power": 1, "cost": 1,
		"debuffType": "atk", "debuffValue": 5, "debuffDuration": 3}
	var weakened := CombatEncounter.new(enemy_def, 100, 100, 6, 2, 5)
	weakened.roll = 0.5
	weakened.begin_player_round()
	weakened.spend_and_resolve("mi", "mi", void_cleave)
	check_eq("ATK debuff immediately updates enemy intent", weakened.enemy_damage_range(),
		Vector2i(1, 1))
	weakened.end_player_turn()
	check_eq("ATK debuff affects the current enemy response", weakened.player_hp, 99)
	check_eq("enemy debuffs tick after that response",
		(weakened.timed_debuffs["atk"] as Dictionary)["rounds"], 2)
	weakened.end_player_turn()
	weakened.end_player_turn()
	check_true("enemy debuff expires after exactly three responses",
		not weakened.timed_debuffs.has("atk"))

	var sap := {"id": "sap_glyph", "type": "attack", "power": 1, "cost": 2,
		"debuffType": "speed", "debuffValue": 4, "debuffDuration": 3}
	var even_enemy := enemy_def.duplicate(true)
	even_enemy["speed"] = 5
	var slowed := CombatEncounter.new(even_enemy, 30, 30, 6, 2, 5)
	slowed.roll = 0.5
	slowed.begin_player_round()
	slowed.spend_and_resolve("mi", "mi", sap)
	check_eq("SPD debuff changes effective enemy Speed", slowed.effective_enemy_speed(), 1)
	check_eq("SPD debuff can earn the current bonus turn", slowed.turns_left, 2)
	check_eq("enemy status summary is compact and explicit",
		slowed.enemy_debuff_summary(), "SPD-4/3r")


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
