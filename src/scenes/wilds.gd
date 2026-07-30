extends Node2D
## The wilds — an open combat frontier reached by a path out of the village. Foes here are
## AGGRO (unlike the safe village where you opt into sparring). Ground is generated in code
## (this workflow has no interactive editor): a grass base plus a restrained DETAIL layer —
## a light meadow of small blossoms, clustered flower beds, and the odd shrub — so it
## never reads as a flat monotone field. Trees/rocks/outpost/enemies are authored in the
## .tscn, grouped into groves and a yard framing an open central clearing to fight in.
##
## Detail comes from the same Serene Village sheet as the terrain. Density is deliberately
## low: textured, not overgrown.

const TILE := 16
const W := 42   # tiles wide
const H := 28   # tiles tall
const GEN_SEED := 20260727   # fixed so the generated meadow is stable run-to-run

const GRASS := Vector2i(4, 0)   # serene_village grass (ground, source 0)

# Dirt trail atlas coords in serene_village. The route chooses among these from each
# cell's open cardinal edges, so bends have real corners instead of one repeated centre tile.
const TRAIL_CENTER := Vector2i(10, 2)
const TRAIL_LEFT := Vector2i(9, 2)
const TRAIL_RIGHT := Vector2i(6, 2)
const TRAIL_TOP: Array[Vector2i] = [Vector2i(7, 3), Vector2i(8, 3)]
const TRAIL_BOTTOM: Array[Vector2i] = [Vector2i(7, 1), Vector2i(8, 1)]
const TRAIL_TOP_LEFT := Vector2i(5, 2)
const TRAIL_TOP_RIGHT := Vector2i(3, 2)
const TRAIL_BOTTOM_LEFT := Vector2i(5, 1)
const TRAIL_BOTTOM_RIGHT := Vector2i(3, 1)

# Fixed route waypoints, in tile coordinates. A three-tile brush turns each centreline into
# a readable trail: the main north road, the outpost spur, and an east-side hunt loop.
const MAIN_ROUTE: Array[Vector2i] = [
	Vector2i(21, 27), Vector2i(21, 23), Vector2i(20, 20),
	Vector2i(18, 15), Vector2i(19, 11), Vector2i(20, 5),
]
const OUTPOST_SPUR: Array[Vector2i] = [
	Vector2i(20, 20), Vector2i(16, 20), Vector2i(12, 20),
	Vector2i(10, 20), Vector2i(8, 20), Vector2i(6, 19),
]
const EAST_HUNT_LOOP: Array[Vector2i] = [
	Vector2i(18, 15), Vector2i(27, 15), Vector2i(33, 16),
	Vector2i(38, 18), Vector2i(38, 20), Vector2i(34, 22),
	Vector2i(29, 22), Vector2i(24, 20), Vector2i(20, 20),
]

# Complete, standalone Serene Village detail frames (source 1).
const MEADOW_FLOWERS: Array[Vector2i] = [
	Vector2i(2, 13), Vector2i(17, 24), Vector2i(17, 25), Vector2i(18, 25)]
const FLOWER_BEDS: Array[Vector2i] = [Vector2i(2, 14), Vector2i(18, 24)]
const SHRUB := Vector2i(7, 12)

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities
var detail: TileMapLayer

var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}   # tiles under props/buildings — kept clear of detail
var _route_cells: Dictionary = {}


func _ready() -> void:
	Audio.play_music("forest")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_ground()
	_build_bounds()
	_mark_occupied()
	_build_detail()
	_place_player()
	_clamp_camera()


## One shared TileSet: source 0 is Serene Village terrain and source 1 is a small set of
## standalone Serene meadow details. Built in code so every coord we paint is registered.
## Ground keeps the .tscn tile_set slot; the Detail layer is created here, just above Ground
## and below the y-sorted Entities so the player and trees draw over the flowers.
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var grass_src := TileSetAtlasSource.new()
	grass_src.texture = preload("res://assets/tilesets/serene_village.png")
	grass_src.texture_region_size = Vector2i(TILE, TILE)
	grass_src.create_tile(GRASS)
	var trail_tiles: Array[Vector2i] = [
		TRAIL_CENTER, TRAIL_LEFT, TRAIL_RIGHT,
		TRAIL_TOP[0], TRAIL_TOP[1], TRAIL_BOTTOM[0], TRAIL_BOTTOM[1],
		TRAIL_TOP_LEFT, TRAIL_TOP_RIGHT, TRAIL_BOTTOM_LEFT, TRAIL_BOTTOM_RIGHT,
	]
	for tile in trail_tiles:
		grass_src.create_tile(tile)
	ts.add_source(grass_src, 0)

	var decal_src := TileSetAtlasSource.new()
	decal_src.texture = preload("res://assets/tilesets/serene_village.png")
	decal_src.texture_region_size = Vector2i(TILE, TILE)
	var coords: Array[Vector2i] = [SHRUB]
	coords.append_array(MEADOW_FLOWERS)
	coords.append_array(FLOWER_BEDS)
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
	_build_route()


