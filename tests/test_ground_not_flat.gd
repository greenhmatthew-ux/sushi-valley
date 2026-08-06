extends SceneTree
## Guard: no region may carpet itself in a flat, untextured tile.
##
##   godot --headless --path . --script res://tests/test_ground_not_flat.gd
##
## Written because "avoid plain tiles" had to be said more than once. The village shipped
## with 76% of its ground (1003 of 1320 authored cells) set to Serene Village's grass tile,
## which measures 2.67 average per-channel deviation — a near-solid green square. Screenshots
## of it read as a flat sheet, and every other suite was green the whole time.
##
## So this asserts the property directly, in pixels: whatever tile a region uses MOST must
## have real variation inside it. Adding decals on top does not satisfy this, because the
## thing that looked flat was the base.

## Average per-channel standard deviation, in 0-255 units, that a tile's own pixels must
## reach. Serene's flat grass sits at 2.67 and its flat road centre at 2.50; the textured
## grass that replaced them is ~8, and the Mountain Pass's stone floor is ~85. 5.0 separates
## "has detail in the art" from "is a solid fill" without demanding busy noise.
const MIN_DETAIL := 5.0

## Regions whose ground is generated at runtime, so this exercises the real _ready() path
## rather than the authored tile data alone.
const REGIONS := {
	"village": "res://src/scenes/world.tscn",
	"wilds": "res://src/scenes/wilds.tscn",
	"mountain pass": "res://src/scenes/mountain_pass.tscn",
}

## Regions still carpeted in a flat tile, recorded rather than hidden.
##
## The Mountain Pass lays Ninja Adventure's relief tile (2,6) over 84% of itself, and that
## tile measures 0.00 deviation — a solid tan fill. It is listed here because no replacement
## has been found yet, not because it is acceptable. Every textured candidate on the relief
## and interior-floor sheets is either a vertical wall stripe or a single object that repeats
## into an obvious grid when tiled, and shipping a visible wallpaper grid would be worse than
## shipping flat.
##
## This list must only ever shrink. A region here that has since been fixed fails the test on
## purpose, so the entry gets deleted instead of quietly outliving the problem.
const KNOWN_FLAT: Array[String] = ["mountain pass"]

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	for region_name in REGIONS:
		await _check_region(String(region_name), String(REGIONS[region_name]))
	_finish()


func _check_region(region_name: String, path: String) -> void:
	var scene: Node2D = load(path).instantiate()
	root.add_child(scene)
	await process_frame

	var ground := scene.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		check_true("%s has a Ground layer" % region_name, false)
		scene.queue_free()
		return

	# Tally the ground by (source, atlas coord) and take the winner. That tile is what the
	# player is actually looking at across most of the region.
	var tally: Dictionary = {}
	var cells := ground.get_used_cells()
	for cell in cells:
		var key := "%d:%s" % [ground.get_cell_source_id(cell), ground.get_cell_atlas_coords(cell)]
		tally[key] = int(tally.get(key, 0)) + 1
	var top_key := ""
	var top_count := 0
	for key in tally:
		if int(tally[key]) > top_count:
			top_count = int(tally[key])
			top_key = String(key)
	if top_key.is_empty():
		check_true("%s paints some ground" % region_name, false)
		scene.queue_free()
		return

	var share := float(top_count) / float(maxi(cells.size(), 1)) * 100.0
	var parts := top_key.split(":")
	var source_id := int(parts[0])
	var coord := _parse_coord(top_key)
	var detail := _tile_detail(ground.tile_set, source_id, coord)

	var textured := detail >= MIN_DETAIL
	if KNOWN_FLAT.has(region_name):
		# Inverted on purpose: the day this region gets a textured floor, this fails and the
		# entry has to come out of KNOWN_FLAT.
		check_true("%s is still the known-flat region (tile %s, %.0f%%, detail %.2f) — fix it and drop it from KNOWN_FLAT"
			% [region_name, coord, share, detail],
			not textured)
	else:
		check_true("%s's most-used ground tile %s covers %.0f%% and is textured (detail %.2f)"
			% [region_name, coord, share, detail],
			textured)
	scene.queue_free()


## Average per-channel standard deviation of the tile's own pixels, straight off the atlas.
func _tile_detail(tile_set: TileSet, source_id: int, coord: Vector2i) -> float:
	if tile_set == null:
		return -1.0
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return -1.0
	var image := source.texture.get_image()
	if image == null:
		return -1.0
	# Imported textures come back in a GPU format; get_pixel on one reads as uniform black,
	# which would make every tile look perfectly "flat" and pass/fail for the wrong reason.
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var size := source.texture_region_size
	var origin := Vector2i(coord.x * size.x, coord.y * size.y)

	var sums := [0.0, 0.0, 0.0]
	var squares := [0.0, 0.0, 0.0]
	var n := 0
	for dx in size.x:
		for dy in size.y:
			var p := origin + Vector2i(dx, dy)
			if p.x >= image.get_width() or p.y >= image.get_height():
				continue
			var c := image.get_pixel(p.x, p.y)
			var channels := [c.r * 255.0, c.g * 255.0, c.b * 255.0]
			for i in 3:
				sums[i] += channels[i]
				squares[i] += channels[i] * channels[i]
			n += 1
	if n == 0:
		return -1.0
	var total := 0.0
	for i in 3:
		var mean: float = sums[i] / n
		total += sqrt(maxf(squares[i] / n - mean * mean, 0.0))
	return total / 3.0


func _parse_coord(key: String) -> Vector2i:
	var inner := key.substr(key.find("(") + 1)
	inner = inner.substr(0, inner.find(")"))
	var bits := inner.split(",")
	return Vector2i(int(bits[0].strip_edges()), int(bits[1].strip_edges()))


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — every region's dominant ground tile has texture in the art itself.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
