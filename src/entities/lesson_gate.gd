extends Area2D
## A recall gate: a torii that will not let the player pass until their SRS
## progress on a required lesson clears a threshold. The educational heart of the
## world, made physical.
##
## The pure decision lives in LessonGateLogic; this node owns the async, UI-driven
## orchestration ported from LessonGate.runLessonGateInteraction /
## runGateRecallLoop: show why it's closed, run recall sessions back-to-back until
## the gate's own threshold is met, then lift the barrier and remember it (a saved
## flag) so it stays open across reloads.
##
## Bus round-trips drive the sessions: emit `learn_open`, await `learn_closed`.
## The gate never touches the recall UI directly, which is why the whole loop is
## testable with a fake responder standing in for the panel.

## Authored per-instance (set in the editor or by the map generator).
@export var gate_id: String = "gate"
@export var required_lesson: String = ""
@export var required_level: int = 1
@export var fail_message: String = ""

var _busy := false
var _open := false

@onready var _barrier: StaticBody2D = $Barrier


func _ready() -> void:
	add_to_group("interactable")
	# A gate the player already cleared in a past session opens on load, silently.
	if not required_lesson.is_empty() and LessonGateLogic.is_cleared(Learning.profile, gate_id):
		_set_open(true)


## Called by the player's interaction probe when they press interact nearby.
func interact(_player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	await _run_interaction()
	_busy = false


func _run_interaction() -> void:
	var profile: LearningProfile = Learning.profile

	if _open or LessonGateLogic.is_cleared(profile, gate_id):
		_set_open(true)
		Bus.dialogue_open.emit("Torii", ["The way is already open."])
		await Bus.dialogue_closed
		return

	if required_lesson.is_empty():
		Bus.dialogue_open.emit("Torii", ["This gate has no required lesson set."])
		await Bus.dialogue_closed
		return

	var eval := LessonGateLogic.evaluate(profile, DB, required_lesson, required_level)
	if eval["satisfied"]:
		_clear_and_open()
		return

	# Not satisfied: explain, then drop into recall unless the lesson can't be
	# helped by practice here (locked cards aren't in the unlocked pool yet, and an
	# unknown lesson has nothing to drill — a session would only surface unrelated
	# cards and look like progress while being unable to clear this gate).
	var detail := LessonGateLogic.detail_text(eval, required_lesson, required_level)
	var opener := fail_message if not fail_message.is_empty() else "Study more before the path opens."
	Bus.dialogue_open.emit("Recall Gate", [opener, detail])
	await Bus.dialogue_closed

	if eval["reason"] == LessonGateLogic.Reason.UNKNOWN_LESSON \
			or eval["reason"] == LessonGateLogic.Reason.LOCKED:
		return

	var final_eval := await _run_recall_loop()
	Bus.hud_refresh.emit()
	if final_eval["cancelled"]:
		return
	if final_eval["satisfied"]:
		_clear_and_open()
	else:
		Bus.toast.emit("Recall progress: %d/%d ready. Nothing left to review right now — come back once more cards are due."
			% [final_eval["ready"], final_eval["total"]])


## Run recall sessions back-to-back until the gate's threshold is actually met —
## not one fixed batch. Returns the final evaluation plus whether the player bailed.
func _run_recall_loop() -> Dictionary:
	var profile: LearningProfile = Learning.profile
	# Studying at a gate IS how its lesson gets learned: unlock it up front so the
	# sessions can contain its cards. Without this, a lesson whose one-off unlock
	# was missed makes the gate structurally unclearable.
	profile.unlock_lesson(required_lesson)
	profile.save()

	while true:
		Bus.learn_open.emit(required_lesson, 5, true)
		var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
		var attempted: int = res[0]
		var cancelled: bool = res[2]

		var eval := LessonGateLogic.evaluate(profile, DB, required_lesson, required_level)
		eval["cancelled"] = cancelled
		if cancelled:
			return eval
		# Stop once satisfied, or once a round genuinely answered nothing (cards on
		# SRS cooldown, or none unlocked) — never loop on empty air.
		if eval["satisfied"] or attempted == 0:
			return eval
		# Break the call stack before reopening, so the panel's learn_open handler
		# doesn't run re-entrantly inside its own learn_closed emission.
		await get_tree().process_frame
	# Unreachable (the loop only exits via return), but GDScript's flow analysis
	# doesn't treat `while true` as guaranteed to return.
	return {}


func _clear_and_open() -> void:
	Learning.profile.set_flag(LessonGateLogic.cleared_flag(gate_id))
	Learning.profile.save()
	_set_open(true)
	Bus.toast.emit("Recall accepted — the path opens.")


## Lift or lower the barrier, visual and collision together.
func _set_open(open: bool) -> void:
	_open = open
	_barrier.visible = not open
	# Deferred: collision state can't change during a physics query/callback.
	($Barrier/Collision as CollisionShape2D).set_deferred("disabled", open)
	# The placeholder gate posts brighten from a dim red (closed) to green (open).
	($Marker as Node2D).modulate = Color(0.4, 0.85, 0.45) if open else Color(0.85, 0.4, 0.4)
