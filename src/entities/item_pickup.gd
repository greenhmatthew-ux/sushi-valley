extends Area2D
## A grabbable item lying in the world. Same interactable contract as LessonGate:
## an Area2D in the "interactable" group, on collision layer 8, exposing
## `interact(player)`. The player's InteractProbe finds the nearest one and calls
## it — so a pickup needs zero changes to player.gd.
##
## On interact it hands the item to the Inv autoload (which stacks it and fires the
## Bus signals) and frees itself. Authored per-instance in the editor: set
## `item_id` and `qty`, drop it in the world.
##
## Placeholder art: the world sprite reuses the item's inventory icon from
## `assets/icons/items/<id>.png`, scaled down to tile size. Items without an icon
## show a small gold diamond. A dedicated ground-drop sprite set (the TS build's
## "world_*" sprites) is a later art pass — noted, not blocking.

@export var item_id: String = "rice_ball"
@export var qty: int = 1
## Draw the item's name under it so pickups are identifiable before you grab them.
@export var show_label: bool = true

const ICON_DIR := "res://assets/icons/items/"
const TARGET_PX := 16.0        # render the icon at roughly one tile
const PLACEHOLDER_COLOR := Color(1.0, 0.824, 0.49)

var _taken := false


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


func _build_visual() -> void:
	var icon := _load_icon()
	if icon != null:
		var sprite := Sprite2D.new()
		sprite.texture = icon
		sprite.position = Vector2(0, -6)
		var longest := float(maxi(icon.get_width(), icon.get_height()))
		if longest > TARGET_PX:
			sprite.scale = Vector2.ONE * (TARGET_PX / longest)
		add_child(sprite)
	else:
		# No icon on file — a small gold diamond stands in.
		var diamond := Polygon2D.new()
		diamond.polygon = PackedVector2Array([
			Vector2(0, -13), Vector2(7, -6), Vector2(0, 1), Vector2(-7, -6)])
		diamond.color = PLACEHOLDER_COLOR
		add_child(diamond)

	if show_label:
		var label := Label.new()
		label.text = _display_name()
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.96))
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(80, 12)
		label.position = Vector2(-40, 2)
		add_child(label)


## Called by the player's interaction probe when they press interact nearby.
func interact(_player: Node = null) -> void:
	if _taken:
		return
	var leftover := Inv.add(item_id, qty)
	var got := qty - leftover
	if got <= 0:
		Bus.toast.emit("Your bag is full.")
		return
	_taken = true
	Bus.toast.emit("Picked up %s%s" % [_display_name(), (" x%d" % got) if got > 1 else ""])
	queue_free()


func _load_icon() -> Texture2D:
	var path := ICON_DIR + item_id + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## The item's display name from DB, falling back to the raw id if DB has no entry.
func _display_name() -> String:
	var def: Dictionary = DB.item(item_id)
	return String(def.get("name", item_id))
