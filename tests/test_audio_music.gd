extends SceneTree
## Verified CC0 music assets, public playback state, and world/combat routing.
##
##   godot --headless --path . --script res://tests/test_audio_music.gd
##
## The test uses the real Audio autoload, but asserts state immediately rather
## than waiting for fades or requiring a physical audio device.

const TRACKS := {
	"title": {
		"path": "res://assets/audio/music/title.ogg",
		"sha256": "858490b0f1c09730ceaede1cdadf3912ab4d1bfd0dd90732171cfded3e773810",
	},
	"village": {
		"path": "res://assets/audio/music/village.ogg",
		"sha256": "c8707cef6c90621a960e2e3bc2c3cc1a4e25c6e1509cd232aa5a162316623dfd",
	},
	"forest": {
		"path": "res://assets/audio/music/forest.ogg",
		"sha256": "3a53eaa9a68f0b9dec59d842f585bba99c3f0011808deff6860ad475245b2bb1",
	},
	"interior": {
		"path": "res://assets/audio/music/interior.ogg",
		"sha256": "655bb2ea668af8438ac95bcb89ea8c63738948cda9bc1148867fb141953e20f1",
	},
	"battle": {
		"path": "res://assets/audio/music/battle.ogg",
		"sha256": "137f9a19a043c23c02179d722b14e9014bc3d73546db722a91640bd6181f1089",
	},
	"mountain": {
		"path": "res://assets/audio/music/mountain.ogg",
		"sha256": "775400a7d3f47b24e62d8139ed012fd595902a814fdcc2357d5f06946aafa88f",
	},
}

const SCENE_MUSIC := {
	"res://src/scenes/world.gd": "village",
	"res://src/scenes/wilds.gd": "forest",
	"res://src/scenes/interior_house.gd": "interior",
}

var failures := 0


func _initialize() -> void:
	await process_frame
	var audio := root.get_node_or_null("Audio")
	check_true("Audio autoload is present", audio != null)
	if audio == null:
		_finish()
		return

	var api_ok := (
		audio.has_method("current_music_id")
		and audio.has_method("available_music_ids")
		and audio.has_method("play_music")
		and audio.has_method("stop_music")
		and audio.has_method("is_music_playing")
	)
	check_true("Audio exposes the public music API", api_ok)
	if not api_ok:
		_finish()
		return

	audio.stop_music(false)
	_validate_assets(audio)
	_validate_scene_requests()
	_validate_public_state(audio)
	_validate_volume_settings(audio)
	var bus := root.get_node_or_null("Bus")
	check_true("Bus autoload is present", bus != null)
	if bus != null:
		_validate_combat_resume(audio, bus)
	audio.stop_music(false)
	_finish()


func _validate_assets(audio: Node) -> void:
	var expected_ids: Array[String] = []
	for raw_id: Variant in TRACKS:
		expected_ids.append(String(raw_id))
	expected_ids.sort()

	var available: Array[String] = audio.available_music_ids()
	available.sort()
	check_eq("Audio advertises exactly the six verified tracks", available, expected_ids)

	var failures_before := failures
	for raw_id: Variant in TRACKS:
		var track_id := String(raw_id)
		var definition: Dictionary = TRACKS[raw_id]
		var path := String(definition["path"])
		var expected_hash := String(definition["sha256"])

		_require("%s file exists" % track_id, FileAccess.file_exists(path))
		_require("%s is an imported AudioStream" % track_id,
			ResourceLoader.exists(path, "AudioStream"))
		var stream := ResourceLoader.load(path, "AudioStream") as AudioStream
		_require("%s resource loads" % track_id, stream != null)
		_require("%s resource is Ogg Vorbis" % track_id,
			stream is AudioStreamOggVorbis)
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			_require("%s file opens" % track_id, file != null)
			if file != null:
				_require_eq("%s has OggS header" % track_id,
					file.get_buffer(4).get_string_from_ascii(), "OggS")
				file.close()
			_require_eq("%s matches the verified source bytes" % track_id,
				FileAccess.get_sha256(path).to_lower(), expected_hash)

	check_true("all six CC0 music resources and hashes are valid",
		failures == failures_before)


func _validate_scene_requests() -> void:
	for raw_path: Variant in SCENE_MUSIC:
		var path := String(raw_path)
		var track_id := String(SCENE_MUSIC[raw_path])
		check_true("%s requests %s music on ready" % [path.get_file(), track_id],
			_script_requests_track(path, track_id))