## Rasterize fixed waypoints with a three-tile brush, then pick real edge/corner art from
## each cell's missing cardinal neighbours. Route cells also join `_blocked`, keeping grass
## tufts and flowers off the walked trail.
func _build_route() -> void:
	_route_cells.clear()
	_add_route(MAIN_ROUTE)
	_add_route(OUTPOST_SPUR)
	_add_route(EAST_HUNT_LOOP)
	for raw_cell in _route_cells:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, _trail_tile(cell))
		_blocked[cell] = true


func _add_route(waypoints: Array[Vector2i]) -> void:
	for i in range(waypoints.size() - 1):
		for center in _raster_line(waypoints[i], waypoints[i + 1]):
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var cell := center + Vector2i(dx, dy)
					if cell.x >= 0 and cell.x < W and cell.y >= 0 and cell.y < H:
						_route_cells[cell] = true


## Integer Bresenham keeps diagonal waypoint segments connected without any float rounding.
func _raster_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x := from_cell.x
	var y := from_cell.y
	var dx := absi(to_cell.x - from_cell.x)
	var sx := 1 if from_cell.x < to_cell.x else -1
	var dy := -absi(to_cell.y - from_cell.y)
	var sy := 1 if from_cell.y < to_cell.y else -1
	var error := dx + dy
	while true:
		cells.append(Vector2i(x, y))
		if x == to_cell.x and y == to_cell.y:
			break
		var twice_error := 2 * error
		if twice_error >= dy:
			error += dy
			x += sx
		if twice_error <= dx:
			error += dx
			y += sy
	return cells


## Bit flags mean the route is open (missing) on that side: top=1, right=2,
## bottom=4, left=8. Concave junctions and endpoints deliberately use the centre tile.
func _trail_tile(cell: Vector2i) -> Vector2i:
	var open_mask := 0
	if not _route_cells.has(cell + Vector2i.UP):
		open_mask |= 1
	if not _route_cells.has(cell + Vector2i.RIGHT):
		open_mask |= 2
	if not _route_cells.has(cell + Vector2i.DOWN):
		open_mask |= 4
	if not _route_cells.has(cell + Vector2i.LEFT):
		open_mask |= 8
	match open_mask:
		1:
			return TRAIL_TOP[(cell.x + cell.y) & 1]
		2:
			return TRAIL_RIGHT
		3:
			return TRAIL_TOP_RIGHT
		4:
			return TRAIL_BOTTOM[(cell.x + cell.y) & 1]
		6:
			return TRAIL_BOTTOM_RIGHT
		8:
			return TRAIL_LEFT
		9:
			return TRAIL_TOP_LEFT
		12:
			return TRAIL_BOTTOM_LEFT
		_:
			return TRAIL_CENTER


## Match the village's proven four-wall boundary pattern. The south transition's 20px
## auto-enter radius fires before the player reaches the bottom wall.
func _build_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	_add_bound(bounds, "Top", Vector2(W * TILE / 2.0, -4), Vector2(W * TILE, 8))
	_add_bound(bounds, "Bottom", Vector2(W * TILE / 2.0, H * TILE + 4),
		Vector2(W * TILE, 8))
	_add_bound(bounds, "Left", Vector2(-4, H * TILE / 2.0), Vector2(8, H * TILE))
	_add_bound(bounds, "Right", Vector2(W * TILE + 4, H * TILE / 2.0),
		Vector2(8, H * TILE))


func _add_bound(parent: StaticBody2D, shape_name: String,
		position: Vector2, size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	collision.name = shape_name
	collision.position = position
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	parent.add_child(collision)


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


## Restrained meadow: a light wash of blossoms across the open grass, tight wildflower
## patches for colour, and rare shrub accents. Then a flower bed framing the yard.
func _build_detail() -> void:
	for x in range(1, W - 1):
		for y in range(1, H - 1):
			var c := Vector2i(x, y)
			if _blocked.has(c):
				continue
			var roll := _rng.randf()
			if roll < 0.08:
				_set_detail(c, MEADOW_FLOWERS[_rng.randi() % MEADOW_FLOWERS.size()])
			elif roll < 0.086:
				_set_detail(c, SHRUB)

	# Wildflower patches — clustered so colour reads as beds, not confetti.
	for i in 7:
		var center := Vector2i(_rng.randi_range(3, W - 4), _rng.randi_range(3, H - 4))
		var species: Vector2i = FLOWER_BEDS[_rng.randi() % FLOWER_BEDS.size()]
		for j in _rng.randi_range(4, 7):
			var c := center + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-1, 1))
			_set_detail(c, species)

	_build_outpost_yard()


## A tended flower bed flanking the outpost front, so it reads as someone's frontier post.
func _build_outpost_yard() -> void:
	var base := _to_tile(_outpost_pos())
	for cell in [Vector2i(-3, 2), Vector2i(-3, 3), Vector2i(-2, 3),
			Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3)]:
		_set_detail(base + cell, FLOWER_BEDS[_rng.randi() % FLOWER_BEDS.size()])


func _set_detail(c: Vector2i, tile: Vector2i) -> void:
	if c.x < 1 or c.x >= W - 1 or c.y < 1 or c.y >= H - 1:
		return
	if _blocked.has(c):
		return
	detail.set_cell(c, 1, tile)   # source 1 = Serene meadow details


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
