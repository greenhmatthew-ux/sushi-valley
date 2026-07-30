extends CanvasLayer
## The bag screen: a card grid of what you're carrying, plus coins and a capacity
## bar. Toggled by the `open_menu` action, rebuilt on every `Bus.inventory_changed`
## so it never polls. Built in code to match recall_panel / toast_layer, and
## because the card count is dynamic.
##
## Kept as a card grid (not a long scroll) per the UX rules: items wrap into a
## fixed-height grid, and only overflow scrolls. Reads item names / icons / kinds
## from DB and quantities from the Inv autoload.
##
## Gear cards expose one clear Equip action. Equipped items sit in a compact strip
## above the bag and can be removed there, so equipment never becomes hidden state.

# Palette shared with recall_panel for a consistent feel.
const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_CARD := UiTheme.SURFACE_RAISED
const COL_CARD_BORDER := UiTheme.BORDER_STRONG
const COL_COIN := UiTheme.ACCENT_GOLD
const COL_TEXT := UiTheme.TEXT_PRIMARY
const COL_WARN := UiTheme.STATE_DANGER

# Kind -> name colour, ported from itemColor() in ItemTypes.ts.
const KIND_COLORS := {
	"gear": Color(0.78, 0.808, 0.847),      # rarity handled by combat slice; common tint here
	"consumable": UiTheme.STATE_SUCCESS,
	"material": Color(0.788, 0.639, 0.42),
	"seed": UiTheme.STATE_SUCCESS,
}

const ICON_DIR := "res://assets/icons/items/"

var _open := false
var _root: Control
var _coins_label: Label
var _equipment_box: HFlowContainer
var _equipment_empty: Label
var _grid: GridContainer
var _empty_label: Label
var _capacity_label: Label


func _ready() -> void:
	layer = 19   # under recall (20) and toast (21)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.inventory_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_menu"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_open(not _open)


func _set_open(open: bool) -> void:
	_open = open
	if open:
		_refresh()
		_root.show()
		get_tree().paused = true
	else:
		_root.hide()
		get_tree().paused = false


# --- content ---------------------------------------------------------------

func _refresh() -> void:
	if _coins_label == null:
		return
	_coins_label.text = "%d coins" % Inv.coins

	for child in _grid.get_children():
		child.queue_free()
	for child in _equipment_box.get_children():
		child.queue_free()

	var equipped: Dictionary = Inv.equipment()
	_equipment_empty.visible = equipped.is_empty()
	for slot in InventoryLogic.EQUIPMENT_SLOTS:
		if equipped.has(slot):
			_equipment_box.add_child(_make_equipped_button(slot, String(equipped[slot])))

	var items: Array = Inv.entries()
	# Sort by display name for a stable, human-friendly order (TS bag() did this).
	items.sort_custom(func(a, b): return _name_of(a["id"]).naturalnocasecmp_to(_name_of(b["id"])) < 0)

	_empty_label.visible = items.is_empty()
	_grid.visible = not items.is_empty()
	for entry in items:
		_grid.add_child(_make_card(String(entry["id"]), int(entry["qty"])))

	var enc: Dictionary = Inv.encumbrance()
	_capacity_label.text = "Carrying %d / %d" % [enc["units"], enc["cap"]]
	_capacity_label.add_theme_color_override("font_color",
		COL_WARN if enc["encumbered"] else COL_HEADING)


func _make_card(id: String, qty: int) -> Control:
	var def: Dictionary = DB.item(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(104, 116)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	vbox.add_child(_icon_node(id))

	var name_label := Label.new()
	name_label.text = String(def.get("name", id))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color",
		KIND_COLORS.get(String(def.get("kind", "")), COL_TEXT))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(88, 0)
	vbox.add_child(name_label)

	var qty_label := Label.new()
	qty_label.text = "x%d" % qty
	qty_label.add_theme_font_size_override("font_size", 12)
	qty_label.add_theme_color_override("font_color", COL_HEADING)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(qty_label)

	if def.get("kind", "") == "gear":
		var stats_label := Label.new()
		stats_label.text = _stats_line(PlayerStats.scaled_item_stats(def, _player_level()))
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.add_theme_color_override("font_color", COL_TEXT)
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stats_label)

		var equip_button := Button.new()
		var required_level := int(def.get("requiredLevel", 1))
		equip_button.text = "Equip" if required_level <= _player_level() \
			else "Lv %d" % required_level
		equip_button.disabled = required_level > _player_level()
		equip_button.focus_mode = Control.FOCUS_ALL
		equip_button.pressed.connect(_on_equip.bind(id))
		vbox.add_child(equip_button)

	return card


