extends CanvasLayer
## The buy screen a Vendor opens: a card grid of that shop's stock, priced from
## data/game/shops.json, purchased against the shared coin purse. Built in code to match
## inventory_panel / recall_panel (the number of cards is dynamic), and kept a separate
## panel rather than reusing inventory_panel because buying needs a price + a Buy button
## per card, not a quantity readout.
##
## Bus-driven: listens for `shop_open` (a vendor interact — see src/entities/vendor.gd),
## closes on ui_cancel. No `shop_closed` reply — nothing awaits a shop closing, unlike the
## dialogue box's conversation flow.

# Palette shared with inventory_panel / recall_panel for a consistent feel.
const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_CARD := UiTheme.SURFACE_RAISED
const COL_CARD_BORDER := UiTheme.BORDER_STRONG
const COL_COIN := UiTheme.ACCENT_GOLD
const COL_TEXT := UiTheme.TEXT_PRIMARY
const COL_GOOD := UiTheme.STATE_SUCCESS
const COL_DISABLED := UiTheme.TEXT_DISABLED

const KIND_COLORS := {
	"gear": Color(0.78, 0.808, 0.847),
	"consumable": UiTheme.STATE_SUCCESS,
	"material": Color(0.788, 0.639, 0.42),
	"seed": UiTheme.STATE_SUCCESS,
}

const ICON_DIR := "res://assets/icons/items/"
const MAX_STACK := 99   # mirrors InventoryLogic.MAX_STACK — a maxed stack can't be bought

## Ordering politely in Japanese takes this much off the price.
const HAGGLE_DISCOUNT := 0.25
## Prefer real shopping/payment language for the prompt — travel-stay-payment carries the
## sourced "how much is it" / "can I use a card" phrases. Falls back to any unlocked card.
const HAGGLE_CATEGORY := "travel-stay-payment"

var _open := false
var _shop_id := ""
var _root: Control
var _title_label: Label
var _region_label: Label
var _coins_label: Label
var _hint_label: Label
var _grid: GridContainer
var _empty_label: Label
var _haggling := false


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.shop_open.connect(_on_shop_open)
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))


func _on_shop_open(shop_id: String) -> void:
	_shop_id = shop_id
	_refresh()
	_root.show()
	get_tree().paused = true
	_open = true


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	_root.hide()
	get_tree().paused = false
	_open = false


# --- content ---------------------------------------------------------------

func _refresh() -> void:
	var shop: Dictionary = DB.shops.get(_shop_id, {})
	_title_label.text = String(shop.get("title", "Shop"))
	_region_label.text = String(shop.get("region", ""))
	_coins_label.text = "%d coins" % Inv.coins
	if _hint_label != null:
		_hint_label.text = "Order in Japanese for %d%% off — a wrong answer just pays full price." % int(HAGGLE_DISCOUNT * 100)

	for child in _grid.get_children():
		child.queue_free()

	var stock: Array = shop.get("stock", [])
	_empty_label.visible = stock.is_empty()
	_grid.visible = not stock.is_empty()

	var first_btn: Button = null
	for entry in stock:
		var id := String(entry.get("item", ""))
		var price := int(entry.get("price", 0))
		if id.is_empty():
			continue
		var card := _make_card(id, price)
		_grid.add_child(card)
		if first_btn == null:
			first_btn = card.get_meta("buy_btn")
	if first_btn != null:
		first_btn.grab_focus.call_deferred()


func _make_card(id: String, price: int) -> Control:
	var def: Dictionary = DB.item(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(112, 148)

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
	name_label.custom_minimum_size = Vector2(96, 0)
	vbox.add_child(name_label)

	var detail_text := _item_detail(def)
	if not detail_text.is_empty():
		var detail_label := Label.new()
		detail_label.name = "ShopItemDetail"
		detail_label.text = detail_text
		detail_label.add_theme_font_size_override("font_size", 9)
		detail_label.add_theme_color_override("font_color", COL_HEADING)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.custom_minimum_size = Vector2(96, 0)
		vbox.add_child(detail_label)

	var price_label := Label.new()
	price_label.text = "%d c" % price
	price_label.add_theme_font_size_override("font_size", 12)
	price_label.add_theme_color_override("font_color", COL_COIN)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_label)

	var can_buy := Inv.coins >= price and Inv.count(id) < MAX_STACK
	var btn := Button.new()
	btn.text = "Buy" if can_buy else ("Full" if Inv.count(id) >= MAX_STACK else "Can't afford")
	btn.disabled = not can_buy
	btn.custom_minimum_size = Vector2(0, 30)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", _button_style(COL_CARD, COL_CARD_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(COL_CARD.lightened(0.08), COL_BORDER))
	btn.add_theme_stylebox_override("disabled", _button_style(COL_CARD.darkened(0.2), COL_DISABLED))
	btn.add_theme_color_override("font_disabled_color", COL_DISABLED)
	btn.pressed.connect(_on_buy.bind(id, price))
	vbox.add_child(btn)
	card.set_meta("buy_btn", btn)

	return card


