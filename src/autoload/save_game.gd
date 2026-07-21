extends Node
## Local save persistence. Replaces localStorage from the web build with a JSON
## file under user://.
##
## One local profile for now (user://profile.json). The TS build keyed saves per
## guest/cloud character; that multi-character keying arrives with cloud saves
## (Slice 10). Keeping the read/write here means the profile model stays pure and
## file IO lives in exactly one place.

const PROFILE_PATH := "user://profile.json"


## Parsed saved profile data, or {} if there is no save yet / it is unreadable.
## A corrupt file is backed up rather than silently overwritten, so a bad save is
## recoverable instead of lost.
func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(PROFILE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("[SaveGame] profile.json was unreadable; backing it up and starting fresh.")
	_backup_corrupt(text)
	return {}


func save_profile(data: Dictionary) -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveGame] could not open %s for writing (err %d)" % [PROFILE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()


func has_save() -> bool:
	return FileAccess.file_exists(PROFILE_PATH)


## Delete the local save. Used by a "new game" flow; guarded so callers must mean it.
func clear() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _backup_corrupt(text: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup := FileAccess.open("user://profile.corrupt.%s.json" % stamp, FileAccess.WRITE)
	if backup != null:
		backup.store_string(text)
		backup.close()
