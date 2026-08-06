extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: Node2D = load("res://src/scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var ground: TileMapLayer = world.get_node("Ground")
	print("ground.position = %s" % ground.position)
	var water := 0
	var coords := {}
	for cell in ground.get_used_cells():
		var c := ground.get_cell_atlas_coords(cell)
		if c.x >= 11 and c.x <= 14 and c.y <= 2:
			water += 1
			coords[c] = int(coords.get(c, 0)) + 1
	print("water-ish cells: %d  %s" % [water, coords])
	var r := world.get_node_or_null("PondRipples")
	if r == null:
		print("no PondRipples")
		quit(0)
		return
	print("ripples: %d  visible=%s modulate=%s" % [r.get_child_count(), r.visible, r.modulate])
	for i in mini(r.get_child_count(), 5):
		var s := r.get_child(i) as Sprite2D
		var at := s.texture as AtlasTexture
		print("   %d pos=%s global=%s region=%s atlas=%s vis=%s"
			% [i, s.position, s.global_position, at.region,
			at.atlas.get_size() if at.atlas != null else "null", s.visible])
	quit(0)
