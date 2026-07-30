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
	"sweep": {"id": "sweep", "type": "attack", "spCost": 1, "role": "samurai",
		"requiredWeaponType": "blade"},
	"kunai": {"id": "kunai", "type": "attack", "spCost": 1, "role": "ranger",
		"requiredWeaponType": "ranged"},
	"iaido": {"id": "iaido", "type": "attack", "spCost": 2, "role": "samurai",
		"requiredLevel": 4, "requiredWeaponType": "blade", "hits": 2},
	"storm_draw": {"id": "storm_draw", "type": "attack", "spCost": 3,
		"role": "samurai", "requiredWeaponType": "blade", "cooldownTurns": 1},
	"mana_tea": {"id": "mana_tea", "type": "buff", "buffType": "energy",
		"buffValue": 3, "spCost": 1, "role": "scholar", "requiredWeaponType": "kana"},
	"bulwark": {"id": "bulwark", "type": "buff", "buffType": "shield",
		"buffValue": 30, "spCost": 3, "role": "guardian", "requiredWeaponType": "heavy"},
	"slow_charge": {"id": "slow_charge", "type": "buff", "buffType": "energy",
		"buffValue": 2, "buffDuration": 3, "spCost": 1, "role": "scholar"},
	"rune_ward": {"id": "rune_ward", "type": "buff", "starter": false,
		"buffType": "def", "buffValue": 4, "buffDuration": 3,
		"spCost": 1, "role": "scholar", "requiredWeaponType": "kana"},
	"spirit_shear": {"id": "spirit_shear", "type": "attack", "power": 16,
		"debuffType": "def", "debuffValue": 4, "debuffDuration": 3,
		"spCost": 3, "role": "samurai", "requiredWeaponType": "blade"},
	"venom_cut": {"id": "venom_cut", "type": "attack", "power": 10,
		"debuffType": "poison", "debuffValue": 3, "debuffDuration": 3,
		"spCost": 1, "role": "samurai", "requiredWeaponType": "blade"},
	"riposte": {"id": "riposte", "type": "counter", "power": 12,
		"counterDamage": 8, "spCost": 2, "role": "samurai",
		"requiredWeaponType": "blade"},
	"perilous_parry": {"id": "perilous_parry", "type": "parry", "power": 18,
		"counterDamage": 14, "spCost": 3, "role": "samurai",
		"requiredWeaponType": "blade"},
	"empty_counter": {"id": "empty_counter", "type": "counter", "power": 12,
		"spCost": 1, "role": "samurai", "requiredWeaponType": "blade"},
}


func _initialize() -> void:
	_sanitize_old_saves()
	_weapon_and_runtime_gates()
	_six_slot_mutation()
	_talent_unlocks()
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
	check_true("timed ATK, DEF, and Speed buffs use the duration resolver",
		AbilityRules.is_runtime_supported(abilities["rune_ward"]))
	check_true("immediate Energy and Shield buffs use the real resolver",
		AbilityRules.is_runtime_supported(abilities["mana_tea"])
		and AbilityRules.is_runtime_supported(abilities["bulwark"]))
	check_true("timed buffs remain hidden even when their stat name matches",
		not AbilityRules.is_runtime_supported(abilities["slow_charge"]))
	check_true("authored stat debuffs are supported but unknown future types stay hidden",
		AbilityRules.is_runtime_supported(abilities["spirit_shear"])
		and not AbilityRules.is_runtime_supported(abilities["venom_cut"]))
	check_true("authored counters and parries resolve but empty reactions stay hidden",
		AbilityRules.is_runtime_supported(abilities["riposte"])
		and AbilityRules.is_runtime_supported(abilities["perilous_parry"])
		and not AbilityRules.is_runtime_supported(abilities["empty_counter"]))
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


func _talent_unlocks() -> void:
	var build := {"skills": ["guard"], "unlockedAbilities": []}
	check_eq("level 1 earns no Talent Points",
		AbilityRules.unspent_talent_points(1, build, abilities), 0)
	check_true("a supported talent cannot unlock before its point is earned",
		not AbilityRules.unlock_talent("sweep", 1, build, abilities))
	check_true("level 2 can permanently unlock Blade Sweep",
		AbilityRules.unlock_talent("sweep", 2, build, abilities))
	check_true("unlocked talent becomes known", AbilityRules.is_known(abilities["sweep"], build))
	check_eq("the unlock consumes its Talent Point",
		AbilityRules.unspent_talent_points(2, build, abilities), 0)
	check_true("the same Talent cannot be purchased twice",
		not AbilityRules.unlock_talent("sweep", 3, build, abilities))
	check_true("timed stat buffs can be sold now that duration is visible and enforced",
		AbilityRules.is_honest_talent(abilities["rune_ward"]))
	check_true("cooldown-only actions are honest now that combat enforces cadence",
		AbilityRules.is_honest_talent(abilities["storm_draw"]))
	check_true("immediate and timed resolved buff talents are honest",
		AbilityRules.is_honest_talent(abilities["mana_tea"])
		and AbilityRules.is_honest_talent(abilities["bulwark"])
		and AbilityRules.is_honest_talent(abilities["rune_ward"]))
	check_true("resolved debuff talents are honest without exposing unknown statuses",
		AbilityRules.is_honest_talent(abilities["spirit_shear"])
		and not AbilityRules.is_honest_talent(abilities["venom_cut"]))
	check_true("counter and parry Talents are honest only with real return damage",
		AbilityRules.is_honest_talent(abilities["riposte"])
		and AbilityRules.is_honest_talent(abilities["perilous_parry"])
		and not AbilityRules.is_honest_talent(abilities["empty_counter"]))
	var choices := AbilityRules.next_talent_defs(
		2, {"skills": [], "unlockedAbilities": []}, abilities,
		["sweep", "kunai", "rune_ward"])
	check_eq("next choices expose one honest action per role",
		choices.map(func(a): return a["id"]), ["sweep", "kunai", "rune_ward"])
	var follow_up := AbilityRules.next_talent_defs(
		2, {"skills": [], "unlockedAbilities": ["sweep"]}, abilities,
		["sweep", "iaido", "kunai", "rune_ward"])
	check_true("the next Samurai Talent stays visible before its level",
		follow_up.map(func(a): return a["id"]).has("iaido"))
	check_true("visible level-locked Talent still cannot be purchased",
		not AbilityRules.can_unlock_talent(abilities["iaido"], 3,
			{"skills": [], "unlockedAbilities": ["sweep"]}, abilities))


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
