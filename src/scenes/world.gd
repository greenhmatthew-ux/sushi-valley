class_name World
extends Node2D
## A playable level: tile layers, props, and the player.
##
## Camera limits are derived from the Ground layer rather than baked into the
## scene, so resizing the map by hand in the editor cannot leave the camera
## clamped to stale bounds.

@onready var ground: TileMapLayer = $Ground


func _ready() -> void:
	_clamp_camera_to_map()


func _clamp_camera_to_map() -> void:
	var player := get_node_or_null("Player")
	if player == null:
		return
	var camera: Camera2D = player.get_node_or_null("Camera")
	if camera == null or ground == null:
		return

	var used := ground.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var tile: Vector2i = ground.tile_set.tile_size
	camera.limit_left = used.position.x * tile.x
	camera.limit_top = used.position.y * tile.y
	camera.limit_right = used.end.x * tile.x
	camera.limit_bottom = used.end.y * tile.y
