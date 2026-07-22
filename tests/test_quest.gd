extends SceneTree
## Quest slice: the pure "clear N enemies" state machine.
##
##   godot --headless --path . --script res://tests/test_quest.gd

var failures: int = 0
var QL = load("res://src/systems/quest_logic.gd")


func _initialize() -> void:
	# started, done, kills, target -> stage
	check_eq("never accepted -> intro", QL.stage(false, false, 0, 3), "intro")
	check_eq("accepted, no kills -> active", QL.stage(true, false, 0, 3), "active")
	check_eq("accepted, partial -> active", QL.stage(true, false, 2, 3), "active")
	check_eq("accepted, goal met -> turnin", QL.stage(true, false, 3, 3), "turnin")
	check_eq("accepted, over goal -> turnin", QL.stage(true, false, 5, 3), "turnin")
	check_eq("turned in -> done", QL.stage(true, true, 5, 3), "done")
	check_eq("done wins even before goal", QL.stage(true, true, 0, 3), "done")

	check_eq("remaining counts down", QL.remaining(1, 3), 2)
	check_eq("remaining never negative", QL.remaining(5, 3), 0)

	_finish()


func _finish() -> void:
	print("")
	print(("PASS — quest state machine resolves each stage."
		if failures == 0 else "FAIL — %d quest check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + "%s (got %s, want %s)" % [label, got, want])
	if not ok:
		failures += 1
