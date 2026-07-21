@tool
extends SceneTree
## One-shot generator for the minimal test HARNESS (not a designed level).
##
##   godot --headless --path . --script res://tools/gen_test_scene.gd
##
## Its only job is to give the game something to boot into so the Slice-3 recall
## loop can be hand-tested: a flat floor, walls to stay inside, the player, one
## recall gate, and the UI layer. No path, pond, or props — level design and
## generated (nano/AI) art are deliberately out of scope. Uses only licensed art
## (the serene_village grass tile) plus engine-drawn placeholders.

const TILESET_PATH := "res://assets/tilesets/village_tileset.tres"
const WORLD_PATH := "res://src/scenes/world.tscn"
const SHEET := "res://assets/tilesets/serene_village.png"

const TILE := 16
const MAP_W := 32
const MAP_H := 22
const GRASS := Vector2i(4, 0)   # a uniform grass tile, verified by pixel scan


func _initialize() -> void:
	var tileset := _build_tileset()
	if ResourceSaver.save(tileset, TILESET_PATH) != OK:
		push_error("failed to save tileset")
		quit(1)
		return
	print("wrote %s" % TILESET_PATH)

	if _build_world(tileset) != OK:
		quit(1)
		return
	print("wrote %s" % WORLD_PATH)
	quit(0)


## Grass-only tileset. No physics layer: the only collision in the harness comes
## from the boundary walls, so tiles need none.
func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load(SHEET)
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(GRASS)
	tileset.add_source(source, 0)
	return tileset


func _build_world(tileset: TileSet) -> int:
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
			ground.set_cell(Vector2i(x, y), 0, GRASS)
	world.add_child(ground)

	# Bootstrap: make the starter lesson available so the gate is studyable.
	var bootstrap := Node.new()
	bootstrap.name = "Bootstrap"
	bootstrap.set_script(load("res://src/scenes/harness_bootstrap.gd"))
	world.add_child(bootstrap)

	# Props holds Y-sorted entities (just the gate here).
	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true

	var gate: Node2D = load("res://src/entities/lesson_gate.tscn").instantiate()
	gate.gate_id = "north_torii"
	gate.required_lesson = "kana-vowels"
	gate.required_level = 1
	gate.fail_message = "The gate hums. Recall your kana to pass."
	gate.position = Vector2(16 * TILE + TILE / 2.0, 8 * TILE + TILE)
	props.add_child(gate)
	world.add_child(props)

	world.add_child(_build_bounds())

	var player: Node2D = load("res://src/entities/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(16 * TILE, 13 * TILE)
	world.add_child(player)

	# UI: recall panel, dialogue box, toast (Bus-driven CanvasLayers).
	world.add_child(load("res://src/ui/ui_layer.tscn").instantiate())

	_claim(world, world)
	var packed := PackedScene.new()
	if packed.pack(world) != OK:
		push_error("failed to pack world")
		return FAILED
	return ResourceSaver.save(packed, WORLD_PATH)


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


## PackedScene only saves nodes owned by the root; instanced subtrees keep their
## own ownership, so claim each node but don't recurse into instanced scenes.
func _claim(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = root
		if child.scene_file_path.is_empty():
			_claim(child, root)