func _validate_public_state(audio: Node) -> void:
	check_eq("music starts with no selected id", audio.current_music_id(), "")

	for raw_id: Variant in TRACKS:
		var track_id := String(raw_id)
		check_true("play_music accepts %s" % track_id, audio.play_music(track_id))
		check_eq("%s becomes current immediately" % track_id,
			audio.current_music_id(), track_id)
		check_true("%s starts the music player" % track_id, audio.is_music_playing())

	var before_invalid: String = audio.current_music_id()
	check_true("unknown music id is rejected", not audio.play_music("not-a-track"))
	check_eq("rejected music does not replace current state",
		audio.current_music_id(), before_invalid)

	audio.stop_music(false)
	check_eq("stop_music clears current id immediately", audio.current_music_id(), "")
	check_true("non-faded stop halts the player", not audio.is_music_playing())


## The Settings autoload owns music/pronunciation volume; Audio must scale its live
## players by it, floor at silence instead of -inf dB, and retune immediately on change.
func _validate_volume_settings(audio: Node) -> void:
	var settings: Node = root.get_node("Settings")
	# Mirrors audio.gd's MUSIC_VOLUME_LINEAR / MUSIC_SILENCE_DB constants, which are not
	# reachable as members through a Node-typed reference.
	var base_linear := 0.35
	var silence_db := -80.0
	var music_player := audio.get("_music_player") as AudioStreamPlayer
	var voice_player := audio.get("_player") as AudioStreamPlayer
	check_true("both audio players exist", music_player != null and voice_player != null)

	settings.music_volume = 0.5
	settings.voice_volume = 0.25
	check_close("music target scales the base mix by the setting",
		float(audio.call("_music_target_db")), linear_to_db(base_linear * 0.5))
	check_close("pronunciation player retunes live",
		voice_player.volume_db, linear_to_db(0.25))

	var cfg := ConfigFile.new()
	check_eq("volumes persist to settings.cfg", cfg.load("user://settings.cfg"), OK)
	check_eq("persisted music volume round-trips",
		float(cfg.get_value("audio", "music_volume", -1.0)), 0.5)
	check_eq("persisted pronunciation volume round-trips",
		float(cfg.get_value("audio", "voice_volume", -1.0)), 0.25)

	check_true("music starts for the live-retune check", audio.play_music("village"))
	settings.music_volume = 0.75
	check_close("playing music retunes to the setting immediately",
		music_player.volume_db, linear_to_db(base_linear * 0.75))
	settings.music_volume = 0.0
	check_close("zero music volume floors at silence, not -inf",
		music_player.volume_db, silence_db)
	audio.stop_music(false)

	settings.music_volume = 1.0
	settings.voice_volume = 1.0
	check_close("full music volume restores the base mix",
		float(audio.call("_music_target_db")), linear_to_db(base_linear))


func _validate_combat_resume(audio: Node, bus: Node) -> void:
	check_true("forest setup starts", audio.play_music("forest"))
	bus.emit_signal("combat_started", "snake")
	check_eq("combat immediately switches to battle",
		audio.current_music_id(), "battle")
	bus.emit_signal("combat_ended", true)
	check_eq("combat end resumes the interrupted forest track",
		audio.current_music_id(), "forest")

	# A second start signal must not overwrite the remembered exploration track.
	check_true("village setup starts", audio.play_music("village"))
	bus.emit_signal("combat_started", "mushroom")
	bus.emit_signal("combat_started", "mushroom")
	check_eq("repeated combat start remains on battle",
		audio.current_music_id(), "battle")
	bus.emit_signal("combat_ended", false)
	check_eq("repeated combat start still resumes village",
		audio.current_music_id(), "village")

	# Combat entered from silence should return to silence, not a stale prior scene.
	audio.stop_music(false)
	bus.emit_signal("combat_started", "slime")
	check_eq("combat can start from silence", audio.current_music_id(), "battle")
	bus.emit_signal("combat_ended", false)
	check_eq("combat entered from silence clears back to silence",
		audio.current_music_id(), "")


func _script_requests_track(path: String, track_id: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var expected := 'Audio.play_music("%s")' % track_id
	for raw_line: String in FileAccess.get_file_as_string(path).split("\n"):
		if raw_line.strip_edges() == expected:
			return true
	return false


func _finish() -> void:
	print("")
	print(("PASS - CC0 music assets, routing, and combat resume are valid."
		if failures == 0 else
		"FAIL - %d music check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


## Decibel values pick up sub-decimal noise from snappedf volume steps; compare loosely.
func check_close(label: String, got: float, want: float) -> void:
	var ok: bool = absf(got - want) < 0.001
	print(("  ok   " if ok else "  FAIL ") + label
		+ ("" if ok else " (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1


func check_eq(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("  ok   " if ok else "  FAIL ") + label
		+ ("" if ok else " (got %s, want %s)" % [got, want]))
	if not ok:
		failures += 1


func _require(label: String, ok: bool) -> void:
	if not ok:
		print("  FAIL " + label)
		failures += 1


func _require_eq(label: String, got: Variant, want: Variant) -> void:
	if got != want:
		print("  FAIL %s (got %s, want %s)" % [label, got, want])
		failures += 1
