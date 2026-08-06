class_name World
extends Node2D
## A playable level: tile layers, props, and the player.
##
## Camera limits are derived from the Ground layer rather than baked into the
## scene, so resizing the map by hand in the editor cannot leave the camera
## clamped to stale bounds.

const GRASS_ATLAS := Vector2i(4, 0)   # serene_village grass tile in the Ground layer
const MEADOW_SEED := 20260728

# Complete, standalone Serene Village flower frames. These are native to the terrain sheet,
# unlike the old Sprout decals, so the village and its exposed edge underlay share one palette.
const MEADOW_FLOWERS: Array[Vector2i] = [
	Vector2i(2, 13), Vector2i(17, 24), Vector2i(17, 25), Vector2i(18, 25)]
const FLOWER_BEDS: Array[Vector2i] = [Vector2i(2, 14), Vector2i(18, 24)]

# Dirt trail frames from the same Serene Village sheet the Wilds trail uses, so the
# road out of the village and the road it becomes are literally the same road.
const TRAIL_CENTER := Vector2i(10, 2)
const TRAIL_LEFT := Vector2i(9, 2)
const TRAIL_RIGHT := Vector2i(6, 2)
const TRAIL_TOP: Array[Vector2i] = [Vector2i(7, 3), Vector2i(8, 3)]
const TRAIL_BOTTOM: Array[Vector2i] = [Vector2i(7, 1), Vector2i(8, 1)]
const TRAIL_TOP_LEFT := Vector2i(5, 2)
const TRAIL_TOP_RIGHT := Vector2i(3, 2)
const TRAIL_BOTTOM_LEFT := Vector2i(5, 1)
const TRAIL_BOTTOM_RIGHT := Vector2i(3, 1)

## Placement maths shared with the Wilds and the Mountain Pass. Preloaded rather than named
## globally, so a clean headless checkout does not depend on the editor's class cache.
const Scatter = preload("res://src/systems/terrain_scatter.gd")
## Swaps Serene's flat grass fill for textured grass once the region has finished building.
const GroundCover = preload("res://src/systems/ground_cover.gd")
## Animated ripples that break up the pond's solid blue fill.
const PondRipples = preload("res://src/entities/pond_ripples.gd")
## Serene's open-water centre frame. Only this one gets ripples: the bank frames are half
## shoreline, and a ripple drawn over one sits on the grass.
const WATER_CENTER := Vector2i(12, 1)
## Share of open-water tiles carrying a ripple. Enough that the surface is never still
## anywhere you look, sparse enough that it reads as water rather than as rain.
const RIPPLE_SHARE := 18

## How far the fields run east past the authored map. The market road used to reach the edge
## of the tile data and simply stop, which is what made the village read as cut off.
## How far the grass underlay runs past the map edge, in tiles.
const EDGE_MARGIN_TILES := 10
const OUTSKIRTS_TILES := 22
const OUTSKIRTS_SEED := 20260804

const PROP_SCENE := preload("res://src/entities/prop.tscn")
const OUTSKIRT_TREES: Array[Texture2D] = [
	preload("res://assets/props/tree_green.png"),
	preload("res://assets/props/tree_leafy.png"),
	preload("res://assets/props/tree_sakura.png"),
]
const OUTSKIRT_ROCK: Texture2D = preload("res://assets/props/rock.png")
const OUTSKIRT_BUSH: Texture2D = preload("res://assets/props/berry_bush.png")
const TREE_FOOT := Vector2(10, 5)
const ROCK_FOOT := Vector2(20, 8)
const BUSH_FOOT := Vector2(12, 6)
## Diagonal tiles of cover planted around each resource node so its siting reads as chosen.
const ANCHOR_COVER := 3
const PROP_FOOT_OFFSET := Vector2(0, -2)

@onready var ground: TileMapLayer = $Ground


func _ready() -> void:
	Audio.play_music("village")
	_build_east_outskirts()
	_weather_road_edges()
	_build_edge_underlay()
	_clamp_camera_to_map()
	_build_meadow()
	_build_south_spur()
	_build_door_spurs()
	_anchor_resource_nodes()
	_build_pond_ripples()
	_texture_grass()
	_order_ground_layers()
	_load_game()


