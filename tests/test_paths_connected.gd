extends SceneTree
## Guard: a region's trail network is ONE connected ribbon, not scraps of path tile.
##
##   godot --headless --path . --script res://tests/test_paths_connected.gd
##
## Matthew, on a screenshot of the Wilds: "stop with broken pathing". Measured, the Wilds
## trail was 282 cells in THIRTY-FIVE components -- a 199-cell main road plus 34 floating
## fragments sitting in open grass with nothing leading to them. The Mountain Pass had 27.
## Every other suite was green, because nothing had ever asked whether a path went anywhere.
##
## Both faults come out of the brush-and-hash rasteriser: the outer band is dropped on a hash
## so edges look walked (which can sever a cell), and a diagonal step joins two cells
## corner-to-corner, which is not walkable and does not read as a path. Scatter.repair_route
## fixes both; this stops it silently coming back.

const REGIONS := {
	"wilds": "res://src/scenes/wilds.tscn",
	"mountain pass": "res://src/scenes/mountain_pass.tscn",
}
## A handful of true endpoints is correct -- a spur that ends at a landmark has one neighbour.
## A network full of them is one that has been shredded.
const MAX_DEAD_ENDS := 20

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	for region_name in REGIONS:
		await _check(String(region_name), String(REGIONS[region_name]))
	_finish()


func _check(region_name: String, path: String) -> void:
	var scene: Node2D = load(path).instantiate()
	root.add_child(scene)
	await process_frame

	var ground := scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		check_true("%s has a Ground layer" % region_name, false)
		return

	# The base fill is whatever the region paints most of; everything else on source 0 is
	# route. Derived rather than hardcoded so this keeps working when a region is retextured.
	var counts: Dictionary = {}
	for cell in ground.get_used_cells():
		var coord := ground.get_cell_atlas_coords(cell)
		counts[coord] = int(counts.get(coord, 0)) + 1
	var base := Vector2i.ZERO
	var best := 0
	for key in counts:
		if int(counts[key]) > best:
			best = int(counts[key])
			base = key

	var trail: Dictionary = {}
	for cell in ground.get_used_cells():
		if ground.get_cell_source_id(cell) == 0 and ground.get_cell_atlas_coords(cell) != base:
			trail[cell] = true
	check_true("%s paints a trail at all (%d cells)" % [region_name, trail.size()],
		trail.size() > 20)
	if trail.is_empty():
		scene.queue_free()
		return

	var seen: Dictionary = {}
	var components := 0
	var largest := 0
	for raw in trail:
		var start: Vector2i = raw
		if seen.has(start):
			continue
		components += 1
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		var size := 0
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			size += 1
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var probe: Vector2i = cell + step
				if trail.has(probe) and not seen.has(probe):
					seen[probe] = true
					stack.append(probe)
		largest = maxi(largest, size)

	var dead := 0
	for raw in trail:
		var cell: Vector2i = raw
		var links := 0
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if trail.has(cell + step):
				links += 1
		if links <= 1:
			dead += 1

	check_true("%s's trail is one connected network (%d component(s), largest %d of %d)"
		% [region_name, components, largest, trail.size()],
		components == 1)
	check_true("%s has few real endpoints, not a shredded path (%d dead ends)"
		% [region_name, dead],
		dead <= MAX_DEAD_ENDS)
	scene.queue_free()
	await process_frame


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — every generated region's paths actually go somewhere.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
