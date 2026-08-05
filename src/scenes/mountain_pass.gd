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

## Placement maths (trail brushes, the scatter lattice, clumping) is shared with the Wilds.
## Preloaded rather than named globally, so a clean headless checkout does not depend on
## the editor's class cache having been rebuilt.
const Scatter = preload("res://src/systems/terrain_scatter.gd")

const TILE := 16
const W := 56   # tiles wide
const H := 56   # tiles tall
const GEN_SEED := 20260731   # fixed, so the scatter is identical run to run

## The climb was widened east and lengthened south in 2026-08. The pass used to be a
## 44x30 room you crossed in one screen; it is now a real ascent with a lower switchback
## below the old entrance, a wind ledge out east, and the same walled top.
const ZONE_SWITCHBACK := Rect2i(0, 30, 44, 26)   # the new lower climb, below the old map
const ZONE_LEDGE := Rect2i(44, 4, 12, 52)        # the new east columns: bare wind ledge

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

# Scattered cover. The same real props the .tscn places by hand, with the same footprints —
# the scatter only decides where.
const PROP_SCENE := preload("res://src/entities/prop.tscn")
const ROCK_TEXTURE: Texture2D = preload("res://assets/props/rock.png")
const PINE_TEXTURE: Texture2D = preload("res://assets/props/tree_green.png")
const ROCK_FOOT := Vector2(12, 6)
const PINE_FOOT := Vector2(10, 5)
const PROP_FOOT_OFFSET := Vector2(0, -2)

## The route north, in tile coordinates. Each route carries its own width: the climb is a
## walked road, the ledge and shelf are single-file tracks that peter out.
const ROUTE: Array[Vector2i] = [
	Vector2i(22, 55), Vector2i(23, 51), Vector2i(18, 48), Vector2i(13, 45),
	Vector2i(16, 40), Vector2i(23, 37), Vector2i(27, 33), Vector2i(22, 30),
	Vector2i(22, 29), Vector2i(22, 26), Vector2i(20, 23),
	Vector2i(17, 20), Vector2i(18, 16), Vector2i(22, 13),
	Vector2i(27, 11), Vector2i(30, 8), Vector2i(29, 5),
]
## A spur east to the lookout where the pass keeper camps.
const LOOKOUT_SPUR: Array[Vector2i] = [
	Vector2i(18, 16), Vector2i(13, 16), Vector2i(9, 15), Vector2i(6, 14),
]
## Out onto the new east ledge, off the switchback rather than off the old road, so the
## detour is something you choose on the way up.
const LEDGE_TRACK: Array[Vector2i] = [
	Vector2i(27, 33), Vector2i(35, 32), Vector2i(42, 29),
	Vector2i(48, 25), Vector2i(51, 20), Vector2i(50, 14),
]
## The wind shelf below the top wall, where the tengu roost.
const SHELF_TRACK: Array[Vector2i] = [
	Vector2i(29, 5), Vector2i(35, 6), Vector2i(41, 5), Vector2i(46, 7),
	Vector2i(50, 9),
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
	_scatter_cover()
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


## Rasterise the route waypoints and lay worn stone over them. Width is per route, so the
## climb reads as the way through and the ledge and shelf read as detours off it.
func _build_route() -> void:
	_route_cells.clear()
	# The climb stays a full road. This sheet's worn stone is only a shade darker than the
	# floor, so a two-tile line of it stopped reading as "this is the way" at all; the
	# detours below carry the hierarchy instead.
	_add_route(ROUTE, 3)
	_add_route(LOOKOUT_SPUR, 2)
	_add_route(LEDGE_TRACK, 1)
	_add_route(SHELF_TRACK, 1)
	# No edge course: every "edge" tile in this sheet carries a notch or rim bar that
	# reads as debris in open ground. The trail is legible from its darker stone alone.
	for raw_cell in _route_cells:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, TRAIL)
		_blocked[cell] = true


func _add_route(waypoints: Array, width: int) -> void:
	for i in waypoints.size() - 1:
		var from: Vector2i = waypoints[i]
		var to: Vector2i = waypoints[i + 1]
		var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
		for step in steps + 1:
			var t := float(step) / float(maxi(steps, 1))
			var point := Vector2i(
				roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t)))
			for cell in Scatter.brush_cells(point, width):
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