## The authored market road is stamped as straight-sided rectangles of the centre tile: its
## two arms hold a uniform width for their whole run, which is the "large rectangle of one
## centre tile" the art rules forbid and the reason the village reads as stencilled.
##
## Rather than re-cutting hand-made tile data, the shoulder is worn outward in patches. Every
## grass tile touching the road is a candidate, decided by a hash of its 3x3 block so the
## widening arrives in bulges a few tiles long instead of a dotted fringe, and the whole road
## is then re-autotiled through the same `_trail_tile` the Wilds trail uses — so the new edges
## get real edge and corner art rather than more centre tile.
##
## Widening only, never narrowing: a road that loses cells can pinch shut or strand a door
## spur, while one that only gains them cannot. Grass is the only surface eaten, so the pond
## and the authored paths are untouched, and occupied tiles are skipped so no shoulder opens
## under a building. Both surfaces are walkable, so this cannot change where the player can go.
##
## Runs before the meadow, or the flower wash would already have been scattered onto tiles
## that are about to become road.
func _weather_road_edges() -> void:
	var trail_frames: Dictionary = {}
	for coord in _trail_coords():
		trail_frames[coord] = true

	var road: Dictionary = {}
	for cell in ground.get_used_cells():
		if trail_frames.has(ground.get_cell_atlas_coords(cell)):
			road[cell] = true
	if road.is_empty():
		return

	var blocked := _occupied_tiles()
	var used := ground.get_used_rect()
	var shoulder: Dictionary = {}
	for raw_cell in road:
		var cell: Vector2i = raw_cell
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var probe: Vector2i = cell + step
			if road.has(probe) or shoulder.has(probe) or blocked.has(probe):
				continue
			if not used.has_point(probe):
				continue
			if ground.get_cell_atlas_coords(probe) != GRASS_ATLAS:
				continue
			if _worn_shoulder(probe):
				shoulder[probe] = true
	for raw_cell in shoulder:
		road[raw_cell] = true
	for raw_cell in road:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, _trail_tile(road, cell))


## Hashed on the cell's 3x3 block, not the cell, so neighbours mostly agree and the shoulder
## comes out as a run of worn ground rather than single scattered tiles.
func _worn_shoulder(cell: Vector2i) -> bool:
	var block := Vector2i(floori(cell.x / 3.0), floori(cell.y / 3.0))
	var h: int = block.x * 374761393 + block.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h >> 5) % 100 < 24


## Put the generated ground layers in a deliberate stack, once, at the end.
##
## Each builder used to place its own layer with move_child and a literal index, which only
## worked for whichever one ran first: EdgeGround inserts at 0 and shifts everything after it,
## so the meadow's "move to 1" actually pushed Ground above it and the village's entire flower
## wash rendered behind the ground it decorates. Ordering here, after every layer exists, is
## the only version that cannot be invalidated by a later builder.
##
## Bottom to top: the underlay that hides the map edge, the ground, its flower wash, the two
## road spurs (a path laid over a flower must cover it), then the pond ripples. Everything
## after this in the child list -- Props and up -- keeps drawing over all of it.
func _order_ground_layers() -> void:
	var stack: Array[String] = ["EdgeGround", "Ground", "Meadow", "SouthRoad", "DoorPaths",
		"PondRipples"]
	var index := 0
	for layer_name in stack:
		var layer := get_node_or_null(NodePath(layer_name))
		if layer == null:
			continue
		move_child(layer, index)
		index += 1


## The pond centre tile is a solid blue fill and there is no textured water frame on the
## sheet. Water is the one surface that should be moving, so it is broken up with motion:
## the same 4-frame ripple the fishing spot uses, scattered over open water and phase-offset
## per tile so the pond does not blink in unison.
func _build_pond_ripples() -> void:
	var open_water: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) != WATER_CENTER:
			continue
		if absi(cell.x * 73856093 ^ cell.y * 19349663) % 100 < RIPPLE_SHARE:
			open_water.append(cell)
	if open_water.is_empty():
		return
	var ripples := PondRipples.new()
	ripples.name = "PondRipples"
	add_child(ripples)
	# Above Ground, below the y-sorted Props, so the player and the bank trees still draw over
	# the water they overlap. Ground's live index for the same reason as the meadow above.
	move_child(ripples, ground.get_index() + 1)
	ripples.build(open_water, ground.position)


