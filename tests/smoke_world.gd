extends SceneTree
## Slice 1/3 smoke test: the harness scene loads, the player animates, moves under
## real input, is stopped by the boundary walls, and the recall gate is present
## and starts closed.
##
##   godot --headless --path . --script res://tests/smoke_world.gd
##
## Physics runs headless, so collision is genuinely exercised here rather than
## assumed. Rendering is not, so this says nothing about how it *looks* — that is
## a hand-test. The harness is deliberately minimal (no level design); this checks
## the plumbing, not a designed map.

const TILE := 16
const MAP_W := 32
const MAP_H := 22

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: Node2D = load("res://src/scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame

	# --- structure ---
	var player: CharacterBody2D = world.get_node_or_null("Player")
	var ground: TileMapLayer = world.get_node_or_null("Ground")
	var gate: Node = world.get_node_or_null("Props/LessonGate")
	check_true("harness has a Player", player != null)
	check_true("harness has a Ground layer", ground != null)
	check_true("harness has a recall gate", gate != null)

	if player == null or ground == null or gate == null:
		_finish()
		return

	check_true("ground is fully tiled (%d cells)" % ground.get_used_cells().size(),
		ground.get_used_cells().size() == MAP_W * MAP_H)

	# --- the gate starts closed ---
	var barrier: CollisionShape2D = gate.get_node("Barrier/Collision")
	check_true("gate barrier starts active", not barrier.disabled)

	# --- camera is clamped to the map ---
	var camera: Camera2D = player.get_node("Camera")
	check_true("camera limits match the map",
		camera.limit_right == MAP_W * TILE and camera.limit_bottom == MAP_H * TILE)

	# --- the sheet actually became animations ---
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	var frames := sprite.sprite_frames
	check_true("sprite_frames built from the walk sheet", frames != null)
	if frames != null:
		for dir in ["down", "up", "left", "right"]:
			check_true("walk_%s has 4 frames" % dir, frames.get_frame_count("walk_" + dir) == 4)
			check_true("idle_%s exists" % dir, frames.has_animation("idle_" + dir))
		check_true("starts idle facing down", sprite.animation == "idle_down")

	# --- movement under real input ---
	player.position = Vector2(16 * TILE, 13 * TILE)
	var start := player.position
	Input.action_press("move_right")
	await _physics_frames(20)
	Input.action_release("move_right")
	var moved := player.position.x - start.x
	check_true("walking right moved the player (%.1f px)" % moved, moved > 10.0)
	check_true("facing resolved to right", player.facing == "right")
	check_true("plays walk_right while moving", sprite.animation == "walk_right")

	await _physics_frames(2)
	check_true("returns to idle_right when input stops", sprite.animation == "idle_right")

	# --- diagonals must not be faster than a straight line ---
	player.position = Vector2(16 * TILE, 13 * TILE)
	start = player.position
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _physics_frames(20)
	Input.action_release("move_right")
	Input.action_release("move_down")
	var diagonal := player.position.distance_to(start)
	check_true("diagonal speed matches straight-line (%.1f vs %.1f)" % [diagonal, moved],
		absf(diagonal - moved) < 2.0)

	# --- boundary walls actually stop the player ---
	player.position = Vector2(2 * TILE, 13 * TILE)
	Input.action_press("move_left")
	await _physics_frames(60)
	Input.action_release("move_left")
	# The feet box is 8px wide, so the centre stops ~4px shy of the wall face at x=0.
	check_true("west wall stops the player (x=%.1f, expected ~4)" % player.position.x,
		absf(player.position.x - 4.0) < 0.5)

	_finish()


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _finish() -> void:
	print("")
	print(("PASS — harness loads, player moves, walls hold, gate present."
		if failures == 0 else "FAIL — %d check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
