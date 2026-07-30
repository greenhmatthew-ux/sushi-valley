extends Area2D
## Context-first crafting access: interacting with a visible station opens only that
## station's recipes. The station owns presentation, never recipe or economy values.

@export_enum("forge", "workshop", "kitchen") var station: String = "kitchen"
@export var station_name: String = "Kitchen Pot"
@export var sprite: Texture2D


func _ready() -> void:
	add_to_group("interactable")
	if sprite != null:
		var visual := Sprite2D.new()
		visual.texture = sprite
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.position = Vector2(0, -6)
		add_child(visual)
	else:
		_build_fallback_visual()
	var label := Label.new()
	label.text = station_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(90, 12)
	label.position = Vector2(-45, 4)
	add_child(label)


func _build_fallback_visual() -> void:
	if station == "forge":
		var anvil := Polygon2D.new()
		anvil.polygon = PackedVector2Array([
			Vector2(-12, -13), Vector2(12, -13), Vector2(8, -8), Vector2(3, -8),
			Vector2(3, -2), Vector2(8, 1), Vector2(-8, 1), Vector2(-3, -2), Vector2(-3, -8)])
		anvil.color = Color(0.42, 0.47, 0.54)
		add_child(anvil)
		var ember := Polygon2D.new()
		ember.polygon = PackedVector2Array([
			Vector2(-3, -15), Vector2(0, -20), Vector2(3, -15), Vector2(0, -12)])
		ember.color = Color(1.0, 0.48, 0.16)
		add_child(ember)
	else:
		var bench := Polygon2D.new()
		bench.polygon = PackedVector2Array([
			Vector2(-13, -12), Vector2(13, -12), Vector2(13, -7), Vector2(9, -7),
			Vector2(9, 1), Vector2(5, 1), Vector2(5, -7), Vector2(-5, -7),
			Vector2(-5, 1), Vector2(-9, 1), Vector2(-9, -7), Vector2(-13, -7)])
		bench.color = Color(0.50, 0.31, 0.16)
		add_child(bench)
		var cloth := Polygon2D.new()
		cloth.polygon = PackedVector2Array([
			Vector2(-8, -14), Vector2(6, -14), Vector2(9, -9), Vector2(-6, -9)])
		cloth.color = Color(0.34, 0.62, 0.70)
		add_child(cloth)


func interact(player: Node = null) -> void:
	if player != null and player.has_method("face"):
		player.face("up")
	Bus.crafting_open.emit(station)
