extends SceneTree
## Pure coverage for disposition semantics and legal enemy movement tuning.
##
##   godot --headless --path . --script res://tests/test_world_behavior_def.gd

const Behaviors = preload("res://src/systems/world_behavior_def.gd")

var failures: int = 0


func _initialize() -> void:
	_all_five_dispositions_have_valid_defaults()
	_state_names_cover_the_runtime_state_machine()
	_disposition_semantics_are_distinct()
	_live_roster_profiles_are_complete()
	_mushroom_and_bat_are_contrasting_valid_presets()
	_preset_results_are_safe_copies()
	_speed_bands_reject_player_matching()
	_burst_limits_require_recovery()
	_timing_and_radius_fields_are_validated()
	_finish()


func _state_names_cover_the_runtime_state_machine() -> void:
	check_eq("state names follow the authored state machine", Behaviors.STATE_NAMES,
		["idle", "roam", "alert", "chase", "engage", "return", "flee"])
	check_eq("idle state name", Behaviors.state_name(Behaviors.STATE_IDLE), "idle")
	check_eq("roam state name", Behaviors.state_name(Behaviors.STATE_ROAM), "roam")
	check_eq("alert state name", Behaviors.state_name(Behaviors.STATE_ALERT), "alert")
	check_eq("chase state name", Behaviors.state_name(Behaviors.STATE_CHASE), "chase")
	check_eq("engage state name", Behaviors.state_name(Behaviors.STATE_ENGAGE), "engage")
	check_eq("return state name", Behaviors.state_name(Behaviors.STATE_RETURN), "return")
	check_eq("optional flee state name", Behaviors.state_name(Behaviors.STATE_FLEE), "flee")
	check_eq("invalid state has a safe label", Behaviors.state_name(-1), "unknown")
	check_eq("out-of-range state has a safe label", Behaviors.state_name(99), "unknown")


func _all_five_dispositions_have_valid_defaults() -> void:
	check_eq("five dispositions are ordered from passive through hunter",
		Behaviors.DISPOSITION_ORDER,
		[
			Behaviors.PASSIVE,
			Behaviors.PROVOKED,
			Behaviors.WARY,
			Behaviors.TERRITORIAL,
			Behaviors.HUNTER,
		])
	for disposition: String in Behaviors.DISPOSITION_ORDER:
		var definition := Behaviors.default_for_disposition(disposition)
		check_true("%s has a default definition" % disposition, not definition.is_empty())
		check_eq("%s default preserves disposition" % disposition,
			String(definition["disposition"]), disposition)
		check_eq("%s default passes validation" % disposition,
			Behaviors.validate(definition), [])
	check_eq("unknown disposition has no default",
		Behaviors.default_for_disposition("missing"), {})


func _disposition_semantics_are_distinct() -> void:
	var passive := Behaviors.disposition_rules(Behaviors.PASSIVE)
	var provoked := Behaviors.disposition_rules(Behaviors.PROVOKED)
	var wary := Behaviors.disposition_rules(Behaviors.WARY)
	var territorial := Behaviors.disposition_rules(Behaviors.TERRITORIAL)
	var hunter := Behaviors.disposition_rules(Behaviors.HUNTER)
	check_true("passive never initiates combat", not bool(passive["initiates_combat"]))
	check_true("passive also ignores provocation",
		not bool(passive["engages_when_provoked"]))
	check_true("provoked waits for a trigger",
		not bool(provoked["initiates_combat"]) and bool(provoked["engages_when_provoked"]))
	check_true("wary retreats during its warning",
		bool(wary["warns_before_chase"]) and bool(wary["retreats_during_warning"]))
	check_true("territorial warns but holds its territory",
		bool(territorial["warns_before_chase"])
		and not bool(territorial["retreats_during_warning"]))
	check_true("only hunter semantics enable a burst",
		bool(hunter["uses_burst"])
		and not bool(territorial["uses_burst"])
		and not bool(wary["uses_burst"]))
	check_eq("unknown disposition has no semantic rules",
		Behaviors.disposition_rules("missing"), {})


