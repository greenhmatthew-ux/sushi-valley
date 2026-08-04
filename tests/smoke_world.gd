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
const MAP_W := 44
const MAP_H := 30

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: Node2D = load("res://src/scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame

	# --- structure ---
	var player: CharacterBody2D = world.get_node_or_null("Props/Player")
	var ground: TileMapLayer = world.get_node_or_null("Ground")
	var edge_ground: TileMapLayer = world.get_node_or_null("EdgeGround")
	var meadow: TileMapLayer = world.get_node_or_null("Meadow")
	var gate: Node = world.get_node_or_null("Props/LessonGate")
	var farm_plot: Node = world.get_node_or_null("Props/FarmPlot1")
	var starter_seeds: Node = world.get_node_or_null("Props/FarmStarterSeeds")
	var fishing_spot: Node = world.get_node_or_null("Props/VillageFishingSpot")
	var herb_patch: Node = world.get_node_or_null("Props/VillageHerbPatch")
	var weather_overlay: Node = world.get_node_or_null("WeatherOverlay")
	check_true("harness has a Player", player != null)
	check_true("harness has a Ground layer", ground != null)
	check_true("world has a textured edge underlay", edge_ground != null)
	check_true("world has authored meadow detail", meadow != null)
	check_true("harness has a recall gate", gate != null)
	check_true("village has a discoverable farm plot", farm_plot != null)
	check_true("farm has a one-time starter seed cache", starter_seeds != null)
	check_true("pond has one authored fishing destination", fishing_spot != null)
	check_true("village has a renewable herb patch", herb_patch != null)
	check_true("outdoor village shows today's weather", weather_overlay != null)

	if player == null or ground == null or gate == null:
		_finish()
		return

	check_true("ground is fully tiled (%d cells)" % ground.get_used_cells().size(),
		ground.get_used_cells().size() == MAP_W * MAP_H)
	if edge_ground != null:
		check_true("edge underlay covers the full camera footprint",
			edge_ground.get_used_cells().size() == MAP_W * MAP_H)
		check_true("northwest edge uses real Serene Village grass",
			edge_ground.get_cell_atlas_coords(Vector2i.ZERO) == Vector2i(4, 0))
		check_true("edge underlay stays behind authored paths and props",
			edge_ground.z_index < ground.z_index)
	if meadow != null:
		var meadow_source: TileSetAtlasSource = meadow.tile_set.get_source(0)
		check_true("village meadow uses the native Serene Village sheet",
			meadow_source.texture.resource_path ==
			"res://assets/tilesets/serene_village.png")

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

	# --- movement under real input (the central plaza is open dirt, prop-free) ---
	var open := Vector2(19 * TILE, 19 * TILE)
	player.position = open
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
	player.position = open
	start = player.position
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _physics_frames(20)
	Input.action_release("move_right")
	Input.action_release("move_down")
	var diagonal := player.position.distance_to(start)
	check_true("diagonal speed matches straight-line (%.1f vs %.1f)" % [diagonal, moved],
		absf(diagonal - moved) < 2.0)

	# --- the pond blocks: walking up into it from the south is stopped by water ---
	# (33,14) sits under the pond in the right-house keep-zone, so it's tree-free.
	check_true("bounds wall has 4 sides", world.get_node("Bounds").get_child_count() == 4)
	player.position = Vector2(33 * TILE, 14 * TILE)
	Input.action_press("move_up")
	await _physics_frames(70)
	Input.action_release("move_up")
	check_true("pond stops the player short of its interior (y=%.1f)" % player.position.y,
		player.position.y > 150.0)
	var interact_probe: Area2D = player.get_node("InteractProbe")
	check_true("the dry shore reaches the authored fishing destination",
		fishing_spot in interact_probe.get_overlapping_areas())
	player.position = herb_patch.position + Vector2(28, 0)
	await _physics_frames(2)
	check_true("the village herb patch is within the real interaction probe",
		herb_patch in interact_probe.get_overlapping_areas())

	# The connected frontier must use the same real terrain vocabulary, not placeholder decals.
	world.queue_free()
	await process_frame
	var wilds: Node2D = load("res://src/scenes/wilds.tscn").instantiate()
	root.add_child(wilds)
	await process_frame
	var wilds_detail: TileMapLayer = wilds.get_node_or_null("Detail")
	var wilds_copper: Node = wilds.get_node_or_null("Entities/CopperSeam")
	var wilds_bamboo: Node = wilds.get_node_or_null("Entities/BambooThicket")
	check_true("Wilds has a renewable copper seam", wilds_copper != null)
	check_true("Wilds has a renewable bamboo thicket", wilds_bamboo != null)
	var wilds_player: CharacterBody2D = wilds.get_node_or_null("Entities/Player")
	if wilds_player != null and wilds_copper != null:
		wilds_player.position = wilds_copper.position + Vector2(28, 0)
		await _physics_frames(2)
		var wilds_probe: Area2D = wilds_player.get_node("InteractProbe")
		check_true("the Wilds copper seam is within the real interaction probe",
			wilds_copper in wilds_probe.get_overlapping_areas())
	check_true("Wilds has authored meadow detail", wilds_detail != null)
	if wilds_detail != null:
		var wilds_source: TileSetAtlasSource = wilds_detail.tile_set.get_source(1)
		check_true("Wilds meadow uses the native Serene Village sheet",
			wilds_source.texture.resource_path ==
			"res://assets/tilesets/serene_village.png")
	wilds.queue_free()
	await process_frame

	var interior: Node2D = load("res://src/scenes/interior_house.tscn").instantiate()
	root.add_child(interior)
	await process_frame
	var interior_floor: TileMapLayer = interior.get_node_or_null("Floor")
	var interior_bed: Node = interior.get_node_or_null("Entities/Bed")
	var sleep_spot: Node = interior.get_node_or_null("Entities/SleepSpot")
	var door_sprite: Sprite2D = interior.get_node_or_null("FloorDecor/DoorSprite")
	check_true("house interior has a real floor layer", interior_floor != null)
	check_true("house interior has an authored bed", interior_bed != null)
	check_true("house bed advances the saved day", sleep_spot != null)
	check_true("house interior has an authored exit door", door_sprite != null)
	if interior_floor != null:
		var floor_source: TileSetAtlasSource = interior_floor.tile_set.get_source(0)
		check_true("house floor uses the CC0 Ninja interior sheet",
			floor_source.texture.resource_path ==
			"res://assets/tilesets/ninja_interior_floor.png")
	if interior_bed != null:
		var bed_texture: AtlasTexture = interior_bed.get("texture")
		check_true("house bed uses the CC0 Ninja bed sheet",
			bed_texture != null and bed_texture.atlas.resource_path ==
			"res://assets/objects/ninja_beds.png")
	if door_sprite != null:
		var door_texture: AtlasTexture = door_sprite.texture
		check_true("house door uses the CC0 Ninja elements sheet",
			door_texture != null and door_texture.atlas.resource_path ==
			"res://assets/objects/ninja_interior_elements.png")
	var interior_player: CharacterBody2D = interior.get_node_or_null("Entities/Player")
	if interior_player != null:
		interior_player.position = Vector2(104, 108)
		var room_start := interior_player.position
		Input.action_press("move_left")
		await _physics_frames(20)
		Input.action_release("move_left")
		check_true("house entry lane still reaches the Host side",
			interior_player.position.x < room_start.x - 10.0)
		interior_player.position = Vector2(44, 100)
		Input.action_press("move_up")
		await _physics_frames(30)
		Input.action_release("move_up")
		check_true("bed blocks only at its visible base (y=%.1f)" % interior_player.position.y,
			interior_player.position.y > 82.0)
	interior.queue_free()

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
