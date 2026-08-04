extends Area2D
## One authored casting destination in visible water.
##
## The ripple used to be drawn with `draw_arc` — coloured primitives rather than art,
## which read as a placeholder next to the tiled pond around it. It is now the Ninja
## Adventure water-ripple animation (CC0, the same pack as the player and enemies), so
## the casting spot is made of the world's own art. Only the *state* is still drawn in
## code: a spot on cooldown dims, because that is information, not decoration.

## Ninja Adventure `Backgrounds/Animated/Water Ripples` — 4 frames of 16px on one row.
const RIPPLE_SHEET := preload("res://assets/tilesets/water_ripple.png")
const RIPPLE_FRAMES := 4
const RIPPLE_FPS := 6.0

@export var site_id := "valley_pond"
@export var display_name := "Village Pond"
@export var base_qty := 2
@export var cooldown_seconds := 120
@export var difficulty := 0.1
@export var seasons: Array[String] = ["spring", "summer", "autumn"]

var _phase := 0.0
var _ripple: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	_build_ripple()
	Fishing.register_site(site_id, display_name, cooldown_seconds, seasons)
	Bus.fishing_changed.connect(func(changed_id):
		if changed_id == site_id:
			_refresh())
	_refresh()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * RIPPLE_FPS, float(RIPPLE_FRAMES))
	if _ripple != null:
		var frame := int(_phase)
		(_ripple.texture as AtlasTexture).region = Rect2(frame * 16, 0, 16, 16)


## Sits flat on the water rather than standing on it, so no feet offset and no Y-sort
## fight with the player casting from the bank.
func _build_ripple() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = RIPPLE_SHEET
	atlas.region = Rect2(0, 0, 16, 16)
	atlas.filter_clip = true
	_ripple = Sprite2D.new()
	_ripple.name = "Ripple"
	_ripple.texture = atlas
	_ripple.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ripple)


## A spot still on cooldown is faded: the art says "water", the alpha says "not yet".
func _refresh() -> void:
	if _ripple == null:
		return
	var ready := Fishing.remaining_seconds(site_id, cooldown_seconds) <= 0
	_ripple.modulate.a = 1.0 if ready else 0.4


func interact(_player: Node = null) -> void:
	var check := Fishing.status(site_id, cooldown_seconds, base_qty + 2, seasons)
	if not bool(check.get("ok", false)):
		Bus.toast.emit(String(check.get("reason", "The pond is quiet.")))
		return
	Bus.fishing_open.emit(site_id, display_name, base_qty, cooldown_seconds, difficulty)


func interaction_label() -> String:
	var remaining := Fishing.remaining_seconds(site_id, cooldown_seconds)
	if remaining > 0:
		return "Fish return in %ds" % remaining
	if Farm.season() not in seasons:
		return "Check the quiet pond"
	return "Fish at %s" % display_name


