extends SceneTree
## Every building door has a path worn to it.
##
##   godot --headless --path . --script res://tests/test_door_paths.gd
##
## The Wilds gate got a spur the day it was built; the house doors never did. Both village
## buildings stood on unbroken grass, so the only thing telling you a door was a door was
## walking into it. A door nobody has walked to does not read as one — the same reason
## tests/test_door_signage.gd exists for the region exits.
##
## Width is checked as well as presence. A spur stamped at the market road's full width is
## the "large rectangle of one centre tile" the level-design rule forbids; a household path
## should be narrower than the road it joins.

const WORLD := "res://src/scenes/world.tscn"
## Trail frames from the Serene Village sheet — the same list world.gd paints from.
const TRAIL_COORDS: Array[Vector2i] = [
	Vector2i(10, 2), Vector2i(9, 2), Vector2i(6, 2),
	Vector2i(7, 3), Vector2i(8, 3), Vector2i(7, 1), Vector2i(8, 1),
	Vector2i(5, 2), Vector2i(3, 2), Vector2i(5, 1), Vector2i(3, 1),
]

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var world: Node = load(WORLD).instantiate()
	root.add_child(world)
	for i in 8:
		await process_frame
	var ground: TileMapLayer = world.get_node("Ground")
	var tile: Vector2i = ground.tile_set.tile_size
	var layers: Array = []
	for child in world.get_children():
		if child is TileMapLayer:
			layers.append(child)

	var doors := 0
	for door in world.get_node("Props").get_children():
		if not (door is Node2D):
			continue
		var target: Variant = door.get("target_scene")
		if target == null or not String(target).contains("interior"):
			continue
		doors += 1
		var step := Vector2i(
			floori((door.position.x - ground.position.x) / tile.x),
			floori((door.position.y - ground.position.y) / tile.y))
		var name := String(door.name)
		check_true("%s has a path at its doorstep" % name,
			_trail_at(layers, Vector2i(step.x, step.y + 1)))
		check_true("%s's path leads somewhere (3+ tiles)" % name,
			_run_length(layers, step) >= 3)
		# The market road is three tiles wide; a doorstep is not a junction.
		check_true("%s's path is narrower than the road at the step" % name,
			_width_at(layers, Vector2i(step.x, step.y + 1)) <= 2)
	check_true("the village has building doors to check (%d)" % doors, doors >= 2)
	world.queue_free()
	_finish()


func _trail_at(layers: Array, cell: Vector2i) -> bool:
	for layer: TileMapLayer in layers:
		if layer.get_cell_source_id(cell) != -1 \
				and layer.get_cell_atlas_coords(cell) in TRAIL_COORDS:
			return true
	return false


func _run_length(layers: Array, step: Vector2i) -> int:
	var run := 0
	for dy in range(1, 16):
		if not _trail_at(layers, Vector2i(step.x, step.y + dy)):
			break
		run += 1
	return run


func _width_at(layers: Array, cell: Vector2i) -> int:
	var width := 0
	for dx in range(-3, 4):
		if _trail_at(layers, Vector2i(cell.x + dx, cell.y)):
			width += 1
	return width


func _finish() -> void:
	print("")
	print(("PASS — every building door has a path worn to it."
		if failures == 0 else "FAIL — %d door-path check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
