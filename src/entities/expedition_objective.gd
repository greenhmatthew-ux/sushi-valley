extends Area2D
## The lost lunchbox — an Expedition's objective, and where its recall happens.
##
## Interactable contract as everywhere else (group "interactable", layer 8,
## interact(player)). What it says depends entirely on the saved stage, so a
## player who quits mid-run and comes back is told exactly what is left:
##   active             — the guard still blocks the trail
##   encounter-cleared  — open it, then run the focused recall
##   objective-recovered— retry the recall (a failed recall is never a dead end)
##   recall-cleared     — the boss is awake; go fight it
##   complete           — a flavour line; the run is done
##
## The recall runs through the ONE shared scheduler by Bus round-trip, exactly
## like every teacher: emit learn_open, await learn_closed. This node owns no
## cards and never touches the recall UI.

const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")

## Emitted whenever the saved stage advances, so the room can show or hide the
## boss without polling. Local signal, not a Bus one: only the owning room cares.
signal stage_advanced

@export var expedition_id: String = ""
## Dialogue title, before and after recovery. Deliberately NOT named `speaker`:
## the context prompt treats a `speaker` as a person and would offer "Talk to
## Lost Lunchbox".
@export var objective_name: String = "Lost Lunchbox"
@export var recovered_name: String = "Recovered Lunchbox"

const CHEST := preload("res://assets/objects/ninja_little_treasure_chest.png")

var _busy := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()
	refresh()


## Open chest once recovered, closed while it is still the goal.
func refresh() -> void:
	if _sprite == null:
		return
	var stage := String(ExpeditionLogic.progress(
		Learning.profile, expedition_id).get("stage", ""))
	var opened := stage in ["objective-recovered", "recall-cleared", "complete"]
	(_sprite.texture as AtlasTexture).region = Rect2(16 if opened else 0, 0, 16, 16)


func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face("up")
	await _run()
	_busy = false


func _run() -> void:
	var expedition: Dictionary = DB.expedition(expedition_id)
	if expedition.is_empty():
		return
	match String(ExpeditionLogic.progress(Learning.profile, expedition_id).get("stage", "")):
		"active":
			Bus.dialogue_open.emit(objective_name, [
				"The thornback has churned the trail into a wall of roots.",
				"Clear the guard before reaching for the lunchbox.",
			])
			await Bus.dialogue_closed
		"encounter-cleared":
			ExpeditionLogic.recover_objective(Learning.profile, expedition_id)
			refresh()
			stage_advanced.emit()
			Bus.dialogue_open.emit(objective_name, [
				"Inside is a cedar bento card from the kitchen trial.",
				"Recall the food kana correctly to break the seal on the wraith grove.",
			])
			await Bus.dialogue_closed
			await _run_recall(expedition)
		"objective-recovered":
			await _run_recall(expedition)
		"recall-cleared":
			Bus.dialogue_open.emit(recovered_name, [
				"The lunchbox is safe. A cold presence now waits in the eastern grove.",
			])
			await Bus.dialogue_closed
		_:
			Bus.dialogue_open.emit(recovered_name, [
				"The lunchbox recipe has been copied into your kitchen notes.",
			])
			await Bus.dialogue_closed


## The focused three-card recall. Unlocks the lesson first so the session always
## has cards, matching the TS flow. Clearing needs one correct answer, not a
## perfect run — and failing only asks you to inspect the lunchbox again.
func _run_recall(expedition: Dictionary) -> void:
	var lesson := String(expedition.get("lessonFocus", ""))
	if not lesson.is_empty():
		Learning.profile.unlock_lesson(lesson)
		Learning.profile.save()
	Bus.learn_open.emit(lesson, 3, true)
	var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
	if bool(res[2]):
		return
	if int(res[0]) > 0 and int(res[1]) > 0 \
			and ExpeditionLogic.mark_recall_cleared(Learning.profile, expedition_id):
		stage_advanced.emit()
		Bus.toast.emit("Lunchbox recall cleared — the Forest Wraith has awakened.")
		Bus.hud_refresh.emit()
		return
	Bus.toast.emit("The grove remains sealed. Inspect the lunchbox to retry the recall.")


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	var tex := AtlasTexture.new()
	tex.atlas = CHEST
	tex.region = Rect2(0, 0, 16, 16)
	tex.filter_clip = true
	_sprite.texture = tex
	_sprite.offset = Vector2(0, -8)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
