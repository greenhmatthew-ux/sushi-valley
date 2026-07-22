extends Node
## Local save persistence. Replaces localStorage from the web build with a JSON
## file under user://.
##
## One local profile for now (user://profile.json). The TS build keyed saves per
## guest/cloud character; that multi-character keying arrives with cloud saves
## (Slice 10). Keeping the read/write here means the profile model stays pure and
## file IO lives in exactly one place.
##
## --- Save document shape (Slice: Persistence) ---
## The file is a single versioned document that wraps every persisted subsystem:
##
##   { "version": 1,
##     "learning": { ...slim LearningProfile save dict (cards/flags/stats/build)... },
##     "world":    { "player": { "x": <float>, "y": <float>, "facing": "down" } } }
##
## `version` is SAVE_SCHEMA_VERSION and exists so future shape changes have a
## migration hook (the project rule: no schema change without a migration plan).
##
## The Learning autoload still persists through save_profile()/load_profile(),
## which now read and write ONLY the "learning" section of this document — so the
## world section is never clobbered by a mid-session learning save. A pre-wrap
## (flat) profile.json is migrated on the first read: a document with no "learning"
## key is treated as the legacy learning dict and wrapped on the next save.

const SAVE_SCHEMA_VERSION := 1
const PROFILE_PATH := "user://profile.json"


# --- learning-facing IO (the Learning autoload calls these) ----------------

## The persisted LEARNING state, or {} if there is no save yet / it is unreadable.
## Unwraps the "learning" section of a versioned document; a legacy flat profile
## (no "learning" key) is returned as-is, which IS its learning data — so old saves
## keep loading unchanged until the next save upgrades them to the wrapped shape.
func load_profile() -> Dictionary:
	var doc := _read_document()
	if doc.has("learning") and doc["learning"] is Dictionary:
		return doc["learning"]
	return doc


## Persist the LEARNING section, preserving any existing world section so a
## mid-session learning save never drops the player's saved position. Always
## writes the current wrapped shape (migrating a legacy flat file in the process).
func save_profile(learning_data: Dictionary) -> void:
	var doc := _read_document()
	# Carry world forward only from an already-wrapped doc; a legacy flat doc has
	# no world section, and its top-level keys must NOT leak into the new wrapper.
	var world_section: Dictionary = doc.get("world", {}) if doc.has("learning") else {}
	_write_document({
		"version": SAVE_SCHEMA_VERSION,
		"learning": learning_data,
		"world": world_section,
	})


func has_save() -> bool:
	return FileAccess.file_exists(PROFILE_PATH)


## Delete the local save. Used by a "new game" flow; guarded so callers must mean it.
func clear() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


# --- full-snapshot layer (world.gd calls these) ----------------------------

## Assemble a full versioned snapshot from explicit parts. Pure — it touches no
## autoloads or scene nodes — so it round-trips in a headless test. The in-game
## caller passes Learning.profile.to_save_dict() and the Player's live transform.
func build_snapshot(learning_data: Dictionary, player_pos: Vector2, facing: String) -> Dictionary:
	return {
		"version": SAVE_SCHEMA_VERSION,
		"learning": learning_data,
		"world": {
			"player": {"x": player_pos.x, "y": player_pos.y, "facing": facing},
		},
	}


## Build and write a full snapshot (learning + world) to disk, then announce it.
## Emitting is guarded to the in-tree autoload so a bare SaveGame.new() in a test
## does not reach for the Bus singleton.
func save_snapshot(learning_data: Dictionary, player_pos: Vector2, facing: String) -> void:
	_write_document(build_snapshot(learning_data, player_pos, facing))
	if is_inside_tree():
		Bus.game_saved.emit()


## The full on-disk document (wrapped, or a legacy flat profile), or {} if none.
## world.gd hands this straight to apply_snapshot().
func load_snapshot() -> Dictionary:
	return _read_document()


## Unpack a snapshot (wrapped or legacy) into its live parts and announce the load.
## Returns the pieces the caller needs to restore state:
##   { "learning": Dictionary,       # the learning save dict (rebuild a LearningProfile from it)
##     "position": Vector2,          # saved Player position ({0,0} if absent)
##     "facing":   String,           # saved Player facing ("down" if absent)
##     "has_player": bool }          # whether a player placement was actually stored
## In-game, learning state is already live: the Learning autoload restores it in
## its own _ready() via load_profile(), so world.gd only needs the placement here.
func apply_snapshot(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"learning": {}, "position": Vector2.ZERO, "facing": "down", "has_player": false}

	var learning_data: Dictionary = data["learning"] if (data.has("learning") and data["learning"] is Dictionary) else data
	var world: Dictionary = data.get("world", {})
	var player: Dictionary = world.get("player", {})
	var has_player: bool = player.has("x") and player.has("y")
	var pos := Vector2(float(player.get("x", 0.0)), float(player.get("y", 0.0)))
	var facing := String(player.get("facing", "down"))

	if is_inside_tree():
		Bus.game_loaded.emit()

	return {
		"learning": learning_data,
		"position": pos,
		"facing": facing,
		"has_player": has_player,
	}


# --- file IO ---------------------------------------------------------------

## Parse the whole save document. A corrupt file is backed up rather than silently
## overwritten, so a bad save is recoverable instead of lost.
func _read_document() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(PROFILE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("[SaveGame] profile.json was unreadable; backing it up and starting fresh.")
	_backup_corrupt(text)
	return {}


func _write_document(doc: Dictionary) -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveGame] could not open %s for writing (err %d)" % [PROFILE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(doc))
	file.close()


func _backup_corrupt(text: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup := FileAccess.open("user://profile.corrupt.%s.json" % stamp, FileAccess.WRITE)
	if backup != null:
		backup.store_string(text)
		backup.close()
