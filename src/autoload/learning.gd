extends Node
## In-game entry point to the learning core. Replaces the `learning()` singleton
## from LearningProgressionSystem.ts.
##
## Owns the one shared LearningProfile + LearningProgression for the whole game,
## wires persistence to SaveGame, and forwards lesson-unlock notices to the Bus as
## a toast. Systems and scenes call `Learning.progression` and `Learning.profile`.
##
## The heavy lifting lives in the pure RefCounted classes (LearningProfile,
## LearningProgression, Srs) so it stays headless-testable; this node is only the
## glue that binds them to DB, SaveGame, and Bus.

const AbilityRules = preload("res://src/systems/ability_logic.gd")

var profile: LearningProfile
var progression: LearningProgression


func _ready() -> void:
	reload()
	# Bus-driven per the project's own rule: combat owns no reference back here, it
	# only announces. Both the overworld spar win (enemy.gd) and the recall-combat
	# win (combat_panel.gd) emit enemy_died, and combat_started fires from either
	# path the instant a fight opens — so a single pair of listeners here covers
	# both the "was this ever fought" and "was this ever beaten" questions.
	Bus.combat_started.connect(_on_combat_started)
	Bus.enemy_died.connect(_on_enemy_died)


func _on_combat_started(enemy_id: String) -> void:
	if profile != null:
		profile.record_enemy_seen(enemy_id)
		profile.save()


func _on_enemy_died(enemy_id: String) -> void:
	if profile != null:
		profile.record_enemy_defeated(enemy_id)
		profile.save()


## (Re)load the profile from disk and rebuild the progression facade. Called on
## boot and after a character/cloud swap.
func reload() -> void:
	profile = LearningProfile.new(SaveGame.load_profile(), DB)
	profile.saver = func(save_dict: Dictionary): SaveGame.save_profile(save_dict)
	progression = LearningProgression.new(profile, DB)
	progression.on_lesson_unlock = func(title: String):
		Bus.toast.emit("New lesson unlocked: %s" % title)
	# XP is what drives player level and therefore combat stats, so it has to be announced.
	progression.on_xp_changed = func(amount: int, total: int):
		Bus.xp_gained.emit(amount)
		var lv := PlayerStats.level_from_xp(total)
		if lv > PlayerStats.level_from_xp(total - amount):
			Bus.level_up.emit(lv)
			Bus.toast.emit("Level %d — you feel steadier." % lv)


# --- convenience pass-throughs the game calls constantly ---

func build_prompt(card: Dictionary = {}, allow_practice: bool = false,
		focus_lesson: String = "", focus_category: String = "") -> Dictionary:
	return progression.build_prompt(card, allow_practice, focus_lesson, focus_category)


func answer(card: Dictionary, chosen: String) -> bool:
	return progression.answer(card, chosen)


func due_count() -> int:
	return progression.due_count()


func get_flag(flag: String) -> bool:
	return profile.get_flag(flag)


func set_flag(flag: String, value: bool = true) -> void:
	profile.set_flag(flag, value)
	profile.save()
	Bus.flag_set.emit(flag, value)


# --- combat abilities ------------------------------------------------------

func equipped_ability_ids() -> Array:
	return profile.build().get("skills", []).duplicate()


func known_ability_defs() -> Array[Dictionary]:
	return AbilityRules.known_defs(profile.build(), DB.abilities, DB.ability_order)


func known_ability_defs_by_role() -> Array[Dictionary]:
	return AbilityRules.known_defs_by_role(profile.build(), DB.abilities, DB.ability_order)


func usable_ability_defs(weapon_type: String) -> Array[Dictionary]:
	return AbilityRules.usable_defs(profile.build(), DB.abilities, weapon_type)


func set_ability_equipped(ability_id: String, equipped: bool, weapon_type: String) -> bool:
	var build := profile.build()
	if not AbilityRules.set_equipped(build, ability_id, equipped, DB.abilities, weapon_type):
		return false
	profile.save()
	Bus.ability_loadout_changed.emit()
	return true


func unspent_talent_points() -> int:
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	var level := PlayerStats.level_from_xp(xp)
	return AbilityRules.unspent_talent_points(level, profile.build(), DB.abilities)


func next_talent_defs() -> Array[Dictionary]:
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	var level := PlayerStats.level_from_xp(xp)
	return AbilityRules.next_talent_defs(
		level, profile.build(), DB.abilities, DB.ability_order)


func can_unlock_talent(ability_id: String) -> bool:
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	var level := PlayerStats.level_from_xp(xp)
	return AbilityRules.can_unlock_talent(
		DB.ability(ability_id), level, profile.build(), DB.abilities)


func unlock_talent(ability_id: String) -> bool:
	var build := profile.build()
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	var level := PlayerStats.level_from_xp(xp)
	if not AbilityRules.unlock_talent(ability_id, level, build, DB.abilities):
		return false
	profile.save()
	Bus.ability_loadout_changed.emit()
	return true


# --- combat attributes ----------------------------------------------------

func allocations() -> Dictionary:
	return PlayerStats.normalized_allocations(profile.build().get("allocations", {}))


func unspent_attribute_points() -> int:
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	return PlayerStats.unspent_attribute_points(xp, profile.build().get("allocations", {}))


func adjust_allocation(attribute: String, delta: int) -> bool:
	var build := profile.build()
	var allocation_data: Dictionary = build.get("allocations", {})
	var xp := int(profile.data.get("stats", {}).get("xp", 0))
	if not PlayerStats.adjust_allocation(allocation_data, attribute, delta, xp):
		return false
	build["allocations"] = allocation_data
	profile.save()
	Bus.player_build_changed.emit()
	return true
