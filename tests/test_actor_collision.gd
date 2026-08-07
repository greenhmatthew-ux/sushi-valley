extends SceneTree
## Static contract for the body layers that keep overworld actors from blocking one another.
##
## This reads the authored scene/script values directly instead of instantiating gameplay. That
## keeps the check focused on collision policy and lets it catch an accidental editor re-save that
## puts either actor back on the terrain layer.
##
##   godot --headless --path . --script res://tests/test_actor_collision.gd

const TERRAIN_LAYER := 1
const PLAYER_BODY_LAYER := 2
const ENEMY_BODY_LAYER := 4

const PLAYER_SCENE := "res://src/entities/player.tscn"
const ENEMY_SCENE := "res://src/entities/enemy.tscn"
const DOOR_SCENE := "res://src/entities/door.tscn"
## Every Expedition room hides and wakes its boss the same way, so every one of them
## has to restore the enemy onto the enemy layer rather than onto terrain.
const EXPEDITION_SCRIPTS: Array[String] = [
	"res://src/scenes/expedition_forest.gd",
	"res://src/scenes/expedition_pass.gd",
]

var failures: int = 0


func _initialize() -> void:
	var player_block := _root_node_block(PLAYER_SCENE, "Player", "CharacterBody2D")
	var enemy_block := _root_node_block(ENEMY_SCENE, "Enemy", "CharacterBody2D")
	var door_block := _root_node_block(DOOR_SCENE, "Door", "Area2D")

	_check_authored_values(player_block, enemy_block, door_block)
	_check_actor_masks(player_block, enemy_block)
	_check_door_detects_only_the_player(door_block)
	_check_expedition_restores_the_enemy_layer()
	_finish()


func _check_authored_values(player_block: String, enemy_block: String,
		door_block: String) -> void:
	check_true("player root node is present", not player_block.is_empty())
	check_true("enemy root node is present", not enemy_block.is_empty())
	check_true("door root node is present", not door_block.is_empty())
	check_eq("player body lives on the dedicated player layer",
		_int_property(player_block, "collision_layer"), PLAYER_BODY_LAYER)
	check_eq("player body scans terrain only",
		_int_property(player_block, "collision_mask"), TERRAIN_LAYER)
	check_eq("enemy body lives on the dedicated enemy layer",
		_int_property(enemy_block, "collision_layer"), ENEMY_BODY_LAYER)
	check_eq("enemy body scans terrain only",
		_int_property(enemy_block, "collision_mask"), TERRAIN_LAYER)
	check_eq("door interaction scans the player layer",
		_int_property(door_block, "collision_mask"), PLAYER_BODY_LAYER)


func _check_actor_masks(player_block: String, enemy_block: String) -> void:
	var player_mask := _int_property(player_block, "collision_mask")
	var enemy_mask := _int_property(enemy_block, "collision_mask")
	check_true("player still collides with terrain", (player_mask & TERRAIN_LAYER) != 0)
	check_true("enemy still collides with terrain", (enemy_mask & TERRAIN_LAYER) != 0)
	check_true("player body excludes enemy bodies", (player_mask & ENEMY_BODY_LAYER) == 0)
	check_true("enemy body excludes the player body", (enemy_mask & PLAYER_BODY_LAYER) == 0)
	check_true("player and enemy body layers remain distinct",
		PLAYER_BODY_LAYER != ENEMY_BODY_LAYER)


func _check_door_detects_only_the_player(door_block: String) -> void:
	var door_mask := _int_property(door_block, "collision_mask")
	check_true("door includes the player body", (door_mask & PLAYER_BODY_LAYER) != 0)
	check_true("door excludes enemy bodies", (door_mask & ENEMY_BODY_LAYER) == 0)
	check_true("door excludes terrain", (door_mask & TERRAIN_LAYER) == 0)


func _check_expedition_restores_the_enemy_layer() -> void:
	for path in EXPEDITION_SCRIPTS:
		var room := path.get_file().get_basename()
		var source := FileAccess.get_file_as_string(path)
		var active_block := _function_block(source, "_set_active")
		check_true("%s stage activation function is present" % room,
			not active_block.is_empty())
		check_true("%s reactivation restores the dedicated enemy layer" % room,
			active_block.contains("\"collision_layer\", 4 if active else 0"))
		check_true("%s never restores an enemy onto the terrain layer" % room,
			not active_block.contains("\"collision_layer\", 1 if active else 0"))


func _root_node_block(path: String, node_name: String, node_type: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var header := "[node name=\"%s\" type=\"%s\"]" % [node_name, node_type]
	var start := source.find(header)
	if start < 0:
		return ""
	var finish := source.find("\n[node ", start + header.length())
	if finish < 0:
		finish = source.length()
	return source.substr(start, finish - start)


func _function_block(source: String, function_name: String) -> String:
	var signature := "func %s(" % function_name
	var start := source.find(signature)
	if start < 0:
		return ""
	var finish := source.find("\nfunc ", start + signature.length())
	if finish < 0:
		finish = source.length()
	return source.substr(start, finish - start)


func _int_property(block: String, property_name: String) -> int:
	var prefix := property_name + " = "
	for raw_line in block.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.begins_with(prefix):
			return int(line.trim_prefix(prefix))
	return -1


func _finish() -> void:
	print("")
	print("PASS - actor bodies share terrain without blocking one another." if failures == 0 \
		else "FAIL - %d actor-collision check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
