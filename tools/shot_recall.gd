extends SceneTree
## Dev helper: boot the harness, open a recall session, and screenshot the panel.
##
##   godot --path . --script res://tools/shot_recall.gd -- <out.png>
##
## Needs a real window (no --headless). Fetches Bus/Learning by node because a
## --script file compiles before autoload name-globals are registered.

func _initialize() -> void:
	_run()


func _run() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() \
		else "user://recall.png"
	var world: Node = load("res://src/scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame

	# The bootstrap unlocks kana-vowels on _ready; open a focused session on it.
	var bus := root.get_node("Bus")
	bus.learn_open.emit("kana-vowels", 5, true)
	for i in 10:
		await process_frame

	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s" % out_path)
	quit(0)
