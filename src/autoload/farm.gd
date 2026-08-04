extends Node
## Runtime coordinator for the saved farm/calendar loop. FarmLogic owns pure
## rules; this node validates DB definitions, commits inventory transactions,
## emits UI signals, and persists only its owned world fields.

const FarmRules = preload("res://src/systems/farm_logic.gd")

var logic = FarmRules.new()


func _ready() -> void:
	logic.load_world_dict(SaveGame.load_world_state())


func day() -> int:
	return logic.day


func season() -> String:
	return logic.season


func clock_text() -> String:
	return logic.clock_text()


func next_clock_text() -> String:
	return logic.next_clock_text()


func next_clock() -> Dictionary:
	return logic.next_clock()


func plot(plot_id: String) -> Dictionary:
	return logic.plot(plot_id)


func crop_def_for_plot(plot_id: String) -> Dictionary:
	return DB.crops.get(String(plot(plot_id).get("cropId", "")), {})


func stage(plot_id: String) -> int:
	return logic.stage(plot_id, DB.crops)


func is_ready(plot_id: String) -> bool:
	return logic.is_ready(plot_id, DB.crops)


func days_remaining(plot_id: String) -> int:
	return logic.days_remaining(plot_id, DB.crops)


func is_in_season(crop: Dictionary) -> bool:
	return logic.is_in_season(crop)


func available_crops() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for crop in DB.crops.values():
		var typed: Dictionary = crop
		var seed_id := String(typed.get("seedItem", ""))
		if Inv.count(seed_id) > 0:
			available.append(typed)
	available.sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")))
	return available


func plant(plot_id: String, crop_id: String) -> Dictionary:
	var crop: Dictionary = DB.crops.get(crop_id, {})
	if crop.is_empty():
		return {"ok": false, "reason": "That crop is not authored."}
	if not logic.is_in_season(crop):
		return {"ok": false, "reason": "%s will not grow in %s." % [
			crop.get("name", crop_id), logic.season.capitalize()]}
	var seed_id := String(crop.get("seedItem", ""))
	if not Inv.has(seed_id):
		return {"ok": false, "reason": "You need %s." % DB.item(seed_id).get("name", seed_id)}
	if not logic.plant(plot_id, crop):
		return {"ok": false, "reason": "That plot is already planted."}
	if Inv.remove(seed_id, 1) != 1:
		logic.clear_plot(plot_id)
		return {"ok": false, "reason": "The seed is no longer in your Bag."}
	_commit()
	return {"ok": true, "crop": crop}


func water(plot_id: String) -> bool:
	if not logic.water(plot_id):
		return false
	_commit()
	return true


func harvest(plot_id: String) -> Dictionary:
	if not logic.is_ready(plot_id, DB.crops):
		return {"ok": false, "reason": "That crop is not ready."}
	var crop: Dictionary = crop_def_for_plot(plot_id)
	var produce_id := String(crop.get("produceItem", ""))
	if Inv.max_addable(produce_id) <= 0:
		return {"ok": false, "reason": "Your %s stack is full." % \
			DB.item(produce_id).get("name", produce_id)}
	if Inv.add(produce_id, 1) != 0:
		return {"ok": false, "reason": "The harvest would not fit in your Bag."}
	logic.clear_plot(plot_id)
	_commit()
	return {"ok": true, "crop": crop, "produce": produce_id}


func advance_day() -> Dictionary:
	var before_season: String = logic.season
	var previous_weather := WeatherSystem.current()
	var next: Dictionary = logic.advance_day(WeatherSystem.is_precipitation(previous_weather))
	_commit()
	next["new_season"] = String(next["season"]) != before_season
	next["previous_weather"] = previous_weather
	next["weather"] = WeatherSystem.current()
	return next


func reload_from_save() -> void:
	logic.load_world_dict(SaveGame.load_world_state())
	Bus.farm_changed.emit()
	Bus.hud_refresh.emit()


func reset(save: bool = false) -> void:
	logic.reset()
	if save:
		_commit()
	else:
		Bus.farm_changed.emit()
		Bus.hud_refresh.emit()


func _commit() -> void:
	SaveGame.save_world_fields(logic.to_world_dict())
	Bus.farm_changed.emit()
	Bus.hud_refresh.emit()
