extends Control
## Focusable world-route graph built entirely from data/game/world-regions.json.
##
## This is deliberately read-only. It explains the authored route network and
## distinguishes playable regions from planned geography without inventing fast
## travel, discovery flags, or entrances that do not exist in runtime scenes.

signal region_focused(region_id: String)

const NODE_SIZE := Vector2(18, 18)
const EDGE_PAD := Vector2(16, 12)

var _regions: Dictionary = {}
var _nodes: Dictionary = {}
var _labels: Dictionary = {}
var _connections: Array[PackedStringArray] = []
var _selected_id := ""


func _ready() -> void:
	name = "WorldMapGraph"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 90)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_layout_nodes)


func configure(regions: Dictionary, current_region_id: String = "") -> void:
	_regions = regions.duplicate(true)
	_selected_id = ""
	_nodes.clear()
	_labels.clear()
	_connections.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_connections()
	for raw_id in _regions:
		_add_region_node(String(raw_id), _regions[raw_id], String(raw_id) == current_region_id)
	_layout_nodes()
	queue_redraw()
	var initial := current_region_id if _nodes.has(current_region_id) else _first_playable_id()
	if not initial.is_empty():
		focus_region(initial, false)


func connection_count() -> int:
	return _connections.size()


func selected_region_id() -> String:
	return _selected_id


func focus_region(region_id: String, grab: bool = true) -> void:
	if not _nodes.has(region_id):
		return
	_selected_id = region_id
	region_focused.emit(region_id)
	if grab:
		(_nodes[region_id] as Button).grab_focus()


func _build_connections() -> void:
	var seen: Dictionary = {}
	for raw_from in _regions:
		var from := String(raw_from)
		var region: Dictionary = _regions[raw_from]
		for raw_to in region.get("connects", []):
			var to := String(raw_to)
			if not _regions.has(to) or to == from:
				continue
			var ordered := [from, to]
			ordered.sort()
			var key := "%s|%s" % ordered
			if seen.has(key):
				continue
			seen[key] = true
			_connections.append(PackedStringArray(ordered))


func _add_region_node(region_id: String, region: Dictionary, current: bool) -> void:
	var playable := String(region.get("status", "")) == "playable"
	var accent := UiTheme.ACCENT_GOLD if current else (
		UiTheme.STATE_SUCCESS if playable else UiTheme.BORDER_STRONG)
	var button := Button.new()
	button.name = "RegionNode_" + region_id
	button.text = "" if playable else "?"
	button.custom_minimum_size = NODE_SIZE
	button.size = NODE_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s — %s" % [region.get("name", region_id),
		"You are here" if current else ("Open" if playable else "Not built yet")]
	button.set_meta("region_id", region_id)
	button.set_meta("status", "current" if current else ("playable" if playable else "planned"))
	button.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	button.add_theme_stylebox_override("normal", _node_style(UiTheme.SURFACE_RAISED, accent, 2))
	button.add_theme_stylebox_override("hover", _node_style(UiTheme.SURFACE_RAISED.lightened(0.08), accent, 2))
	button.add_theme_stylebox_override("pressed", _node_style(UiTheme.SURFACE_DEEP, accent, 2))
	button.add_theme_stylebox_override("focus", _node_style(UiTheme.SURFACE_RAISED, UiTheme.ACCENT_GOLD, 3))
	button.focus_entered.connect(focus_region.bind(region_id, false))
	button.pressed.connect(focus_region.bind(region_id, false))
	add_child(button)
	_nodes[region_id] = button

	# Name the real route without filling the planned frontier with overlapping
	# placeholder labels. Planned nodes remain focusable and reveal their honest name.
	if playable:
		var label := Label.new()
		label.name = "RegionLabel_" + region_id
		label.text = String(region.get("name", region_id))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		label.add_theme_color_override("font_color", accent)
		add_child(label)
		_labels[region_id] = label


func _layout_nodes() -> void:
	if _nodes.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	for raw_id in _nodes:
		var region_id := String(raw_id)
		var center := _region_center(_regions[region_id])
		var button: Button = _nodes[region_id]
		button.position = (center - NODE_SIZE * 0.5).round()
		button.size = NODE_SIZE
		if _labels.has(region_id):
			var label: Label = _labels[region_id]
			label.position = (center + Vector2(13, -8)).round()
			label.size = Vector2(maxf(0.0, size.x - label.position.x - 2.0), 16)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SURFACE_DEEP, true)
	for edge in _connections:
		var from := String(edge[0])
		var to := String(edge[1])
		if not _regions.has(from) or not _regions.has(to):
			continue
		var both_open := String(_regions[from].get("status", "")) == "playable" \
			and String(_regions[to].get("status", "")) == "playable"
		draw_line(_region_center(_regions[from]), _region_center(_regions[to]),
			UiTheme.STATE_SUCCESS.darkened(0.25) if both_open else UiTheme.BORDER_SUBTLE,
			2.0 if both_open else 1.0, true)


func _region_center(region: Dictionary) -> Vector2:
	var x := clampf(float(region.get("x", 0.5)), 0.0, 1.0)
	var y := clampf(float(region.get("y", 0.5)), 0.0, 1.0)
	return Vector2(
		lerpf(EDGE_PAD.x, maxf(EDGE_PAD.x, size.x - EDGE_PAD.x), x),
		lerpf(EDGE_PAD.y, maxf(EDGE_PAD.y, size.y - EDGE_PAD.y), y))


func _first_playable_id() -> String:
	for raw_id in _regions:
		if String(_regions[raw_id].get("status", "")) == "playable":
			return String(raw_id)
	return ""


func _node_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(9)
	style.set_border_width_all(width)
	style.border_color = border
	return style
