extends SceneTree
## Six-slot ability loadout rules: starter ownership, save cleanup, weapon gates, and
## combat filtering are pure and deterministic.

const AbilityRules = preload("res://src/systems/ability_logic.gd")

var failures := 0
var abilities := {
	"strike": {"id": "strike", "type": "attack", "starter": true,
		"requiredWeaponType": "blade"},
	"guard": {"id": "guard", "type": "block", "starter": true},
	"focus": {"id": "focus", "type": "heal", "starter": true},
	"rune_ward": {"id": "rune_ward", "type": "buff", "starter": false,
		"requiredWeaponType": "kana"},
}


func _initialize() -> void:
	_sanitize_old_saves()
	_weapon_and_runtime_gates()
	_six_slot_mutation()
	_finish()


func _sanitize_old_saves() -> void:
	var build := {"skills": ["strike", "strike", "missing", "focus"],
		"unlockedAbilities": ["rune_ward", "rune_ward", "missing"]}
	AbilityRules.sanitize_build(build, abilities)
	check_eq("equipped ids are valid and de-duplicated", build["skills"], ["strike", "focus"])
	check_eq("unlocks are valid and de-duplicated", build["unlockedAbilities"], ["rune_ward"])


func _weapon_and_runtime_gates() -> void:
	var build := {"skills": ["strike", "guard", "focus", "rune_ward"],
		"unlockedAbilities": ["rune_ward"]}
	check_true("Strike needs its blade", not AbilityRules.weapon_matches(abilities["strike"], ""))
	check_true("Strike accepts a blade", AbilityRules.weapon_matches(abilities["strike"], "blade"))
	check_true("authored buffs wait for their real resolver",
		not AbilityRules.is_runtime_supported(abilities["rune_ward"]))
	var usable := AbilityRules.usable_defs(build, abilities, "blade")
	check_eq("combat gets only supported, weapon-ready actions",
		usable.map(func(a): return a["id"]), ["strike", "guard", "focus"])


func _six_slot_mutation() -> void:
	var build := {"skills": ["guard"], "unlockedAbilities": []}
	check_true("known starter can be equipped",
		AbilityRules.set_equipped(build, "focus", true, abilities, ""))
	check_eq("equip appends to loadout", build["skills"], ["guard", "focus"])
	check_true("equipped skill can be removed",
		AbilityRules.set_equipped(build, "guard", false, abilities, ""))
	check_eq("remove updates loadout", build["skills"], ["focus"])
	check_true("wrong-weapon skill is rejected",
		not AbilityRules.set_equipped(build, "strike", true, abilities, ""))
	for id in ["step", "chant", "feint", "ward"]:
		abilities[id] = {"id": id, "type": "attack", "starter": true}
	var full_build := {"skills": ["guard", "focus", "step", "chant", "feint", "ward"],
		"unlockedAbilities": []}
	check_true("a seventh skill is rejected even when its weapon matches",
		not AbilityRules.set_equipped(full_build, "strike", true, abilities, "blade"))
	check_eq("full loadout remains capped at six",
		full_build["skills"].size(), AbilityRules.MAX_SKILLS)


func _finish() -> void:
	print("")
	print("PASS — loadout ownership, limits, and weapon gates hold." if failures == 0 \
		else "FAIL — %d ability check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
