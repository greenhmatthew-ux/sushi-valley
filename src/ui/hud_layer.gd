extends CanvasLayer
## A small always-on HUD: the coin purse in the top-right corner. Bus-driven — it
## reflects the live Inv balance and updates the instant coins change (a quest reward,
## a shop purchase), so the player always sees what they've earned without opening the
## bag. Sits under the dialogue/recall/toast layers so those still cover it when open.

const COIN_COLOR := Color(1.0, 0.843, 0.4)
const HEART_TEX := preload("res://assets/ui/hearts.png")
const HEART_COUNT := 3   ## Player.MAX_HP (12) / 4 HP per heart

var _label: Label
var _hearts: Array[TextureRect] = []


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Bus.coins_changed.connect(_on_coins_changed)
	Bus.inventory_changed.connect(_refresh)
	_refresh()
	_build_hearts()
	Bus.player_hp_changed.connect(_on_hp)


func _on_coins_changed(_coins: int) -> void:
	_refresh()


## Heart bar, top-left. Each heart holds 4 HP; the sheet runs empty (frame 0) -> full (4).
func _build_hearts() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.position = Vector2(10, 8)
	add_child(box)
	for i in HEART_COUNT:
		var tr := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = HEART_TEX
		at.region = Rect2(64, 0, 16, 16)   # full to start
		tr.texture = at
		tr.custom_minimum_size = Vector2(30, 30)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(tr)
		_hearts.append(tr)


func _on_hp(hp: int, _max_hp: int) -> void:
	for i in _hearts.size():
		var fill := clampi(hp - i * 4, 0, 4)   # quarters filled in this heart
		(_hearts[i].texture as AtlasTexture).region = Rect2(fill * 16, 0, 16, 16)


func _refresh() -> void:
	if _label != null:
		_label.text = "%d coins" % Inv.coins


func _build() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.9)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.824, 0.49, 0.75)
	style.set("content_margin_left", 14)
	style.set("content_margin_right", 14)
	style.set("content_margin_top", 6)
	style.set("content_margin_bottom", 6)
	panel.add_theme_stylebox_override("panel", style)
	# Pin to the top-right corner, 8px in, sizing to its contents.
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", COIN_COLOR)
	panel.add_child(_label)
