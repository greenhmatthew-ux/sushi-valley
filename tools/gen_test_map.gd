@tool
extends SceneTree
## One-shot generator for the Slice 1 test map and its TileSet.
##
##   godot --headless --path . --script res://tools/gen_test_map.gd
##
## This exists because the map had to be built without a GUI. The output is a
## normal TileSet resource and a normal .tscn — both are meant to be edited by
## hand in the Godot editor from here on. This is a PLACEHOLDER whose only job is
## to prove movement, collision, Y-sort, and camera limits. Real level design is
## Slice 11; re-running this will overwrite hand edits.

const TILESET_PATH := "res://assets/tilesets/village_tileset.tres"
const WORLD_PATH := "res://src/scenes/world.tscn"
const SHEET := "res://assets/tilesets/serene_village.png"

const TILE := 16
const MAP_W := 40
const MAP_H := 30

# Atlas coordinates in serene_village.png, verified by scanning every tile in the
# sheet for 100%-uniform colour rather than eyeballing the image.
#
# No grass/dirt transition tiles are used. The sheet's transition set draws a
# small grass ISLAND on dirt, so every one of its edge tiles carries grass in the
# corners; tiling them along a straight run leaves grass gaps between each tile
# and the path renders as a comb. Until a proper terrain set is authored (Slice
# 11), the path is pure dirt with a deliberately irregular outline.
#
# The other uniform "dirt" tiles the scan found — (17,3), (17,4), (17,5) — match
# on hue but are a paler striped material, not a speckle variant of this dirt.
# Mixing them in read as debris scattered over the path, so the path is one tile
# and gets its variety from its outline instead.
const GRASS := Vector2i(4, 0)
const DIRT := Vector2i(10, 2)
const WATER := Vector2i(9, 5)           # uniform deep water; the only solid tile

const SOLID_TILES: Array[Vector2i] = [WATER]
const ALL_TILES: Array[Vector2i] = [GRASS, DIRT, WATER]


func _initialize() -> void:
	var tileset := _build_tileset()
	var err := ResourceSaver.save(tileset, TILESET_PATH)
	if err != OK:
		push_error("failed to save tileset: %d" % err)
		quit(1)
		return
	print("wrote %s" % TILESET_PATH)

	err = _build_world(tileset)
	if err != OK:
		quit(1)
		return
	print("wrote %s" % WORLD_PATH)
	quit(0)


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()

	var source := TileSetAtlasSource.new()
	source.texture = load(SHEET)
	source.texture_region_size = Vector2i(TILE, TILE)

	for coords in ALL_TILES:
		source.create_tile(coords)

	# The source must join the TileSet BEFORE any collision is set: TileData reads
	# its physics layers from the parent TileSet, so setting collision on a
	# detached source silently fails with "layer 0 out of bounds".
	tileset.add_source(source, 0)

	# Water blocks movement. The collision polygon is the full tile because water
	# tiles ARE fully solid — unlike props, whose collision must match the visual
	# footprint rather than the art bounds.
	var full_tile := PackedVector2Array([
		Vector2(-TILE / 2.0, -TILE / 2.0),
		Vector2(TILE / 2.0, -TILE / 2.0),
		Vector2(TILE / 2.0, TILE / 2.0),
		Vector2(-TILE / 2.0, TILE / 2.0),
	])
	for coords in SOLID_TILES:
		var data := source.get_tile_data(coords, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, full_tile)

	return tileset


