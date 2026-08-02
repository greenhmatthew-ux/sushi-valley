extends Node2D
## The Mountain Pass — the third region, north out of the Wilds.
##
## `data/game/world-regions.json` has listed this route since the TS build ("planned;
## no Godot scene exists yet"), and the mountain music track has been sitting unused
## since the audio import. This is that route: a rocky corridor climbing north, where
## the foes are the mid-tier roster the game already had data for but never placed.
##
## Ground is generated here rather than authored, the same workflow as the Wilds:
## there is no interactive editor in this project, so terrain is code and only the
## props, enemies and NPCs live in the .tscn. The look is deliberately different from
## the Wilds' meadow — bare stone underfoot, cliff walls boxing the route in — so the
## player can tell at a glance they have left the forest.

const TILE := 16
const W := 44   # tiles wide
const H := 30   # tiles tall
const GEN_SEED := 20260731   # fixed, so the scatter is identical run to run

# --- ninja_relief atlas coords (source 0) -------------------------------
# The tan/rock family. Every coordinate here was checked by rendering the tile on
# its own at high zoom first, because this sheet is mostly autotile edge pieces and
# a flat-looking average colour hides a corner nub or a rim bar — scattered as floor
# those read as debris strewn over the whole region. Exactly two tiles in the family
# are genuinely flat, and these are they.
const STONE_FLOOR := Vector2i(2, 6)
## Worn route stone, a shade darker. Used only for the trail: scattering it as
## mottling as well made the route unreadable, since the path and the noise were
## then the same tile. The open ground stays one colour and the scree gives it
## texture, which also means the darker stone always means "this is the way".
const TRAIL := Vector2i(7, 6)
## Cliff wall: a rim course on top, then the striated faces, then a shadowed base.
const CLIFF_RIM := Vector2i(2, 5)
const CLIFF_FACE: Array[Vector2i] = [
	Vector2i(5, 6), Vector2i(8, 6), Vector2i(4, 6), Vector2i(9, 6),
]
const CLIFF_BASE := Vector2i(2, 7)

# --- ninja_relief_detail atlas coords (source 1) ------------------------
## Loose scree and boulders that actually read as objects on the ground, rather
## than the cliff fragments an earlier pass mistook for gravel.
const SCREE: Array[Vector2i] = [Vector2i(0, 3), Vector2i(4, 5)]
const BOULDERS: Array[Vector2i] = [Vector2i(4, 3), Vector2i(4, 4)]

## How many tiles of cliff wall to run along the north edge. The pass reads as a
## corridor, so the climb is walled rather than fading into empty space.
const CLIFF_ROWS := 3

## The route north, in tile coordinates. Rasterised with a three-tile brush like the
## Wilds trail, so bends have width instead of being a one-tile line.
const ROUTE: Array[Vector2i] = [
	Vector2i(22, 29), Vector2i(22, 26), Vector2i(20, 23),
	Vector2i(17, 20), Vector2i(18, 16), Vector2i(22, 13),
	Vector2i(27, 11), Vector2i(30, 8), Vector2i(29, 5),
]
## A spur east to the lookout where the pass keeper camps.
const LOOKOUT_SPUR: Array[Vector2i] = [
	Vector2i(18, 16), Vector2i(13, 16), Vector2i(9, 15), Vector2i(6, 14),
]

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities
var detail: TileMapLayer

var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}
var _route_cells: Dictionary = {}


func _ready() -> void:
	Audio.play_music("mountain")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_ground()
	_build_cliffs()
	_build_bounds()
	_mark_occupied()
	_build_detail()
	_place_player()
	_clamp_camera()


## One TileSet with a single relief source. Built in code so every coordinate painted
## below is registered — an unregistered coord silently draws nothing.
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var source := TileSetAtlasSource.new()
	source.texture = preload("res://assets/tilesets/ninja_relief.png")
	source.texture_region_size = Vector2i(TILE, TILE)
	var coords: Array[Vector2i] = [STONE_FLOOR, TRAIL, CLIFF_RIM, CLIFF_BASE]
	coords.append_array(CLIFF_FACE)
	for c in coords:
		source.create_tile(c)
	ts.add_source(source, 0)

	var detail_source := TileSetAtlasSource.new()
	detail_source.texture = preload("res://assets/tilesets/ninja_relief_detail.png")
	detail_source.texture_region_size = Vector2i(TILE, TILE)
	var detail_coords: Array[Vector2i] = []
	detail_coords.append_array(SCREE)
	detail_coords.append_array(BOULDERS)
	for c in detail_coords:
		detail_source.create_tile(c)
	ts.add_source(detail_source, 1)

	ground.tile_set = ts
	detail = TileMapLayer.new()
	detail.name = "Detail"
	detail.tile_set = ts
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(detail)
	move_child(detail, 1)   # Ground(0) < Detail(1) < Entities(2)


