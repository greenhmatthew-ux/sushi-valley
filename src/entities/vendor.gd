extends Area2D
## A shopkeeper. Same interactable contract as Npc (Area2D in group "interactable",
## collision layer 8, exposing interact(player)), so the player's InteractProbe drives it
## with no player.gd changes. On interact it opens the shared ShopPanel via Bus.shop_open,
## keyed by `shop_id` (a key into DB.shops) — the vendor never holds a UI reference.
##
## Like Npc, it is non-blocking (no StaticBody): the merchant adds life without walling the
## player in. Art is a standing character frame plus a name label, built in code so the
## .tscn stays tiny. Reuses the NPC sheet layout (16x16 frame at column 0, row 0).

## Which shop this vendor sells — must be a key in DB.shops (see data/game/shops.json).
@export var shop_id: String = "forest_trader"
## Shown above the merchant and used as the panel greeting speaker.
@export var vendor_name: String = "Trader"
## Character sheet for the standing sprite. Swap per-instance for a different merchant.
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/npc_merchant_walk.png")


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


## Called by the player's interaction probe when they press interact nearby.
func interact(player: Node = null) -> void:
	if player != null and player.has_method("face"):
		player.face(_facing_from(global_position - player.global_position))
	Bus.shop_open.emit(shop_id)


func _facing_from(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func _build_visual() -> void:
	var body := Sprite2D.new()
	body.texture = sprite_sheet
	body.region_enabled = true
	body.region_rect = Rect2(0, 0, 16, 16)   # column 0, row 0 — standing, facing down
	body.offset = Vector2(0, -8)              # feet on the node origin
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)

	var label := Label.new()
	label.text = vendor_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1.0, 0.843, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 12)
	label.position = Vector2(-40, -30)
	add_child(label)
