extends Area2D
## Context-first crafting access: interacting with a visible station opens only that
## station's recipes. The station owns presentation, never recipe or economy values.

@export_enum("forge", "workshop", "kitchen") var station: String = "kitchen"
@export var station_name: String = "Kitchen Pot"
@export var sprite: Texture2D
## Optional tool laid over the station sprite (the Workshop uses a hammer over its tool crate).
@export var overlay_sprite: Texture2D


func _ready() -> void:
	add_to_group("interactable")
	if sprite != null:
		var visual := Sprite2D.new()
		visual.texture = sprite
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.position = Vector2(0, -6)
		add_child(visual)
	else:
		push_warning("Crafting station '%s' has no authored sprite" % station_name)
	if overlay_sprite != null:
		var overlay := Sprite2D.new()
		overlay.texture = overlay_sprite
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.position = Vector2(0, -10)
		add_child(overlay)
	var label := Label.new()
	label.text = station_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(90, 12)
	# Keep the station name above the prop so the approaching player and interaction
	# prompt cannot cover it.
	label.position = Vector2(-45, -31)
	add_child(label)

func interact(player: Node = null) -> void:
	if player != null and player.has_method("face"):
		player.face("up")
	Bus.crafting_open.emit(station)