## Everything above plants against the flat grass coord, so the grass is only re-textured
## once they have all run. The EdgeGround underlay shares the Ground TileSet, so it is
## repainted too or the map would sit on a flat green mat with a textured island on it.
func _texture_grass() -> void:
	GroundCover.repaint(ground, GRASS_ATLAS)
	var edge := get_node_or_null("EdgeGround") as TileMapLayer
	if edge != null:
		GroundCover.repaint(edge, GRASS_ATLAS)


## Fields east of town. The authored tile data stops dead at its own edge, so the market road
## ran east and ended in grey — the "cut off" edge. Rather than operating on a hand-made
## tilemap, the strip is painted into the Ground layer at runtime: `get_used_rect()` then
## grows on its own, so the camera clamp and the edge underlay follow without being told.
##
## Runs before the underlay and the clamp, and paints nothing the authored map already owns.
func _build_east_outskirts() -> void:
	if ground.tile_set == null:
		return
	var used := ground.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var first_new_x := used.end.x
	var last_new_x := first_new_x + OUTSKIRTS_TILES

	for x in range(first_new_x, last_new_x):
		for y in range(used.position.y, used.end.y):
			ground.set_cell(Vector2i(x, y), 0, GRASS_ATLAS)

	_continue_market_road(used, first_new_x, last_new_x)
	_enclose_outskirts(used, last_new_x)
	_plant_outskirts(used, first_new_x, last_new_x)


## Carry whatever the authored map has at its east edge — the market road — straight out
## into the fields, so the road leaves town instead of stopping at the tile data.
func _continue_market_road(used: Rect2i, first_new_x: int, last_new_x: int) -> void:
	var trail_frames: Dictionary = {}
	for coord in _trail_coords():
		trail_frames[coord] = true
	# The authored road stops three tiles short of its own data edge, so each row is scanned
	# back for the last trail tile. Matching the trail frames rather than "not grass" is what
	# keeps the pond — which also reaches the east side — from being mistaken for a road.
	var road_end: Dictionary = {}   # row -> east-most authored road tile
	var scan_limit: int = maxi(used.end.x - 8, used.position.x)
	for y in range(used.position.y, used.end.y):
		for x in range(used.end.x - 1, scan_limit - 1, -1):
			if trail_frames.has(ground.get_cell_atlas_coords(Vector2i(x, y))):
				road_end[y] = x
				break
	if road_end.is_empty():
		return

	# Register the trail frames on the authored TileSet's source, or set_cell draws nothing.
	var source := ground.tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return
	for coord in _trail_coords():
		if not source.has_tile(coord):
			source.create_tile(coord)

	# The track stops short of the hedgerow and ends among the fields. Running it to the
	# boundary would just move the "road that stops at nothing" problem further out.
	var track_end: int = last_new_x - 4
	var rows: Array[int] = []
	var join_x := 0
	for raw_row in road_end:
		rows.append(int(raw_row))
		join_x = maxi(join_x, int(road_end[raw_row]))
	rows.sort()
	var centre_row: int = rows[rows.size() / 2]

	var cells: Dictionary = {}
	# Two columns at the full market width, so the join reads as the same road...
	for y in rows:
		for x in range(int(road_end[y]), join_x + 3):
			cells[Vector2i(x, y)] = true
	# ...then it narrows to a farm track and wanders. Carrying all four market rows straight
	# out to the fields drew a stamped brown slab, which is the thing paths must never be.
	var waypoints: Array[Vector2i] = [
		Vector2i(join_x + 3, centre_row),
		Vector2i(join_x + 8, centre_row + 1),
		Vector2i((join_x + track_end) / 2, centre_row - 1),
		Vector2i(track_end, centre_row),
	]
	for i in waypoints.size() - 1:
		var width := 3 if i == 0 else 2
		for center in _raster_line(waypoints[i], waypoints[i + 1]):
			for cell in Scatter.brush_cells(center, width):
				cells[cell] = true

	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if cell.x <= int(road_end.get(cell.y, -1)):
			continue   # never repaint an authored tile; it only anchors the join
		if cell.x < used.position.x or cell.x >= last_new_x \
				or cell.y < used.position.y or cell.y >= used.end.y:
			continue
		ground.set_cell(cell, 0, _trail_tile(cells, cell))


