extends Area2D
## The trailhead into an Expedition — the woods-side door with a lock on it.
##
## Same interactable contract as Door / LessonGate: an Area2D in group
## "interactable" on collision layer 8 exposing interact(player). Unlike a Door
## it never travels blind: it asks ExpeditionLogic whether the run is open,
## explains the lock when it is not, and confirms before committing (the
## EXPEDITION_DESIGN entry contract: "Entry point -> confirmation UI -> load
## map"). Progress is started here so a retreat resumes the same stage.

const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")

## Expedition id from data/game/expeditions.json.
@export var expedition_id: String = ""
@export_file("*.tscn") var room_scene: String = ""
## Said when the unlock contract is not met yet. Authored per-instance so the
## reason names the real prerequisite instead of a generic "locked".
@export var locked_lines: PackedStringArray = PackedStringArray([
	"This forest route is sealed.",
])
## What the confirmation calls the run, and what it promises about checkpoints.
## Authored per-instance for the same reason `locked_lines` is: a second Expedition
## is a different route through different country, and "the handcrafted forest
## route" is a lie anywhere but the woods. Defaults are the woods' own wording.
@export var route_name: String = "handcrafted forest route"
@export var checkpoint_line: String = \
	"Progress is saved after the encounter, the lunchbox, the recall, and the boss."

const POST := preload("res://assets/tilesets/serene_village.png")
## Picket post from the Serene Village sheet — the same tile the lesson gate
## uses, so a gated route reads consistently across the game.
const POST_REGION := Rect2(80, 240, 16, 16)

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


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
	var title := String(expedition.get("displayName", expedition_id))

	if not ExpeditionLogic.can_enter(Learning.profile, expedition):
		var lines: Array[String] = []
		for l in locked_lines:
			lines.append(String(l))
		Bus.dialogue_open.emit(title, lines)
		await Bus.dialogue_closed
		return

	# "Resume" is the honest word once a run is underway — the room will put the
	# player back at the stage their save holds, not at the start.
	var existing := ExpeditionLogic.progress(Learning.profile, expedition_id)
	var underway := not existing.is_empty() \
		and String(existing.get("stage", "")) != "complete"
	Bus.dialogue_open.emit(title, [
		"%s the %s?" % ["Resume" if underway else "Begin", route_name],
		checkpoint_line,
	])
	await Bus.dialogue_closed

	ExpeditionLogic.start(Learning.profile, expedition)
	Bus.hud_refresh.emit()
	Transitions.travel(room_scene, "expedition_entry")


## Two posts framing a gap, built in code so the .tscn stays tiny. The gap is
## the walkable trailhead; the posts only say "this is a way through".
func _build_visual() -> void:
	for offset in [-14, 14]:
		var post := Sprite2D.new()
		var tex := AtlasTexture.new()
		tex.atlas = POST
		tex.region = POST_REGION
		tex.filter_clip = true
		post.texture = tex
		post.position = Vector2(offset, 0)
		post.offset = Vector2(0, -8)
		post.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(post)
