extends SceneTree
## The teaching-NPC loop: first meeting unlocks + reviews, return visits only review
## what the shared SRS actually says is due.
##
##   godot --headless --path . --script res://tests/test_teacher_npc.gd
##
## Runs the real node against fake UI: stand-ins answer the dialogue/recall Bus
## round-trips the way DialogueBox and RecallPanel would, so the whole async
## interaction is exercised without a viewport. Autoloads are live here (the node
## calls Learning/DB/Speech directly), so this doubles as a wiring check.
##
## Autoloads are fetched via root.get_node() rather than their global names: this
## entry script is parsed before the autoloads register, so naming them directly
## is a compile error (the same reason smoke_autoloads.gd does it this way).

var failures: int = 0
var teacher: Node
var learn_opens: Array = []      # every (lesson, size, practice) the teacher requested

var bus: Node
var db: Node
var learning: Node
var save_game: Node


func _initialize() -> void:
	await process_frame   # let autoloads finish _ready

	bus = root.get_node("Bus")
	db = root.get_node("DB")
	learning = root.get_node("Learning")
	save_game = root.get_node("SaveGame")

	# Fake the two UI surfaces the teacher talks to.
	bus.dialogue_open.connect(func(_speaker, _lines): bus.dialogue_closed.emit.call_deferred())
	bus.learn_open.connect(_fake_recall)

	teacher = load("res://src/entities/teacher_npc.tscn").instantiate()
	teacher.npc_id = "test_hana"
	teacher.speaker = "Hana"
	teacher.teaches_lesson = "greetings"
	teacher.session_size = 3
	root.add_child(teacher)
	await process_frame

	# Clean slate: this profile must not carry a met-flag or unlocked greetings.
	save_game.clear()
	learning.reload()

	await _first_meeting_unlocks_and_reviews()
	await _return_visit_finishes_the_remaining_cards()
	await _return_visit_with_nothing_due_does_not_review()
	await _return_visit_reviews_when_due_again()
	await _category_teacher_walks_the_ladder()

	save_game.clear()
	_finish()


## A category teacher carries a whole ladder: it works on the first unfinished lesson in its
## category and advances once that rung is done, so one NPC covers ten lessons.
func _category_teacher_walks_the_ladder() -> void:
	save_game.clear()
	learning.reload()

	var sensei: Node = load("res://src/entities/teacher_npc.tscn").instantiate()
	sensei.npc_id = "test_sensei"
	sensei.speaker = "Sensei"
	sensei.teaches_category = "kana-hiragana"
	sensei.session_size = 5
	root.add_child(sensei)
	await process_frame

	var first: String = sensei.current_lesson()
	check_true("category teacher starts on a real lesson", not first.is_empty())
	check_eq("and it is the first rung of the ladder", first, "kana-vowels")

	# Finish that rung the way play would: talk until every card is answered once.
	for i in 6:
		if sensei.current_lesson() != first:
			break
		await sensei.interact(null)

	check_true("teacher advances off a finished rung", sensei.current_lesson() != first)
	check_true("and the next rung is still in the same category",
		String(db.lesson(sensei.current_lesson()).get("category", "")) == "kana-hiragana")
	# The met-flag is per-lesson, so the new rung gets its own introduction.
	check_true("the finished rung is the one marked taught", learning.get_flag(sensei.taught_flag(first)))
	check_true("the new rung is NOT pre-marked, so it gets its own introduction",
		not learning.get_flag(sensei.taught_flag(sensei.current_lesson())))
	sensei.queue_free()


func _first_meeting_unlocks_and_reviews() -> void:
	check_true("greetings starts locked", not _lesson_unlocked("greetings"))
	check_true("taught flag starts clear", not learning.get_flag(teacher.taught_flag("greetings")))

	learn_opens.clear()
	await teacher.interact(null)

	check_true("first meeting unlocks the lesson", _lesson_unlocked("greetings"))
	check_true("first meeting sets the taught flag for THAT lesson", learning.get_flag(teacher.taught_flag("greetings")))
	check_eq("first meeting runs exactly one session", learn_opens.size(), 1)
	if learn_opens.size() == 1:
		check_eq("session targets this teacher's lesson", learn_opens[0][0], "greetings")
		check_eq("session is a micro-review", learn_opens[0][1], 3)


## A micro-review is deliberately smaller than the lesson (3 of greetings' 5 cards), so
## some cards are still unseen afterwards. Coming back should finish them — this is the
## "several encounters with a small card set" loop, not a bug.
func _return_visit_finishes_the_remaining_cards() -> void:
	check_true("cards remain due after one micro-review", _due_in("greetings") > 0)
	learn_opens.clear()
	await teacher.interact(null)
	check_eq("return visit reviews the leftovers", learn_opens.size(), 1)


## Once every card has been answered correctly the SRS schedules them into the future.
## A return visit should recognise that and NOT open a review — never a forced wall.
func _return_visit_with_nothing_due_does_not_review() -> void:
	# Drain anything still due so the whole lesson is genuinely scheduled forward.
	while _due_in("greetings") > 0:
		await teacher.interact(null)
	check_eq("nothing due once the lesson is drained", _due_in("greetings"), 0)

	learn_opens.clear()
	await teacher.interact(null)
	check_eq("no review opened when nothing is due", learn_opens.size(), 0)


## Force the schedule back into the past; now the same visit should review again.
func _return_visit_reviews_when_due_again() -> void:
	for id in db.lesson("greetings")["cardIds"]:
		learning.profile.card(id)["dueAt"] = 0.0
	learning.profile.save()
	check_true("cards are due again", _due_in("greetings") > 0)

	learn_opens.clear()
	await teacher.interact(null)
	check_eq("return visit reviews when cards are due", learn_opens.size(), 1)


# --- fakes ------------------------------------------------------------------

## Stand in for RecallPanel: record the request, answer every card, then report back
## the way the real panel does via learn_closed(attempted, correct, cancelled).
func _fake_recall(lesson: String, size: int, practice: bool) -> void:
	learn_opens.append([lesson, size, practice])
	var attempted := 0
	var correct := 0
	for i in size:
		var prompt: Dictionary = learning.build_prompt({}, practice, lesson)
		if prompt.is_empty():
			break
		attempted += 1
		if learning.answer(prompt["card"], String(prompt["answer"])):
			correct += 1
	bus.learn_closed.emit.call_deferred(attempted, correct, false)


# --- helpers ----------------------------------------------------------------

func _lesson_unlocked(lesson_id: String) -> bool:
	for id in db.lesson(lesson_id).get("cardIds", []):
		var c: Dictionary = learning.profile.card(id)
		if c.is_empty() or not c.get("unlocked", false):
			return false
	return true


func _due_in(lesson_id: String) -> int:
	var pool: Array = []
	for id in db.lesson(lesson_id).get("cardIds", []):
		var c: Dictionary = learning.profile.card(id)
		if not c.is_empty() and c.get("unlocked", false):
			pool.append(c)
	return Srs.due(pool).size()


func _finish() -> void:
	print("")
	print(("PASS — teaching NPCs unlock, review, and respect the shared SRS schedule."
		if failures == 0 else "FAIL — %d teacher check(s) failed." % failures))
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
