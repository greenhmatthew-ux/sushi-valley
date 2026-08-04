extends Area2D
## A readable renewable resource in the world. Visuals are intentionally sparse
## and code-drawn so resource state is legible without turning the map into an
## icon grid; the real item icon and name appear in the Bag after gathering.

@export var node_id := "wilds_herb_1"
@export var display_name := "Wild Herb Patch"
@export var item_id := "wild_herb"
@export var base_qty := 2
@export var reset_days := 1
@export var skill_station := "kitchen"
@export var level_req := 1
@export_enum("herb", "ore", "bamboo") var resource_kind := "herb"
@export var required_tool_id := ""

var _phase := 0.0


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	Bus.gathering_changed.connect(_on_gathering_changed)
	Bus.farm_changed.connect(_refresh)
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	queue_redraw()


func interact(_player: Node = null) -> void:
	var result := Gathering.gather(node_id, item_id, base_qty, reset_days,
		skill_station, level_req, resource_kind, required_tool_id)
	if not bool(result.get("ok", false)):
		Bus.toast.emit(String(result.get("reason", "Nothing is ready to gather.")))
		return
	var item_name := String(DB.item(item_id).get("name", display_name))
	var bonus_text := ""
	if int(result.get("weather_bonus", 0)) > 0:
		bonus_text = " +1 weather bonus."
	var level_text := " %s reached Lv %d!" % [skill_station.capitalize(),
		int(result.get("level", 1))] if bool(result.get("leveled_up", false)) else ""
	Bus.toast.emit("Gathered %d %s. +%d %s XP.%s%s" % [
		int(result.get("qty", 0)), item_name, int(result.get("xp", 0)),
		skill_station.capitalize(), bonus_text, level_text])


func interaction_label() -> String:
	var remaining := Gathering.remaining_days(node_id, reset_days)
	if remaining == 1:
		return "%s returns tomorrow" % display_name
	if remaining > 1:
		return "%s returns in %d days" % [display_name, remaining]
	if not required_tool_id.is_empty() and not Inv.has(required_tool_id):
		return "Craft %s at %s" % [
			DB.item(required_tool_id).get("name", required_tool_id),
			Gathering.tool_source_label(required_tool_id)]
	var level := Crafting.station_level(skill_station)
	if level < level_req:
		return "Requires %s Lv %d" % [skill_station.capitalize(), level_req]
	return "Gather %s" % display_name


func _on_gathering_changed(changed_id: String) -> void:
	if changed_id.is_empty() or changed_id == node_id:
		_refresh()


func _refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var ready := Gathering.is_ready(node_id, reset_days)
	var alpha := 1.0 if ready else 0.36
	match resource_kind:
		"ore":
			_draw_ore(alpha)
		"bamboo":
			_draw_bamboo(alpha)
		_:
			_draw_herb(alpha)
	if ready:
		var glint_alpha := 0.35 + (sin(_phase * 2.0) + 1.0) * 0.18
		draw_circle(Vector2(11, -15), 1.5, Color(1.0, 0.9, 0.48, glint_alpha))
		draw_line(Vector2(11, -19), Vector2(11, -17),
			Color(1.0, 0.95, 0.7, glint_alpha), 1.0)
		draw_line(Vector2(8, -15), Vector2(9, -15),
			Color(1.0, 0.95, 0.7, glint_alpha), 1.0)
	else:
		draw_arc(Vector2(0, -4), 8.0, -PI * 0.2, PI * 1.35, 16,
			Color(0.75, 0.82, 0.88, 0.42), 1.0)
	if not required_tool_id.is_empty():
		_draw_tool_badge(Inv.has(required_tool_id))


func _draw_herb(alpha: float) -> void:
	var dark := Color(0.18, 0.42, 0.24, alpha)
	var leaf := Color(0.35, 0.68, 0.35, alpha)
	var light := Color(0.55, 0.82, 0.44, alpha)
	_draw_leaf_ellipse(Vector2(-6, -5), Vector2(5, 3), leaf)
	_draw_leaf_ellipse(Vector2(6, -6), Vector2(5, 3), light)
	_draw_leaf_ellipse(Vector2(0, -12), Vector2(4, 6), leaf)
	for x in [-7.0, 0.0, 7.0]:
		draw_line(Vector2(x, 1), Vector2(x * 0.55, -10), dark, 2.0)
	draw_rect(Rect2(-12, 0, 24, 3), Color(0.24, 0.36, 0.19, alpha))


func _draw_ore(alpha: float) -> void:
	var shadow := Color(0.16, 0.18, 0.2, alpha)
	var stone := Color(0.42, 0.46, 0.5, alpha)
	var face := Color(0.58, 0.63, 0.67, alpha)
	var copper := Color(0.78, 0.45, 0.25, alpha)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, 2), Vector2(-11, -9), Vector2(-2, -14),
		Vector2(7, -11), Vector2(15, -1), Vector2(10, 5), Vector2(-9, 6)]), shadow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-11, 0), Vector2(-8, -8), Vector2(-1, -11),
		Vector2(6, -8), Vector2(11, -1), Vector2(7, 2), Vector2(-7, 3)]), stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, -8), Vector2(-1, -11), Vector2(1, -5), Vector2(-4, -1)]), face)
	for fleck in [Vector2(-5, -5), Vector2(4, -4), Vector2(7, 0)]:
		draw_circle(fleck, 1.7, copper)


func _draw_bamboo(alpha: float) -> void:
	var dark := Color(0.16, 0.38, 0.2, alpha)
	var stalk := Color(0.42, 0.68, 0.3, alpha)
	var light := Color(0.64, 0.82, 0.34, alpha)
	for x in [-7.0, 0.0, 7.0]:
		var height := 24.0 - absf(x) * 0.45
		draw_rect(Rect2(x - 2, -height, 4, height + 3), stalk if x != 0 else light)
		for y in [-18.0, -11.0, -4.0]:
			draw_line(Vector2(x - 2, y), Vector2(x + 2, y), dark, 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, -height + 4), Vector2(x + 8, -height), Vector2(x + 3, -height + 7)]), dark)
	draw_rect(Rect2(-12, 1, 24, 3), Color(0.22, 0.34, 0.16, alpha))


func _draw_tool_badge(owned: bool) -> void:
	var color := UiTheme.STATE_SUCCESS if owned else UiTheme.ACCENT_GOLD
	draw_circle(Vector2(-13, -16), 5.0, Color(UiTheme.SURFACE_DEEP, 0.92))
	draw_arc(Vector2(-13, -16), 5.0, 0.0, TAU, 12, color, 1.0)
	# Tiny readable silhouettes: pick, axe, and sickle respectively. The full CC0
	# item art stays in recipes/Bag; this badge only says "a tool matters here."
	match resource_kind:
		"ore":
			draw_line(Vector2(-15, -19), Vector2(-10, -14), color, 1.2)
			draw_line(Vector2(-17, -18), Vector2(-12, -20), color, 1.2)
		"bamboo":
			draw_line(Vector2(-16, -13), Vector2(-11, -19), color, 1.2)
			draw_rect(Rect2(-14, -20, 5, 2), color)
		_:
			draw_arc(Vector2(-13, -16), 3.0, -PI * 0.45, PI * 0.55, 8, color, 1.2)
			draw_line(Vector2(-15, -14), Vector2(-11, -18), color, 1.2)


func _draw_leaf_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
