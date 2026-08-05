extends SceneTree
## Every resource node sits somewhere that explains why it is there.
##
##   godot --headless --path . --script res://tests/test_resource_node_siting.gd
##
## Nodes were placed wherever the scatter happened to leave a gap, so ore seams sat on open
## grass with no stone in sight and bamboo stood alone in the middle of a meadow. That reads
## as an accident, because it was one — see the placement rule in CLAUDE.md.
##
## So each kind has to earn its spot from the props actually generated around it:
##   ore     — against rock or cliff
##   bamboo  — in a stand, with other growth around it
##   herb    — in shaded or sheltered ground, under cover
##
## The regions build their cover procedurally, so this asserts against the real generated
## scene rather than the authored .tscn: it is the generator's output the player walks past.
## A node must also stay *reachable* — cover that seals a node off is a worse failure than
## cover that is missing, which is why the open-approach check sits alongside the others.

const SCENES: Array[String] = [
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
	"res://src/scenes/world.tscn",
]
## A prop reads as "belonging with" a node when it is close enough to share its patch of
## ground. Two tiles: touching diagonally at 16px, plus room for the node's own art.
const NEAR := 40.0
## Cover the node needs around it, by kind.
const WANTED := {
	"ore": ["rock"],
	"bamboo": ["tree", "bush"],
	"herb": ["tree", "bush"],
}
## Every node needs at least one open side, or the cover that explains it also walls it off.
const APPROACH := 20.0

var failures: int = 0


func _initialize() -> void:
	await process_frame
	for path in SCENES:
		await _check_scene(path)
	_finish()


func _check_scene(path: String) -> void:
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	# Regions generate their terrain and scatter in _ready; let that finish before looking.
	for i in 8:
		await process_frame
	print("  -- %s" % path.get_file())
	var nodes := _find_resource_nodes(scene)
	check_true("%s has resource nodes to site" % path.get_file(), not nodes.is_empty())
	var props := _find_props(scene)
	for node: Node2D in nodes:
		_check_node(node, props)
	scene.queue_free()
	await process_frame


func _find_resource_nodes(scene: Node) -> Array:
	var out: Array = []
	for n in scene.find_children("*", "Area2D", true, false):
		if n.get("resource_kind") != null and n.get("node_id") != null:
			out.append(n)
	return out


## Props carry no type marker, so classify by the art they draw — which is exactly what the
## player uses to read the ground too.
func _find_props(scene: Node) -> Array:
	var out: Array = []
	for p in scene.find_children("*", "Node2D", true, false):
		if not (p is Prop):
			continue
		var tex: Texture2D = p.get("texture")
		if tex == null:
			continue
		var file := tex.resource_path.get_file()
		var kind := ""
		if file.begins_with("tree"):
			kind = "tree"
		elif file.begins_with("rock"):
			kind = "rock"
		elif file.begins_with("berry"):
			kind = "bush"
		if kind != "":
			out.append({"kind": kind, "pos": p.global_position})
	return out


func _check_node(node: Node2D, props: Array) -> void:
	var kind := String(node.get("resource_kind"))
	var id := String(node.get("node_id"))
	var wanted: Array = WANTED.get(kind, [])
	var found: Array[String] = []
	var blocking := 0
	for p in props:
		var d: float = node.global_position.distance_to(p["pos"])
		if d <= NEAR and String(p["kind"]) in wanted:
			found.append(String(p["kind"]))
		if d <= APPROACH and String(p["kind"]) != "bush":
			blocking += 1
	check_true("%s (%s) sits against %s" % [id, kind, " or ".join(wanted)], not found.is_empty())
	check_true("%s is not walled in by its own cover" % id, blocking <= 2)


func _finish() -> void:
	print("")
	print(("PASS — every resource node is sited where its kind belongs."
		if failures == 0 else "FAIL — %d resource-node siting check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
