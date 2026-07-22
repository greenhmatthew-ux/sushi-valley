extends SceneTree
## Transitions slice: the pending-spawn hand-off between levels.
##
##   godot --headless --path . --script res://tests/test_transitions.gd
##
## Instantiates the Transitions autoload script directly (no scene change, no tree
## reliance) and asserts the arrival point round-trips exactly once.

var failures: int = 0


func _initialize() -> void:
	var t: Node = load("res://src/autoload/transitions.gd").new()

	check_true("fresh instance has no pending spawn", not t.has_pending_spawn())
	check_eq("fresh take returns empty", t.take_pending_spawn(), "")

	t.set_pending_spawn("interior_entry")
	check_true("pending is set", t.has_pending_spawn())
	check_eq("take returns the pending spawn", t.take_pending_spawn(), "interior_entry")
	check_true("take cleared the slot", not t.has_pending_spawn())
	check_eq("second take is empty (no stale reuse)", t.take_pending_spawn(), "")

	# A later door overwrites an unconsumed spawn rather than stacking.
	t.set_pending_spawn("house_door")
	t.set_pending_spawn("shop_door")
	check_eq("latest spawn wins", t.take_pending_spawn(), "shop_door")

	# The return spawn defaults empty (set only when entering a sub-location).
	check_eq("fresh return spawn is empty", t.peek_return_spawn(), "")

	t.free()
	_finish()


func _finish() -> void:
	print("")
	print(("PASS — level transitions carry the arrival spawn exactly once."
		if failures == 0 else "FAIL — %d transition check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
