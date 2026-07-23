extends Node2D
class_name Prop
## A full-asset world prop — a tree, a building, a lantern, a torii.
##
## Project art rules, enforced in one place:
##   * Render the ENTIRE sprite. No AtlasTexture region, so nothing is ever cropped.
##   * Never mirror. No flip_h/flip_v and no negative scale, so an asset is never flipped.
##   * Origin is the feet (bottom-centre), so it Y-sorts against the player correctly.
##   * Collision, when solid, is the base footprint only (a trunk, a foundation) — not the
##     whole art bounds — so the player tucks behind the canopy/roof and only the base blocks.
##
## Configure per-instance in the editor: set `texture`, whether it is `solid`, and the base
## `foot_size` / `foot_offset`. Everything is built at runtime from those.

@export var texture: Texture2D
## When true, a StaticBody blocks the player at the base footprint below.
@export var solid: bool = true
## Size of the solid base collision box, in px (the trunk / building foundation).
@export var foot_size: Vector2 = Vector2(16, 8)
## Centre of that box relative to the feet (origin); negative y lifts it off the ground line.
@export var foot_offset: Vector2 = Vector2(0, -4)


func _ready() -> void:
	y_sort_enabled = true
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Centred sprite lifted so the bottom of the art sits on the feet/origin.
		sprite.offset = Vector2(0, -texture.get_height() / 2.0)
		add_child(sprite)
	if solid:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = foot_size
		cs.shape = shape
		cs.position = foot_offset
		body.add_child(cs)
		add_child(body)
