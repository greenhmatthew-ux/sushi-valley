extends Node
## Playback for licensed, recorded Japanese pronunciation clips.
##
## There is deliberately no generated-speech or text-to-speech fallback: cards
## without a mapped recording remain silent.

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_player()


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


func _ensure_player() -> void:
	if is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "PronunciationPlayer"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)


func _is_audio_resource(path: String) -> bool:
	return path.begins_with("res://") and ResourceLoader.exists(path, "AudioStream")
