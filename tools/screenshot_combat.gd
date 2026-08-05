extends SceneTree
## Dev helper: boot the village, open a fight, and write a PNG of the combat panel.
##
##   godot --path . --script res://tools/screenshot_combat.gd -- <enemy_id> <out.png>
##
## Needs a real window (do NOT pass --headless) because it reads the rendered framebuffer,
## same as tools/screenshot.gd. Combat cannot be reached by walking in a screenshot run, so
## the fight is opened through EncounterDirector directly.
##
## Combat pauses the tree; this keeps working because the UI layer is PROCESS_MODE_ALWAYS
## and `process_frame` still fires while paused.

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var enemy_id: String = args[0] if args.size() > 0 else "mushroom"
	var out_path: String = args[1] if args.size() > 1 else "user://combat.png"
	for i in 5:
		await process_frame
	var err := change_scene_to_file("res://src/scenes/world.tscn")
	if err != OK:
		push_error("could not load world (err %d)" % err)
		quit(1)
		return
	for i in 30:
		await process_frame
	# A fresh profile opens the Welcome Back card over everything; dismiss it first or the
	# screenshot is of that panel rather than the fight.
	for layer in root.get_children():
		if String(layer.name).begins_with("WelcomeBack"):
			layer.hide()
		for node in layer.find_children("*", "Control", true, false):
			if String(node.name).begins_with("WelcomeBack"):
				node.hide()
	for i in 5:
		await process_frame
	var director := root.get_node_or_null("EncounterDirector")
	if director == null:
		push_error("no EncounterDirector autoload")
		quit(1)
		return
	director.request(enemy_id)
	# Combat pauses the tree, so step the frames that still run while paused.
	for i in 40:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit(0)
