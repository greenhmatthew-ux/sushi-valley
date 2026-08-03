extends SceneTree
## The returning-player card: what it chooses to say, and that it yields control.
##
##   godot --headless --path . --script res://tests/test_session_summary.gd
##
## The card exists so a player coming back after days sees what is actionable
## without rereading logs. These checks pin the selection rules (ready work
## first, capped to a glance, silent when nothing waits) and that the panel
## pauses the game, is keyboard/controller-reachable, and hands control back.

const Summary = preload("res://src/systems/session_summary.gd")
const Journal = preload("res://src/systems/quest_journal.gd")

var failures: int = 0


func _quest(title: String, stage: int, progress: int = 0, goal: int = 0) -> Dictionary:
	return {"title": title, "giver": "Mako", "stage": stage,
		"progress": progress, "goal": goal}


func _initialize() -> void:
	_selection_rules()
	await _panel_behavior()
	_finish()


func _selection_rules() -> void:
	var quiet := Summary.build([], 0, 0, 0)
	check_true("nothing waiting means no card", not quiet["show"])
	check_eq("a quiet save produces no lines", quiet["lines"].size(), 0)

	var done_only := Summary.build(
		[_quest("Old Errand", Journal.Stage.DONE), _quest("Hidden", Journal.Stage.UNMET)],
		0, 0, 0)
	check_true("finished and unmet quests alone do not reopen the card",
		not done_only["show"])

	var model := Summary.build([
		_quest("Stock the Stall", Journal.Stage.READY),
		_quest("River Guard", Journal.Stage.ACTIVE, 1, 2),
	], 4, 2, 1)
	check_true("actionable state shows the card", model["show"])
	check_eq("ready work leads, then progress, reviews, points",
		model["lines"].map(func(l): return l["kind"]),
		["ready", "active", "review", "points"])
	check_true("a ready line names the quest and who pays out",
		String(model["lines"][0]["text"]).contains("Stock the Stall")
		and String(model["lines"][0]["text"]).contains("Mako"))
	check_true("an active line carries real progress",
		String(model["lines"][1]["text"]).contains("1/2"))
	check_true("both point pools share one line",
		String(model["lines"][3]["text"]).contains("2 Talent")
		and String(model["lines"][3]["text"]).contains("1 Attribute"))

	var crowded_entries: Array = []
	for i in 4:
		crowded_entries.append(_quest("Ready %d" % i, Journal.Stage.READY))
	crowded_entries.append(_quest("Busy", Journal.Stage.ACTIVE, 0, 3))
	var crowded := Summary.build(crowded_entries, 0, 0, 0)
	var kinds: Array = crowded["lines"].map(func(l): return l["kind"])
	check_eq("quest lines stay a glance: three plus an overflow count",
		kinds, ["ready", "ready", "ready", "more"])
	check_true("the overflow line counts everything it hid",
		String(crowded["lines"][3]["text"]).contains("2 more"))


func _panel_behavior() -> void:
	await process_frame
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/welcome_back_panel.gd"))
	root.add_child(panel)
	await process_frame

	# A --script harness has no current_scene, so auto-show must decline no matter
	# what saves earlier suites left behind. This is what keeps every other scene
	# test (smoke_world, crafting, quest givers, ...) free of surprise pauses.
	check_true("embedded outside a real launch, the card never auto-opens", not paused)

	panel.call("_show_model", Summary.build(
		[_quest("Stock the Stall", Journal.Stage.READY)], 3, 0, 0))
	await process_frame
	check_true("the card pauses the world while it is up", paused)
	var button: Button = panel.find_child("ContinueButton", true, false)
	check_true("one Continue action exists", button != null)
	if button != null:
		check_true("Continue is reachable by keyboard and controller",
			button.focus_mode == Control.FOCUS_ALL and button.has_focus())
		button.pressed.emit()
		await process_frame
		check_true("Continue hands control back", not paused)

	panel.queue_free()
	await process_frame


func _finish() -> void:
	print("")
	print(("PASS — the returning-player card says what waits and yields control."
		if failures == 0 else "FAIL — %d session summary check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
