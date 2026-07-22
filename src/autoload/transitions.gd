extends Node
## Level transitions for the village <-> building interiors.
##
## A Door calls `travel()`; the destination scene reads `take_pending_spawn()` in its
## _ready and places its player at the matching spawn marker. Player-carried state
## (Inv, Learning, SaveGame) lives in other autoloads and survives
## change_scene_to_file, so only the arrival point needs to be handed across.
##
## The remember-spawn step is split from the scene change so the logic stays
## headless-testable without loading a real scene.

var _pending_spawn: String = ""


## Remember where to arrive, then load the target scene.
func travel(scene_path: String, spawn_id: String = "") -> void:
	set_pending_spawn(spawn_id)
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[Transitions] could not load %s (err %d)" % [scene_path, err])


func set_pending_spawn(spawn_id: String) -> void:
	_pending_spawn = spawn_id


## Read once on arrival; returns "" when nothing is pending and clears the slot so a
## later reload (or a fresh entry) does not reuse a stale spawn.
func take_pending_spawn() -> String:
	var s := _pending_spawn
	_pending_spawn = ""
	return s


func has_pending_spawn() -> bool:
	return not _pending_spawn.is_empty()
