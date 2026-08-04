extends CanvasLayer
## "Previously" — the returning-player card (UI_UX_GUIDE section 6).
##
## Shown once per launch, before input reaches the world, when a save from a
## previous session holds something actionable: a quest ready to turn in, one in
## progress, reviews due, or points to spend. A first-ever session, or a return
## with nothing waiting, never sees it. One Continue action and nothing else —
## this is a hook back into the loop, not a report to read.

const Summary = preload("res://src/systems/session_summary.gd")
const Activities = preload("res://src/systems/activity_tracker.gd")

const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_TITLE := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const KIND_COLORS := {
	"ready": UiTheme.ACCENT_GOLD,
	"active": UiTheme.TEXT_PRIMARY,
	"mission": UiTheme.STATE_SUCCESS,
	"more": UiTheme.TEXT_MUTED,
	"review": UiTheme.STATE_INFO,
	"points": UiTheme.STATE_SUCCESS,
}

## Survives scene changes (each level instances its own ui_layer), so walking
## through a door mid-session can never re-open the card.
static var _shown_this_launch := false

var _root: Control


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deferred past the owning scene's _ready: quest progress is measured from
	# what the player is carrying, and world.gd restores the bag in _load_game.
	_maybe_show.call_deferred()
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))


func _maybe_show() -> void:
	if _shown_this_launch:
		return
	_shown_this_launch = true
	# Only a real game launch has a current_scene; a test or tool that instances
	# a level by hand does not, and an unexpected pause there breaks physics and
	# input for everything sharing the tree.
	if get_tree().current_scene == null:
		return
	# Boot-time state, not has_save(): the bag autosaves within the first frames
	# of a new game, so "a file exists now" would greet a first-time player with
	# "Welcome back".
	if not SaveGame.had_save_at_boot:
		return
	var model: Dictionary = Summary.build(
		Activities.actionable_entries(Learning.profile, DB, Inv),
		Learning.due_count(),
		Learning.unspent_talent_points(),
		Learning.unspent_attribute_points(),
		Activities.tracked_key(Learning.profile))
	if not model["show"]:
		return
	_show_model(model)


func _show_model(model: Dictionary) -> void:
	_build(model)
	get_tree().paused = true


func _close() -> void:
	get_tree().paused = false
	if _root != null:
		_root.queue_free()
		_root = null


func _unhandled_input(event: InputEvent) -> void:
	if _root != null and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _build(model: Dictionary) -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	# Centered and content-sized: the line count is capped by SessionSummary,
	# so unlike the notebook this can never outgrow the screen.
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 0)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := _label(18, COL_TITLE)
	title.text = "Welcome back"
	vbox.add_child(title)

	var subtitle := _label(11, COL_HEADING)
	subtitle.text = "Waiting for you since last time:"
	vbox.add_child(subtitle)

	for line in model["lines"]:
		var kind := String(line.get("kind", "active"))
		var l := _label(13, KIND_COLORS.get(kind, UiTheme.TEXT_PRIMARY))
		l.text = String(line.get("text", ""))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 364
		vbox.add_child(l)

	var button := Button.new()
	button.name = "ContinueButton"
	button.text = "Continue"
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(120, 34)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_close)
	vbox.add_child(button)
	button.grab_focus()


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
