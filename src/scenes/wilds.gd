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
##
## The region was widened south and east in 2026-08: the old 42x28 field was one flat green
## rectangle you could cross in seconds. It is now four readable zones — the arrival downs,
## the outpost clearing, the deep east woods, and the bamboo hollow — with scatter density,
## species and threat authored per zone rather than one uniform wash.

## Placement maths (trail brushes, the scatter lattice, clumping) is shared with the
## Mountain Pass. Preloaded rather than named globally, so a clean headless checkout does
## not depend on the editor's class cache having been rebuilt.
const Scatter = preload("res://src/systems/terrain_scatter.gd")
## Swaps Serene's flat grass fill for textured grass once the region has finished building.
const GroundCover = preload("res://src/systems/ground_cover.gd")

const TILE := 16
const W := 72   # tiles wide
const H := 50   # tiles tall
const GEN_SEED := 20260727   # fixed so the generated meadow is stable run-to-run

## Zones drive scatter density and species. Rects are in tiles and are tested in order, so
## the knoll wins inside the woods; anything unclaimed is the original outpost clearing.
const ZONE_KNOLL := Rect2i(54, 1, 18, 13)    # bare rocky rise holding the ore seams
const ZONE_WOODS := Rect2i(42, 0, 30, 30)    # deep east woods: shrubs, few blossoms
const ZONE_GROVE := Rect2i(32, 30, 40, 20)   # south-east bamboo hollow
const ZONE_DOWNS := Rect2i(0, 30, 32, 20)    # open arrival meadow from the village

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

# Fixed route waypoints, in tile coordinates. Each route carries its own width so the
# network reads as a hierarchy instead of one uniform brown ribbon: a walked main road,
# thinner spurs, and single-file hunting tracks that peter out in the woods.
## The north end runs all the way to the map edge — past the PassDoor's own tile — so
## the trail visibly leaves the region instead of petering out four tiles short of it,
## which read as "the road ends here" rather than "the road continues north".
const MAIN_ROUTE: Array[Vector2i] = [
	Vector2i(21, 49), Vector2i(21, 45), Vector2i(19, 40), Vector2i(20, 34),
	Vector2i(21, 30), Vector2i(21, 27), Vector2i(21, 23), Vector2i(20, 20),
	Vector2i(18, 15), Vector2i(19, 11), Vector2i(20, 5),
	Vector2i(20, 1),
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
## Into the new east woods, then north to the ore on the knoll. Single file: the woods are
## meant to feel like somewhere you push through, not somewhere a cart goes.
const WOODS_TRACK: Array[Vector2i] = [
	Vector2i(38, 18), Vector2i(45, 17), Vector2i(51, 14),
	Vector2i(55, 11), Vector2i(60, 8), Vector2i(63, 5),
]
const KNOLL_SPUR: Array[Vector2i] = [
	Vector2i(60, 8), Vector2i(64, 9), Vector2i(67, 7),
]
## The hollow track leaves the main road below the clearing and loops through the bamboo.
const HOLLOW_TRACK: Array[Vector2i] = [
	Vector2i(20, 34), Vector2i(28, 35), Vector2i(35, 37),
	Vector2i(42, 39), Vector2i(50, 41), Vector2i(56, 44),
	Vector2i(62, 45),
]
## A short walked loop around the arrival meadow, so the downs are not one straight run.
const DOWNS_LOOP: Array[Vector2i] = [
	Vector2i(21, 45), Vector2i(15, 44), Vector2i(11, 40),
	Vector2i(13, 36), Vector2i(19, 40),
]

# Complete, standalone Serene Village detail frames (source 1).
const MEADOW_FLOWERS: Array[Vector2i] = [
	Vector2i(2, 13), Vector2i(17, 24), Vector2i(17, 25), Vector2i(18, 25)]
const FLOWER_BEDS: Array[Vector2i] = [Vector2i(2, 14), Vector2i(18, 24)]
const SHRUB := Vector2i(7, 12)

# Woodland cover. The same real 16px-native props the landmarks in the .tscn use — the
# scatter only decides *where*, never what the art is.
const PROP_SCENE := preload("res://src/entities/prop.tscn")
const TREE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/props/tree_green.png"),
	preload("res://assets/props/tree_leafy.png"),
	preload("res://assets/props/tree_sakura.png"),
]
const ROCK_TEXTURE: Texture2D = preload("res://assets/props/rock.png")
const BUSH_TEXTURE: Texture2D = preload("res://assets/props/berry_bush.png")
## Trunk/base footprints, matching the hand-authored props in wilds.tscn exactly.
const TREE_FOOT := Vector2(10, 5)
const TREE_FOOT_OFFSET := Vector2(0, -2)
const ROCK_FOOT := Vector2(20, 8)
const ROCK_FOOT_OFFSET := Vector2(0, -3)
## Diagonal tiles of cover planted around each resource node so its siting reads as chosen.
const ANCHOR_COVER := 3

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities
var detail: TileMapLayer

