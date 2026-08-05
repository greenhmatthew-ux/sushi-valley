class_name AbilityLogic
extends RefCounted

const Roles = preload("res://src/systems/role_logic.gd")
## Pure rules for the player's six-slot combat loadout.
##
## The authored ability table owns names, effects, role tags, and weapon requirements.
## This class only answers build questions, so persistence and UI share one definition of
## "known", "equipped", and "usable" without depending on autoloads.

const MAX_SKILLS := 6
const MAX_TALENT_POINTS := PlayerStats.MAX_LEVEL - 1
const TALENT_LEVEL_BANDS: Array[int] = [1, 12, 24, 36, 48, 60]
const RUNTIME_TYPES := ["attack", "block", "heal", "counter", "parry"]
const IMMEDIATE_BUFF_TYPES := ["energy", "shield"]
const TIMED_BUFF_TYPES := ["atk", "def", "speed"]
const TIMED_DEBUFF_TYPES := ["atk", "def", "speed"]
const UNRESOLVED_EFFECT_FIELDS := []


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


static func role_matches(ability: Dictionary, active_role: String) -> bool:
	var required_role := role_of(ability)
	return required_role == Roles.ADVENTURER or required_role == active_role


static func is_compatible(ability: Dictionary, weapon_type: String,
		active_role: String = "") -> bool:
	var resolved_role := active_role if not active_role.is_empty() \
		else Roles.role_for_weapon_type(weapon_type)
	return weapon_matches(ability, weapon_type) and role_matches(ability, resolved_role)


static func is_runtime_supported(ability: Dictionary) -> bool:
	var action_type := String(ability.get("type", ""))
	if action_type in RUNTIME_TYPES:
		if action_type in ["counter", "parry"]:
			return int(ability.get("counterDamage", 0)) > 0
		if ability.has("debuffType"):
			return String(ability.get("debuffType", "")) in TIMED_DEBUFF_TYPES \
				and int(ability.get("debuffDuration", 0)) > 0
		return true
	if action_type != "buff":
		return false
	var buff_type := String(ability.get("buffType", ""))
	var duration := int(ability.get("buffDuration", 1))
	return (buff_type in IMMEDIATE_BUFF_TYPES and duration <= 1) \
		or (buff_type in TIMED_BUFF_TYPES and duration > 0)


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
	return clampi(level - 1, 0, MAX_TALENT_POINTS)


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


static func can_equip(ability: Dictionary, build: Dictionary, weapon_type: String,
		active_role: String = "") -> bool:
	return is_known(ability, build) and is_runtime_supported(ability) \
		and is_compatible(ability, weapon_type, active_role)


static func set_equipped(build: Dictionary, ability_id: String, equipped: bool,
		abilities: Dictionary, weapon_type: String, active_role: String = "") -> bool:
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
	if not can_equip(ability, build, weapon_type, active_role):
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


## The fallback matches next_talent_defs: an ability the table gives no role tag
## is a general "adventurer" action, not an error.
static func role_of(ability: Dictionary) -> String:
	return String(ability.get("role", "adventurer"))


## Complete state for Character > Talents. Ownership is permanent; weapon compatibility
## affects equipping and combat use, never whether a player may buy a Talent Point unlock.
static func talent_state(ability: Dictionary, level: int, build: Dictionary,
		abilities: Dictionary, weapon_type: String = "", active_role: String = "") -> Dictionary:
	var ability_id := String(ability.get("id", ""))
	var known := is_known(ability, build)
	var equipped: bool = ability_id in build.get("skills", [])
	var runtime_supported := is_runtime_supported(ability)
	var honest := is_honest_talent(ability)
	var required_level := maxi(1, int(ability.get("requiredLevel", 1)))
	var cost := maxi(0, int(ability.get("spCost", 0)))
	var level_ready := level >= required_level
	var points_ready := unspent_talent_points(level, build, abilities) >= cost
	var resolved_role := active_role if not active_role.is_empty() \
		else Roles.role_for_weapon_type(weapon_type)
	var weapon_ready := is_compatible(ability, weapon_type, resolved_role)
	var ownership_state := "known"
	if not known:
		if not honest:
			ownership_state = "unsupported"
		elif not level_ready:
			ownership_state = "level_locked"
		elif not points_ready:
			ownership_state = "points_locked"
		else:
			ownership_state = "available"
	var state := ownership_state
	if known and not weapon_ready:
		state = "wrong_weapon"
	elif equipped:
		state = "equipped"
	return {
		"ability": ability,
		"ability_id": ability_id,
		"role": role_of(ability),
		"known": known,
		"equipped": equipped,
		"runtime_supported": runtime_supported,
		"honest_talent": honest,
		"level_ready": level_ready,
		"points_ready": points_ready,
		"weapon_ready": weapon_ready,
		"unlockable": can_unlock_talent(ability, level, build, abilities),
		"equipable": can_equip(ability, build, weapon_type, resolved_role),
		"required_level": required_level,
		"cost": cost,
		"ownership_state": ownership_state,
		"loadout_state": "equipped" if equipped else "unequipped",
		"weapon_state": "ready" if weapon_ready else "wrong_weapon",
		"state": state,
	}