## The village has no bounds body — town is held in by its own tree line and water. The new
## fields need their own edge, so they get a wall on three sides and a tree line drawn along
## it, which is what the player actually reads as "the fields end here".
func _enclose_outskirts(used: Rect2i, last_new_x: int) -> void:
	var tile: Vector2i = ground.tile_set.tile_size
	var bounds := StaticBody2D.new()
	bounds.name = "OutskirtBounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)

	var origin := ground.position
	var top := origin.y + used.position.y * tile.y
	var bottom := origin.y + used.end.y * tile.y
	var east := origin.x + last_new_x * tile.x
	# The authored Bounds box was built for the town alone and its east wall stands well
	# inside the new fields — leave it up and the fields render perfectly and cannot be
	# walked to. Retire it, and start the new north/south walls where it stood, so the
	# enclosure stays continuous instead of leaving a gap to walk out through.
	var west: float = minf(_retire_town_east_wall(), origin.x + used.end.x * tile.x)
	_add_bound(bounds, "East", Vector2(east + 4, (top + bottom) / 2.0),
		Vector2(8, bottom - top))
	_add_bound(bounds, "North", Vector2((west + east) / 2.0, top - 4),
		Vector2(east - west, 8))
	_add_bound(bounds, "South", Vector2((west + east) / 2.0, bottom + 4),
		Vector2(east - west, 8))


## Take down the town's east wall and report where it stood. It is found by shape rather
## than by node name: the authored bounds children carry generated names like
## "@CollisionShape2D@330", which are not something to depend on.
func _retire_town_east_wall() -> float:
	var bounds := get_node_or_null("Bounds") as StaticBody2D
	if bounds == null:
		return INF
	var east_wall: CollisionShape2D = null
	for child in bounds.get_children():
		var collision := child as CollisionShape2D
		if collision == null:
			continue
		var rectangle := collision.shape as RectangleShape2D
		if rectangle == null or rectangle.size.x >= rectangle.size.y:
			continue   # a north or south wall, not one of the side walls
		if east_wall == null or collision.position.x > east_wall.position.x:
			east_wall = collision
	if east_wall == null:
		return INF
	east_wall.disabled = true
	return east_wall.position.x


func _add_bound(parent: StaticBody2D, shape_name: String,
		position: Vector2, size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	collision.name = shape_name
	collision.position = position
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	parent.add_child(collision)


## Hedgerow along the new edge, then scattered cover through the fields, using the shared
## placement module and the same props the village already plants by hand.
func _plant_outskirts(used: Rect2i, first_new_x: int, last_new_x: int) -> void:
	var blocked := _occupied_tiles()
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) != GRASS_ATLAS:
			blocked[cell] = true   # the road and everything authored stay clear

	var rng := RandomNumberGenerator.new()
	rng.seed = OUTSKIRTS_SEED
	var size := Vector2i(last_new_x + 1, used.end.y)
	var mix := func(cell: Vector2i) -> Dictionary:
		if cell.x < first_new_x + 1 or cell.x > last_new_x - 1:
			return {}
		if cell.x >= last_new_x - 2:
			return {"tree": 0.9, "rock": 0.05, "bush": 0.02}   # the hedgerow edge
		return {"tree": 0.14, "rock": 0.05, "bush": 0.16}      # open field
	var clumped: Array[String] = ["tree", "bush"]
	for entry in Scatter.plan_cover(size, blocked, mix, clumped, OUTSKIRTS_SEED):
		var cell: Vector2i = entry["cell"]
		match String(entry["kind"]):
			"tree":
				_add_outskirt_prop(cell, OUTSKIRT_TREES[rng.randi() % OUTSKIRT_TREES.size()],
					true, TREE_FOOT)
			"rock":
				_add_outskirt_prop(cell, OUTSKIRT_ROCK, true, ROCK_FOOT)
			"bush":
				# Bushes block. Scenery the player walks straight through reads as a
				# painted-on decal rather than something growing in the field.
				_add_outskirt_prop(cell, OUTSKIRT_BUSH, true, BUSH_FOOT)