var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}   # tiles under props/buildings — kept clear of detail
## Tiles a solid thing actually stands on. `_blocked` also carries the generous approach pad
## around doors and nodes, which is a reservation rather than an obstacle — anchoring cover
## to a node has to be able to use that reserved ring, and only this says what is truly taken.
var _prop_cells: Dictionary = {}
var _route_cells: Dictionary = {}


func _ready() -> void:
	Audio.play_music("forest")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_ground()
	_build_bounds()
	_mark_occupied()
	_scatter_cover()
	_anchor_resource_nodes()
	_build_detail()
	_texture_grass()
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


## Rasterize fixed waypoints with a per-route brush, then pick real edge/corner art from
## each cell's missing cardinal neighbours. Route cells also join `_blocked`, keeping grass
## tufts and flowers off the walked trail.
func _build_route() -> void:
	_route_cells.clear()
	_add_route(MAIN_ROUTE, 2)
	_add_route(OUTPOST_SPUR, 2)
	_add_route(EAST_HUNT_LOOP, 2)
	_add_route(DOWNS_LOOP, 1)
	_add_route(HOLLOW_TRACK, 1)
	_add_route(WOODS_TRACK, 1)
	_add_route(KNOLL_SPUR, 1)
	for raw_cell in _route_cells:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, _trail_tile(cell))
		_blocked[cell] = true


## `width` is the brush square in tiles. The waypoint cell itself is always stamped, so a
## door sitting on a waypoint is always reached however ragged the edges get.
func _add_route(waypoints: Array[Vector2i], width: int) -> void:
	for i in range(waypoints.size() - 1):
		for center in _raster_line(waypoints[i], waypoints[i + 1]):
			for cell in Scatter.brush_cells(center, width):
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
## base or a trunk, and so the tree scatter below has somewhere it must not build. Doors,
## spawn markers and the expedition gate get the widest pad: a 32px tree dropped next to a
## walk-in door would hide the way out and crowd its auto-enter radius.
func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		_mark_prop_tiles((e as Node2D).position, _occupancy_pad(e))


func _occupancy_pad(node: Node) -> int:
	var node_name := String(node.name)
	if node is Marker2D or node is Area2D or node_name.ends_with("Door"):
		return 3
	if node_name.begins_with("Outpost"):
		return 2
	return 1


func _mark_prop_tiles(position: Vector2, pad: int) -> void:
	var t := _to_tile(position)
	_prop_cells[t] = true
	for dx in range(-pad, pad + 1):
		for dy in range(-pad, pad + 1):
			_blocked[t + Vector2i(dx, dy)] = true


## Fill the new zones with real cover, using the same props the .tscn authors by hand — the
## scatter decides *where*, never what the art is. Candidates sit on a jittered two-tile
## lattice because the tree art is 32px: a one-tile lattice mats canopies into a wall, and a
## three-tile one reads as an orchard. Every candidate must clear the walked trail and any
## authored entity by a full tile, so cover never closes a route or crowds a landmark.
func _scatter_cover() -> void:
	# Trees and bushes clump; rocks stay incidental, so a thicket still has bare stone in
	# it and a glade is not swept perfectly clean.
	var clumped: Array[String] = ["tree", "bush"]
	for entry in Scatter.plan_cover(Vector2i(W, H), _blocked,
			_zone_cover_mix, clumped, GEN_SEED):
		var cell: Vector2i = entry["cell"]
		match String(entry["kind"]):
			"tree":
				_add_cover(cell, TREE_TEXTURES[_rng.randi() % TREE_TEXTURES.size()],
					true, TREE_FOOT, TREE_FOOT_OFFSET)
			"rock":
				_add_cover(cell, ROCK_TEXTURE, true, ROCK_FOOT, ROCK_FOOT_OFFSET)
			"bush":
				# Berry bushes are walk-through in the village; keep them so here.
				_add_cover(cell, BUSH_TEXTURE, false, Vector2.ZERO, Vector2.ZERO)


## Give every seam and patch a reason to be where it is: ore against stone, bamboo in a
## stand, rainleaf under cover. `plan_cover` holds a clear tile ring around everything in
## `_blocked` — resource nodes included — so the ground beside a node came out deliberately
## bare and the node read as dropped wherever the scatter left room. This is the corrective
## pass, and it runs after the scatter so it fills what the scatter was forbidden to.
##
## Only diagonals are used (see `Scatter.anchor_cells`), so all four straight approaches to
## a node stay walkable however much cover it gets.
func _anchor_resource_nodes() -> void:
	for node in _resource_nodes():
		for anchor in Scatter.anchor_cells(node.position, TILE, ANCHOR_COVER,
				Vector2i(W, H), _prop_cells, _route_cells):
			match String(node.get("resource_kind")):
				"ore":
					_add_cover(anchor, ROCK_TEXTURE, true, ROCK_FOOT, ROCK_FOOT_OFFSET)
				"bamboo":
					_add_cover(anchor, TREE_TEXTURES[_rng.randi() % TREE_TEXTURES.size()],
						true, TREE_FOOT, TREE_FOOT_OFFSET)
				"herb":
					_add_cover(anchor, BUSH_TEXTURE, false, Vector2.ZERO, Vector2.ZERO)