## Bare stone. Texture comes from the scree and boulders scattered on top rather
## than from a tile mix: this family has exactly two flat tiles, and the second one
## is spoken for by the trail.
func _build_ground() -> void:
	for x in W:
		for y in H:
			ground.set_cell(Vector2i(x, y), 0, STONE_FLOOR)
	_build_route()


## Rasterise the route waypoints with a three-tile brush and lay worn stone over them.
func _build_route() -> void:
	_route_cells.clear()
	_add_route(ROUTE)
	_add_route(LOOKOUT_SPUR)
	# No edge course: every "edge" tile in this sheet carries a notch or rim bar that
	# reads as debris in open ground. The trail is legible from its darker stone alone.
	for raw_cell in _route_cells:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, TRAIL)
		_blocked[cell] = true


func _add_route(waypoints: Array) -> void:
	for i in waypoints.size() - 1:
		var from: Vector2i = waypoints[i]
		var to: Vector2i = waypoints[i + 1]
		var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
		for step in steps + 1:
			var t := float(step) / float(maxi(steps, 1))
			var point := Vector2i(
				roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t)))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var cell := point + Vector2i(dx, dy)
					if _in_bounds(cell):
						_route_cells[cell] = true


## A wall of rock across the north edge, so the pass is a corridor with a top to it
## rather than stone that simply stops. Purely visual — the bounds body does the
## blocking, and it is placed to sit exactly under this band.
func _build_cliffs() -> void:
	for x in W:
		ground.set_cell(Vector2i(x, 0), 0, CLIFF_RIM)
		for y in range(1, CLIFF_ROWS):
			ground.set_cell(Vector2i(x, y), 0,
				CLIFF_FACE[(x + y) % CLIFF_FACE.size()])
		ground.set_cell(Vector2i(x, CLIFF_ROWS), 0, CLIFF_BASE)
		for y in range(0, CLIFF_ROWS + 1):
			_blocked[Vector2i(x, y)] = true


## Four walls, matching the village and wilds pattern. The north wall sits below the
## cliff band so the player cannot walk into the rock face.
func _build_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	var cliff_h := (CLIFF_ROWS + 1) * TILE
	_add_bound(bounds, "Top", Vector2(W * TILE / 2.0, cliff_h / 2.0),
		Vector2(W * TILE, cliff_h))
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


## Keep scattered detail off the tiles props and NPCs stand on.
func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		var t := _to_tile((e as Node2D).position)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_blocked[t + Vector2i(dx, dy)] = true


## Loose scree and the odd boulder, away from the route. Sparse on purpose: the pass
## should read as bare stone with things lying on it, not as a textured carpet.
func _build_detail() -> void:
	for x in W:
		for y in range(CLIFF_ROWS + 1, H):
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			var roll := _rng.randf()
			if roll < 0.11:
				detail.set_cell(cell, 1, SCREE[_rng.randi_range(0, SCREE.size() - 1)])
			elif roll < 0.13:
				detail.set_cell(cell, 1, BOULDERS[_rng.randi_range(0, BOULDERS.size() - 1)])


func _place_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var marker := _find_marker(Transitions.take_pending_spawn())
	if marker != null:
		(player as Node2D).global_position = marker.global_position


func _find_marker(spawn_id: String) -> Node2D:
	var fallback: Node2D = null
	for m in get_tree().get_nodes_in_group("spawn_point"):
		if fallback == null:
			fallback = m
		if not spawn_id.is_empty() and m.get("spawn_id") == spawn_id:
			return m
	return fallback


func _clamp_camera() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = W * TILE
	camera.limit_bottom = H * TILE


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x) / TILE, int(world_position.y) / TILE)
