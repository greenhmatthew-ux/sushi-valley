extends CanvasLayer
## Minimal dialogue box. Rebuild of DialogueBox.ts, pared to what the recall loop
## needs: a speaker name and one or more lines, advanced with the interact key or
## a click, closing with `dialogue_closed` so callers (the gate) can await it.
##
## Bus-driven: listens for `dialogue_open`, replies with `dialogue_closed`.

const COL_PANEL := Color(0.078, 0.106, 0.141, 0.98)
const COL_BORDER := Color(1.0, 0.824, 0.49)
const COL_NAME := Color(1.0, 0.824, 0.49)

var _active := false
var _lines: Array = []
var _line_index := 0

var _root: Control
var _name_label: Label
var _line_label: Label
var _hint_label: Label


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.dialogue_open.connect(_on_dialogue_open)


func _on_dialogue_open(speaker: String, lines: Array) -> void:
	if _active:
		return
	_lines = lines.duplicate()
	if _lines.is_empty():
		Bus.dialogue_closed.emit()
		return
	_line_index = 0
	_active = true
	get_tree().paused = true
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_show_line()
	_root.show()


func _show_line() -> void:
	_line_label.text = String(_lines[_line_index])
	_hint_label.text = "▸" if _line_index < _lines.size() - 1 else "▸ close"


func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_close()
	else:
		_show_line()


func _close() -> void:
	_active = false
	_root.hide()
	get_tree().paused = false
	Bus.dialogue_closed.emit()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed):
		_advance()
		get_viewport().set_input_as_handled()


func _build_scaffold() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	# Bottom strip, inset from the screen edges.
	panel.anchor_left = 0.08; panel.anchor_right = 0.92
	panel.anchor_top = 0.72; panel.anchor_bottom = 0.94
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", COL_NAME)
	vbox.add_child(_name_label)

	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", 16)
	_line_label.add_theme_color_override("font_color", Color.WHITE)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_line_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hint_label)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(12)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s
