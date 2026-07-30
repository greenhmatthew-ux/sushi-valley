class_name AbilityLogic
extends RefCounted
## Pure rules for the player's six-slot combat loadout.
##
## The authored ability table owns names, effects, role tags, and weapon requirements.
## This class only answers build questions, so persistence and UI share one definition of
## "known", "equipped", and "usable" without depending on autoloads.

const MAX_SKILLS := 6
const RUNTIME_TYPES := ["attack", "block", "heal"]


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
