class_name PlayerStats
extends RefCounted
## Player level and combat stats, derived from learning XP. Pure and node-free.
##
## COMBAT_DESIGN.md: "Player stats derive from learning XP level, vitality/power/agility
## allocation, and equipped gear." The important direction of causality stays intact: studying
## Japanese raises the level that grants Attribute Points. Nothing else grants combat-level XP.
##
## WHY THIS EXISTS. The ported enemy numbers assume a character who levels. Without that the
## player was a permanent 12 HP with a flat basic attack, and a simulation of the real
## encounter showed the kappa (55 hp / 9 atk) and lantern (60 hp / 10 atk) were unwinnable at
## 0% even with every recall answered correctly — you die in two rounds and need seven to
## kill. Enemies were not too strong; the player simply never grew.

## XP for one level. LearningProgression awards 6-12 per correct answer, so a level is roughly
## a dozen reviews — frequent enough to feel earned, slow enough to matter.
const XP_PER_LEVEL := 100

const BASE_MAX_HP := 12
const BASE_ATK := 6
const BASE_DEF := 2
const BASE_SPEED := 5

## Per level gained. HP grows fastest because incoming damage is what ends a fight, and the
## enemy roster's atk climbs steeply (5 -> 10 across the four foes that exist).
const HP_PER_LEVEL := 6
const ATK_PER_LEVEL := 2
## DEF every other level, so mitigation improves without trivialising early foes.
const LEVELS_PER_DEF := 2

## Kana's useful allocation values are retained. Attribute Points are intentionally separate
## from future Talent unlocks so an early HP choice cannot quietly block a later ability.
const ALLOCATION_KEYS := ["vitality", "power", "agility"]
const ACTIVE_ALLOCATION_KEYS := ["vitality", "power", "agility"]
const VITALITY_HP := 6
const POWER_ATK := 1
const AGILITY_SPEED := 1

const RARITY_GROWTH := {
	"common": 0.012,
	"uncommon": 0.015,
	"rare": 0.018,
	"epic": 0.021,
	"legendary": 0.024,
	"titan": 0.028,
}


static func level_from_xp(xp: int) -> int:
	return 1 + int(floor(float(maxi(0, xp)) / float(XP_PER_LEVEL)))


## XP still needed for the next level, for a progress readout.
static func xp_into_level(xp: int) -> int:
	return maxi(0, xp) % XP_PER_LEVEL


## One refundable Attribute Point per level gained. Level 1 starts with no unearned choice.
static func attribute_points_earned(xp: int) -> int:
	return maxi(0, level_from_xp(xp) - 1)


static func normalized_allocations(raw: Dictionary) -> Dictionary:
	var allocations := {"vitality": 0, "power": 0, "agility": 0}
	for key in ALLOCATION_KEYS:
		allocations[key] = maxi(0, int(raw.get(key, 0)))
	return allocations


static func attribute_points_spent(raw: Dictionary) -> int:
	var allocations := normalized_allocations(raw)
	return int(allocations["vitality"]) + int(allocations["power"]) \
		+ int(allocations["agility"])


static func unspent_attribute_points(xp: int, raw: Dictionary) -> int:
	return maxi(0, attribute_points_earned(xp) - attribute_points_spent(raw))


## Mutate one allocation step. Decreases are always allowed for free respec; increases must
## be active and affordable.
static func adjust_allocation(raw: Dictionary, key: String, delta: int, xp: int) -> bool:
	if key not in ALLOCATION_KEYS or delta not in [-1, 1]:
		return false
	var current := maxi(0, int(raw.get(key, 0)))
	if delta < 0:
		if current <= 0:
			return false
		raw[key] = current - 1
		return true
	if key not in ACTIVE_ALLOCATION_KEYS or unspent_attribute_points(xp, raw) <= 0:
		return false
	raw[key] = current + 1
	return true


static func max_hp(level: int) -> int:
	return BASE_MAX_HP + (maxi(1, level) - 1) * HP_PER_LEVEL


static func atk(level: int) -> int:
	return BASE_ATK + (maxi(1, level) - 1) * ATK_PER_LEVEL


static func def(level: int) -> int:
	return BASE_DEF + (maxi(1, level) - 1) / LEVELS_PER_DEF


## Preserve Kana's gentle base curve: +1 SPD about every three learning levels.
static func speed(level: int) -> int:
	return BASE_SPEED + int(floor((maxi(1, level) - 1) * 0.3))


## Rarity inference and positive-stat scaling preserve Kana's authored gear rules:
## requiredLevel is an equip floor, while gear keeps growing with the player after it.
static func item_rarity(item: Dictionary) -> String:
	var explicit := String(item.get("rarity", ""))
	if not explicit.is_empty():
		return explicit
	if item.get("kind", "") != "gear":
		return "common"
	var required_level := int(item.get("requiredLevel", 1))
	if required_level >= 60:
		return "legendary"
	if required_level >= 48:
		return "epic"
	if required_level >= 36:
		return "rare"
	if required_level >= 12:
		return "uncommon"
	return "common"


static func scaled_item_stats(item: Dictionary, level: int) -> Dictionary:
	var base: Dictionary = item.get("stats", {})
	if item.get("kind", "") != "gear":
		return base.duplicate(true)
	var floor_level := int(item.get("requiredLevel", 1))
	var levels := maxi(0, level - floor_level)
	var growth := float(RARITY_GROWTH.get(item_rarity(item), RARITY_GROWTH["common"]))
	var multiplier := 1.0 + levels * growth
	var scaled: Dictionary = {}
	for stat in ["hp", "atk", "def", "spd"]:
		if not base.has(stat):
			continue
		var value := int(base[stat])
		scaled[stat] = maxi(value, roundi(value * multiplier)) if value > 0 else value
	return scaled


static func gear_bonus(gear_defs: Array[Dictionary], level: int) -> Dictionary:
	var total := {"hp": 0, "atk": 0, "def": 0, "spd": 0}
	for item in gear_defs:
		var stats := scaled_item_stats(item, level)
		for stat in total:
			total[stat] += int(stats.get(stat, 0))
	return total


## Everything a fight needs, from learning XP, allocations, and equipped gear.
static func from_xp(xp: int, gear_defs: Array[Dictionary] = [],
		allocation_data: Dictionary = {}) -> Dictionary:
	var lv := level_from_xp(xp)
	var gear := gear_bonus(gear_defs, lv)
	var allocations := normalized_allocations(allocation_data)
	return {
		"level": lv,
		"max_hp": maxi(1, max_hp(lv) + int(gear["hp"])
			+ int(allocations["vitality"]) * VITALITY_HP),
		"atk": maxi(1, atk(lv) + int(gear["atk"])
			+ int(allocations["power"]) * POWER_ATK),
		"def": maxi(0, def(lv) + int(gear["def"])),
		"speed": maxi(1, speed(lv) + int(gear["spd"])
			+ int(allocations["agility"]) * AGILITY_SPEED),
		"xp_into_level": xp_into_level(xp),
		"xp_per_level": XP_PER_LEVEL,
	}
