extends Node
## Runtime transaction coordinator for renewable regional resource nodes.
## GatheringLogic owns calendar/reset math; this facade validates authored data,
## commits inventory + station progression, and persists feature-owned world state.

const Rules = preload("res://src/systems/gathering_logic.gd")

var logic := Rules.new()


func _ready() -> void:
	logic.load_world_dict(SaveGame.load_world_state())


func status(node_id: String, item_id: String, base_qty: int, reset_days: int,
		skill_station: String, level_req: int, resource_kind: String,
		required_tool_id: String = "") -> Dictionary:
	logic.register_node(node_id, reset_days)
	if node_id.is_empty() or DB.item(item_id).is_empty():
		return {"ok": false, "reason": "This resource is not authored."}
	if skill_station not in CraftingLogic.STATIONS:
		return {"ok": false, "reason": "This resource has no valid life skill."}
	if not required_tool_id.is_empty():
		var tool: Dictionary = DB.item(required_tool_id)
		if tool.is_empty() or String(tool.get("kind", "")) != "tool":
			return {"ok": false, "reason": "This resource has no valid tool requirement."}
		if not Inv.has(required_tool_id):
			return {
				"ok": false,
				"reason": "Need %s - craft it at the %s." % [
					tool.get("name", required_tool_id), tool_source_label(required_tool_id)],
				"missing_tool": required_tool_id,
			}
	var required := maxi(1, level_req)
	var level := Crafting.station_level(skill_station)
	if level < required:
		return {"ok": false, "reason": "Requires %s Lv %d." % [
			skill_station.capitalize(), required], "level": level}
	var remaining := logic.remaining_days(node_id, Farm.day(), reset_days)
	if remaining > 0:
		return {"ok": false, "reason": _return_text(remaining), "remaining": remaining}
	var bonus := Rules.weather_bonus(resource_kind, WeatherSystem.is_raining())
	# Today's world event stacks with the weather rather than replacing it: they are two
	# different reasons for a good day, and a player who works out both is being rewarded
	# for paying attention.
	var event_bonus := WorldEventLogic.gather_bonus(
		WorldEventLogic.event_for_day(Farm.day(), DB.events), resource_kind)
	var quantity := maxi(1, base_qty) + bonus + event_bonus
	if Inv.max_addable(item_id) < quantity:
		return {"ok": false, "reason": "Your %s stack needs %d open spaces." % [
			DB.item(item_id).get("name", item_id), quantity]}
	return {
		"ok": true,
		"reason": "Ready.",
		"qty": quantity,
		"weather_bonus": bonus,
		"event_bonus": event_bonus,
		"xp": Rules.earned_xp(required),
		"level": level,
	}


func gather(node_id: String, item_id: String, base_qty: int, reset_days: int,
		skill_station: String, level_req: int, resource_kind: String,
		required_tool_id: String = "") -> Dictionary:
	var check := status(node_id, item_id, base_qty, reset_days, skill_station,
		level_req, resource_kind, required_tool_id)
	if not bool(check.get("ok", false)):
		return check
	var quantity := int(check["qty"])
	if Inv.add(item_id, quantity) != 0:
		return {"ok": false, "reason": "The resource would not fit in your Bag."}
	# Every validation happened before the first mutation. From here all three
	# owned states commit exactly once: bag, station XP, then saved node day.
	logic.mark_gathered(node_id, Farm.day(), reset_days)
	var previous_level := int(check["level"])
	var new_level := Crafting.award_xp(skill_station, int(check["xp"]))
	Learning.profile.record_activity(LearningProfile.ACTIVITY_RESOURCE_GATHER)
	Learning.profile.save()
	_commit(node_id)
	check["level"] = new_level
	check["leveled_up"] = new_level > previous_level
	return check


func is_ready(node_id: String, reset_days: int = 1) -> bool:
	return logic.is_ready(node_id, Farm.day(), reset_days)


func remaining_days(node_id: String, reset_days: int = 1) -> int:
	return logic.remaining_days(node_id, Farm.day(), reset_days)


func register_node(node_id: String, reset_days: int = 1) -> bool:
	return logic.register_node(node_id, reset_days)


func preview_next_day() -> Dictionary:
	return logic.preview_advance(Farm.day(), 1)


func daily_status() -> Dictionary:
	var result := {"tracked": 0, "renewed": 0, "recovering": 0}
	for raw_id in logic.reset_days_by_node:
		var node_id := String(raw_id)
		if not logic.nodes.has(node_id):
			continue
		result["tracked"] += 1
		var reset_days := int(logic.reset_days_by_node.get(node_id, 1))
		if logic.is_ready(node_id, Farm.day(), reset_days):
			result["renewed"] += 1
		else:
			result["recovering"] += 1
	return result


func tool_source_label(tool_id: String) -> String:
	for raw_recipe in DB.recipes.values():
		var recipe: Dictionary = raw_recipe
		var output: Dictionary = recipe.get("output", {})
		if String(output.get("item", "")) == tool_id:
			return String(recipe.get("station", "workshop")).capitalize()
	return "Workshop"


func reload_from_save() -> void:
	logic.load_world_dict(SaveGame.load_world_state())
	Bus.gathering_changed.emit("")


func reset(save: bool = false) -> void:
	logic.reset()
	if save:
		SaveGame.save_world_fields(logic.to_world_dict())
	Bus.gathering_changed.emit("")


func _commit(node_id: String) -> void:
	SaveGame.save_world_fields(logic.to_world_dict())
	Bus.gathering_changed.emit(node_id)


func _return_text(days: int) -> String:
	if days == 1:
		return "Returns tomorrow."
	return "Returns in %d days." % days
