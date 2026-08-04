extends SceneTree
## Deterministic seasonal forecasts, precipitation-fed crops, outdoor visuals,
## HUD truth, and storm fishing all follow the archived weather contract.

const PROFILE_PATH := "user://profile.json"
const WeatherRules = preload("res://src/systems/weather_logic.gd")
const FarmRules = preload("res://src/systems/farm_logic.gd")

var failures := 0
var _backup_text := ""
var _had_backup := false
var farm: Node
var inv: Node
var save: Node
var bus: Node
var weather: Node


func _initialize() -> void:
	_stash_real_save()
	await process_frame
	farm = root.get_node("Farm")
	inv = root.get_node("Inv")
	save = root.get_node("SaveGame")
	bus = root.get_node("Bus")
	weather = root.get_node("WeatherSystem")

	_pure_forecast_contract()
	_pure_precipitation_contract()
	await _runtime_and_ui_contract()

	_restore_real_save()
	_finish()


func _pure_forecast_contract() -> void:
	check_near("day-one PRNG matches the archived JS double math",
		WeatherRules.day_random(1), 0.8966319432707112, 0.000000001)
	check_eq("Spring day 1 is rainy", WeatherRules.current_weather(1, "spring"), "rain")
	check_eq("Spring day 2 is clear", WeatherRules.current_weather(2, "spring"), "clear")
	check_eq("Summer day 3 is stormy", WeatherRules.current_weather(3, "summer"), "storm")
	check_eq("Winter day 1 is snowy", WeatherRules.current_weather(1, "winter"), "snow")
	check_true("rain counts as precipitation", WeatherRules.is_precipitation("rain"))
	check_true("snow counts as precipitation", WeatherRules.is_precipitation("snow"))
	check_true("clouds do not water crops", not WeatherRules.is_precipitation("cloudy"))


func _pure_precipitation_contract() -> void:
	var logic: RefCounted = FarmRules.new()
	var crops := {
		"cucumber": {"id": "cucumber", "days": 3,
			"seasons": ["spring", "summer"]},
	}
	check_true("the weather fixture crop plants", logic.plant("rain_plot", crops["cucumber"]))
	logic.advance_day(false)
	check_true("a clear night consumes today's watering",
		not bool(logic.plot("rain_plot")["watered"]))
	logic.advance_day(true)
	check_true("rain grows a dry crop and leaves tomorrow watered",
		bool(logic.plot("rain_plot")["watered"]))
	logic.advance_day(false)
	check_true("rain-carried watering advances the following clear day",
		logic.is_ready("rain_plot", crops))


func _runtime_and_ui_contract() -> void:
	save.clear()
	inv.reset()
	farm.reset(false)
	check_eq("a fresh saved calendar has today's deterministic rain", weather.current(), "rain")
	inv.add("cucumber_seed", 1)
	var planted: Dictionary = farm.plant("weather_plot", "cucumber")
	check_true("runtime crop plants before the rainy night", bool(planted.get("ok", false)))
	var result: Dictionary = farm.advance_day()
	check_eq("day advance records the weather that affected crops",
		String(result.get("previous_weather", "")), "rain")
	check_eq("the next saved day has its deterministic forecast",
		String(result.get("weather", "")), "clear")
	check_true("rain leaves the saved plot watered on the new day",
		bool(save.load_world_state()["farm"]["plots"]["weather_plot"]["watered"]))

	var hud := CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud_layer.gd"))
	root.add_child(hud)
	await process_frame
	var weather_label := hud.find_child("HudWeather", true, false) as Label
	check_true("HUD exposes a dedicated weather line", weather_label != null)
	check_eq("HUD names the current clear day", weather_label.text, "Clear")

	farm.logic.day = 3
	farm.logic.season = "summer"
	bus.farm_changed.emit()
	await process_frame
	check_eq("the runtime derives a storm from the changed calendar", weather.current(), "storm")
	check_eq("HUD explains the storm's fishing consequence",
		weather_label.text, "Storm - rough fishing")

	var overlay := load("res://src/ui/weather_overlay.tscn").instantiate() as CanvasLayer
	root.add_child(overlay)
	await process_frame
	var canvas: Control = overlay.get_node("WeatherCanvas")
	check_eq("outdoor overlay renders the same storm as the HUD",
		String(canvas.get("weather")), "storm")
	check_true("the screen-space weather canvas covers the viewport",
		canvas.size.x >= 640.0 and canvas.size.y >= 360.0)
	for scene_path in ["res://src/scenes/world.tscn", "res://src/scenes/wilds.tscn",
			"res://src/scenes/mountain_pass.tscn", "res://src/scenes/expedition_forest.tscn"]:
		check_true("%s authors an outdoor weather layer" % scene_path.get_file(),
			_scene_has_root_child(scene_path, "WeatherOverlay"))
	check_true("the house keeps weather outside",
		not _scene_has_root_child("res://src/scenes/interior_house.tscn", "WeatherOverlay"))

	var fishing_panel := CanvasLayer.new()
	fishing_panel.set_script(load("res://src/ui/fishing_panel.gd"))
	root.add_child(fishing_panel)
	await process_frame
	bus.fishing_open.emit("storm_test", "Test Pond", 2, 120, 0.1)
	await process_frame
	check_true("rain and storms activate the harder fishing model",
		bool(fishing_panel.get("_stormy")))
	check_true("the fishing title warns about rough conditions",
		"Storm Fishing" in String((fishing_panel.get("_title") as Label).text))
	fishing_panel.call("_cancel")

	fishing_panel.queue_free()
	overlay.queue_free()
	hud.queue_free()
	await process_frame


func _scene_has_root_child(scene_path: String, child_name: String) -> bool:
	# Godot 4.7 writes the node's type into the header (`name="X" type="Y" parent=`),
	# so match the name, then a root parent anywhere later in the same header.
	var source := FileAccess.get_file_as_string(scene_path)
	var pattern := RegEx.new()
	pattern.compile("\\[node name=\"%s\"[^\\]]* parent=\"\\.\"" % child_name)
	return pattern.search(source) != null


func _stash_real_save() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		_backup_text = FileAccess.get_file_as_string(PROFILE_PATH)
		_had_backup = true


func _restore_real_save() -> void:
	if _had_backup:
		var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup_text)
			file.close()
		var snapshot: Dictionary = save.load_snapshot()
		inv.load_dict(snapshot.get("inventory", {}))
		farm.reload_from_save()
	else:
		save.clear()
		inv.reset()
		farm.reset(false)


func _finish() -> void:
	print("")
	print("PASS - saved weather affects crops, fishing, HUD, and outdoor scenes."
		if failures == 0 else "FAIL - %d weather check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_near(label: String, got: float, want: float, epsilon: float) -> void:
	check_true("%s (got %.12f, want %.12f)" % [label, got, want],
		absf(got - want) <= epsilon)
