@tool
extends SceneTree
## Generator for the starting village terrain, using the Serene Village tileset
## with corner-Wang autotiling so paths and the pond get clean, seam-free edges.
##
##   godot --headless --path . --script res://tools/gen_starting_level.gd
##
## Why corner-Wang: this tileset is a Pokemon-style autotile where each transition
## tile is defined by which of its 4 CORNERS are the "inside" terrain. The tile
## atlas coords below were found by pixel-sampling every tile's four corners (see
## the scratchpad scans). A few combinations aren't drawn in the sheet and are
## produced by flipping/transposing an existing tile — the artist expects that.
##
## The output world.tscn is meant to be hand-edited in Godot from here; re-running
## overwrites it. Terrain only for now; buildings/props come next.

const TILESET_PATH := "res://assets/tilesets/village_tileset.tres"
const WORLD_PATH := "res://src/scenes/world.tscn"
const SHEET := "res://assets/tilesets/serene_village.png"

const TILE := 16
const MAP_W := 44
const MAP_H := 30
const GRASS := Vector2i(4, 0)

# Prop crops from the Serene Village sheet, in pixels (found by the grid render).
# [region, footprint_size, footprint_offset_from_base] — the sprite draws in full
# but collision is only the solid base, per the map rules.
const TREE_GREEN := Rect2i(144, 208, 32, 32)
const TREE_TEAL := Rect2i(208, 208, 32, 32)
const HOUSE_RED := Rect2i(144, 336, 80, 64)

# Transform flags for placing a mirrored/transposed tile without a separate atlas
# entry. OR-ed into the alternative_tile arg of set_cell.
const FH := TileSetAtlasSource.TRANSFORM_FLIP_H
const FV := TileSetAtlasSource.TRANSFORM_FLIP_V
const TR := TileSetAtlasSource.TRANSFORM_TRANSPOSE

# --- grass/DIRT corner-Wang: "TLTRBLBR" (D=dirt inside, G=grass) -> [atlas, xform]
# From the clean dark-dirt block (cols 3-10). Left/right edges are transposes of
# the top/bottom edges; the BR outer corner is a 180-degree flip of the TL corner.
const DIRT := {
	"GGGG": [Vector2i(4, 0), 0],
	"DGGG": [Vector2i(3, 1), 0],           # TL outer corner
	"GDGG": [Vector2i(5, 1), 0],           # TR outer corner
	"GGDG": [Vector2i(10, 3), 0],          # BL outer corner
	"GGGD": [Vector2i(3, 1), FH | FV],     # BR outer corner (180 of TL)
	"DDGG": [Vector2i(7, 1), 0],           # top edge
	"GGDD": [Vector2i(3, 2), 0],           # bottom edge
	"DGDG": [Vector2i(7, 1), TR],          # left edge (transpose of top)
	"GDGD": [Vector2i(3, 2), TR],          # right edge (transpose of bottom)
	"DDDG": [Vector2i(6, 1), 0],           # inner corner, grass notch BR
	"DDGD": [Vector2i(9, 1), 0],           # inner corner, grass notch BL
	"DGDD": [Vector2i(6, 2), 0],           # inner corner, grass notch TR
	"GDDD": [Vector2i(9, 2), 0],           # inner corner, grass notch TL
	"DDDD": [Vector2i(10, 2), 0],          # interior
	"DGGD": [Vector2i(10, 2), 0],          # diagonal (rare) -> interior fallback
	"GDDG": [Vector2i(10, 2), 0],
}

# --- grass/WATER corner-Wang: "TLTRBLBR" (W=water inside, G=grass) -> [atlas, xform]
const WATER := {
	"GGGG": [Vector2i(4, 0), 0],
	"WGGG": [Vector2i(13, 2), 0],          # TL outer corner
	"GWGG": [Vector2i(11, 2), 0],          # TR outer corner
	"GGWG": [Vector2i(11, 2), FH | FV],    # BL outer corner
	"GGGW": [Vector2i(13, 2), FH | FV],    # BR outer corner
	"WWGG": [Vector2i(12, 2), 0],          # top edge
	"GGWW": [Vector2i(17, 6), 0],          # bottom edge
	"WGWG": [Vector2i(14, 1), 0],          # left edge
	"GWGW": [Vector2i(14, 0), 0],          # right edge
	"GWWW": [Vector2i(18, 6), 0],          # inner corner, grass notch TL
	"WGWW": [Vector2i(16, 6), 0],          # inner corner, grass notch TR
	"WWGW": [Vector2i(18, 6), FV],         # inner corner, grass notch BL
	"WWWG": [Vector2i(16, 6), FV],         # inner corner, grass notch BR
	"WWWW": [Vector2i(12, 1), 0],          # interior
	"GWWG": [Vector2i(12, 1), 0],          # diagonal (rare) -> interior fallback
	"WGGW": [Vector2i(12, 1), 0],
}

