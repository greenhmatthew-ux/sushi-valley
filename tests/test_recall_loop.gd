extends SceneTree
## Slice 3: the full recall loop, headless. Drives a real LessonGate through a
## fake responder that stands in for the recall panel + dialogue box, so the async
## orchestration (dialogue -> recall sessions -> re-evaluate -> open + persist) is
## exercised without a human clicking buttons.
##
##   godot --headless --path . --script res://tests/test_recall_loop.gd
##
## This is the proof the port works: study at the gate -> the gate opens -> the
## clear is remembered across a reload. The fake responder answers deferred (a
## frame later) exactly as the real UI would, which also guards against the
## emit/await race where a synchronous reply is missed.
##
## Faithful nuance carried from LessonGate.ts: a gate does NOT teach. If its lesson
## is still locked it refuses and points you to a teacher, and never drops into
## recall (a session then could only surface unrelated cards). The lesson must be
## unlocked first — by a teacher NPC in-game (Slice 6); here, by hand.

var failures: int = 0
var _answer_correctly := true   # flipped to simulate a player who bails/fails

# Autoloads are fetched by node, not referenced as bare globals: a --script file
# is compiled at startup, before autoload name-globals (SaveGame/Bus/Learning)
# are registered, so bare references fail to compile. Class-names (LessonGateLogic,
# LearningProfile) are unaffected. Project scripts loaded later resolve globals fine.
var _save: Node
var _bus: Node
var _learning: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	_save = root.get_node("SaveGame")
	_bus = root.get_node("Bus")
	_learning = root.get_node("Learning")

	_bus.dialogue_open.connect(_fake_dialogue)
	_bus.learn_open.connect(_fake_recall)

	await _refuses_a_locked_lesson()
	await _clears_when_studied()
	await _reopens_from_saved_flag()
	await _cancel_leaves_gate_closed()

	_finish()


## A gate whose lesson is still locked refuses, and does not teach it.
func _refuses_a_locked_lesson() -> void:
	_reset()
	_answer_correctly = true   # willing to study, but the gate won't offer it

	var gate := _make_gate()
	root.add_child(gate)
	await process_frame
	await gate.interact()

	check_true("locked-lesson gate stays closed", not gate._open)
	check_true("locked-lesson gate sets no cleared flag",
		not LessonGateLogic.is_cleared(_learning.profile, "north_torii"))
	check_true("a gate never unlocks a locked lesson itself",
		not _learning.profile.card("kana-a").get("unlocked", false))
	gate.free()


## The headline: lesson taught (unlocked), studied at the gate, opens and persists.
func _clears_when_studied() -> void:
	_reset()
	_answer_correctly = true
	# Simulate the teacher NPC (Slice 6) having taught this lesson.
	_learning.profile.unlock_lesson("kana-vowels")

	var gate := _make_gate()
	root.add_child(gate)
	await process_frame

	var barrier: CollisionShape2D = gate.get_node("Barrier/Collision")
	check_true("gate starts closed (barrier active)", not barrier.disabled)

	# Walk up and interact. The fake responder answers every card correctly.
	await gate.interact()
	await process_frame   # let the deferred collision-disable flush

	check_true("gate opened after studying", gate._open)
	check_true("barrier collision lifted", barrier.disabled)
	check_true("cleared flag was saved",
		LessonGateLogic.is_cleared(_learning.profile, "north_torii"))
	check_true("recall actually recorded correct answers",
		int(_learning.profile.card("kana-a").get("correctCount", 0)) >= 1)
	check_true("clear survives a save+reload", _flag_survives_reload("north_torii"))

	gate.free()


## A gate cleared in a past session opens on load without any interaction.
func _reopens_from_saved_flag() -> void:
	_reset()
	_learning.profile.set_flag(LessonGateLogic.cleared_flag("north_torii"))
	_learning.profile.save()
	_learning.reload()   # prove it comes back from disk, not memory
	check_true("(precondition) flag persisted",
		LessonGateLogic.is_cleared(_learning.profile, "north_torii"))

	var gate := _make_gate()
	root.add_child(gate)
	await process_frame
	var barrier: CollisionShape2D = gate.get_node("Barrier/Collision")
	check_true("previously-cleared gate opens on load", gate._open)
	check_true("previously-cleared gate has no barrier", barrier.disabled)
	gate.free()


## Bailing out of recall (cancel) must NOT open the gate.
func _cancel_leaves_gate_closed() -> void:
	_reset()
	_learning.profile.unlock_lesson("kana-vowels")
	_answer_correctly = false   # responder cancels the first session

	var gate := _make_gate()
	root.add_child(gate)
	await process_frame
	await gate.interact()

	check_true("cancelled recall leaves the gate closed", not gate._open)
	check_true("cancelled recall does not set the cleared flag",
		not LessonGateLogic.is_cleared(_learning.profile, "north_torii"))
	gate.free()


# --- fake UI responders ----------------------------------------------------

## Stand-in for the dialogue box: dismiss on the next frame. Deferring is what the
## real UI does (it waits for a keypress) and it dodges the synchronous-reply race.
func _fake_dialogue(_speaker: String, _lines: Array) -> void:
	await process_frame
	_bus.dialogue_closed.emit()


## Stand-in for the recall panel. Answers up to `size` distinct cards from the
## focus lesson — correctly, or cancels immediately when simulating a bail.
func _fake_recall(focus_lesson: String, size: int, allow_practice: bool) -> void:
	await process_frame
	if not _answer_correctly:
		_bus.learn_closed.emit(0, 0, true)   # cancelled, nothing attempted
		return

	var attempted := 0
	var correct := 0
	var seen := {}
	for i in size:
		var prompt: Dictionary = _learning.progression.build_prompt({}, allow_practice, focus_lesson)
		if prompt.is_empty():
			break
		var id := String(prompt["card"].get("id", ""))
		if attempted > 0 and seen.has(id):
			break   # matches the panel: don't just repeat a card
		seen[id] = true
		if _learning.progression.answer(prompt["card"], String(prompt["answer"])):
			correct += 1
		attempted += 1
	_bus.learn_closed.emit(attempted, correct, false)


# --- helpers ---------------------------------------------------------------

func _reset() -> void:
	_save.clear()
	_learning.reload()


func _make_gate() -> Node2D:
	var gate: Node2D = load("res://src/entities/lesson_gate.tscn").instantiate()
	gate.gate_id = "north_torii"
	gate.required_lesson = "kana-vowels"
	gate.required_level = 1
	return gate


func _flag_survives_reload(gate_id: String) -> bool:
	_learning.reload()
	return LessonGateLogic.is_cleared(_learning.profile, gate_id)


func _finish() -> void:
	_save.clear()
	print("")
	print(("PASS — the recall loop opens the gate and remembers it."
		if failures == 0 else "FAIL — %d recall-loop check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