## Give the village's herb and bamboo patches the same reason to be where they are that the
## Wilds and the Pass now give theirs. `plan_cover` holds a clear ring around everything
## occupied, so the field nodes stood alone in mown grass; these plant cover touching them.
## Diagonals only, so all four straight approaches to a patch stay walkable.
func _anchor_resource_nodes() -> void:
	# Centre tiles only. `_occupied_tiles` pads every prop by a tile, and that pad is a
	# reservation rather than an obstacle — it is exactly the ring the cover needs to use.
	var blocked := _prop_centre_tiles()
	var tile: Vector2i = ground.tile_set.tile_size
	var used: Rect2i = ground.get_used_rect()
	for node in _resource_nodes():
		var local: Vector2 = node.position - ground.position
		for anchor in Scatter.anchor_cells(local, tile.x, ANCHOR_COVER,
				used.end, blocked, {}):
			match String(node.get("resource_kind")):
				"bamboo":
					_add_outskirt_prop(anchor,
						OUTSKIRT_TREES[anchor.x % OUTSKIRT_TREES.size()], true, TREE_FOOT)
				_:
					_add_outskirt_prop(anchor, OUTSKIRT_BUSH, true, BUSH_FOOT)
			blocked[anchor] = true


## The tile each authored prop actually stands on, with no approach padding.
func _prop_centre_tiles() -> Dictionary:
	var taken: Dictionary = {}
	var props := get_node_or_null("Props")
	if props == null:
		return taken
	var tile: Vector2i = ground.tile_set.tile_size
	for e in props.get_children():
		if not (e is Node2D) or e.name == "Player":
			continue
		taken[Vector2i(((e as Node2D).position - ground.position) / Vector2(tile))] = true
	return taken


## Resource nodes are plain Area2Ds with no class of their own, so they are found by the
## export every one of them carries rather than by type.
func _resource_nodes() -> Array:
	var out: Array = []
	for candidate in find_children("*", "Area2D", true, false):
		if candidate.get("resource_kind") != null:
			out.append(candidate)
	return out


func _add_outskirt_prop(cell: Vector2i, texture: Texture2D, solid: bool,
		foot_size: Vector2) -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	var prop := PROP_SCENE.instantiate() as Prop
	if prop == null:
		return
	prop.texture = texture
	prop.solid = solid
	if solid:
		prop.foot_size = foot_size
		prop.foot_offset = PROP_FOOT_OFFSET
	var tile: Vector2i = ground.tile_set.tile_size
	prop.position = ground.position + Vector2(
		cell.x * tile.x + tile.x / 2.0, (cell.y + 1) * tile.y)
	props.add_child(prop)


## The hand-authored Ground layer is intentionally offset to align its paths and water with
## the scene's buildings. Its old camera/bounds footprint still begins at world (0, 0), which
## exposed the gray clear colour along the north and west edges. Fill that footprint with the
## same licensed Serene Village grass beneath the authored map; this preserves every authored
## path while making the existing boundary tree line read as part of the world.
func _build_edge_underlay() -> void:
	var edge_ground := TileMapLayer.new()
	edge_ground.name = "EdgeGround"
	edge_ground.z_index = -10
	edge_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	edge_ground.tile_set = ground.tile_set
	# Ground is offset inside the scene, so a layer left at the origin paints the same cells
	# 89,21px away from them. The underlay was drawing as a rectangle visibly shifted off the
	# map corner; SouthRoad and DoorPaths already do this and line up because of it.
	edge_ground.position = ground.position
	# Grown past the map on every side. Aligning the layer above fixed where it draws but also
	# revealed what its old 89,21px offset had been hiding by accident: the authored tree line
	# west of the tile data stood on bare grey. The underlay exists to cover exactly that --
	# camera overshoot and props outside the ground rect -- so it is sized for the job instead
	# of matching the map exactly.
	var used := ground.get_used_rect().grow(EDGE_MARGIN_TILES)
	for x in range(used.position.x, used.end.x):
		for y in range(used.position.y, used.end.y):
			edge_ground.set_cell(Vector2i(x, y), 0, GRASS_ATLAS)
	add_child(edge_ground)
	move_child(edge_ground, 0)


