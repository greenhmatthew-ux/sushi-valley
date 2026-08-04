extends SceneTree
## The returning-player card prioritizes the saved selection, includes structured
## missions, stays glance-sized, and yields control.

const Summary = preload("res://src/systems/session_summary.gd")

var failures := 0


func _activity(key: String, kind: String, text: String, priority: int,
		trackable: bool = true) -> Dictionary:
	return {"key": key, "summary_kind": kind, "summary_text": text,
		"priority": priority, "trackable": trackable}


func _initialize() -> void:
	_selection_rules()
	await _panel_behavior()
	_finish()


func _selection_rules() -> void:
	var quiet := Summary.build([], 0, 0, 0)
	check_true("nothing waiting means no card", not quiet["show"])
	check_eq("a quiet save produces no lines", quiet["lines"].size(), 0)

	var done_only := Summary.build([
		_activity("quest:old", "active", "Old Errand", 2, false),
	], 0, 0, 0)
	check_true("completed activities alone do not reopen the card",
		not done_only["show"])

	var model := Summary.build([
		_activity("quest:stock", "ready", "Ready to turn in: Stock the Stall — see Mako", 0),
		_activity("quest:river", "active", "In progress: River Guard — 1/2", 2),
	], 4, 2, 1)
	check_true("actionable state shows the card", model["show"])
	check_eq("ready work leads, then progress, reviews, points",
		model["lines"].map(func(line): return line["kind"]),
		["ready", "active", "review", "points"])
	check_true("a ready line names the quest and who pays out",
		String(model["lines"][0]["text"]).contains("Stock the Stall")
		and String(model["lines"][0]["text"]).contains("Mako"))
	check_true("an active line carries real progress",
		String(model["lines"][1]["text"]).contains("1/2"))
	check_true("both point pools share one line",
		String(model["lines"][3]["text"]).contains("2 Talent")
		and String(model["lines"][3]["text"]).contains("1 Attribute"))

	var mixed := Summary.build([
		_activity("raid:sushi", "mission", "Raid: Sushi Prep — Defeat Pantry Oni", 0),
		_activity("quest:river", "active", "In progress: River Guard — 1/2", 2),
	], 0, 0, 0, "quest:river")
	check_eq("the saved selection leads even when a boss has automatic priority",
		mixed["lines"].map(func(line): return line["kind"]), ["active", "mission"])
	check_true("structured missions appear in the returning-player card",
		String(mixed["lines"][1]["text"]).contains("Pantry Oni"))

	var crowded_entries: Array = []
	for i in 5:
		crowded_entries.append(_activity(
			"quest:%d" % i, "ready", "Ready %d" % i, 0))
	var crowded := Summary.build(crowded_entries, 0, 0, 0)
	var kinds: Array = crowded["lines"].map(func(line): return line["kind"])
	check_eq("activity lines stay a glance: three plus an overflow count",
		kinds, ["ready", "ready", "ready", "more"])
	check_true("the overflow line counts everything it hid",
		String(crowded["lines"][3]["text"]).contains("2 more"))


func _panel_behavior() -> void:
	await process_frame
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/welcome_back_panel.gd"))
	root.add_child(panel)
	await process_frame

	check_true("embedded outside a real launch, the card never auto-opens", not paused)
	panel.call("_show_model", Summary.build([
		_activity("quest:stock", "ready", "Ready to turn in: Stock the Stall", 0),
	], 3, 0, 0))
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
	print(("PASS — the returning-player card unifies activities and yields control."
		if failures == 0 else "FAIL — %d session-summary check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