func _make_equipped_button(slot: String, item_id: String) -> Button:
	var item: Dictionary = DB.item(item_id)
	var button := Button.new()
	button.text = "%s: %s" % [slot.capitalize(), item.get("name", item_id)]
	button.tooltip_text = "%s\n%s\nPress to unequip." % [
		_stats_line(PlayerStats.scaled_item_stats(item, _player_level())), item.get("desc", "")]
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_on_unequip.bind(slot, item_id))
	return button


func _on_equip(item_id: String) -> void:
	var item: Dictionary = DB.item(item_id)
	if Inv.equip(item_id):
		Bus.toast.emit("Equipped %s." % item.get("name", item_id))
	else:
		Bus.toast.emit("Could not equip %s." % item.get("name", item_id))


func _on_unequip(slot: String, item_id: String) -> void:
	if Inv.unequip(slot):
		Bus.toast.emit("Unequipped %s." % DB.item(item_id).get("name", item_id))
	else:
		Bus.toast.emit("Bag stack is full; equipment was left in place.")


func _player_level() -> int:
	var xp := 0
	if Learning.profile != null:
		xp = int(Learning.profile.data.get("stats", {}).get("xp", 0))
	return PlayerStats.level_from_xp(xp)


func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	for stat in ["hp", "atk", "def", "spd"]:
		var value := int(stats.get(stat, 0))
		if value != 0:
			parts.append("%+d %s" % [value, stat.to_upper()])
	return "  ".join(parts)


func _icon_node(id: String) -> Control:
	var path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path) as Texture2D
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(48, 48)
		return tex
	var placeholder := ColorRect.new()
	placeholder.color = COL_BORDER
	placeholder.custom_minimum_size = Vector2(48, 48)
	return placeholder


func _name_of(id: String) -> String:
	return String(DB.item(id).get("name", id))


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
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
	panel.anchor_left = 0.08; panel.anchor_top = 0.06
	panel.anchor_right = 0.92; panel.anchor_bottom = 0.94
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header row: title on the left, coins on the right.
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Bag"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_BORDER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 16)
	_coins_label.add_theme_color_override("font_color", COL_COIN)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coins_label)

	var equipment_heading := Label.new()
	equipment_heading.text = "Equipped — press an item to remove it"
	equipment_heading.add_theme_font_size_override("font_size", 13)
	equipment_heading.add_theme_color_override("font_color", COL_HEADING)
	vbox.add_child(equipment_heading)

	_equipment_empty = Label.new()
	_equipment_empty.text = "No equipment yet. Equip gear from the bag below."
	_equipment_empty.add_theme_font_size_override("font_size", 12)
	_equipment_empty.add_theme_color_override("font_color", COL_HEADING)
	vbox.add_child(_equipment_empty)

	_equipment_box = HFlowContainer.new()
	_equipment_box.add_theme_constant_override("h_separation", 6)
	_equipment_box.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_equipment_box)

	# Grid of cards, height-capped so overflow scrolls instead of the whole page.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Your bag is empty."
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", COL_HEADING)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(_empty_label)

	# Footer: capacity + how to close.
	var footer := HBoxContainer.new()
	vbox.add_child(footer)

	_capacity_label = Label.new()
	_capacity_label.add_theme_font_size_override("font_size", 12)
	_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_capacity_label)

	var hint := Label.new()
	hint.text = "Esc / menu to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_HEADING)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(hint)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s


func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = COL_CARD_BORDER
	return s
