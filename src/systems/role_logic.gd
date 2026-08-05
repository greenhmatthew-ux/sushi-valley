class_name RoleLogic
extends RefCounted
## Pure, save-free definition of the player's weapon-derived combat role.
##
## Roles are deliberately derived rather than persisted. Equipping a weapon changes the
## active role immediately, while an empty or unknown weapon type safely falls back to the
## passive-free Adventurer. Encounter systems consume the numeric accessors below so each
## passive has one authoritative value.

const ADVENTURER := "adventurer"
const SAMURAI := "samurai"
const RANGER := "ranger"
const SCHOLAR := "scholar"
const GUARDIAN := "guardian"

const ROLE_ORDER: Array[String] = [SAMURAI, RANGER, SCHOLAR, GUARDIAN]

const WEAPON_TO_ROLE: Dictionary = {
	"blade": SAMURAI,
	"ranged": RANGER,
	"kana": SCHOLAR,
	"heavy": GUARDIAN,
}

const ROLE_DEFS: Dictionary = {
	ADVENTURER: {
		"id": ADVENTURER,
		"name": "Adventurer",
		"weapon_type": "",
		"passive": "No role passive.",
		"speed_bonus": 0,
		"max_energy_bonus": 0,
		"opening_flow": 0,
		"opening_shield_percent": 0.0,
		"opening_shield_minimum": 0,
	},
	SAMURAI: {
		"id": SAMURAI,
		"name": "Samurai",
		"weapon_type": "blade",
		"passive": "Begin combat with 1 Flow.",
		"speed_bonus": 0,
		"max_energy_bonus": 0,
		"opening_flow": 1,
		"opening_shield_percent": 0.0,
		"opening_shield_minimum": 0,
	},
	RANGER: {
		"id": RANGER,
		"name": "Ranger",
		"weapon_type": "ranged",
		"passive": "+1 effective SPD.",
		"speed_bonus": 1,
		"max_energy_bonus": 0,
		"opening_flow": 0,
		"opening_shield_percent": 0.0,
		"opening_shield_minimum": 0,
	},
	SCHOLAR: {
		"id": SCHOLAR,
		"name": "Scholar",
		"weapon_type": "kana",
		"passive": "+1 maximum Energy.",
		"speed_bonus": 0,
		"max_energy_bonus": 1,
		"opening_flow": 0,
		"opening_shield_percent": 0.0,
		"opening_shield_minimum": 0,
	},
	GUARDIAN: {
		"id": GUARDIAN,
		"name": "Guardian",
		"weapon_type": "heavy",
		"passive": "Begin combat with Shield equal to 10% max HP (minimum 2).",
		"speed_bonus": 0,
		"max_energy_bonus": 0,
		"opening_flow": 0,
		"opening_shield_percent": 0.10,
		"opening_shield_minimum": 2,
	},
}


static func role_for_weapon_type(weapon_type: String) -> String:
	var normalized := weapon_type.strip_edges().to_lower()
	return String(WEAPON_TO_ROLE.get(normalized, ADVENTURER))


static func definition(role_id: String) -> Dictionary:
	var normalized := _normalized_role(role_id)
	return (ROLE_DEFS[normalized] as Dictionary).duplicate(true)


static func active_definition(weapon_type: String) -> Dictionary:
	return definition(role_for_weapon_type(weapon_type))


static func passive_summary(role_id: String) -> String:
	return String(ROLE_DEFS[_normalized_role(role_id)].get("passive", ""))


static func speed_bonus(role_id: String) -> int:
	return int(ROLE_DEFS[_normalized_role(role_id)].get("speed_bonus", 0))


static func max_energy_bonus(role_id: String) -> int:
	return int(ROLE_DEFS[_normalized_role(role_id)].get("max_energy_bonus", 0))


static func opening_flow(role_id: String) -> int:
	return int(ROLE_DEFS[_normalized_role(role_id)].get("opening_flow", 0))


static func opening_shield(role_id: String, max_hp: int) -> int:
	var role: Dictionary = ROLE_DEFS[_normalized_role(role_id)]
	var percent := float(role.get("opening_shield_percent", 0.0))
	if percent <= 0.0:
		return 0
	var minimum := maxi(0, int(role.get("opening_shield_minimum", 0)))
	return maxi(minimum, roundi(float(maxi(0, max_hp)) * percent))


static func _normalized_role(role_id: String) -> String:
	var normalized := role_id.strip_edges().to_lower()
	return normalized if ROLE_DEFS.has(normalized) else ADVENTURER
