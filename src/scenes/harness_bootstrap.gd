extends Node
## Minimal gameplay bootstrap for the test harness.
##
## Ensures the starter lesson is available so the recall gate is actually
## studyable when hand-testing. In the real game a teacher NPC unlocks lessons
## (Slice 6); this is a stand-in for that, not level content. Idempotent —
## unlocking an already-unlocked lesson is a no-op.

@export var starter_lesson: String = "kana-vowels"


func _ready() -> void:
	if not starter_lesson.is_empty():
		Learning.profile.unlock_lesson(starter_lesson)
		Learning.profile.save()
