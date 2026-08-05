extends SceneTree
## Can the player actually walk to the things a region contains?
##
##   godot --headless --path . --script res://tests/test_region_reachability.gd
##
## Written after the village fields shipped sealed off behind an authored wall: the region
## rendered perfectly in every survey screenshot, and a wall is invisible. Rendering was
## never evidence of reachability, and neither is "the node exists in the scene".
##
## Each region is flood-filled from the player's own start position over a tile grid, using
## real physics queries against the terrain layer, and every door, gatherable, NPC and enemy
## has to come out inside the reachable area. The probe is deliberately smaller than the
## player, so this fails on genuine seals and enclosures rather than on tight gaps.

const TILE := 16
const PROBE_RADIUS := 4.0
const TERRAIN_LAYER := 1

const REGIONS: Array[Dictionary] = [
	{"scene": "res://src/scenes/world.tscn", "ground": "Ground"},
	{"scene": "res://src/scenes/wilds.tscn", "ground": "Ground"},
	{"scene": "res://src/scenes/mountain_pass.tscn", "ground": "Ground"},
]

## Node names that are meant to be unreachable or have no walkable tile of their own.
const SKIP_NAMES: Array[String] = ["Player", "Bounds", "OutskirtBounds", "Ground", "Detail"]

const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const CONTENT_MARKERS: Array[String] = [
	"target_scene", "node_id", "sign_id", "spot_id", "pickup_id",
	"quest_id", "shop_id", "npc_id", "enemy_id", "station",
]

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	for region in REGIONS:
		await _check_region(region)
	_finish()


func _check_region(region: Dictionary) -> void:
	var scene_path := String(region["scene"])
	var label := scene_path.get_file()
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	# Physics has to have run at least once or every query comes back empty, which would
	# read as "nothing is solid" and pass this whole suite vacuously.
	for i in 4:
		await physics_frame

	var ground := scene.get_node_or_null(String(region["ground"])) as TileMapLayer
	var player := _first_in_group(scene, "player") as Node2D
	if ground == null or player == null:
		check_true("%s has a ground layer and a player" % label, false)
		scene.queue_free()
		await process_frame
		return

	var used := ground.get_used_rect()
	var origin := ground.position
	var space := (scene as Node2D).get_world_2d().direct_space_state
	var reachable := _flood(space, used, origin, player.global_position)
	check_true("%s: the player can leave their own start tile (%d tiles reachable)"
		% [label, reachable.size()], reachable.size() > 20)

	var checked := 0
	var stranded: Array[String] = []
	for node in _content_nodes(scene):
		checked += 1
		if not _near_reachable(reachable, origin, (node as Node2D).global_position):
			stranded.append(String(node.name))
	check_true("%s: every one of its %d placed things can be walked to%s"
		% [label, checked, "" if stranded.is_empty() else " — stranded: %s"
			% ", ".join(stranded.slice(0, 6))],
		stranded.is_empty())

	scene.queue_free()
	await process_frame


## Four-way flood over tile centres. A cell is open when a probe smaller than the player
## fits in it, so tight-but-walkable gaps are not reported as seals.
func _flood(space: PhysicsDirectSpaceState2D, used: Rect2i, origin: Vector2,
		from: Vector2) -> Dictionary:
	var shape := CircleShape2D.new()
	shape.radius = PROBE_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = TERRAIN_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var start := _to_cell(origin, from)
	var open: Dictionary = {}
	var frontier: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if not used.has_point(cell):
			continue
		query.transform = Transform2D(0.0, _to_world(origin, cell))
		if not space.intersect_shape(query, 1).is_empty():
			continue
		open[cell] = true
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return open


## Interactables are used from an adjacent tile, and a solid prop legitimately stands on its
## own tile, so a thing counts as reachable when the player can stand next to it.
func _near_reachable(reachable: Dictionary, origin: Vector2, position: Vector2) -> bool:
	var cell := _to_cell(origin, position)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if reachable.has(cell + Vector2i(dx, dy)):
				return true
	return false


## The things a region exists to hold: doors, gatherables, NPCs, enemies, signs, study
## spots, pickups. Scenery is not included — a tree behind a tree is nobody's problem.
func _content_nodes(scene: Node) -> Array[Node]:
	var found: Array[Node] = []
	for holder: String in ["Entities", "Props"]:
		var parent := scene.get_node_or_null(holder)
		if parent == null:
			continue
		for child in parent.get_children():
			if not (child is Node2D) or String(child.name) in SKIP_NAMES:
				continue
			if _is_content(child):
				found.append(child)
	return found


func _is_content(node: Node) -> bool:
	for property: String in CONTENT_MARKERS:
		var value: Variant = node.get(property)
		if value != null and not String(value).strip_edges().is_empty():
			return true
	return false


func _first_in_group(scene: Node, group: String) -> Node:
	if scene.is_in_group(group):
		return scene
	for child in scene.get_children():
		var found := _first_in_group(child, group)
		if found != null:
			return found
	return null


func _to_cell(origin: Vector2, position: Vector2) -> Vector2i:
	return Vector2i(floori((position.x - origin.x) / TILE), floori((position.y - origin.y) / TILE))


func _to_world(origin: Vector2, cell: Vector2i) -> Vector2:
	return origin + Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


func _finish() -> void:
	print("")
	print("PASS - every region's content can be walked to from where the player starts."
		if failures == 0 else "FAIL - %d reachability check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
