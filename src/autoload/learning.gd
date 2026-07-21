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

var profile: LearningProfile
var progression: LearningProgression


func _ready() -> void:
	reload()


## (Re)load the profile from disk and rebuild the progression facade. Called on
## boot and after a character/cloud swap.
func reload() -> void:
	profile = LearningProfile.new(SaveGame.load_profile(), DB)
	profile.saver = func(save_dict: Dictionary): SaveGame.save_profile(save_dict)
	progression = LearningProgression.new(profile, DB)
	progression.on_lesson_unlock = func(title: String):
		Bus.toast.emit("New lesson unlocked: %s" % title)


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