## Every honest Talent is represented exactly once, grouped first by its authored role and
## then by the six progression bands. A legacy known action remains visible even if a newer
## runtime no longer offers it for purchase, preserving old-save ownership truthfully.
static func talent_groups(level: int, build: Dictionary, abilities: Dictionary,
		weapon_type: String = "", authored_order: Array = [],
		active_role: String = "") -> Array[Dictionary]:
	var ids: Array = authored_order if not authored_order.is_empty() else abilities.keys()
	var by_role: Dictionary = {}
	for role_id in Roles.ROLE_ORDER:
		by_role[role_id] = {}
	for raw_id in ids:
		var ability: Dictionary = abilities.get(String(raw_id), {})
		var legacy_talent := is_known(ability, build) \
			and not bool(ability.get("starter", false)) \
			and int(ability.get("spCost", 0)) > 0
		if ability.is_empty() or (not is_honest_talent(ability) and not legacy_talent):
			continue
		var role_id := role_of(ability)
		if not by_role.has(role_id):
			continue
		var required_level := maxi(1, int(ability.get("requiredLevel", 1)))
		var band_start := TALENT_LEVEL_BANDS[0]
		for candidate in TALENT_LEVEL_BANDS:
			if required_level < candidate:
				break
			band_start = candidate
		if not (by_role[role_id] as Dictionary).has(band_start):
			(by_role[role_id] as Dictionary)[band_start] = []
		((by_role[role_id] as Dictionary)[band_start] as Array).append(
			talent_state(ability, level, build, abilities, weapon_type, active_role))

	var groups: Array[Dictionary] = []
	for role_id in Roles.ROLE_ORDER:
		var bands: Array[Dictionary] = []
		for band_start in TALENT_LEVEL_BANDS:
			var states: Array = (by_role[role_id] as Dictionary).get(band_start, [])
			if states.is_empty():
				continue
			var band_index := TALENT_LEVEL_BANDS.find(band_start)
			var band_end := PlayerStats.MAX_LEVEL if band_index == TALENT_LEVEL_BANDS.size() - 1 \
				else TALENT_LEVEL_BANDS[band_index + 1] - 1
			bands.append({
				"start_level": band_start,
				"end_level": band_end,
				"states": states,
			})
		groups.append({
			"role": role_id,
			"role_def": Roles.definition(role_id),
			"bands": bands,
		})
	return groups


## Known actions bucketed by role for display, as [{role, defs}] with roles in the
## order the authored table first uses them. Data-driven so a fifth style added to
## abilities.json shows up without touching UI code.
static func known_defs_by_role(build: Dictionary, abilities: Dictionary,
		authored_order: Array = []) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var by_role := {}
	for ability in known_defs(build, abilities, authored_order):
		var role := role_of(ability)
		if not by_role.has(role):
			var group := {"role": role, "defs": []}
			by_role[role] = group
			groups.append(group)
		(by_role[role]["defs"] as Array).append(ability)
	return groups


## Equipped and currently weapon-compatible definitions for combat. Invalid or stale
## ids are skipped rather than making a fight unusable; Basic Attack remains separate.
static func usable_defs(build: Dictionary, abilities: Dictionary,
		weapon_type: String, active_role: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_id in build.get("skills", []):
		var ability: Dictionary = abilities.get(String(raw_id), {})
		if is_known(ability, build) and is_runtime_supported(ability) \
				and is_compatible(ability, weapon_type, active_role):
			out.append(ability)
	return out
