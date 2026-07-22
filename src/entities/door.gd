extends Area2D
## A doorway between levels. Same interactable contract as LessonGate / Npc:
## an Area2D in group "interactable", collision_layer 8, exposing interact(player) —
## the player's InteractProbe finds it and calls interact(), so no player.gd changes.
##
## On use it travels to `target_scene`, arriving at the marker named `target_spawn`
## in that scene. Set both per-instance in the editor. Doors are invisible by default
## (the house art already draws a door, and interiors add their own exit mat); drop a
## Sprite2D under an instance if a spot needs a visible marker.

@export_file("*.tscn") var target_scene: String = ""
## Must match a spawn marker's `spawn_id` in the destination scene ("" = its default).
@export var target_spawn: String = ""
## When true, stepping onto the door travels immediately (no interact press needed).
@export var auto_enter: bool = false

var _used := false


func _ready() -> void:
	add_to_group("interactable")
	if auto_enter:
		body_entered.connect(_on_body_entered)


## Called by the player's interaction probe when they press interact nearby.
func interact(_player: Node = null) -> void:
	_travel()


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		_travel()


func _travel() -> void:
	if _used:
		return   # guard against a double-fire during the scene change
	if target_scene.is_empty():
		push_warning("[Door] no target_scene set on %s" % name)
		return
	_used = true
	Transitions.travel(target_scene, target_spawn)