## Texture the flat grass fields with a restrained wash of native Serene Village blossoms
## and a few clustered flower beds — placed ONLY on plain grass tiles
## and never under a prop/building. Purely decorative, generated on entry, so the authored
## .tscn stays untouched. Low density on purpose (Matthew: areas should not be dense).
func _build_meadow() -> void:
	var detail := TileMapLayer.new()
	detail.name = "Meadow"
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = preload("res://assets/tilesets/serene_village.png")
	src.texture_region_size = Vector2i(16, 16)
	var coords: Array[Vector2i] = []
	coords.append_array(MEADOW_FLOWERS)
	coords.append_array(FLOWER_BEDS)
	for c in coords:
		src.create_tile(c)
	ts.add_source(src, 0)
	detail.tile_set = ts
	# Same offset bug as the underlay: without this the flower wash is painted 89,21px from
	# the grass it is meant to decorate.
	detail.position = ground.position
	add_child(detail)
	# Anchored to Ground's live index, never a literal. It used to be moved to index 1 on the
	# assumption Ground sat at 0 -- but _build_edge_underlay has already inserted EdgeGround at
	# 0 by this point, so Ground is at 1 and this pushed it to 2, leaving the meadow BELOW the
	# ground that draws over it. The village's whole flower wash was invisible.
	move_child(detail, ground.get_index() + 1)

	var blocked := _occupied_tiles()
	var grass: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) == GRASS_ATLAS and not blocked.has(cell):
			grass.append(cell)

	var rng := RandomNumberGenerator.new()
	rng.seed = MEADOW_SEED
	# A light wash of tiny blossoms across open grass, plus a few larger accents.
	for cell in grass:
		var roll := rng.randf()
		if roll < 0.06:
			detail.set_cell(cell, 0, MEADOW_FLOWERS[rng.randi() % MEADOW_FLOWERS.size()])
		elif roll < 0.066:
			detail.set_cell(cell, 0, FLOWER_BEDS[rng.randi() % FLOWER_BEDS.size()])
	# a few clustered wildflower beds for colour (grass-only, skips blocked)
	for i in 8:
		if grass.is_empty():
			break
		var center: Vector2i = grass[rng.randi() % grass.size()]
		var species: Vector2i = FLOWER_BEDS[rng.randi() % FLOWER_BEDS.size()]
		for j in rng.randi_range(3, 6):
			var c := center + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
			if ground.get_cell_atlas_coords(c) == GRASS_ATLAS and not blocked.has(c):
				detail.set_cell(c, 0, species)

	_soften_path_edges(detail, blocked, rng)
	_build_house_yards(detail, blocked, rng)


## The authored path is a hard-edged stamp. Rather than re-cutting the tile data (risky
## surgery on a hand-made map), scatter growth along the grass side of every path border so
## the boundary reads as worn-in rather than stencilled.
func _soften_path_edges(detail: TileMapLayer, blocked: Dictionary, rng: RandomNumberGenerator) -> void:
	const NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) != GRASS_ATLAS or blocked.has(cell):
			continue
		# Grass touching something that isn't grass (path, water) = a border tile.
		var on_edge := false
		for n in NEIGHBOURS:
			var probe: Vector2i = cell + n
			if ground.get_cell_source_id(probe) != -1 \
					and ground.get_cell_atlas_coords(probe) != GRASS_ATLAS:
				on_edge = true
				break
		if on_edge and rng.randf() < 0.35:
			detail.set_cell(cell, 0, MEADOW_FLOWERS[rng.randi() % MEADOW_FLOWERS.size()])


