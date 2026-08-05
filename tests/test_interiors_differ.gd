extends SceneTree
## No two buildings open into the same room.
##
##   godot --headless --path . --script res://tests/test_interiors_differ.gd
##
## Both village houses pointed at one interior_house.tscn, and both doors even read "the
## House". Walking into the second building showed you the first building's bed, the first
## building's bookcase and the first building's host — which is the same placeholder failure
## as two NPCs sharing a face, and CLAUDE.md names it directly: every interior is furnished
## for what its building is for.
##
## So this checks the three ways a "new" interior can turn out to be the old one: the same
## scene file, the same room, or the same furniture. It reads the doors rather than a hard
## list of scenes, so a building added later is covered the moment its door exists.

const REGIONS: Array[String] = [
	"res://src/scenes/world.tscn",
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
]
## Two rooms furnished from the same sheet will share the odd piece — a door, a floor mat.
## Sharing most of it is the failure.
const MAX_SHARED_FURNITURE := 0.5

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var interiors := _interiors_reached_from_regions()
	check_true("village doors lead into interiors (%d found)" % interiors.size(),
		interiors.size() >= 2)
	var rooms: Dictionary = {}
	for path: String in interiors:
		rooms[path] = _describe(path)
	var paths: Array = rooms.keys()
	for i in paths.size():
		for j in range(i + 1, paths.size()):
			_compare(String(paths[i]), String(paths[j]), rooms)
	_finish()


## Every distinct interior scene any region's doors travel to, plus the destination each
## door advertises — two doors calling different rooms the same thing is its own bug.
func _interiors_reached_from_regions() -> Array:
	var found: Array = []
	var destinations: Dictionary = {}
	for region_path in REGIONS:
		var region: Node = load(region_path).instantiate()
		for door in region.find_children("*", "Area2D", true, false):
			var target := String(door.get("target_scene") if door.get("target_scene") != null else "")
			if not target.contains("interior"):
				continue
			if target not in found:
				found.append(target)
			var label := String(door.get("destination") if door.get("destination") != null else "")
			if destinations.has(label) and destinations[label] != target:
				check_true("'%s' names one room, not %s and %s"
					% [label, destinations[label].get_file(), target.get_file()], false)
			destinations[label] = target
		region.free()
	return found


## Room shape and the art actually hung in it, which is what the player sees on walking in.
func _describe(path: String) -> Dictionary:
	var scene: Node = load(path).instantiate()
	var shape := Vector3i(int(scene.get("room_width")), int(scene.get("room_height")),
		int(scene.get("doorway_x")))
	var furniture: Dictionary = {}
	for prop in scene.find_children("*", "Node2D", true, false):
		var tex: Texture2D = prop.get("texture") as Texture2D
		if tex == null:
			continue
		# Region, not just the sheet: every piece in here comes off the same two atlases.
		if tex is AtlasTexture:
			furniture[str((tex as AtlasTexture).region)] = true
		else:
			furniture[tex.resource_path] = true
	var tint: Variant = scene.get("wall_tint")
	scene.free()
	return {"shape": shape, "furniture": furniture, "tint": tint}


func _compare(a_path: String, b_path: String, rooms: Dictionary) -> void:
	var a: Dictionary = rooms[a_path]
	var b: Dictionary = rooms[b_path]
	var pair := "%s vs %s" % [a_path.get_file(), b_path.get_file()]
	check_true("%s are different scenes" % pair, a_path != b_path)
	check_true("%s are not the same room shape (%s / %s)" % [pair, a["shape"], b["shape"]],
		a["shape"] != b["shape"])
	var a_furniture: Dictionary = a["furniture"]
	var b_furniture: Dictionary = b["furniture"]
	var shared := 0
	for key in a_furniture:
		if b_furniture.has(key):
			shared += 1
	var smaller: int = maxi(1, mini(a_furniture.size(), b_furniture.size()))
	var overlap := float(shared) / float(smaller)
	check_true("%s are furnished differently (%d/%d pieces shared)"
		% [pair, shared, smaller], overlap <= MAX_SHARED_FURNITURE)


func _finish() -> void:
	print("")
	print(("PASS — every building opens into a room furnished for what it is."
		if failures == 0 else "FAIL — %d interior check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
