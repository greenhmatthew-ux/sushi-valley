extends Node
## Playback for licensed Japanese pronunciation and verified CC0 game music.
##
## There is deliberately no generated-speech or text-to-speech fallback: cards
## without a mapped recording remain silent.

const MUSIC_TRACKS: Dictionary = {
	"title": "res://assets/audio/music/title.ogg",
	"battle": "res://assets/audio/music/battle.ogg",
	"mountain": "res://assets/audio/music/mountain.ogg",
	"interior": "res://assets/audio/music/interior.ogg",
	"village": "res://assets/audio/music/village.ogg",
	"forest": "res://assets/audio/music/forest.ogg",
}
const MUSIC_TRACK_IDS: Array[String] = [
	"title", "battle", "mountain", "interior", "village", "forest",
]
const MUSIC_VOLUME_LINEAR := 0.35
const MUSIC_FADE_SECONDS := 0.4
const MUSIC_SILENCE_DB := -80.0

var _player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _music_tween: Tween
var _music_streams: Dictionary = {}
var _current_music_track_id := ""
var _music_before_combat := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_player()
	_ensure_music_player()
	Bus.combat_started.connect(_on_combat_started)
	Bus.combat_ended.connect(_on_combat_ended)
	Bus.audio_settings_changed.connect(_on_audio_settings_changed)


func has_pronunciation(card_id: String) -> bool:
	var pronunciation := DB.pronunciation_for_card(card_id)
	if pronunciation.is_empty():
		return false
	var path := String(pronunciation.get("path", ""))
	return _is_audio_resource(path)


func play_pronunciation(card_id: String) -> bool:
	var pronunciation := DB.pronunciation_for_card(card_id)
	if pronunciation.is_empty():
		return false
	var path := String(pronunciation.get("path", ""))
	if not _is_audio_resource(path):
		return false
	var stream := ResourceLoader.load(path, "AudioStream") as AudioStream
	if stream == null:
		return false
	_ensure_player()
	_player.stop()
	_player.stream = stream
	_player.play()
	return true


func stop_pronunciation() -> void:
	if is_instance_valid(_player):
		_player.stop()


func play_music(track_id: String) -> bool:
	if not MUSIC_TRACKS.has(track_id):
		return false
	_ensure_music_player()
	if _current_music_track_id == track_id and _music_player.playing:
		return true

	var stream := _music_stream(track_id)
	if stream == null:
		return false

	_kill_music_tween()
	_current_music_track_id = track_id
	var target_db := _music_target_db()
	if not is_inside_tree():
		_start_music_stream(stream)
		_music_player.volume_db = target_db
		return true

	_music_tween = create_tween()
	if _music_player.playing:
		var half_fade := MUSIC_FADE_SECONDS * 0.5
		_music_tween.tween_property(
			_music_player, "volume_db", MUSIC_SILENCE_DB, half_fade
		)
		_music_tween.tween_callback(_start_music_stream.bind(stream))
		_music_tween.tween_property(_music_player, "volume_db", target_db, half_fade)
	else:
		_start_music_stream(stream)
		_music_player.volume_db = MUSIC_SILENCE_DB
		_music_tween.tween_property(
			_music_player, "volume_db", target_db, MUSIC_FADE_SECONDS
		)
	return true


func stop_music(fade: bool = true) -> void:
	_current_music_track_id = ""
	_music_before_combat = ""
	_kill_music_tween()
	if not is_instance_valid(_music_player) or not _music_player.playing:
		return
	if fade and is_inside_tree():
		_music_tween = create_tween()
		_music_tween.tween_property(
			_music_player, "volume_db", MUSIC_SILENCE_DB, MUSIC_FADE_SECONDS
		)
		_music_tween.tween_callback(_finish_music_stop)
	else:
		_finish_music_stop()


func current_music_id() -> String:
	return _current_music_track_id


func available_music_ids() -> Array[String]:
	return MUSIC_TRACK_IDS.duplicate()


func is_music_playing() -> bool:
	return is_instance_valid(_music_player) and _music_player.playing


func _ensure_player() -> void:
	if is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "PronunciationPlayer"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = _voice_db()
	add_child(_player)


func _ensure_music_player() -> void:
	if is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player.volume_db = _music_target_db()
	add_child(_music_player)


func _music_stream(track_id: String) -> AudioStream:
	if _music_streams.has(track_id):
		return _music_streams[track_id] as AudioStream
	var path := String(MUSIC_TRACKS.get(track_id, ""))
	if not _is_audio_resource(path):
		return null
	var loaded := ResourceLoader.load(path, "AudioStream") as AudioStream
	if loaded == null:
		return null
	var stream := loaded.duplicate() as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music_streams[track_id] = stream
	return stream


func _start_music_stream(stream: AudioStream) -> void:
	_music_player.stream = stream
	_music_player.play()


func _finish_music_stop() -> void:
	if not is_instance_valid(_music_player):
		return
	_music_player.stop()
	_music_player.stream = null
	_music_player.volume_db = _music_target_db()


## Effective music loudness: the pack's base mix level scaled by the player's setting.
## linear_to_db(0) is -inf, so silence floors at the same -80 dB the fades already use.
func _music_target_db() -> float:
	return _linear_to_db_safe(MUSIC_VOLUME_LINEAR * Settings.music_volume)


func _voice_db() -> float:
	return _linear_to_db_safe(Settings.voice_volume)


func _linear_to_db_safe(linear: float) -> float:
	return MUSIC_SILENCE_DB if linear <= 0.0 else linear_to_db(linear)


## Live retune: the settings panel announces on the Bus; only the players change. A fade
## already in flight owns the music volume, so it is killed rather than fought.
func _on_audio_settings_changed(_music: float, _voice: float) -> void:
	if is_instance_valid(_player):
		_player.volume_db = _voice_db()
	if is_instance_valid(_music_player) and _music_player.playing:
		_kill_music_tween()
		_music_player.volume_db = _music_target_db()


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


func _on_combat_started(_enemy_id: String) -> void:
	if _current_music_track_id == "battle":
		return
	_music_before_combat = _current_music_track_id
	play_music("battle")


func _on_combat_ended(_victory: bool) -> void:
	var resume_track := _music_before_combat
	_music_before_combat = ""
	if resume_track.is_empty():
		stop_music()
	else:
		play_music(resume_track)


func _is_audio_resource(path: String) -> bool:
	return path.begins_with("res://") and ResourceLoader.exists(path, "AudioStream")
