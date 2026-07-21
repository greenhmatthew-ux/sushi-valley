class_name LessonGateLogic
extends RefCounted
## The educational core: a gate stays closed until the player's SRS progress on a
## required lesson meets a threshold. Pure evaluation + flag helpers, ported from
## src/game/systems/LessonGate.ts (the async, UI-driven orchestration lives in the
## lesson_gate entity node; this stays headless-testable).
##
## Gates reward real study, never fake completion — so "satisfied" means every
## card in the lesson is unlocked AND has been answered correctly at least
## `required_level` times (correctCount as an SRS-level proxy).

enum Reason { OK, UNKNOWN_LESSON, LOCKED, NEEDS_PRACTICE }


## Evaluate a gate against the player's profile.
## Returns { satisfied: bool, reason: Reason, total: int, ready: int }.
static func evaluate(profile: LearningProfile, content, lesson_id: String,
		required_level: int = 1) -> Dictionary:
	var lesson: Dictionary = content.lesson(lesson_id)
	var card_ids: Array = lesson.get("cardIds", [])
	if lesson.is_empty() or card_ids.is_empty():
		return {"satisfied": false, "reason": Reason.UNKNOWN_LESSON, "total": 0, "ready": 0}

	var ready := 0
	var any_locked := false
	for id in card_ids:
		var card: Dictionary = profile.card(id)
		if card.is_empty() or not card.get("unlocked", false):
			any_locked = true
			continue
		if int(card.get("correctCount", 0)) >= required_level:
			ready += 1

	var total: int = card_ids.size()
	var satisfied := ready >= total
	var reason: Reason
	if satisfied:
		reason = Reason.OK
	elif any_locked:
		reason = Reason.LOCKED
	else:
		reason = Reason.NEEDS_PRACTICE
	return {"satisfied": satisfied, "reason": reason, "total": total, "ready": ready}


## The flag key a gate sets once its recall requirement has been met. Keyed by the
## gate's authored id so two gates never share a cleared flag.
static func cleared_flag(gate_id: String) -> String:
	return "gate_%s_cleared" % (gate_id if not gate_id.is_empty() else "gate")


static func is_cleared(profile: LearningProfile, gate_id: String) -> bool:
	return profile.get_flag(cleared_flag(gate_id))


## Human-readable detail line for a not-yet-satisfied gate, matching the TS copy.
static func detail_text(eval: Dictionary, lesson_id: String, required_level: int) -> String:
	match eval["reason"]:
		Reason.UNKNOWN_LESSON:
			return "Lesson \"%s\" has no cards yet." % lesson_id
		Reason.LOCKED:
			return "This lesson has not been unlocked yet — find whoever teaches it first."
		_:
			return "Recall progress: %d/%d ready (need level %d)." % [eval["ready"], eval["total"], required_level]
