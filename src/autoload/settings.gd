extends Node
## Player preferences that outlive a save file: camera zoom and whether English is pinned.
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

## UI scale. Deliberately separate from `zoom`: zoom moves the world camera and
## must stay on integer-friendly steps for 16px art, while this only resizes UI.
## Turning it up does not make panels bigger on screen — it makes their TEXT
## bigger, so panels hold less. That is the accessibility trade the guide asks for.
##
## The range stops at 110%, not the guide's 160%. The game lays UI out in a fixed
## 640x360 canvas, and raising the scale divides that canvas by the same factor —
## at 160% panels get 400x225, which the denser ones cannot hold. The recall panel
## is the binding constraint: its reveal state (furigana, prompt, hint, feedback,
## two answer rows, Continue) fills the full-size canvas almost exactly, and at
## 120% it overflows by a few pixels for the longest cards. Going higher needs
## those panels redesigned to reflow, not a bigger number here — every step in
## this list is swept by tests/test_ui_fits.gd on every run.
const UI_SCALES: Array[float] = [0.8, 0.9, 1.0, 1.1]
const UI_SCALE_DEFAULT := 1.0

var ui_scale: float = UI_SCALE_DEFAULT:
	set(value):
		var next := _nearest_ui_scale(value)
		if is_equal_approx(next, ui_scale):
			return
		ui_scale = next
		Bus.ui_scale_changed.emit(ui_scale)
		save()

## Linear volumes, 0.0 (silent) to 1.0 (full), in 5% steps. Music layers on top of the
## Audio autoload's own base mix level; pronunciation plays at the set level directly.
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_STEP := 0.05

var music_volume: float = VOLUME_MAX:
	set(value):
		var snapped_value := clampf(snappedf(value, VOLUME_STEP), VOLUME_MIN, VOLUME_MAX)
		if is_equal_approx(snapped_value, music_volume):
			return
		music_volume = snapped_value
		Bus.audio_settings_changed.emit(music_volume, voice_volume)
		save()

var voice_volume: float = VOLUME_MAX:
	set(value):
		var snapped_value := clampf(snappedf(value, VOLUME_STEP), VOLUME_MIN, VOLUME_MAX)
		if is_equal_approx(snapped_value, voice_volume):
			return
		voice_volume = snapped_value
		Bus.audio_settings_changed.emit(music_volume, voice_volume)
		save()

## The game speaks Japanese first — that is the whole point. English is a safety net you
## True while the peek key is held, independent of the sticky preference above.
var _peeking: bool = false

## How much English the player wants, per UI_UX_GUIDE section 15. The old setting was
## a single "show English" switch, which could only say always or never; the middle
## two are the ones that actually teach. AFTER_ATTEMPT keeps the meaning hidden while
## you are answering and reveals it once you have committed, so the recall is real but
## the answer is never withheld.
## Named TranslationMode, not Translation: that shadows Godot's own class.
enum TranslationMode { HIDDEN, ON_REQUEST, AFTER_ATTEMPT, ALWAYS }
const TRANSLATION_LABELS := ["Hidden", "On request", "After attempt", "Always"]

var translation_mode: int = TranslationMode.ON_REQUEST:
	set(value):
		var next := clampi(value, 0, TranslationMode.size() - 1)
		if next == translation_mode:
			return
		translation_mode = next
		Bus.language_changed.emit(english_visible())
		save()

## Furigana over Japanese, section 15's Off/New/All. NEW shows the reading only while
## a word is still being learned, so the crutch falls away on its own rather than the
## player having to notice and turn it off.
enum Furigana { OFF, NEW, ALL }
const FURIGANA_LABELS := ["Off", "While learning", "Always"]
## Correct answers after which a word stops counting as new, for Furigana.NEW.
const FURIGANA_NEW_THRESHOLD := 3

var furigana_mode: int = Furigana.NEW:
	set(value):
		var next := clampi(value, 0, Furigana.size() - 1)
		if next == furigana_mode:
			return
		furigana_mode = next
		Bus.language_changed.emit(english_visible())
		save()


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
## Peeking is deliberately ignored in HIDDEN: a player who asked for no English at all
## should not get it by leaning on a key.
func english_visible() -> bool:
	if translation_mode == TranslationMode.ALWAYS:
		return true
	return _peeking and translation_mode != TranslationMode.HIDDEN


## Whether a surface should reveal the meaning once the player has answered.
func translation_on_reveal() -> bool:
	return translation_mode >= TranslationMode.AFTER_ATTEMPT


## Whether to print the reading above a prompt for a card with this many correct
## answers behind it.
func furigana_visible(correct_count: int) -> bool:
	match furigana_mode:
		Furigana.ALL:
			return true
		Furigana.NEW:
			return correct_count < FURIGANA_NEW_THRESHOLD
		_:
			return false


## Held-key peek. Kept separate from `translation_mode` so releasing the key returns to
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
	# Migrate the old boolean: someone who pinned English wanted it always, and the
	# default off state is really "on request", since peek already existed.
	var legacy_english := bool(cfg.get_value("language", "show_english", false))
	translation_mode = int(cfg.get_value("language", "translation_mode",
		TranslationMode.ALWAYS if legacy_english else TranslationMode.ON_REQUEST))
	furigana_mode = int(cfg.get_value("language", "furigana_mode", Furigana.NEW))
	music_volume = clampf(snappedf(
		float(cfg.get_value("audio", "music_volume", VOLUME_MAX)), VOLUME_STEP),
		VOLUME_MIN, VOLUME_MAX)
	voice_volume = clampf(snappedf(
		float(cfg.get_value("audio", "voice_volume", VOLUME_MAX)), VOLUME_STEP),
		VOLUME_MIN, VOLUME_MAX)
	ui_scale = _nearest_ui_scale(
		float(cfg.get_value("display", "ui_scale", UI_SCALE_DEFAULT)))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "zoom", zoom)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("language", "show_english", translation_mode == TranslationMode.ALWAYS)
	cfg.set_value("language", "translation_mode", translation_mode)
	cfg.set_value("language", "furigana_mode", furigana_mode)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "voice_volume", voice_volume)
	cfg.save(PATH)


## Step the zoom one notch. `direction` is +1 (closer) or -1 (further out).
func nudge_zoom(direction: int) -> void:
	zoom = zoom + ZOOM_STEP * signf(direction)


## Snap to an authored UI step. A free float would let a config edit (or a future
## slider) land on a scale no panel was ever measured at.
func _nearest_ui_scale(value: float) -> float:
	var best := UI_SCALE_DEFAULT
	for step in UI_SCALES:
		if absf(step - value) < absf(best - value):
			best = step
	return best


## Step the UI scale one notch through UI_SCALES. Returns false at either end, so
## a caller can grey out the control rather than silently doing nothing.
func nudge_ui_scale(direction: int) -> bool:
	var index := UI_SCALES.find(ui_scale)
	if index < 0:
		index = UI_SCALES.find(UI_SCALE_DEFAULT)
	var next := index + signi(direction)
	if next < 0 or next >= UI_SCALES.size():
		return false
	ui_scale = UI_SCALES[next]
	return true


func ui_scale_label() -> String:
	return "%d%%" % int(round(ui_scale * 100.0))


func reset() -> void:
	zoom = ZOOM_DEFAULT
