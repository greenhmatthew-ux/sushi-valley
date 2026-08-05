extends Area2D
## A readable renewable resource in the world.
##
## The node itself used to be `draw_colored_polygon` shapes — a grey blob for ore, green
## ellipses for a herb. Next to the tiled world those read as placeholder geometry. The
## object is now real Ninja Adventure nature art (CC0, the project's character/prop canon).
##
## What stays drawn in code is only *state*, because none of it exists as art: the ready
## glint, the depleted arc, the permanent-tool badge, and the gather burst. Those are the
## affordances that tell the player whether walking over is worth it, so they are kept.
##
## Ore art is chosen by the item, not just the kind. Copper and iron seams were previously
## the same grey blob with the same orange flecks, so the only way to tell a Copper Seam
## from an Iron Seam was to walk up and read the prompt. Tan rock is copper, grey rock is
## iron, which is what the ores themselves look like.

## Ninja Adventure `Backgrounds/Tilesets/TilesetNature.png`, 24x21 tiles of 16px.
const Art := preload("res://src/systems/world_art_catalog.gd")
const NATURE_SHEET := Art.NATURE_SHEET
## Isolated single-tile boulders, not slices of the big multi-tile clusters beside them.
const ROCK_TAN := Art.ROCK_TAN
const ROCK_GREY := Art.ROCK_GREY
## Leafy plant and tall blades from the same sheet's plant rows.
const PLANT_HERB := Art.PLANT_HERB
const PLANT_BAMBOO := Art.PLANT_BAMBOO
## Ores that read as grey stone. Anything else falls back to the tan rock.
const GREY_ORES := Art.GREY_ORES

@export var node_id := "wilds_herb_1"
@export var display_name := "Wild Herb Patch"
@export var item_id := "wild_herb"
@export var base_qty := 2
@export var reset_days := 1
@export var skill_station := "kitchen"
@export var level_req := 1
@export_enum("herb", "ore", "bamboo") var resource_kind := "herb"
@export var required_tool_id := ""

const FEEDBACK_SECONDS := 0.8

var _phase := 0.0
var _burst_time := 0.0
var _burst_qty := 0
var _body: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	_build_body()
	Gathering.register_node(node_id, reset_days)
	Bus.gathering_changed.connect(_on_gathering_changed)
	Bus.farm_changed.connect(_refresh)
	_refresh()


## Feet on the node origin, matching every other standing thing in the world so Y-sort
## and placement behave the same way they do for props.
func _build_body() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = NATURE_SHEET
	atlas.region = _body_region()
	atlas.filter_clip = true
	_body = Sprite2D.new()
	_body.name = "Body"
	_body.texture = atlas
	_body.offset = Vector2(0, -8)
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)


func _body_region() -> Rect2:
	match resource_kind:
		"ore":
			return ROCK_GREY if item_id in GREY_ORES else ROCK_TAN
		"bamboo":
			return PLANT_BAMBOO
		_:
			return PLANT_HERB


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	_burst_time = maxf(0.0, _burst_time - delta)
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
	_start_feedback(int(result.get("qty", 0)))
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
	if _body != null:
		# A depleted node stays visible but fades: the rock did not leave, it is spent.
		_body.modulate.a = 1.0 if Gathering.is_ready(node_id, reset_days) else 0.36
	queue_redraw()


func _draw() -> void:
	var ready := Gathering.is_ready(node_id, reset_days)
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
	if _burst_time > 0.0:
		_draw_gather_burst()


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


func _start_feedback(quantity: int) -> void:
	_burst_time = FEEDBACK_SECONDS
	_burst_qty = maxi(1, quantity)
	var previous := get_node_or_null("GatherFeedback")
	if previous != null:
		previous.queue_free()
	var label := Label.new()
	label.name = "GatherFeedback"
	label.text = "+%d" % _burst_qty
	label.position = Vector2(-18, -35)
	label.size = Vector2(36, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 8
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", _resource_feedback_color())
	label.add_theme_color_override("font_outline_color", UiTheme.SURFACE_DEEP)
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -47.0, FEEDBACK_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FEEDBACK_SECONDS * 0.55) \
		.set_delay(FEEDBACK_SECONDS * 0.45)
	tween.chain().tween_callback(label.queue_free)


func _draw_gather_burst() -> void:
	var progress := 1.0 - (_burst_time / FEEDBACK_SECONDS)
	var color := _resource_feedback_color()
	color.a = _burst_time / FEEDBACK_SECONDS
	for i in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / 8.0)
		var start := Vector2(0, -7) + direction * (4.0 + progress * 5.0)
		var finish := Vector2(0, -7) + direction * (8.0 + progress * 10.0)
		draw_line(start, finish, color, 1.5)
	draw_circle(Vector2(0, -7), maxf(1.0, 4.0 - progress * 3.0), color)


func _resource_feedback_color() -> Color:
	match resource_kind:
		"ore": return Color(0.96, 0.58, 0.3)
		"bamboo": return Color(0.7, 0.9, 0.38)
		_: return Color(0.5, 0.92, 0.52)
