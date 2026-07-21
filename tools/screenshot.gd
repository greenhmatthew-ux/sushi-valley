extends SceneTree
## Dev helper: boot a scene, let it settle, and write a PNG of the viewport.
##
##   godot --path . --script res://tools/screenshot.gd -- <res://scene.tscn> <out.png> [zoom]
##
## Needs a real window (do NOT pass --headless) because it reads the rendered
## framebuffer. Defaults to the main scene and user://screenshot.png. Passing a
## zoom below 1 pulls the camera back to survey a whole level.

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://src/scenes/world.tscn"
	var out_path: String = args[1] if args.size() > 1 else "user://screenshot.png"
	var zoom: float = float(args[2]) if args.size() > 2 else 0.0

	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)

	# Optional 4th/5th args: place the player at cell (cx,cy) to frame a spot.
	if args.size() > 4:
		var player := scene.get_node_or_null("Player")
		if player != null:
			player.position = Vector2(float(args[3]) * 16.0, float(args[4]) * 16.0)

	if zoom > 0.0:
		var camera: Camera2D = scene.get_node_or_null("Player/Camera")
		if camera != null:
			camera.zoom = Vector2(zoom, zoom)
			# Limits would clamp a pulled-back camera back into the map.
			camera.limit_left = -100000
			camera.limit_top = -100000
			camera.limit_right = 100000
			camera.limit_bottom = 100000

	# Let physics settle and animations reach a real frame before capturing.
	for i in 20:
		await process_frame

	var image := root.get_texture().get_image()
	var err := image.save_png(out_path)
	if err != OK:
		push_error("screenshot failed: %d" % err)
		quit(1)
		return
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit(0)
