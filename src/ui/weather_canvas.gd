extends Control
## Lightweight, code-drawn outdoor weather. It stays restrained over the pixel
## art: a tint plus sparse streaks/flakes, with no imported placeholder texture.

var weather := "clear"
var _elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_weather(value: String) -> void:
	weather = value
	_elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if weather in ["rain", "storm", "snow"]:
		_elapsed = fmod(_elapsed + delta, 1000.0)
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match weather:
		"cloudy":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.24, 0.31, 0.06))
		"rain", "storm":
			_draw_rain(weather == "storm")
		"snow":
			_draw_snow()


func _draw_rain(heavy: bool) -> void:
	var count := 52 if heavy else 30
	var speed := 165.0 if heavy else 105.0
	draw_rect(Rect2(Vector2.ZERO, size),
		Color(0.05, 0.10, 0.18, 0.14 if heavy else 0.08))
	for i in count:
		var x := fposmod(float(i * 73) + _elapsed * speed, size.x + 56.0) - 28.0
		var y := fposmod(float(i * 47) + _elapsed * speed * 1.7, size.y + 40.0) - 20.0
		var length := 10.0 if heavy else 7.0
		draw_line(Vector2(x, y), Vector2(x - length * 0.35, y + length),
			Color(0.63, 0.84, 0.98, 0.50 if heavy else 0.34), 1.0)


func _draw_snow() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.80, 0.88, 0.05))
	for i in 34:
		var drift := sin(_elapsed * 0.8 + float(i)) * 10.0
		var x := fposmod(float(i * 83) + drift, size.x + 24.0) - 12.0
		var y := fposmod(float(i * 41) + _elapsed * 24.0, size.y + 20.0) - 10.0
		draw_circle(Vector2(x, y), 1.3 if i % 4 == 0 else 0.8,
			Color(0.94, 0.97, 1.0, 0.58))