## Buying is where learned Japanese gets SPENT. Asking politely in Japanese earns a discount;
## getting it wrong (or having nothing learned yet) simply pays full price.
##
## The shape of this follows UI_UX_GUIDE principle 7 exactly — "Japanese mastery adds
## understanding, efficiency, optional routes, relationships, and rewards; it never removes
## basic accessibility or the main route." So recall is a DISCOUNT, never a gate: a player who
## knows no Japanese can still buy everything, they just pay list price.
##
## The prompt is drawn from the shared scheduler like every other surface, so haggling is real
## review and not a side deck.
func _on_buy(id: String, price: int) -> void:
	if Inv.coins < price or Inv.count(id) >= MAX_STACK:
		return   # stale button state (e.g. a duplicate signal) — do nothing rather than overspend
	if _haggling:
		return
	_haggling = true
	var final_price := await _haggle(price)
	_haggling = false

	# Re-check affordability: the discount can only ever lower the price, but the player may
	# have been at exactly `price` and the panel state could be stale.
	if Inv.coins < final_price or not Inv.spend_coins(final_price):
		Bus.toast.emit("Not enough coins.")
		_refresh()
		return
	Inv.add(id, 1)
	Bus.item_purchased.emit(id, final_price)
	var item: Dictionary = DB.item(id)
	var name := String(item.get("name", id))
	var equip_hint := " Equip in Menu > Bag." if String(item.get("kind", "")) == "gear" else ""
	if final_price < price:
		Bus.toast.emit("Bought %s for %d coins (saved %d).%s" % [
			name, final_price, price - final_price, equip_hint])
	else:
		Bus.toast.emit("Bought %s for %d coins.%s" % [name, final_price, equip_hint])
	_refresh()


## Run one recall for a discount. Returns the price to actually charge.
## Silently returns the full price when the player has nothing unlocked yet — a beginner
## should not be shown a prompt they cannot possibly answer.
func _haggle(price: int) -> int:
	var prompt: Dictionary = Learning.build_prompt({}, true, "", HAGGLE_CATEGORY)
	if prompt.is_empty():
		prompt = Learning.build_prompt({}, true)   # any unlocked card
	if prompt.is_empty():
		return price

	Bus.learn_open.emit("", 1, true)
	var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
	var attempted: int = res[0]
	var correct: int = res[1]
	if bool(res[2]) or attempted == 0:
		return price   # cancelled or nothing to ask — no penalty, no discount
	if correct > 0:
		return maxi(1, int(round(price * (1.0 - HAGGLE_DISCOUNT))))
	return price


func _icon_node(id: String) -> Control:
	var def := DB.item(id)
	var icon_id := String(def.get("iconAlias", id))
	var path := ICON_DIR + icon_id + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.name = "ItemIcon_%s" % id
		tex.texture = load(path) as Texture2D
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(40, 40)
		return tex
	var placeholder := ColorRect.new()
	placeholder.color = COL_BORDER
	placeholder.custom_minimum_size = Vector2(40, 40)
	return placeholder


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


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "ShopShell"
	panel.add_theme_stylebox_override("panel", _panel_style())
	# The card grid needs a little more width than text-only modals, but no longer
	# needs to consume 90% of both axes.
	UiTheme.fit_modal_shell(panel, 0.10, 0.08)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header row: title + region on the left, coins on the right.
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	_title_label = Label.new()
	_title_label.text = "Shop"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", COL_BORDER)
	titles.add_child(_title_label)

	_region_label = Label.new()
	_region_label.add_theme_font_size_override("font_size", 12)
	_region_label.add_theme_color_override("font_color", COL_HEADING)
	titles.add_child(_region_label)

	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 16)
	_coins_label.add_theme_color_override("font_color", COL_COIN)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_coins_label)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_hint_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.LEARNING_VIOLET)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint_label)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Nothing in stock right now."
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", COL_HEADING)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(_empty_label)

	var hint := Label.new()
	hint.text = "Esc to leave"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_HEADING)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(hint)


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


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = border
	return s
