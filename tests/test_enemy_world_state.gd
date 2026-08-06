extends SceneTree
## Deterministic overworld enemy-state contract.
##
## This deliberately drives the state evaluator directly instead of waiting an
## exact number of physics frames. Physics owns movement; advance_world_state()
## owns readable decisions and is therefore the stable seam this test pins.
##
##   godot --headless --path . --script res://tests/test_enemy_world_state.gd

const ENEMY_SCENE := "res://src/entities/enemy.tscn"
const ACTIVE_REGION_SCENES: Array[String] = [
	"res://src/scenes/world.tscn",
	"res://src/scenes/wilds.tscn",
	"res://src/scenes/mountain_pass.tscn",
	"res://src/scenes/expedition_forest.tscn",
]
const REQUIRED_STATES: Array[String] = [
	"IDLE", "ROAM", "ALERT", "CHASE", "ENGAGE", "RETURN",
]
const REQUIRED_AGGRO_LEVELS: Array[String] = [
	"PASSIVE", "PROVOKED", "WARY", "TERRITORIAL", "HUNTER",
]
const REQUIRED_PROPERTIES: Array[String] = [
	"world_state", "aggro_level", "idle_duration", "warning_seconds",
	"memory_seconds", "leash_radius", "roam_radius", "roam_speed",
	"chase_speed", "burst_speed", "burst_duration", "burst_recovery",
]

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var probe: Node = load(ENEMY_SCENE).instantiate()
	var states := _enum_values(probe, "WorldState")
	var aggro_levels := _enum_values(probe, "AggroLevel")
	var seam_ready := _check_runtime_seam(probe, states, aggro_levels)
	if seam_ready:
		_check_state_transitions(probe, states, aggro_levels)
		_check_disposition_triggers(probe, states, aggro_levels)
		_check_wary_warning_retreat(probe, states, aggro_levels)
		_check_hunter_burst_recovery(probe, states, aggro_levels)
		_check_post_flee_grace(probe, states, aggro_levels)
		_check_authored_contrast(aggro_levels)
		_check_active_region_speed_bands()
		await _check_swing_uses_recall_encounter(states)
		await _check_real_line_of_sight()
	probe.free()
	_finish()