## Each house gets a small tended yard — flower beds flanking the door — so the buildings
## read as someone's home rather than sprites dropped on grass. Anchored to the door
## markers so this stays correct if a house is ever moved.
func _build_house_yards(detail: TileMapLayer, blocked: Dictionary, rng: RandomNumberGenerator) -> void:
	var tile: Vector2i = ground.tile_set.tile_size
	for door_name in ["House1Door", "House2Door"]:
		var door := get_node_or_null("Props/" + door_name)
		if door == null:
			continue
		var base := Vector2i((door as Node2D).position / Vector2(tile))
		# Fixed offsets don't survive contact with a hand-authored map — the tiles beside a
		# door may be path, another prop's pad, or the house footprint itself. Search
		# outward instead and plant in the nearest usable grass on each side of the door,
		# so a yard appears wherever the house actually stands.
		for side in [-1, 1]:
			var planted := 0
			for dx in range(2, 6):
				for dy in range(-1, 4):
					if planted >= 3:
						break
					var c: Vector2i = base + Vector2i(side * dx, dy)
					if ground.get_cell_atlas_coords(c) == GRASS_ATLAS and not blocked.has(c) \
							and detail.get_cell_source_id(c) == -1:
						detail.set_cell(c, 0, FLOWER_BEDS[rng.randi() % FLOWER_BEDS.size()])
						planted += 1


## The south transition stood four tiles clear of the authored road, out on open grass —
## the way out of the village looked exactly like the field beside it, and an auto-enter
## door gives no warning before it fires. Lay a short spur from the road down through
## the gate to the map edge so the road visibly leaves town and the eye follows it out.
##
## Its own layer, sitting directly above Ground: the hand-authored Ground data is never
## rewritten, and the road is not mixed into the decorative Meadow layer, whose own
## placement is a separate matter. It shares Ground's transform because the authored
## Ground is deliberately offset from world origin — a layer left at (0, 0) lands most
## of a screen away from the tiles it was computed against.
##
## Only plain grass (or a hole in the authored map, where the grass underlay shows
## through) is painted, so this can never blot out an authored path, the pond, or a
## building. Anchored to the door, so moving the door moves the road. Waypoints, not a
## rectangle: the spur bends a tile west on the way down and the edge/corner art is
## chosen per cell, per the map rules on stamped paths.
func _build_south_spur() -> void:
	var door := get_node_or_null("Props/WildsPath") as Node2D
	if door == null or ground.tile_set == null:
		return
	var tile: Vector2i = ground.tile_set.tile_size
	var gate := Vector2i(
		floori((door.position.x - ground.position.x) / tile.x),
		floori((door.position.y - ground.position.y) / tile.y))
	# The bend sits above the gate, never on it: the posts flank the door, so the road
	# has to run straight through that row or the gap ends up half off the road.
	var waypoints: Array[Vector2i] = [
		gate + Vector2i(0, -7), gate + Vector2i(-1, -4),
		gate + Vector2i(0, -1), gate + Vector2i(0, 4),
	]

	# The stretch that overlaps the authored road stays in the cell set but is never
	# painted: it is what makes the topmost painted row pick a joining tile instead of
	# a grass-fringed edge, so the spur reads as the road continuing, not a new strip.
	var cells: Dictionary = {}
	for i in waypoints.size() - 1:
		for center in _raster_line(waypoints[i], waypoints[i + 1]):
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					cells[center + Vector2i(dx, dy)] = true

	var road := TileMapLayer.new()
	road.name = "SouthRoad"
	road.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	road.position = ground.position
	var src := TileSetAtlasSource.new()
	src.texture = preload("res://assets/tilesets/serene_village.png")
	src.texture_region_size = tile
	for c in _trail_coords():
		src.create_tile(c)
	var ts := TileSet.new()
	ts.tile_size = tile
	ts.add_source(src, 0)
	road.tile_set = ts
	add_child(road)
	move_child(road, ground.get_index() + 1)

	var used := ground.get_used_rect()
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if not used.has_point(cell):
			continue
		var source := ground.get_cell_source_id(cell)
		if source != -1 and ground.get_cell_atlas_coords(cell) != GRASS_ATLAS:
			continue
		road.set_cell(cell, 0, _trail_tile(cells, cell))


