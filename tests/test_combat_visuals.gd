extends SceneTree
## Combat shows the thing you are fighting, and a hit looks like one.
##
##   godot --headless --path . --script res://tests/test_combat_visuals.gd
##
## Combat shipped with no art and no motion anywhere in the panel — no texture, no sprite,
## no tween. A fight was a name, two bars and a line of prose, so a killing blow and a
## scratch were indistinguishable: the bar moved, the text changed, nothing else happened.
##
## These are the pieces that fixed that, and each one is easy to lose silently. The portrait
## resolves through `spriteAlias`, which most of the 76-strong roster does not have — a
## regression there shows an empty box rather than throwing. The hit layer must stay a
## sibling overlay, because floating numbers parented into the round would reflow it.

var failures := 0


func _initialize() -> void:
	await process_frame
	var db: Node = root.get_node("DB")
	var director: Node = root.get_node("EncounterDirector")
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/combat_panel.gd"))
	root.add_child(panel)
	await process_frame

	var portrait: TextureRect = panel.find_child("CombatEnemyPortrait", true, false)
	var hit_layer: Control = panel.find_child("HitLayer", true, false)
	check_true("combat builds an enemy portrait", portrait != null)
	check_true("combat builds a hit overlay", hit_layer != null)
	check_true("the hit overlay never blocks input",
		hit_layer != null and hit_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check_true("floating numbers cannot reflow the round",
		hit_layer != null and not (hit_layer.get_parent() is BoxContainer))

	# An enemy the project actually ships art for.
	check_true("encounter opens", not String(director.request("mushroom")).is_empty())
	await process_frame
	check_true("the foe you are fighting is on screen",
		portrait.visible and portrait.texture != null)
	check_true("the portrait is a single sheet frame, not the whole walk sheet",
		portrait.texture is AtlasTexture
		and (portrait.texture as AtlasTexture).region.size == Vector2(16, 16))
	check_true("the portrait is drawn at native scale, unsmoothed",
		portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)

	# A hit must not move a container child: the panel's bars and portrait are laid out by
	# their container, so a position tween fought the layout and parked the player's HP bar
	# at the top of the panel. Scale is the one transform a container does not own.
	var hp_bar: ProgressBar = panel.get("_player_hp_bar")
	var before: Vector2 = hp_bar.position
	panel.call("_show_hit", hp_bar, 7, Color.RED)
	await process_frame
	await process_frame
	check_true("a hit leaves the struck bar where its container put it",
		hp_bar.position.is_equal_approx(before))

	# Enemies with no art must degrade to no portrait rather than an empty box.
	var artless := ""
	for enemy_id in db.enemy_order:
		var enemy: Dictionary = db.enemy(String(enemy_id))
		var sprite := String(enemy.get("spriteAlias", enemy.get("sprite", "")))
		if sprite.is_empty() or not ResourceLoader.exists("res://assets/sprites/%s.png" % sprite):
			artless = String(enemy_id)
			break
	if artless.is_empty():
		check_true("every enemy has portrait art (nothing to degrade)", true)
	else:
		panel.call("_set_enemy_portrait", artless)
		check_true("an enemy with no art shows no portrait rather than an empty box (%s)"
			% artless, not portrait.visible and portrait.texture == null)

	_finish()


func _finish() -> void:
	print("")
	print(("PASS — combat shows its enemy and its hits."
		if failures == 0 else "FAIL — %d combat-visual check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