func _check_runtime_seam(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> bool:
	var ok := true
	for state_name in REQUIRED_STATES:
		var present := states.has(state_name)
		check_true("WorldState exposes %s" % state_name, present)
		ok = ok and present
	for level_name in REQUIRED_AGGRO_LEVELS:
		var present := aggro_levels.has(level_name)
		check_true("AggroLevel exposes %s" % level_name, present)
		ok = ok and present
	for property_name in REQUIRED_PROPERTIES:
		var present := _has_property(enemy, property_name)
		check_true("enemy exposes %s" % property_name, present)
		ok = ok and present
	var can_reset := enemy.has_method("reset_world_state")
	var can_advance := enemy.has_method("advance_world_state")
	check_true("enemy exposes reset_world_state(home)", can_reset)
	check_true("enemy exposes deterministic advance_world_state", can_advance)
	return ok and can_reset and can_advance


func _check_state_transitions(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> void:
	enemy.set("aggro_level", int(aggro_levels["TERRITORIAL"]))
	enemy.set("idle_duration", 0.0)
	enemy.set("warning_seconds", 0.4)
	enemy.set("memory_seconds", 0.8)
	enemy.set("detect_radius", 96.0)
	enemy.set("leash_radius", 144.0)
	enemy.set("roam_radius", 32.0)
	enemy.set("roam_speed", 24.0)
	enemy.set("chase_speed", 52.0)
	enemy.set("burst_speed", 0.0)
	enemy.set("burst_duration", 0.0)
	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	check_eq("reset starts at IDLE", _state(enemy), int(states["IDLE"]))

	var far_player := Vector2(260.0, 0.0)
	var seen_player := Vector2(64.0, 0.0)
	var contact_player := Vector2(10.0, 0.0)
	_advance(enemy, 0.01, far_player, true)
	check_eq("an expired idle begins bounded ROAM",
		_state(enemy), int(states["ROAM"]))
	_advance(enemy, 0.01, seen_player, true)
	check_eq("seeing the player enters ALERT before pursuit",
		_state(enemy), int(states["ALERT"]))
	_advance(enemy, 0.39, seen_player, true)
	check_eq("warning delay holds ALERT instead of instantly chasing",
		_state(enemy), int(states["ALERT"]))
	_advance(enemy, 0.02, seen_player, true)
	check_eq("finishing the warning enters CHASE",
		_state(enemy), int(states["CHASE"]))
	_advance(enemy, 0.01, contact_player, true)
	check_eq("contact range enters ENGAGE",
		_state(enemy), int(states["ENGAGE"]))

	_reach_chase(enemy, seen_player)
	_advance(enemy, 0.79, seen_player, false)
	check_eq("brief lost sight uses authored memory",
		_state(enemy), int(states["CHASE"]))
	_advance(enemy, 0.02, seen_player, false)
	check_eq("expired sight memory enters RETURN",
		_state(enemy), int(states["RETURN"]))

	_reach_chase(enemy, seen_player)
	enemy.global_position = Vector2(145.0, 0.0)
	_advance(enemy, 0.01, Vector2(160.0, 0.0), true)
	check_eq("crossing the home leash forces RETURN even with line of sight",
		_state(enemy), int(states["RETURN"]))
	enemy.global_position = Vector2(1.0, 0.0)
	_advance(enemy, 0.01, far_player, false)
	check_eq("reaching home completes RETURN at IDLE",
		_state(enemy), int(states["IDLE"]))


func _reach_chase(enemy: Node, player_position: Vector2) -> void:
	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	_advance(enemy, 0.01, player_position, true)
	_advance(enemy, float(enemy.get("warning_seconds")) + 0.01,
		player_position, true)


func _check_disposition_triggers(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> void:
	enemy.set("idle_duration", 10.0)
	enemy.set("detect_radius", 96.0)
	enemy.set("warning_seconds", 0.4)
	enemy.global_position = Vector2.ZERO
	enemy.set("aggro_level", int(aggro_levels["PASSIVE"]))
	enemy.call("reset_world_state", Vector2.ZERO)
	_advance(enemy, 1.0, Vector2(10.0, 0.0), true)
	check_eq("PASSIVE never initiates even at contact",
		_state(enemy), int(states["IDLE"]))

	enemy.set("aggro_level", int(aggro_levels["PROVOKED"]))
	enemy.set("warning_seconds", 0.0)
	enemy.call("reset_world_state", Vector2.ZERO)
	_advance(enemy, 1.0, Vector2(10.0, 0.0), true)
	check_eq("PROVOKED ignores proximity before a trigger",
		_state(enemy), int(states["IDLE"]))
	var source := Node2D.new()
	source.global_position = Vector2(40.0, 0.0)
	enemy.call("provoke", source)
	check_eq("PROVOKED chases after an explicit trigger",
		_state(enemy), int(states["CHASE"]))
	source.free()


func _check_wary_warning_retreat(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> void:
	enemy.set("aggro_level", int(aggro_levels["WARY"]))
	enemy.set("idle_duration", 10.0)
	enemy.set("detect_radius", 100.0)
	enemy.set("warning_seconds", 0.5)
	enemy.set("memory_seconds", 1.0)
	enemy.set("leash_radius", 144.0)
	enemy.set("roam_speed", 22.0)
	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	var close_player := Vector2(50.0, 0.0)
	_advance(enemy, 0.01, close_player, true)
	_advance(enemy, 0.2, close_player, true)
	check_eq("WARY holds ALERT during its warning",
		_state(enemy), int(states["ALERT"]))
	check_true("WARY warning velocity yields ground instead of charging",
		(enemy.get("velocity") as Vector2).x < 0.0)
	_advance(enemy, 0.31, close_player, true)
	check_eq("WARY commits only when the player stays close",
		_state(enemy), int(states["CHASE"]))

	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	var edge_player := Vector2(80.0, 0.0)
	_advance(enemy, 0.01, edge_player, true)
	_advance(enemy, 0.51, edge_player, true)
	check_eq("WARY returns home when its warning is respected",
		_state(enemy), int(states["RETURN"]))


func _check_hunter_burst_recovery(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> void:
	enemy.set("enemy_id", "bat")
	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	var player_position := Vector2(64.0, 0.0)
	_advance(enemy, 0.01, player_position, true)
	_advance(enemy, float(enemy.get("warning_seconds")) + 0.01,
		player_position, true)
	_advance(enemy, 0.01, player_position, true)
	check_eq("HUNTER begins with its authored short burst",
		roundf((enemy.get("velocity") as Vector2).length()),
		float(enemy.get("burst_speed")))
	_advance(enemy, float(enemy.get("burst_duration")), player_position, true)
	_advance(enemy, 0.01, player_position, true)
	check_eq("HUNTER drops to escapable chase speed during recovery",
		roundf((enemy.get("velocity") as Vector2).length()),
		float(enemy.get("chase_speed")))
	_advance(enemy, float(enemy.get("burst_recovery")) - 0.1,
		player_position, true)
	check_eq("HUNTER cannot burst again before recovery completes",
		roundf((enemy.get("velocity") as Vector2).length()),
		float(enemy.get("chase_speed")))
	_advance(enemy, 0.2, player_position, true)
	check_eq("HUNTER may burst again only after full recovery",
		roundf((enemy.get("velocity") as Vector2).length()),
		float(enemy.get("burst_speed")))
	check_eq("burst proof remains in CHASE",
		_state(enemy), int(states["CHASE"]))


func _check_post_flee_grace(enemy: Node, states: Dictionary,
		aggro_levels: Dictionary) -> void:
	enemy.set("aggro_level", int(aggro_levels["TERRITORIAL"]))
	enemy.set("idle_duration", 10.0)
	enemy.set("detect_radius", 96.0)
	enemy.set("warning_seconds", 0.4)
	enemy.set("post_flee_grace", 2.5)
	enemy.global_position = Vector2.ZERO
	enemy.call("reset_world_state", Vector2.ZERO)
	enemy.call("retreat_after_encounter")
	_advance(enemy, 0.01, Vector2(24.0, 0.0), true)
	check_eq("flee outcome returns home before reacquiring",
		_state(enemy), int(states["IDLE"]))
	_advance(enemy, 2.3, Vector2(24.0, 0.0), true)
	check_eq("post-flee grace prevents immediate re-engagement",
		_state(enemy), int(states["IDLE"]))
	_advance(enemy, 0.3, Vector2(24.0, 0.0), true)
	check_eq("enemy may warn again after flee grace expires",
		_state(enemy), int(states["ALERT"]))


func _check_real_line_of_sight() -> void:
	var enemy := load(ENEMY_SCENE).instantiate() as CharacterBody2D
	enemy.set_physics_process(false)
	enemy.global_position = Vector2.ZERO
	root.add_child(enemy)
	var player := Node2D.new()
	player.global_position = Vector2(96.0, 0.0)
	root.add_child(player)
	await physics_frame
	check_true("real terrain ray starts clear",
		bool(enemy.call("_has_line_of_sight", player)))

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(48.0, 0.0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12.0, 48.0)
	shape.shape = rectangle
	wall.add_child(shape)
	root.add_child(wall)
	await physics_frame
	check_true("real layer-1 terrain blocks enemy sight",
		not bool(enemy.call("_has_line_of_sight", player)))
	wall.collision_layer = 0
	await physics_frame
	check_true("non-terrain actors do not block enemy sight",
		bool(enemy.call("_has_line_of_sight", player)))

	wall.queue_free()
	player.queue_free()
	enemy.queue_free()
	await process_frame


func _check_swing_uses_recall_encounter(states: Dictionary) -> void:
	var director: Node = root.get_node("EncounterDirector")
	var enemy := load(ENEMY_SCENE).instantiate() as CharacterBody2D
	enemy.set("enemy_id", "mushroom")
	enemy.set_physics_process(false)
	root.add_child(enemy)
	await process_frame
	var hp_before := int(enemy.get("hp"))
	enemy.call("take_damage", 999)
	var token := String(director.call("active_token"))
	check_true("overworld swing reserves a recall encounter token", not token.is_empty())
	check_eq("overworld swing cannot bypass learning by reducing hostile HP",
		int(enemy.get("hp")), hp_before)
	check_eq("overworld swing moves the hostile into ENGAGE",
		int(enemy.get("world_state")), int(states["ENGAGE"]))
	check_true("test can resolve the swing-owned encounter",
		bool(director.call("resolve", token, false)))
	await process_frame
	check_true("fleeing the swing-owned encounter returns or settles at home",
		int(enemy.get("world_state")) in [int(states["RETURN"]), int(states["IDLE"])])
	check_true("fleeing releases the swing-owned encounter",
		not bool(director.call("is_busy")))
	enemy.queue_free()
	await process_frame


func _check_authored_contrast(aggro_levels: Dictionary) -> void:
	var wilds: Node = load("res://src/scenes/wilds.tscn").instantiate()
	var mountain: Node = load("res://src/scenes/mountain_pass.tscn").instantiate()
	var mushroom := _find_enemy(wilds, "mushroom")
	var bat := _find_enemy(mountain, "bat")
	check_true("Whispering Woods authors a Mushroom", mushroom != null)
	check_true("Mountain Pass authors a Bat", bat != null)
	if mushroom == null or bat == null:
		wilds.free()
		mountain.free()
		return

	check_eq("Mushroom uses the warning-heavy WARY profile",
		int(mushroom.get("aggro_level")), int(aggro_levels["WARY"]))
	check_eq("Bat uses the pursuit-heavy HUNTER profile",
		int(bat.get("aggro_level")), int(aggro_levels["HUNTER"]))
	check_true("Bat notices the player farther away",
		float(bat.get("detect_radius")) > float(mushroom.get("detect_radius")))
	check_true("Mushroom gives at least as much warning as Bat",
		float(mushroom.get("warning_seconds")) >= float(bat.get("warning_seconds")))
	check_true("Bat chases faster than Mushroom without matching player speed",
		float(bat.get("chase_speed")) > float(mushroom.get("chase_speed"))
		and not _forbidden_sustained_speed(float(bat.get("chase_speed"))))
	check_true("WARY Mushroom has no pursuit burst",
		float(mushroom.get("burst_duration")) <= 0.0)
	check_true("HUNTER Bat has a short faster burst",
		float(bat.get("burst_speed")) > float(bat.get("chase_speed"))
		and float(bat.get("burst_duration")) > 0.0
		and float(bat.get("burst_duration")) <= 0.6)
	check_true("HUNTER Bat pays at least two seconds of burst recovery",
		float(bat.get("burst_recovery")) >= 2.0)

	wilds.free()
	mountain.free()


func _check_active_region_speed_bands() -> void:
	var checked := 0
	for scene_path in ACTIVE_REGION_SCENES:
		var scene: Node = load(scene_path).instantiate()
		for enemy in _enemy_nodes(scene):
			checked += 1
			var label := "%s/%s" % [scene_path.get_file(), String(enemy.name)]
			var aggro_level := int(enemy.get("aggro_level"))
			var roam_speed := float(enemy.get("roam_speed"))
			var chase_speed := float(enemy.get("chase_speed"))
			var burst_speed := float(enemy.get("burst_speed"))
			var burst_duration := float(enemy.get("burst_duration"))
			check_true("%s uses an authored behavior profile" % label,
				not bool(enemy.get("uses_fallback_behavior")))
			check_true("%s roam speed stays in 18-36 px/s" % label,
				roam_speed >= 18.0 and roam_speed <= 36.0)
			if aggro_level == 0: # PASSIVE never enters CHASE, so zero is intentional.
				check_eq("%s passive profile has no chase speed" % label,
					chase_speed, 0.0)
			else:
				check_true("%s chase speed stays in 48-68 px/s" % label,
					chase_speed >= 48.0 and chase_speed <= 68.0)
			check_true("%s never sustains the player's 80 px/s band" % label,
				not _forbidden_sustained_speed(roam_speed)
				and not _forbidden_sustained_speed(chase_speed))
			if burst_duration > 0.0:
				check_true("%s burst is faster, outside 76-84, and <=0.6s" % label,
					burst_speed > chase_speed
					and not _forbidden_sustained_speed(burst_speed)
					and burst_duration <= 0.6)
		scene.free()
	check_true("speed audit covers the placed enemy roster (%d)" % checked,
		checked >= 20)

	var village: Node = load("res://src/scenes/world.tscn").instantiate()
	var spar_zone := village.get_node_or_null("Props/Slime1/SparZone")
	check_true("starter sparring partner exposes its interaction zone", spar_zone != null)
	if spar_zone != null:
		check_eq("starter interaction prompt says Spar",
			String(spar_zone.call("interaction_label")), "Spar")
	# A spar must be a RECALL fight, not a shoving match. It used to set a flag and then let
	# the player win by walking into the partner until its HP hit zero -- the one route in the
	# game where a fight was won with no card, no recall and no Japanese.
	var slime: Node = village.get_node_or_null("Props/Slime1")
	if slime != null:
		check_true("the starter partner is a sparring partner",
			bool(slime.get("sparring_partner")))
		# Set HP explicitly: this scene is never added to the tree, so _ready has not run and
		# hp would otherwise be 0, making the assertion below pass for the wrong reason.
		slime.set("hp", 12)
		slime.call("take_damage", 9999)
		check_true("contact damage cannot beat a sparring partner (hp 12 -> %d)"
			% int(slime.get("hp")),
			int(slime.get("hp")) == 12 and is_instance_valid(slime))
	village.free()


func _advance(enemy: Node, delta: float, player_position: Vector2,
		has_line_of_sight: bool) -> void:
	enemy.call("advance_world_state", delta, player_position, has_line_of_sight)


func _state(enemy: Node) -> int:
	return int(enemy.get("world_state"))


func _enum_values(node: Node, enum_name: String) -> Dictionary:
	var script := node.get_script() as Script
	if script == null:
		return {}
	return script.get_script_constant_map().get(enum_name, {})


func _find_enemy(node: Node, enemy_id: String) -> Node:
	if _has_property(node, "enemy_id") and String(node.get("enemy_id")) == enemy_id:
		return node
	for child in node.get_children():
		var found := _find_enemy(child, enemy_id)
		if found != null:
			return found
	return null


func _enemy_nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if _has_property(node, "enemy_id") and node.has_method("take_damage"):
		found.append(node)
	for child in node.get_children():
		found.append_array(_enemy_nodes(child))
	return found


func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false


func _forbidden_sustained_speed(speed: float) -> bool:
	return speed >= 76.0 and speed <= 84.0


func _finish() -> void:
	print("")
	print("PASS - enemy world states are readable, escapable, and distinct."
		if failures == 0 else "FAIL - %d enemy world-state check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