## A worn footpath from every building door out to the road it stands on.
##
## The Wilds gate has had a spur since it was built, but the house doors never did: both
## buildings sat on unbroken grass, so the only clue a door was a door was walking into it.
## A door nobody has worn a path to does not read as one.
##
## Width is deliberately not constant. The market road is three tiles, these run two where
## they meet it and narrow to one at the step, which is what a path used by one household
## looks like next to a road used by the village.
func _build_door_spurs() -> void:
	var props := get_node_or_null("Props")
	if props == null or ground.tile_set == null:
		return
	var tile: Vector2i = ground.tile_set.tile_size
	var used := ground.get_used_rect()
	var trail_frames: Dictionary = {}
	for coord in _trail_coords():
		trail_frames[coord] = true

	var cells: Dictionary = {}
	for door in props.get_children():
		if not (door is Node2D):
			continue
		var target: Variant = door.get("target_scene")
		if target == null or not String(target).contains("interior"):
			continue
		var step := Vector2i(
			floori((door.position.x - ground.position.x) / tile.x),
			floori((door.position.y - ground.position.y) / tile.y))
		var road_row := _road_row_below(step, used, trail_frames)
		if road_row < 0:
			continue
		# One tile wide at the doorstep, two once it is clear of the building.
		for y in range(step.y, road_row + 1):
			var width := 1 if y <= step.y + 1 else 2
			for cell in Scatter.brush_cells(Vector2i(step.x, y), width):
				cells[cell] = true
	if cells.is_empty():
		return

	var paths := TileMapLayer.new()
	paths.name = "DoorPaths"
	paths.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	paths.position = ground.position
	var src := TileSetAtlasSource.new()
	src.texture = preload("res://assets/tilesets/serene_village.png")
	src.texture_region_size = tile
	for c in _trail_coords():
		src.create_tile(c)
	var ts := TileSet.new()
	ts.tile_size = tile
	ts.add_source(src, 0)
	paths.tile_set = ts
	add_child(paths)
	move_child(paths, ground.get_index() + 1)

	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if not used.has_point(cell):
			continue
		# Never paint over authored ground that is already something — a road, the pond,
		# a yard. The spur only ever crosses plain grass.
		var source := ground.get_cell_source_id(cell)
		if source != -1 and ground.get_cell_atlas_coords(cell) != GRASS_ATLAS:
			continue
		paths.set_cell(cell, 0, _trail_tile(cells, cell))


## The row of the first road tile below a doorstep, or -1 if the door does not face one
## within a short walk — in which case it gets no spur rather than a path to nowhere.
func _road_row_below(step: Vector2i, used: Rect2i, trail_frames: Dictionary) -> int:
	for y in range(step.y + 1, mini(step.y + 14, used.end.y)):
		for dx in range(-2, 3):
			var probe := Vector2i(step.x + dx, y)
			if trail_frames.has(ground.get_cell_atlas_coords(probe)):
				return y
	return -1


func _trail_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = [
		TRAIL_CENTER, TRAIL_LEFT, TRAIL_RIGHT,
		TRAIL_TOP_LEFT, TRAIL_TOP_RIGHT, TRAIL_BOTTOM_LEFT, TRAIL_BOTTOM_RIGHT,
	]
	coords.append_array(TRAIL_TOP)
	coords.append_array(TRAIL_BOTTOM)
	return coords


## Integer Bresenham, so a diagonal segment stays connected without float rounding.
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


## Bit flags mean the route is open (missing) on that side: top=1, right=2, bottom=4,
## left=8 — the same selection the Wilds trail uses, so both roads bend identically.
func _trail_tile(cells: Dictionary, cell: Vector2i) -> Vector2i:
	var open_mask := 0
	if not cells.has(cell + Vector2i.UP):
		open_mask |= 1
	if not cells.has(cell + Vector2i.RIGHT):
		open_mask |= 2
	if not cells.has(cell + Vector2i.DOWN):
		open_mask |= 4
	if not cells.has(cell + Vector2i.LEFT):
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
	# Restore the bag BEFORE the early return: a save can legitimately hold items and coins
	# without a player placement, and dropping them would silently delete quest progress
	# (quest completion is measured from what you are carrying).
	var bag: Dictionary = placement.get("inventory", {})
	if not bag.is_empty():
		Inv.load_dict(bag)
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
	SaveGame.save_snapshot(learning_data, pos, facing, Inv.to_dict())


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
