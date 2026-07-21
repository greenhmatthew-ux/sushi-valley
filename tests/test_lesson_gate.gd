extends SceneTree
## Slice 3: the pure LessonGate evaluation logic.
##
##   godot --headless --path . --script res://tests/test_lesson_gate.gd
##
## The async, UI-driven recall loop is covered by the in-scene loop test; this
## pins the pure decision: locked vs. needs-practice vs. satisfied, and the
## required-level threshold.

var failures: int = 0
var db: Node


func _initialize() -> void:
	db = load("res://src/autoload/db.gd").new()
	db.load_all()

	_unknown_lesson()
	_locked_until_unlocked()
	_needs_practice_then_satisfied()
	_required_level_threshold()
	_flag_helpers()

	db.free()
	_finish()


func _unknown_lesson() -> void:
	var p := LearningProfile.new({}, db)
	var e := LessonGateLogic.evaluate(p, db, "no-such-lesson", 1)
	check_true("unknown lesson -> not satisfied", not e["satisfied"])
	check_eq("unknown lesson -> UNKNOWN_LESSON", e["reason"], LessonGateLogic.Reason.UNKNOWN_LESSON)


func _locked_until_unlocked() -> void:
	var p := LearningProfile.new({}, db)
	# kana-vowels cards exist but start locked.
	var e := LessonGateLogic.evaluate(p, db, "kana-vowels", 1)
	check_true("locked lesson -> not satisfied", not e["satisfied"])
	check_eq("locked lesson -> LOCKED", e["reason"], LessonGateLogic.Reason.LOCKED)
	check_true("total reflects lesson size", e["total"] == db.lesson("kana-vowels")["cardIds"].size())
	check_eq("nothing ready while locked", e["ready"], 0)


func _needs_practice_then_satisfied() -> void:
	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)
	p.unlock_lesson("kana-vowels")

	# Unlocked but unpracticed: needs practice, not locked.
	var e := LessonGateLogic.evaluate(p, db, "kana-vowels", 1)
	check_true("unlocked+unpracticed -> not satisfied", not e["satisfied"])
	check_eq("unlocked+unpracticed -> NEEDS_PRACTICE", e["reason"], LessonGateLogic.Reason.NEEDS_PRACTICE)

	# Answer every card correctly once -> satisfied at level 1.
	for id in db.lesson("kana-vowels")["cardIds"]:
		prog.grade(p.card(id), "good")
	e = LessonGateLogic.evaluate(p, db, "kana-vowels", 1)
	check_true("all-practiced -> satisfied", e["satisfied"])
	check_eq("all-practiced -> OK", e["reason"], LessonGateLogic.Reason.OK)
	check_eq("ready == total when satisfied", e["ready"], e["total"])


func _required_level_threshold() -> void:
	var p := LearningProfile.new({}, db)
	var prog := LearningProgression.new(p, db)
	p.unlock_lesson("kana-vowels")
	var ids: Array = db.lesson("kana-vowels")["cardIds"]

	# One correct each: satisfies level 1 but not level 3.
	for id in ids:
		prog.grade(p.card(id), "good")
	check_true("1 correct satisfies level 1",
		LessonGateLogic.evaluate(p, db, "kana-vowels", 1)["satisfied"])
	check_true("1 correct does NOT satisfy level 3",
		not LessonGateLogic.evaluate(p, db, "kana-vowels", 3)["satisfied"])

	# Three correct each: now satisfies level 3.
	for id in ids:
		prog.grade(p.card(id), "good")
		prog.grade(p.card(id), "good")
	check_true("3 correct satisfies level 3",
		LessonGateLogic.evaluate(p, db, "kana-vowels", 3)["satisfied"])


func _flag_helpers() -> void:
	var p := LearningProfile.new({}, db)
	check_eq("clear-flag keying", LessonGateLogic.cleared_flag("north_path"), "gate_north_path_cleared")
	check_true("gate starts uncleared", not LessonGateLogic.is_cleared(p, "north_path"))
	p.set_flag(LessonGateLogic.cleared_flag("north_path"))
	check_true("gate reads cleared after flag set", LessonGateLogic.is_cleared(p, "north_path"))


func _finish() -> void:
	print("")
	print(("PASS — lesson gate evaluation is faithful."
		if failures == 0 else "FAIL — %d gate check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