func _live_roster_profiles_are_complete() -> void:
	var expected: Dictionary = {
		"slime": Behaviors.PASSIVE,
		"mushroom": Behaviors.WARY,
		"kappa": Behaviors.TERRITORIAL,
		"lantern": Behaviors.HUNTER,
		"racoon": Behaviors.PROVOKED,
		"snake": Behaviors.WARY,
		"owl": Behaviors.WARY,
		"lizard": Behaviors.TERRITORIAL,
		"bat": Behaviors.HUNTER,
		"mole": Behaviors.TERRITORIAL,
		"bear": Behaviors.TERRITORIAL,
		"tengu": Behaviors.HUNTER,
		"thornback": Behaviors.TERRITORIAL,
		"forest_wraith": Behaviors.HUNTER,
		"cliff_drake": Behaviors.TERRITORIAL,
		"mountain_king": Behaviors.TERRITORIAL,
	}
	check_eq("all 16 live enemies have authored world profiles",
		Behaviors.ENEMY_PRESETS.size(), 16)
	for enemy_id: String in expected:
		var profile := Behaviors.profile(enemy_id)
		check_eq("%s keeps its authored disposition" % enemy_id,
			String(profile["disposition"]), String(expected[enemy_id]))
		check_true("%s does not use fallback behavior" % enemy_id,
			not bool(profile["is_fallback"]))
		check_eq("%s profile validates" % enemy_id, Behaviors.validate(profile), [])
	check_eq("correct Raccoon spelling resolves legacy authored ID",
		String(Behaviors.profile("raccoon")["id"]), "racoon")

	var fallback := Behaviors.profile("dormant_uninspected_enemy")
	check_true("unknown runtime profile is marked as fallback", bool(fallback["is_fallback"]))
	check_eq("unknown runtime profile is safely passive",
		String(fallback["disposition"]), Behaviors.PASSIVE)
	check_eq("unknown runtime profile never chases", float(fallback["chase_speed"]), 0.0)
	check_eq("safe fallback still validates", Behaviors.validate(fallback), [])


func _mushroom_and_bat_are_contrasting_valid_presets() -> void:
	var mushroom := Behaviors.preset_for_enemy("mushroom")
	var bat := Behaviors.preset_for_enemy("bat")
	check_eq("Mushroom uses wary behavior",
		String(mushroom["disposition"]), Behaviors.WARY)
	check_eq("Bat uses hunter behavior",
		String(bat["disposition"]), Behaviors.HUNTER)
	check_eq("Mushroom preset passes validation", Behaviors.validate(mushroom), [])
	check_eq("Bat preset passes validation", Behaviors.validate(bat), [])
	check_true("Bat detects farther than Mushroom",
		float(bat["detect_radius"]) > float(mushroom["detect_radius"]))
	check_true("Mushroom gives a longer warning than Bat",
		float(mushroom["warning_seconds"]) > float(bat["warning_seconds"]))
	check_eq("Mushroom has no pursuit burst", float(mushroom["burst_speed"]), 0.0)
	check_eq("Bat uses the authored short burst", float(bat["burst_speed"]), 96.0)
	check_eq("Bat burst is capped at six tenths of a second",
		float(bat["burst_seconds"]), 0.6)
	check_eq("preset lookup normalizes case and whitespace",
		String(Behaviors.preset_for_enemy("  BAT ")["id"]), "bat")
	check_eq("unknown enemies do not inherit filler behavior",
		Behaviors.preset_for_enemy("uninspected_enemy"), {})


func _preset_results_are_safe_copies() -> void:
	var mushroom := Behaviors.preset_for_enemy("mushroom")
	mushroom["chase_speed"] = 80.0
	check_eq("callers cannot mutate shared enemy presets",
		float(Behaviors.preset_for_enemy("mushroom")["chase_speed"]), 50.0)
	var hunter_default := Behaviors.default_for_disposition(Behaviors.HUNTER)
	hunter_default["burst_seconds"] = 9.0
	check_eq("callers cannot mutate shared disposition defaults",
		float(Behaviors.default_for_disposition(Behaviors.HUNTER)["burst_seconds"]), 0.6)


