extends SceneTree
## The notebook: what the player knows, and being able to hear it.
##
##   godot --headless --path . --script res://tests/test_notebook_panel.gd
##
## The notebook is the one screen that lists everything the player has learned,
## and every one of those words has a native recording that it never offered.
## This pins that a learned, voiced word is playable from the list — and that the
## control is reachable by keyboard and controller, not mouse-only.

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var audio: Node = root.get_node("Audio")

	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/notebook_panel.gd"))
	root.add_child(panel)
	await process_frame

	learning.profile.unlock_lesson("travel-vocab-1")
	panel.call("_set_open", true)
	await process_frame

	var summary: Label = panel.get("_summary")
	check_true("the notebook reports what has been learned",
		summary != null and summary.text.contains("words learned"))

	var lesson_cards: Array = db.lesson("travel-vocab-1")["cardIds"]
	var voiced_id := ""
	for cid in lesson_cards:
		if bool(audio.call("has_pronunciation", String(cid))):
			voiced_id = String(cid)
			break
	check_true("a learned word with a recording exists", not voiced_id.is_empty())

	var play: Button = panel.find_child("Play_" + voiced_id, true, false)
	check_true("a learned, voiced word can be played from the notebook", play != null)
	if play != null:
		check_true("the play control is reachable by keyboard and controller",
			play.focus_mode == Control.FOCUS_ALL)
		play.pressed.emit()
		await process_frame
		check_true("pressing it actually plays the recording",
			(audio.get("_player") as AudioStreamPlayer).stream != null)

	# A word with no recording must not offer a dead button.
	var silent_id := ""
	for cid in db.card_order:
		if not bool(audio.call("has_pronunciation", String(cid))):
			silent_id = String(cid)
			break
	if not silent_id.is_empty():
		check_true("a word with no recording offers no play control",
			panel.find_child("Play_" + silent_id, true, false) == null)

	panel.call("_set_open", false)
	panel.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("")
	print(("PASS — the notebook lists what is known and can speak it."
		if failures == 0 else "FAIL — %d notebook check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
