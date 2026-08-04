class_name GatheringLogic
extends RefCounted
## Pure renewable-node state. Common nodes reset on the next saved calendar day;
## rare nodes opt into a larger reset_days value. Stable authored node IDs are
## the only persisted identity, so moving a visual never resets its cooldown.

## v6 saved node IDs but not their cooldown. These are the only multi-day nodes
## that version could have written, so this small migration table preserves their
## authored truth instead of briefly treating them as common one-day resources.
const V6_RESET_OVERRIDES := {
	"wilds_rich_copper_seam": 2,
	"wilds_old_growth_bamboo": 2,
	"wilds_deep_rainleaf": 2,
}

var nodes: Dictionary = {} # node_id -> last gathered global calendar day
var reset_days_by_node: Dictionary = {} # node_id -> authored cooldown used by sleep preview


func register_node(node_id: String, reset_days: int = 1) -> bool:
	if node_id.is_empty():
		return false
	reset_days_by_node[node_id] = maxi(1, reset_days)
	return true


func is_ready(node_id: String, current_day: int, reset_days: int = 1) -> bool:
	if node_id.is_empty() or not nodes.has(node_id):
		return not node_id.is_empty()
	return maxi(1, current_day) >= int(nodes[node_id]) + maxi(1, reset_days)


func remaining_days(node_id: String, current_day: int, reset_days: int = 1) -> int:
	if is_ready(node_id, current_day, reset_days):
		return 0
	return maxi(0, int(nodes.get(node_id, current_day)) + maxi(1, reset_days)
		- maxi(1, current_day))


func mark_gathered(node_id: String, current_day: int, reset_days: int = 1) -> bool:
	if node_id.is_empty():
		return false
	nodes[node_id] = maxi(1, current_day)
	register_node(node_id, reset_days)
	return true


func to_world_dict() -> Dictionary:
	var saved_resets: Dictionary = {}
	for node_id in nodes:
		saved_resets[node_id] = maxi(1, int(reset_days_by_node.get(node_id, 1)))
	return {"gathering": {
		"nodes": nodes.duplicate(true),
		"resetDays": saved_resets,
	}}


func load_world_dict(world: Dictionary) -> void:
	nodes.clear()
	reset_days_by_node.clear()
	var gathering: Dictionary = world.get("gathering", {}) \
		if world.get("gathering") is Dictionary else {}
	var raw_nodes: Dictionary = gathering.get("nodes", {}) \
		if gathering.get("nodes") is Dictionary else {}
	for raw_id in raw_nodes:
		var node_id := String(raw_id)
		var gathered_day := int(raw_nodes[raw_id])
		if not node_id.is_empty() and gathered_day > 0:
			nodes[node_id] = gathered_day
	var raw_resets: Dictionary = gathering.get("resetDays", {}) \
		if gathering.get("resetDays") is Dictionary else {}
	for raw_id in raw_resets:
		var node_id := String(raw_id)
		if nodes.has(node_id):
			reset_days_by_node[node_id] = maxi(1, int(raw_resets[raw_id]))
	# v6 saves knew the gathered day but not the authored cooldown. Known rare
	# IDs use the exact migration table; every other v6 node was authored daily.
	for node_id in nodes:
		if not reset_days_by_node.has(node_id):
			reset_days_by_node[node_id] = int(V6_RESET_OVERRIDES.get(node_id, 1))


## What one explicit day advance will do to the nodes currently on cooldown.
## Ready historical entries are ignored, so the preview never counts old routes.
func preview_advance(current_day: int, days_ahead: int = 1) -> Dictionary:
	var target_day := maxi(1, current_day) + maxi(1, days_ahead)
	var depleted := 0
	var returning := 0
	var waiting := 0
	for raw_id in nodes:
		var node_id := String(raw_id)
		var cooldown := maxi(1, int(reset_days_by_node.get(node_id, 1)))
		if is_ready(node_id, current_day, cooldown):
			continue
		depleted += 1
		if is_ready(node_id, target_day, cooldown):
			returning += 1
		else:
			waiting += 1
	return {
		"depleted": depleted,
		"returning": returning,
		"waiting": waiting,
		"target_day": target_day,
	}


func reset() -> void:
	nodes.clear()
	reset_days_by_node.clear()


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
