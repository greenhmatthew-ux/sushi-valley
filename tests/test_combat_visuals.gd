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

	# The foe used to hold one frozen frame for the whole fight, which is most of why combat
	# did not read as a fight. Drive the panel's own _process rather than waiting on frames:
	# combat pauses the tree, and this asserts the animation survives that (the panel is
	# PROCESS_MODE_ALWAYS, and losing that would silently freeze the foe again).
	var atlas := portrait.texture as AtlasTexture
	if int(panel.get("_portrait_rows")) > 1:
		var first_row: float = atlas.region.position.y
		var moved := false
		for i in 30:
			panel.call("_process", 0.1)
			if atlas.region.position.y != first_row:
				moved = true
				break
		check_true("the foe animates instead of holding one frame", moved)
		check_true("its frames stay inside the sheet",
			atlas.region.position.y >= 0
			and atlas.region.end.y <= atlas.atlas.get_height())
		# Striking must visibly change its cadence, not just the HP number.
		panel.call("_strike_portrait")
		check_true("striking kicks the foe into its fast cadence",
			float(panel.get("_strike_left")) > 0.0)
	else:
		check_true("mushroom's sheet has walk rows to animate", false)

	# --- every ability resolves with a visual, or deliberately with none ---
	#
	# All 68 used to resolve identically: a number moved. The effect is derived from the
	# ability's own style/type/hits rather than a per-ability table, so this walks the whole
	# roster -- a 69th ability added tomorrow is covered by construction, and one that maps to
	# a sheet that does not exist fails here rather than throwing mid-fight.
	var fx := load("res://src/ui/combat_fx.gd")
	var offensive_without_effect: Array[String] = []
	var defensive_with_effect: Array[String] = []
	var unknown_sheet: Array[String] = []
	for id in db.abilities:
		var ability: Dictionary = db.abilities[id]
		var effect := String(fx.effect_for(ability))
		var kind := String(ability.get("type", "attack"))
		if not effect.is_empty() and not fx.SHEETS.has(effect):
			unknown_sheet.append(String(id))
		if kind in ["block", "parry", "buff", "heal"]:
			if not effect.is_empty():
				defensive_with_effect.append(String(id))
		elif effect.is_empty():
			offensive_without_effect.append(String(id))
	check_true("every ability maps to a sheet that exists (%d abilities)" % db.abilities.size(),
		unknown_sheet.is_empty())
	check_true("every offensive ability throws something (%s)"
		% ", ".join(PackedStringArray(offensive_without_effect)),
		offensive_without_effect.is_empty())
	# A block that threw a sword arc would read as an attack.
	check_true("no block/parry/buff/heal throws a slash (%s)"
		% ", ".join(PackedStringArray(defensive_with_effect)),
		defensive_with_effect.is_empty())

	# A flurry must not look like a single blow.
	check_true("hit count changes the blade effect",
		fx.effect_for({"style": "blade", "type": "attack", "hits": 1})
		!= fx.effect_for({"style": "blade", "type": "attack", "hits": 3}))

	# The effect must live on the overlay, not in the laid-out round, and must clean itself up.
	var overlay_children := hit_layer.get_child_count()
	fx.play(hit_layer, portrait, "cut", Color.WHITE)
	check_true("an effect is parented to the hit overlay",
		hit_layer.get_child_count() == overlay_children + 1)

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

	# The wind-up. "It hits you this turn" was only ever a small line in the panel corner,
	# so the dangerous turn looked exactly like a safe one. The foe shows it now.
	var encounter: CombatEncounter = panel.get("_encounter")
	encounter.turns_left = 3
	panel.call("_render_enemy_intent")
	check_true("a foe that is not about to swing stays still",
		panel.get("_telegraph") == null)
	encounter.turns_left = 1
	panel.call("_render_enemy_intent")
	var telegraph: Tween = panel.get("_telegraph")
	check_true("a foe about to swing winds up", telegraph != null and telegraph.is_valid())
	# It must pulse self_modulate, not modulate: hits tween modulate, and a looping tween on
	# the same property would fight every strike and strand the portrait mid-colour.
	panel.call("_show_hit", portrait, 5, Color.RED)
	await process_frame
	check_true("the wind-up survives being hit mid-pulse",
		panel.get("_telegraph") != null and (panel.get("_telegraph") as Tween).is_valid())
	panel.call("_set_telegraph", false)
	check_true("the wind-up stops cleanly and restores the portrait",
		panel.get("_telegraph") == null and portrait.self_modulate == Color.WHITE)

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
