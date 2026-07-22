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
const FLOOR := Vector2i(2, 10)     # warm timber floor
const WALL := Vector2i(18, 13)     # wood-plank wall face
const WALL_TOP := Vector2i(7, 2)   # dark cap along the very top edge

@onready var floor_layer: TileMapLayer = $Floor
@onready var entities: Node2D = $Entities


func _ready() -> void:
	_build_room()
	_build_walls()
	_place_player()
	_clamp_camera()


func _build_room() -> void:
	# Row 0 is a dark cap; row 1 and the outer columns are the wood-plank wall; the rest
	# is floor. The bottom stays open — that edge is the doorway you walk out through.
	for x in W:
		for y in H:
			var tile: Vector2i
			if y == 0:
				tile = WALL_TOP
			elif y == 1 or x == 0 or x == W - 1:
				tile = WALL
			else:
				tile = FLOOR
			floor_layer.set_cell(Vector2i(x, y), 0, tile)


## A StaticBody border confining the player to the interior floor (inside the walls);
## the open bottom is left to the door, which auto-triggers before they reach the edge.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var l := float(TILE)               # inner left (right of the col-0 wall)
	var r := float((W - 1) * TILE)     # inner right (left of the last-col wall)
	var t := float(2 * TILE)           # inner top (below the back wall)
	var b := float(H * TILE)           # inner bottom (the open doorway edge)
	# [center, size]: seal top/left/right; the bottom rect stops a walk-off past the door.
	var rects := [
		[Vector2((l + r) * 0.5, t - 4.0), Vector2(r - l, 8.0)],
		[Vector2((l + r) * 0.5, b + 4.0), Vector2(r - l, 8.0)],
		[Vector2(l - 4.0, (t + b) * 0.5), Vector2(8.0, b - t)],
		[Vector2(r + 4.0, (t + b) * 0.5), Vector2(8.0, b - t)],
	]
	for rect_def in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect_def[1]
		cs.shape = shape
		cs.position = rect_def[0]
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
