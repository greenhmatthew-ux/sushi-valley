extends Node2D
## The wilds — an open combat area reached by a path out of the village. Unlike the safe
## starting area (where foes are sparring partners you opt into), the monsters here are
## AGGRO: they chase on sight and strike, driving the player's HP/hearts. Ground is built
## in code (this workflow has no interactive editor); trees/rocks and enemies are authored
## in the .tscn at a deliberately low density.

const TILE := 16
const W := 42   # tiles wide
const H := 28   # tiles tall
const GRASS := Vector2i(4, 0)   # serene_village grass tile

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities


func _ready() -> void:
	_build_ground()
	_place_player()
	_clamp_camera()


func _build_ground() -> void:
	for x in W:
		for y in H:
			ground.set_cell(Vector2i(x, y), 0, GRASS)


func _place_player() -> void:
	var player: Node2D = entities.get_node_or_null("Player")
	if player == null:
		return
	var marker := _find_marker(Transitions.take_pending_spawn())
	if marker != null:
		player.global_position = marker.global_position
	if player.has_method("face"):
		player.face("up")


## Match a Marker2D in group "spawn_point" by its spawn_id; default to the first found.
func _find_marker(spawn_id: String) -> Node2D:
	var fallback: Node2D = null
	for m in get_tree().get_nodes_in_group("spawn_point"):
		if fallback == null:
			fallback = m
		if not spawn_id.is_empty() and m.get("spawn_id") == spawn_id:
			return m
	return fallback


func _clamp_camera() -> void:
	var player: Node2D = entities.get_node_or_null("Player")
	if player == null:
		return
	var cam: Camera2D = player.get_node_or_null("Camera")
	if cam == null:
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = W * TILE
	cam.limit_bottom = H * TILE
	cam.reset_smoothing()