## Resource nodes are plain Area2Ds with no class of their own, so they are found by the
## export every one of them carries rather than by type.
func _resource_nodes() -> Array:
	var out: Array = []
	for candidate in find_children("*", "Area2D", true, false):
		if candidate.get("resource_kind") != null:
			out.append(candidate)
	return out


## Per-zone chance of a tree / a rock / a bush at any one lattice point, before clumping.
## The default is the outpost clearing: thin cover only, because its landmarks, yard and
## NPCs are hand-authored and the open ground in front of them is the region's arena.
func _zone_cover_mix(cell: Vector2i) -> Dictionary:
	if ZONE_KNOLL.has_point(cell):
		return {"tree": 0.05, "rock": 0.34, "bush": 0.02}
	if ZONE_WOODS.has_point(cell):
		return {"tree": 0.88, "rock": 0.06, "bush": 0.08}
	if ZONE_GROVE.has_point(cell):
		return {"tree": 0.46, "rock": 0.03, "bush": 0.20}
	if ZONE_DOWNS.has_point(cell):
		return {"tree": 0.14, "rock": 0.06, "bush": 0.16}
	return {"tree": 0.06, "rock": 0.03, "bush": 0.05}


func _add_cover(cell: Vector2i, texture: Texture2D, solid: bool,
		foot_size: Vector2, foot_offset: Vector2) -> void:
	var prop := PROP_SCENE.instantiate() as Prop
	if prop == null:
		push_error("wilds: prop.tscn did not instantiate as a Prop")
		return
	prop.texture = texture
	prop.solid = solid
	if solid:
		prop.foot_size = foot_size
		prop.foot_offset = foot_offset
	# Origin is the feet, so sit the prop on the bottom-centre of its tile.
	prop.position = Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE)
	entities.add_child(prop)
	# Its own tile only: neighbours stay open so trunks can stand two tiles apart and the
	# canopies actually touch, which is what makes the woods read as woods.
	_blocked[cell] = true
	_prop_cells[cell] = true


## Restrained meadow, but no longer one uniform wash: the arrival downs are the flowery
## ones, the woods floor trades blossoms for shrubs, and the knoll is nearly bare so the
## rock reads as rock. Then clustered wildflower patches and the flower bed framing the yard.
func _build_detail() -> void:
	for x in range(1, W - 1):
		for y in range(1, H - 1):
			var c := Vector2i(x, y)
			if _blocked.has(c):
				continue
			var mix := _zone_detail_mix(c)
			var roll := _rng.randf()
			if roll < float(mix["flower"]):
				_set_detail(c, MEADOW_FLOWERS[_rng.randi() % MEADOW_FLOWERS.size()])
			elif roll < float(mix["flower"]) + float(mix["shrub"]):
				_set_detail(c, SHRUB)

	# Wildflower patches — clustered so colour reads as beds, not confetti. They belong to
	# the open ground; the woods and the knoll are deliberately left out.
	for patch_zone in [ZONE_DOWNS, ZONE_GROVE, Rect2i(1, 1, 40, 28)]:
		for i in 5:
			var center := Vector2i(
				_rng.randi_range(patch_zone.position.x + 2, patch_zone.end.x - 3),
				_rng.randi_range(patch_zone.position.y + 2, patch_zone.end.y - 3))
			var species: Vector2i = FLOWER_BEDS[_rng.randi() % FLOWER_BEDS.size()]
			for j in _rng.randi_range(4, 7):
				var c := center + Vector2i(_rng.randi_range(-2, 2), _rng.randi_range(-1, 1))
				_set_detail(c, species)

	_build_outpost_yard()


## Per-zone chance of a blossom / a shrub on any one open tile.
func _zone_detail_mix(cell: Vector2i) -> Dictionary:
	if ZONE_KNOLL.has_point(cell):
		return {"flower": 0.01, "shrub": 0.02}
	if ZONE_WOODS.has_point(cell):
		return {"flower": 0.02, "shrub": 0.05}
	if ZONE_GROVE.has_point(cell):
		return {"flower": 0.11, "shrub": 0.03}
	if ZONE_DOWNS.has_point(cell):
		return {"flower": 0.10, "shrub": 0.01}
	return {"flower": 0.08, "shrub": 0.006}


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


## Last, so the detail and cover passes above still see the flat grass they key off.
func _texture_grass() -> void:
	GroundCover.repaint(ground, GRASS)


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
