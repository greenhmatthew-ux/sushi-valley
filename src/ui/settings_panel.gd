extends CanvasLayer
## Settings: how close the camera sits, and whether English is pinned on screen.
##
## Opened with the `open_settings` action. Built in code to match the other panels
## (recall/inventory/shop), which are all code-built because their contents are dynamic
## and authoring them as .tscn would fight that.
##
## Writes straight to the Settings autoload, which persists to its own user://settings.cfg
## and announces changes on the Bus — this panel never pokes the camera or dialogue itself.

const COL_DIM := Color(0.02, 0.03, 0.047, 0.6)
const COL_PANEL := Color(0.078, 0.106, 0.141, 0.98)
const COL_BORDER := Color(1.0, 0.824, 0.49)
const COL_HEADING := Color(0.624, 0.69, 0.765)
const COL_TEXT := Color(0.93, 0.95, 0.96)
const COL_HINT := Color(0.624, 0.839, 1.0)

var _open := false
var _root: Control
var _zoom_label: Label
var _zoom_slider: HSlider
var _english_check: CheckButton


func _ready() -> void:
	layer = 22   # above the other panels; settings should always be reachable
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_settings"):
		_set_open(not _open)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	if open:
		_sync_from_settings()
		_root.show()
		get_tree().paused = true
		_zoom_slider.grab_focus()
	else:
		_root.hide()
		get_tree().paused = false


func _sync_from_settings() -> void:
	_zoom_slider.set_value_no_signal(Settings.zoom)
	_english_check.set_pressed_no_signal(Settings.show_english)
	_update_zoom_label()


func _update_zoom_label() -> void:
	# Phrase it as what the player perceives, not the raw multiplier.
	var z: float = _zoom_slider.value
	var feel := "further out" if z < Settings.ZOOM_DEFAULT else ("closer in" if z > Settings.ZOOM_DEFAULT else "default")
	_zoom_label.text = "Camera zoom:  %.1fx   (%s)" % [z, feel]


func _on_zoom_changed(value: float) -> void:
	Settings.zoom = value
	_update_zoom_label()


func _on_english_toggled(pressed: bool) -> void:
	Settings.show_english = pressed


# --- scaffold ---------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(460, 0)
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	vbox.add_child(_heading("Settings"))

	# --- camera zoom ---
	_zoom_label = _label(15, COL_TEXT)
	vbox.add_child(_zoom_label)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = Settings.ZOOM_MIN
	_zoom_slider.max_value = Settings.ZOOM_MAX
	_zoom_slider.step = Settings.ZOOM_STEP
	_zoom_slider.custom_minimum_size = Vector2(0, 24)
	_zoom_slider.focus_mode = Control.FOCUS_ALL
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	vbox.add_child(_zoom_slider)

	vbox.add_child(_hint("Lower = see more of the map."))
	vbox.add_child(_spacer(6))

	# --- language ---
	vbox.add_child(_heading("Language"))
	_english_check = CheckButton.new()
	_english_check.text = "Always show English"
	_english_check.focus_mode = Control.FOCUS_ALL
	_english_check.add_theme_font_size_override("font_size", 15)
	_english_check.toggled.connect(_on_english_toggled)
	vbox.add_child(_english_check)

	vbox.add_child(_hint("The valley speaks Japanese. Hold TAB anywhere to peek at the English."))
	vbox.add_child(_spacer(6))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 32)
	close.focus_mode = Control.FOCUS_ALL
	close.pressed.connect(func(): _set_open(false))
	vbox.add_child(close)


func _heading(text: String) -> Label:
	var l := _label(18, COL_BORDER)
	l.text = text
	return l


func _hint(text: String) -> Label:
	var l := _label(12, COL_HINT)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s
