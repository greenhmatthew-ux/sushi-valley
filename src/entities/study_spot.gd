extends Area2D
## A place to sit and review — the "Tea study-spot: a quick optional review of due cards" the
## learning docs list as one of the starting surfaces.
##
## Same interactable contract as the rest (group "interactable", layer 8, interact(player)).
##
## Unlike a teacher, a study spot owns no lesson and unlocks nothing. It reviews whatever the
## shared SRS says is due across everything you know, which makes it the one place to clear a
## backlog without walking the whole village. Nothing due is a valid, pleasant answer — the
## docs are explicit that reviews are never a wall, so it declines rather than inventing
## practice you did not ask for.
##
## Deliberately no reward beyond the XP the review itself grants: a spot you can stand next to
## must not become the optimal way to farm, or it stops being a convenience and becomes a
## chore you are obliged to visit.

## Authored per-instance.
@export var spot_id: String = "study_spot"
## Shown as the speaker. Leave empty for an unattended spot (a desk, a tea table).
@export var label: String = ""
## English-only framing shown before the review. Never Japanese — the Japanese comes from the
## cards themselves (see docs/LEARNING_PROGRESSION.md on sourcing).
@export var caption: String = "You sit for a moment and go over what you have learned."
## How many cards a sitting covers. Micro-reviews only: 1/3/5.
@export var session_size: int = 5
## What the player sits at. Not optional in practice: an interactable with no visual is
## discoverable only by walking into it and trusting the context prompt, which reads as a
## bug, not a secret. Point this at a prop texture (crate/barrel) that matches the caption.
@export var sprite: Texture2D

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	if sprite != null:
		var s := Sprite2D.new()
		s.texture = sprite
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)


func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face("up")
	await _study()
	_busy = false


func _study() -> void:
	var due := Learning.due_count()
	if due == 0:
		Bus.dialogue_open.emit(label, [
			"Nothing needs reviewing right now.",
			"Go and learn something new — this will be here when it does.",
		])
		await Bus.dialogue_closed
		return

	Bus.dialogue_open.emit(label, [caption, "%d word%s ready." % [due, "" if due == 1 else "s"]])
	await Bus.dialogue_closed

	# No focus lesson and no practice fallback: a study spot reviews what is genuinely DUE.
	# Allowing practice here would let it manufacture an endless queue.
	Bus.learn_open.emit("", mini(session_size, due), false)
	var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
	var attempted: int = res[0]
	var correct: int = res[1]
	if attempted > 0 and not bool(res[2]):
		Bus.toast.emit("Reviewed %d/%d correctly." % [correct, attempted])
	Bus.hud_refresh.emit()