# Water atlas tiles that block movement: >=2 water corners (interior, straight
# edges, inner corners). Outer corners (1 water corner) are walkable shoreline.
const WATER_SOLID := [
	Vector2i(12, 1), Vector2i(12, 2), Vector2i(17, 6),
	Vector2i(14, 0), Vector2i(14, 1), Vector2i(18, 6), Vector2i(16, 6),
]

var _dirt_corner := {}    # Vector2i corner -> true
var _water_corner := {}


func _initialize() -> void:
	var tileset := _build_tileset()
	if ResourceSaver.save(tileset, TILESET_PATH) != OK:
		push_error("tileset save failed"); quit(1); return
	print("wrote %s" % TILESET_PATH)
	if _build_world(tileset) != OK:
		quit(1); return
	print("wrote %s" % WORLD_PATH)
	quit(0)


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()

	var source := TileSetAtlasSource.new()
	source.texture = load(SHEET)
	source.texture_region_size = Vector2i(TILE, TILE)

	# Register every atlas coord any Wang entry references (unique set).
	var coords := {}
	for table in [DIRT, WATER]:
		for key in table:
			coords[table[key][0]] = true
	for c in coords:
		source.create_tile(c)
	tileset.add_source(source, 0)

	# Full-tile collision for solid water tiles (added after the source joins the
	# set, or TileData has no physics layer to attach to).
	var full := PackedVector2Array([
		Vector2(-TILE / 2.0, -TILE / 2.0), Vector2(TILE / 2.0, -TILE / 2.0),
		Vector2(TILE / 2.0, TILE / 2.0), Vector2(-TILE / 2.0, TILE / 2.0),
	])
	for c in WATER_SOLID:
		var data := source.get_tile_data(c, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, full)
	return tileset


