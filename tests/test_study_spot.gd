extends SceneTree
## Study spots: clear a real backlog, and decline politely when there is none.
##
##   godot --headless --path . --script res://tests/test_study_spot.gd
##
## Two rules matter, and both are the kind that fail silently:
##
##   1. A spot reviews only what is genuinely DUE. If it allowed the practice fallback it
##      would manufacture an endless queue, turning a convenience you walk past into a chore
##      you are obliged to visit — and the learning docs are explicit that reviews are never
##      a wall.
##   2. It never asks for more cards than are actually due, so a 5-card bench with 2 due
##      words does not pad the session out with repeats.

var failures: int = 0
var spot: Node
var bus: Node
var learning: Node
var db: Node
var save_game: Node

var learn_opens: Array = []   # (lesson, size, allow_practice) triples the spot requested


func _initialize() -> void:
	await process_frame
	bus = root.get_node("Bus")
	learning = root.get_node("Learning")
	db = root.get_node("DB")
	save_game = root.get_node("SaveGame")

	bus.dialogue_open.connect(func(_s, _l): bus.dialogue_closed.emit.call_deferred())
	bus.learn_open.connect(_fake_recall)

	spot = load("res://src/entities/study_spot.tscn").instantiate()
	spot.spot_id = "test_bench"
	spot.session_size = 5
	root.add_child(spot)
	await process_frame

	save_game.clear()
	learning.reload()

	await _nothing_due_declines()
	await _reviews_only_what_is_due()
	await _never_asks_for_more_than_is_due()

	save_game.clear()
	_finish()


## A fresh profile has nothing unlocked, so nothing can be due. The spot must not open a
## session at all.
func _nothing_due_declines() -> void:
	check_eq("fresh profile has nothing due", learning.due_count(), 0)
	learn_opens.clear()
	await spot.interact(null)
	check_eq("no session opened when nothing is due", learn_opens.size(), 0)


func _reviews_only_what_is_due() -> void:
	learning.profile.unlock_lesson("greetings")
	# Unlocked-but-never-reviewed cards read as due, which is what we want to clear.
	check_true("unlocked cards are due", learning.due_count() > 0)

	learn_opens.clear()
	await spot.interact(null)
	check_eq("a session opened", learn_opens.size(), 1)
	if learn_opens.size() == 1:
		check_eq("no focus lesson — it reviews everything you know", learn_opens[0][0], "")
		check_true("practice fallback is OFF, so it cannot invent a queue", not bool(learn_opens[0][2]))


## Drain to a known small backlog and confirm the request is clamped to it.
func _never_asks_for_more_than_is_due() -> void:
	# Push everything far into the future, then bring exactly two cards back.
	# NOTE: Srs stores dueAt in MILLISECONDS since epoch (Time.get_unix_time_from_system()
	# * 1000), so "far future" is ~1e15, not ~1e11 — 9e11 ms is 1998 and reads as overdue.
	for c in learning.profile.all_cards():
		c["dueAt"] = 9e15
	var ids: Array = db.lesson("greetings")["cardIds"]
	for i in 2:
		learning.profile.card(String(ids[i]))["dueAt"] = 0.0
	learning.profile.save()
	check_eq("exactly two words are due", learning.due_count(), 2)

	learn_opens.clear()
	await spot.interact(null)
	check_eq("a session opened", learn_opens.size(), 1)
	if learn_opens.size() == 1:
		check_eq("and it asked for only the 2 due, not its full size of 5", learn_opens[0][1], 2)


func _fake_recall(lesson: String, size: int, practice: bool) -> void:
	learn_opens.append([lesson, size, practice])
	var attempted := 0
	var correct := 0
	for i in size:
		var p: Dictionary = learning.build_prompt({}, practice, lesson)
		if p.is_empty():
			break
		attempted += 1
		if learning.answer(p["card"], String(p["answer"])):
			correct += 1
	bus.learn_closed.emit.call_deferred(attempted, correct, false)


func _finish() -> void:
	print("")
	print(("PASS — study spots clear real backlogs and never manufacture practice."
		if failures == 0 else "FAIL — %d study-spot check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + label + ("" if ok else "  (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1
