extends SceneTree
## Guard: every gathering node can actually be stood next to and used.
##
##   godot --headless --path . --script res://tests/test_nodes_reachable.gd
##
## A node can be correctly configured -- on the right collision layer, in the "interactable"
## group, exposing interact() -- and still be dead in the player's hands, because reaching it
## is a physics question, not a configuration one. The Wilds and the village both PLANT cover
## around their resource nodes at runtime, and a trunk dropped on the one open approach makes
## a node that tests green unusable.
##
## So this asks the question the player asks: standing where I can stand, is the node inside
## my interact probe? It sweeps the player's own feet collider around each node and needs at
## least one unblocked spot within probe reach.
##
## Interact reach is the probe circle (16px) and the node's own Reach shape; a spot counts
## when the feet fit and the centre-to-centre distance is inside that.

const REGIONS := {
	"village": "res://src/scenes/world.tscn",
	"wilds": "res://src/scenes/wilds.tscn",
	"mountain pass": "res://src/scenes/mountain_pass.tscn",
}
## Player's feet collider from player.tscn, and its InteractProbe radius.
const FEET := Vector2(8, 5)
const PROBE_RADIUS := 16.0
## Where the player may stand, relative to the node, in px. Cardinals first: the scatter is
## documented to keep straight approaches open, so a node reachable only diagonally is a
## warning sign but still passes.
const OFFSETS: Array[Vector2] = [
	Vector2(0, 14), Vector2(0, -14), Vector2(-14, 0), Vector2(14, 0),
	Vector2(0, 20), Vector2(-20, 0), Vector2(20, 0), Vector2(0, -20),
	Vector2(-12, 12), Vector2(12, 12), Vector2(-12, -12), Vector2(12, -12),
]

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
	await physics_frame

	var space := scene.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = FEET

	var nodes: Array = []
	for candidate in scene.find_children("*", "Area2D", true, false):
		if candidate.get("resource_kind") != null and candidate.has_method("interact"):
			nodes.append(candidate)
	check_true("%s has gathering nodes to reach (%d)" % [region_name, nodes.size()],
		not nodes.is_empty())

	var stranded: Array[String] = []
	for node in nodes:
		var reachable := false
		for offset in OFFSETS:
			if offset.length() > PROBE_RADIUS + 6.0:
				continue
			var params := PhysicsShapeQueryParameters2D.new()
			params.shape = shape
			params.transform = Transform2D(0.0, (node as Node2D).global_position + offset)
			# World geometry only: layer 1 is what actually stops the player. The nodes
			# themselves sit on layer 8 and must not count as blocking each other.
			params.collision_mask = 1
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if space.intersect_shape(params, 1).is_empty():
				reachable = true
				break
		if not reachable:
			stranded.append("%s@%s" % [node.name, (node as Node2D).global_position])
	check_true("%s: every gathering node has somewhere to stand (%s)"
		% [region_name, "none stranded" if stranded.is_empty()
			else ", ".join(PackedStringArray(stranded))],
		stranded.is_empty())
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
		print("PASS — every gathering node can be stood next to.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
