class_name FarmLogic
extends RefCounted
## Pure calendar + crop-plot state. Balance and dry-day behavior are ported from
## the archived FarmSystem.ts / WorldClock.ts: four 28-day seasons, planting
## waters immediately, watered days grow, and dry days pause without withering.

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const DAYS_PER_SEASON := 28

var day: int = 1
var season: String = "spring"
var plots: Dictionary = {} # stable plot id -> {cropId, plantedDay, watered}


func clock_text() -> String:
	return "%s - Day %d" % [season.capitalize(), day_of_season()]


func day_of_season() -> int:
	return ((day - 1) % DAYS_PER_SEASON) + 1


func next_clock() -> Dictionary:
	var next_day := day + 1
	var next_season := season
	if next_day > 1 and (next_day - 1) % DAYS_PER_SEASON == 0:
		var index := SEASONS.find(season)
		next_season = SEASONS[(maxi(index, 0) + 1) % SEASONS.size()]
	return {"day": next_day, "season": next_season}


func next_clock_text() -> String:
	var next := next_clock()
	var next_season_day := ((int(next["day"]) - 1) % DAYS_PER_SEASON) + 1
	return "%s - Day %d" % [String(next["season"]).capitalize(), next_season_day]


func plot(plot_id: String) -> Dictionary:
	if plots.has(plot_id) and plots[plot_id] is Dictionary:
		return (plots[plot_id] as Dictionary).duplicate(true)
	return {"cropId": "", "plantedDay": 0, "watered": false}


func is_in_season(crop: Dictionary) -> bool:
	return season in crop.get("seasons", [])


func plant(plot_id: String, crop: Dictionary) -> bool:
	if plot_id.is_empty() or String(crop.get("id", "")).is_empty() \
			or not String(plot(plot_id).get("cropId", "")).is_empty() \
			or not is_in_season(crop):
		return false
	plots[plot_id] = {
		"cropId": String(crop["id"]),
		"plantedDay": day,
		"watered": true,
	}
	return true


func water(plot_id: String) -> bool:
	var current := plot(plot_id)
	if String(current.get("cropId", "")).is_empty() or bool(current.get("watered", false)):
		return false
	current["watered"] = true
	plots[plot_id] = current
	return true


func stage(plot_id: String, crops: Dictionary) -> int:
	var current := plot(plot_id)
	var crop_id := String(current.get("cropId", ""))
	var crop: Dictionary = crops.get(crop_id, {})
	if crop_id.is_empty() or crop.is_empty():
		return 0
	var total_days := maxi(1, int(crop.get("days", 1)))
	var age := day - int(current.get("plantedDay", day))
	if age >= total_days:
		return 3
	if age >= ceili(float(total_days) / 2.0):
		return 2
	return 1


func is_ready(plot_id: String, crops: Dictionary) -> bool:
	return stage(plot_id, crops) == 3


func days_remaining(plot_id: String, crops: Dictionary) -> int:
	var current := plot(plot_id)
	var crop: Dictionary = crops.get(String(current.get("cropId", "")), {})
	if crop.is_empty():
		return 0
	return maxi(0, int(crop.get("days", 1)) \
		- (day - int(current.get("plantedDay", day))))


func clear_plot(plot_id: String) -> void:
	plots.erase(plot_id)


func advance_day() -> Dictionary:
	# Process today's water before the clock moves. A dry crop increments its
	# planted day, keeping age unchanged after the global day increments.
	for raw_id in plots.keys():
		var plot_id := String(raw_id)
		var current := plot(plot_id)
		if String(current.get("cropId", "")).is_empty():
			plots.erase(plot_id)
			continue
		if bool(current.get("watered", false)):
			current["watered"] = false
		else:
			current["plantedDay"] = int(current.get("plantedDay", day)) + 1
		plots[plot_id] = current
	var next := next_clock()
	day = int(next["day"])
	season = String(next["season"])
	return next


func to_world_dict() -> Dictionary:
	return {
		"calendar": {"day": day, "season": season},
		"farm": {"plots": plots.duplicate(true)},
	}


func load_world_dict(world: Dictionary) -> void:
	day = 1
	season = "spring"
	plots.clear()
	var calendar: Dictionary = world.get("calendar", {})
	day = maxi(1, int(calendar.get("day", 1)))
	var loaded_season := String(calendar.get("season", "spring"))
	season = loaded_season if loaded_season in SEASONS else "spring"
	var farm: Dictionary = world.get("farm", {})
	var raw_plots: Dictionary = farm.get("plots", {})
	for raw_id in raw_plots:
		if not (raw_plots[raw_id] is Dictionary):
			continue
		var raw: Dictionary = raw_plots[raw_id]
		var crop_id := String(raw.get("cropId", ""))
		if crop_id.is_empty():
			continue
		plots[String(raw_id)] = {
			"cropId": crop_id,
			"plantedDay": maxi(1, int(raw.get("plantedDay", day))),
			"watered": bool(raw.get("watered", false)),
		}


func reset() -> void:
	day = 1
	season = "spring"
	plots.clear()