func _speed_bands_reject_player_matching() -> void:
	check_true("75.9 px/s is outside the sustained player band",
		Behaviors.is_sustained_speed_allowed(75.9))
	check_true("76 px/s begins the forbidden sustained band",
		not Behaviors.is_sustained_speed_allowed(76.0))
	check_true("80 px/s cannot be sustained by an enemy",
		not Behaviors.is_sustained_speed_allowed(80.0))
	check_true("84 px/s ends the forbidden sustained band",
		not Behaviors.is_sustained_speed_allowed(84.0))
	check_true("84.1 px/s is outside the sustained player band",
		Behaviors.is_sustained_speed_allowed(84.1))

	_assert_invalid_change("roam below 18 is rejected", "mushroom", "roam_speed", 17.9,
		"roam_speed must stay within")
	_assert_invalid_change("roam above 36 is rejected", "mushroom", "roam_speed", 36.1,
		"roam_speed must stay within")
	_assert_invalid_change("chase below 48 is rejected", "mushroom", "chase_speed", 47.9,
		"chase_speed must stay within")
	_assert_invalid_change("chase above 68 is rejected", "mushroom", "chase_speed", 68.1,
		"chase_speed must stay within")
	_assert_invalid_change("player-matching chase is named explicitly", "mushroom", "chase_speed", 80.0,
		"sustained 76-84")


func _burst_limits_require_recovery() -> void:
	_assert_invalid_change("hunter burst cannot exceed 96", "bat", "burst_speed", 96.1,
		"at most 96")
	_assert_invalid_change("hunter burst must clear the sustained player band", "bat", "burst_speed", 84.0,
		"above 84")
	_assert_invalid_change("hunter burst cannot exceed 0.6 seconds", "bat", "burst_seconds", 0.61,
		"at most 0.6")
	_assert_invalid_change("hunter burst requires two seconds recovery", "bat", "recovery_seconds", 1.99,
		"at least 2.0")
	var mushroom := Behaviors.preset_for_enemy("mushroom")
	mushroom["burst_speed"] = 90.0
	mushroom["burst_seconds"] = 0.4
	check_true("non-hunters cannot receive burst tuning",
		_has_error(Behaviors.validate(mushroom), "only hunter"))


func _timing_and_radius_fields_are_validated() -> void:
	_assert_invalid_change("negative warning is rejected", "mushroom", "warning_seconds", -0.1,
		"warning_seconds cannot be negative")
	_assert_invalid_change("negative memory is rejected", "mushroom", "memory_seconds", -0.1,
		"memory_seconds cannot be negative")
	_assert_invalid_change("negative recovery is rejected", "mushroom", "recovery_seconds", -0.1,
		"recovery_seconds cannot be negative")
	_assert_invalid_change("negative flee grace is rejected", "mushroom",
		"post_flee_grace_seconds", -0.1, "post_flee_grace_seconds cannot be negative")
	_assert_invalid_change("proactive behavior requires a warning", "mushroom", "warning_seconds", 0.0,
		"require a positive warning_seconds")
	_assert_invalid_change("proactive behavior requires detection", "mushroom", "detect_radius", 0.0,
		"require a positive detect_radius")
	_assert_invalid_change("memory must remain positive while active", "mushroom", "memory_seconds", 0.0,
		"require positive memory_seconds")
	_assert_invalid_change("flee grace must remain positive", "mushroom",
		"post_flee_grace_seconds", 0.0, "must be positive")
	_assert_invalid_change("leash cannot be inside detection", "mushroom", "leash_radius", 40.0,
		"smaller than detect_radius")
	_assert_invalid_change("leash cannot be inside roam radius", "bat", "leash_radius", 40.0,
		"smaller than roam_radius")

	var missing := Behaviors.preset_for_enemy("mushroom")
	missing.erase("memory_seconds")
	check_true("missing timing fields fail before integration",
		_has_error(Behaviors.validate(missing), "missing required field 'memory_seconds'"))
	var provoked := Behaviors.default_for_disposition(Behaviors.PROVOKED)
	provoked["detect_radius"] = 24.0
	check_true("provoked behavior cannot silently become proximity aggro",
		_has_error(Behaviors.validate(provoked), "cannot initiate through detect_radius"))


func _assert_invalid_change(label: String, enemy_id: String, field: String,
		value: Variant, expected_error: String) -> void:
	var definition := Behaviors.preset_for_enemy(enemy_id)
	definition[field] = value
	var errors := Behaviors.validate(definition)
	check_true(label + " (errors: %s)" % [errors], _has_error(errors, expected_error))


func _has_error(errors: Array[String], fragment: String) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false


func _finish() -> void:
	print("")
	print("PASS - enemy world behavior definitions are deterministic and safe." if failures == 0 \
		else "FAIL - %d world behavior check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
