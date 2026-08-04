extends Area2D
## One visible, saved crop plot. Interaction stays context-first: empty plots
## open the seed picker, dry crops water, and mature crops harvest.

@export var plot_id := "valley_plot_1"

const SOIL := Color("#8a5d3d")
const WET_SOIL := Color("#654331")
const BORDER := Color("#5c4433")
const WATER := Color("#81d4fa")
const LEAF := Color("#66bb6a")
const LEAF_LIGHT := Color("#9be7a3")


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	Farm.register_plot(plot_id)
	Bus.farm_changed.connect(_refresh)
	_refresh()


func interact(_player: Node = null) -> void:
	var state := Farm.plot(plot_id)
	if String(state.get("cropId", "")).is_empty():
		Bus.farm_plot_open.emit(plot_id)
		return
	var crop: Dictionary = Farm.crop_def_for_plot(plot_id)
	if Farm.is_ready(plot_id):
		var result := Farm.harvest(plot_id)
		if result.get("ok", false):
			Bus.toast.emit("Harvested %s." % crop.get("name", "crop"))
		else:
			Bus.toast.emit(String(result.get("reason", "Could not harvest.")))
	elif not bool(state.get("watered", false)) and WeatherSystem.is_precipitation():
		Bus.toast.emit("%s is being watered by the %s. Rest when ready." % [
			crop.get("name", "Crop"), WeatherSystem.display_name().to_lower()])
	elif not bool(state.get("watered", false)):
		if Farm.water(plot_id):
			Bus.toast.emit("Watered the %s." % crop.get("name", "crop"))
	else:
		var remaining := Farm.days_remaining(plot_id)
		Bus.toast.emit("%s - %d day%s remaining. Rest at home when ready." % [
			crop.get("name", "Crop"), remaining, "" if remaining == 1 else "s"])


func interaction_label() -> String:
	var state := Farm.plot(plot_id)
	if String(state.get("cropId", "")).is_empty():
		return "Plant a seed"
	var crop: Dictionary = Farm.crop_def_for_plot(plot_id)
	var name := String(crop.get("name", "crop"))
	if Farm.is_ready(plot_id):
		return "Harvest %s" % name
	if not bool(state.get("watered", false)) and WeatherSystem.is_precipitation():
		return "%s waters %s" % [WeatherSystem.display_name(), name]
	if not bool(state.get("watered", false)):
		return "Water %s" % name
	return "Check %s" % name


func _refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var state := Farm.plot(plot_id)
	var watered := bool(state.get("watered", false)) or WeatherSystem.is_precipitation()
	draw_rect(Rect2(-13, -6, 26, 12), BORDER)
	draw_rect(Rect2(-11, -5, 22, 10), WET_SOIL if watered else SOIL)
	draw_line(Vector2(-8, -2), Vector2(8, -2), Color(BORDER, 0.8), 1.0)
	draw_line(Vector2(-8, 2), Vector2(8, 2), Color(BORDER, 0.8), 1.0)
	if watered:
		draw_rect(Rect2(-9, 4, 18, 2), WATER)
	var crop_id := String(state.get("cropId", ""))
	if crop_id.is_empty():
		return
	_draw_crop(crop_id, Farm.stage(plot_id))


func _draw_crop(crop_id: String, stage: int) -> void:
	var height := 5 if stage <= 1 else (9 if stage == 2 else 14)
	match crop_id:
		"rice":
			for x in [-5, 0, 5]:
				draw_rect(Rect2(x - 1, -height - 3, 2, height), LEAF)
				if stage == 3:
					draw_rect(Rect2(x - 1, -height - 4, 3, 3), Color("#ffd54f"))
		"cucumber":
			draw_circle(Vector2(0, -6), float(height) * 0.45, LEAF)
			if stage == 3:
				draw_rect(Rect2(2, -6, 8, 4), LEAF_LIGHT)
		"mushroom":
			draw_rect(Rect2(-2, -height, 4, height - 3), Color("#d7ccc8"))
			draw_circle(Vector2(0, -height), float(height) * 0.42, Color("#8d6e63"))
		"herb":
			var radius := 2.0 if stage <= 1 else (4.0 if stage == 2 else 6.0)
			for offset in [Vector2(-4, -5), Vector2(4, -5), Vector2(0, -9)]:
				draw_circle(offset, radius, LEAF)
			draw_circle(Vector2(0, -6), radius * 0.45, LEAF_LIGHT)
		_:
			draw_rect(Rect2(-1, -height, 2, height), LEAF)
			draw_circle(Vector2(0, -height), 3.0, LEAF_LIGHT)
