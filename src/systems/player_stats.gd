class_name PlayerStats
extends RefCounted
## Player level and combat stats, derived from learning XP. Pure and node-free.
##
## COMBAT_DESIGN.md: "Player stats derive from learning XP level, vitality/power/agility
## allocation, and equipped gear." Only the level half exists here — there is no allocation or
## gear system yet — but the important part is the direction of causality: studying Japanese is
## what makes you stronger. Nothing else in the game grants XP.
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


## Everything a fight needs, from one XP total.
static func from_xp(xp: int) -> Dictionary:
	var lv := level_from_xp(xp)
	return {
		"level": lv,
		"max_hp": max_hp(lv),
		"atk": atk(lv),
		"def": def(lv),
		"xp_into_level": xp_into_level(xp),
		"xp_per_level": XP_PER_LEVEL,
	}
