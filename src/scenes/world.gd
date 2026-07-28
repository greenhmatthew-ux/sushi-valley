class_name World
extends Node2D
## A playable level: tile layers, props, and the player.
##
## Camera limits are derived from the Ground layer rather than baked into the
## scene, so resizing the map by hand in the editor cannot leave the camera
## clamped to stale bounds.

const GRASS_ATLAS := Vector2i(4, 0)   # serene_village grass tile in the Ground layer
const MEADOW_SEED := 20260728

# Sprout decal coords (same restrained meadow set used in the wilds, for a consistent look).
const TUFTS: Array[Vector2i] = [Vector2i(5, 1), Vector2i(6, 1)]
const FLOWERS: Array[Vector2i] = [Vector2i(6, 2), Vector2i(6, 3), Vector2i(7, 3)]
const PEBBLE := Vector2i(6, 4)

@onready var ground: TileMapLayer = $Ground


func _ready() -> void:
	_clamp_camera_to_map()
	_build_meadow()
	_load_game()


## Texture the flat grass fields the same way the wilds does: a restrained wash of Sprout
## tufts, a few clustered wildflower beds, rare pebbles — placed ONLY on plain grass tiles
## and never under a prop/building. Purely decorative, generated on entry, so the authored
## .tscn stays untouched. Low density on purpose (Matthew: areas should not be dense).
func _build_meadow() -> void:
	var detail := TileMapLayer.new()
	detail.name = "Meadow"
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = preload("res://assets/sprites/sprout-basic-grass-biome.png")
	src.texture_region_size = Vector2i(16, 16)
	var coords: Array[Vector2i] = [PEBBLE]
	coords.append_array(TUFTS)
	coords.append_array(FLOWERS)
	for c in coords:
		src.create_tile(c)
	ts.add_source(src, 0)
	detail.tile_set = ts
	add_child(detail)
	move_child(detail, 1)   # after Ground(0), before the y-sorted Props

	var blocked := _occupied_tiles()
	var grass: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) == GRASS_ATLAS and not blocked.has(cell):
			grass.append(cell)

	var rng := RandomNumberGenerator.new()
	rng.seed = MEADOW_SEED
	# a light wash of tufts + rare pebbles across open grass
	for cell in grass:
		var roll := rng.randf()
		if roll < 0.09:
			detail.set_cell(cell, 0, TUFTS[rng.randi() % TUFTS.size()])
		elif roll < 0.098:
			detail.set_cell(cell, 0, PEBBLE)
	# a few clustered wildflower beds for colour (grass-only, skips blocked)
	for i in 8:
		if grass.is_empty():
			break
		var center: Vector2i = grass[rng.randi() % grass.size()]
		var species: Vector2i = FLOWERS[rng.randi() % FLOWERS.size()]
		for j in rng.randi_range(3, 6):
			var c := center + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
			if ground.get_cell_atlas_coords(c) == GRASS_ATLAS and not blocked.has(c):
				detail.set_cell(c, 0, species)


## Tiles sitting under a prop/building, kept clear of scattered detail. Buildings, doors and
## gates get a wider pad than small props so nothing pokes through a wall.
func _occupied_tiles() -> Dictionary:
	var blocked: Dictionary = {}
	var props := get_node_or_null("Props")
	if props == null:
		return blocked
	var tile: Vector2i = ground.tile_set.tile_size
	for e in props.get_children():
		if not (e is Node2D) or e.name == "Player":
			continue
		var t := Vector2i((e as Node2D).position / Vector2(tile))
		var n := String(e.name)
		var pad := 2 if (n.contains("House") or n.contains("Door") or n.contains("Gate")) else 1
		for dx in range(-pad, pad + 1):
			for dy in range(-pad, pad + 1):
				blocked[t + Vector2i(dx, dy)] = true
	return blocked


## Restore saved progress on entry. The Learning autoload already re-hydrated the
## review schedule in its own _ready() (SaveGame.load_profile feeds it), so here we
## only place the Player where they left off. Read-only: nothing is written on load.
func _load_game() -> void:
	# Arriving back through a door beats the saved position — spawn at that doorway.
	var arrival := Transitions.take_pending_spawn()
	if not arrival.is_empty() and _place_at_spawn(arrival):
		return
	if not SaveGame.has_save():
		return
	var placement := SaveGame.apply_snapshot(SaveGame.load_snapshot())
	if not placement.get("has_player", false):
		return
	var player := get_node_or_null("Props/Player")
	if player == null:
		return
	player.global_position = placement["position"]
	player.face(String(placement["facing"]))


## Move the player to the spawn_point marker whose spawn_id matches; returns success.
func _place_at_spawn(spawn_id: String) -> bool:
	var player := get_node_or_null("Props/Player")
	if player == null:
		return false
	for m in get_tree().get_nodes_in_group("spawn_point"):
		if m.get("spawn_id") == spawn_id:
			player.global_position = m.global_position
			player.face("down")
			return true
	return false


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
	var player := get_node_or_null("Props/Player")
	if player != null:
		pos = player.global_position
		facing = String(player.facing)
	SaveGame.save_snapshot(learning_data, pos, facing)


func _clamp_camera_to_map() -> void:
	var player := get_node_or_null("Props/Player")
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