func _build_world(tileset: TileSet) -> int:
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.set_script(load("res://src/scenes/world.gd"))

	# --- ground: grass everywhere, with a dirt path crossing it ---
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	for y in MAP_H:
		for x in MAP_W:
			ground.set_cell(Vector2i(x, y), 0, GRASS)

	# A path with a varying width and a bend, so it reads as placed rather than
	# stamped as one rectangle of centre tiles.
	_carve_path(ground)

	# --- water: a pond in the north-east. Its own layer because it is solid. ---
	var water := TileMapLayer.new()
	water.name = "Water"
	water.tile_set = tileset
	water.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for y in range(4, 10):
		for x in range(27, 36):
			# Rounded corners so the pond is not a hard rectangle.
			var corner := (y == 4 or y == 9) and (x == 27 or x == 35)
			if not corner:
				water.set_cell(Vector2i(x, y), 0, WATER)

	world.add_child(ground)
	world.add_child(water)

	# --- props: trees, Y-sorted so the player can walk behind their canopies ---
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	var tree_scene: PackedScene = load("res://src/entities/tree_oak.tscn")
	# Placed clear of the path and the pond, per the "props must not block obvious
	# walkable routes" rule.
	for spot in [
		Vector2i(6, 6), Vector2i(10, 5), Vector2i(15, 8), Vector2i(5, 20),
		Vector2i(12, 23), Vector2i(20, 25), Vector2i(30, 20), Vector2i(34, 24),
		Vector2i(24, 4), Vector2i(8, 13),
	]:
		var tree := tree_scene.instantiate()
		# +TILE puts the trunk base on the tile's bottom edge, where its feet are.
		tree.position = Vector2(spot.x * TILE + TILE / 2.0, spot.y * TILE + TILE)
		props.add_child(tree)
	world.add_child(props)

	# --- bounds: keep the player on the map ---
	world.add_child(_build_bounds())

	# --- player ---
	var player: Node2D = load("res://src/entities/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(20 * TILE, 16 * TILE)
	world.add_child(player)

	# Camera limits are NOT set here: world.gd derives them from the Ground layer
	# at runtime, so they stay correct when the map is resized by hand.

	# Every node must be owned by the scene root or it will not be saved.
	_claim(world, world)

	var packed := PackedScene.new()
	var err := packed.pack(world)
	if err != OK:
		push_error("failed to pack world: %d" % err)
		return err
	return ResourceSaver.save(packed, WORLD_PATH)


## Dirt path: runs east-west across the middle, then turns south at the junction.
## Both the width and the centre-line wander a little, so it reads as a worn track
## rather than a stamped rectangle of one centre tile.
func _carve_path(ground: TileMapLayer) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260721   # fixed, so regenerating gives the same map

	# East-west leg.
	for x in range(2, 26):
		var centre := 15 + int(round(sin(x * 0.35) * 1.0))
		var width := 3 + (1 if rng.randf() < 0.25 else 0)
		for i in width:
			_set_dirt(ground, Vector2i(x, centre + i - 1))

	# North-south leg, branching south from the junction.
	for y in range(15, MAP_H - 2):
		var centre := 23 + int(round(sin(y * 0.3) * 1.0))
		var width := 3 + (1 if rng.randf() < 0.25 else 0)
		for i in width:
			_set_dirt(ground, Vector2i(centre + i - 1, y))


func _set_dirt(ground: TileMapLayer, cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= MAP_W or cell.y >= MAP_H:
		return
	ground.set_cell(cell, 0, DIRT)


func _build_bounds() -> StaticBody2D:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	var w := MAP_W * TILE
	var h := MAP_H * TILE
	var thickness := 8.0
	# [centre, size] for the four walls, placed just outside the playable area.
	for wall: Array in [
		[Vector2(w / 2.0, -thickness / 2.0), Vector2(w, thickness)],
		[Vector2(w / 2.0, h + thickness / 2.0), Vector2(w, thickness)],
		[Vector2(-thickness / 2.0, h / 2.0), Vector2(thickness, h)],
		[Vector2(w + thickness / 2.0, h / 2.0), Vector2(thickness, h)],
	]:
		var shape := RectangleShape2D.new()
		shape.size = wall[1]
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = wall[0]
		bounds.add_child(collider)
	return bounds


## PackedScene only saves nodes owned by the root, and instantiated subtrees keep
## their own internal ownership — so claim the node but do not recurse into it.
func _claim(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = root
		if child.scene_file_path.is_empty():
			_claim(child, root)
