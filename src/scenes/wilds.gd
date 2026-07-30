extends Node2D
## The wilds — an open combat frontier reached by a path out of the village. Foes here are
## AGGRO (unlike the safe village where you opt into sparring). Ground is generated in code
## (this workflow has no interactive editor): a grass base plus a restrained DETAIL layer —
## a light meadow of grass tufts, clustered wildflowers, the odd mushroom/pebble — so it
## never reads as a flat monotone field. Trees/rocks/outpost/enemies are authored in the
## .tscn, grouped into groves and a yard framing an open central clearing to fight in.
##
## Detail comes from the Sprout decal sheet (the same set the village scatters), for a
## consistent look. Density is deliberately low: textured, not overgrown.

const TILE := 16
const W := 42   # tiles wide
const H := 28   # tiles tall
const GEN_SEED := 20260727   # fixed so the generated meadow is stable run-to-run

const GRASS := Vector2i(4, 0)   # serene_village grass (ground, source 0)

# Sprout decal atlas (source 1): confirmed by inspecting sprout-basic-grass-biome.png.
const TUFTS: Array[Vector2i] = [Vector2i(5, 1), Vector2i(6, 1)]           # small leaf clumps
const FLOWERS: Array[Vector2i] = [Vector2i(6, 2), Vector2i(6, 3), Vector2i(7, 3)]  # yellow/pink
const MUSHROOM := Vector2i(5, 0)
const PEBBLE := Vector2i(6, 4)

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities
var detail: TileMapLayer

var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}   # tiles under props/buildings — kept clear of detail


func _ready() -> void:
	Audio.play_music("forest")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_ground()
	_mark_occupied()
	_build_detail()
	_place_player()
	_clamp_camera()


## One shared TileSet: source 0 is serene_village (grass ground), source 1 is the Sprout decal
## sheet (meadow detail). Built in code so every coord we paint is registered. Ground keeps
## the .tscn tile_set slot; the Detail layer is created here, just above Ground and below the
## y-sorted Entities so the player and trees draw over the flowers.
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var grass_src := TileSetAtlasSource.new()
	grass_src.texture = preload("res://assets/tilesets/serene_village.png")
	grass_src.texture_region_size = Vector2i(TILE, TILE)
	grass_src.create_tile(GRASS)
	ts.add_source(grass_src, 0)

	var decal_src := TileSetAtlasSource.new()
	decal_src.texture = preload("res://assets/sprites/sprout-basic-grass-biome.png")
	decal_src.texture_region_size = Vector2i(TILE, TILE)
	var coords: Array[Vector2i] = [MUSHROOM, PEBBLE]
	coords.append_array(TUFTS)
	coords.append_array(FLOWERS)
	for c in coords:
		decal_src.create_tile(c)
	ts.add_source(decal_src, 1)

	ground.tile_set = ts
	detail = TileMapLayer.new()
	detail.name = "Detail"
	detail.tile_set = ts
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(detail)
	move_child(detail, 1)   # Ground(0) < Detail(1) < Entities(2)


func _build_ground() -> void:
	for x in W:
		for y in H:
			ground.set_cell(Vector2i(x, y), 0, GRASS)


## Record the tiles a prop/building sits on so scattered detail never pokes through a house
## base or a trunk. The outpost gets a bigger pad; small props just their own tile.
func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		var t := _to_tile((e as Node2D).position)
		var pad := 2 if String(e.name).begins_with("Outpost") else 1
		for dx in range(-pad, pad + 1):
			for dy in range(-pad, pad + 1):
				_blocked[t + Vector2i(dx, dy)] = true


## Restrained meadow: a light wash of grass tufts across the open grass, tight wildflower
## patches for colour, and rare mushroom/pebble accents. Then a flower bed framing the yard.
func _build_detail() -> void:
	for x in range(1, W - 1):
		for y in range(1, H - 1):
			var c := Vector2i(x, y)
			if _blocked.has(c):
				continue
			var roll := _rng.randf()
			if roll < 0.11:
				_set_detail(c, TUFTS[_rng.randi() % TUFTS.size()])
			elif roll < 0.118:
				_set_detail(c, PEBBLE)
			elif roll < 0.122:
				_set_detail(c, MUSHROOM)

	# Wildflower patches — clustered so colour reads as beds, not confetti (overwrites tufts).
	for i in 7:
		var center := Vector2i(_rng.randi_range(3, W - 4), _rng.randi_range(3, H - 4))
		var species: Vector2i = FLOWERS[_rng.randi() % FLOWERS.size()]
		for j in _rng.randi_range(4, 7):
			var c := center + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-1, 1))
			_set_detail(c, species)

	_build_outpost_yard()


## A tended flower bed flanking the outpost front, so it reads as someone's frontier post.
func _build_outpost_yard() -> void:
	var base := _to_tile(_outpost_pos())
	for cell in [Vector2i(-3, 2), Vector2i(-3, 3), Vector2i(-2, 3),
			Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3)]:
		_set_detail(base + cell, FLOWERS[_rng.randi() % FLOWERS.size()])


func _set_detail(c: Vector2i, tile: Vector2i) -> void:
	if c.x < 1 or c.x >= W - 1 or c.y < 1 or c.y >= H - 1:
		return
	if _blocked.has(c):
		return
	detail.set_cell(c, 1, tile)   # source 1 = Sprout decals


func _outpost_pos() -> Vector2:
	var o := entities.get_node_or_null("Outpost")
	return (o as Node2D).position if o != null else Vector2(160, 300)


func _to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


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
