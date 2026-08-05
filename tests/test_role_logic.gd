extends SceneTree
## Pure weapon-to-role and passive-definition coverage.
##
##   godot --headless --path . --script res://tests/test_role_logic.gd

const Roles = preload("res://src/systems/role_logic.gd")

var failures: int = 0


func _initialize() -> void:
	_weapon_mapping_is_complete()
	_definitions_are_stable_and_safe()
	_each_role_has_only_its_authored_passive()
	_guardian_shield_scales_with_a_minimum()
	_finish()


func _weapon_mapping_is_complete() -> void:
	var expected: Dictionary = {
		"blade": Roles.SAMURAI,
		"ranged": Roles.RANGER,
		"kana": Roles.SCHOLAR,
		"heavy": Roles.GUARDIAN,
	}
	check_eq("role order is the four authored combat roles", Roles.ROLE_ORDER,
		[Roles.SAMURAI, Roles.RANGER, Roles.SCHOLAR, Roles.GUARDIAN])
	for weapon_type: String in expected:
		var role_id := Roles.role_for_weapon_type(weapon_type)
		check_eq("%s maps to %s" % [weapon_type, expected[weapon_type]],
			role_id, expected[weapon_type])
		check_eq("%s definition points back to its weapon" % role_id,
			String(Roles.definition(role_id)["weapon_type"]), weapon_type)
	check_eq("empty weapon is Adventurer",
		Roles.role_for_weapon_type(""), Roles.ADVENTURER)
	check_eq("unknown weapon is Adventurer",
		Roles.role_for_weapon_type("future_weapon"), Roles.ADVENTURER)
	check_eq("weapon mapping is whitespace and case tolerant",
		Roles.role_for_weapon_type("  BLADE "), Roles.SAMURAI)


func _definitions_are_stable_and_safe() -> void:
	for role_id: String in [Roles.ADVENTURER] + Roles.ROLE_ORDER:
		var role := Roles.definition(role_id)
		check_eq("%s definition keeps its id" % role_id, String(role["id"]), role_id)
		check_true("%s has a display name" % role_id, not String(role["name"]).is_empty())
		check_true("%s has passive copy" % role_id, role.has("passive"))
	var mutated := Roles.definition(Roles.SAMURAI)
	mutated["opening_flow"] = 99
	check_eq("callers cannot mutate the shared role table",
		Roles.opening_flow(Roles.SAMURAI), 1)
	check_eq("unknown role definition falls back to Adventurer",
		String(Roles.definition("missing")["id"]), Roles.ADVENTURER)
	check_eq("role lookup is whitespace and case tolerant",
		String(Roles.definition("  RANGER ")["id"]), Roles.RANGER)
	check_eq("active definition derives from the weapon",
		String(Roles.active_definition("kana")["id"]), Roles.SCHOLAR)


func _each_role_has_only_its_authored_passive() -> void:
	_assert_passives(Roles.ADVENTURER, 0, 0, 0, 0)
	_assert_passives(Roles.SAMURAI, 0, 0, 1, 0)
	_assert_passives(Roles.RANGER, 1, 0, 0, 0)
	_assert_passives(Roles.SCHOLAR, 0, 1, 0, 0)
	_assert_passives(Roles.GUARDIAN, 0, 0, 0, 2)
	check_true("Samurai passive explains Flow",
		Roles.passive_summary(Roles.SAMURAI).contains("1 Flow"))
	check_true("Ranger passive explains Speed",
		Roles.passive_summary(Roles.RANGER).contains("+1 effective SPD"))
	check_true("Scholar passive explains Energy",
		Roles.passive_summary(Roles.SCHOLAR).contains("+1 maximum Energy"))
	check_true("Guardian passive explains Shield",
		Roles.passive_summary(Roles.GUARDIAN).contains("10% max HP"))


func _assert_passives(role_id: String, expected_speed: int, expected_energy: int,
		expected_flow: int, expected_shield: int) -> void:
	check_eq("%s Speed bonus" % role_id, Roles.speed_bonus(role_id), expected_speed)
	check_eq("%s Energy bonus" % role_id,
		Roles.max_energy_bonus(role_id), expected_energy)
	check_eq("%s opening Flow" % role_id, Roles.opening_flow(role_id), expected_flow)
	check_eq("%s opening Shield" % role_id,
		Roles.opening_shield(role_id, 12), expected_shield)


func _guardian_shield_scales_with_a_minimum() -> void:
	check_eq("low HP Guardian still receives two Shield",
		Roles.opening_shield(Roles.GUARDIAN, 1), 2)
	check_eq("starter HP Guardian receives two Shield",
		Roles.opening_shield(Roles.GUARDIAN, 12), 2)
	check_eq("Guardian Shield rounds authored ten percent to an integer",
		Roles.opening_shield(Roles.GUARDIAN, 26), 3)
	check_eq("Guardian Shield scales at high HP",
		Roles.opening_shield(Roles.GUARDIAN, 100), 10)
	check_eq("other roles never inherit Guardian Shield",
		Roles.opening_shield(Roles.SAMURAI, 100), 0)


func _finish() -> void:
	print("")
	print("PASS - weapon-derived roles and passives are deterministic." if failures == 0 \
		else "FAIL - %d role check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
