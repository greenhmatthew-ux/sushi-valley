class_name GatheringLogic
extends RefCounted
## Pure renewable-node state. Common nodes reset on the next saved calendar day;
## rare nodes opt into a larger reset_days value. Stable authored node IDs are
## the only persisted identity, so moving a visual never resets its cooldown.

var nodes: Dictionary = {} # node_id -> last gathered global calendar day


func is_ready(node_id: String, current_day: int, reset_days: int = 1) -> bool:
	if node_id.is_empty() or not nodes.has(node_id):
		return not node_id.is_empty()
	return maxi(1, current_day) >= int(nodes[node_id]) + maxi(1, reset_days)


func remaining_days(node_id: String, current_day: int, reset_days: int = 1) -> int:
	if is_ready(node_id, current_day, reset_days):
		return 0
	return maxi(0, int(nodes.get(node_id, current_day)) + maxi(1, reset_days)
		- maxi(1, current_day))


func mark_gathered(node_id: String, current_day: int) -> bool:
	if node_id.is_empty():
		return false
	nodes[node_id] = maxi(1, current_day)
	return true


func to_world_dict() -> Dictionary:
	return {"gathering": {"nodes": nodes.duplicate(true)}}


func load_world_dict(world: Dictionary) -> void:
	nodes.clear()
	var gathering: Dictionary = world.get("gathering", {}) \
		if world.get("gathering") is Dictionary else {}
	var raw_nodes: Dictionary = gathering.get("nodes", {}) \
		if gathering.get("nodes") is Dictionary else {}
	for raw_id in raw_nodes:
		var node_id := String(raw_id)
		var gathered_day := int(raw_nodes[raw_id])
		if not node_id.is_empty() and gathered_day > 0:
			nodes[node_id] = gathered_day


func reset() -> void:
	nodes.clear()


static func weather_bonus(resource_kind: String, raining: bool) -> int:
	# Ported from the archived ResourceNodes system: rain enriches herbs, while
	# a non-rain day makes exposed ore easier to work. Bamboo is weather-neutral.
	if resource_kind == "herb" and raining:
		return 1
	if resource_kind == "ore" and not raining:
		return 1
	return 0


static func earned_xp(level_req: int) -> int:
	return maxi(5, maxi(1, level_req) * 3)
