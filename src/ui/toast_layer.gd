extends CanvasLayer
## Transient notifications. Rebuild of Toast.ts, pared down: shows one message at
## a time near the bottom of the screen, fading after a couple of seconds.
##
## Bus-driven: listens for `toast`. Runs while paused (process ALWAYS) so a
## session-summary toast emitted just before the world unpauses still appears.

const HOLD_SECONDS := 2.2
const FADE_SECONDS := 0.4

var _label: Label
var _panel: PanelContainer
var _tween: Tween


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Bus.toast.connect(_on_toast)


func _on_toast(text: String) -> void:
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 1.0
	_panel.show()
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(_panel.hide)


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.824, 0.49, 0.8)
	for side in ["left", "right"]:
		style.set("content_margin_" + side, 16)
	for side in ["top", "bottom"]:
		style.set("content_margin_" + side, 10)
	_panel.add_theme_stylebox_override("panel", style)
	# Bottom-center strip.
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 0.86; _panel.anchor_bottom = 0.86
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.96))
	_panel.add_child(_label)
	_panel.hide()
