extends SceneTree
## Slice 1 smoke test: the world scene loads, the player animates, moves under
## real input, and is actually stopped by collision.
##
##   godot --headless --path . --script res://tests/smoke_world.gd
##
## Physics runs headless, so collision is genuinely exercised here rather than
## assumed. Rendering is not, so this says nothing about how it *looks* — that is
## a hand-test.

const TILE := 16
const MAP_W := 40
const MAP_H := 30

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: Node2D = load("res://src/scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame

	# --- structure ---
	var player: CharacterBody2D = world.get_node_or_null("Player")
	check_true("world has a Player", player != null)
	var ground: TileMapLayer = world.get_node_or_null("Ground")
	var water: TileMapLayer = world.get_node_or_null("Water")
	check_true("world has Ground and Water layers", ground != null and water != null)
	check_true("Props holds 10 trees", world.get_node("Props").get_child_count() == 10)

	if player == null or ground == null or water == null:
		_finish()
		return

	check_true("ground is fully tiled (%d cells)" % ground.get_used_cells().size(),
		ground.get_used_cells().size() == MAP_W * MAP_H)
	check_true("pond has water tiles", water.get_used_cells().size() > 30)

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

	# --- water is solid ---
	var tile_set := water.tile_set
	check_true("tileset declares a physics layer", tile_set.get_physics_layers_count() == 1)
	var water_cell: Vector2i = water.get_used_cells()[0]
	var data := water.get_cell_tile_data(water_cell)
	check_true("water tiles carry a collision polygon",
		data != null and data.get_collision_polygons_count(0) == 1)

	# --- movement under real input ---
	player.position = Vector2(20 * TILE, 16 * TILE)
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
	player.position = Vector2(20 * TILE, 16 * TILE)
	start = player.position
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _physics_frames(20)
	Input.action_release("move_right")
	Input.action_release("move_down")
	var diagonal := player.position.distance_to(start)
	check_true("diagonal speed matches straight-line (%.1f vs %.1f)" % [diagonal, moved],
		absf(diagonal - moved) < 2.0)

	# --- collision actually stops the player ---
	player.position = Vector2(2 * TILE, 16 * TILE)
	Input.action_press("move_left")
	await _physics_frames(60)
	Input.action_release("move_left")
	# The feet box is 8px wide, so the centre stops 4px shy of the wall face at x=0.
	check_true("west wall stops the player (x=%.1f, expected ~4)" % player.position.x,
		absf(player.position.x - 4.0) < 0.5)

	# Walk into the pond from the south; the water tiles must block.
	player.position = Vector2(31 * TILE, 12 * TILE)
	Input.action_press("move_up")
	await _physics_frames(60)
	Input.action_release("move_up")
	check_true("pond blocks the player (y=%.1f, water ends at y=160)" % player.position.y,
		player.position.y > 160.0)

	_finish()


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _finish() -> void:
	print("")
	if failures == 0:
		print("PASS — world loads, player moves, collision holds.")
	else:
		print("FAIL — %d check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
