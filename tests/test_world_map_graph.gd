extends SceneTree
## World map graph contract: authored coordinates drive focusable nodes, links are
## deduplicated, status is honest, and every node remains inside the available frame.

var failures := 0


func _initialize() -> void:
	await process_frame
	var graph := Control.new()
	graph.set_script(load("res://src/ui/world_map_graph.gd"))
	graph.size = Vector2(480, 150)
	root.add_child(graph)
	await process_frame
	var selected: Array[String] = []
	graph.region_focused.connect(func(id): selected.append(id))
	graph.call("configure", root.get_node("DB").regions, "whispering_woods")
	await process_frame

	check_eq("every authored region becomes one focusable node",
		_count_named(graph, "RegionNode_"), root.get_node("DB").regions.size())
	check_eq("the authored undirected network is drawn once per connection",
		graph.call("connection_count"), 11)
	var current: Button = graph.find_child("RegionNode_whispering_woods", true, false)
	var planned: Button = graph.find_child("RegionNode_north_reach", true, false)
	check_true("the runtime region is explicitly current",
		current != null and current.get_meta("status") == "current"
		and current.tooltip_text.contains("You are here"))
	check_true("unbuilt geography is a question, not a fake destination",
		planned != null and planned.text == "?" and planned.get_meta("status") == "planned"
		and planned.tooltip_text.contains("Not built yet"))
	check_true("the three real routes keep their authored names",
		graph.find_child("RegionLabel_valley_crossroads", true, false) != null
		and graph.find_child("RegionLabel_whispering_woods", true, false) != null
		and graph.find_child("RegionLabel_mountain_pass", true, false) != null)
	check_true("all route nodes stay inside the graph", _all_nodes_inside(graph))

	graph.call("focus_region", "mountain_pass", false)
	check_eq("focus selection follows the requested route",
		graph.call("selected_region_id"), "mountain_pass")
	check_true("focus emits the region id", not selected.is_empty() and selected[-1] == "mountain_pass")

	graph.size = Vector2(320, 100)
	await process_frame
	check_true("nodes reflow inside a compact graph", _all_nodes_inside(graph))
	graph.queue_free()
	await process_frame

	print("")
	print("PASS — the world map is a focusable, honest route graph." \
		if failures == 0 else "FAIL — %d world-map check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func _count_named(node: Node, prefix: String) -> int:
	var count := 0
	for child in node.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
	return count


func _all_nodes_inside(graph: Control) -> bool:
	var frame := Rect2(Vector2.ZERO, graph.size).grow(0.5)
	for child in graph.get_children():
		if child is Button and String(child.name).begins_with("RegionNode_"):
			var button := child as Button
			if not frame.encloses(Rect2(button.position, button.size)):
				return false
	return true


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
