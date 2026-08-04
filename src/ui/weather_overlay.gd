extends CanvasLayer
## Screen-space weather for outdoor maps. Each outdoor scene instances this one
## reusable layer; interiors deliberately do not, so rain never falls through a roof.

const WeatherCanvas = preload("res://src/ui/weather_canvas.gd")

var _canvas: Control


func _ready() -> void:
	layer = 14 # above the world, below HUD (17), prompts (18), and modals (19+)
	_canvas = WeatherCanvas.new()
	_canvas.name = "WeatherCanvas"
	add_child(_canvas)
	_canvas.set_weather(WeatherSystem.current())
	Bus.farm_changed.connect(_refresh)


func _refresh() -> void:
	_canvas.set_weather(WeatherSystem.current())
