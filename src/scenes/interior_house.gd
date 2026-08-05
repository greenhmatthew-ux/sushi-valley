extends Node2D
## A building interior — a small room entered from a village door.
##
## Built in code (this workflow has no interactive editor): a floor with a back wall, a
## collision border that seals the room, an exit Door back to the village, and the player
## placed at the arrival marker. Player-carried state (Inv, Learning) rides the autoloads
## across the scene swap, so only the arrival point is passed in.
##
## Floor and walls share one warm Ninja Adventure interior tile. The wall reads as distinct
## via a darker modulate on its own TileMapLayer: the same material in shadow, not a collage.

const TILE := 16

## Room shape is per-scene, not per-script. Two buildings that share this script must not
## share a room: an interior reused wholesale is the same placeholder failure as two NPCs
## sharing a face, so the shape, the doorway and the wall shade are all set by the scene.
@export var room_width: int = 13    # in tiles
@export var room_height: int = 9    # in tiles
## The tile the front door occupies in the bottom wall.
@export var doorway_x: int = 6
@export var wall_tint: Color = Color(0.62, 0.5, 0.4)

const FLOOR_TEX := preload("res://assets/tilesets/ninja_interior_floor.png")
const FLOOR_TILE := Vector2i(4, 2)   # complete warm brick centre tile; repeats without seams

@onready var floor_layer: TileMapLayer = $Floor
@onready var entities: Node2D = $Entities
var wall_layer: TileMapLayer


func _ready() -> void:
	Audio.play_music("interior")
	_build_tileset()
	_build_room()
	_build_walls()
	_place_player()
	_clamp_camera()


func _build_tileset() -> void:
	var src := TileSetAtlasSource.new()
	src.texture = FLOOR_TEX
	src.texture_region_size = Vector2i(TILE, TILE)
	src.create_tile(FLOOR_TILE)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)

	floor_layer.tile_set = ts

	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wall_layer.tile_set = ts
	wall_layer.modulate = wall_tint
	add_child(wall_layer)
	move_child(wall_layer, floor_layer.get_index() + 1)


func _build_room() -> void:
	# Rows 0-1, the outer columns, and the bottom row are wall (darker layer); the rest is
	# floor. The bottom wall has a one-tile gap at `doorway_x` — that is the doorway, and the
	# door sprite sits IN it, attached to the wall, rather than floating on open floor.
	for x in room_width:
		for y in room_height:
			var is_wall := y == 0 or y == 1 or x == 0 or x == room_width - 1 \
				or (y == room_height - 1 and x != doorway_x)
			var layer := wall_layer if is_wall else floor_layer
			layer.set_cell(Vector2i(x, y), 0, FLOOR_TILE)


## A StaticBody border confining the player to the interior floor (inside the walls);
## the open bottom is left to the door, which auto-triggers before they reach the edge.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var l := float(TILE)               # inner left (right of the col-0 wall)
	var r := float((room_width - 1) * TILE)   # inner right (left of the last-col wall)
	var t := float(2 * TILE)           # inner top (below the back wall)
	var b := float(room_height * TILE)  # inner bottom (the open doorway edge)
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
	cam.limit_right = room_width * TILE
	cam.limit_bottom = room_height * TILE
	cam.reset_smoothing()
