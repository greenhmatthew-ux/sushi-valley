extends CanvasLayer
## Station-scoped recipe list. One scroll owner, exact material counts, one Craft action,
## and no global crafting tab: the visible world station is the entry point.

const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_TEXT := UiTheme.TEXT_PRIMARY
const COL_MUTED := UiTheme.TEXT_MUTED
const COL_CARD := UiTheme.SURFACE_RAISED

var _open := false
var _station := ""
var _root: Control
var _title: Label
var _progress: Label
var _list: VBoxContainer
var _input_hint: Label


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Bus.crafting_open.connect(_on_open)
	Bus.crafting_changed.connect(func(station): if _open and station == _station: _refresh())
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	Bus.input_method_changed.connect(func(_method): _refresh_input_hint())


func _on_open(station: String) -> void:
	if _open or get_tree().paused:
		return
	_station = station
	_open = true
	_refresh()
	_root.show()
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	_open = false
	_root.hide()
	get_tree().paused = false


func _refresh() -> void:
	_title.text = _station.capitalize()
	_progress.text = "Level %d · Recipes use this station's own XP." % Crafting.station_level(_station)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var first: Button = null
	for recipe in Crafting.recipes_for_station(_station):
		var row := _recipe_row(recipe)
		_list.add_child(row)
		var button: Button = row.get_meta("craft_button")
		if first == null and not button.disabled:
			first = button
	if first != null:
		first.grab_focus.call_deferred()


func _recipe_row(recipe: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var output: Dictionary = recipe.get("output", {})
	var heading := Label.new()
	heading.text = "%s  →  %s x%d" % [recipe.get("name", "Recipe"),
		DB.item(String(output.get("item", ""))).get("name", output.get("item", "")),
		int(output.get("qty", 0))]
	heading.add_theme_font_size_override("font_size", UiTheme.FONT_META)
	heading.add_theme_color_override("font_color", COL_TEXT)
	info.add_child(heading)
	var output_item: Dictionary = DB.item(String(output.get("item", "")))
	var output_detail := _item_detail(output_item)
	if not output_detail.is_empty():
		var output_label := Label.new()
		output_label.name = "CraftOutputDetail"
		output_label.text = output_detail
		output_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		output_label.add_theme_color_override("font_color", COL_MUTED)
		info.add_child(output_label)
	var ingredients: Array[String] = []
	for input in recipe.get("inputs", []):
		var item_id := String(input.get("item", ""))
		ingredients.append("%s %d/%d" % [DB.item(item_id).get("name", item_id),
			Inv.count(item_id), int(input.get("qty", 0))])
	var detail := Label.new()
	detail.text = " · ".join(ingredients)
	detail.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	detail.add_theme_color_override("font_color", COL_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(detail)
	var status: Dictionary = Crafting.recipe_status(recipe, _station)
	var button := Button.new()
	button.text = "Craft" if status.get("ok", false) else String(status.get("reason", "Locked"))
	button.disabled = not bool(status.get("ok", false))
	button.custom_minimum_size = Vector2(118, 32)
	button.pressed.connect(_on_craft.bind(String(recipe.get("id", ""))))
	row.add_child(button)
	panel.set_meta("craft_button", button)
	return panel


func _on_craft(recipe_id: String) -> void:
	var result := Crafting.craft(recipe_id, _station)
	if result.get("ok", false):
		var output: Dictionary = result["output"]
		var item: Dictionary = DB.item(String(output["item"]))
		var equip_hint := " Equip in Menu > Bag." if String(item.get("kind", "")) == "gear" else ""
		Bus.toast.emit("Crafted %s x%d · +%d XP.%s" % [
			item.get("name", output["item"]), output["qty"], result["xp"], equip_hint])
	else:
		Bus.toast.emit(String(result.get("reason", "Could not craft.")))


func _item_detail(def: Dictionary) -> String:
	if String(def.get("kind", "")) != "gear":
		return ""
	var parts: Array[String] = []
	var weapon_type := String(def.get("weaponType", ""))
	if not weapon_type.is_empty():
		parts.append("%s weapon" % weapon_type.capitalize())
	for stat in ["atk", "def", "hp", "spd"]:
		var amount := int(def.get("stats", {}).get(stat, 0))
		if amount != 0:
			parts.append("%s %s%d" % [stat.to_upper(), "+" if amount > 0 else "", amount])
	return " · ".join(parts)


func _build() -> void:
	_root = Control.new()
	_root.name = "CraftingRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)
	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "CraftingShell"
	UiTheme.fit_modal_shell(panel)
	var shell_style := StyleBoxFlat.new()
	shell_style.bg_color = COL_PANEL
	shell_style.set_corner_radius_all(14)
	shell_style.set_border_width_all(3)
	shell_style.border_color = COL_BORDER
	panel.add_theme_stylebox_override("panel", shell_style)
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", UiTheme.FONT_HEADING)
	_title.add_theme_color_override("font_color", COL_BORDER)
	content.add_child(_title)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_progress.add_theme_color_override("font_color", COL_MUTED)
	content.add_child(_progress)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "RecipeList"
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_input_hint = Label.new()
	_input_hint.name = "InputHint"
	_input_hint.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_input_hint.add_theme_color_override("font_color", COL_MUTED)
	content.add_child(_input_hint)
	_refresh_input_hint()


func _refresh_input_hint() -> void:
	if _input_hint != null:
		_input_hint.text = "[%s] closes · Crafting consumes materials only after every check passes." \
			% InputHints.primary_label("ui_cancel")
