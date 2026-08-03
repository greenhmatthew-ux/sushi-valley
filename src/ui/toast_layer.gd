extends CanvasLayer
## Transient notifications. Rebuild of Toast.ts.
##
## Bus-driven: listens for `toast`. Runs while paused (process ALWAYS) so a
## session-summary toast emitted just before the world unpauses still appears.
##
## What to show and for how long is ToastFeed's call (queueing, ×N aggregation,
## faster turnover under a backlog) — this layer only renders its answer. It
## also slides up out of the bottom band while dialogue or combat own it, per
## the section 5 rule that notifications never overlap either.

const Feed = preload("res://src/systems/toast_feed.gd")

const FADE_SECONDS := 0.4
## Bottom-center strip in normal play.
const ANCHOR_NORMAL := 0.86
## Dialogue reserves the bottom 190px and the combat panel's action row lives
## there too, so while either is open the strip sits just above that band
## (0.40 × 360 ≈ 144, clearing the dialogue top at 170 with its half-height).
const ANCHOR_LIFTED := 0.40

var _feed := Feed.new()
var _label: Label
var _panel: PanelContainer
var _tween: Tween
## Tracked separately (not one counter) because their signals are not strictly
## paired: the dialogue box ignores an open while already active, and an open
## with no lines answers straight back with closed. Re-setting a bool is
## harmless where a counter would drift.
var _dialogue_up := false
var _combat_up := false
## Scaling root — the strip anchors inside this, not the raw viewport.
var _root: Control


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Bus.toast.connect(_on_toast)
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	Bus.dialogue_open.connect(func(_speaker, _lines): _set_lift(true, _combat_up))
	Bus.dialogue_closed.connect(func(): _set_lift(false, _combat_up))
	Bus.combat_started.connect(func(_id): _set_lift(_dialogue_up, true))
	Bus.combat_ended.connect(func(_victory): _set_lift(_dialogue_up, false))


func _process(_delta: float) -> void:
	if not _feed.tick(_now()):
		return
	if _feed.is_showing():
		_show_current()
	else:
		_fade_out()


func _on_toast(text: String) -> void:
	if _feed.push(text, _now()):
		_show_current()


func _show_current() -> void:
	_label.text = _feed.display_text()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 1.0
	_panel.show()


func _fade_out() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(_panel.hide)


func _set_lift(dialogue_up: bool, combat_up: bool) -> void:
	_dialogue_up = dialogue_up
	_combat_up = combat_up
	var anchor := ANCHOR_LIFTED if (_dialogue_up or _combat_up) else ANCHOR_NORMAL
	_panel.anchor_top = anchor
	_panel.anchor_bottom = anchor


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiTheme.fit_layer(self, _root)

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
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = ANCHOR_NORMAL; _panel.anchor_bottom = ANCHOR_NORMAL
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	_panel.add_child(_label)
	_panel.hide()
