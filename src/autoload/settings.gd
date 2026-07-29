extends Node
## Player preferences that outlive a save file — currently camera zoom, with room for
## audio/speech toggles later.
##
## Deliberately NOT part of the save profile: settings are about how you like to play, not
## progress, so `SaveGame.clear()` (new game, tests) must never reset them. They live in
## their own `user://settings.cfg` and load before any scene needs them.
##
## Changes announce on the Bus so whatever is live (the player's camera, a panel) reacts
## without polling or holding a reference back to this node.

const PATH := "user://settings.cfg"

## Camera zoom. Higher = closer in. 2.0 was the old hardcoded value; the range lets the
## player pull back to see more of the map. Kept to 0.5 steps because this is 16px pixel
## art — fractional zooms between those steps shimmer as the camera moves.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.5
const ZOOM_DEFAULT := 2.0

var zoom: float = ZOOM_DEFAULT:
	set(value):
		var snapped_value := clampf(snappedf(value, ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		if is_equal_approx(snapped_value, zoom):
			return
		zoom = snapped_value
		Bus.zoom_changed.emit(zoom)
		save()

## The game speaks Japanese first — that is the whole point. English is a safety net you
## can pin on permanently here, or peek at any time by holding the `peek_english` key.
## Off by default so the Japanese is what you actually read.
var show_english: bool = false:
	set(value):
		if value == show_english:
			return
		show_english = value
		Bus.language_changed.emit(english_visible())
		save()

## True while the peek key is held, independent of the sticky preference above.
var _peeking: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # peek must work while a panel pauses the game
	load_settings()


## Hold-to-peek is global: it has to work in dialogue, in a recall prompt, and out in the
## world, so it lives here rather than in any one panel. Deliberately not marked handled —
## peeking is passive and must never eat a key another surface also wants.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("peek_english"):
		set_peeking(true)
	elif event.is_action_released("peek_english"):
		set_peeking(false)


## Whether English should be on screen right now — either pinned in settings or peeked.
func english_visible() -> bool:
	return show_english or _peeking


## Held-key peek. Kept separate from `show_english` so releasing the key returns to
## whatever the player actually chose in settings.
func set_peeking(active: bool) -> void:
	if active == _peeking:
		return
	_peeking = active
	Bus.language_changed.emit(english_visible())


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return   # no file yet — defaults stand
	# Assign through the backing field so loading doesn't re-save what we just read.
	var loaded := float(cfg.get_value("display", "zoom", ZOOM_DEFAULT))
	zoom = clampf(snappedf(loaded, ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
	show_english = bool(cfg.get_value("language", "show_english", false))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "zoom", zoom)
	cfg.set_value("language", "show_english", show_english)
	cfg.save(PATH)


## Step the zoom one notch. `direction` is +1 (closer) or -1 (further out).
func nudge_zoom(direction: int) -> void:
	zoom = zoom + ZOOM_STEP * signf(direction)


func reset() -> void:
	zoom = ZOOM_DEFAULT
