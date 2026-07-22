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
	_load_game()


## Restore saved progress on entry. The Learning autoload already re-hydrated the
## review schedule in its own _ready() (SaveGame.load_profile feeds it), so here we
## only place the Player where they left off. Read-only: nothing is written on load.
func _load_game() -> void:
	if not SaveGame.has_save():
		return
	var placement := SaveGame.apply_snapshot(SaveGame.load_snapshot())
	if not placement.get("has_player", false):
		return
	var player := get_node_or_null("Player")
	if player == null:
		return
	player.global_position = placement["position"]
	player.face(String(placement["facing"]))


## Autosave when the player closes the window. WM_CLOSE_REQUEST (not EXIT_TREE) is
## the genuine "quit the game" event, so headless test teardown and future scene
## swaps do not overwrite a real save with a throwaway position.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _save_game() -> void:
	var learning_data: Dictionary = {}
	if Learning.profile != null:
		learning_data = Learning.profile.to_save_dict()
	var pos := Vector2.ZERO
	var facing := "down"
	var player := get_node_or_null("Player")
	if player != null:
		pos = player.global_position
		facing = String(player.facing)
	SaveGame.save_snapshot(learning_data, pos, facing)


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
