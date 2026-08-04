extends Area2D
## One authored casting destination in visible water. Sparse code-drawn ripples
## identify the interaction without stamping a row of resource icons on the pond.

@export var site_id := "valley_pond"
@export var display_name := "Village Pond"
@export var base_qty := 2
@export var cooldown_seconds := 120
@export var difficulty := 0.1
@export var seasons: Array[String] = ["spring", "summer", "autumn"]

var _phase := 0.0


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	Fishing.register_site(site_id, display_name, cooldown_seconds, seasons)
	Bus.fishing_changed.connect(func(changed_id):
		if changed_id == site_id:
			queue_redraw())
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	queue_redraw()


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


func _draw() -> void:
	var fade := 0.35 + (sin(_phase * 1.4) + 1.0) * 0.18
	var ripple := Color(0.63, 0.86, 0.96, fade)
	for radius in [7.0, 12.0, 17.0]:
		draw_arc(Vector2.ZERO, radius, PI * 0.12, PI * 0.88, 14, ripple, 1.0)
		draw_arc(Vector2.ZERO, radius, PI * 1.12, PI * 1.88, 14, ripple, 1.0)
	var fish_color := Color(0.35, 0.72, 0.82, 0.78)
	var fish_y := sin(_phase) * 2.0
	draw_circle(Vector2(1, fish_y), 3.0, fish_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, fish_y), Vector2(-7, fish_y - 3), Vector2(-7, fish_y + 3)]), fish_color)
	draw_circle(Vector2(2.2, fish_y - 0.8), 0.6, Color.WHITE)