func _build_world(tileset: TileSet) -> int:
	# --- author the terrain shapes at the corner-grid level ---
	# Pond tucked into the NE corner, clear of the roads.
	_paint_pond(Vector2i(37, 6), 5, 3)
	# Main east-west road, and a north road out of the village to the torii gate.
	_paint_path_h(3, 40, 19, 3)
	_paint_path_v(19, 6, 19, 3)

	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.set_script(load("res://src/scenes/world.gd"))

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for y in MAP_H:
		for x in MAP_W:
			_place_cell(ground, Vector2i(x, y))
	world.add_child(ground)

	var bootstrap := Node.new()
	bootstrap.name = "Bootstrap"
	bootstrap.set_script(load("res://src/scenes/harness_bootstrap.gd"))
	world.add_child(bootstrap)

	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true

	# Two cottages along the north side of the main road.
	_add_prop(props, HOUSE_RED, Vector2(11 * TILE, 17 * TILE), Vector2(64, 22), Vector2(0, -11))
	_add_prop(props, HOUSE_RED, Vector2(33 * TILE, 17 * TILE), Vector2(64, 22), Vector2(0, -11))

	# Trees: a soft perimeter plus a few clusters, kept off the roads and pond.
	for spot in _tree_spots():
		var region: Rect2i = TREE_TEAL if (spot.x + spot.y) % 3 == 0 else TREE_GREEN
		_add_prop(props, region, Vector2(spot.x * TILE + TILE / 2.0, spot.y * TILE + TILE),
			Vector2(8, 5), Vector2(0, -2))

	# The torii recall gate at the north end of the road — the way out of town.
	var gate: Node2D = load("res://src/entities/lesson_gate.tscn").instantiate()
	gate.gate_id = "north_torii"
	gate.required_lesson = "kana-vowels"
	gate.required_level = 1
	gate.fail_message = "The gate hums. Recall your kana to pass."
	gate.position = Vector2(19 * TILE + TILE / 2.0, 6 * TILE + TILE)
	props.add_child(gate)
	world.add_child(props)

	world.add_child(_build_bounds())

	var player: Node2D = load("res://src/entities/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(19 * TILE, 24 * TILE)
	world.add_child(player)

	world.add_child(load("res://src/ui/ui_layer.tscn").instantiate())

	_claim(world, world)
	var packed := PackedScene.new()
	if packed.pack(world) != OK:
		push_error("pack failed"); return FAILED
	return ResourceSaver.save(packed, WORLD_PATH)


# --- corner-grid shape authoring ------------------------------------------

## A grid corner is "in" a terrain if any of the 4 cells touching it is marked.
## Painting works on CELLS; the resolver reads corners, so terrain edges land
## half a tile outside the painted cells — the standard corner-Wang behavior.
func _mark_cell_dirt(cell: Vector2i) -> void:
	for corner in _cell_corners(cell):
		_dirt_corner[corner] = true

func _mark_cell_water(cell: Vector2i) -> void:
	for corner in _cell_corners(cell):
		_water_corner[corner] = true

func _cell_corners(cell: Vector2i) -> Array:
	return [cell, cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(1, 1)]


func _paint_path_h(x0: int, x1: int, y_center: int, width: int) -> void:
	var half := width / 2
	for x in range(x0, x1 + 1):
		# A gentle wander so the road doesn't read as a stamped rectangle.
		var cy := y_center + int(round(sin(x * 0.3) * 0.8))
		for i in range(-half, half + 1):
			_mark_cell_dirt(Vector2i(x, cy + i))

func _paint_path_v(x_center: int, y0: int, y1: int, width: int) -> void:
	var half := width / 2
	for y in range(y0, y1 + 1):
		var cx := x_center + int(round(sin(y * 0.3) * 0.8))
		for i in range(-half, half + 1):
			_mark_cell_dirt(Vector2i(cx + i, y))

func _paint_pond(center: Vector2i, rx: int, ry: int) -> void:
	for y in range(center.y - ry - 1, center.y + ry + 2):
		for x in range(center.x - rx - 1, center.x + rx + 2):
			var dx := float(x - center.x) / rx
			var dy := float(y - center.y) / ry
			if dx * dx + dy * dy <= 1.0:
				_mark_cell_water(Vector2i(x, y))


func _place_cell(ground: TileMapLayer, cell: Vector2i) -> void:
	var tl := cell
	var tr := cell + Vector2i(1, 0)
	var bl := cell + Vector2i(0, 1)
	var br := cell + Vector2i(1, 1)

	# Water wins over dirt where they'd meet (they're authored not to overlap).
	if _water_corner.has(tl) or _water_corner.has(tr) or _water_corner.has(bl) or _water_corner.has(br):
		var sig := _sig(_water_corner, tl, tr, bl, br, "W")
		_put(ground, cell, WATER, sig)
	elif _dirt_corner.has(tl) or _dirt_corner.has(tr) or _dirt_corner.has(bl) or _dirt_corner.has(br):
		var sig := _sig(_dirt_corner, tl, tr, bl, br, "D")
		_put(ground, cell, DIRT, sig)
	else:
		ground.set_cell(cell, 0, GRASS)


func _sig(grid: Dictionary, tl: Vector2i, tr: Vector2i, bl: Vector2i, br: Vector2i, inside: String) -> String:
	return (inside if grid.has(tl) else "G") + (inside if grid.has(tr) else "G") \
		+ (inside if grid.has(bl) else "G") + (inside if grid.has(br) else "G")


func _put(ground: TileMapLayer, cell: Vector2i, table: Dictionary, sig: String) -> void:
	var entry: Array = table.get(sig, table["GGGG"])
	ground.set_cell(cell, 0, entry[0], entry[1])


## A world prop: draws the full sprite but collides only on its solid base. The
## sprite's origin is its base center (feet), so Y-sort tucks the player behind it
## correctly. `body_offset` nudges the collision rect relative to that base.
func _add_prop(parent: Node2D, region: Rect2i, base_pos: Vector2, body_size: Vector2, body_offset: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = base_pos
	body.y_sort_enabled = true

	var atlas := AtlasTexture.new()
	atlas.atlas = load(SHEET)
	atlas.region = region
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -region.size.y / 2.0)   # base at the node origin
	body.add_child(sprite)

	var shape := RectangleShape2D.new()
	shape.size = body_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = body_offset
	body.add_child(collider)

	parent.add_child(body)


## Tree cells: a loose perimeter ring plus a couple of clusters. Anything on a
## road, in the pond, or under a house is skipped so nothing blocks a route.
func _tree_spots() -> Array:
	var spots: Array = []
	var blocked := func(c: Vector2i) -> bool:
		return _dirt_corner.has(c) or _water_corner.has(c) \
			or _dirt_corner.has(c + Vector2i(1, 1)) or _water_corner.has(c + Vector2i(1, 1))
	# Perimeter ring, 2 in from the edge, spaced out.
	for x in range(2, MAP_W - 1, 3):
		for y in [2, MAP_H - 3]:
			spots.append(Vector2i(x, y))
	for y in range(4, MAP_H - 3, 3):
		for x in [2, MAP_W - 3]:
			spots.append(Vector2i(x, y))
	# A couple of small groves.
	for c in [Vector2i(7, 11), Vector2i(8, 12), Vector2i(26, 11), Vector2i(27, 12),
			Vector2i(14, 24), Vector2i(24, 25)]:
		spots.append(c)
	return spots.filter(func(c): return not blocked.call(c) \
		and c.x >= 1 and c.y >= 1 and c.x < MAP_W - 1 and c.y < MAP_H - 1)


func _build_bounds() -> StaticBody2D:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	var w := MAP_W * TILE
	var h := MAP_H * TILE
	var t := 8.0
	for wall: Array in [
		[Vector2(w / 2.0, -t / 2.0), Vector2(w, t)],
		[Vector2(w / 2.0, h + t / 2.0), Vector2(w, t)],
		[Vector2(-t / 2.0, h / 2.0), Vector2(t, h)],
		[Vector2(w + t / 2.0, h / 2.0), Vector2(t, h)],
	]:
		var shape := RectangleShape2D.new()
		shape.size = wall[1]
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = wall[0]
		bounds.add_child(collider)
	return bounds


func _claim(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = root
		if child.scene_file_path.is_empty():
			_claim(child, root)
