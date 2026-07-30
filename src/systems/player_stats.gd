class_name PlayerStats
extends RefCounted
## Player level and combat stats, derived from learning XP. Pure and node-free.
##
## COMBAT_DESIGN.md: "Player stats derive from learning XP level, vitality/power/agility
## allocation, and equipped gear." Level and equipped-gear bonuses exist here; allocation remains
## a later slice. The important direction of causality stays intact: studying Japanese raises the
## level that drives base stats and gear scaling. Nothing else grants combat-level XP.
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

## Per level gained. HP grows fastest because incoming damage is what ends a fight, and the
## enemy roster's atk climbs steeply (5 -> 10 across the four foes that exist).
const HP_PER_LEVEL := 6
const ATK_PER_LEVEL := 2
## DEF every other level, so mitigation improves without trivialising early foes.
const LEVELS_PER_DEF := 2

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


static func max_hp(level: int) -> int:
	return BASE_MAX_HP + (maxi(1, level) - 1) * HP_PER_LEVEL


static func atk(level: int) -> int:
	return BASE_ATK + (maxi(1, level) - 1) * ATK_PER_LEVEL


static func def(level: int) -> int:
	return BASE_DEF + (maxi(1, level) - 1) / LEVELS_PER_DEF


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


## Everything a fight needs, from learning XP plus the currently equipped gear.
static func from_xp(xp: int, gear_defs: Array[Dictionary] = []) -> Dictionary:
	var lv := level_from_xp(xp)
	var gear := gear_bonus(gear_defs, lv)
	return {
		"level": lv,
		"max_hp": maxi(1, max_hp(lv) + int(gear["hp"])),
		"atk": maxi(1, atk(lv) + int(gear["atk"])),
		"def": maxi(0, def(lv) + int(gear["def"])),
		"speed": int(gear["spd"]),
		"xp_into_level": xp_into_level(xp),
		"xp_per_level": XP_PER_LEVEL,
	}
