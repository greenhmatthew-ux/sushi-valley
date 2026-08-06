extends SceneTree
## Dev helper: open a real fight, fire an attack effect, and photograph it.
##
##   godot --path . --script res://tools/shot_combat.gd -- <out.png> [effect]
##
## Needs a real window (no --headless) because it reads the framebuffer. Combat pauses the
## tree, so the panel's PROCESS_MODE_ALWAYS is what keeps the effect tween running here.

const FX = preload("res://src/ui/combat_fx.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://combat.png"
	var effect: String = args[1] if args.size() > 1 else "cut"

	await process_frame
	var director: Node = root.get_node("EncounterDirector")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame

	director.request("mushroom")
	for i in 6:
		await process_frame

	var portrait: TextureRect = panel.find_child("CombatEnemyPortrait", true, false)
	var hit_layer: Control = panel.find_child("HitLayer", true, false)
	FX.play(hit_layer, portrait, effect, Color.WHITE)
	panel.call("_show_hit", portrait, 24, Color(0.9, 0.3, 0.3))

	# Land mid-animation rather than after it: a 4-frame effect at 22fps is gone in 0.18s.
	for i in 3:
		await process_frame

	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (effect=%s)" % [out_path, effect])
	quit(0)
