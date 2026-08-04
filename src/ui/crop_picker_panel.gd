extends CanvasLayer
## Small seed picker opened only from an empty world plot. It lists real owned
## seeds, authored grow time, and season eligibility with keyboard/controller focus.

var _open := false
var _plot_id := ""
var _root: Control
var _subtitle: Label
var _list: VBoxContainer
var _cancel_button: Button


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Bus.farm_plot_open.connect(_on_open)
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))


func _on_open(plot_id: String) -> void:
	if _open or get_tree().paused:
		return
	var crops := Farm.available_crops()
	if crops.is_empty():
		Bus.toast.emit("No seeds in your Bag. Look for the starter seed cache by the plots.")
		return
	_plot_id = plot_id
	_open = true
	_refresh(crops)
	_root.show()
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _refresh(crops: Array[Dictionary]) -> void:
	_subtitle.text = "%s - Pick one owned seed. Off-season crops stay disabled." % Farm.clock_text()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var first: Button = null
	for crop in crops:
		var seed_id := String(crop.get("seedItem", ""))
		var in_season := Farm.is_in_season(crop)
		var button := Button.new()
		button.name = "PlantCrop_" + String(crop.get("id", ""))
		button.text = "%s x%d - %dd - %s" % [
			DB.item(seed_id).get("name", seed_id), Inv.count(seed_id), int(crop.get("days", 1)),
			"In season" if in_season else "Off season"]
		var season_names := PackedStringArray()
		for season in crop.get("seasons", []):
			season_names.append(String(season).capitalize())
		button.tooltip_text = "Grows in %s." % ", ".join(season_names)
		button.disabled = not in_season
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, 34)
		button.pressed.connect(_on_plant.bind(String(crop.get("id", ""))))
		_list.add_child(button)
		if first == null and in_season:
			first = button
	if first != null:
		first.grab_focus.call_deferred()
	else:
		_cancel_button.grab_focus.call_deferred()


func _on_plant(crop_id: String) -> void:
	var result := Farm.plant(_plot_id, crop_id)
	if result.get("ok", false):
		Bus.toast.emit("Planted %s - watered for today." % \
			(result.get("crop", {}) as Dictionary).get("name", crop_id))
		_close()
	else:
		Bus.toast.emit(String(result.get("reason", "Could not plant that seed.")))


func _close() -> void:
	_open = false
	_plot_id = ""
	_root.hide()
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.name = "CropPickerRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)
	var dim := ColorRect.new()
	dim.color = UiTheme.SURFACE_BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var shell := PanelContainer.new()
	shell.name = "CropPickerShell"
	UiTheme.fit_modal_shell(shell)
	shell.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.STATE_SUCCESS))
	_root.add_child(shell)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	shell.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(UiTheme.label("Plant a Seed", UiTheme.FONT_TITLE, UiTheme.ACCENT_GOLD))
	_subtitle = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_subtitle)
	_list = VBoxContainer.new()
	_list.name = "CropChoices"
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelPlanting"
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_close)
	box.add_child(_cancel_button)
