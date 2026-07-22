extends Node2D
## A building interior — a small timber room entered from a village door.
##
## Built in code (this workflow has no interactive editor): a wood floor with a back
## wall, a collision border that seals the room, an exit Door back to the village, and
## the player placed at the arrival marker. Player-carried state (Inv, Learning) rides
## the autoloads across the scene swap, so only the arrival point is passed in.

const TILE := 16
const W := 13   # room width in tiles
const H := 9    # room height in tiles

# Atlas coords into home_interiors_timber_roof.png (16px grid).
const FLOOR := Vector2i(2, 7)
const WALL := Vector2i(23, 11)

@onready var floor_layer: TileMapLayer = $Floor
@onready var entities: Node2D = $Entities


func _ready() -> void:
	_build_room()
	_build_walls()
	_place_player()
	_clamp_camera()


func _build_room() -> void:
	for x in W:
		for y in H:
			floor_layer.set_cell(Vector2i(x, y), 0, WALL if y == 0 else FLOOR)


## A simple StaticBody border so the player can't leave the room except by the door.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var w := float(W * TILE)
	var h := float(H * TILE)
	# [center, size]: the top rect seals the back-wall row; the rest close the edges.
	var rects := [
		[Vector2(w * 0.5, TILE - 2.0), Vector2(w, 8.0)],
		[Vector2(w * 0.5, h + 2.0), Vector2(w, 8.0)],
		[Vector2(2.0, h * 0.5), Vector2(8.0, h)],
		[Vector2(w - 2.0, h * 0.5), Vector2(8.0, h)],
	]
	for r in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r[1]
		cs.shape = shape
		cs.position = r[0]
		body.add_child(cs)


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
