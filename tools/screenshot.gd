extends SceneTree
## Dev helper: boot a scene, let it settle, and write a PNG of the viewport.
##
##   godot --path . --script res://tools/screenshot.gd -- <res://scene.tscn> <out.png> [zoom] [cx] [cy]
##
## Needs a real window (do NOT pass --headless) because it reads the rendered
## framebuffer. Defaults to the main scene and user://screenshot.png. Passing a
## zoom below 1 pulls the camera back to survey a whole level, and a tile
## coordinate frames a particular spot.
##
## The scene is swapped in with `change_scene_to_file` rather than instantiated
## alongside: Godot boots the project's main scene next to a --script MainLoop,
## and it does so *after* _initialize, so simply adding another scene left the
## village on screen with its player camera current — every "screenshot" of a
## different region silently came back as the village.
##
## Node paths are resolved by group rather than by a fixed "Props/Player" path,
## which only ever matched the village.

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://src/scenes/world.tscn"
	var out_path: String = args[1] if args.size() > 1 else "user://screenshot.png"
	var zoom: float = float(args[2]) if args.size() > 2 else 0.0

	# Let the boot settle first, so the main scene it loads is the one we replace.
	for i in 5:
		await process_frame
	var err := change_scene_to_file(scene_path)
	if err != OK:
		push_error("could not load %s (err %d)" % [scene_path, err])
		quit(1)
		return
	for i in 30:
		await process_frame

	for node in get_nodes_in_group("player"):
		var player := node as Node2D
		if args.size() > 4:
			player.global_position = Vector2(float(args[3]) * 16.0, float(args[4]) * 16.0)
		# The player's camera node is named "Camera", not "Camera2D" — looking only for
		# the latter silently ignored every zoom argument ever passed to this tool.
		var camera := player.get_node_or_null("Camera") as Camera2D
		if camera == null:
			camera = player.get_node_or_null("Camera2D") as Camera2D
		if camera == null:
			continue
		# Position smoothing was still gliding toward the teleported player when the
		# frame was grabbed, so a framed spot came out tens of pixels off — enough to
		# push the thing being inspected out of shot.
		camera.reset_smoothing()
		if zoom <= 0.0:
			continue
		camera.zoom = Vector2(zoom, zoom)
		# Limits would clamp a pulled-back camera back into the map.
		camera.limit_left = -100000
		camera.limit_top = -100000
		camera.limit_right = 100000
		camera.limit_bottom = 100000

	# The daily briefing opens over the middle of the screen on load, so every framed
	# capture of the village came back with the thing being inspected behind a panel.
	# Dismiss it the same way the player would rather than hiding the whole UI layer,
	# which would also take the HUD a screenshot is often meant to show.
	for node in root.find_children("*", "CanvasLayer", true, false):
		if node.has_method("_close") and node.get_script() != null \
				and String(node.get_script().resource_path).ends_with("welcome_back_panel.gd"):
			node.call("_close")
	await process_frame

	# Let physics settle and animations reach a real frame before capturing.
	for i in 25:
		await process_frame

	var image := root.get_texture().get_image()
	var save_err := image.save_png(out_path)
	if save_err != OK:
		push_error("screenshot failed: %d" % save_err)
		quit(1)
		return
	print("wrote %s (%dx%d) from %s" % [
		out_path, image.get_width(), image.get_height(),
		current_scene.name if current_scene != null else "?"])
	quit(0)
