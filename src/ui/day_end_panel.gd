extends CanvasLayer
## Explicit sleep confirmation. Advancing time is never a surprise: the panel
## names tomorrow, crop behavior, and the full-heal effect before committing.

var _open := false
var _root: Control
var _title: Label
var _detail: Label


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Bus.sleep_requested.connect(_on_open)
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))


func _on_open() -> void:
	if _open or get_tree().paused:
		return
	_open = true
	_title.text = "Rest until %s?" % Farm.next_clock_text()
	var current_weather := WeatherSystem.current()
	var crop_note := "Rain or snow is watering every planted crop today." \
		if WeatherSystem.is_precipitation(current_weather) \
		else "Watered crops advance today; dry crops pause without withering."
	var resource_note := _resource_preview_text(Gathering.preview_next_day())
	_detail.text = "You wake fully healed. %s%s Tomorrow: %s." % [
		crop_note, (" " + resource_note) if not resource_note.is_empty() else "",
		WeatherSystem.display_name(WeatherSystem.tomorrow())]
	_root.show()
	get_tree().paused = true
	(_root.find_child("ConfirmSleep", true, false) as Button).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _on_sleep() -> void:
	var resource_preview := Gathering.preview_next_day()
	var result := Farm.advance_day()
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_hp"):
		player.set_hp(int(player.MAX_HP))
	_close()
	var season_note := " A new season begins." if result.get("new_season", false) else ""
	var crop_note := " Precipitation watered every planted crop." \
		if WeatherSystem.is_precipitation(String(result.get("previous_weather", ""))) \
		else " Watered crops grew; dry crops paused."
	var resource_note := ""
	var returning := int(resource_preview.get("returning", 0))
	if returning > 0:
		resource_note = " %d resource node%s renewed." % [
			returning, "" if returning == 1 else "s"]
	Bus.toast.emit("%s begins - %s.%s%s%s" % [Farm.clock_text(),
		WeatherSystem.display_name(String(result.get("weather", WeatherSystem.current()))),
		season_note, crop_note, resource_note])


func _resource_preview_text(preview: Dictionary) -> String:
	var returning := int(preview.get("returning", 0))
	var waiting := int(preview.get("waiting", 0))
	if returning <= 0 and waiting <= 0:
		return ""
	var parts: Array[String] = []
	if returning > 0:
		parts.append("%d gathered resource node%s return tomorrow" % [
			returning, "" if returning == 1 else "s"])
	if waiting > 0:
		parts.append("%d rare node%s need more time" % [
			waiting, "" if waiting == 1 else "s"])
	return "%s." % "; ".join(parts)


func _close() -> void:
	_open = false
	_root.hide()
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.name = "DayEndRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)
	var dim := ColorRect.new()
	dim.color = UiTheme.SURFACE_BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var shell := PanelContainer.new()
	shell.name = "DayEndShell"
	UiTheme.fit_modal_shell(shell)
	shell.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.ACCENT_GOLD))
	_root.add_child(shell)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	shell.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_title = UiTheme.label("", UiTheme.FONT_TITLE, UiTheme.ACCENT_GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_detail = UiTheme.label(
		"You wake fully healed. Watered crops advance one day; dry crops pause without withering.",
		UiTheme.FONT_SECTION, UiTheme.TEXT_PRIMARY)
	_detail.name = "DayEndDetail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var sleep := Button.new()
	sleep.name = "ConfirmSleep"
	sleep.text = "Sleep"
	sleep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sleep.pressed.connect(_on_sleep)
	buttons.add_child(sleep)
	var cancel := Button.new()
	cancel.name = "CancelSleep"
	cancel.text = "Stay awake"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close)
	buttons.add_child(cancel)
