extends SceneTree
## The notebook's recall panel, and specifically its listening rounds.
##
##   godot --headless --path . --script res://tests/test_recall_panel.gd
##
## Reading a word and catching it spoken are different skills, and the game only
## ever trained the first: every prompt showed the written form. Now that almost
## every card carries a native recording, a card that has already been answered
## correctly is sometimes asked by ear instead, with the writing withheld until
## the answer is in.
##
## The ordering rule is the part worth protecting: a word must never be asked by
## ear before it has been seen, or the player is guessing at a shape they have
## never been shown.

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var audio: Node = root.get_node("Audio")

	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/recall_panel.gd"))
	root.add_child(panel)
	await process_frame

	# A lesson whose cards all shipped with audio, so listening is possible at all.
	learning.profile.unlock_lesson("travel-vocab-1")
	var lesson_cards: Array = db.lesson("travel-vocab-1")["cardIds"]
	check_true("the listening fixture lesson has cards", not lesson_cards.is_empty())
	var voiced := 0
	for cid in lesson_cards:
		if bool(audio.call("has_pronunciation", String(cid))):
			voiced += 1
	check_eq("every fixture card can actually be heard", voiced, lesson_cards.size())

	# Start from a known slate. Grading below writes through to the saved profile,
	# so without this the "not yet seen" case passes once and then never again.
	for cid in lesson_cards:
		var fresh: Dictionary = learning.profile.card(String(cid))
		if not fresh.is_empty():
			fresh["correctCount"] = 0

	# Force the coin flip: seed the panel's RNG so the listening branch is taken.
	panel.set("_rng", _rng_that_rolls_below(0.35))

	# A brand-new card must still be shown, never asked by ear first.
	bus.learn_open.emit("travel-vocab-1", 1, true)
	await process_frame
	var question: Label = panel.get("_question")
	var current: Dictionary = panel.get("_current")
	var new_card: Dictionary = current.get("card", {})
	check_eq("an unseen card is never asked by ear",
		question.text, String(current.get("question", "")))
	check_true("an unseen card is shown its written form",
		not bool(panel.get("_listening")))

	# Close the open session: the panel refuses a second one while it is running.
	var open_choices: GridContainer = panel.get("_choices_box")
	(open_choices.get_child(0) as Button).pressed.emit()
	await process_frame
	(panel.get("_continue_btn") as Button).pressed.emit()
	await process_frame
	check_true("the first session closed", not bool(panel.get("_active")))

	# Answer every card correctly once, so they all count as seen.
	for cid in lesson_cards:
		var card: Dictionary = learning.profile.card(String(cid))
		if not card.is_empty():
			learning.progression.grade(card, "good")

	# Now the same draw should arrive by ear.
	panel.set("_rng", _rng_that_rolls_below(0.35))
	bus.learn_open.emit("travel-vocab-1", 1, true)
	await process_frame
	current = panel.get("_current")
	var heard: Dictionary = current.get("card", {})
	check_true("a seen, voiced card can be asked by ear", bool(panel.get("_listening")))
	check_true("a listening round withholds the written form",
		question.text != String(heard.get("prompt", "")))
	check_eq("a listening round says what is being asked", question.text, "Listen")
	check_true("a listening round tells the player what to do",
		not (panel.get("_hint") as Label).text.is_empty())
	check_true("a listening round offers the recording",
		(panel.get("_listen_btn") as Button).visible)
	check_true("the recording is actually playing",
		(audio.get("_player") as AudioStreamPlayer).stream != null)

	# The choices must still be answerable, and answering reveals the writing.
	var choices: GridContainer = panel.get("_choices_box")
	check_true("a listening round still offers choices", choices.get_child_count() > 1)
	var pressed: Button = choices.get_child(0) as Button
	pressed.pressed.emit()
	await process_frame
	check_eq("answering reveals the word that was played",
		question.text, String(heard.get("prompt", "")))
	check_true("the reveal explains the answer",
		not (panel.get("_feedback") as Label).text.is_empty())

	panel.queue_free()
	await process_frame
	_finish()


## An RNG whose next randf() lands under `ceiling`, so the listening branch is a
## decision the test makes rather than one it waits for.
func _rng_that_rolls_below(ceiling: float) -> RandomNumberGenerator:
	for seed_value in 500:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randf() < ceiling:
			return rng
	push_error("no seed produced a roll below %f" % ceiling)
	return RandomNumberGenerator.new()


func _finish() -> void:
	print("")
	print(("PASS — recall asks by ear only after the word has been seen."
		if failures == 0 else "FAIL — %d recall-panel check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
