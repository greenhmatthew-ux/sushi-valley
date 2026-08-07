extends SceneTree
## Every scene-to-scene Door is signposted.
##
##   godot --headless --path . --script res://tests/test_door_signage.gd
##
## A Door is a bare trigger volume, and most of them are `auto_enter`: before this
## slice the tile that threw you into another region looked exactly like the tile
## beside it, and you only learned where it went by being taken there. The signage
## is built in code from per-instance offsets, so it is the kind of thing that
## silently stops existing the moment an export is renamed or a scene is re-saved
## from the editor — hence a test rather than trust.
##
## The geometry checks matter as much as the labels. A screenshot once showed a
## region that headless tests called fine while its trail stopped four tiles short
## of the exit, which read as "the road ends here". So: the road has to reach the
## door, and nothing the door draws may be solid, because a prop that can block the
## way into a transition is the exact failure this feature exists to prevent.

const SCENES := [
	"res://src/scenes/world.tscn",
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
	"res://src/scenes/interior_house.tscn",
	"res://src/scenes/expedition_forest.tscn",
	"res://src/scenes/expedition_pass.tscn",
]
## Serene Village grass — anything else on a trail cell means dirt was laid there.
const GRASS := Vector2i(4, 0)

var failures: int = 0


func _initialize() -> void:
	await process_frame
	for path in SCENES:
		await _check_scene(path)
	_finish()


func _check_scene(path: String) -> void:
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var doors := _doors(scene)
	var name := path.get_file()
	check_true("%s has transition doors (%d)" % [name, doors.size()], not doors.is_empty())
	for door in doors:
		_check_door(name, door)
	_check_route_reaches_doors(name, scene, doors)
	if not doors.is_empty():
		_prompt_names_the_destination(doors[0])

	scene.queue_free()
	await process_frame


func _check_door(scene_name: String, door: Node) -> void:
	var label := "%s/%s" % [scene_name, door.name]

	check_true("%s names where it goes" % label, not String(door.destination).is_empty())

	# A walk-in door fires without asking, so its destination has to be readable
	# before the player reaches it. A press-to-enter door gets the same phrase from
	# the context prompt instead.
	var plate := door.get_node_or_null("Nameplate") as Label
	if door.auto_enter:
		check_true("%s floats a nameplate" % label, plate != null)
		if plate != null:
			check_eq("%s nameplate reads its destination" % label,
				plate.text, "To %s" % door.destination)
	else:
		check_true("%s leaves the plate to the context prompt" % label, plate == null)

	# Something has to be visible at the spot, or the exit is still invisible.
	var visible_children := 0
	for child in door.get_children():
		if child is Sprite2D or child is Label:
			visible_children += 1
	check_true("%s draws something (%d parts)" % [label, visible_children],
		visible_children > 0)

	# Signage stands beside the gap, never in it: a marker on the door's own tile
	# would be a prop overlapping a transition.
	for offset_name in ["post_offset", "sign_offset"]:
		var offset: Vector2 = door.get(offset_name)
		if offset != Vector2.ZERO:
			check_true("%s %s clears the doorway (%.0fpx)" % [label, offset_name, offset.length()],
				offset.length() >= 16.0)

	# Nothing built here may block the way in.
	for child in door.get_children():
		check_true("%s signage is not solid (%s)" % [label, child.name],
			not (child is StaticBody2D))


## The trail has to arrive at the transition. Each region generates its ground
## differently, so each is asked in its own terms; the question is the same one.
func _check_route_reaches_doors(scene_name: String, scene: Node, doors: Array[Node]) -> void:
	match scene_name:
		"wilds.tscn":
			var ground: TileMapLayer = scene.get_node("Ground")
			for door in doors:
				var cell := _tile_of(door, scene.TILE)
				check_true("wilds: the trail reaches %s" % door.name,
					ground.get_cell_atlas_coords(cell) != GRASS)
		"mountain_pass.tscn":
			var ground: TileMapLayer = scene.get_node("Ground")
			for door in doors:
				check_eq("the pass route reaches %s" % door.name,
					ground.get_cell_atlas_coords(_tile_of(door, scene.TILE)), scene.TRAIL)
		"expedition_forest.tscn", "expedition_pass.tscn":
			var route: Dictionary = scene.get("_route_cells")
			for door in doors:
				check_true("the expedition trail reaches %s" % door.name,
					route.has(_tile_of(door, scene.TILE)))
		"world.tscn":
			# The village road is hand-authored and the south exit sits clear of it,
			# so world.gd lays a spur; it shares the authored Ground's transform.
			var road := scene.get_node_or_null("SouthRoad") as TileMapLayer
			check_true("the village lays a road to its south exit", road != null)
			if road == null:
				return
			var ground: TileMapLayer = scene.get_node("Ground")
			check_eq("the spur shares the authored map's offset",
				road.position, ground.position)
			for door in doors:
				if not door.auto_enter:
					continue   # house doorsteps are on the authored map already
				var pos: Vector2 = (door as Node2D).position - road.position
				var cell := Vector2i(floori(pos.x / 16.0), floori(pos.y / 16.0))
				check_true("the village road reaches %s" % door.name,
					road.get_cell_source_id(cell) != -1)
			# and it must leave town rather than stopping at the gate
			check_true("the road runs on past the gate (%d tiles)"
				% road.get_used_cells().size(), road.get_used_cells().size() >= 12)


## The keypress prompt and the world nameplate have to name the same place, or a
## player reads one thing and presses a key expecting another.
##
## Scripts are loaded here rather than preloaded at the top of the file: a preload
## is resolved while this test is still being compiled, before the autoloads exist,
## and door.gd/context_prompt.gd both name them — which fails their compile and
## leaves every Door in the project script-less for the rest of the run.
func _prompt_names_the_destination(door: Node) -> void:
	var prompt: Node = load("res://src/ui/context_prompt.gd").new()
	var authored: String = door.destination
	check_eq("the context prompt names the destination",
		prompt._verb_for(door), "Enter %s" % authored)
	door.destination = ""
	check_eq("and falls back to a bare verb when a door has no name",
		prompt._verb_for(door), "Enter")
	door.destination = authored
	prompt.free()


func _tile_of(door: Node, tile: int) -> Vector2i:
	var pos: Vector2 = (door as Node2D).position
	return Vector2i(floori(pos.x / tile), floori(pos.y / tile))


func _doors(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node.get("target_scene") != null and node.has_method("interact") \
			and not String(node.get("target_scene")).is_empty():
		out.append(node)
	for child in node.get_children():
		out.append_array(_doors(child))
	return out


func _finish() -> void:
	print("")
	print(("PASS — every way out of a region is signposted."
		if failures == 0 else "FAIL — %d door-signage check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
