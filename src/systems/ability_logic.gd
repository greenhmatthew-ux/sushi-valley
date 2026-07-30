class_name AbilityLogic
extends RefCounted
## Pure rules for the player's six-slot combat loadout.
##
## The authored ability table owns names, effects, role tags, and weapon requirements.
## This class only answers build questions, so persistence and UI share one definition of
## "known", "equipped", and "usable" without depending on autoloads.

const MAX_SKILLS := 6
const RUNTIME_TYPES := ["attack", "block", "heal"]
const UNRESOLVED_EFFECT_FIELDS := [
	"buffType", "counterDamage", "debuffType", "lifestealPct",
]


static func sanitize_build(build: Dictionary, abilities: Dictionary) -> void:
	var known_seen := {}
	var unlocked: Array = []
	for raw_id in build.get("unlockedAbilities", []):
		var ability_id := String(raw_id)
		if ability_id.is_empty() or known_seen.has(ability_id) or not abilities.has(ability_id):
			continue
		known_seen[ability_id] = true
		unlocked.append(ability_id)
	build["unlockedAbilities"] = unlocked

	var equipped_seen := {}
	var skills: Array = []
	for raw_id in build.get("skills", []):
		var ability_id := String(raw_id)
		if skills.size() >= MAX_SKILLS or ability_id.is_empty() \
				or equipped_seen.has(ability_id) or not abilities.has(ability_id):
			continue
		var ability: Dictionary = abilities[ability_id]
		if not is_known(ability, build):
			continue
		equipped_seen[ability_id] = true
		skills.append(ability_id)
	build["skills"] = skills


static func is_known(ability: Dictionary, build: Dictionary) -> bool:
	if ability.is_empty():
		return false
	return bool(ability.get("starter", false)) \
		or String(ability.get("id", "")) in build.get("unlockedAbilities", [])


static func weapon_matches(ability: Dictionary, weapon_type: String) -> bool:
	var required := String(ability.get("requiredWeaponType", ""))
	return required.is_empty() or required == weapon_type


static func is_runtime_supported(ability: Dictionary) -> bool:
	return String(ability.get("type", "")) in RUNTIME_TYPES


## Talent purchases are stricter than old-save/runtime filtering: never sell an action whose
## authored secondary effect the current encounter would silently ignore.
static func is_honest_talent(ability: Dictionary) -> bool:
	if not is_runtime_supported(ability) or bool(ability.get("starter", false)) \
			or int(ability.get("spCost", 0)) <= 0:
		return false
	for field in UNRESOLVED_EFFECT_FIELDS:
		if ability.has(field):
			return false
	return true


static func talent_points_earned(level: int) -> int:
	return maxi(0, level - 1)


static func talent_points_spent(build: Dictionary, abilities: Dictionary) -> int:
	var spent := 0
	for raw_id in build.get("unlockedAbilities", []):
		var ability: Dictionary = abilities.get(String(raw_id), {})
		spent += maxi(0, int(ability.get("spCost", 0)))
	return spent


static func unspent_talent_points(level: int, build: Dictionary,
		abilities: Dictionary) -> int:
	return maxi(0, talent_points_earned(level) - talent_points_spent(build, abilities))


static func can_unlock_talent(ability: Dictionary, level: int, build: Dictionary,
		abilities: Dictionary) -> bool:
	if not is_honest_talent(ability) or is_known(ability, build):
		return false
	if level < int(ability.get("requiredLevel", 1)):
		return false
	return unspent_talent_points(level, build, abilities) >= int(ability.get("spCost", 0))


static func unlock_talent(ability_id: String, level: int, build: Dictionary,
		abilities: Dictionary) -> bool:
	if not abilities.has(ability_id):
		return false
	var ability: Dictionary = abilities[ability_id]
	if not can_unlock_talent(ability, level, build, abilities):
		return false
	build["unlockedAbilities"].append(ability_id)
	return true


## Keep the choice readable: show the earliest honest unknown action for each authored role.
static func next_talent_defs(_level: int, build: Dictionary, abilities: Dictionary,
		authored_order: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roles_seen := {}
	var ids: Array = authored_order if not authored_order.is_empty() else abilities.keys()
	for raw_id in ids:
		var ability: Dictionary = abilities.get(String(raw_id), {})
		var role := String(ability.get("role", "adventurer"))
		if roles_seen.has(role) or is_known(ability, build) or not is_honest_talent(ability):
			continue
		roles_seen[role] = true
		out.append(ability)
	return out


static func can_equip(ability: Dictionary, build: Dictionary, weapon_type: String) -> bool:
	return is_known(ability, build) and is_runtime_supported(ability) \
		and weapon_matches(ability, weapon_type)


static func set_equipped(build: Dictionary, ability_id: String, equipped: bool,
		abilities: Dictionary, weapon_type: String) -> bool:
	sanitize_build(build, abilities)
	var skills: Array = build["skills"]
	var already_equipped := ability_id in skills
	if equipped == already_equipped:
		return true
	if not equipped:
		skills.erase(ability_id)
		return true
	if skills.size() >= MAX_SKILLS or not abilities.has(ability_id):
		return false
	var ability: Dictionary = abilities[ability_id]
	if not can_equip(ability, build, weapon_type):
		return false
	skills.append(ability_id)
	return true


static func known_defs(build: Dictionary, abilities: Dictionary,
		authored_order: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = authored_order if not authored_order.is_empty() else abilities.keys()
	for raw_id in ids:
		var ability: Dictionary = abilities.get(String(raw_id), {})
		if is_known(ability, build):
			out.append(ability)
	return out


## Equipped and currently weapon-compatible definitions for combat. Invalid or stale
## ids are skipped rather than making a fight unusable; Basic Attack remains separate.
static func usable_defs(build: Dictionary, abilities: Dictionary,
		weapon_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_id in build.get("skills", []):
		var ability: Dictionary = abilities.get(String(raw_id), {})
		if is_known(ability, build) and is_runtime_supported(ability) \
				and weapon_matches(ability, weapon_type):
			out.append(ability)
	return out