## Keep scattered detail and scattered cover off the tiles props and NPCs stand on. Doors,
## spawn markers and gates get the widest pad: a boulder dropped beside a walk-in door
## would hide the way out and crowd its auto-enter radius.
func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		var t := _to_tile((e as Node2D).position)
		var pad := 3 if (e is Marker2D or e is Area2D
			or String(e.name).ends_with("Door")) else 1
		for dx in range(-pad, pad + 1):
			for dy in range(-pad, pad + 1):
				_blocked[t + Vector2i(dx, dy)] = true


## Fill the new switchback and ledge with real cover, using the same rock and pine art the
## .tscn places by hand. The old core keeps only a thin dusting: its landmarks, the forge
## and the lookout camp are authored, and the open stone in front of them is the arena.
func _scatter_cover() -> void:
	# Pines clump into stands; boulders stay incidental, so a stand still has stone in it.
	var clumped: Array[String] = ["pine"]
	for entry in Scatter.plan_cover(Vector2i(W, H), _blocked,
			_zone_cover_mix, clumped, GEN_SEED):
		var cell: Vector2i = entry["cell"]
		if String(entry["kind"]) == "pine":
			_add_cover(cell, PINE_TEXTURE, PINE_FOOT)
		else:
			_add_cover(cell, ROCK_TEXTURE, ROCK_FOOT)
		_blocked[cell] = true


## Per-zone chance of a boulder / a pine at any one lattice point, before clumping. The
## ledge is scoured bare by the wind: stone, and almost nothing that grows.
func _zone_cover_mix(cell: Vector2i) -> Dictionary:
	if ZONE_LEDGE.has_point(cell):
		return {"pine": 0.05, "rock": 0.40}
	if ZONE_SWITCHBACK.has_point(cell):
		return {"pine": 0.26, "rock": 0.30}
	return {"pine": 0.04, "rock": 0.06}


func _add_cover(cell: Vector2i, texture: Texture2D, foot_size: Vector2) -> void:
	var prop := PROP_SCENE.instantiate() as Prop
	if prop == null:
		push_error("mountain pass: prop.tscn did not instantiate as a Prop")
		return
	prop.texture = texture
	prop.foot_size = foot_size
	prop.foot_offset = PROP_FOOT_OFFSET
	# Origin is the feet, so sit the prop on the bottom-centre of its tile.
	prop.position = Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE)
	entities.add_child(prop)


## Loose scree and the odd boulder, away from the route. Sparse on purpose: the pass
## should read as bare stone with things lying on it, not as a textured carpet. The lower
## switchback and the wind ledge carry more of it — that is where the rock is breaking up.
func _build_detail() -> void:
	for x in W:
		for y in range(CLIFF_ROWS + 1, H):
			var cell := Vector2i(x, y)
			if _blocked.has(cell):
				continue
			var mix := _zone_detail_mix(cell)
			var roll := _rng.randf()
			if roll < float(mix["scree"]):
				detail.set_cell(cell, 1, SCREE[_rng.randi_range(0, SCREE.size() - 1)])
			elif roll < float(mix["scree"]) + float(mix["boulder"]):
				detail.set_cell(cell, 1, BOULDERS[_rng.randi_range(0, BOULDERS.size() - 1)])


func _zone_detail_mix(cell: Vector2i) -> Dictionary:
	if ZONE_LEDGE.has_point(cell):
		return {"scree": 0.18, "boulder": 0.05}
	if ZONE_SWITCHBACK.has_point(cell):
		return {"scree": 0.15, "boulder": 0.04}
	return {"scree": 0.11, "boulder": 0.02}


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
	# The player's camera node is named "Camera"; looking only for "Camera2D" meant this
	# clamp had never once applied, and the pass showed empty space past its own edges.
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		camera = player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = W * TILE
	camera.limit_bottom = H * TILE
	camera.reset_smoothing()


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x) / TILE, int(world_position.y) / TILE)
